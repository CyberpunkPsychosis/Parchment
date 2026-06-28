"""APNs 推送（基于 token / .p8 的鉴权）。

启用所需环境变量（缺任一则自动 no-op；在线用户本就由 WebSocket 实时送达）：
  APNS_KEY_PATH   —— .p8 私钥文件路径
  APNS_KEY_ID     —— 密钥 ID（10 位）
  APNS_TEAM_ID    —— Apple Team ID（10 位）
  APNS_BUNDLE_ID  —— App Bundle ID（apns-topic），如 com.flow.app
  APNS_SANDBOX    —— "true"(默认，开发证书) / "false"(生产)

依赖（仅启用推送时需要，已加入 requirements）：PyJWT、cryptography、h2。
未安装/未配置时全部 try 兜底，绝不影响主流程。
"""
import os
import time
import threading

from sqlalchemy.orm import Session

from .models import DeviceToken

APNS_KEY_PATH = os.getenv("APNS_KEY_PATH")
APNS_KEY_ID = os.getenv("APNS_KEY_ID")
APNS_TEAM_ID = os.getenv("APNS_TEAM_ID")
APNS_BUNDLE_ID = os.getenv("APNS_BUNDLE_ID")
APNS_SANDBOX = os.getenv("APNS_SANDBOX", "true").strip().lower() != "false"

_token_cache: dict = {"jwt": None, "ts": 0.0}
_lock = threading.Lock()


def push_enabled() -> bool:
    return bool(APNS_KEY_PATH and APNS_KEY_ID and APNS_TEAM_ID and APNS_BUNDLE_ID)


def _provider_token() -> str | None:
    """生成（并缓存 <1h）APNs provider JWT（ES256 签名）。"""
    import jwt  # PyJWT（需 cryptography 提供 ES256）
    with _lock:
        now = time.time()
        if _token_cache["jwt"] and now - _token_cache["ts"] < 3000:
            return _token_cache["jwt"]
        with open(APNS_KEY_PATH, "r", encoding="utf-8") as f:
            key = f.read()
        tok = jwt.encode({"iss": APNS_TEAM_ID, "iat": int(now)}, key,
                         algorithm="ES256", headers={"kid": APNS_KEY_ID})
        _token_cache.update(jwt=tok, ts=now)
        return tok


def send_push(db: Session, user_ids: list[int], title: str, body: str) -> None:
    """给指定用户的所有设备发推送。未配置凭证 / 缺依赖 / 失败 均安全跳过。"""
    if not user_ids or not push_enabled():
        return
    tokens = [t.token for t in db.query(DeviceToken)
              .filter(DeviceToken.user_id.in_(user_ids)).all()]
    if not tokens:
        return
    try:
        import httpx
        jwt_tok = _provider_token()
        if not jwt_tok:
            return
        host = "api.sandbox.push.apple.com" if APNS_SANDBOX else "api.push.apple.com"
        payload = {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}}
        headers = {"authorization": f"bearer {jwt_tok}",
                   "apns-topic": APNS_BUNDLE_ID, "apns-push-type": "alert"}
        with httpx.Client(http2=True, timeout=10.0, trust_env=False) as client:
            for tk in tokens:
                try:
                    client.post(f"https://{host}/3/device/{tk}", headers=headers, json=payload)
                except httpx.HTTPError:
                    continue
    except Exception:
        # 缺 PyJWT/cryptography/h2、密钥读取失败等 —— 一律静默，不影响发消息
        return
