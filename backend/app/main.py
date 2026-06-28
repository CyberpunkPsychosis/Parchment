"""FLOW 后端入口。"""
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from .db import Base, engine, SessionLocal
from . import models  # noqa: F401  注册模型后再建表
from .routes import (auth_routes, chat_routes, membership, image_routes,
                     companion_routes, market_routes, group_routes, messaging_routes,
                     friends_routes, moments_routes, media_routes, search_routes,
                     block_routes, assistant_routes, admin_routes)
from .config import STORAGE_DIR
from .seed import seed_demo_market, seed_demo_groups

Base.metadata.create_all(bind=engine)
os.makedirs(STORAGE_DIR, exist_ok=True)


def _migrate():
    """给已存在的表补新列（SQLite create_all 不会自动加列）。"""
    with engine.connect() as conn:
        cols = [r[1] for r in conn.execute(text("PRAGMA table_info(companions)"))]
        for col in ("forked_from_snapshot_id", "published_snapshot_id"):
            if col not in cols:
                conn.execute(text(f"ALTER TABLE companions ADD COLUMN {col} INTEGER"))
        # 记忆归属（传承）列
        if "origin" not in [r[1] for r in conn.execute(text("PRAGMA table_info(memories)"))]:
            conn.execute(text("ALTER TABLE memories ADD COLUMN origin VARCHAR"))
        if "origin" not in [r[1] for r in conn.execute(text("PRAGMA table_info(snapshot_memories)"))]:
            conn.execute(text("ALTER TABLE snapshot_memories ADD COLUMN origin VARCHAR"))

        def _ensure(table: str, cols: dict):
            existing = [r[1] for r in conn.execute(text(f"PRAGMA table_info({table})"))]
            for name, decl in cols.items():
                if name not in existing:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {decl}"))

        # 体验完善新增列（表存在时才补；新表由 create_all 建）
        _ensure("companions", {"exp": "INTEGER", "exp_day": "VARCHAR", "exp_today": "INTEGER",
                               "avatar_url": "VARCHAR"})
        _ensure("messages", {"reply_to_id": "INTEGER"})
        _ensure("users", {"avatar_url": "VARCHAR", "bio": "VARCHAR"})
        _ensure("conversations", {"avatar": "VARCHAR", "member_cap": "INTEGER", "announcement": "VARCHAR"})
        _ensure("conversation_members", {"pinned": "BOOLEAN", "muted": "BOOLEAN"})
        _ensure("users", {"is_seed": "BOOLEAN", "is_admin": "BOOLEAN"})
        conn.commit()


_migrate()


def _bootstrap_admin(db):
    """按 .env 的 ADMIN_EMAIL/ADMIN_PASSWORD 引导一个管理员账号（幂等，凭证不进仓库）。"""
    from .config import ADMIN_EMAIL, ADMIN_PASSWORD
    from .models import User
    from .auth import hash_password
    if not ADMIN_EMAIL or not ADMIN_PASSWORD:
        return
    u = db.query(User).filter(User.email == ADMIN_EMAIL).first()
    if u:
        if not u.is_admin:
            u.is_admin = True
            db.commit()
        return
    db.add(User(email=ADMIN_EMAIL, password_hash=hash_password(ADMIN_PASSWORD),
                nickname="运营", is_admin=True))
    db.commit()
    print(f"[admin] 已创建管理员账号：{ADMIN_EMAIL}")


# demo 演示账号（环游的小云）已停用：不再注入 demo 市场搭子/社群
_db = SessionLocal()
try:
    # seed_demo_market(_db)   # 停用：不要 demo 用户及其市场搭子
    # seed_demo_groups(_db)   # 停用：不要 demo 用户及其社群
    _bootstrap_admin(_db)
    # 首批假用户 + 朋友圈（仅首次；之后由每日滑入持续补充）
    try:
        from .seed_population import seed_initial_population
        seed_initial_population(_db)
    except Exception as e:  # 素材缺失/网络等都不应阻断启动
        print(f"[seed] 初始假数据跳过：{e}")
finally:
    _db.close()

app = FastAPI(title="FLOW Backend", version="0.1.0")

# 静态资源（贴纸等转存文件）
app.mount("/media", StaticFiles(directory=STORAGE_DIR), name="media")

# 本地开发：放开 CORS（模拟器同机直连本就不受限，部署时再收紧）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_routes.router)
app.include_router(chat_routes.router)
app.include_router(membership.router)
app.include_router(image_routes.router)
app.include_router(companion_routes.router)
app.include_router(market_routes.router)
app.include_router(group_routes.router)
app.include_router(messaging_routes.router)
app.include_router(friends_routes.router)
app.include_router(moments_routes.router)
app.include_router(media_routes.router)
app.include_router(search_routes.router)
app.include_router(block_routes.router)
app.include_router(assistant_routes.router)
app.include_router(admin_routes.router)


@app.on_event("startup")
async def _start_daily_seed_loop():
    """每日自动滑入：后台 asyncio 循环，每 ~24h 跑一次 daily_tick（按天幂等，重启安全）。"""
    import asyncio
    from .config import SEED_DAILY_ENABLED, SEED_DAILY_USERS, SEED_DAILY_MOMENTS
    if not SEED_DAILY_ENABLED:
        return
    from .seed_population import daily_tick

    async def loop():
        while True:
            try:
                db = SessionLocal()
                try:
                    daily_tick(db, SEED_DAILY_USERS, SEED_DAILY_MOMENTS)
                finally:
                    db.close()
            except Exception as e:
                print(f"[seed] 每日滑入出错（忽略）：{e}")
            await asyncio.sleep(6 * 3600)   # 每 6 小时检查一次；按天幂等保证一天只灌一批

    asyncio.create_task(loop())


@app.get("/")
def health():
    return {"ok": True, "service": "flow-backend"}
