from fastapi import APIRouter
from models.user import UserSignUp, UserSignIn, UserToken
from services import auth as auth_service
from pydantic import BaseModel, EmailStr
router = APIRouter(prefix="/user", tags=["user"])

class ConfirmBody(BaseModel):
    email: EmailStr
    code: str

@router.post("/confirm", status_code=204, summary="Confirm a newly registered user")
def confirm_user(body: ConfirmBody):
    auth_service.confirm_sign_up(body.email, body.code)
    return  # 204 No Content

class ResendBody(BaseModel):
    email: EmailStr

@router.post("/resend-code", status_code=204, summary="Resend the confirmation code")
def resend_code(body: ResendBody):
    # This uses Cognito's resend API (add helper below if you like)
    auth_service.resend_confirmation_code(body.email)
    return


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
