import hashlib
import re
import secrets
from datetime import datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from app.core.config import get_settings
from app.core.db import utcnow

_hasher = PasswordHasher()
# Verified against when the user does not exist, so timing does not reveal registered emails.
_DUMMY_HASH = _hasher.hash("medtrack-dummy-password")

MIN_PASSWORD_LENGTH = 10


def password_problem(password: str) -> str | None:
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"Password must be at least {MIN_PASSWORD_LENGTH} characters"
    if not (re.search(r"[A-Za-z]", password) and re.search(r"\d", password)):
        return "Password must contain letters and digits"
    return None


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, InvalidHashError):
        return False


def create_access_token(user_id: str, session_id: str, now: datetime | None = None) -> tuple[str, int]:
    s = get_settings()
    now = now or utcnow()
    ttl = timedelta(minutes=s.access_token_ttl_minutes)
    payload = {
        "sub": user_id,
        "sid": session_id,
        "iat": int(now.timestamp()),
        "exp": int((now + ttl).timestamp()),
        "typ": "access",
    }
    return jwt.encode(payload, s.jwt_secret, algorithm="HS256"), int(ttl.total_seconds())


def decode_access_token(token: str) -> dict | None:
    try:
        data = jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None
    return data if data.get("typ") == "access" else None


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()
