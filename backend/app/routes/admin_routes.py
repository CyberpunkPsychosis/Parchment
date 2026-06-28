"""运营后台接口（全部需管理员）。建假用户、替假用户发内容、一键清空、每日滑入。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_admin_user
from ..db import get_db
from ..models import User, Post, Companion, Group, GroupMember
from ..config import SEED_DAILY_USERS, SEED_DAILY_MOMENTS
from .. import seed_population as sp
from .. import seed_assets

router = APIRouter(tags=["admin"])


def _fake_user_dict(db: Session, u: User) -> dict:
    posts = db.query(Post).filter(Post.author_id == u.id).count()
    comps = db.query(Companion).filter(Companion.owner_id == u.id).count()
    groups = db.query(Group).filter(Group.owner_id == u.id).count()
    return {"id": u.id, "nickname": u.nickname, "bio": u.bio, "avatar_url": u.avatar_url,
            "post_count": posts, "companion_count": comps, "group_count": groups}


@router.get("/admin/stats")
def stats(admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    real_users = db.query(User).filter((User.is_seed.is_(None)) | (User.is_seed == False)).count()  # noqa: E712
    fake_users = db.query(User).filter(User.is_seed == True).count()  # noqa: E712
    posts = db.query(Post).count()
    return {"real_users": real_users, "fake_users": fake_users, "posts": posts,
            "has_assets": seed_assets.has_assets()}


@router.get("/admin/fake-users")
def list_fake_users(admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    rows = db.query(User).filter(User.is_seed == True).order_by(User.id.desc()).all()  # noqa: E712
    return {"users": [_fake_user_dict(db, u) for u in rows]}


class FakeUserIn(BaseModel):
    nickname: str | None = Field(default=None, max_length=40)
    bio: str | None = Field(default=None, max_length=200)
    avatar_url: str | None = None


@router.post("/admin/fake-users")
def create_fake_user(body: FakeUserIn, admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    u = sp.create_fake_user(db, nickname=(body.nickname or None),
                            bio=(body.bio if body.bio is not None else None),
                            avatar_url=(body.avatar_url or None))
    return _fake_user_dict(db, u)


class GenerateIn(BaseModel):
    count: int = Field(default=5, ge=1, le=50)


@router.post("/admin/fake-users/generate")
def generate_fake_users(body: GenerateIn, admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    made = sp.generate_users(db, body.count)
    return {"created": len(made), "users": [_fake_user_dict(db, u) for u in made]}


def _seed_user_or_404(db: Session, uid: int) -> User:
    u = db.query(User).filter(User.id == uid, User.is_seed == True).first()  # noqa: E712
    if not u:
        raise HTTPException(status_code=404, detail="假用户不存在")
    return u


class MomentIn(BaseModel):
    content: str = Field(default="", max_length=1000)
    image_url: str | None = None


@router.post("/admin/fake-users/{uid}/moments")
def post_moment(uid: int, body: MomentIn, admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    u = _seed_user_or_404(db, uid)
    if not body.content.strip() and not body.image_url:
        raise HTTPException(status_code=400, detail="内容不能为空")
    p = sp.post_moment_as(db, u, body.content, body.image_url)
    return {"id": p.id, "author_name": p.author_name, "content": p.content, "image_url": p.image_url}


class CompanionIn(BaseModel):
    name: str = Field(max_length=20)
    persona: str = Field(min_length=1, max_length=600)
    greeting: str = Field(default="", max_length=120)
    tint: str = "teal"
    avatar_url: str | None = None


@router.post("/admin/fake-users/{uid}/companions")
def make_companion(uid: int, body: CompanionIn, admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    u = _seed_user_or_404(db, uid)
    c = Companion(owner_id=u.id, name=body.name, persona=body.persona,
                  avatar=body.name[:1] or "搭", tint=body.tint, greeting=body.greeting,
                  avatar_url=body.avatar_url or None)
    db.add(c); db.commit(); db.refresh(c)
    return c.public_dict()


class GroupIn(BaseModel):
    name: str = Field(min_length=1, max_length=30)
    description: str = Field(default="", max_length=200)
    member_seed_users: int = Field(default=0, ge=0, le=50)   # 顺带拉几个假用户进群


@router.post("/admin/fake-users/{uid}/groups")
def make_group(uid: int, body: GroupIn, admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    import secrets, string
    u = _seed_user_or_404(db, uid)
    code = "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(6))
    g = Group(owner_id=u.id, owner_name=u.nickname, name=body.name, description=body.description,
              avatar=body.name[:1], tint="teal", join_mode="open", member_cap=500, invite_code=code)
    db.add(g); db.commit(); db.refresh(g)
    db.add(GroupMember(group_id=g.id, user_id=u.id))
    # 顺带拉一些其它假用户进群，显得有人气
    if body.member_seed_users:
        others = (db.query(User).filter(User.is_seed == True, User.id != u.id)  # noqa: E712
                  .order_by(User.id.desc()).limit(body.member_seed_users).all())
        for o in others:
            db.add(GroupMember(group_id=g.id, user_id=o.id))
    db.commit()
    return {"id": g.id, "name": g.name, "description": g.description,
            "member_count": db.query(GroupMember).filter(GroupMember.group_id == g.id).count()}


@router.delete("/admin/fake-users/{uid}")
def delete_fake_user(uid: int, admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    _seed_user_or_404(db, uid)
    sp.purge_user(db, uid)
    return {"ok": True}


@router.delete("/admin/fake-data")
def wipe_all(admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    n = sp.purge_all_seed(db)
    return {"ok": True, "removed_users": n}


@router.post("/admin/seed/daily-tick")
def daily_tick_now(admin: User = Depends(get_admin_user), db: Session = Depends(get_db)):
    return sp.daily_tick(db, SEED_DAILY_USERS, SEED_DAILY_MOMENTS, force=True)
