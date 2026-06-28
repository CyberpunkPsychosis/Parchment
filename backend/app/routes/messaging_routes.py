"""统一会话与消息：私聊 / 群聊 / 搭子都跑这套。
REST 收发 + WebSocket 实时投递。会话历史持久化。"""
import json
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db, SessionLocal
from ..auth import decode_token
from ..models import (User, Companion, Group, Conversation, ConversationMember, Message, Memory)
from ..providers import complete_chat
from ..usage import consume

router = APIRouter(tags=["messaging"])

PALETTE = ["teal", "sage", "tealDark", "ink", "gray"]


def _initials(name: str) -> str:
    name = (name or "").strip() or "用户"
    return name[:2].upper() if name[:1].isascii() else name[:1]


def _tint_for(n: int) -> str:
    return PALETTE[n % len(PALETTE)]


# ---------- 会话/成员 helpers（供其它路由复用） ----------

def member_ids(db: Session, cid: int) -> list[int]:
    return [m.user_id for m in db.query(ConversationMember)
            .filter(ConversationMember.conversation_id == cid,
                    ConversationMember.user_id.isnot(None)).all()]


def is_member(db: Session, cid: int, uid: int) -> bool:
    return db.query(ConversationMember).filter(
        ConversationMember.conversation_id == cid,
        ConversationMember.user_id == uid).first() is not None


def touch(db: Session, conv: Conversation):
    conv.updated_at = datetime.utcnow()
    db.commit()


def ensure_direct(db: Session, a: int, b: int) -> Conversation:
    """取或建两人私聊会话。"""
    rows = db.query(Conversation).filter(Conversation.type == "direct").all()
    for c in rows:
        ids = set(member_ids(db, c.id))
        if ids == {a, b}:
            return c
    c = Conversation(type="direct")
    db.add(c); db.commit(); db.refresh(c)
    db.add(ConversationMember(conversation_id=c.id, user_id=a))
    db.add(ConversationMember(conversation_id=c.id, user_id=b))
    db.commit()
    return c


def ensure_group_conversation(db: Session, group: Group) -> Conversation:
    """取或建某群的群聊会话，并把现有群成员补进会话。"""
    c = db.query(Conversation).filter(
        Conversation.type == "group", Conversation.group_id == group.id).first()
    if not c:
        c = Conversation(type="group", group_id=group.id, title=group.name)
        db.add(c); db.commit(); db.refresh(c)
    # 补成员（群成员表 -> 会话成员表）
    from ..models import GroupMember
    existing = set(member_ids(db, c.id))
    for gm in db.query(GroupMember).filter(GroupMember.group_id == group.id).all():
        if gm.user_id not in existing:
            role = "owner" if gm.user_id == group.owner_id else "member"
            db.add(ConversationMember(conversation_id=c.id, user_id=gm.user_id, role=role))
    db.commit()
    return c


def serialize_message(db: Session, m: Message) -> dict:
    """uid 无关的消息 DTO；客户端用 sender_user_id 判断是否自己发的。"""
    if m.sender_companion_id:
        c = db.query(Companion).filter(Companion.id == m.sender_companion_id).first()
        name = c.name if c else "AI"
        return {"id": m.id, "conversation_id": m.conversation_id, "kind": m.kind,
                "content": m.content, "created_at": m.created_at.isoformat(),
                "sender_user_id": None, "companion_id": m.sender_companion_id,
                "sender_name": name, "sender_avatar": c.avatar if c else "AI",
                "sender_avatar_url": None,
                "sender_tint": c.tint if c else "teal", "is_ai": True}
    u = db.query(User).filter(User.id == m.sender_user_id).first() if m.sender_user_id else None
    name = u.nickname if u else "用户"
    return {"id": m.id, "conversation_id": m.conversation_id, "kind": m.kind,
            "content": m.content, "created_at": m.created_at.isoformat(),
            "sender_user_id": m.sender_user_id, "companion_id": None,
            "sender_name": name, "sender_avatar": _initials(name),
            "sender_avatar_url": u.avatar_url if u else None,
            "sender_tint": _tint_for(m.sender_user_id or 0), "is_ai": False}


