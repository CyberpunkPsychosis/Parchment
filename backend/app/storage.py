"""资源转存。把第三方临时图片 URL 下载落地，返回稳定 URL。
本地存磁盘 + StaticFiles 提供；上线把 save_remote_image 换成传对象存储(OSS/S3)即可。"""
import os
import uuid
import httpx

from .config import STORAGE_DIR, PUBLIC_BASE_URL

_STICKER_DIR = os.path.join(STORAGE_DIR, "stickers")


def _ext_from(content_type: str, url: str) -> str:
    if "png" in content_type or url.lower().endswith(".png"):
        return "png"
    if "jpeg" in content_type or "jpg" in content_type or url.lower().endswith((".jpg", ".jpeg")):
        return "jpg"
    if "webp" in content_type:
        return "webp"
    return "png"


async def save_remote_image(url: str, subdir: str = "stickers") -> str | None:
    """下载远程图片落地，返回稳定 URL（失败返回 None）。"""
    target_dir = os.path.join(STORAGE_DIR, subdir)
    os.makedirs(target_dir, exist_ok=True)
    try:
        async with httpx.AsyncClient(timeout=60.0, trust_env=False) as client:
            resp = await client.get(url)
            if resp.status_code != 200:
                return None
            ext = _ext_from(resp.headers.get("content-type", ""), url)
            fname = f"{uuid.uuid4().hex}.{ext}"
            with open(os.path.join(target_dir, fname), "wb") as f:
                f.write(resp.content)
            return f"{PUBLIC_BASE_URL}/media/{subdir}/{fname}"
    except (httpx.HTTPError, OSError):
        return None
