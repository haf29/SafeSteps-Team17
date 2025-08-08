
from fastapi import APIRouter, HTTPException, status
from models.user import UserSignUp, UserSignIn, UserToken
from services import auth as auth_service

router = APIRouter(prefix="/user", tags=["user"])

@router.post("/signup", status_code=status.HTTP_201_CREATED)
def register_user(user: UserSignUp):
    user_sub = auth_service.sign_up(user)
    return {"message": "User registered successfully", "user_sub": user_sub}

@router.post("/login", response_model=UserToken)
def login(credentials: UserSignIn):
    return auth_service.sign_in(credentials)

@router.post("/forgot", status_code=status.HTTP_202_ACCEPTED)
def forgot(payload: dict):
    email = payload.get("email")
    if not email:
        raise HTTPException(status_code=400, detail="Missing email")
    auth_service.send_reset(email)
    return {"message": "If the email exists, a reset link has been sent"}