def conv_dict(db: Session, conv: Conversation, uid: int) -> dict:
    members = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == conv.id).all()
    human = [m for m in members if m.user_id]
    last = (db.query(Message).filter(Message.conversation_id == conv.id)
            .order_by(Message.created_at.desc()).first())

    avatar_url = None
    if conv.type == "group":
        g = db.query(Group).filter(Group.id == conv.group_id).first() if conv.group_id else None
        if g:  # 社群
            title = g.name; avatar = g.avatar; tint = g.tint
        else:  # 好友群
            title = conv.title or "群聊"; avatar = _initials(title); tint = "teal"
            avatar_url = conv.avatar
    elif conv.type == "companion":
        cm = next((m for m in members if m.companion_id), None)
        c = db.query(Companion).filter(Companion.id == cm.companion_id).first() if cm else None
        title = c.name if c else "AI"; avatar = c.avatar if c else "AI"; tint = c.tint if c else "teal"
    else:  # direct
        other = next((m for m in human if m.user_id != uid), None)
        u = db.query(User).filter(User.id == other.user_id).first() if other else None
        title = u.nickname if u else "对话"; avatar = _initials(title)
        tint = _tint_for(other.user_id if other else 0)
        avatar_url = u.avatar_url if u else None

    # 未读
    me = next((m for m in members if m.user_id == uid), None)
    unread = 0
    if last and last.sender_user_id != uid:
        q = db.query(Message).filter(Message.conversation_id == conv.id,
                                     Message.sender_user_id != uid)
        if me and me.last_read_at:
            q = q.filter(Message.created_at > me.last_read_at)
        unread = q.count()

    if not last:
        preview = ""
    elif last.kind == "text" or last.kind == "system":
        preview = last.content
    elif last.kind in ("image", "sticker", "companion"):
        preview = "[图片]" if last.kind != "companion" else "[搭子名片]"
    elif last.kind == "voice":
        preview = "[语音]"
    else:
        preview = "[文件]"

    return {"id": conv.id, "type": conv.type, "group_id": conv.group_id,
            "title": title, "avatar": avatar, "avatar_url": avatar_url, "tint": tint,
            "is_group": conv.type == "group",
            "member_count": len(human),
            "member_cap": conv.member_cap,
            "announcement": conv.announcement,
            "preview": preview,
            "time": (last.created_at if last else conv.updated_at).isoformat(),
            "unread": unread,
            "pinned": bool(me.pinned) if me else False,
            "muted": bool(me.muted) if me else False}


# ---------- WebSocket 实时投递 ----------

class ConnectionManager:
    def __init__(self):
        self.active: dict[int, set[WebSocket]] = {}

    async def connect(self, uid: int, ws: WebSocket):
        await ws.accept()
        self.active.setdefault(uid, set()).add(ws)

    def disconnect(self, uid: int, ws: WebSocket):
        conns = self.active.get(uid)
        if conns:
            conns.discard(ws)
            if not conns:
                self.active.pop(uid, None)

    async def send_to_users(self, uids: list[int], payload: dict):
        data = json.dumps(payload, ensure_ascii=False)
        for uid in set(uids):
            for ws in list(self.active.get(uid, ())):
                try:
                    await ws.send_text(data)
                except Exception:
                    self.disconnect(uid, ws)


manager = ConnectionManager()


async def broadcast_message(db: Session, conv: Conversation, m: Message):
    info = serialize_message(db, m)
    payload = {"type": "message", "conversation_id": conv.id, "message": info}
    uids = member_ids(db, conv.id)
    await manager.send_to_users(uids, payload)
    # 离线成员推送（未配 APNs 凭证时为 no-op）
    try:
        from ..push import send_push
        offline = [u for u in uids if u != m.sender_user_id and u not in manager.active]
        if offline:
            send_push(db, offline, info["sender_name"], info["content"][:60])
    except Exception:
        pass


