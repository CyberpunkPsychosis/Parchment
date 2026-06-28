"""全局搜索：好友(用户) / 群组社群 / 可认领搭子。"""
from fastapi import APIRouter, Depends
from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User, Group, GroupMember, CompanionSnapshot

router = APIRouter(tags=["search"])


def _initials(name: str) -> str:
    name = (name or "").strip() or "?"
    return name[:2].upper() if name[:1].isascii() else name[:1]


@router.get("/search")
def search(q: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    q = q.strip()
    if not q:
        return {"users": [], "groups": [], "companions": []}
    like = f"%{q}%"

    users = (db.query(User).filter(or_(User.nickname.ilike(like), User.email.ilike(like)))
             .filter(User.id != user.id).limit(10).all())
    users_out = [{"id": u.id, "nickname": u.nickname or u.email.split("@")[0],
                  "initials": _initials(u.nickname or u.email), "tint": "teal",
                  "avatar_url": u.avatar_url} for u in users]

    groups = db.query(Group).filter(Group.name.ilike(like)).limit(10).all()
    def _gc(gid): return db.query(GroupMember).filter(GroupMember.group_id == gid).count()
    groups_out = [{"id": g.id, "name": g.name, "avatar": g.avatar, "tint": g.tint,
                   "member_count": _gc(g.id), "member_cap": g.member_cap,
                   "is_member": db.query(GroupMember).filter(
                       GroupMember.group_id == g.id, GroupMember.user_id == user.id).first() is not None}
                  for g in groups]

    snaps = (db.query(CompanionSnapshot).filter(CompanionSnapshot.active == 1)
             .filter(CompanionSnapshot.name.ilike(like)).limit(10).all())
    comps_out = [{"snapshot_id": s.id, "name": s.name, "avatar": s.avatar, "tint": s.tint,
                  "persona": s.persona, "publisher_name": s.publisher_name} for s in snaps]

    return {"users": users_out, "groups": groups_out, "companions": comps_out}
