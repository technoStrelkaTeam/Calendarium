from fastapi import FastAPI, Depends
from starlette.middleware.cors import CORSMiddleware

from api.config import oauth2_scheme
from api.database import create_db_and_tables
from api.routers import users, subscribe

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(users.router)
app.include_router(subscribe.router)

@app.get("/test")
async def root(token: str = Depends(oauth2_scheme)):
    return {"message": "Hello World", "your_auth_token": token}


@app.on_event("startup")
def on_startup():
    create_db_and_tables()
