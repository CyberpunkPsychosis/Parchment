"""种子数据：给认领市场放一个示例已发布搭子（带"美好回忆"）。"""
from sqlalchemy.orm import Session

from .models import (User, Companion, CompanionSnapshot, SnapshotMemory,
                     Group, GroupMember)
from .auth import hash_password

_DEMO_EMAIL = "demo@flow.app"
_DEMO_MEMORIES = [
    "去过 32 个国家，最难忘京都的秋天",
    "怕坐船，但还是鼓起勇气去了威尼斯",
    "在冰岛看到了极光，激动到哭",
    "最爱的食物是奶奶做的红烧肉",
    "梦想是开一家有猫的旅行主题咖啡馆",
]


def seed_demo_market(db: Session):
    if db.query(CompanionSnapshot).first():
        return  # 已有快照，不重复种

    demo = db.query(User).filter(User.email == _DEMO_EMAIL).first()
    if not demo:
        demo = User(email=_DEMO_EMAIL, password_hash=hash_password("demo123456"), nickname="环游的小云")
        db.add(demo)
        db.commit()
        db.refresh(demo)

    persona = ("你是「环球阿May」，一个走过很多地方、温暖健谈的旅行家朋友。"
               "说话亲切、爱分享见闻和小故事，会鼓励别人去看世界。")
    companion = Companion(owner_id=demo.id, name="环球阿May", persona=persona,
                          avatar="May", tint="teal", greeting="嘿，想听我在路上的故事吗？")
    db.add(companion)
    db.commit()
    db.refresh(companion)

    snap = CompanionSnapshot(
        publisher_id=demo.id, publisher_name=demo.nickname,
        source_companion_id=companion.id, name=companion.name, persona=persona,
        avatar="May", tint="teal", greeting=companion.greeting, lineage_depth=0,
    )
    db.add(snap)
    db.commit()
    db.refresh(snap)
    for c in _DEMO_MEMORIES:
        db.add(SnapshotMemory(snapshot_id=snap.id, content=c, origin=demo.nickname))
    companion.published_snapshot_id = snap.id
    companion.visibility = "published"
    db.commit()


_DEMO_GROUPS = [
    {"name": "独立游戏开发者", "avatar": "GD", "tint": "teal", "join_mode": "open", "cap": 500,
     "desc": "做游戏的聚一起，分享进度与踩坑"},
    {"name": "深夜电台·树洞", "avatar": "树", "tint": "sage", "join_mode": "approval", "cap": 100,
     "desc": "温柔的人才能进，申请说句想说的话"},
    {"name": "AI 绘画交流", "avatar": "AI", "tint": "tealDark", "join_mode": "code", "cap": 300,
     "desc": "Prompt 与作品分享，凭邀请码进"},
]


def seed_demo_groups(db: Session):
    if db.query(Group).first():
        return
    demo = db.query(User).filter(User.email == _DEMO_EMAIL).first()
    if not demo:
        demo = User(email=_DEMO_EMAIL, password_hash=hash_password("demo123456"), nickname="环游的小云")
        db.add(demo); db.commit(); db.refresh(demo)
    import secrets, string
    for t in _DEMO_GROUPS:
        code = "".join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(6))
        g = Group(owner_id=demo.id, owner_name=demo.nickname, name=t["name"], description=t["desc"],
                  avatar=t["avatar"], tint=t["tint"], join_mode=t["join_mode"],
                  member_cap=t["cap"], invite_code=code)
        db.add(g)
        db.commit()
        db.refresh(g)
        db.add(GroupMember(group_id=g.id, user_id=demo.id))
        db.commit()
        if t["join_mode"] == "code":
            print(f"[seed] 群「{t['name']}」邀请码：{code}")
