"""推送发送（占位接口）。

真实 APNs 投递需要 Apple 推送密钥（.p8 / Key ID / Team ID / Bundle ID）。
未配置凭证时为 no-op —— 在线用户已由 WebSocket 实时送达，离线推送留待配置后启用。
"""
import os
from sqlalchemy.orm import Session

from .models import DeviceToken

APNS_KEY_PATH = os.getenv("APNS_KEY_PATH")  # 配置后启用真实投递


def push_enabled() -> bool:
    return bool(APNS_KEY_PATH)


def send_push(db: Session, user_ids: list[int], title: str, body: str) -> None:
    """给指定用户的所有设备发推送。未配置凭证则跳过。"""
    if not user_ids or not push_enabled():
        return
    tokens = [t.token for t in db.query(DeviceToken)
              .filter(DeviceToken.user_id.in_(user_ids)).all()]
    if not tokens:
        return
    # TODO: 用 tokens 走 APNs（如 aioapns / httpx+JWT）。此处保留接入点。
    _ = (tokens, title, body)
