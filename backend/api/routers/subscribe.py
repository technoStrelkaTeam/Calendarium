from datetime import timedelta
from dateutil.relativedelta import relativedelta
from typing import Annotated

from fastapi import APIRouter, HTTPException, Depends
from sqlmodel import select

from api.config import oauth2_scheme, SECRET_KEY, ALGORITHM
from api.database import SessionDep
from api.models.subscribe import Subscribe
from api.models.users import User
from api.schemas.subscribe import *
from api.models.enums import Interval
from api.schemas.stats import ChartData, AiInsights
from api.services.chart_service import ChartService
from api.services.llm_analyzer import analyzer

from jwt import InvalidTokenError
import jwt

router = APIRouter(
    prefix="/subscribes",
    tags=["Subscribes"]
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
    except InvalidTokenError:
        raise credentials_exception
    user = session.exec(select(User).filter(User.username == username)).first()
    if user is None:
        raise credentials_exception
    return user


@router.get("/", response_model=list[SubscribePublic])
async def get_all(
    current_user: Annotated[User, Depends(get_current_user)],
    session: SessionDep,
):
    if "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=401, detail="You not a admin")
    subs = session.exec(select(Subscribe)).all()
    return subs

@router.get("/me/chart-data", response_model=ChartData)
async def get_chart_data(
    current_user: Annotated[User, Depends(get_current_user)],
    session: SessionDep,
):
    subs = session.exec(select(Subscribe).where(Subscribe.user_id == current_user.id)).all()
    return ChartService.generate(subs)


@router.get("/me/ai-analysis", response_model=AiInsights)
async def get_ai_analysis(
    current_user: Annotated[User, Depends(get_current_user)],
    session: SessionDep,
):
    subs = session.exec(select(Subscribe).where(Subscribe.user_id == current_user.id)).all()

    subs_list = [
        {
            "name": s.name,
            "category": s.category or "другое",
            "cost": s.cost,
            "interval": s.interval,
            "type_interval": s.type_interval.value
        }
        for s in subs
    ]

    result = analyzer.analyze(subs_list)
    return AiInsights(**result)

@router.get("/me", response_model=list[SubscribePublic])
async def read_own_subscribes(
    current_user: Annotated[User, Depends(get_current_user)],
    session: SessionDep,
):
    subs = session.exec(
        select(Subscribe).filter(Subscribe.user_id == current_user.id)
    ).all()
    return subs


@router.get("/me/{subscribe_id}", response_model=SubscribePublic)
async def read_own_subscribe(
    current_user: Annotated[User, Depends(get_current_user)],
    subscribe_id: int,
    session: SessionDep,
):
    sub = session.get(Subscribe, subscribe_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
    if sub.user_id != current_user.id and "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=403, detail="Not your subscription")
    return sub


@router.post("/me", response_model=SubscribePublic)
async def create_subscribe(
    current_user: Annotated[User, Depends(get_current_user)],
    session: SessionDep,
    sub_in: SubscribeCreate,
):

    sub_data = sub_in.model_dump()
    sub_data["user_id"] = current_user.id

    db_sub = Subscribe.model_validate(sub_data)

    session.add(db_sub)
    session.commit()
    session.refresh(db_sub)
    return db_sub

@router.put("/me/{subscribe_id}", response_model=SubscribePublic)
async def update_subscribe(
    current_user: Annotated[User, Depends(get_current_user)],
    subscribe_id: int,
    session: SessionDep,
    subscribe_update: SubscribeUpdate,
):
    sub = session.get(Subscribe, subscribe_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
    if sub.user_id != current_user.id and "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=403, detail="Not your subscription")
    data = subscribe_update.model_dump(exclude_unset=True)
    sub.sqlmodel_update(data)
    session.add(sub)
    session.commit()
    session.refresh(sub)
    return sub


@router.delete("/me/{subscribe_id}")
async def delete_subscribe(
    current_user: Annotated[User, Depends(get_current_user)],
    subscribe_id: int,
    session: SessionDep,
):
    sub = session.get(Subscribe, subscribe_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
    if sub.user_id != current_user.id and "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=403, detail="Not your subscription")
    session.delete(sub)
    session.commit()
    return {"ok": True}


@router.post("/{subscribe_id}/update")
async def update_next_billing(
    current_user: Annotated[User, Depends(get_current_user)],
    subscribe_id: int,
    session: SessionDep,
):
    sub = session.get(Subscribe, subscribe_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
    if sub.user_id != current_user.id and "ROLE_ADMIN" not in current_user.roles:
        raise HTTPException(status_code=403, detail="Not your subscription")

    if sub.type_interval == "day":
        sub.next_pay += relativedelta(day=sub.interval + sub.next_pay.day)
    elif sub.type_interval == "month":
        sub.next_pay += relativedelta(month=sub.interval + sub.next_pay.month)
    elif sub.type_interval == "year":
        sub.next_pay += relativedelta(year=sub.interval + sub.next_pay.year)

    session.add(sub)
    session.commit()
    session.refresh(sub)
    
    return {
        "ok": True,
        "next_pay": sub.next_pay.isoformat()
    }