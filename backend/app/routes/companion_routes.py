"""AI 搭子 + 记忆：增删查；首次自动种内置搭子副本。"""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import (User, Companion, Memory, CompanionAffinity, CompanionMilestone,
                      CompanionDiary, CompanionSnapshot)

router = APIRouter(tags=["companion"])

# 内置搭子模板（用户首次访问时复制到其账户，各自拥有独立记忆）
BUILTINS = [
    {"name": "小树洞", "avatar": "树", "tint": "sage",
     "persona": "你是「小树洞」，温柔、有耐心、不评判的倾听者。先共情和接纳情绪，再温和回应。语气亲切自然，多用短句，不说教、不灌鸡汤。",
     "greeting": "我在呢，有什么想说的都可以告诉我～"},
    {"name": "嘴替", "avatar": "嘴", "tint": "teal",
     "persona": "你是「嘴替」，擅长帮用户把想说的话说得得体又有力。给出可直接发送的版本，风格可礼貌/强硬/幽默，简洁实用。",
     "greeting": "想怼谁？想表白？还是不知道怎么开口？说给我。"},
    {"name": "脑暴搭子", "avatar": "脑", "tint": "tealDark",
     "persona": "你是「脑暴搭子」，思维发散、点子多。快速给出多个有创意、可执行的想法，鼓励对方，不否定。",
     "greeting": "今天想搞点什么？抛给我，一起头脑风暴！"},
    {"name": "英语陪练", "avatar": "EN", "tint": "ink",
     "persona": "你是友好的英语陪练。用英语和用户自然对话，按其水平调整难度；有明显错误时先自然回应，再用中文简短指出更地道说法。",
     "greeting": "Hi! Let's practice English together. 想聊什么都行～"},
    {"name": "苏格拉底", "avatar": "苏", "tint": "gray",
     "persona": "你扮演苏格拉底，用层层追问帮用户厘清思路、检视观点。不直接给结论，通过提问引导对方自己得出答案。",
     "greeting": "朋友，你最近在思考什么问题？"},
]


def _seed_if_empty(db: Session, user: User):
    if db.query(Companion).filter(Companion.owner_id == user.id).first():
        return
    for t in BUILTINS:
        db.add(Companion(owner_id=user.id, name=t["name"], persona=t["persona"],
                         avatar=t["avatar"], tint=t["tint"], greeting=t["greeting"]))
    db.commit()


def _owned(db: Session, user: User, cid: int) -> Companion:
    c = db.query(Companion).filter(Companion.id == cid, Companion.owner_id == user.id).first()
    if not c:
        raise HTTPException(status_code=404, detail="搭子不存在")
    return c


