from __future__ import annotations

from sqlalchemy import Column, JSON
from sqlmodel import Field

from api.schemas.users import UserBase


class User(UserBase, table=True):
    id: int | None = Field(default=None, primary_key=True)
    password: str
    roles: list[str] | None = Field(default=["ROLE_USER"], sa_column=Column(JSON))
