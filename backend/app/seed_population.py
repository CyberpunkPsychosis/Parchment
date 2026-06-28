"""运营假用户的生成 / 每日滑入 / 级联清理。

- 假用户：User.is_seed=True，邮箱 fake_<uuid>@seed.parchment.app，随机密码。
- 朋友圈：以假用户身份发 Post，配图取自 seed_assets 素材池。
- 每日滑入：daily_tick 按天幂等（SeedState 记录），灌少量新用户 + 新朋友圈（当前时间）。
- 清理：purge_user / purge_all_seed 把假用户及其全部衍生数据级联删除。
"""
import os
import uuid
import random
from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from .auth import hash_password
from . import seed_assets
from .models import (User, Post, PostLike, PostComment, Companion, Memory,
                     CompanionAffinity, CompanionMilestone, CompanionDiary,
                     CompanionSnapshot, SnapshotMemory, Group, GroupMember,
                     Conversation, ConversationMember, Message,
                     Friendship, FriendRequest, Block, Report, AssistantMessage,
                     SeedState)

SEED_DOMAIN = "seed.parchment.app"

# —— 内容库（手写、自然、风格多样）——
_NICKNAMES = [
    "山间煮茶", "晚风收集者", "可颂不加糖", "胶片里的夏天", "麦田observer", "深夜放毒",
    "一只柯基的铲屎官", "把生活过成诗", "周末不上班", "热带鱼小姐", "阿宅的逆袭",
    "云朵收藏家", "慢半拍", "三分钟热度选手", "海边的卡夫卡迷", "今天也要元气满满",
    "咖啡因依赖症", "城南旧事", "野生设计师", "在逃猫咪", "Lemon七", "夜跑选手老王",
    "面包与远方", "不务正业插画师", "南方有乔木", "考研倒计时", "健身房常客",
    "陈大白", "爱睡觉的考拉", "雨天读诗", "代码与吉他", "旅行的意义", "豆浆配油条",
    "小满未满", "林深时见鹿", "凌晨四点的城市", "种花的人", "微醺时刻",
    "二两清欢", "宝藏男孩阿亮",
]
_BIOS = [
    "记录平平无奇但值得的一天。", "热爱生活，偶尔丧。", "用脚步丈量世界。",
    "美食是治愈一切的良药。", "做个温柔且有力量的人。", "把日子过成喜欢的样子。",
    "摄影 / 旅行 / 猫。", "代码写得好，咖啡喝得饱。", "努力成为更好的自己。",
    "晚安是世界上最温柔的情话。", "今天也在认真生活。", "慢慢来，比较快。",
    "人间值得，奶茶也值得。", "在路上，永远年轻。", "保持热爱，奔赴山海。",
    "平凡日子里的小确幸。", "不爱说话，但爱拍照。", "理想主义者的现实生活。",
    "减肥从明天开始。", "和喜欢的一切在一起。",
]
# 朋友圈文案库（按主题混合）
_MOMENTS = [
    "今天的晚霞美到不真实，停下脚步看了好久。",
    "周末去爬了趟山，腿废了但值了，山顶的风太治愈。",
    "新学的这道菜居然成功了！色香味俱全（自夸）。",
    "下雨天，窝在家里看完了一整本书，久违的松弛感。",
    "猫主子今天破天荒地黏人，被治愈到了。",
    "加班到现在，但项目终于上线了，撒花🎈（划掉）。",
    "城市的夜跑路线又解锁一条，多巴胺拉满。",
    "咖啡店挖到宝，这家的手冲真的绝，已列入常去名单。",
    "整理了房间，扔掉一堆没用的东西，心情都跟着清爽了。",
    "和老友吃了顿火锅，三个小时没停过嘴，太久没这么开心了。",
    "通勤路上随手拍的，原来每天路过的地方也这么好看。",
    "尝试早睡第一天，失败。但至少躺下了（？）。",
    "海边真的有种魔力，看着浪一波波涌过来，烦恼都被带走了。",
    "今天被一个陌生人的善意暖到，世界还是很可爱的。",
    "终于把拖了半个月的健身计划重启了，肌肉酸爽。",
    "买了束花放在桌上，瞬间觉得生活精致了起来。",
    "深夜放毒：刚出炉的可颂，外酥里软，幸福感爆棚。",
    "假期最后一天，给自己冲杯茶，安静地发会儿呆。",
    "学吉他第30天，终于能完整弹一首了，成就感满满。",
    "今天的工作很顺，奖励自己一顿好的，明天继续。",
    "路过菜市场，烟火气扑面而来，这才是生活本来的样子。",
    "下班看到这片天空，决定绕远路多走两站。",
    "好久没写字了，提笔却不知从何说起，但还是想记录这一刻。",
    "周末和朋友去看了展，被治愈也被启发，灵感回来了。",
    "今天降温了，记得多穿点，照顾好自己呀。",
]
_COMMENTS = [
    "也太好看了吧！", "求定位～", "羡慕了", "好治愈", "拍得真好",
    "哈哈哈哈太真实了", "下次带上我", "学到了", "保重身体呀", "同款心情",
    "好有氛围感", "看饿了", "加油！", "美美哒", "想去想去",
]
_CITIES = ["北京", "上海", "深圳", "广州", "成都", "杭州", "武汉", "西安",
           "重庆", "南京", "长沙", "苏州", "天津", "青岛", "厦门", "昆明"]


