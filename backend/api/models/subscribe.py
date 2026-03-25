from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel

from api.models.enums import Interval


class Subscribe(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)

    user_id: int = Field(foreign_key="user.id", index=True)

    name: str = Field(max_length=100)
    category: Optional[str] = Field(default=None, max_length=50)

    cost: int
    interval: int
    type_interval: Interval

    next_pay: datetime
