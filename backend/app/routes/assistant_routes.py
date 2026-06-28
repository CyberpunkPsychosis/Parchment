"""羊皮纸助手：自然语言 → 站内动作。
MVP 工具：answer（直接回答）/ send_message（发到某会话）/ post_moment（发朋友圈）/ summarize（总结某群）。
有副作用的动作（发消息/发朋友圈）只返回"提案"，由客户端确认后再调既有接口执行；
只读动作（总结/回答/分析/联网搜索）后端直接给结果。联网搜索复用智谱 web-search-pro。"""
import os
import json
import uuid
import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import (User, Conversation, ConversationMember, Message, Post, Group, GroupMember,
                      Companion, Memory, AssistantMessage)
from ..providers import complete_chat
from ..usage import consume
from .messaging_routes import conv_dict, serialize_message

router = APIRouter(tags=["assistant"])

_ZHIPU_TOOLS_URL = "https://open.bigmodel.cn/api/paas/v4/tools"


async def _web_search(query: str) -> str | None:
    """复用智谱 web-search-pro 联网搜索（沿用 ZHIPU_API_KEY，无需新 key）。失败/未配 key 返回 None。"""
    key = os.getenv("ZHIPU_API_KEY", "").strip()
    if not key or not query.strip():
        return None
    payload = {"request_id": uuid.uuid4().hex, "tool": "web-search-pro",
               "stream": False, "messages": [{"role": "user", "content": query.strip()}]}
    try:
        async with httpx.AsyncClient(timeout=30.0, trust_env=False) as client:
            r = await client.post(_ZHIPU_TOOLS_URL, json=payload,
                                  headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
            if r.status_code != 200:
                return None
            data = r.json()
    except (httpx.HTTPError, ValueError):
        return None
    found: list = []

    def collect(o):
        if isinstance(o, dict):
            sr = o.get("search_result")
            if isinstance(sr, list):
                found.extend(sr)
            for v in o.values():
                collect(v)
        elif isinstance(o, list):
            for v in o:
                collect(v)
    collect(data)
    lines = []
    for it in found[:5]:
        if not isinstance(it, dict):
            continue
        title = (it.get("title") or "").strip()
        content = (it.get("content") or it.get("snippet") or "").strip()[:300]
        link = (it.get("link") or it.get("url") or "").strip()
        lines.append(f"- {title}\n  {content}\n  {link}")
    return "\n".join(lines) if lines else None


def _my_conversations(db: Session, uid: int) -> list[dict]:
    """用户可作为动作目标的会话（群/私聊/搭子），给模型做名称匹配。"""
    ids = [m.conversation_id for m in db.query(ConversationMember)
           .filter(ConversationMember.user_id == uid).all()]
    rows = db.query(Conversation).filter(Conversation.id.in_(ids)).all() if ids else []
    out = []
    for c in rows:
        d = conv_dict(db, c, uid)
        out.append({"id": c.id, "title": d["title"], "type": c.type})
    return out


def _resolve(convs: list[dict], target: str) -> dict | None:
    """把模型给的 target（会话名或 id）解析成具体会话。"""
    if not target:
        return None
    t = str(target).strip()
    # 直接 id
    for c in convs:
        if t == str(c["id"]):
            return c
    # 精确名 → 包含 → 被包含
    for c in convs:
        if c["title"] == t:
            return c
    for c in convs:
        if t in c["title"] or c["title"] in t:
            return c
    return None


_SYS = """你是「羊皮纸助手」，帮用户在 App 内办事。根据用户的话，选择一个动作并严格只输出 JSON（不要多余文字、不要 markdown）：
- 闲聊/提问/查资料 → {"action":"answer","say":"你的回答"}
- 把一段话发到某个会话 → {"action":"send_message","target":"会话名","content":"要发送的内容","say":"对用户的确认话术"}
- 发一条朋友圈/动态 → {"action":"post_moment","content":"动态正文","say":"对用户的确认话术"}
- 总结/回顾某个群最近聊了什么 → {"action":"summarize","target":"群名","say":"好的，我看看"}
- 分析最近的朋友圈/动态（如"今天谁想出去玩""大家最近在聊啥"）→ {"action":"analyze_moments","say":"好的，我看看朋友圈"}
- 分析社群广场最近都有什么群/什么内容 → {"action":"analyze_plaza","say":"好的，我看看社群广场"}
- 需要查最新资讯/上网搜（如"搜下今天的新闻""查查XX是什么"）→ {"action":"search","query":"搜索关键词","say":"我去查查"}
- 先上网搜再发到某个群（如"搜条新闻发到家庭群"）→ {"action":"search_send","query":"搜索关键词","target":"群名","say":"好，我查完发给你确认"}
规则：target 必须从【会话列表】里选最匹配的名字；想不出具体动作就用 answer。say 用中文、简短自然。
【会话列表】：%s"""


def _assistant_voice(db: Session, uid: int) -> str:
    """让助手用"用户养的搭子"的口吻说话：取等级最高的那只，注入人设 + 几条记忆。"""
    comp = (db.query(Companion).filter(Companion.owner_id == uid)
            .order_by(Companion.exp.desc()).first())
    if not comp:
        return ("你是「羊皮纸助手」，像朋友一样口语化、简短、有活人感地帮用户。"
                "别像客服或百科。")
    mems = (db.query(Memory).filter(Memory.companion_id == comp.id, Memory.origin.is_(None))
            .order_by(Memory.created_at.desc()).limit(6).all())
    sys = (f"你是用户养的 AI 搭子「{comp.name}」，也是 ta 的贴身助手。{comp.persona}\n"
           "用第一人称、口语化、有活人感、简短地回答，像熟人那样；别像客服或百科。")
    if mems:
        sys += "\n[你还记得关于 ta 的一些事，聊到相关自然带上]\n" + "\n".join(f"- {m.content}" for m in mems)
    return sys


class ActIn(BaseModel):
    text: str = Field(min_length=1, max_length=1000)


def _parse_json(raw: str) -> dict:
    s = raw.strip()
    a, b = s.find("{"), s.rfind("}")
    if a == -1 or b == -1 or b < a:
        return {}
    try:
        d = json.loads(s[a:b + 1])
        return d if isinstance(d, dict) else {}
    except (ValueError, TypeError):
        return {}


def _history(db: Session, uid: int, limit: int = 10) -> list[dict]:
    """取该用户最近的助手对话（最旧在前），给模型做多轮上下文。"""
    rows = (db.query(AssistantMessage).filter(AssistantMessage.user_id == uid)
            .order_by(AssistantMessage.id.desc()).limit(limit).all())[::-1]
    return [{"role": m.role, "content": m.content} for m in rows]


def _save(db: Session, uid: int, role: str, content: str) -> None:
    content = (content or "").strip()
    if not content:
        return
    db.add(AssistantMessage(user_id=uid, role=role, content=content))
    db.commit()


@router.post("/assistant/act")
async def act(body: ActIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    consume(db, user)
    # 多轮上下文 + 聊天记录：先取历史，落本轮 user 文本，分派出结果后再落助手回复
    hist = _history(db, user.id)
    _save(db, user.id, "user", body.text)
    resp = await _dispatch(db, user, body, hist)
    _save(db, user.id, "assistant", resp.get("say", ""))
    return resp


async def _dispatch(db: Session, user: User, body: ActIn, hist: list[dict]) -> dict:
    tier = "pro" if user.is_pro else "free"
    voice = _assistant_voice(db, user.id)   # 用"用户养的搭子"的口吻
    convs = _my_conversations(db, user.id)
    conv_names = "、".join(c["title"] for c in convs) or "（暂无会话）"
    convo = hist + [{"role": "user", "content": body.text}]   # 历史 + 本轮，让指代可解析

    raw = await complete_chat(tier, convo, system=_SYS % conv_names)
    plan = _parse_json(raw)
    action = plan.get("action")
    say = (plan.get("say") or "").strip()

    if action == "send_message":
        target = _resolve(convs, plan.get("target", ""))
        content = (plan.get("content") or "").strip()
        if not target or not content:
            return {"kind": "answer", "say": say or "我没找到要发去的会话，或者没听清要发什么，能再说一次吗？"}
        return {"kind": "send_message", "conversation_id": target["id"],
                "conversation_title": target["title"], "content": content,
                "say": say or f"我准备把这条发到【{target['title']}】："}

    if action == "post_moment":
        content = (plan.get("content") or "").strip()
        if not content:
            return {"kind": "answer", "say": say or "你想发点什么到朋友圈呢？"}
        return {"kind": "post_moment", "content": content,
                "say": say or "我准备帮你发这条朋友圈："}

    if action == "summarize":
        target = _resolve(convs, plan.get("target", ""))
        if not target:
            return {"kind": "answer", "say": say or "你想让我总结哪个群呀？"}
        rows = (db.query(Message).filter(Message.conversation_id == target["id"], Message.kind == "text")
                .order_by(Message.created_at.desc()).limit(40).all())[::-1]
        if not rows:
            return {"kind": "answer", "say": f"【{target['title']}】最近还没什么消息可总结。"}
        lines = []
        for m in rows:
            who = serialize_message(db, m)["sender_name"]
            lines.append(f"{who}：{m.content}")
        summary = await complete_chat(tier, [{"role": "user", "content":
            "用简洁的要点总结下面这段群聊聊了什么：\n" + "\n".join(lines)}],
            system="你是羊皮纸助手，帮用户快速回顾群聊。")
        return {"kind": "summarize", "conversation_title": target["title"],
                "say": f"【{target['title']}】最近聊了：\n{summary.strip()}"}

    if action == "analyze_moments":
        posts = db.query(Post).order_by(Post.created_at.desc()).limit(50).all()
        if not posts:
            return {"kind": "answer", "say": "最近朋友圈还没什么动态可以分析～"}
        lines = [f"{p.author_name}：{p.content or '[图片]'}" for p in posts]
        result = await complete_chat(tier, [{"role": "user", "content":
            f"用户的要求：{body.text}\n\n下面是最近的朋友圈动态，请据此分析（点出具体是哪些人/哪些动态）：\n"
            + "\n".join(lines)}], system="你是羊皮纸助手，帮用户分析朋友圈动态，简洁、点名到人。")
        return {"kind": "analyze", "say": result.strip() or (say or "我看完啦～")}

    if action == "analyze_plaza":
        groups = db.query(Group).order_by(Group.created_at.desc()).limit(50).all()
        if not groups:
            return {"kind": "answer", "say": "社群广场现在还没什么群～"}
        lines = []
        for g in groups:
            n = db.query(GroupMember).filter(GroupMember.group_id == g.id).count()
            lines.append(f"{g.name}（{n}人）：{g.description or ''}")
        result = await complete_chat(tier, [{"role": "user", "content":
            f"用户的要求：{body.text}\n\n下面是社群广场最近的群，请据此分析最近都流行/聚集了什么内容：\n"
            + "\n".join(lines)}], system="你是羊皮纸助手，帮用户洞察社群广场的趋势，简洁。")
        return {"kind": "analyze", "say": result.strip() or (say or "我看完啦～")}

    if action == "search":
        q = (plan.get("query") or body.text).strip()
        results = await _web_search(q)
        if not results:
            return {"kind": "answer", "say": "联网搜索现在没查到结果（或后端未配置智谱 ZHIPU_API_KEY）。"}
        answer = await complete_chat(tier, [{"role": "user", "content":
            f"用户的问题：{body.text}\n\n下面是联网搜到的资料，请据此简洁回答，并在末尾附 1-3 条来源链接：\n{results}"}],
            system=voice + "\n根据下面联网搜索结果回答，准确、给出来源。", temperature=0.5)
        return {"kind": "answer", "say": answer.strip() or "我查到一些资料～"}

    if action == "search_send":
        target = _resolve(convs, plan.get("target", ""))
        q = (plan.get("query") or body.text).strip()
        if not target:
            return {"kind": "answer", "say": say or "你想把搜到的内容发到哪个群呀？"}
        results = await _web_search(q)
        if not results:
            return {"kind": "answer", "say": "联网搜索现在没查到结果（或后端未配置智谱 ZHIPU_API_KEY）。"}
        msg = await complete_chat(tier, [{"role": "user", "content":
            f"把下面联网搜到的资料整理成一条适合直接发到群里的简短消息（不超过 120 字，可带 1 条链接）：\n{results}"}],
            system="你是羊皮纸助手，把资讯整理成可直接转发的简短群消息。", temperature=0.5)
        msg = msg.strip()
        if not msg:
            return {"kind": "answer", "say": "我查到了，但没整理出合适的内容，要不直接说要发啥？"}
        return {"kind": "send_message", "conversation_id": target["id"],
                "conversation_title": target["title"], "content": msg,
                "say": f"我查好了，准备发到【{target['title']}】："}

    # 默认：直接回答（用搭子的口吻，带多轮上下文）
    answer = await complete_chat(tier, convo, system=voice, temperature=0.9)
    return {"kind": "answer", "say": answer.strip() or say or "嗯，我在听～"}


@router.get("/assistant/history")
def assistant_history(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """助手聊天记录（最旧在前）。"""
    rows = (db.query(AssistantMessage).filter(AssistantMessage.user_id == user.id)
            .order_by(AssistantMessage.id.asc()).all())
    return {"messages": [m.public_dict() for m in rows]}


@router.delete("/assistant/history")
def clear_assistant_history(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """清空助手聊天记录。"""
    db.query(AssistantMessage).filter(AssistantMessage.user_id == user.id).delete()
    db.commit()
    return {"ok": True}
