from sqlalchemy.orm import Session

from app.models import AuditLog


def record(
    db: Session,
    *,
    actor_id: str | None,
    action: str,
    target_type: str | None = None,
    target_id: str | None = None,
    household_id: str | None = None,
    data: dict | None = None,
) -> AuditLog:
    """Writes in the caller's transaction: if the audited operation rolls back so does its audit row,
    and if this call fails the operation fails too (an action can never succeed without its audit)."""
    row = AuditLog(
        actor_user_id=actor_id,
        action=action,
        target_type=target_type,
        target_id=target_id,
        household_id=household_id,
        data=data or {},
    )
    db.add(row)
    db.flush()
    return row
