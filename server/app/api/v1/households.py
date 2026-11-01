from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import AuthContext, get_auth, get_household_access, require_any
from app.api.v1.schemas import HouseholdIn, MemberIn, MemberPatch, SeniorIn, SeniorPatch
from app.core.db import get_db
from app.core.errors import AppError, Conflict, NotFound
from app.core.permissions import CAREGIVER_GRANTABLE
from app.models import Household, Membership, Senior, User
from app.services import audit, engine
from app.services import auth as auth_service
from app.services.authz import HouseholdAccess

router = APIRouter(prefix="/households", tags=["households"])


def _h(h: Household) -> dict:
    return {"id": h.id, "name": h.name, "plan": h.plan, "created_at": h.created_at}


def _m(m: Membership) -> dict:
    return {
        "id": m.id,
        "user_id": m.user_id,
        "email": m.user.email,
        "full_name": m.user.full_name,
        "role": m.role,
        "permissions": m.permissions or [],
        "senior_id": m.senior_id,
    }


def _s(s: Senior) -> dict:
    return {
        "id": s.id,
        "household_id": s.household_id,
        "full_name": s.full_name,
        "phone": s.phone,
        "birth_year": s.birth_year,
        "language": s.language,
        "timezone": s.timezone,
        "is_active": s.is_active,
        "has_login": s.user_id is not None,
    }


@router.post("", status_code=201)
def create_household(body: HouseholdIn, auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    h = Household(name=body.name.strip())
    db.add(h)
    db.flush()
    db.add(Membership(household_id=h.id, user_id=auth.user.id, role="owner"))
    engine.get_policy(db, h.id)
    audit.record(
        db, actor_id=auth.user.id, action="household.created", target_type="household", target_id=h.id, household_id=h.id
    )
    return _h(h)


@router.get("")
def my_households(auth: AuthContext = Depends(get_auth), db: Session = Depends(get_db)):
    rows = (
        db.query(Household)
        .join(Membership, Membership.household_id == Household.id)
        .filter(Membership.user_id == auth.user.id)
        .order_by(Household.created_at)
        .all()
    )
    return [_h(h) for h in rows]


@router.get("/{household_id}")
def get_household(access: HouseholdAccess = Depends(get_household_access), db: Session = Depends(get_db)):
    require_any(access, "households.read")
    return _h(db.get(Household, access.household_id))


# ---- members ------------------------------------------------------------------------------------
@router.get("/{household_id}/members")
def list_members(access: HouseholdAccess = Depends(get_household_access), db: Session = Depends(get_db)):
    access.require("members.manage")
    return [_m(m) for m in db.query(Membership).filter_by(household_id=access.household_id).order_by(Membership.created_at)]


def _validated_grants(role: str, permissions: list[str]) -> list[str]:
    if role != "caregiver":
        return []
    bad = [p for p in permissions if p not in CAREGIVER_GRANTABLE]
    if bad:
        raise AppError(
            f"These permissions cannot be granted to a caregiver: {', '.join(sorted(bad))}",
            code="validation_error",
            status_code=422,
        )
    return sorted(set(permissions))


@router.post("/{household_id}/members", status_code=201)
def add_member(
    body: MemberIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("members.manage")
    grants = _validated_grants(body.role, body.permissions)
    user = db.query(User).filter_by(email=body.email).first()
    if user is None or not user.is_active:
        raise NotFound("No registered user with that email. Ask them to create an account first.")
    if db.query(Membership).filter_by(household_id=access.household_id, user_id=user.id).first():
        raise Conflict("This person is already a member of the household")
    m = Membership(household_id=access.household_id, user_id=user.id, role=body.role, permissions=grants)
    db.add(m)
    db.flush()
    audit.record(
        db,
        actor_id=auth.user.id,
        action="member.added",
        target_type="membership",
        target_id=m.id,
        household_id=access.household_id,
        data={"email": user.email, "role": body.role, "permissions": grants},
    )
    return _m(m)


def _member(db: Session, access: HouseholdAccess, member_id: str) -> Membership:
    m = db.query(Membership).filter_by(id=member_id, household_id=access.household_id).first()
    if m is None:
        raise NotFound("Member not found")
    return m


@router.patch("/{household_id}/members/{member_id}")
def update_member(
    member_id: str,
    body: MemberPatch,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("members.manage")
    m = _member(db, access, member_id)
    if m.role != "caregiver":
        raise AppError("Only caregiver permissions can be edited", code="validation_error", status_code=422)
    m.permissions = _validated_grants("caregiver", body.permissions)
    audit.record(
        db,
        actor_id=auth.user.id,
        action="member.permissions_changed",
        target_type="membership",
        target_id=m.id,
        household_id=access.household_id,
        data={"permissions": m.permissions},
    )
    return _m(m)


@router.delete("/{household_id}/members/{member_id}", status_code=204)
def remove_member(
    member_id: str,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("members.manage")
    m = _member(db, access, member_id)
    if m.role == "owner" and db.query(Membership).filter_by(household_id=access.household_id, role="owner").count() <= 1:
        raise AppError("A household needs at least one owner", code="conflict", status_code=409)
    db.delete(m)
    audit.record(
        db,
        actor_id=auth.user.id,
        action="member.removed",
        target_type="membership",
        target_id=member_id,
        household_id=access.household_id,
    )


# ---- seniors ------------------------------------------------------------------------------------
@router.post("/{household_id}/seniors", status_code=201)
def create_senior(
    body: SeniorIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("seniors.manage")
    s = Senior(
        household_id=access.household_id,
        full_name=body.full_name.strip(),
        phone=body.phone,
        birth_year=body.birth_year,
        language=body.language,
        timezone=body.timezone,
    )
    db.add(s)
    db.flush()
    if body.login_email:
        user = auth_service.create_user(db, email=body.login_email, password=body.login_password, full_name=s.full_name)
        s.user_id = user.id
        db.add(Membership(household_id=access.household_id, user_id=user.id, role="senior", senior_id=s.id))
    audit.record(
        db,
        actor_id=auth.user.id,
        action="senior.created",
        target_type="senior",
        target_id=s.id,
        household_id=access.household_id,
        data={"has_login": bool(body.login_email)},
    )
    return _s(s)


@router.get("/{household_id}/seniors")
def list_seniors(access: HouseholdAccess = Depends(get_household_access), db: Session = Depends(get_db)):
    require_any(access, "seniors.manage", "adherence.read", "medications.read")
    q = db.query(Senior).filter_by(household_id=access.household_id, is_active=True)
    if access.role == "senior":
        q = q.filter(Senior.id == access.senior_id)
    return [_s(s) for s in q.order_by(Senior.created_at)]


@router.patch("/{household_id}/seniors/{senior_id}")
def update_senior(
    senior_id: str,
    body: SeniorPatch,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("seniors.manage")
    s = db.query(Senior).filter_by(id=senior_id, household_id=access.household_id).first()
    if s is None:
        raise NotFound("Senior not found")
    changes = body.model_dump(exclude_unset=True, exclude_none=True)
    for k, v in changes.items():
        setattr(s, k, v)
    audit.record(
        db,
        actor_id=auth.user.id,
        action="senior.updated",
        target_type="senior",
        target_id=s.id,
        household_id=access.household_id,
        data={"fields": sorted(changes)},
    )
    return _s(s)
