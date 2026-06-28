"""通用图片上传：存到 /media/uploads，返回稳定 URL。朋友圈配图 / 聊天发图共用。"""
import os
import uuid
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException

from ..deps import get_current_user
from ..models import User
from ..config import STORAGE_DIR, PUBLIC_BASE_URL

router = APIRouter(tags=["media"])

_ALLOWED = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif"}
_MAX = 8 * 1024 * 1024  # 8MB

# 语音消息音频
_AUDIO = {"audio/m4a": "m4a", "audio/mp4": "m4a", "audio/x-m4a": "m4a",
          "audio/aac": "aac", "audio/mpeg": "mp3", "audio/wav": "wav",
          "audio/x-wav": "wav", "audio/webm": "webm"}
_MAX_AUDIO = 16 * 1024 * 1024  # 16MB


def _save(data: bytes, ext: str) -> str:
    target = os.path.join(STORAGE_DIR, "uploads")
    os.makedirs(target, exist_ok=True)
    name = f"{uuid.uuid4().hex}.{ext}"
    with open(os.path.join(target, name), "wb") as f:
        f.write(data)
    return f"{PUBLIC_BASE_URL}/media/uploads/{name}"


@router.post("/upload/image")
async def upload_image(file: UploadFile = File(...), user: User = Depends(get_current_user)):
    ext = _ALLOWED.get(file.content_type or "")
    if not ext:
        raise HTTPException(status_code=400, detail="仅支持 png/jpg/webp/gif")
    data = await file.read()
    if len(data) > _MAX:
        raise HTTPException(status_code=413, detail="图片过大（>8MB）")
    return {"url": _save(data, ext)}


@router.post("/upload/audio")
async def upload_audio(file: UploadFile = File(...), user: User = Depends(get_current_user)):
    """语音消息音频上传。返回稳定 URL；前端再带上时长拼成 content。"""
    ext = _AUDIO.get((file.content_type or "").lower(), "m4a")
    data = await file.read()
    if len(data) > _MAX_AUDIO:
        raise HTTPException(status_code=413, detail="音频过大（>16MB）")
    return {"url": _save(data, ext)}
