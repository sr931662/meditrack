from datetime import timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.deps import AuthContext, page, require_platform
from app.api.v1.schemas import (
    AdminUserIn,
    AdminUserPatch,
    ConfigIn,
    ReasonIn,
    RolePermsIn,
    SupportAccessIn,
)
from app.core.db import get_db, utcnow
from app.core.errors import AppError, Forbidden, NotFound
from app.core.permissions import (
    HOUSEHOLD_PERMISSIONS,
    HOUSEHOLD_ROLES,
    ORG_ADMIN,
    PLATFORM_PERMISSIONS,
    PLATFORM_ROLES,
    SUPER_ADMIN,
)
from app.models import AuditLog, DoseEvent, Escalation, Household, Membership, RolePermission, SupportAccessGrant, User
from app.services import audit, authz, sysconfig
from app.services import auth as auth_service

router = APIRouter(prefix="/admin", tags=["admin"])


def _user(u: User) -> dict:
    return {
        "id": u.id,
        "email": u.email,
        "full_name": u.full_name,
        "platform_role": u.platform_role,
        "is_active": u.is_active,
        "disabled_reason": u.disabled_reason,
        "created_at": u.created_at,
    }


def _check_role_assignable(db: Session, auth: AuthContext, role: str | None) -> None:
    if role is None:
        return
    if auth.user.platform_role != SUPER_ADMIN:
        raise Forbidden("Only a super administrator can assign platform roles")
    if role == ORG_ADMIN and not sysconfig.get(db, "features.b2b_enabled"):
        raise Forbidden("Healthcare-organisation administration is not enabled on this platform")


