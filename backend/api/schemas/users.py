from __future__ import annotations
from sqlmodel import Field, SQLModel


class UserBase(SQLModel):
    name: str = Field(index=True)
    username: str = Field(default=None, index=True, unique=True, nullable=False)
    email: str = Field(default=None, unique=True, nullable=False)


class UserPublic(UserBase):
    id: int | None = Field(default=None, primary_key=True)


class UserRegister(UserBase):
    password: str


class UserUpdate(UserBase):
    name: str | None = None
    username: str | None = None
    email: str | None = None
    password: str | None = None
