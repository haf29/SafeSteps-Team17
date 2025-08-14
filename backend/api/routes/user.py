from fastapi import APIRouter
from models.user import UserSignUp, UserSignIn, UserToken
from services import auth as auth_service

router = APIRouter(prefix="/user", tags=["user"])

@router.post("/signup", status_code=201)
def register_user(user: UserSignUp):
    user_sub = auth_service.sign_up(user)
    return {
        "message": "User registered successfully - Check email for confirmation code",
        "user_sub": user_sub
    }

@router.post("/login", response_model=UserToken)
def login(credentials: UserSignIn):
    return auth_service.sign_in(credentials)
