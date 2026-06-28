"""数据模型。User + 每日用量计数。会话历史暂不落库（无状态对话）。"""
import math
from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, UniqueConstraint, Boolean
from .db import Base

# —— 搭子成长（共同养成核心）——
EXP_PER_REPLY = 6      # 搭子每次回复获得的经验
EXP_DAILY_CAP = 120    # 单只搭子每日经验上限（防刷）
_STAGES = ["幼年", "成长", "成熟", "羁绊"]


def companion_level(exp: int) -> int:
    """由经验派生等级：升级所需经验递增（Lv 起点经验 = 50*(L-1)^2）。"""
    return int(math.sqrt(max(0, exp) / 50.0)) + 1


def companion_stage(level: int) -> str:
    if level >= 15:
        return _STAGES[3]
    if level >= 8:
        return _STAGES[2]
    if level >= 3:
        return _STAGES[1]
    return _STAGES[0]


def level_exp_bounds(level: int) -> tuple[int, int]:
    """该等级的起点经验与下一级所需经验。"""
    return 50 * (level - 1) ** 2, 50 * level ** 2


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    nickname = Column(String, nullable=False, default="")
    avatar_url = Column(String, nullable=True)   # 真实头像（无则前端用首字母）
    bio = Column(String, nullable=True)          # 个性签名
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
            "avatar_url": self.avatar_url,
            "bio": self.bio,
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
    avatar_url = Column(String, nullable=True)             # 自定义头像图（可空）
    tint = Column(String, nullable=False, default="teal")  # 颜色 key
    greeting = Column(String, nullable=False, default="")
    # —— 认领（Phase 9）——
    parent_id = Column(Integer, nullable=True)             # fork 来源搭子
    forked_from_snapshot_id = Column(Integer, nullable=True)  # 认领自哪个快照
    published_snapshot_id = Column(Integer, nullable=True)    # 当前发布的快照（None=未发布）
    visibility = Column(String, nullable=False, default="private")  # private | published
    # —— 成长系统 ——
    exp = Column(Integer, nullable=False, default=0)
    exp_day = Column(String, nullable=True)        # 最近一次计经验的日期(YYYY-MM-DD)
    exp_today = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def add_exp(self, amount: int = EXP_PER_REPLY) -> bool:
        """加经验（按天封顶）。返回是否因此升级。"""
        today = datetime.utcnow().date().isoformat()
        if self.exp_day != today:
            self.exp_day = today
            self.exp_today = 0
        room = max(0, EXP_DAILY_CAP - (self.exp_today or 0))
        gained = min(amount, room)
        if gained <= 0:
            return False
        before = companion_level(self.exp or 0)
        self.exp = (self.exp or 0) + gained
        self.exp_today = (self.exp_today or 0) + gained
        return companion_level(self.exp) > before

    def growth_dict(self) -> dict:
        exp = self.exp or 0
        level = companion_level(exp)
        lo, hi = level_exp_bounds(level)
        return {
            "exp": exp, "level": level, "stage": companion_stage(level),
            "level_min_exp": lo, "level_max_exp": hi,
        }

    def public_dict(self, memory_count: int = 0) -> dict:
        return {
            "id": self.id, "name": self.name, "persona": self.persona,
            "avatar": self.avatar, "avatar_url": self.avatar_url,
            "tint": self.tint, "greeting": self.greeting,
            "visibility": self.visibility, "memory_count": memory_count,
            "published": self.published_snapshot_id is not None,
            "adopted": self.forked_from_snapshot_id is not None,
            **self.growth_dict(),
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

    def public_dict(self, memory_count: int = 0, is_mine: bool = False,
                    already_adopted: bool = False) -> dict:
        return {
            "id": self.id, "name": self.name, "persona": self.persona,
            "avatar": self.avatar, "tint": self.tint, "greeting": self.greeting,
            "publisher_name": self.publisher_name,
            "lineage_depth": self.lineage_depth, "adopt_count": self.adopt_count,
            "memory_count": memory_count, "is_mine": is_mine,
            "already_adopted": already_adopted,
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


class Friendship(Base):
    """双向好友关系（存一行，user_a < user_b 去重）。"""
    __tablename__ = "friendships"
    __table_args__ = (UniqueConstraint("user_a", "user_b", name="uq_friend_pair"),)

    id = Column(Integer, primary_key=True, index=True)
    user_a = Column(Integer, index=True, nullable=False)
    user_b = Column(Integer, index=True, nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class FriendRequest(Base):
    __tablename__ = "friend_requests"

    id = Column(Integer, primary_key=True, index=True)
    from_user_id = Column(Integer, index=True, nullable=False)
    from_user_name = Column(String, nullable=False, default="")
    to_user_id = Column(Integer, index=True, nullable=False)
    status = Column(String, nullable=False, default="pending")  # pending | accepted | rejected
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class Conversation(Base):
    """统一会话：私聊 / 群聊 / 搭子。所有聊天都落在这里。"""
    __tablename__ = "conversations"

    id = Column(Integer, primary_key=True, index=True)
    type = Column(String, nullable=False, default="direct")  # direct | group | companion
    group_id = Column(Integer, nullable=True, index=True)    # type=group 时关联 groups.id
    title = Column(String, nullable=False, default="")       # 可选缓存标题
    avatar = Column(String, nullable=True)                   # 好友群头像
    member_cap = Column(Integer, nullable=True)              # 好友群人数上限（None=用默认）
    announcement = Column(String, nullable=True)             # 群公告
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)  # 末条消息时间，用于排序


class ConversationMember(Base):
    """会话成员：可以是人(user_id)或 AI 搭子(companion_id)。"""
    __tablename__ = "conversation_members"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(Integer, index=True, nullable=False)
    user_id = Column(Integer, index=True, nullable=True)        # 人类成员
    companion_id = Column(Integer, index=True, nullable=True)   # AI 搭子成员（阶段 4）
    role = Column(String, nullable=False, default="member")     # owner | member
    last_read_at = Column(DateTime, nullable=True)              # 已读水位（算未读）
    pinned = Column(Boolean, nullable=True)                     # 置顶
    muted = Column(Boolean, nullable=True)                      # 免打扰
    joined_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class Message(Base):
    """带发送者身份的消息（支持多人 + AI 同框）。"""
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(Integer, index=True, nullable=False)
    sender_user_id = Column(Integer, index=True, nullable=True)      # 人发的
    sender_companion_id = Column(Integer, index=True, nullable=True) # AI 搭子发的
    kind = Column(String, nullable=False, default="text")  # text|image|sticker|file|voice|system|companion
    content = Column(String, nullable=False, default="")   # 文本 / URL / JSON / "url|duration"(voice)
    reply_to_id = Column(Integer, nullable=True, index=True)  # 引用的消息
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class MessageReaction(Base):
    __tablename__ = "message_reactions"
    __table_args__ = (UniqueConstraint("message_id", "user_id", "emoji", name="uq_msg_react"),)

    id = Column(Integer, primary_key=True, index=True)
    message_id = Column(Integer, index=True, nullable=False)
    user_id = Column(Integer, index=True, nullable=False)
    emoji = Column(String, nullable=False)


class Post(Base):
    """朋友圈动态。"""
    __tablename__ = "posts"

    id = Column(Integer, primary_key=True, index=True)
    author_id = Column(Integer, index=True, nullable=False)
    author_name = Column(String, nullable=False, default="")
    content = Column(String, nullable=False, default="")
    image_url = Column(String, nullable=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class PostLike(Base):
    __tablename__ = "post_likes"
    __table_args__ = (UniqueConstraint("post_id", "user_id", name="uq_post_like"),)

    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, index=True, nullable=False)
    user_id = Column(Integer, index=True, nullable=False)


class PostComment(Base):
    __tablename__ = "post_comments"

    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, index=True, nullable=False)
    user_id = Column(Integer, index=True, nullable=False)
    user_name = Column(String, nullable=False, default="")
    content = Column(String, nullable=False, default="")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class DeviceToken(Base):
    """推送设备 token（APNs）。真实投递需配置 Apple 推送密钥。"""
    __tablename__ = "device_tokens"
    __table_args__ = (UniqueConstraint("token", name="uq_device_token"),)

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True, nullable=False)
    token = Column(String, nullable=False)
    platform = Column(String, nullable=False, default="ios")
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