def _make_email() -> str:
    return f"fake_{uuid.uuid4().hex[:12]}@{SEED_DOMAIN}"


def create_fake_user(db: Session, nickname: str | None = None, bio: str | None = None,
                     avatar_url: str | None = None, city: str | None = None,
                     idx: int | None = None) -> User:
    """建一个假用户（is_seed=True）。头像默认留空（由运营自行设置），城市均匀轮转分配。"""
    if idx is None:
        idx = random.randint(0, 9999)
    u = User(
        email=_make_email(),
        password_hash=hash_password(uuid.uuid4().hex),  # 随机密码，无人登录
        nickname=nickname or random.choice(_NICKNAMES),
        bio=bio if bio is not None else random.choice(_BIOS),
        avatar_url=avatar_url or None,           # 不自动生成头像，运营后台再设
        city=city or _CITIES[idx % len(_CITIES)],   # 城市均匀分布
        is_seed=True,
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def post_moment_as(db: Session, author: User, content: str,
                   image_url: str | None = None, created_at: datetime | None = None,
                   location: str | None = None) -> Post:
    p = Post(author_id=author.id, author_name=author.nickname,
             content=content, image_url=image_url,
             location=location if location is not None else author.city,  # 默认标作者城市
             created_at=created_at or datetime.utcnow())
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def _seed_users(db: Session) -> list[User]:
    return db.query(User).filter(User.is_seed == True).all()  # noqa: E712


def seed_initial_population(db: Session, users: int = 20, moments: int = 50) -> dict:
    """首次建一批假用户 + 错峰朋友圈（仅当还没有假用户时）。"""
    if db.query(User).filter(User.is_seed == True).first():  # noqa: E712
        return {"skipped": True}
    made_users = [create_fake_user(db, idx=i) for i in range(users)]
    now = datetime.utcnow()
    # 文案洗牌轮转，尽量不重复
    bank = _MOMENTS[:]; random.shuffle(bank)
    posts = []
    for i in range(moments):
        author = random.choice(made_users)
        # 近 ~20 天内错峰
        ts = now - timedelta(days=random.randint(0, 20), hours=random.randint(0, 23),
                             minutes=random.randint(0, 59))
        # 配图留空（由运营在后台设置）；地点默认作者城市
        posts.append(post_moment_as(db, author, bank[i % len(bank)], None, ts))
    _add_likes_and_comments(db, made_users, posts)
    print(f"[seed] 首批注入假用户 {len(made_users)} 位、朋友圈 {len(posts)} 条")
    return {"users": len(made_users), "moments": len(posts)}


def _add_likes_and_comments(db: Session, users: list[User], posts: list[Post]):
    """给帖子加点赞 + 少量评论，更像活人。"""
    if not users:
        return
    for p in posts:
        # 点赞：随机若干假用户（不含作者）
        likers = random.sample(users, k=min(len(users), random.randint(0, 6)))
        for u in likers:
            if u.id == p.author_id:
                continue
            if not db.query(PostLike).filter(PostLike.post_id == p.id, PostLike.user_id == u.id).first():
                db.add(PostLike(post_id=p.id, user_id=u.id))
        # 约 1/3 概率配 1-2 条评论
        if random.random() < 0.33:
            for c in random.sample(users, k=min(len(users), random.randint(1, 2))):
                if c.id == p.author_id:
                    continue
                db.add(PostComment(post_id=p.id, user_id=c.id, user_name=c.nickname,
                                   content=random.choice(_COMMENTS)))
    db.commit()


def generate_users(db: Session, count: int) -> list[User]:
    """随机批量生成假用户，每人带 1 条当前时间的朋友圈。"""
    out = []
    base = db.query(User).filter(User.is_seed == True).count()  # noqa: E712
    for k in range(count):
        u = create_fake_user(db, idx=base + k)
        post_moment_as(db, u, random.choice(_MOMENTS), None)   # 配图留空，运营后台再设
        out.append(u)
    return out


def _today() -> str:
    return datetime.utcnow().strftime("%Y-%m-%d")


def daily_tick(db: Session, n_users: int, n_moments: int, force: bool = False) -> dict:
    """每日滑入：按天幂等。建 n_users 个新假用户 + n_moments 条当前时间朋友圈。"""
    st = db.query(SeedState).filter(SeedState.key == "last_tick_day").first()
    if not force and st and st.value == _today():
        return {"skipped": True, "reason": "already ran today"}

    new_users = generate_users(db, n_users) if n_users > 0 else []
    pool = _seed_users(db)
    posts = []
    for i in range(n_moments):
        if not pool:
            break
        author = random.choice(pool)
        posts.append(post_moment_as(db, author, random.choice(_MOMENTS), None))
    _add_likes_and_comments(db, pool, posts)

    if st:
        st.value = _today(); st.updated_at = datetime.utcnow()
    else:
        db.add(SeedState(key="last_tick_day", value=_today()))
    db.commit()
    print(f"[seed] 每日滑入：新假用户 {len(new_users)}、新朋友圈 {len(posts)}")
    return {"new_users": len(new_users), "new_moments": len(posts)}


def purge_user(db: Session, uid: int) -> None:
    """级联删除某用户（假用户）及其全部衍生数据。"""
    # 朋友圈（本人发的）+ 其帖下的赞/评论
    my_posts = [p.id for p in db.query(Post).filter(Post.author_id == uid).all()]
    if my_posts:
        db.query(PostLike).filter(PostLike.post_id.in_(my_posts)).delete(synchronize_session=False)
        db.query(PostComment).filter(PostComment.post_id.in_(my_posts)).delete(synchronize_session=False)
        db.query(Post).filter(Post.id.in_(my_posts)).delete(synchronize_session=False)
    # 本人在别处的赞/评论
    db.query(PostLike).filter(PostLike.user_id == uid).delete(synchronize_session=False)
    db.query(PostComment).filter(PostComment.user_id == uid).delete(synchronize_session=False)
    # 搭子及其衍生
    comp_ids = [c.id for c in db.query(Companion).filter(Companion.owner_id == uid).all()]
    if comp_ids:
        db.query(Memory).filter(Memory.companion_id.in_(comp_ids)).delete(synchronize_session=False)
        db.query(CompanionAffinity).filter(CompanionAffinity.companion_id.in_(comp_ids)).delete(synchronize_session=False)
        db.query(CompanionMilestone).filter(CompanionMilestone.companion_id.in_(comp_ids)).delete(synchronize_session=False)
        db.query(CompanionDiary).filter(CompanionDiary.companion_id.in_(comp_ids)).delete(synchronize_session=False)
        snap_ids = [s.id for s in db.query(CompanionSnapshot).filter(CompanionSnapshot.source_companion_id.in_(comp_ids)).all()]
        if snap_ids:
            db.query(SnapshotMemory).filter(SnapshotMemory.snapshot_id.in_(snap_ids)).delete(synchronize_session=False)
            db.query(CompanionSnapshot).filter(CompanionSnapshot.id.in_(snap_ids)).delete(synchronize_session=False)
        db.query(ConversationMember).filter(ConversationMember.companion_id.in_(comp_ids)).delete(synchronize_session=False)
        db.query(Companion).filter(Companion.id.in_(comp_ids)).delete(synchronize_session=False)
    # 拥有的群（连同成员、会话、消息）
    grp_ids = [g.id for g in db.query(Group).filter(Group.owner_id == uid).all()]
    if grp_ids:
        db.query(GroupMember).filter(GroupMember.group_id.in_(grp_ids)).delete(synchronize_session=False)
        convs = [c.id for c in db.query(Conversation).filter(Conversation.group_id.in_(grp_ids)).all()]
        if convs:
            db.query(Message).filter(Message.conversation_id.in_(convs)).delete(synchronize_session=False)
            db.query(ConversationMember).filter(ConversationMember.conversation_id.in_(convs)).delete(synchronize_session=False)
            db.query(Conversation).filter(Conversation.id.in_(convs)).delete(synchronize_session=False)
        db.query(Group).filter(Group.id.in_(grp_ids)).delete(synchronize_session=False)
    # 群成员身份 / 会话成员 / 好友 / 消息 / 助手记录 / 拉黑举报
    db.query(GroupMember).filter(GroupMember.user_id == uid).delete(synchronize_session=False)
    db.query(ConversationMember).filter(ConversationMember.user_id == uid).delete(synchronize_session=False)
    db.query(Message).filter(Message.sender_user_id == uid).delete(synchronize_session=False)
    db.query(Friendship).filter((Friendship.user_a == uid) | (Friendship.user_b == uid)).delete(synchronize_session=False)
    db.query(FriendRequest).filter((FriendRequest.from_user_id == uid) | (FriendRequest.to_user_id == uid)).delete(synchronize_session=False)
    db.query(Block).filter((Block.user_id == uid) | (Block.blocked_id == uid)).delete(synchronize_session=False)
    db.query(Report).filter(Report.reporter_id == uid).delete(synchronize_session=False)
    db.query(AssistantMessage).filter(AssistantMessage.user_id == uid).delete(synchronize_session=False)
    db.query(User).filter(User.id == uid).delete(synchronize_session=False)
    db.commit()


def purge_all_seed(db: Session) -> int:
    ids = [u.id for u in db.query(User).filter(User.is_seed == True).all()]  # noqa: E712
    for uid in ids:
        purge_user(db, uid)
    return len(ids)
