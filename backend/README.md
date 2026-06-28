# FLOW Backend

FastAPI 后端：账号（邮箱+密码）、会员等级、AI 代理（按 tier 路由模型）。
API key 只在后端，绝不进 app。

## 本地启动

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # 填 ZHIPU_API_KEY（不填则走"演示回声"模式）
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- 交互式文档： http://localhost:8000/docs
- 健康检查： http://localhost:8000/

iOS 模拟器同机直连 `http://localhost:8000`。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/register` | 邮箱+密码注册 → `{token, user}` |
| POST | `/auth/login` | 登录 → `{token, user}` |
| GET  | `/me` | 当前用户（需 `Authorization: Bearer <token>`）|
| POST | `/chat/stream` | SSE 流式对话，按 tier 选模型 |

## 模型路由

见 `app/config.py` 的 `MODEL_TIERS`：
- `free` → 智谱 `glm-4-flash`
- `pro`  → DeepSeek `deepseek-chat`

换模型只改这张表 / 改 `.env` 里的 key。没配 key 时自动进"演示回声"模式，方便先调通链路。
