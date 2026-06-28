"""统一 LLM 客户端（OpenAI 兼容）+ 故障转移。
按 tier 的模型池有序尝试：主模型连不上/超时/限流就自动切下一个，用户无感。
全部不可用或没配 key 时走演示回声，保证链路不断。"""
import json
import asyncio
from typing import AsyncGenerator

import httpx

from .config import pool_for, MAX_CONTEXT_MESSAGES


def _partial_suffix_len(s: str, tag: str) -> int:
    """s 结尾处与 tag 开头重叠的最长长度（用于跨分片识别半个标签）。"""
    for k in range(min(len(s), len(tag) - 1), 0, -1):
        if s.endswith(tag[:k]):
            return k
    return 0


class _ThinkFilter:
    """流式剥离 <think>...</think> 推理块。
    MiniMax-M2、deepseek-reasoner 等推理模型会把思考过程内联进 content，
    用户不该看到。逐 delta 喂入，跨分片的半个标签也能正确处理。"""
    OPEN, CLOSE = "<think>", "</think>"

    def __init__(self):
        self.buf = ""
        self.in_think = False
        self.started = False  # 是否已吐出首个非空白字符（用于吃掉 </think> 后的前导空行）

    def _emit(self, s: str) -> str:
        if not self.started:
            s = s.lstrip()
            if s:
                self.started = True
        return s

    def feed(self, delta: str) -> str:
        self.buf += delta
        out = ""
        while self.buf:
            if not self.in_think:
                i = self.buf.find(self.OPEN)
                if i != -1:
                    out += self._emit(self.buf[:i])
                    self.buf = self.buf[i + len(self.OPEN):]
                    self.in_think = True
                    continue
                cut = _partial_suffix_len(self.buf, self.OPEN)
                out += self._emit(self.buf[:len(self.buf) - cut])
                self.buf = self.buf[len(self.buf) - cut:]
                break
            i = self.buf.find(self.CLOSE)
            if i != -1:
                self.buf = self.buf[i + len(self.CLOSE):]
                self.in_think = False
                continue
            cut = _partial_suffix_len(self.buf, self.CLOSE)
            self.buf = self.buf[len(self.buf) - cut:]
            break
        return out

    def flush(self) -> str:
        out = "" if self.in_think else self._emit(self.buf)
        self.buf = ""
        return out


async def stream_chat_events(tier: str, messages: list[dict],
                             system: str | None = None,
                             temperature: float | None = None) -> AsyncGenerator[dict, None]:
    """逐事件 yield：先 {"meta":{...}} 告知实际使用的模型，再若干 {"delta": "..."}。
    temperature 给"活人感"留口子：搭子聊天调高(更随性)，提取/JSON 任务调低(更稳)。"""
    # 上下文截断，控制输入 token
    trimmed = messages[-MAX_CONTEXT_MESSAGES:]
    full = ([{"role": "system", "content": system}] if system else []) + trimmed

    pool = pool_for(tier)

    for idx, cfg in enumerate(pool):
        # chat_path 可覆盖默认路径；extra 可并入额外请求参数（如 MiniMax 的 thinking 开关）
        url = f'{cfg["base_url"]}{cfg.get("chat_path", "/chat/completions")}'
        headers = {"Authorization": f'Bearer {cfg["api_key"]}', "Content-Type": "application/json"}
        payload = {"model": cfg["model"], "messages": full, "stream": True}
        if temperature is not None:
            payload["temperature"] = temperature
        if isinstance(cfg.get("extra"), dict):
            payload.update(cfg["extra"])
        try:
            async with httpx.AsyncClient(timeout=60.0, trust_env=False) as client:
                async with client.stream("POST", url, headers=headers, json=payload) as resp:
                    if resp.status_code != 200:
                        # 该模型不可用 → 故障转移到下一个
                        await resp.aread()
                        continue
                    # 拿到正常响应，开始产出
                    yield {"meta": {"model": cfg["model"], "provider": cfg["provider"],
                                    "tier": tier, "failover": idx > 0}}
                    filt = _ThinkFilter()  # 剥离推理模型的 <think> 块
                    async for line in resp.aiter_lines():
                        if not line or not line.startswith("data:"):
                            continue
                        data = line[len("data:"):].strip()
                        if data == "[DONE]":
                            break
                        try:
                            obj = json.loads(data)
                            delta = obj["choices"][0]["delta"].get("content")
                        except (json.JSONDecodeError, KeyError, IndexError):
                            continue
                        if delta:
                            out = filt.feed(delta)
                            if out:
                                yield {"delta": out}
                    tail = filt.flush()
                    if tail:
                        yield {"delta": tail}
                    return  # 正常结束
        except httpx.HTTPError:
            continue  # 连接层失败 → 试下一个

    # 全部失败或池为空 → 演示回声
    yield {"meta": {"model": "demo", "tier": tier, "fake": True}}
    async for ch in _fake_stream(full):
        yield {"delta": ch}


async def complete_chat(tier: str, messages: list[dict], system: str | None = None,
                        temperature: float | None = None) -> str:
    """非流式：收集完整回复（润色/翻译/回复建议用）。同样享受故障转移。"""
    parts = []
    async for ev in stream_chat_events(tier, messages, system, temperature):
        if "delta" in ev:
            parts.append(ev["delta"])
    return "".join(parts)


async def generate_image(prompt: str, size: str = "1024x1024") -> str | None:
    """文生图，按 image 池有序故障转移。返回图片 URL，失败返回 None。
    目前支持 OpenAI 兼容的 images/generations（智谱 CogView 即此格式）。"""
    pool = pool_for("image")
    for cfg in pool:
        url = f'{cfg["base_url"]}/images/generations'
        headers = {"Authorization": f'Bearer {cfg["api_key"]}', "Content-Type": "application/json"}
        payload = {"model": cfg["model"], "prompt": prompt, "size": size}
        try:
            async with httpx.AsyncClient(timeout=90.0, trust_env=False) as client:
                resp = await client.post(url, headers=headers, json=payload)
                if resp.status_code != 200:
                    continue  # 故障转移
                data = resp.json()
                items = data.get("data") or []
                if items and items[0].get("url"):
                    return items[0]["url"]
        except (httpx.HTTPError, ValueError):
            continue
    return None


async def _fake_stream(messages: list[dict]) -> AsyncGenerator[str, None]:
    """无 key 时的占位回声，逐字模拟流式。"""
    last_user = next((m["content"] for m in reversed(messages) if m["role"] == "user"), "你好")
    reply = f"（演示模式·未配置模型 key）我收到了你说的：「{last_user}」。配置 ZHIPU_API_KEY 后这里就是真实 AI 回复。"
    for ch in reply:
        yield ch
        await asyncio.sleep(0.02)
