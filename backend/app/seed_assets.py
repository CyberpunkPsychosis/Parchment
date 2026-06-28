"""运营种子素材池：随仓库提交的真实占位照片（JPG），由后端自己托管。

seed_assets/avatars/*.jpg、seed_assets/moments/*.jpg 随 git 走（国内可访问）。
首次使用时拷到 STORAGE_DIR/seed/ → 经 /media 静态挂载对外，URL 形如
{PUBLIC_BASE_URL}/media/seed/<file>。pick_* 轮换取图，尽量少重复。
"""
import os
import shutil

from .config import STORAGE_DIR, PUBLIC_BASE_URL

_ASSETS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "seed_assets")
_SEED_STORAGE = os.path.join(STORAGE_DIR, "seed")

_avatars: list[str] = []
_moments: list[str] = []
_ready = False


def _ensure_ready():
    """把素材池拷进 STORAGE_DIR/seed/（缺则拷），并缓存文件名列表。幂等。"""
    global _ready, _avatars, _moments
    if _ready:
        return
    os.makedirs(_SEED_STORAGE, exist_ok=True)
    for sub in ("avatars", "moments"):
        src_dir = os.path.join(_ASSETS_DIR, sub)
        if not os.path.isdir(src_dir):
            continue
        for fn in sorted(os.listdir(src_dir)):
            if not fn.lower().endswith((".jpg", ".jpeg", ".png")):
                continue
            dst = os.path.join(_SEED_STORAGE, f"{sub}_{fn}")
            if not os.path.exists(dst):
                try:
                    shutil.copyfile(os.path.join(src_dir, fn), dst)
                except OSError:
                    continue
            (_avatars if sub == "avatars" else _moments).append(f"{sub}_{fn}")
    _ready = True


def _url(name: str) -> str:
    return f"{PUBLIC_BASE_URL}/media/seed/{name}"


def has_assets() -> bool:
    _ensure_ready()
    return bool(_avatars)


def pick_avatar(i: int) -> str | None:
    """按序号轮换取一个头像 URL。"""
    _ensure_ready()
    if not _avatars:
        return None
    return _url(_avatars[i % len(_avatars)])


def pick_moment(i: int) -> str | None:
    """按序号轮换取一张朋友圈配图 URL。"""
    _ensure_ready()
    if not _moments:
        return None
    return _url(_moments[i % len(_moments)])


def avatar_count() -> int:
    _ensure_ready()
    return len(_avatars)
