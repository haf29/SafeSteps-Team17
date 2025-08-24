# backend/api/models/user.py
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, EmailStr, Field

# ---------- PUBLIC MODELS ----------

class UserSignUp(BaseModel):
    # what the frontend sends on signup
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)
    full_name: Optional[str] = None
    # Pydantic v2: use `pattern`, not `regex`
    # Lebanon format (+961 and 7–8 digits). If you want global E.164 later,
    # switch to pattern=r'^\+\d{7,15}$'
    phone: str = Field(..., pattern=r'^\+961\d{7,8}$')

class UserSignIn(BaseModel):
    # what the frontend sends on login
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)

class UserToken(BaseModel):
    # what we return on login
    access_token: str
    refresh_token: Optional[str] = None
    id_token: str
    expires_in: int

class UserProfile(BaseModel):
    user_sub: str
    email: EmailStr
    full_name: Optional[str] = None
    phone: Optional[str] = None
    created_at: datetime
    updated_at: datetime

# ---------- INTERNAL HELPER ----------

def _is_strong_password(password: str, email: str | None = None) -> Optional[str]:
    """
    Return None if strong; otherwise return a short message explaining why.
    Policy: ≥12 chars, at least 1 lowercase, 1 uppercase, 1 digit, 1 symbol;
    must not contain the email local-part (before '@').
    """
    if len(password) < 12:
        return "Password must be at least 12 characters long."
    has_lower = any(c.islower() for c in password)
    has_upper = any(c.isupper() for c in password)
    has_digit = any(c.isdigit() for c in password)
    has_symbol = any(not c.isalnum() for c in password)
    if not (has_lower and has_upper and has_digit and has_symbol):
        return "Password must include lowercase, uppercase, number, and special character."
    if email:
        local = email.split("@", 1)[0].lower()
        if local and local in password.lower():
            return "Password must not contain your email name."
    return None
