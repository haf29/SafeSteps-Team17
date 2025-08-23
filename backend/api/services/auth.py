# backend/api/services/auth.py
from pathlib import Path
from dotenv import load_dotenv

# Load .env that sits in backend/api/.env
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

import os
import boto3
from botocore.exceptions import ClientError
from fastapi import HTTPException, status
from models.user import UserSignUp, UserSignIn, UserToken, _is_strong_password

AWS_REGION = os.getenv("AWS_REGION", "eu-north-1")
USER_POOL_ID = os.getenv("COGNITO_USER_POOL_ID")  # optional for these flows
CLIENT_ID = os.getenv("COGNITO_APP_CLIENT_ID")    # REQUIRED for sign up / initiate_auth

if not CLIENT_ID:
    raise RuntimeError(
        "COGNITO_APP_CLIENT_ID is not set. Create backend/api/.env and define COGNITO_APP_CLIENT_ID=<your app client id>."
    )

cognito = boto3.client("cognito-idp", region_name=AWS_REGION)

def sign_up(user: UserSignUp) -> str:
    """
    Register a user in Cognito using email as the username.
    The user will receive a verification code depending on pooled settings.
    """
    # Strength check (pydantic already enforces min length; we add stricter rules)
    err = _is_strong_password(user.password, user.email)
    if err:
        raise HTTPException(status_code=400, detail=err)

    try:
        resp = cognito.sign_up(
            ClientId=CLIENT_ID,
            Username=user.email,   # using email as the Cognito username
            Password=user.password,
            UserAttributes=[
                {"Name": "email", "Value": user.email},
                {"Name": "name",  "Value": user.full_name or ""},
                 {"Name": "phone_number", "Value": user.phone}, 
            ],
        )
        return resp.get("UserSub", "")
    except ClientError as e:
        msg = e.response.get("Error", {}).get("Message", str(e))
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=msg)

def confirm_sign_up(email: str, code: str) -> None:
    """Confirm a newly registered user with the verification code."""
    try:
        cognito.confirm_sign_up(ClientId=CLIENT_ID, Username=email, ConfirmationCode=code)
    except ClientError as e:
        msg = e.response.get("Error", {}).get("Message", str(e))
        raise HTTPException(status_code=400, detail=msg)

def resend_confirmation_code(email: str) -> None:
    try:
        cognito.resend_confirmation_code(ClientId=CLIENT_ID, Username=email)
    except ClientError as e:
        msg = e.response.get("Error", {}).get("Message", str(e))
        raise HTTPException(status_code=400, detail=msg)

def sign_in(credentials: UserSignIn) -> UserToken:
    """
    USER_PASSWORD_AUTH flow (be sure your App Client enables this flow).
    """
    try:
        resp = cognito.initiate_auth(
            ClientId=CLIENT_ID,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": credentials.email,   # we use email as username
                "PASSWORD": credentials.password,
            },
        )
        tokens = resp.get("AuthenticationResult", {})
        return UserToken(
            access_token=tokens.get("AccessToken", ""),
            refresh_token=tokens.get("RefreshToken", ""),
            id_token=tokens.get("IdToken", ""),
            expires_in=tokens.get("ExpiresIn", 3600),
        )
    except ClientError as e:
        msg = e.response.get("Error", {}).get("Message", "Authentication failed")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=msg)
