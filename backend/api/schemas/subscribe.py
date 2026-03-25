from __future__ import annotations
from sqlmodel import SQLModel

from datetime import datetime
from typing import Optional

from pydantic import field_validator

from api.models.enums import Interval


class SubscribeBase(SQLModel):
    name: str
    category: Optional[str] = None
    cost: int
    interval: int
    type_interval: Interval
    next_pay: datetime


class SubscribeCreate(SubscribeBase):
    @field_validator("interval")
    @classmethod
    def interval_positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("Interval must be positive")
        return v


class SubscribePublic(SubscribeBase):
    id: int
    user_id: int


class SubscribeUpdate(SQLModel):
    name: Optional[str] = None
    category: Optional[str] = None
    cost: Optional[int] = None
    interval: Optional[int] = None
    type_interval: Optional[Interval] = None
    next_pay: Optional[datetime] = None