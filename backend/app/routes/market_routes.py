"""AI 搭子认领市场：发布快照 / 浏览 / 认领(fork) / 传承链。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User, Companion, Memory, CompanionSnapshot, SnapshotMemory

router = APIRouter(tags=["market"])


def _snap_mem_count(db: Session, sid: int) -> int:
    return db.query(SnapshotMemory).filter(SnapshotMemory.snapshot_id == sid).count()


# 发布门槛：搭子需养到一定记忆量才能上市场（防止市场充斥空白搭子，约一周起步量）
MIN_PUBLISH_MEMORIES = 8


@router.get("/companions/{cid}/publish-eligibility")
def publish_eligibility(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """发布资格：当前记忆数 / 门槛 / 是否可发布。"""
    c = db.query(Companion).filter(Companion.id == cid, Companion.owner_id == user.id).first()
    if not c:
        raise HTTPException(status_code=404, detail="搭子不存在")
    total = db.query(Memory).filter(Memory.companion_id == cid).count()
    return {"memory_count": total, "required": MIN_PUBLISH_MEMORIES, "can_publish": total >= MIN_PUBLISH_MEMORIES}


@router.post("/companions/{cid}/publish")
def publish(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """把搭子发布为可认领快照。仅打包 visibility=shareable 的记忆。"""
    c = db.query(Companion).filter(Companion.id == cid, Companion.owner_id == user.id).first()
    if not c:
        raise HTTPException(status_code=404, detail="搭子不存在")

    total_mem = db.query(Memory).filter(Memory.companion_id == cid).count()
    if total_mem < MIN_PUBLISH_MEMORIES:
        raise HTTPException(status_code=400,
                            detail=f"搭子还太年轻，多陪它聊聊、攒到至少 {MIN_PUBLISH_MEMORIES} 条记忆再发布吧（现在 {total_mem} 条）")

    shareable = db.query(Memory).filter(Memory.companion_id == cid,
                                        Memory.visibility == "shareable").all()
    if not shareable:
        raise HTTPException(status_code=400, detail="至少勾选 1 条要分享的记忆再发布")

    # 传承：若该搭子是认领来的，新快照接在其来源快照之后
    depth = 0
    if c.forked_from_snapshot_id:
        parent = db.query(CompanionSnapshot).filter(
            CompanionSnapshot.id == c.forked_from_snapshot_id).first()
        if parent:
            depth = parent.lineage_depth + 1

    snap = CompanionSnapshot(
        publisher_id=user.id, publisher_name=user.nickname,
        source_companion_id=c.id, parent_snapshot_id=c.forked_from_snapshot_id,
        name=c.name, persona=c.persona, avatar=c.avatar, tint=c.tint, greeting=c.greeting,
        lineage_depth=depth,
    )
    db.add(snap)
    db.commit()
    db.refresh(snap)

    for m in shareable:
        # 自己的记忆(origin=None)发布时盖上自己的名字；继承来的保留原主人
        db.add(SnapshotMemory(snapshot_id=snap.id, content=m.content,
                              origin=m.origin or user.nickname))
    c.published_snapshot_id = snap.id
    c.visibility = "published"
    db.commit()
    return snap.public_dict(memory_count=len(shareable), is_mine=True)


@router.delete("/market/{sid}")
def unpublish(sid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """下架（挡住新认领；已认领的副本不受影响）。"""
    snap = db.query(CompanionSnapshot).filter(CompanionSnapshot.id == sid).first()
    if not snap or snap.publisher_id != user.id:
        raise HTTPException(status_code=404, detail="快照不存在")
    snap.active = 0
    src = db.query(Companion).filter(Companion.id == snap.source_companion_id).first()
    if src and src.published_snapshot_id == sid:
        src.published_snapshot_id = None
        src.visibility = "private"
    db.commit()
    return {"ok": True}


def _already_adopted(db: Session, uid: int, sid: int) -> bool:
    return db.query(Companion).filter(Companion.owner_id == uid,
                                      Companion.forked_from_snapshot_id == sid).first() is not None


@router.get("/market")
def market(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = (db.query(CompanionSnapshot).filter(CompanionSnapshot.active == 1)
            .order_by(CompanionSnapshot.adopt_count.desc(), CompanionSnapshot.created_at.desc()).all())
    return {"items": [s.public_dict(_snap_mem_count(db, s.id), s.publisher_id == user.id,
                                    _already_adopted(db, user.id, s.id)) for s in rows]}


_PREVIEW_N = 3  # 认领前只露几条做"钩子"，其余认领后聊天慢慢发现


@router.get("/market/{sid}")
def market_detail(sid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    snap = db.query(CompanionSnapshot).filter(CompanionSnapshot.id == sid, CompanionSnapshot.active == 1).first()
    if not snap:
        raise HTTPException(status_code=404, detail="快照不存在")
    mems = db.query(SnapshotMemory).filter(SnapshotMemory.snapshot_id == sid).all()
    total = len(mems)
    d = snap.public_dict(total, snap.publisher_id == user.id, _already_adopted(db, user.id, sid))
    # 仅预览前几条；其余隐藏，认领后通过对话发现
    d["memories"] = [m.content for m in mems[:_PREVIEW_N]]
    d["hidden_count"] = max(0, total - _PREVIEW_N)
    return d


@router.post("/market/{sid}/adopt")
def adopt(sid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """认领 = fork：把快照复制成自己账户里的新搭子（含继承记忆）。"""
    snap = db.query(CompanionSnapshot).filter(CompanionSnapshot.id == sid, CompanionSnapshot.active == 1).first()
    if not snap:
        raise HTTPException(status_code=404, detail="快照不存在")

    c = Companion(
        owner_id=user.id, name=snap.name, persona=snap.persona, avatar=snap.avatar,
        tint=snap.tint, greeting=snap.greeting,
        parent_id=snap.source_companion_id, forked_from_snapshot_id=snap.id,
    )
    db.add(c)
    db.commit()
    db.refresh(c)

    # 继承记忆（私有副本，保留"来自谁"，构成传承；认领者可自行决定是否再分享）
    for m in db.query(SnapshotMemory).filter(SnapshotMemory.snapshot_id == sid).all():
        db.add(Memory(companion_id=c.id, content=m.content, source="inherited",
                      visibility="private", origin=m.origin or snap.publisher_name))
    snap.adopt_count += 1
    db.commit()
    return c.public_dict(memory_count=_snap_mem_count(db, sid))
