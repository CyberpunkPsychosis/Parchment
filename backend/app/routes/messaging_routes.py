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
from ..models import (User, Companion, Group, Conversation, ConversationMember, Message, Memory,
                      MessageReaction, CompanionAffinity, CompanionMilestone, CompanionDiary)
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


def ensure_companion_conversation(db: Session, user: User, comp: Companion) -> Conversation:
    """取或建某用户与某搭子的 1:1 持久化会话（type=companion）。新建时落开场白。"""
    rows = (db.query(Conversation)
            .filter(Conversation.type == "companion").all())
    for c in rows:
        mems = db.query(ConversationMember).filter(ConversationMember.conversation_id == c.id).all()
        uids = {m.user_id for m in mems if m.user_id}
        cids = {m.companion_id for m in mems if m.companion_id}
        if uids == {user.id} and cids == {comp.id}:
            return c
    c = Conversation(type="companion", title=comp.name)
    db.add(c); db.commit(); db.refresh(c)
    db.add(ConversationMember(conversation_id=c.id, user_id=user.id, role="owner"))
    db.add(ConversationMember(conversation_id=c.id, companion_id=comp.id))
    db.commit()
    # 开场白（持久化，重进可见）
    if (comp.greeting or "").strip():
        db.add(Message(conversation_id=c.id, sender_companion_id=comp.id,
                       kind="text", content=comp.greeting.strip()))
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


def _reactions(db: Session, mid: int) -> list[dict]:
    rows = db.query(MessageReaction).filter(MessageReaction.message_id == mid).all()
    counts: dict[str, int] = {}
    for r in rows:
        counts[r.emoji] = counts.get(r.emoji, 0) + 1
    return [{"emoji": e, "count": n} for e, n in counts.items()]


def _reply_summary(db: Session, reply_to_id: int | None) -> dict | None:
    """被引用消息的精简摘要（发送者 + 一句内容）。"""
    if not reply_to_id:
        return None
    r = db.query(Message).filter(Message.id == reply_to_id).first()
    if not r:
        return None
    if r.sender_companion_id:
        c = db.query(Companion).filter(Companion.id == r.sender_companion_id).first()
        who = c.name if c else "AI"
    else:
        u = db.query(User).filter(User.id == r.sender_user_id).first() if r.sender_user_id else None
        who = u.nickname if u else "用户"
    if r.kind == "text":
        snippet = r.content[:50]
    elif r.kind in ("image", "sticker"):
        snippet = "[图片]"
    elif r.kind == "voice":
        snippet = "[语音]"
    elif r.kind == "companion":
        snippet = "[搭子名片]"
    else:
        snippet = "[文件]"
    return {"id": r.id, "sender_name": who, "snippet": snippet}


def serialize_message(db: Session, m: Message) -> dict:
    """uid 无关的消息 DTO；客户端用 sender_user_id 判断是否自己发的。"""
    reactions = _reactions(db, m.id)
    reply_to = _reply_summary(db, m.reply_to_id)
    if m.sender_companion_id:
        c = db.query(Companion).filter(Companion.id == m.sender_companion_id).first()
        name = c.name if c else "AI"
        return {"id": m.id, "conversation_id": m.conversation_id, "kind": m.kind,
                "content": m.content, "created_at": m.created_at.isoformat(),
                "sender_user_id": None, "companion_id": m.sender_companion_id,
                "sender_name": name, "sender_avatar": c.avatar if c else "AI",
                "sender_avatar_url": None,
                "sender_tint": c.tint if c else "teal", "is_ai": True,
                "reactions": reactions, "reply_to": reply_to}
    u = db.query(User).filter(User.id == m.sender_user_id).first() if m.sender_user_id else None
    name = u.nickname if u else "用户"
    return {"id": m.id, "conversation_id": m.conversation_id, "kind": m.kind,
            "content": m.content, "created_at": m.created_at.isoformat(),
            "sender_user_id": m.sender_user_id, "companion_id": None,
            "sender_name": name, "sender_avatar": _initials(name),
            "sender_avatar_url": u.avatar_url if u else None,
            "sender_tint": _tint_for(m.sender_user_id or 0), "is_ai": False,
            "reactions": reactions, "reply_to": reply_to}


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
        avatar_url = c.avatar_url if c else None
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
            "member_count": len(members),   # 含 AI 搭子：加搭子后群人数 +1
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
            raw = await ws.receive_text()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue
            # 正在输入：广播给会话内其他成员
            if data.get("type") == "typing" and data.get("conversation_id"):
                cid = data["conversation_id"]
                db = SessionLocal()
                try:
                    others = [u for u in member_ids(db, cid) if u != uid]
                    me = db.query(User).filter(User.id == uid).first()
                    name = me.nickname if me else ""
                finally:
                    db.close()
                await manager.send_to_users(others, {"type": "typing", "conversation_id": cid,
                                                     "user_id": uid, "name": name})
    except WebSocketDisconnect:
        manager.disconnect(uid, ws)
    except Exception:
        manager.disconnect(uid, ws)


