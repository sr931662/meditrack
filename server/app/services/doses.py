"""State changes on a dose, shared by the HTTP API and the offline-sync endpoint."""

from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import DoseEvent, Escalation
from app.services import audit, engine

RESPONSES = {"acknowledged", "taken", "help", "cannot_find", "unwell", "remind_later"}
HELP_RESPONSES = {"help", "cannot_find", "unwell"}


def apply_response(db: Session, event: DoseEvent, response: str, occurred_at: datetime, actor_id: str | None) -> bool:
    """Record what the senior said. Returns False if it changed nothing (already recorded / dose closed)."""
    if response not in RESPONSES:
        raise AppError(f"Unknown response '{response}'", code="validation_error", status_code=422)
    if event.resolved_at or event.caregiver_status:
        engine.log_event(db, event, "late_response", occurred_at, actor_id, response=response)
        return False

    if response == "acknowledged":
        if event.acknowledged_at:
            return False
        event.acknowledged_at = occurred_at
        engine.log_event(db, event, "acknowledged", occurred_at, actor_id)
    elif response == "taken":
        if event.user_reported_taken_at:
            return False
        event.user_reported_taken_at = occurred_at
        event.acknowledged_at = event.acknowledged_at or occurred_at
        # A self-report, nothing more: it is never presented as verified (see DoseEvent.independently_confirmed).
        engine.log_event(db, event, "user_reported_taken", occurred_at, actor_id)
    elif response in HELP_RESPONSES:
        if event.help_requested_at:
            return False
        event.help_requested_at, event.help_reason = occurred_at, response
        event.acknowledged_at = event.acknowledged_at or occurred_at
        engine.log_event(db, event, "help_requested", occurred_at, actor_id, reason=response)
        engine.move_escalation_job(db, event, occurred_at)  # a request for help is not left waiting 45 minutes
    elif response == "remind_later":
        event.snoozed_until = occurred_at + timedelta(minutes=engine.SNOOZE_MIN)
        engine.log_event(db, event, "snoozed", occurred_at, actor_id, until=event.snoozed_until.isoformat())
        policy = engine.get_policy(db, event.household_id)
        engine.move_escalation_job(db, event, occurred_at + timedelta(minutes=policy.t_escalate_min))
        engine.add_reminder_job(db, event, event.snoozed_until)
    db.flush()
    return True


def caregiver_confirm(db: Session, event: DoseEvent, status: str, note: str, now: datetime, actor_id: str) -> None:
    if status not in ("taken", "not_taken"):
        raise AppError("status must be 'taken' or 'not_taken'", code="validation_error", status_code=422)
    event.caregiver_status = status
    event.caregiver_confirmed_at = now
    engine.log_event(db, event, "caregiver_confirmed", now, actor_id, status=status, note=note)
    audit.record(
        db,
        actor_id=actor_id,
        action="dose.caregiver_confirmed",
        target_type="dose_event",
        target_id=event.id,
        household_id=event.household_id,
        data={"status": status},
    )
    db.flush()


def acknowledge_escalation(db: Session, esc: Escalation, now: datetime, actor_id: str) -> None:
    if esc.status != "open":
        return  # idempotent
    esc.status, esc.acknowledged_by, esc.acknowledged_at = "acknowledged", actor_id, now
    engine.log_event(db, esc.dose_event, "escalation_acknowledged", now, actor_id)
    audit.record(
        db,
        actor_id=actor_id,
        action="escalation.acknowledged",
        target_type="escalation",
        target_id=esc.id,
        household_id=esc.household_id,
    )


def resolve_escalation(db: Session, esc: Escalation, outcome: str, note: str, now: datetime, actor_id: str) -> None:
    if esc.status == "resolved":
        return
    if esc.status != "acknowledged":
        raise AppError("Acknowledge the escalation before resolving it", code="conflict", status_code=409)
    event = esc.dose_event
    esc.status, esc.resolved_by, esc.resolved_at, esc.outcome, esc.resolution_note = "resolved", actor_id, now, outcome, note
    event.resolved_at = now
    if outcome == "taken_confirmed":
        event.caregiver_status, event.caregiver_confirmed_at = "taken", now
    elif outcome == "not_taken_confirmed":  # only ever set by a human who verified it
        event.caregiver_status, event.caregiver_confirmed_at = "not_taken", now
    engine.log_event(db, event, "escalation_resolved", now, actor_id, outcome=outcome, note=note)
    audit.record(
        db,
        actor_id=actor_id,
        action="escalation.resolved",
        target_type="escalation",
        target_id=esc.id,
        household_id=esc.household_id,
        data={"outcome": outcome},
    )
