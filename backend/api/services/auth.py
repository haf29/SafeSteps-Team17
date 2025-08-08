import os
from typing import Dict, Optional
from fastapi import HTTPException, status
from models.user import UserSignUp, UserSignIn, UserToken
from models.user import _is_strong_password  # reuse model validator logic

AUTH_MODE = os.getenv("AUTH_MODE", "dev").lower()

class _DevAuth:
    def __init__(self):
        self.users: Dict[str, Dict[str, Optional[str]]] = {
            "test@test.com": {"password": "password123AA!", "full_name": "Test User"}
        }

    def sign_up(self, user: UserSignUp) -> str:
        if user.email in self.users:
            raise HTTPException(status_code=409, detail="Email already exists")
        # extra guard (model already validated)
        err = _is_strong_password(user.password, user.email)
        if err:
            raise HTTPException(status_code=400, detail=err)
        self.users[user.email] = {"password": user.password, "full_name": user.full_name}
        return f"dev-{user.email}"

    def sign_in(self, creds: UserSignIn) -> UserToken:
        u = self.users.get(creds.email)
        if not u or u["password"] != creds.password:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
        return UserToken(
            access_token="dev_access_token",
            refresh_token="dev_refresh_token",
            id_token="dev_id_token",
            expires_in=3600,
        )

    def send_reset(self, email: str) -> None:
        return

_dev = _DevAuth()

def sign_up(user: UserSignUp) -> str:
    return _dev.sign_up(user)

def sign_in(creds: UserSignIn) -> UserToken:
    return _dev.sign_in(creds)

def send_reset(email: str) -> None:
    return _dev.send_reset(email)
