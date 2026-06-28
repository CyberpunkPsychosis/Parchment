"""集中配置：JWT、模型池（热加载）、每日用量上限。"""
import os
import json
from dotenv import load_dotenv

load_dotenv()

# --- JWT ---
JWT_SECRET = os.getenv("JWT_SECRET", "dev-change-me-please")
JWT_ALG = "HS256"
JWT_EXPIRE_DAYS = 30

# --- 对外可访问的后端地址（用于拼贴纸等静态资源的稳定 URL）---
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "http://localhost:8000")

# --- 本地存储目录（贴纸等转存到这里；上线换对象存储）---
STORAGE_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "storage")

# --- 每日 AI 调用上限（防刷爆成本）---
# 0 或负数 = 不限量。测试期默认全部放开；上线要限量时在 .env 设
# DAILY_LIMIT_FREE / DAILY_LIMIT_PRO（如 20 / 100）即可，无需改代码。
def _int_env(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, ""))
    except (TypeError, ValueError):
        return default

DAILY_LIMITS = {"free": _int_env("DAILY_LIMIT_FREE", 0),
                "pro": _int_env("DAILY_LIMIT_PRO", 0)}

# --- 运营管理员（启动时按 env 引导，凭证不进仓库）---
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "").strip()
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "").strip()

# --- 每日自动滑入假用户/朋友圈 ---
SEED_DAILY_ENABLED = os.getenv("SEED_DAILY_ENABLED", "true").strip().lower() != "false"
SEED_DAILY_USERS = _int_env("SEED_DAILY_USERS", 3)
SEED_DAILY_MOMENTS = _int_env("SEED_DAILY_MOMENTS", 8)

# --- 上下文截断：每次最多发给模型的历史消息条数（控制输入 token）---
MAX_CONTEXT_MESSAGES = 30

# --- 模型池（从 model_pool.json 热加载）---
_POOL_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "model_pool.json")
_pool_cache: dict = {}
_pool_mtime: float = 0.0

# 文件缺失时的兜底池
_DEFAULT_POOL = {
    "free": [{"provider": "zhipu", "base_url": "https://open.bigmodel.cn/api/paas/v4",
              "model": "glm-4-flash", "key_env": "ZHIPU_API_KEY"}],
    "pro": [{"provider": "zhipu", "base_url": "https://open.bigmodel.cn/api/paas/v4",
             "model": "glm-4-flash", "key_env": "ZHIPU_API_KEY"}],
}


def _load_pool() -> dict:
    """读取模型池，按 mtime 热重载（改 json 即时生效）。"""
    global _pool_cache, _pool_mtime
    try:
        mtime = os.path.getmtime(_POOL_PATH)
        if mtime != _pool_mtime or not _pool_cache:
            with open(_POOL_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
            _pool_cache = {k: v for k, v in data.items() if not k.startswith("_")}
            _pool_mtime = mtime
    except (OSError, json.JSONDecodeError):
        return _DEFAULT_POOL
    return _pool_cache or _DEFAULT_POOL


def pool_for(tier: str) -> list[dict]:
    """返回该 tier 的【有序、已配 key】的候选模型列表。
    跳过没配 key 的项；pro 没有任何可用项时回退到 free。空列表 → 调用方进入演示模式。"""
    pool = _load_pool()
    candidates = pool.get(tier) or pool.get("free") or []
    resolved = []
    for c in candidates:
        key = os.getenv(c.get("key_env", ""), "").strip()
        if key:
            resolved.append({**c, "api_key": key})
    if not resolved and tier != "free":
        return pool_for("free")
    return resolved