@router.get("/users")
def list_users(
    auth: AuthContext = Depends(require_platform("users.read")),
    db: Session = Depends(get_db),
    q: str | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    query = db.query(User)
    if q:
        query = query.filter(User.email.contains(q.lower()))
    total = query.with_entities(func.count()).scalar()
    return page([_user(u) for u in query.order_by(User.created_at).limit(limit).offset(offset)], total, limit, offset)


@router.post("/users", status_code=201)
def create_user(body: AdminUserIn, auth: AuthContext = Depends(require_platform("users.create")), db: Session = Depends(get_db)):
    _check_role_assignable(db, auth, body.platform_role)
    u = auth_service.create_user(
        db, email=body.email, password=body.password, full_name=body.full_name, platform_role=body.platform_role
    )
    audit.record(
        db,
        actor_id=auth.user.id,
        action="user.created",
        target_type="user",
        target_id=u.id,
        data={"email": u.email, "platform_role": u.platform_role},
    )
    return _user(u)


def _target(db: Session, user_id: str) -> User:
    u = db.get(User, user_id)
    if u is None:
        raise NotFound("User not found")
    return u


@router.patch("/users/{user_id}")
def update_user(
    user_id: str,
    body: AdminUserPatch,
    auth: AuthContext = Depends(require_platform("users.update")),
    db: Session = Depends(get_db),
):
    u = _target(db, user_id)
    if body.platform_role is not None:
        new = None if body.platform_role == "none" else body.platform_role
        _check_role_assignable(db, auth, new)
        if u.id == auth.user.id and new != u.platform_role:
            raise AppError("You cannot change your own platform role")
        old, u.platform_role = u.platform_role, new
        auth_service.revoke_all_sessions(db, u.id)  # force re-login so no stale privileges survive
        audit.record(
            db,
            actor_id=auth.user.id,
            action="user.role_changed",
            target_type="user",
            target_id=u.id,
            data={"from": old, "to": new},
        )
    if body.full_name:
        u.full_name = body.full_name
        audit.record(db, actor_id=auth.user.id, action="user.updated", target_type="user", target_id=u.id)
    return _user(u)


@router.post("/users/{user_id}/disable")
def disable_user(
    user_id: str, body: ReasonIn, auth: AuthContext = Depends(require_platform("users.disable")), db: Session = Depends(get_db)
):
    u = _target(db, user_id)
    if u.id == auth.user.id:
        raise AppError("You cannot disable your own account")
    if u.platform_role == SUPER_ADMIN and auth.user.platform_role != SUPER_ADMIN:
        raise Forbidden()
    u.is_active, u.disabled_reason = False, body.reason
    revoked = auth_service.revoke_all_sessions(db, u.id)
    audit.record(
        db,
        actor_id=auth.user.id,
        action="user.disabled",
        target_type="user",
        target_id=u.id,
        data={"reason": body.reason, "sessions_revoked": revoked},
    )
    return _user(u)


@router.post("/users/{user_id}/enable")
def enable_user(user_id: str, auth: AuthContext = Depends(require_platform("users.disable")), db: Session = Depends(get_db)):
    u = _target(db, user_id)
    u.is_active, u.disabled_reason, u.failed_logins, u.locked_until = True, None, 0, None
    audit.record(db, actor_id=auth.user.id, action="user.enabled", target_type="user", target_id=u.id)
    return _user(u)


# ---- roles & permissions ------------------------------------------------------------------------
@router.get("/roles")
def list_roles(auth: AuthContext = Depends(require_platform("roles.manage")), db: Session = Depends(get_db)):
    out = []
    for role in (*PLATFORM_ROLES, *HOUSEHOLD_ROLES):
        out.append(
            {
                "role": role,
                "scope": "platform" if role in PLATFORM_ROLES else "household",
                "permissions": sorted(authz.role_permissions(db, role)),
            }
        )
    return {"roles": out, "available": {"platform": PLATFORM_PERMISSIONS, "household": HOUSEHOLD_PERMISSIONS}}


@router.put("/roles/{role}/permissions")
def set_role_permissions(
    role: str,
    body: RolePermsIn,
    auth: AuthContext = Depends(require_platform("permissions.manage")),
    db: Session = Depends(get_db),
):
    if role not in (*PLATFORM_ROLES, *HOUSEHOLD_ROLES):
        raise NotFound("Unknown role")
    if role == SUPER_ADMIN:
        raise AppError("The super_admin role is fixed so the platform can never be locked out")
    allowed = set(PLATFORM_PERMISSIONS if role in PLATFORM_ROLES else HOUSEHOLD_PERMISSIONS)
    unknown = [p for p in body.permissions if p not in allowed]
    if unknown:
        raise AppError(f"Not valid for role '{role}': {', '.join(sorted(unknown))}", code="validation_error", status_code=422)
    old = authz.role_permissions(db, role)
    db.query(RolePermission).filter_by(role=role).delete()
    for p in sorted(set(body.permissions)):
        db.add(RolePermission(role=role, permission=p))
    db.flush()
    audit.record(
        db,
        actor_id=auth.user.id,
        action="role.permissions_changed",
        target_type="role",
        target_id=role,
        data={"added": sorted(set(body.permissions) - old), "removed": sorted(old - set(body.permissions))},
    )
    return {"role": role, "permissions": sorted(set(body.permissions))}


# ---- audit, config, support, monitoring ---------------------------------------------------------
@router.get("/audit-logs")
def audit_logs(
    auth: AuthContext = Depends(require_platform("audit_logs.read")),
    db: Session = Depends(get_db),
    action: str | None = None,
    actor_id: str | None = None,
    household_id: str | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    q = db.query(AuditLog)
    if action:
        q = q.filter(AuditLog.action == action)
    if actor_id:
        q = q.filter(AuditLog.actor_user_id == actor_id)
    if household_id:
        q = q.filter(AuditLog.household_id == household_id)
    total = q.with_entities(func.count()).scalar()
    rows = q.order_by(AuditLog.at.desc()).limit(limit).offset(offset).all()
    return page(
        [
            {
                "id": r.id,
                "at": r.at,
                "actor_user_id": r.actor_user_id,
                "action": r.action,
                "target_type": r.target_type,
                "target_id": r.target_id,
                "household_id": r.household_id,
                "data": r.data,
            }
            for r in rows
        ],
        total,
        limit,
        offset,
    )


@router.get("/config")
def get_config(auth: AuthContext = Depends(require_platform("system_config.manage")), db: Session = Depends(get_db)):
    return {"values": sysconfig.all_values(db)}


@router.put("/config")
def put_config(
    body: ConfigIn, auth: AuthContext = Depends(require_platform("system_config.manage")), db: Session = Depends(get_db)
):
    for k, v in body.values.items():
        sysconfig.set_value(db, k, v)
    audit.record(db, actor_id=auth.user.id, action="config.updated", data={"keys": sorted(body.values)})
    return {"values": sysconfig.all_values(db)}


@router.post("/support-access", status_code=201)
def grant_support_access(
    body: SupportAccessIn, auth: AuthContext = Depends(require_platform("support.access")), db: Session = Depends(get_db)
):
    if db.get(Household, body.household_id) is None:
        raise NotFound("Household not found")
    g = SupportAccessGrant(
        user_id=auth.user.id,
        household_id=body.household_id,
        reason=body.reason,
        expires_at=utcnow() + timedelta(minutes=body.minutes),
    )
    db.add(g)
    db.flush()
    audit.record(
        db,
        actor_id=auth.user.id,
        action="support_access.granted",
        target_type="household",
        target_id=body.household_id,
        household_id=body.household_id,
        data={"reason": body.reason, "minutes": body.minutes, "grant_id": g.id},
    )
    return {"id": g.id, "expires_at": g.expires_at}


@router.get("/households")
def list_households(
    auth: AuthContext = Depends(require_platform("households.read")),
    db: Session = Depends(get_db),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """Operational metadata only. No medication, adherence or other health data is exposed here."""
    total = db.query(func.count(Household.id)).scalar()
    rows = db.query(Household).order_by(Household.created_at).limit(limit).offset(offset).all()
    counts = dict(db.query(Membership.household_id, func.count()).group_by(Membership.household_id).all())
    return page(
        [{"id": h.id, "name": h.name, "plan": h.plan, "members": counts.get(h.id, 0), "created_at": h.created_at} for h in rows],
        total,
        limit,
        offset,
    )


@router.get("/stats")
def stats(auth: AuthContext = Depends(require_platform("system.monitor")), db: Session = Depends(get_db)):
    return {
        "users": db.query(func.count(User.id)).scalar(),
        "households": db.query(func.count(Household.id)).scalar(),
        "dose_events_24h": db.query(func.count(DoseEvent.id))
        .filter(DoseEvent.scheduled_for >= utcnow() - timedelta(hours=24))
        .scalar(),
        "open_escalations": db.query(func.count(Escalation.id)).filter(Escalation.status != "resolved").scalar(),
    }
