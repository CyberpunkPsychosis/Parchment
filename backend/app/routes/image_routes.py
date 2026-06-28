"""手绘贴纸：文生图(CogView-3-Flash 免费) + 转存 + 表情包库。"""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User, Sticker
from ..providers import generate_image, complete_chat
from ..storage import save_remote_image
from ..usage import consume

router = APIRouter(tags=["sticker"])

# 干净可爱的卡通贴纸风：纯白背景、主体清晰，避免发黄/抽象
_STYLE = ("可爱的卡通贴纸，手绘插画风格，线条清晰流畅，色彩明亮干净，"
          "纯白色背景，主体居中、完整、清晰可辨，简洁不杂乱，无文字。画的是：")


class CtxMessage(BaseModel):
    role: str
    content: str


class StickerIn(BaseModel):
    prompt: str = Field(default="", max_length=200)
    # 传了最近对话则按语境生成（prompt 可作为额外要求/留空）
    context: list[CtxMessage] | None = None


@router.post("/image/sticker")
async def create_sticker(body: StickerIn,
                         user: User = Depends(get_current_user),
                         db: Session = Depends(get_db)):
    consume(db, user)  # 计入每日用量；超额 429
    tier = "pro" if user.is_pro else "free"

    # 1) 决定画面描述
    description = body.prompt.strip()
    if body.context:
        convo = "\n".join(f'{"我" if m.role == "user" else "对方"}：{m.content}' for m in body.context[-6:])
        extra = f"用户还特别要求：{description}。" if description else ""
        description = await complete_chat(tier, [{
            "role": "user",
            "content": (
                "你是表情包创意师。下面是一段聊天，请聚焦【最后一条消息】的情绪与话题，"
                "构思一个最贴切、好玩、能直接发出去的表情包画面。"
                "只输出一句简短中文画面描述（主体 + 表情/动作），不要解释、不要引号、不要标点结尾。\n\n"
                f"聊天：\n{convo}\n\n{extra}")
        }])
        description = description.strip().strip("。.\n\"' ")
    if not description:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="请给出贴纸描述")

    # 2) 出图
    temp_url = await generate_image(_STYLE + description)
    if not temp_url:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="生成失败，请稍后再试")

    # 3) 转存为稳定 URL（防过期）
    stable_url = await save_remote_image(temp_url) or temp_url

    # 4) 入库（"最近发送"按 created_at 倒序）
    sticker = Sticker(user_id=user.id, url=stable_url, prompt=description)
    db.add(sticker)
    db.commit()
    db.refresh(sticker)
    return sticker.public_dict()


@router.get("/stickers")
def list_stickers(favorite: bool = False,
                  user: User = Depends(get_current_user),
                  db: Session = Depends(get_db)):
    q = db.query(Sticker).filter(Sticker.user_id == user.id)
    if favorite:
        q = q.filter(Sticker.is_favorite == True)  # noqa: E712
    rows = q.order_by(Sticker.created_at.desc()).limit(100).all()
    return {"stickers": [s.public_dict() for s in rows]}


@router.post("/stickers/{sticker_id}/favorite")
def toggle_favorite(sticker_id: int,
                    user: User = Depends(get_current_user),
                    db: Session = Depends(get_db)):
    s = db.query(Sticker).filter(Sticker.id == sticker_id, Sticker.user_id == user.id).first()
    if not s:
        raise HTTPException(status_code=404, detail="贴纸不存在")
    s.is_favorite = not s.is_favorite
    db.commit()
    return s.public_dict()


@router.delete("/stickers/{sticker_id}")
def delete_sticker(sticker_id: int,
                   user: User = Depends(get_current_user),
                   db: Session = Depends(get_db)):
    s = db.query(Sticker).filter(Sticker.id == sticker_id, Sticker.user_id == user.id).first()
    if not s:
        raise HTTPException(status_code=404, detail="贴纸不存在")
    db.delete(s)
    db.commit()
    return {"ok": True}
