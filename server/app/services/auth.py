from datetime import timedelta

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.db import utcnow
from app.core.errors import AppError, Conflict, Forbidden, Unauthorized
from app.core.security import (
    create_access_token,
    hash_password,
    hash_token,
    new_refresh_token,
    password_problem,
    verify_password,
)
from app.models import AuthSession, User
from app.services import audit

BAD_CREDENTIALS = "Incorrect email or password"


def normalize_email(email: str) -> str:
    return email.strip().lower()


def create_user(db: Session, *, email: str, password: str, full_name: str, platform_role: str | None = None) -> User:
    problem = password_problem(password)
    if problem:
        raise AppError(problem, code="weak_password", status_code=422)
    email = normalize_email(email)
    if db.query(User).filter_by(email=email).first():
        raise Conflict("An account with this email already exists")
    user = User(email=email, full_name=full_name.strip(), password_hash=hash_password(password), platform_role=platform_role)
    db.add(user)
    db.flush()
    return user


def _issue(db: Session, user: User, session: AuthSession | None = None) -> dict:
    s = get_settings()
    refresh = new_refresh_token()
    if session is None:
        session = AuthSession(
            user_id=user.id, refresh_hash=hash_token(refresh), expires_at=utcnow() + timedelta(days=s.refresh_token_ttl_days)
        )
        db.add(session)
    else:
        session.prev_refresh_hash = session.refresh_hash
        session.refresh_hash = hash_token(refresh)
        session.expires_at = utcnow() + timedelta(days=s.refresh_token_ttl_days)
    db.flush()
    access, ttl = create_access_token(user.id, session.id)
    return {"access_token": access, "refresh_token": refresh, "token_type": "bearer", "expires_in": ttl}


def login(db: Session, email: str, password: str) -> dict:
    s = get_settings()
    user = db.query(User).filter_by(email=normalize_email(email)).first()
    now = utcnow()
    if user and user.locked_until and user.locked_until > now:
        raise AppError("Too many failed attempts. Try again later.", code="locked", status_code=429)
    ok = verify_password(password, user.password_hash if user else None)
    if not ok:
        if user:
            user.failed_logins += 1
            if user.failed_logins >= s.login_lockout_threshold:
                user.locked_until = now + timedelta(minutes=s.login_lockout_minutes)
                user.failed_logins = 0
                audit.record(db, actor_id=user.id, action="auth.locked_out", target_type="user", target_id=user.id)
            db.commit()  # persist the counter even though the request fails
        raise Unauthorized(BAD_CREDENTIALS)
    if not user.is_active:
        raise Forbidden("This account has been disabled. Contact support.")
    user.failed_logins = 0
    user.locked_until = None
    return _issue(db, user)


def refresh(db: Session, refresh_token: str) -> dict:
    h = hash_token(refresh_token)
    session = db.query(AuthSession).filter_by(refresh_hash=h).first()
    if session is None:
        reused = db.query(AuthSession).filter_by(prev_refresh_hash=h).first()
        if reused is not None and reused.revoked_at is None:
            reused.revoked_at = utcnow()  # token theft signal: kill the whole session
            db.commit()
        raise Unauthorized("Invalid refresh token")
    user = db.get(User, session.user_id)
    if session.revoked_at or session.expires_at <= utcnow() or not user or not user.is_active:
        raise Unauthorized("Invalid refresh token")
    return _issue(db, user, session)


def revoke_session(db: Session, session_id: str) -> None:
    s = db.get(AuthSession, session_id)
    if s and not s.revoked_at:
        s.revoked_at = utcnow()


def revoke_all_sessions(db: Session, user_id: str) -> int:
    n = 0
    for s in db.query(AuthSession).filter_by(user_id=user_id, revoked_at=None):
        s.revoked_at = utcnow()
        n += 1
    return n
