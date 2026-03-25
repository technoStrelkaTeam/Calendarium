from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="users/token")
SECRET_KEY = "fef499912d964845de031662e67f3a764860d1b07e86f9ed4a437632d7f1742b"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
AI_MODEL = "gemma3:1b"