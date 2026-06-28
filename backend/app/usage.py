"""每日 AI 用量上限。防止恶意刷量把成本打爆。"""
from datetime import date
from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from .models import DailyUsage, User
from .config import DAILY_LIMITS


def consume(db: Session, user: User) -> dict:
    """检查并 +1 今日用量。超额抛 429。返回 {used, limit}。"""
    tier = "pro" if user.is_pro else "free"
    limit = DAILY_LIMITS.get(tier, DAILY_LIMITS["free"])
    today = date.today().isoformat()

    row = db.query(DailyUsage).filter_by(user_id=user.id, day=today).first()
    used = row.count if row else 0

    if used >= limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(f"今日免费次数已用完（{limit} 次/天），升级会员解锁更多"
                    if tier == "free" else f"今日次数已达上限（{limit} 次/天），明天再来吧"),
        )

    if row:
        row.count += 1
    else:
        db.add(DailyUsage(user_id=user.id, day=today, count=1))
    db.commit()
    return {"used": used + 1, "limit": limit}
