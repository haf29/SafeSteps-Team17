import os
from typing import Tuple
import boto3
from botocore.exceptions import ClientError
from fastapi import HTTPException,status 

from api.models.user import UserSignUp, UserSignIn, UserToken

USER_POOL_ID = os.getenv("COGNITO_USER_POOL_ID")
CLIENT_ID = os.getenv("COGNITO_APP_CLIENT_ID")

cognito = boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION", "eu_north-1" ))

def sign_up(user : UserSignUp) -> str: 
    try:
        response = cognito.sign_up(
            ClientId=CLIENT_ID,
            Username=user.email,
            Password=user.password,
            UserAttributes=[{"Name": "email", "Value": user.email}]
        )
        return response["UserSub"]
    except ClientError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    
def confirm_sign_up(email: str, code: str) -> None:
    cognito.confirm_sign_up(
        ClientId=CLIENT_ID,
        Username=email,
        ConfirmationCode=code
    )
    return 
def sign_in(credentials: UserSignIn) -> UserToken:
    try:
        response = cognito.admin_initiate_auth(
            ClientId=CLIENT_ID,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": credentials.email, "PASSWORD": credentials.password},
        )
        auth = response["AuthenticationResult"]
        return UserToken(
            access_token=auth["AccessToken"],
            refresh_token=auth["RefreshToken"],
            id_token=auth["IdToken"],
            expires_in=auth["ExpiresIn"]
        )
    except ClientError as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    