class CompanionAffinity(Base):
    """每个用户与某搭子的亲密度（共同养成里"我和它有多熟"）。"""
    __tablename__ = "companion_affinity"
    __table_args__ = (UniqueConstraint("companion_id", "user_id", name="uq_affinity"),)

    id = Column(Integer, primary_key=True, index=True)
    companion_id = Column(Integer, index=True, nullable=False)
    user_id = Column(Integer, index=True, nullable=False)
    points = Column(Integer, nullable=False, default=0)
    aff_day = Column(String, nullable=True)        # 当日计点日期(防刷)
    aff_today = Column(Integer, nullable=False, default=0)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def bump(self, amount: int = 3, daily_cap: int = 60) -> int:
        today = datetime.utcnow().date().isoformat()
        if self.aff_day != today:
            self.aff_day = today
            self.aff_today = 0
        room = max(0, daily_cap - (self.aff_today or 0))
        gained = min(amount, room)
        self.points = (self.points or 0) + gained
        self.aff_today = (self.aff_today or 0) + gained
        self.updated_at = datetime.utcnow()
        return self.points

    def public_dict(self) -> dict:
        pts = self.points or 0
        level = companion_level(pts)   # 复用同一曲线展示"亲密等级"
        lo, hi = level_exp_bounds(level)
        return {"points": pts, "level": level, "level_min": lo, "level_max": hi}


class CompanionMilestone(Base):
    """搭子里程碑/纪念（首次聊天、升级、相伴 N 天）。"""
    __tablename__ = "companion_milestones"

    id = Column(Integer, primary_key=True, index=True)
    companion_id = Column(Integer, index=True, nullable=False)
    kind = Column(String, nullable=False, default="")   # first_chat | level_up | days_N
    content = Column(String, nullable=False, default="")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def public_dict(self) -> dict:
        return {"id": self.id, "kind": self.kind, "content": self.content,
                "created_at": self.created_at.isoformat()}


class CompanionDiary(Base):
    """搭子成长日记/动态（升级、里程碑时由模型写一句）。"""
    __tablename__ = "companion_diary"

    id = Column(Integer, primary_key=True, index=True)
    companion_id = Column(Integer, index=True, nullable=False)
    content = Column(String, nullable=False, default="")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    def public_dict(self) -> dict:
        return {"id": self.id, "content": self.content,
                "created_at": self.created_at.isoformat()}


class Block(Base):
    """拉黑：user_id 拉黑了 blocked_id。"""
    __tablename__ = "blocks"
    __table_args__ = (UniqueConstraint("user_id", "blocked_id", name="uq_block"),)

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True, nullable=False)
    blocked_id = Column(Integer, index=True, nullable=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)


class Report(Base):
    """举报：用户 / 消息 / 群 等。"""
    __tablename__ = "reports"

    id = Column(Integer, primary_key=True, index=True)
    reporter_id = Column(Integer, index=True, nullable=False)
    target_type = Column(String, nullable=False, default="user")  # user | message | group | post
    target_id = Column(Integer, nullable=False)
    reason = Column(String, nullable=False, default="")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
