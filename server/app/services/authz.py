"""The single place that answers 'may this user do X (in this household)?'. Reads the database on every
call, so role/permission edits and revocations take effect immediately without re-issuing tokens."""

from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.core.db import utcnow
from app.core.errors import Forbidden, NotFound
from app.core.permissions import SUPPORT_READ_PERMISSIONS
from app.models import Membership, RolePermission, SupportAccessGrant, User


def role_permissions(db: Session, role: str) -> set[str]:
    return {p for (p,) in db.query(RolePermission.permission).filter_by(role=role)}


def platform_permissions(db: Session, user: User) -> set[str]:
    return role_permissions(db, user.platform_role) if user.platform_role else set()


@dataclass
class HouseholdAccess:
    household_id: str
    role: str  # owner | caregiver | senior | support
    permissions: set[str]
    senior_id: str | None = None  # a senior only ever sees their own records
    membership: Membership | None = None

    def require(self, permission: str) -> None:
        if permission not in self.permissions:
            raise Forbidden()


def household_access(db: Session, user: User, household_id: str) -> HouseholdAccess:
    """Membership is required; non-members get 404 so household ids cannot be probed."""
    m = db.query(Membership).filter_by(household_id=household_id, user_id=user.id).first()
    if m is not None:
        if m.role == "caregiver":
            perms = set(m.permissions or [])
        else:
            perms = role_permissions(db, m.role)
        return HouseholdAccess(household_id, m.role, perms, m.senior_id, m)
    if user.platform_role and "support.access" in platform_permissions(db, user):
        grant = (
            db.query(SupportAccessGrant)
            .filter(
                SupportAccessGrant.user_id == user.id,
                SupportAccessGrant.household_id == household_id,
                SupportAccessGrant.expires_at > utcnow(),
            )
            .first()
        )
        if grant:
            return HouseholdAccess(household_id, "support", set(SUPPORT_READ_PERMISSIONS))
        raise Forbidden("Support access needs a recorded reason; request a time-boxed support grant first")
    raise NotFound("Household not found")
