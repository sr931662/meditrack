from collections.abc import Callable
from dataclasses import dataclass

from fastapi import Depends, Path
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.db import get_db, utcnow
from app.core.errors import Forbidden, Unauthorized
from app.core.security import decode_access_token
from app.models import AuthSession, User
from app.services import authz

_bearer = HTTPBearer(auto_error=False)


@dataclass
class AuthContext:
    user: User
    session_id: str


def get_auth(creds: HTTPAuthorizationCredentials | None = Depends(_bearer), db: Session = Depends(get_db)) -> AuthContext:
    """Valid signature is not enough: the session must be unrevoked and the user active, checked in the DB
    on every request, so disabling an account or logging out takes effect immediately."""
    if creds is None:
        raise Unauthorized()
    claims = decode_access_token(creds.credentials)
    if claims is None:
        raise Unauthorized("Invalid or expired token")
    session = db.get(AuthSession, claims["sid"])
    user = db.get(User, claims["sub"])
    if not session or session.revoked_at or session.expires_at <= utcnow() or not user or not user.is_active:
        raise Unauthorized("Session is no longer valid")
    return AuthContext(user, session.id)


def require_platform(permission: str) -> Callable:
    def dep(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)) -> AuthContext:
        if permission not in authz.platform_permissions(db, auth.user):
            raise Forbidden()
        return auth

    return dep


def get_household_access(
    household_id: str = Path(...), auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)
) -> authz.HouseholdAccess:
    return authz.household_access(db, auth.user, household_id)


def require_any(access: authz.HouseholdAccess, *permissions: str) -> None:
    if not any(p in access.permissions for p in permissions):
        raise Forbidden()


def page(items: list, total: int, limit: int, offset: int) -> dict:
    return {"items": items, "total": total, "limit": limit, "offset": offset}