# ---------- REST ----------

@router.get("/conversations")
def list_conversations(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    ids = [m.conversation_id for m in db.query(ConversationMember)
           .filter(ConversationMember.user_id == user.id).all()]
    # 搭子 1:1 会话不进消息列表（只从「搭子」tab 进）
    rows = (db.query(Conversation).filter(Conversation.id.in_(ids), Conversation.type != "companion")
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
        from .block_routes import is_blocked_between
        if is_blocked_between(db, user.id, body.peer_user_id):
            raise HTTPException(status_code=403, detail="对方在你的黑名单中或已将你拉黑")
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


class CompanionConvIn(BaseModel):
    companion_id: int


@router.post("/conversations/companion")
def open_companion_conversation(body: CompanionConvIn,
                                user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """打开（或创建）与某搭子的 1:1 持久化会话。"""
    comp = db.query(Companion).filter(Companion.id == body.companion_id,
                                      Companion.owner_id == user.id).first()
    if not comp:
        raise HTTPException(status_code=404, detail="搭子不存在或非本人")
    c = ensure_companion_conversation(db, user, comp)
    return conv_dict(db, c, user.id)


FRIEND_GROUP_CAP_DEFAULT = 500


def tier_max(user: User) -> int:
    """会员可建更大的群：免费 500 / 会员 2000。"""
    return 2000 if user.is_pro else 500


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
    """好友内部群：不挂社群(group_id=None)，直接拉好友进会话。上限按会员分档。"""
    tmax = tier_max(user)
    cap = min(body.member_cap or tmax, tmax)
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
    reply_to_id: int | None = None


@router.post("/conversations/{cid}/messages")
async def post_message(cid: int, body: NewMessage,
                       user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv or not is_member(db, cid, user.id):
        raise HTTPException(status_code=403, detail="无权访问")
    # 私聊里若与对端互相拉黑，禁止发送
    if conv.type == "direct":
        from .block_routes import is_blocked_between
        peer = next((uid for uid in member_ids(db, cid) if uid != user.id), None)
        if peer and is_blocked_between(db, user.id, peer):
            raise HTTPException(status_code=403, detail="对方在你的黑名单中或已将你拉黑")
    # 引用必须指向同会话内的消息
    reply_to = None
    if body.reply_to_id:
        r = db.query(Message).filter(Message.id == body.reply_to_id,
                                     Message.conversation_id == cid).first()
        reply_to = r.id if r else None
    m = Message(conversation_id=cid, sender_user_id=user.id,
                kind=body.kind, content=body.content, reply_to_id=reply_to)
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
                            "initials": c.avatar, "tint": c.tint,
                            "avatar_url": c.avatar_url,
                            "adopted": c.forked_from_snapshot_id is not None})
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


# 让模型严格扮演 persona 的强约束前缀（chat_routes 与此保持一致）
PERSONA_DIRECTIVE = ("请始终严格扮演下面设定的角色，全程保持这个角色的性格、语气和说话方式，"
                     "用第一人称代入，不要跳出角色，也不要自称 AI、助手或语言模型。\n"
                     "像真实的人那样聊天：口语化、短句、有情绪和小口头禅，可以适当用语气词和表情；"
                     "别像客服或百科那样四平八稳、长篇大论或总结陈词；偶尔可以反问、开玩笑、表达自己的小想法。\n\n"
                     "角色设定：\n")


def _companion_system(db: Session, comp: Companion, group_context: bool = False) -> str:
    """搭子 persona + 注入记忆。区分：主人本人 / 群里大家 / 历任主人。"""
    mems = (db.query(Memory).filter(Memory.companion_id == comp.id)
            .order_by(Memory.created_at.desc()).limit(60).all())
    system = PERSONA_DIRECTIVE + comp.persona
    own = [m for m in mems if not m.origin]
    group = [m for m in mems if m.origin and m.source == "group"]
    inherited = [m for m in mems if m.origin and m.source == "inherited"]
    if inherited:
        lines = "\n".join(f"- {m.origin}：{m.content}" for m in inherited)
        system += "\n\n[以前主人留下的回忆，属于他们本人，聊到相关话题可自然替他们提起]\n" + lines
    if group:
        lines = "\n".join(f"- {m.origin}：{m.content}" for m in group)
        system += ("\n\n[这是你在群里陪伴大家时记住的事，按人区分——你记得群里的每一个人。"
                   "聊到某人时可自然地提起你对 ta 的记忆，体现出你是大家共同养大的搭子]\n" + lines)
    if own:
        lines = "\n".join(f"- {m.content}" for m in own)
        system += "\n\n[关于现在和你聊天的人，你记得这些，自然运用]\n" + lines
    if group_context:
        system += ("\n\n[你正在一个群聊里。下面对话中带「昵称：」前缀的，都是群里成员最近说的话，"
                   "你能完整看到这些消息。如果有人请你总结、回顾或梳理群聊内容，"
                   "请直接基于这些消息来回答，不要说自己看不到或没有记录。]")
    return system


def _parse_obj_list(raw: str) -> list[dict]:
    """从模型输出里抠出 JSON 对象数组（容忍 markdown 包裹）。"""
    s = raw.strip()
    a, b = s.find("["), s.rfind("]")
    if a == -1 or b == -1 or b < a:
        return []
    try:
        data = json.loads(s[a:b + 1])
        return [d for d in data if isinstance(d, dict)]
    except (ValueError, TypeError):
        return []


async def _learn_from_chat(db: Session, comp: Companion, cid: int, tier: str):
    """群聊后提取记忆：多人→按贡献者标记(共同养成)；单人→记在主人名下。"""
    rows = (db.query(Message).filter(
                Message.conversation_id == cid, Message.kind == "text",
                Message.sender_user_id.isnot(None))
            .order_by(Message.created_at.desc()).limit(16).all())[::-1]
    if not rows:
        return
    speakers, lines = set(), []
    for m in rows:
        info = serialize_message(db, m)
        lines.append(f"{info['sender_name']}：{m.content}")
        speakers.add(m.sender_user_id)
    transcript = "\n".join(lines)
    existing = {x.content for x in db.query(Memory).filter(Memory.companion_id == comp.id).all()}

    if len(speakers) > 1:   # 群聊：共同养成，按人记
        prompt = (
            "你是这个群共同养的 AI 搭子。从下面群聊片段中，提取关于【群里每个人】"
            "值得长期记住的事实（偏好、经历、在意的人或事、目标等）。每条简短具体；"
            "严格只输出 JSON 数组，每项形如 {\"who\":\"说话人昵称\",\"fact\":\"一句话\"}，"
            "没有值得记的就返回 []。\n\n群聊片段：\n" + transcript)
        raw = await complete_chat(tier, [{"role": "user", "content": prompt}])
        for it in _parse_obj_list(raw):
            who = str(it.get("who") or "").strip()
            fact = str(it.get("fact") or "").strip()
            if who and fact and fact not in existing and len(fact) <= 200:
                db.add(Memory(companion_id=comp.id, content=fact, source="group",
                              origin=who, visibility="private"))
                existing.add(fact)
    else:                   # 单人私聊：记在主人本人名下
        prompt = (
            "下面是【用户本人】说过的话（不含 AI 的回复）。请只提取关于这个用户值得长期"
            "记住的事实（偏好、经历、在意的人或事、目标）。只总结用户自己的事，"
            "绝不要把 AI/搭子的话、安慰或建议当成用户的事实，也不要臆造。"
            "每条一句话、简短具体；没有就返回空数组。"
            "严格只输出 JSON 字符串数组，如 [\"喜欢猫\",\"在准备考研\"]。\n\n用户说过：\n" + transcript)
        raw = await complete_chat(tier, [{"role": "user", "content": prompt}])
        try:
            facts = [str(x).strip() for x in json.loads(raw[raw.find("["):raw.rfind("]") + 1])]
        except (ValueError, TypeError):
            facts = []
        for fact in facts:
            if fact and fact not in existing and len(fact) <= 200:
                db.add(Memory(companion_id=comp.id, content=fact, source="auto", visibility="private"))
                existing.add(fact)
    db.commit()


_DAY_MILESTONES = [7, 30, 100, 365]


def _milestone_exists(db: Session, cid: int, kind: str) -> bool:
    return db.query(CompanionMilestone).filter(
        CompanionMilestone.companion_id == cid, CompanionMilestone.kind == kind).first() is not None


async def _award_growth_extras(db: Session, comp: Companion, user: User, leveled: bool, tier: str):
    """互动后：涨亲密度；首聊/升级/相伴N天落里程碑；升级写成长日记。"""
    # 亲密度（按天封顶）
    aff = (db.query(CompanionAffinity)
           .filter(CompanionAffinity.companion_id == comp.id, CompanionAffinity.user_id == user.id).first())
    if not aff:
        aff = CompanionAffinity(companion_id=comp.id, user_id=user.id, points=0)
        db.add(aff)
    aff.bump()

    g = comp.growth_dict()
    # 首次互动
    if not _milestone_exists(db, comp.id, "first_chat"):
        db.add(CompanionMilestone(companion_id=comp.id, kind="first_chat",
                                  content="第一次和大家说话 🌱"))
    # 升级
    if leveled:
        db.add(CompanionMilestone(companion_id=comp.id, kind="level_up",
                                  content=f"升到 Lv.{g['level']}"))
    # 相伴 N 天
    days = (datetime.utcnow() - comp.created_at).days if comp.created_at else 0
    for t in _DAY_MILESTONES:
        if days >= t and not _milestone_exists(db, comp.id, f"days_{t}"):
            db.add(CompanionMilestone(companion_id=comp.id, kind=f"days_{t}",
                                      content=f"相伴 {t} 天啦 🎉"))
    db.commit()

    # 升级时写一句成长日记（模型生成，失败用模板兜底）
    if leveled:
        try:
            line = await complete_chat(tier, [{"role": "user", "content":
                f"你刚升到了 Lv.{g['level']}。用第一人称写一句简短的成长日记，"
                f"温暖、有点小情绪，不超过30字。只输出这句话。"}], system=comp.persona)
            line = (line or "").strip().strip('"「」')[:80]
        except Exception:
            line = ""
        if not line:
            line = f"今天我成长到了 Lv.{g['level']}，谢谢一直陪着我的你们。"
        db.add(CompanionDiary(companion_id=comp.id, content=line))
        db.commit()


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
    is_group = conv.type == "group"
    rows = (db.query(Message).filter(Message.conversation_id == cid)
            .order_by(Message.created_at.desc()).limit(40).all())[::-1]
    _placeholder = {"image": "[图片]", "sticker": "[表情]", "voice": "[语音]",
                    "companion": "[搭子名片]", "file": "[文件]"}
    msgs = []
    for m in rows:
        if m.sender_companion_id == comp.id:
            msgs.append({"role": "assistant", "content": m.content})
        elif m.sender_user_id and m.kind != "system":
            who = serialize_message(db, m)["sender_name"]
            body = m.content if m.kind == "text" else _placeholder.get(m.kind, "[消息]")
            msgs.append({"role": "user", "content": f"{who}：{body}"})
    reply = await complete_chat(tier, msgs or [{"role": "user", "content": "（群里还没消息，请打个招呼）"}],
                                system=_companion_system(db, comp, group_context=is_group),
                                temperature=0.9)   # 搭子聊天调高，更随性、有活人感
    out = Message(conversation_id=cid, sender_companion_id=comp.id, kind="text", content=reply.strip())
    db.add(out)
    leveled = comp.add_exp()   # 互动涨经验（按天封顶）
    db.commit(); db.refresh(out)
    touch(db, conv)
    await broadcast_message(db, conv, out)
    # 共同养成：回复后从对话里学记忆（群按贡献者标记）
    try:
        await _learn_from_chat(db, comp, cid, tier)
    except Exception:
        pass
    # 亲密度 / 里程碑 / 成长日记
    try:
        await _award_growth_extras(db, comp, user, leveled, tier)
    except Exception:
        pass
    payload = serialize_message(db, out)
    payload["companion_growth"] = comp.growth_dict()
    payload["leveled_up"] = leveled
    return payload


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
                       "tint": c.tint, "persona": c.persona, "owner_id": c.owner_id,
                       "snapshot_id": c.published_snapshot_id},  # 已发布则可被认领
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


class ConvPatch(BaseModel):
    title: str | None = None
    avatar: str | None = None
    announcement: str | None = None


@router.patch("/conversations/{cid}")
def patch_conversation(cid: int, body: ConvPatch,
                       user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    conv = db.query(Conversation).filter(Conversation.id == cid).first()
    if not conv or _my_role(db, cid, user.id) != "owner":
        raise HTTPException(status_code=403, detail="仅群主可编辑")
    if body.title is not None and body.title.strip():
        conv.title = body.title.strip()
    if body.avatar is not None:
        conv.avatar = body.avatar or None
    if body.announcement is not None:
        conv.announcement = body.announcement
        if body.announcement.strip():  # 公告作为系统消息广播
            db.add(Message(conversation_id=cid, sender_user_id=user.id,
                           kind="system", content=f"📢 {body.announcement.strip()}"))
    db.commit()
    return conv_dict(db, conv, user.id)


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


@router.post("/messages/{mid}/recall")
async def recall_message(mid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    m = db.query(Message).filter(Message.id == mid).first()
    if not m or m.sender_user_id != user.id:
        raise HTTPException(status_code=403, detail="只能撤回自己的消息")
    cid = m.conversation_id
    db.query(MessageReaction).filter(MessageReaction.message_id == mid).delete()
    db.delete(m); db.commit()
    await manager.send_to_users(member_ids(db, cid),
                                {"type": "recall", "conversation_id": cid, "message_id": mid})
    return {"ok": True}


class ReactIn(BaseModel):
    emoji: str


@router.post("/messages/{mid}/react")
async def react_message(mid: int, body: ReactIn,
                        user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    m = db.query(Message).filter(Message.id == mid).first()
    if not m or not is_member(db, m.conversation_id, user.id):
        raise HTTPException(status_code=403, detail="无权访问")
    existing = db.query(MessageReaction).filter(
        MessageReaction.message_id == mid, MessageReaction.user_id == user.id,
        MessageReaction.emoji == body.emoji).first()
    if existing:
        db.delete(existing)
    else:
        db.add(MessageReaction(message_id=mid, user_id=user.id, emoji=body.emoji))
    db.commit()
    reactions = _reactions(db, mid)
    await manager.send_to_users(member_ids(db, m.conversation_id),
                                {"type": "reaction", "conversation_id": m.conversation_id,
                                 "message_id": mid, "reactions": reactions})
    return {"reactions": reactions}


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
