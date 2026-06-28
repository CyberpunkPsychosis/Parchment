"""拉黑 / 举报。被拉黑后双方互相搜不到、无法私聊。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import or_, and_
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User, Block, Report

router = APIRouter(tags=["safety"])


def is_blocked_between(db: Session, a: int, b: int) -> bool:
    """任一方向存在拉黑即视为被屏蔽。"""
    return db.query(Block).filter(or_(
        and_(Block.user_id == a, Block.blocked_id == b),
        and_(Block.user_id == b, Block.blocked_id == a),
    )).first() is not None


class BlockIn(BaseModel):
    user_id: int


@router.post("/blocks")
def add_block(body: BlockIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if body.user_id == user.id:
        raise HTTPException(status_code=400, detail="不能拉黑自己")
    if not db.query(User).filter(User.id == body.user_id).first():
        raise HTTPException(status_code=404, detail="用户不存在")
    if not db.query(Block).filter(Block.user_id == user.id, Block.blocked_id == body.user_id).first():
        db.add(Block(user_id=user.id, blocked_id=body.user_id))
        db.commit()
    return {"ok": True, "blocked": True}


@router.delete("/blocks/{uid}")
def remove_block(uid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.query(Block).filter(Block.user_id == user.id, Block.blocked_id == uid).first()
    if row:
        db.delete(row)
        db.commit()
    return {"ok": True, "blocked": False}


@router.get("/blocks")
def list_blocks(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(Block).filter(Block.user_id == user.id).all()
    out = []
    for b in rows:
        u = db.query(User).filter(User.id == b.blocked_id).first()
        if u:
            out.append({"user_id": u.id, "nickname": u.nickname, "avatar_url": u.avatar_url})
    return {"blocks": out}


class ReportIn(BaseModel):
    target_type: str = Field(default="user")  # user | message | group | post
    target_id: int
    reason: str = Field(default="", max_length=500)


@router.post("/reports")
def add_report(body: ReportIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if body.target_type not in ("user", "message", "group", "post"):
        raise HTTPException(status_code=400, detail="非法举报类型")
    db.add(Report(reporter_id=user.id, target_type=body.target_type,
                  target_id=body.target_id, reason=body.reason.strip()))
    db.commit()
    return {"ok": True}