@router.websocket("/ws")
async def ws_endpoint(ws: WebSocket, token: str = Query(default="")):
    uid = decode_token(token)
    if uid is None:
        await ws.close(code=4401)
        return
    await manager.connect(uid, ws)
    try:
        while True:
            await ws.receive_text()  # 心跳/忽略；发送走 REST
    except WebSocketDisconnect:
        manager.disconnect(uid, ws)
    except Exception:
        manager.disconnect(uid, ws)


# ---------- REST ----------

@router.get("/conversations")
def list_conversations(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    ids = [m.conversation_id for m in db.query(ConversationMember)
           .filter(ConversationMember.user_id == user.id).all()]
    rows = (db.query(Conversation).filter(Conversation.id.in_(ids))
            .order_by(Conversation.updated_at.desc()).all() if ids else [])
    out = [conv_dict(db, c, user.id) for c in rows]
    # 时间新→旧，再把置顶稳定提前
    out.sort(key=lambda d: d["time"], reverse=True)
    out.sort(key=lambda d: 0 if d.get("pinned") else 1)
    return {"conversations": out}


@router.post("/conversations/{cid}/pin")
def toggle_pin(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    m = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == cid, ConversationMember.user_id == user.id).first()
    if not m:
        raise HTTPException(status_code=403, detail="无权访问")
    m.pinned = not bool(m.pinned); db.commit()
    return {"pinned": bool(m.pinned)}


@router.post("/conversations/{cid}/mute")
def toggle_mute(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    m = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == cid, ConversationMember.user_id == user.id).first()
    if not m:
        raise HTTPException(status_code=403, detail="无权访问")
    m.muted = not bool(m.muted); db.commit()
    return {"muted": bool(m.muted)}


class NewConversation(BaseModel):
    type: str = Field(default="direct")     # direct | group
    peer_user_id: int | None = None
    group_id: int | None = None


@router.post("/conversations")
def create_conversation(body: NewConversation,
                        user: User = Depends(get_current_user),
                        db: Session = Depends(get_db)):
    if body.type == "direct":
        if not body.peer_user_id or body.peer_user_id == user.id:
            raise HTTPException(status_code=400, detail="缺少有效的对端用户")
        if not db.query(User).filter(User.id == body.peer_user_id).first():
            raise HTTPException(status_code=404, detail="用户不存在")
        c = ensure_direct(db, user.id, body.peer_user_id)
        return conv_dict(db, c, user.id)
    if body.type == "group":
        g = db.query(Group).filter(Group.id == body.group_id).first()
        if not g:
            raise HTTPException(status_code=404, detail="群不存在")
        if not is_member(db, ensure_group_conversation(db, g).id, user.id):
            raise HTTPException(status_code=403, detail="未加入该群")
        c = ensure_group_conversation(db, g)
        return conv_dict(db, c, user.id)
    raise HTTPException(status_code=400, detail="不支持的会话类型")


FRIEND_GROUP_CAP_DEFAULT = 500


def _human_count(db: Session, cid: int) -> int:
    return db.query(ConversationMember).filter(
        ConversationMember.conversation_id == cid,
        ConversationMember.user_id.isnot(None)).count()


class NewFriendGroup(BaseModel):
    name: str = Field(default="", max_length=24)
    member_ids: list[int] = []
    member_cap: int | None = Field(default=None, ge=2, le=2000)


@router.post("/conversations/group")
def create_friend_group(body: NewFriendGroup,
                        user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """好友内部群：不挂社群(group_id=None)，直接拉好友进会话。"""
    cap = body.member_cap or FRIEND_GROUP_CAP_DEFAULT
    c = Conversation(type="group", title=body.name.strip() or "群聊", member_cap=cap)
    db.add(c); db.commit(); db.refresh(c)
    db.add(ConversationMember(conversation_id=c.id, user_id=user.id, role="owner"))
    for uid in set(body.member_ids):
        if uid != user.id and db.query(User).filter(User.id == uid).first():
            db.add(ConversationMember(conversation_id=c.id, user_id=uid))
    db.commit()
    return conv_dict(db, c, user.id)


@router.get("/conversations/{cid}/messages")
def list_messages(cid: int, after_id: int = 0, limit: int = 50,
                  user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not is_member(db, cid, user.id):
        raise HTTPException(status_code=403, detail="无权访问")
    q = db.query(Message).filter(Message.conversation_id == cid)
    if after_id:
        q = q.filter(Message.id > after_id)
    rows = q.order_by(Message.created_at.asc()).limit(limit).all()
    return {"messages": [serialize_message(db, m) for m in rows]}


class NewMessage(BaseModel):
    kind: str = Field(default="text")
    content: str = Field(default="")


@router.post("/conversations/{cid}/messages")
async def post_message(cid: int, body: NewMessage,
                       user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv or not is_member(db, cid, user.id):
        raise HTTPException(status_code=403, detail="无权访问")
    m = Message(conversation_id=cid, sender_user_id=user.id,
                kind=body.kind, content=body.content)
    db.add(m); db.commit(); db.refresh(m)
    touch(db, conv)
    await broadcast_message(db, conv, m)
    return serialize_message(db, m)


@router.get("/conversations/{cid}/members")
def conversation_members(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not is_member(db, cid, user.id):
        raise HTTPException(status_code=403, detail="无权访问")
    rows = db.query(ConversationMember).filter(ConversationMember.conversation_id == cid).all()
    out = []
    for m in rows:
        if m.companion_id:
            c = db.query(Companion).filter(Companion.id == m.companion_id).first()
            if c:
                out.append({"is_ai": True, "companion_id": c.id, "name": c.name,
                            "initials": c.avatar, "tint": c.tint})
        elif m.user_id:
            u = db.query(User).filter(User.id == m.user_id).first()
            name = u.nickname if u else "用户"
            out.append({"is_ai": False, "user_id": m.user_id, "name": name, "role": m.role,
                        "initials": _initials(name), "tint": _tint_for(m.user_id),
                        "avatar_url": u.avatar_url if u else None})
    return {"members": out}


class AddMemberIn(BaseModel):
    user_id: int | None = None
    companion_id: int | None = None


@router.post("/conversations/{cid}/members")
def add_member(cid: int, body: AddMemberIn,
               user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv or not is_member(db, cid, user.id):
        raise HTTPException(status_code=403, detail="无权访问")
    if body.companion_id:
        c = db.query(Companion).filter(Companion.id == body.companion_id, Companion.owner_id == user.id).first()
        if not c:
            raise HTTPException(status_code=404, detail="搭子不存在或非本人")
        if not db.query(ConversationMember).filter(
                ConversationMember.conversation_id == cid,
                ConversationMember.companion_id == c.id).first():
            db.add(ConversationMember(conversation_id=cid, companion_id=c.id))
            db.commit()
    elif body.user_id:
        if conv.type != "group":
            raise HTTPException(status_code=400, detail="仅群聊可加人")
        if not is_member(db, cid, body.user_id):
            cap = conv.member_cap or FRIEND_GROUP_CAP_DEFAULT
            if _human_count(db, cid) >= cap:
                raise HTTPException(status_code=409, detail="群成员已满")
            db.add(ConversationMember(conversation_id=cid, user_id=body.user_id))
            db.commit()
    return conv_dict(db, conv, user.id)


def _companion_system(db: Session, comp: Companion) -> str:
    """搭子 persona + 注入记忆（与 chat_routes 一致的精简版）。"""
    mems = (db.query(Memory).filter(Memory.companion_id == comp.id)
            .order_by(Memory.created_at.desc()).limit(40).all())
    system = comp.persona
    own = [m for m in mems if not m.origin]
    inherited = [m for m in mems if m.origin]
    if inherited:
        lines = "\n".join(f"- {m.origin}：{m.content}" for m in inherited)
        system += "\n\n[以前主人留下的回忆，属于他们本人，聊到相关话题可自然替他们提起]\n" + lines
    if own:
        lines = "\n".join(f"- {m.content}" for m in own)
        system += "\n\n[关于现在和你聊天的人，你记得这些，自然运用]\n" + lines
    return system


class AIReplyIn(BaseModel):
    companion_id: int


@router.post("/conversations/{cid}/ai-reply")
async def ai_reply(cid: int, body: AIReplyIn,
                   user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv or not is_member(db, cid, user.id):
        raise HTTPException(status_code=403, detail="无权访问")
    comp = db.query(Companion).filter(Companion.id == body.companion_id).first()
    if not comp:
        raise HTTPException(status_code=404, detail="搭子不存在")
    # 搭子须为会话成员（本人可临时加入）
    if not db.query(ConversationMember).filter(
            ConversationMember.conversation_id == cid,
            ConversationMember.companion_id == comp.id).first():
        if comp.owner_id != user.id:
            raise HTTPException(status_code=403, detail="搭子不在群里")
        db.add(ConversationMember(conversation_id=cid, companion_id=comp.id)); db.commit()

    consume(db, user)  # 超额抛 429
    tier = "pro" if user.is_pro else "free"
    rows = (db.query(Message).filter(Message.conversation_id == cid)
            .order_by(Message.created_at.desc()).limit(20).all())[::-1]
    msgs = []
    for m in rows:
        if m.sender_companion_id == comp.id:
            msgs.append({"role": "assistant", "content": m.content})
        elif m.kind == "text":
            who = serialize_message(db, m)["sender_name"]
            msgs.append({"role": "user", "content": f"{who}：{m.content}"})
    reply = await complete_chat(tier, msgs or [{"role": "user", "content": "（群里还没消息，请打个招呼）"}],
                                system=_companion_system(db, comp))
    out = Message(conversation_id=cid, sender_companion_id=comp.id, kind="text", content=reply.strip())
    db.add(out); db.commit(); db.refresh(out)
    touch(db, conv)
    await broadcast_message(db, conv, out)
    return serialize_message(db, out)


class ShareCompanionIn(BaseModel):
    companion_id: int


@router.post("/conversations/{cid}/share-companion")
async def share_companion(cid: int, body: ShareCompanionIn,
                          user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv or not is_member(db, cid, user.id):
        raise HTTPException(status_code=403, detail="无权访问")
    c = db.query(Companion).filter(Companion.id == body.companion_id).first()
    if not c:
        raise HTTPException(status_code=404, detail="搭子不存在")
    card = json.dumps({"companion_id": c.id, "name": c.name, "avatar": c.avatar,
                       "tint": c.tint, "persona": c.persona, "owner_id": c.owner_id},
                      ensure_ascii=False)
    m = Message(conversation_id=cid, sender_user_id=user.id, kind="companion", content=card)
    db.add(m); db.commit(); db.refresh(m)
    touch(db, conv)
    await broadcast_message(db, conv, m)
    return serialize_message(db, m)


def _my_role(db: Session, cid: int, uid: int) -> str | None:
    m = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == cid, ConversationMember.user_id == uid).first()
    return m.role if m else None


@router.post("/conversations/{cid}/leave")
def leave_conversation(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    m = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == cid, ConversationMember.user_id == user.id).first()
    if m:
        db.delete(m); db.commit()
    return {"ok": True}


class RemoveMemberIn(BaseModel):
    user_id: int | None = None
    companion_id: int | None = None


@router.post("/conversations/{cid}/remove-member")
def remove_member(cid: int, body: RemoveMemberIn,
                  user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if _my_role(db, cid, user.id) != "owner":
        raise HTTPException(status_code=403, detail="仅群主可移除成员")
    q = db.query(ConversationMember).filter(ConversationMember.conversation_id == cid)
    if body.companion_id:
        row = q.filter(ConversationMember.companion_id == body.companion_id).first()
    elif body.user_id and body.user_id != user.id:
        row = q.filter(ConversationMember.user_id == body.user_id).first()
    else:
        row = None
    if row:
        db.delete(row); db.commit()
    return {"ok": True}


@router.post("/conversations/{cid}/read")
def mark_read(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    me = db.query(ConversationMember).filter(
        ConversationMember.conversation_id == cid,
        ConversationMember.user_id == user.id).first()
    if not me:
        raise HTTPException(status_code=403, detail="无权访问")
    me.last_read_at = datetime.utcnow()
    db.commit()
    return {"ok": True}