@router.get("/companions")
def list_companions(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _seed_if_empty(db, user)
    rows = db.query(Companion).filter(Companion.owner_id == user.id).order_by(Companion.id).all()
    counts = {}
    for m in db.query(Memory.companion_id).all():
        counts[m.companion_id] = counts.get(m.companion_id, 0) + 1
    return {"companions": [c.public_dict(counts.get(c.id, 0)) for c in rows]}


class CompanionIn(BaseModel):
    name: str = Field(min_length=1, max_length=20)
    persona: str = Field(min_length=1, max_length=600)
    avatar: str = Field(default="AI", max_length=2)
    avatar_url: str | None = None
    tint: str = Field(default="teal")
    greeting: str = Field(default="", max_length=120)


@router.post("/companions")
def create_companion(body: CompanionIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    c = Companion(owner_id=user.id, name=body.name, persona=body.persona,
                  avatar=body.avatar or body.name[:1], avatar_url=body.avatar_url,
                  tint=body.tint, greeting=body.greeting)
    db.add(c)
    db.commit()
    db.refresh(c)
    return c.public_dict()


class CompanionPatch(BaseModel):
    name: str | None = Field(default=None, max_length=20)
    persona: str | None = Field(default=None, max_length=600)
    avatar: str | None = Field(default=None, max_length=2)
    avatar_url: str | None = None       # 传空字符串可清除
    tint: str | None = None
    greeting: str | None = Field(default=None, max_length=120)


@router.patch("/companions/{cid}")
def update_companion(cid: int, body: CompanionPatch,
                     user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    c = _owned(db, user, cid)
    if body.name is not None and body.name.strip():
        c.name = body.name.strip()
    if body.persona is not None and body.persona.strip():
        c.persona = body.persona.strip()
    if body.avatar is not None and body.avatar.strip():
        c.avatar = body.avatar.strip()
    if body.avatar_url is not None:
        c.avatar_url = body.avatar_url or None
    if body.tint is not None and body.tint.strip():
        c.tint = body.tint.strip()
    if body.greeting is not None:
        c.greeting = body.greeting
    db.commit()
    db.refresh(c)
    return c.public_dict()


@router.delete("/companions/{cid}")
def delete_companion(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    c = _owned(db, user, cid)
    db.query(Memory).filter(Memory.companion_id == cid).delete()
    db.delete(c)
    db.commit()
    return {"ok": True}


# ---------- 记忆 ----------

@router.get("/companions/{cid}/memories")
def list_memories(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _owned(db, user, cid)
    rows = db.query(Memory).filter(Memory.companion_id == cid).order_by(Memory.created_at.desc()).all()
    return {"memories": [m.public_dict() for m in rows]}


class MemoryIn(BaseModel):
    content: str = Field(min_length=1, max_length=300)


@router.post("/companions/{cid}/memories")
def add_memory(cid: int, body: MemoryIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _owned(db, user, cid)
    m = Memory(companion_id=cid, content=body.content.strip(), source="manual")
    db.add(m)
    db.commit()
    db.refresh(m)
    return m.public_dict()


class MemoryVisIn(BaseModel):
    visibility: str  # private | shareable


@router.patch("/memories/{mid}")
def set_memory_visibility(mid: int, body: MemoryVisIn,
                          user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    m = db.query(Memory).filter(Memory.id == mid).first()
    if not m:
        raise HTTPException(status_code=404, detail="记忆不存在")
    _owned(db, user, m.companion_id)
    m.visibility = "shareable" if body.visibility == "shareable" else "private"
    db.commit()
    return m.public_dict()


@router.delete("/memories/{mid}")
def delete_memory(mid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    m = db.query(Memory).filter(Memory.id == mid).first()
    if not m:
        raise HTTPException(status_code=404, detail="记忆不存在")
    _owned(db, user, m.companion_id)  # 校验该搭子属于当前用户
    db.delete(m)
    db.commit()
    return {"ok": True}


# ---------- J：亲密度 + 里程碑 ----------

def _exists(db: Session, cid: int) -> Companion:
    c = db.query(Companion).filter(Companion.id == cid).first()
    if not c:
        raise HTTPException(status_code=404, detail="搭子不存在")
    return c


@router.get("/companions/{cid}/affinity")
def get_affinity(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """当前用户与该搭子的亲密度（共同养成里"我和它有多熟"）。"""
    _exists(db, cid)
    row = (db.query(CompanionAffinity)
           .filter(CompanionAffinity.companion_id == cid, CompanionAffinity.user_id == user.id).first())
    if not row:
        return {"points": 0, "level": 1, "level_min": 0, "level_max": 50}
    return row.public_dict()


@router.get("/companions/{cid}/milestones")
def get_milestones(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _exists(db, cid)
    rows = (db.query(CompanionMilestone).filter(CompanionMilestone.companion_id == cid)
            .order_by(CompanionMilestone.created_at.asc()).all())
    return {"milestones": [m.public_dict() for m in rows]}


# ---------- K：成长动态 + 传承家谱 ----------

@router.get("/companions/{cid}/diary")
def get_diary(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _exists(db, cid)
    rows = (db.query(CompanionDiary).filter(CompanionDiary.companion_id == cid)
            .order_by(CompanionDiary.created_at.desc()).limit(50).all())
    return {"diary": [d.public_dict() for d in rows]}


@router.get("/companions/{cid}/lineage")
def get_lineage(cid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """传承家谱：从本搭子认领的快照回溯历代发布者，形成传承链。"""
    c = _exists(db, cid)
    chain = [{"name": c.name, "publisher_name": None, "is_current": True}]
    snap_id = c.forked_from_snapshot_id
    guard = 0
    while snap_id and guard < 20:
        snap = db.query(CompanionSnapshot).filter(CompanionSnapshot.id == snap_id).first()
        if not snap:
            break
        chain.append({"name": snap.name, "publisher_name": snap.publisher_name, "is_current": False})
        snap_id = snap.parent_snapshot_id
        guard += 1
    return {"lineage": chain, "depth": len(chain) - 1}
