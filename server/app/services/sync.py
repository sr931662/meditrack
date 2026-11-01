"""Offline event ingestion. Each device event carries a client-generated id; applying it twice is a no-op."""

from datetime import datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import DoseEvent, Schedule, SyncReceipt
from app.services import doses, engine
from app.services.authz import HouseholdAccess


def _resolve_event(db: Session, access: HouseholdAccess, raw: dict) -> DoseEvent | None:
    hid = access.household_id
    if raw.get("dose_event_id"):
        ev = db.query(DoseEvent).filter_by(id=raw["dose_event_id"], household_id=hid).first()
    elif raw.get("schedule_id") and raw.get("scheduled_for"):
        sch = db.query(Schedule).filter_by(id=raw["schedule_id"], household_id=hid).first()
        if sch is None:
            return None
        when: datetime = raw["scheduled_for"]
        if when not in engine.occurrences(sch, when, when):
            return None  # not a real occurrence of this schedule
        ev = engine.create_dose_event(db, sch, when, with_jobs=False)
    else:
        return None
    if ev is not None and access.role == "senior" and ev.senior_id != access.senior_id:
        return None
    return ev


def apply_batch(db: Session, access: HouseholdAccess, actor_id: str, events: list[dict], now: datetime) -> list[dict]:
    results = []
    ordered = sorted(events, key=lambda e: e.get("occurred_at") or now)
    by_id = {}
    for raw in ordered:
        cid = raw["client_event_id"]
        if db.query(SyncReceipt.id).filter_by(household_id=access.household_id, client_event_id=cid).first():
            by_id[cid] = "duplicate"
            continue
        try:
            with db.begin_nested():
                ev = _resolve_event(db, access, raw)
                if ev is None:
                    by_id[cid] = "rejected"
                    continue
                if raw["type"] != "respond":
                    raise AppError("Unsupported event type", code="validation_error")
                doses.apply_response(db, ev, raw["response"], raw.get("occurred_at") or now, actor_id)
                db.add(SyncReceipt(household_id=access.household_id, client_event_id=cid, result="applied"))
                db.flush()
            by_id[cid] = "applied"
        except IntegrityError:
            by_id[cid] = "duplicate"
        except AppError:
            by_id[cid] = "rejected"
    for raw in events:  # answer in the caller's original order
        results.append({"client_event_id": raw["client_event_id"], "result": by_id[raw["client_event_id"]]})
    return results
