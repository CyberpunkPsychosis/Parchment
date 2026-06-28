"""会员套餐 + 购买。当前为 MOCK 支付（直接升级），上线接真支付。"""
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..deps import get_current_user
from ..db import get_db
from ..models import User

router = APIRouter(tags=["membership"])

# 套餐定义（价格仅展示用；真实扣费以支付渠道为准）
PLANS = [
    {"id": "monthly", "name_zh": "月度会员", "name_en": "Monthly", "price_cny": 30,  "days": 30,
     "desc_zh": "高级模型 · 100 次/天", "desc_en": "Premium model · 100/day"},
    {"id": "yearly",  "name_zh": "年度会员", "name_en": "Yearly",  "price_cny": 198, "days": 365,
     "desc_zh": "约 5.5 折 · 全年畅享", "desc_en": "~45% off · best value"},
]
_PLAN_BY_ID = {p["id"]: p for p in PLANS}

# 会员权益（前端付费墙展示）
BENEFITS = [
    {"zh": "解锁更聪明的高级模型", "en": "Smarter premium model"},
    {"zh": "每天 100 次 AI 对话", "en": "100 AI chats per day"},
    {"zh": "更快的响应与更长记忆", "en": "Faster replies, longer memory"},
    {"zh": "全部 AI 搭子与助手功能", "en": "All companions & assistant tools"},
]


@router.get("/membership/plans")
def plans():
    return {"plans": PLANS, "benefits": BENEFITS}


class PurchaseIn(BaseModel):
    plan_id: str
    # 上线后这里会带真实支付凭证，例如：
    #   apple_receipt: str   # App Store 收据，服务端向 Apple 验证
    #   wx_prepay_id / alipay_trade_no 等


@router.post("/membership/purchase")
def purchase(body: PurchaseIn,
             user: User = Depends(get_current_user),
             db: Session = Depends(get_db)):
    plan = _PLAN_BY_ID.get(body.plan_id)
    if not plan:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="无效的套餐")

    # ===== 真支付接入位置（上线替换这一段）=====
    # 1) 校验支付凭证：
    #    - Apple IAP：把 apple_receipt POST 到 Apple 验证（verifyReceipt / App Store Server API），
    #      确认 product_id 与 plan 对应、未退款。
    #    - 微信/支付宝：用回调通知 + 订单号核验金额与状态。
    # 2) 校验通过后再执行下面的升级。
    # 目前为 MOCK：直接升级，方便本地联调。
    base = user.tier_expiry if (user.tier == "pro" and user.tier_expiry and user.tier_expiry > datetime.utcnow()) else datetime.utcnow()
    user.tier = "pro"
    user.tier_expiry = base + timedelta(days=plan["days"])
    db.commit()
    db.refresh(user)
    return {"ok": True, "user": user.public_dict()}
