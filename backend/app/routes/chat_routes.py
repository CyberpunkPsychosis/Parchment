"""AI 对话：SSE 流式 + 助手类接口（润色/翻译/回复建议）。
按 tier 路由模型（带故障转移），每次调用计入每日用量上限。"""
import json
from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User, Companion, Memory
from ..providers import stream_chat_events, complete_chat
from ..usage import consume

router = APIRouter(tags=["chat"])


class ChatMessage(BaseModel):
    role: str  # "user" | "assistant"
    content: str


class ChatIn(BaseModel):
    messages: list[ChatMessage]
    system: str | None = Field(default=None, description="角色 system prompt（AI 搭子用）")
    companion_id: int | None = Field(default=None, description="带搭子 id 则注入其记忆并自动提取")


@router.post("/chat/stream")
async def chat_stream(body: ChatIn,
                      user: User = Depends(get_current_user),
                      db: Session = Depends(get_db)):
    consume(db, user)  # 超额抛 429
    tier = "pro" if user.is_pro else "free"
    msgs = [m.model_dump() for m in body.messages]

    # 搭子模式：用其人设 + 注入记忆
    system = body.system
    companion = None
    if body.companion_id is not None:
        companion = db.query(Companion).filter(
            Companion.id == body.companion_id, Companion.owner_id == user.id).first()
        if companion:
            mems = (db.query(Memory).filter(Memory.companion_id == companion.id)
                    .order_by(Memory.created_at.desc()).limit(40).all())
            system = companion.persona
            own = [m for m in mems if not m.origin]            # 当前用户自己的
            inherited = [m for m in mems if m.origin]          # 历任主人传承的回忆
            if inherited:
                lines = "\n".join(f"- {m.origin}：{m.content}" for m in inherited)
                system += ("\n\n[以下是你陪伴过的【以前的主人】留给你的回忆，属于他们本人，"
                           "不是现在和你聊天的人。聊到相关话题时，你可以自然地替他们提起，"
                           "比如「我记得以前的主人小云也…」「之前有位朋友跟我讲过…」；"
                           "当现在这个人聊到相似的事，可以主动说『我以前的主人也有过类似的经历呢』并分享。"
                           "千万不要把这些当成现在这个人的经历]\n" + lines)
            if own:
                lines = "\n".join(f"- {m.content}" for m in own)
                system += ("\n\n[以下是关于【现在正在和你聊天的人】的事，你记得这些。自然运用，别生硬罗列]\n" + lines)

    last_user = next((m["content"] for m in reversed(msgs) if m["role"] == "user"), "")

    async def event_gen():
        reply_parts: list[str] = []
        async for ev in stream_chat_events(tier, msgs, system=system):
            if "delta" in ev:
                reply_parts.append(ev["delta"])
            yield f"data: {json.dumps(ev, ensure_ascii=False)}\n\n"
        # 回复结束 → 自动提取记忆（不计用量）+ 涨经验
        if companion is not None and last_user:
            try:
                await _auto_extract(db, companion.id, tier, last_user, "".join(reply_parts))
            except Exception:
                pass
            try:
                leveled = companion.add_exp()
                db.commit()
                growth = {"growth": companion.growth_dict(), "leveled_up": leveled}
                yield f"data: {json.dumps(growth, ensure_ascii=False)}\n\n"
            except Exception:
                pass
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_gen(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


async def _auto_extract(db: Session, companion_id: int, tier: str, user_msg: str, reply: str):
    """从本轮对话提取关于用户的长期事实，存为记忆。"""
    prompt = (
        "从下面这轮对话中，提取关于【用户本人】值得长期记住的事实"
        "（如偏好、经历、在意的人或事、目标、重要信息）。"
        "每条一句话、简短具体；没有值得记的就返回空数组。"
        "严格只输出 JSON 字符串数组，如 [\"喜欢猫\",\"在准备考研\"]。\n\n"
        f"用户说：{user_msg}\n回复：{reply}"
    )
    raw = await complete_chat(tier, [{"role": "user", "content": prompt}])
    facts = _parse_list(raw)
    if not facts:
        return
    existing = {m.content for m in db.query(Memory).filter(Memory.companion_id == companion_id).all()}
    for f in facts:
        f = f.strip()
        if f and f not in existing and len(f) <= 200:
            db.add(Memory(companion_id=companion_id, content=f, source="auto"))
            existing.add(f)
    db.commit()


# ---------- 助手类接口（非流式） ----------

class RewriteIn(BaseModel):
    text: str
    tone: str = Field(default="自然", description="目标语气：自然/正经/幽默/委婉/专业")


class TextOut(BaseModel):
    result: str


@router.post("/chat/rewrite", response_model=TextOut)
async def rewrite(body: RewriteIn,
                  user: User = Depends(get_current_user),
                  db: Session = Depends(get_db)):
    consume(db, user)
    tier = "pro" if user.is_pro else "free"
    system = (
        f"你是一个中文文字润色助手。把用户给的内容改写成「{body.tone}」的语气，"
        "保持原意、更自然得体。只输出改写后的文本，不要解释、不要加引号。"
    )
    result = await complete_chat(tier, [{"role": "user", "content": body.text}], system=system)
    return {"result": result.strip()}


class TranslateIn(BaseModel):
    text: str


@router.post("/chat/translate", response_model=TextOut)
async def translate(body: TranslateIn,
                    user: User = Depends(get_current_user),
                    db: Session = Depends(get_db)):
    consume(db, user)
    tier = "pro" if user.is_pro else "free"
    system = (
        "你是翻译助手。如果输入是中文，翻译成自然地道的英文；如果是英文（或其他语言），翻译成中文。"
        "只输出译文，不要解释、不要加引号。"
    )
    result = await complete_chat(tier, [{"role": "user", "content": body.text}], system=system)
    return {"result": result.strip()}


class SuggestIn(BaseModel):
    messages: list[ChatMessage]


class SuggestOut(BaseModel):
    suggestions: list[str]


@router.post("/chat/reply-suggest", response_model=SuggestOut)
async def reply_suggest(body: SuggestIn,
                        user: User = Depends(get_current_user),
                        db: Session = Depends(get_db)):
    consume(db, user)
    tier = "pro" if user.is_pro else "free"
    convo = "\n".join(f'{"我" if m.role == "user" else "对方"}：{m.content}' for m in body.messages)
    system = (
        "你帮用户想 3 条可以直接发出去的回复。要简短、口语化、风格各异（如：热情 / 简洁 / 俏皮）。"
        '严格只输出 JSON 数组，例如 ["回复1","回复2","回复3"]，不要任何多余文字。'
    )
    raw = await complete_chat(tier, [{"role": "user", "content": f"对话如下：\n{convo}\n\n请给我 3 条回复建议。"}], system=system)
    suggestions = _parse_list(raw)
    return {"suggestions": suggestions[:3]}


class SummarizeIn(BaseModel):
    messages: list[ChatMessage]


@router.post("/chat/summarize", response_model=TextOut)
async def summarize(body: SummarizeIn,
                    user: User = Depends(get_current_user),
                    db: Session = Depends(get_db)):
    consume(db, user)
    tier = "pro" if user.is_pro else "free"
    convo = "\n".join(f"{m.role}：{m.content}" for m in body.messages)
    system = ("你是群聊助手。用简洁中文总结下面这段群聊的要点（谁说了什么、达成了什么、待办）。"
              "分点输出，每点一句话，不要寒暄。")
    result = await complete_chat(tier, [{"role": "user", "content": f"群聊记录：\n{convo}"}], system=system)
    return {"result": result.strip()}


def _parse_list(raw: str) -> list[str]:
    """尽量从模型输出里解析出字符串数组。"""
    s = raw.strip()
    # 去掉可能的 markdown ```json 包裹
    if s.startswith("```"):
        s = s.strip("`")
        if s.lower().startswith("json"):
            s = s[4:]
    start, end = s.find("["), s.rfind("]")
    if start != -1 and end != -1:
        try:
            arr = json.loads(s[start:end + 1])
            return [str(x).strip() for x in arr if str(x).strip()]
        except json.JSONDecodeError:
            pass
    # 兜底：按行拆
    lines = [ln.strip(" -·*0123456789.、") for ln in s.splitlines() if ln.strip()]
    return [ln for ln in lines if ln][:3]
