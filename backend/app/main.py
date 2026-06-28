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
                     friends_routes, moments_routes, media_routes, search_routes)
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
        _ensure("companions", {"exp": "INTEGER", "exp_day": "VARCHAR", "exp_today": "INTEGER"})
        _ensure("users", {"avatar_url": "VARCHAR", "bio": "VARCHAR"})
        _ensure("conversations", {"avatar": "VARCHAR", "member_cap": "INTEGER", "announcement": "VARCHAR"})
        _ensure("conversation_members", {"pinned": "BOOLEAN", "muted": "BOOLEAN"})
        conn.commit()


_migrate()

# 种一个 demo 已发布搭子，让认领市场不空
_db = SessionLocal()
try:
    seed_demo_market(_db)
    seed_demo_groups(_db)
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


@app.get("/")
def health():
    return {"ok": True, "service": "flow-backend"}
