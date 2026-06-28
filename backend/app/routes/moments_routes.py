"""朋友圈/动态：发帖 / 点赞 / 评论 + 设备推送 token 注册。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User, Post, PostLike, PostComment, DeviceToken

router = APIRouter(tags=["moments"])


def _initials(name: str) -> str:
    name = (name or "").strip() or "用户"
    return name[:2].upper() if name[:1].isascii() else name[:1]


def _post_dict(db: Session, p: Post, uid: int) -> dict:
    likes = db.query(PostLike).filter(PostLike.post_id == p.id).count()
    liked = db.query(PostLike).filter(PostLike.post_id == p.id, PostLike.user_id == uid).first() is not None
    comments = db.query(PostComment).filter(PostComment.post_id == p.id).count()
    author = db.query(User).filter(User.id == p.author_id).first()
    return {"id": p.id, "author_id": p.author_id, "author_name": p.author_name,
            "author_initials": _initials(p.author_name),
            "author_avatar_url": author.avatar_url if author else None, "content": p.content,
            "image_url": p.image_url, "created_at": p.created_at.isoformat(),
            "like_count": likes, "liked": liked, "comment_count": comments}


@router.get("/moments")
def feed(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(Post).order_by(Post.created_at.desc()).limit(50).all()
    return {"posts": [_post_dict(db, p, user.id) for p in rows]}


class PostIn(BaseModel):
    content: str = Field(default="", max_length=1000)
    image_url: str | None = None


@router.post("/moments")
def create_post(body: PostIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not body.content.strip() and not body.image_url:
        raise HTTPException(status_code=400, detail="内容不能为空")
    p = Post(author_id=user.id, author_name=user.nickname, content=body.content, image_url=body.image_url)
    db.add(p); db.commit(); db.refresh(p)
    return _post_dict(db, p, user.id)


@router.post("/moments/{pid}/like")
def toggle_like(pid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    existing = db.query(PostLike).filter(PostLike.post_id == pid, PostLike.user_id == user.id).first()
    if existing:
        db.delete(existing); db.commit(); liked = False
    else:
        db.add(PostLike(post_id=pid, user_id=user.id)); db.commit(); liked = True
    count = db.query(PostLike).filter(PostLike.post_id == pid).count()
    return {"liked": liked, "like_count": count}


@router.get("/moments/{pid}")
def post_detail(pid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """单条动态详情：帖子 + 全部评论（微信式详情页用）。"""
    p = db.query(Post).filter(Post.id == pid).first()
    if not p:
        raise HTTPException(status_code=404, detail="动态不存在")
    rows = db.query(PostComment).filter(PostComment.post_id == pid).order_by(PostComment.created_at.asc()).all()
    return {"post": _post_dict(db, p, user.id),
            "comments": [{"id": r.id, "user_name": r.user_name, "initials": _initials(r.user_name),
                          "content": r.content, "created_at": r.created_at.isoformat()} for r in rows]}


@router.get("/moments/{pid}/comments")
def comments(pid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(PostComment).filter(PostComment.post_id == pid).order_by(PostComment.created_at.asc()).all()
    return {"comments": [{"id": r.id, "user_name": r.user_name, "initials": _initials(r.user_name),
                          "content": r.content, "created_at": r.created_at.isoformat()} for r in rows]}


class CommentIn(BaseModel):
    content: str = Field(min_length=1, max_length=500)


@router.post("/moments/{pid}/comments")
def add_comment(pid: int, body: CommentIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not db.query(Post).filter(Post.id == pid).first():
        raise HTTPException(status_code=404, detail="动态不存在")
    cm = PostComment(post_id=pid, user_id=user.id, user_name=user.nickname, content=body.content)
    db.add(cm); db.commit(); db.refresh(cm)
    return {"id": cm.id, "user_name": cm.user_name, "initials": _initials(cm.user_name),
            "content": cm.content, "created_at": cm.created_at.isoformat()}


# ---------- 推送设备 token ----------

class DeviceIn(BaseModel):
    token: str
    platform: str = "ios"


@router.post("/devices")
def register_device(body: DeviceIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.query(DeviceToken).filter(DeviceToken.token == body.token).first()
    if row:
        row.user_id = user.id
    else:
        db.add(DeviceToken(user_id=user.id, token=body.token, platform=body.platform))
    db.commit()
    return {"ok": True}
