"""注册 / 登录 / 当前用户。"""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import User
from ..auth import hash_password, verify_password, create_access_token
from ..deps import get_current_user

router = APIRouter(tags=["auth"])


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)
    nickname: str = Field(default="", max_length=40)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class AuthOut(BaseModel):
    token: str
    user: dict


@router.post("/auth/register", response_model=AuthOut)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == body.email).first():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该邮箱已注册")
    user = User(
        email=body.email,
        password_hash=hash_password(body.password),
        nickname=body.nickname or body.email.split("@")[0],
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return {"token": create_access_token(user.id), "user": user.public_dict()}


@router.post("/auth/login", response_model=AuthOut)
def login(body: LoginIn, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == body.email).first()
    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="邮箱或密码错误")
    return {"token": create_access_token(user.id), "user": user.public_dict()}


@router.get("/me")
def me(user: User = Depends(get_current_user)):
    return user.public_dict()


class SettingsIn(BaseModel):
    auto_send_stickers: bool | None = None
    nickname: str | None = Field(default=None, max_length=40)
    avatar_url: str | None = None
    bio: str | None = Field(default=None, max_length=200)
    city: str | None = Field(default=None, max_length=20)


@router.patch("/me/settings")
def update_settings(body: SettingsIn,
                    user: User = Depends(get_current_user),
                    db: Session = Depends(get_db)):
    if body.auto_send_stickers is not None:
        user.auto_send_stickers = body.auto_send_stickers
    if body.nickname is not None and body.nickname.strip():
        user.nickname = body.nickname.strip()
    if body.avatar_url is not None:
        user.avatar_url = body.avatar_url or None
    if body.bio is not None:
        user.bio = body.bio
    if body.city is not None:
        user.city = body.city.strip() or None
    db.commit()
    db.refresh(user)
    return user.public_dict()
