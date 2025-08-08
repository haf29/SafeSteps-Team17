from pydantic import BaseModel, EmailStr, Field, validator
from typing import Optional
import re

STRONG_PW_RE = re.compile(
    r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$%\^&\*\(\)_\+\-\=\[\]\{\};':\"\\|,.<>\/\?]).{12,}$"
)

def _is_strong_password(pw: str, email: Optional[str] = None) -> Optional[str]:
    if pw.strip() != pw:
        return "Password cannot start or end with spaces"
    if not STRONG_PW_RE.match(pw):
        return ("Password must be at least 12 chars and include upper, lower, "
                "digit, and special character")
    if email:
        local = email.split("@")[0].lower()
        if local and local in pw.lower():
            return "Password cannot contain your email username"
    if "password" in pw.lower():
        return "Password cannot contain the word 'password'"
    return None

class UserSignUp(BaseModel):
    full_name: Optional[str] = ""
    email: EmailStr
    password: str = Field(min_length=12)

    @validator("password")
    def validate_password(cls, v, values):
        err = _is_strong_password(v, values.get("email"))
        if err:
            raise ValueError(err)
        return v

class UserSignIn(BaseModel):
    email: EmailStr
    password: str

class UserToken(BaseModel):
    access_token: str
    refresh_token: Optional[str] = ""
    id_token: Optional[str] = ""
    token_type: str = "bearer"
    expires_in: int = 3600
