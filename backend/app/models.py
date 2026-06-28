"""数据模型。User + 每日用量计数。会话历史暂不落库（无状态对话）。"""
from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, UniqueConstraint, Boolean
from .db import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    nickname = Column(String, nullable=False, default="")
    tier = Column(String, nullable=False, default="free")  # "free" | "pro"
    tier_expiry = Column(DateTime, nullable=True)
    auto_send_stickers = Column(Boolean, nullable=True)  # None=未选择(首次询问), True/False=已记住偏好
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    @property
    def is_pro(self) -> bool:
        """会员且未过期才算 pro。"""
        if self.tier != "pro":
            return False
        if self.tier_expiry and self.tier_expiry < datetime.utcnow():
            return False
        return True

    def public_dict(self) -> dict:
        return {
            "id": self.id,
            "email": self.email,
            "nickname": self.nickname,
            "tier": "pro" if self.is_pro else "free",
            "tier_expiry": self.tier_expiry.isoformat() if self.tier_expiry else None,
            "auto_send_stickers": self.auto_send_stickers,  # null=首次未选
        }


class DailyUsage(Base):
    __tablename__ = "daily_usage"
    __table_args__ = (UniqueConstraint("user_id", "day", name="uq_user_day"),)

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True, nullable=False)
    day = Column(String, nullable=False)   # "YYYY-MM-DD"
    count = Column(Integer, nullable=False, default=0)


class Companion(Base):
    """AI 搭子。归属某用户；含认领预留字段（parent_id / visibility）。"""
    __tablename__ = "companions"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, index=True, nullable=False)
    name = Column(String, nullable=False)
    persona = Column(String, nullable=False, default="")   # system prompt
    avatar = Column(String, nullable=False, default="AI")  # 头像首字
    tint = Column(String, nullable=False, default="teal")  # 颜色 key
    greeting = Column(String, nullable=False, default="")
    # —— 认领（Phase 9）——
    parent_id = Column(Integer, nullable=True)             # fork 来源搭子
    forked_from_snapshot_id = Column(Integer, nullable=True)  # 认领自哪个快照
    published_snapshot_id = Column(Integer, nullable=True)    # 当前发布的快照（None=未发布）
    visibility = Column(String, nullable=False, default="private")  # private | published
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def public_dict(self, memory_count: int = 0) -> dict:
        return {
            "id": self.id, "name": self.name, "persona": self.persona,
            "avatar": self.avatar, "tint": self.tint, "greeting": self.greeting,
            "visibility": self.visibility, "memory_count": memory_count,
            "published": self.published_snapshot_id is not None,
            "adopted": self.forked_from_snapshot_id is not None,
        }


class Memory(Base):
    """搭子记忆。逐条可标可见性（为认领的隐私控制铺路）。"""
    __tablename__ = "memories"

    id = Column(Integer, primary_key=True, index=True)
    companion_id = Column(Integer, index=True, nullable=False)
    content = Column(String, nullable=False)
    source = Column(String, nullable=False, default="auto")        # auto | manual | inherited
    visibility = Column(String, nullable=False, default="private") # private | shareable
    origin = Column(String, nullable=True)   # None=当前用户自己的；否则=来自哪位前任主人(名字)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def public_dict(self) -> dict:
        return {"id": self.id, "content": self.content, "source": self.source,
                "visibility": self.visibility, "origin": self.origin,
                "created_at": self.created_at.isoformat()}


class CompanionSnapshot(Base):
    """发布的搭子快照（可被认领的冻结版）。形成传承链。"""
    __tablename__ = "companion_snapshots"

    id = Column(Integer, primary_key=True, index=True)
    publisher_id = Column(Integer, index=True, nullable=False)
    publisher_name = Column(String, nullable=False, default="")
    source_companion_id = Column(Integer, nullable=True)
    parent_snapshot_id = Column(Integer, nullable=True)   # 上一代快照（传承）
    name = Column(String, nullable=False)
    persona = Column(String, nullable=False, default="")
    avatar = Column(String, nullable=False, default="AI")
    tint = Column(String, nullable=False, default="teal")
    greeting = Column(String, nullable=False, default="")
    lineage_depth = Column(Integer, nullable=False, default=0)
    adopt_count = Column(Integer, nullable=False, default=0)
    active = Column(Integer, nullable=False, default=1)    # 0=已下架
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def public_dict(self, memory_count: int = 0, is_mine: bool = False) -> dict:
        return {
            "id": self.id, "name": self.name, "persona": self.persona,
            "avatar": self.avatar, "tint": self.tint, "greeting": self.greeting,
            "publisher_name": self.publisher_name,
            "lineage_depth": self.lineage_depth, "adopt_count": self.adopt_count,
            "memory_count": memory_count, "is_mine": is_mine,
        }


class SnapshotMemory(Base):
    """快照里冻结的记忆（发布时从 shareable 记忆复制）。"""
    __tablename__ = "snapshot_memories"

    id = Column(Integer, primary_key=True, index=True)
    snapshot_id = Column(Integer, index=True, nullable=False)
    content = Column(String, nullable=False)
    origin = Column(String, nullable=True)   # 这条回忆来自哪位主人(名字)，构成传承


class Group(Base):
    """群组（广场可发现 / 可加入）。"""
    __tablename__ = "groups"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, index=True, nullable=False)
    owner_name = Column(String, nullable=False, default="")
    name = Column(String, nullable=False)
    description = Column(String, nullable=False, default="")
    avatar = Column(String, nullable=False, default="群")
    tint = Column(String, nullable=False, default="teal")
    join_mode = Column(String, nullable=False, default="open")  # open | code | approval
    member_cap = Column(Integer, nullable=False, default=200)
    invite_code = Column(String, nullable=False, default="")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def public_dict(self, member_count: int = 0, is_member: bool = False,
                    pending: bool = False, is_owner: bool = False) -> dict:
        return {
            "id": self.id, "name": self.name, "description": self.description,
            "avatar": self.avatar, "tint": self.tint, "join_mode": self.join_mode,
            "member_cap": self.member_cap, "member_count": member_count,
            "owner_name": self.owner_name, "is_member": is_member,
            "pending": pending, "is_owner": is_owner,
            "invite_code": self.invite_code if is_owner else None,
        }


class GroupMember(Base):
    __tablename__ = "group_members"

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, index=True, nullable=False)
    user_id = Column(Integer, index=True, nullable=False)
    joined_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class GroupJoinRequest(Base):
    __tablename__ = "group_join_requests"

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, index=True, nullable=False)
    user_id = Column(Integer, index=True, nullable=False)
    user_name = Column(String, nullable=False, default="")
    status = Column(String, nullable=False, default="pending")  # pending | approved | rejected
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class Sticker(Base):
    __tablename__ = "stickers"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True, nullable=False)
    url = Column(String, nullable=False)        # 稳定 URL（已转存到本地/对象存储）
    prompt = Column(String, nullable=False, default="")
    is_favorite = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def public_dict(self) -> dict:
        return {
            "id": self.id,
            "url": self.url,
            "prompt": self.prompt,
            "is_favorite": self.is_favorite,
            "created_at": self.created_at.isoformat(),
        }
