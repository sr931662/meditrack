from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import AuthContext, get_auth
from app.api.v1.schemas import LoginIn, RefreshIn, RegisterIn
from app.core.db import get_db
from app.models import Household, Membership
from app.services import auth as auth_service
from app.services import authz

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", status_code=201)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    user = auth_service.create_user(db, email=body.email, password=body.password, full_name=body.full_name)
    return {"id": user.id, "email": user.email, "full_name": user.full_name}


@router.post("/login")
def login(body: LoginIn, db: Session = Depends(get_db)):
    return auth_service.login(db, body.email, body.password)


@router.post("/refresh")
def refresh(body: RefreshIn, db: Session = Depends(get_db)):
    return auth_service.refresh(db, body.refresh_token)


@router.post("/logout", status_code=204)
def logout(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    auth_service.revoke_session(db, auth.session_id)


@router.get("/me")
def me(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    """Everything the client needs to render role-appropriate UI. The UI is a convenience only;
    the backend re-checks every permission on every request."""
    u = auth.user
    memberships = []
    for m, h in (
        db.query(Membership, Household)
        .join(Household, Household.id == Membership.household_id)
        .filter(Membership.user_id == u.id)
    ):
        perms = set(m.permissions or []) if m.role == "caregiver" else authz.role_permissions(db, m.role)
        memberships.append(
            {
                "household_id": h.id,
                "household_name": h.name,
                "role": m.role,
                "permissions": sorted(perms),
                "senior_id": m.senior_id,
            }
        )
    return {
        "id": u.id,
        "email": u.email,
        "full_name": u.full_name,
        "platform_role": u.platform_role,
        "platform_permissions": sorted(authz.platform_permissions(db, u)),
        "memberships": memberships,
    }
