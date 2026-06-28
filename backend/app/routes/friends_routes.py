"""好友：用户搜索 / 申请 / 同意 / 好友列表 / 公开主页。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import or_, and_
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User, Friendship, FriendRequest, Companion
from .block_routes import is_blocked_between

router = APIRouter(tags=["friends"])

PALETTE = ["teal", "sage", "tealDark", "ink", "gray"]


def _initials(name: str) -> str:
    name = (name or "").strip() or "用户"
    return name[:2].upper() if name[:1].isascii() else name[:1]


def _tint(uid: int) -> str:
    return PALETTE[uid % len(PALETTE)]


def are_friends(db: Session, x: int, y: int) -> bool:
    a, b = min(x, y), max(x, y)
    return db.query(Friendship).filter(Friendship.user_a == a, Friendship.user_b == b).first() is not None


def _pending_between(db: Session, frm: int, to: int) -> FriendRequest | None:
    return db.query(FriendRequest).filter(
        FriendRequest.from_user_id == frm, FriendRequest.to_user_id == to,
        FriendRequest.status == "pending").first()


def _user_dict(db: Session, u: User, me: int) -> dict:
    return {
        "id": u.id, "nickname": u.nickname or u.email.split("@")[0],
        "initials": _initials(u.nickname or u.email), "tint": _tint(u.id),
        "avatar_url": u.avatar_url, "bio": u.bio,
        "is_friend": are_friends(db, me, u.id),
        "outgoing_pending": _pending_between(db, me, u.id) is not None,
        "incoming_pending": _pending_between(db, u.id, me) is not None,
        "is_me": u.id == me,
    }


@router.get("/users/search")
def search_users(q: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    q = q.strip()
    if not q:
        return {"users": []}
    rows = (db.query(User)
            .filter(or_(User.nickname.ilike(f"%{q}%"), User.email.ilike(f"%{q}%")))
            .filter(User.id != user.id).limit(40).all())
    rows = [u for u in rows if not is_blocked_between(db, user.id, u.id)][:20]
    return {"users": [_user_dict(db, u, user.id) for u in rows]}


@router.get("/users/{uid}")
def user_profile(uid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    u = db.query(User).filter(User.id == uid).first()
    if not u:
        raise HTTPException(status_code=404, detail="用户不存在")
    d = _user_dict(db, u, user.id)
    # 附公开搭子（分享/认领用）
    comps = db.query(Companion).filter(
        Companion.owner_id == uid, Companion.visibility == "published").all()
    d["companions"] = [c.public_dict() for c in comps]
    return d


class FriendReqIn(BaseModel):
    to_user_id: int


@router.post("/friends/request")
def send_request(body: FriendReqIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    to = body.to_user_id
    if to == user.id:
        raise HTTPException(status_code=400, detail="不能加自己")
    if not db.query(User).filter(User.id == to).first():
        raise HTTPException(status_code=404, detail="用户不存在")
    if are_friends(db, user.id, to):
        return {"ok": True, "status": "friends"}
    # 对方已向我发过 → 直接互相成为好友
    rev = _pending_between(db, to, user.id)
    if rev:
        rev.status = "accepted"
        _add_friend(db, user.id, to)
        db.commit()
        return {"ok": True, "status": "accepted"}
    if _pending_between(db, user.id, to):
        return {"ok": True, "status": "pending"}
    db.add(FriendRequest(from_user_id=user.id, from_user_name=user.nickname, to_user_id=to))
    db.commit()
    return {"ok": True, "status": "pending"}


@router.get("/friends/requests")
def incoming_requests(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(FriendRequest).filter(
        FriendRequest.to_user_id == user.id, FriendRequest.status == "pending").all()
    out = []
    for r in rows:
        u = db.query(User).filter(User.id == r.from_user_id).first()
        out.append({"id": r.id, "from_user_id": r.from_user_id,
                    "nickname": r.from_user_name or (u.nickname if u else "用户"),
                    "initials": _initials(r.from_user_name or (u.nickname if u else "")),
                    "tint": _tint(r.from_user_id),
                    "avatar_url": u.avatar_url if u else None})
    return {"requests": out}


def _add_friend(db: Session, x: int, y: int):
    a, b = min(x, y), max(x, y)
    if not db.query(Friendship).filter(Friendship.user_a == a, Friendship.user_b == b).first():
        db.add(Friendship(user_a=a, user_b=b))


@router.post("/friends/requests/{rid}/accept")
def accept_request(rid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    r = db.query(FriendRequest).filter(FriendRequest.id == rid, FriendRequest.to_user_id == user.id).first()
    if not r:
        raise HTTPException(status_code=404, detail="申请不存在")
    r.status = "accepted"
    _add_friend(db, r.from_user_id, user.id)
    db.commit()
    return {"ok": True}


@router.post("/friends/requests/{rid}/reject")
def reject_request(rid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    r = db.query(FriendRequest).filter(FriendRequest.id == rid, FriendRequest.to_user_id == user.id).first()
    if not r:
        raise HTTPException(status_code=404, detail="申请不存在")
    r.status = "rejected"
    db.commit()
    return {"ok": True}


@router.get("/friends")
def list_friends(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(Friendship).filter(
        or_(Friendship.user_a == user.id, Friendship.user_b == user.id)).all()
    ids = [(r.user_b if r.user_a == user.id else r.user_a) for r in rows]
    users = db.query(User).filter(User.id.in_(ids)).all() if ids else []
    return {"friends": [_user_dict(db, u, user.id) for u in users]}
