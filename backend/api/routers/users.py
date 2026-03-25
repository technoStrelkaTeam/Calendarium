from datetime import timedelta
from typing import Annotated

import jwt
from fastapi import APIRouter, Query, HTTPException, Depends
from fastapi.security import OAuth2PasswordRequestForm
from jwt import InvalidTokenError
from sqlmodel import select

from api.config import oauth2_scheme, SECRET_KEY, ALGORITHM, ACCESS_TOKEN_EXPIRE_MINUTES
from api.database import SessionDep
from api.models.users import User
from api.schemas.tokens import TokenData, Token
from api.schemas.users import *
from pydantic import BaseModel

from api.utils import hash_password, check_password, create_access_token, connect_to_the_mail

class ImapImportRequest(BaseModel):
    login: str
    password: str

router = APIRouter(
    prefix="/users",
    tags=["Users"]
)


async def get_current_user(session: SessionDep, token: Annotated[str, Depends(oauth2_scheme)]):
    credentials_exception = HTTPException(
        status_code=401,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            raise credentials_exception
        token_data = TokenData(username=username)
    except InvalidTokenError:
        raise credentials_exception
    user = session.exec(select(User).filter(User.username == username)).first()
    if user is None:
        raise credentials_exception
    return user


@router.get("/", response_model=list[UserPublic])
async def get_all(current_user: Annotated[User, Depends(get_current_user)],
                  session: SessionDep, offset: int = 0, limit: Annotated[int, Query(le=100)] = 100,
                  ):
    if "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=401, detail="You not a admin")
    users = session.exec(select(User).offset(offset).limit(limit)).all()
    return users


@router.get("/login")
async def login(token: str = Depends(oauth2_scheme)):
    return {"message": "ok", "your_auth_token": token}


@router.post("/register", response_model=UserPublic)
async def register(session: SessionDep, user: UserRegister):
    user.password = hash_password(user.password)
    db_user = User.model_validate(user)
    session.add(db_user)
    session.commit()
    session.refresh(db_user)
    return db_user


@router.post("/token")
async def token(session: SessionDep, form_data: OAuth2PasswordRequestForm = Depends()):
    user = session.exec(select(User).filter(User.username == form_data.username)).first()
    if not user:
        user = session.exec(select(User).filter(User.email == form_data.username)).first()
    if not user:
        raise HTTPException(status_code=400, detail="Incorrect username/email or password")
    if not check_password(form_data.password, user.password):
        raise HTTPException(status_code=400, detail="Incorrect username/email or password")

    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return Token(access_token=access_token, token_type="bearer")


@router.get("/me", response_model=UserPublic)
async def read_users_me(
    current_user: Annotated[User, Depends(get_current_user)],
):
    return current_user


@router.put("/me", response_model=UserPublic)
async def update(current_user: Annotated[User, Depends(get_current_user)],
                 session: SessionDep, user_update: UserUpdate):
    user = session.get(User, current_user.id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    if user_update.password:
        user_update.password = hash_password(user_update.password)
    user_data = user_update.model_dump(exclude_unset=True)
    user.sqlmodel_update(user_data)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


@router.delete("/me")
async def delete(current_user: Annotated[User, Depends(get_current_user)],
                 session: SessionDep):
    user = session.get(User, current_user.id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    session.delete(user)
    session.commit()
    return {"ok": True}


@router.get("/{user_id}", response_model=UserPublic)
async def get_by_id(current_user: Annotated[User, Depends(get_current_user)],
                    user_id: int, session: SessionDep):
    if "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=401, detail="You not a admin")
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.put("/{user_id}", response_model=UserPublic)
async def update(current_user: Annotated[User, Depends(get_current_user)],
                 user_id: int, session: SessionDep, user_update: UserUpdate):
    if "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=401, detail="You not a admin")
    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    user_update.password = hash_password(user_update.password)
    user_data = user_update.model_dump(exclude_unset=True)
    user.sqlmodel_update(user_data)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


@router.delete("/{user_id}")
async def delete(current_user: Annotated[User, Depends(get_current_user)],
                 user_id: int, session: SessionDep):
    if "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=401, detail="You not a admin")
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    session.delete(user)
    session.commit()
    return {"ok": True}


@router.get("/getByUsername/{username}", response_model=UserPublic)
async def get_by_username(username: str, session: SessionDep):
    result = session.exec(select(User).filter(User.username == username)).first()
    if not result:
        raise HTTPException(status_code=404, detail="User not found")
    return result


@router.get("/getByEmail/{email}", response_model=UserPublic)
async def get_by_email(email: str, session: SessionDep):
    result = session.exec(select(User).filter(User.email == email)).first()
    if not result:
        raise HTTPException(status_code=404, detail="User not found")
    return result

# добавлен эндпоинт для api метода получения подписок по imap

@router.post("/import-from-imap")
async def import_from_imap(current_user: Annotated[User, Depends(get_current_user)], request: ImapImportRequest):
    try:
        subs = connect_to_the_mail(request.login, request.password)
        return {"status": "ok", "data": subs}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Import failed: {exc}")
