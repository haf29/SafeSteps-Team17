from datetime import datetime
from typing import Optional
from pydantic import BaseModel, EmailStr, Field

class UserSignUp(BaseModel):
    #what I'm expecting from frontend after signup
    email: EmailStr 
    password: str = Field(min_length=8, max_length=256)
    full_name : Optional[str] = None

class UserSignIn(BaseModel):
    #what I'm expecting from frontend after signin
    email: EmailStr
    password: str = Field(min_length=8, max_length=256)

class UserToken(BaseModel):
    #What I'm sending from backend to frontend after signin
    access_token: str
    refresh_token: Optional[str] = None
    id_token: str
    expires_in: int 

class UserProfile(BaseModel):
    user_sub: str # cognito user id UUID 
    email: EmailStr
    full_name: Optional[str] = None
    created_at: datetime
    updated_at: datetime