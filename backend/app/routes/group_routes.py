"""群组广场：发现 / 创建 / 加入(开放·邀请码·审批) / 我的群 / 审批。"""
import secrets
import string
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User, Group, GroupMember, GroupJoinRequest

router = APIRouter(tags=["group"])


def _count(db: Session, gid: int) -> int:
    return db.query(GroupMember).filter(GroupMember.group_id == gid).count()


def _is_member(db: Session, gid: int, uid: int) -> bool:
    return db.query(GroupMember).filter(GroupMember.group_id == gid, GroupMember.user_id == uid).first() is not None


def _is_pending(db: Session, gid: int, uid: int) -> bool:
    return db.query(GroupJoinRequest).filter(
        GroupJoinRequest.group_id == gid, GroupJoinRequest.user_id == uid,
        GroupJoinRequest.status == "pending").first() is not None


def _gen_code() -> str:
    return "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(6))


def _dict(db: Session, g: Group, uid: int) -> dict:
    return g.public_dict(_count(db, g.id), _is_member(db, g.id, uid),
                         _is_pending(db, g.id, uid), g.owner_id == uid)


@router.get("/groups/plaza")
def plaza(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(Group).order_by(Group.created_at.desc()).all()
    return {"groups": [_dict(db, g, user.id) for g in rows]}


@router.get("/groups/mine")
def mine(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    ids = [m.group_id for m in db.query(GroupMember).filter(GroupMember.user_id == user.id).all()]
    rows = db.query(Group).filter(Group.id.in_(ids)).all() if ids else []
    return {"groups": [_dict(db, g, user.id) for g in rows]}


class GroupIn(BaseModel):
    name: str = Field(min_length=1, max_length=24)
    description: str = Field(default="", max_length=120)
    avatar: str = Field(default="群", max_length=2)
    tint: str = Field(default="teal")
    join_mode: str = Field(default="open")  # open | code | approval
    member_cap: int = Field(default=200, ge=2, le=2000)


@router.post("/groups")
def create_group(body: GroupIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    g = Group(owner_id=user.id, owner_name=user.nickname, name=body.name, description=body.description,
              avatar=body.avatar or body.name[:1], tint=body.tint,
              join_mode=body.join_mode if body.join_mode in ("open", "code", "approval") else "open",
              member_cap=body.member_cap, invite_code=_gen_code())
    db.add(g)
    db.commit()
    db.refresh(g)
    db.add(GroupMember(group_id=g.id, user_id=user.id))  # 群主自动入群
    db.commit()
    return _dict(db, g, user.id)


def _do_join(db: Session, g: Group, user: User):
    if _is_member(db, g.id, user.id):
        return {"joined": True}
    if _count(db, g.id) >= g.member_cap:
        raise HTTPException(status_code=409, detail="群成员已满")
    db.add(GroupMember(group_id=g.id, user_id=user.id))
    db.commit()
    return {"joined": True}


@router.post("/groups/{gid}/join")
def join(gid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == gid).first()
    if not g:
        raise HTTPException(status_code=404, detail="群不存在")
    if g.join_mode == "open":
        return _do_join(db, g, user)
    if g.join_mode == "approval":
        if _is_member(db, gid, user.id):
            return {"joined": True}
        if not _is_pending(db, gid, user.id):
            db.add(GroupJoinRequest(group_id=gid, user_id=user.id, user_name=user.nickname))
            db.commit()
        return {"pending": True}
    raise HTTPException(status_code=400, detail="该群需要邀请码加入")


class CodeIn(BaseModel):
    code: str


@router.post("/groups/join-by-code")
def join_by_code(body: CodeIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.invite_code == body.code.strip().upper()).first()
    if not g:
        raise HTTPException(status_code=404, detail="邀请码无效")
    return {**_do_join(db, g, user), "group": _dict(db, g, user.id)}


@router.get("/groups/{gid}")
def group_detail(gid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == gid).first()
    if not g:
        raise HTTPException(status_code=404, detail="群不存在")
    members = db.query(GroupMember).filter(GroupMember.group_id == gid).all()
    out = []
    for m in members:
        u = db.query(User).filter(User.id == m.user_id).first()
        name = u.nickname if u else "用户"
        first = name[:1]
        initials = name[:2].upper() if first.isascii() else name[:1]
        out.append({"name": name, "initials": initials, "is_owner": m.user_id == g.owner_id})
    d = _dict(db, g, user.id)
    d["members"] = out
    return d


@router.get("/groups/{gid}/requests")
def requests(gid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == gid, Group.owner_id == user.id).first()
    if not g:
        raise HTTPException(status_code=404, detail="群不存在或无权限")
    rows = db.query(GroupJoinRequest).filter(
        GroupJoinRequest.group_id == gid, GroupJoinRequest.status == "pending").all()
    return {"requests": [{"id": r.id, "user_name": r.user_name} for r in rows]}


@router.post("/groups/requests/{rid}/approve")
def approve(rid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    r = db.query(GroupJoinRequest).filter(GroupJoinRequest.id == rid).first()
    if not r:
        raise HTTPException(status_code=404, detail="申请不存在")
    g = db.query(Group).filter(Group.id == r.group_id, Group.owner_id == user.id).first()
    if not g:
        raise HTTPException(status_code=403, detail="无权限")
    r.status = "approved"
    if not _is_member(db, g.id, r.user_id) and _count(db, g.id) < g.member_cap:
        db.add(GroupMember(group_id=g.id, user_id=r.user_id))
    db.commit()
    return {"ok": True}
