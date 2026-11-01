"""Dose events, verification, escalations, offline sync, notifications and the caregiver dashboard."""

from datetime import UTC, date, datetime, time, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.deps import AuthContext, get_auth, get_household_access, page, require_any
from app.api.v1.schemas import CaregiverConfirmIn, NoteIn, ResolveIn, RespondIn, SyncIn, VerificationIn
from app.core.db import get_db, utcnow
from app.core.errors import NotFound
from app.integrations.demo import DEMO_ID_PREFIX
from app.models import (
    DoseEvent,
    Escalation,
    EscalationDelivery,
    Medication,
    Notification,
    Senior,
)
from app.services import doses, engine, sync, verification
from app.services.authz import HouseholdAccess

router = APIRouter(prefix="/households/{household_id}", tags=["doses"])


# ---- serialisation ------------------------------------------------------------------------------
def _delivery(d: EscalationDelivery) -> dict:
    return {
        "id": d.id,
        "contact_name": d.contact_name,
        "channel": d.channel,
        "status": d.status,
        "attempts": d.attempts,
        "last_error": d.last_error,
        "simulated": bool(d.provider_message_id and d.provider_message_id.startswith(DEMO_ID_PREFIX)),
        "updated_at": d.updated_at,
    }


def _esc(e: Escalation, deliveries: bool = False, context: dict | None = None) -> dict:
    out = {
        "id": e.id,
        "dose_event_id": e.dose_event_id,
        "status": e.status,
        "priority": e.priority,
        "reason": e.reason,
        "triggered_at": e.triggered_at,
        "acknowledged_at": e.acknowledged_at,
        "resolved_at": e.resolved_at,
        "outcome": e.outcome,
        "resolution_note": e.resolution_note,
    }
    if deliveries:
        out["deliveries"] = [_delivery(d) for d in e.deliveries]
    if context:
        out.update(context)
    return out


def _esc_context(db: Session, e: Escalation) -> dict:
    """Names a caregiver needs on the list/detail view without extra round trips."""
    ev = e.dose_event
    senior, med = db.get(Senior, ev.senior_id), db.get(Medication, ev.medication_id)
    return {
        "senior_id": ev.senior_id,
        "senior_name": senior.full_name if senior else "?",
        "senior_phone": senior.phone if senior else None,
        "medication": f"{med.name} {med.strength}" if med else "?",
        "scheduled_for": ev.scheduled_for,
    }


def _verification(v) -> dict:
    return {
        "id": v.id,
        "status": v.status,
        "confidence": v.confidence,
        "matched_medication_id": v.matched_medication_id,
        "extracted_text": v.extracted_text,
        "barcode": v.barcode,
        "packaging": v.packaging,
        "reasons": v.reasons,
        "next_action": v.next_action,
        "provider": v.provider,
        "model": v.model,
        "created_at": v.created_at,
    }


def _event(e: DoseEvent, detail: bool = False) -> dict:
    out = {
        "id": e.id,
        "senior_id": e.senior_id,
        "medication_id": e.medication_id,
        "schedule_id": e.schedule_id,
        "scheduled_for": e.scheduled_for,
        "display_status": e.display_status,
        # each fact is reported separately so the UI can never blur them together
        "reminder_sent_at": e.reminder_sent_at,
        "acknowledged_at": e.acknowledged_at,
        "packaging_matched": e.packaging_matched,
        "user_reported_taken_at": e.user_reported_taken_at,
        "caregiver_status": e.caregiver_status,
        "caregiver_confirmed_at": e.caregiver_confirmed_at,
        "independently_confirmed": e.independently_confirmed,
        "help_requested_at": e.help_requested_at,
        "snoozed_until": e.snoozed_until,
        "resolved_at": e.resolved_at,
        "escalation": _esc(e.escalation, deliveries=detail) if e.escalation else None,
    }
    if detail:
        out["verifications"] = [_verification(v) for v in e.verifications]
        out["timeline"] = [
            {"type": lg.type, "at": lg.at, "data": lg.data} for lg in sorted(e.logs, key=lambda x: (x.at, x.recorded_at))
        ]
    return out


def _scoped_event(db: Session, access: HouseholdAccess, event_id: str) -> DoseEvent:
    q = db.query(DoseEvent).filter_by(id=event_id, household_id=access.household_id)
    if access.role == "senior":
        q = q.filter(DoseEvent.senior_id == access.senior_id)
    e = q.first()
    if e is None:
        raise NotFound("Dose event not found")
    return e


def _day_bounds(d: date) -> tuple[datetime, datetime]:
    start = datetime.combine(d, time.min, tzinfo=UTC)
    return start, start + timedelta(days=1)


# ---- dose events --------------------------------------------------------------------------------
@router.get("/dose-events")
def list_dose_events(
    access: HouseholdAccess = Depends(get_household_access),
    db: Session = Depends(get_db),
    on: date | None = Query(None, alias="date"),
    senior_id: str | None = None,
    medication_id: str | None = None,
    status: str | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    require_any(access, "adherence.read", "reminders.read")
    q = db.query(DoseEvent).filter_by(household_id=access.household_id)
    if access.role == "senior":
        senior_id = access.senior_id
    if senior_id:
        q = q.filter(DoseEvent.senior_id == senior_id)
    if medication_id:
        q = q.filter(DoseEvent.medication_id == medication_id)
    if on:
        lo, hi = _day_bounds(on)
        q = q.filter(DoseEvent.scheduled_for >= lo, DoseEvent.scheduled_for < hi)
    rows = q.order_by(DoseEvent.scheduled_for).all()
    if status:
        rows = [r for r in rows if r.display_status == status]
    total = len(rows)
    return page([_event(r) for r in rows[offset : offset + limit]], total, limit, offset)


@router.get("/dose-events/{event_id}")
def get_dose_event(event_id: str, access: HouseholdAccess = Depends(get_household_access), db: Session = Depends(get_db)):
    require_any(access, "adherence.read", "reminders.read")
    return _event(_scoped_event(db, access, event_id), detail=True)


@router.post("/dose-events/{event_id}/respond")
def respond(
    event_id: str,
    body: RespondIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("doses.respond")
    e = _scoped_event(db, access, event_id)
    changed = doses.apply_response(db, e, body.response, body.occurred_at or utcnow(), auth.user.id)
    return {"changed": changed, "event": _event(e)}


@router.post("/dose-events/{event_id}/verifications", status_code=201)
def submit_verification(
    event_id: str,
    body: VerificationIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("verification.submit")
    e = _scoped_event(db, access, event_id)
    row = verification.verify_dose(db, e, body.extracted_text, body.barcode, body.image_ref, auth.user.id, utcnow())
    return _verification(row)


@router.post("/dose-events/{event_id}/caregiver-confirm")
def caregiver_confirm(
    event_id: str,
    body: CaregiverConfirmIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("verification.review")
    e = _scoped_event(db, access, event_id)
    doses.caregiver_confirm(db, e, body.status, body.note, utcnow(), auth.user.id)
    return _event(e)


@router.post("/dose-events/{event_id}/request-verification")
def request_verification(
    event_id: str,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    """A caregiver asks the senior to show the packaging again. Informational prompt only."""
    access.require("verification.review")
    e = _scoped_event(db, access, event_id)
    now = utcnow()
    engine.log_event(db, e, "verification_requested", now, auth.user.id)
    med = db.get(Medication, e.medication_id)
    db.add(
        Notification(
            household_id=e.household_id,
            senior_id=e.senior_id,
            recipient_role="senior",
            kind="verification_prompt",
            title=f"Please check your {med.name}",
            body="Your caregiver asked you to show the medicine box to the camera.",
            dose_event_id=e.id,
            created_at=now,
        )
    )
    return {"ok": True}


# ---- escalations --------------------------------------------------------------------------------
def _scoped_escalation(db: Session, access: HouseholdAccess, esc_id: str) -> Escalation:
    e = db.query(Escalation).filter_by(id=esc_id, household_id=access.household_id).first()
    if e is None:
        raise NotFound("Escalation not found")
    return e


@router.get("/escalations")
def list_escalations(
    access: HouseholdAccess = Depends(get_household_access),
    db: Session = Depends(get_db),
    status: str | None = Query(None, pattern="^(open|resolved|acknowledged)$"),
    priority: str | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    access.require("escalation.read")
    q = db.query(Escalation).filter_by(household_id=access.household_id)
    if status == "open":  # "needs attention": not yet resolved
        q = q.filter(Escalation.status != "resolved")
    elif status:
        q = q.filter(Escalation.status == status)
    if priority:
        q = q.filter(Escalation.priority == priority)
    total = q.with_entities(func.count()).scalar()
    rows = q.order_by(Escalation.triggered_at.desc()).limit(limit).offset(offset).all()
    return page([_esc(r, deliveries=True, context=_esc_context(db, r)) for r in rows], total, limit, offset)


@router.get("/escalations/{esc_id}")
def get_escalation(esc_id: str, access: HouseholdAccess = Depends(get_household_access), db: Session = Depends(get_db)):
    access.require("escalation.read")
    e = _scoped_escalation(db, access, esc_id)
    return {**_esc(e, deliveries=True, context=_esc_context(db, e)), "event": _event(e.dose_event, detail=True)}


@router.post("/escalations/{esc_id}/acknowledge")
def acknowledge(
    esc_id: str,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("escalation.acknowledge")
    e = _scoped_escalation(db, access, esc_id)
    doses.acknowledge_escalation(db, e, utcnow(), auth.user.id)
    return _esc(e)


@router.post("/escalations/{esc_id}/notes", status_code=201)
def add_note(
    esc_id: str,
    body: NoteIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("escalation.acknowledge")
    e = _scoped_escalation(db, access, esc_id)
    engine.log_event(db, e.dose_event, "caregiver_note", utcnow(), auth.user.id, note=body.note)
    return {"ok": True}


@router.post("/escalations/{esc_id}/resolve")
def resolve(
    esc_id: str,
    body: ResolveIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("escalation.resolve")
    e = _scoped_escalation(db, access, esc_id)
    doses.resolve_escalation(db, e, body.outcome, body.note, utcnow(), auth.user.id)
    return _esc(e)


# ---- offline sync -------------------------------------------------------------------------------
@router.post("/sync/events")
def sync_events(
    body: SyncIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("doses.respond")
    results = sync.apply_batch(db, access, auth.user.id, [e.model_dump() for e in body.events], utcnow())
    return {"results": results, "server_time": utcnow()}


# ---- notifications ------------------------------------------------------------------------------
@router.get("/notifications")
def notifications(
    access: HouseholdAccess = Depends(get_household_access),
    db: Session = Depends(get_db),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    require_any(access, "reminders.read", "escalation.read")
    q = db.query(Notification).filter_by(household_id=access.household_id)
    if access.role == "senior":
        q = q.filter(Notification.recipient_role == "senior", Notification.senior_id == access.senior_id)
    else:
        q = (
            q.filter(Notification.recipient_role == "caregivers")
            if "escalation.read" in access.permissions
            else q.filter(Notification.recipient_role == "senior")
        )
    total = q.with_entities(func.count()).scalar()
    rows = q.order_by(Notification.created_at.desc()).limit(limit).offset(offset).all()
    return page(
        [
            {
                "id": n.id,
                "kind": n.kind,
                "title": n.title,
                "body": n.body,
                "dose_event_id": n.dose_event_id,
                "created_at": n.created_at,
            }
            for n in rows
        ],
        total,
        limit,
        offset,
    )


# ---- dashboard ----------------------------------------------------------------------------------
@router.get("/dashboard")
def dashboard(
    access: HouseholdAccess = Depends(get_household_access),
    db: Session = Depends(get_db),
    on: date | None = Query(None, alias="date"),
    senior_id: str | None = None,
    medication_id: str | None = None,
    priority: str | None = None,
):
    """Counts keep the evidence levels apart: packaging match, self-report and caregiver confirmation
    are separate numbers and are never summed into a single 'taken' figure."""
    access.require("adherence.read")
    day = on or utcnow().date()
    lo, hi = _day_bounds(day)
    hid = access.household_id
    q = db.query(DoseEvent).filter(DoseEvent.household_id == hid, DoseEvent.scheduled_for >= lo, DoseEvent.scheduled_for < hi)
    if senior_id:
        q = q.filter(DoseEvent.senior_id == senior_id)
    if medication_id:
        q = q.filter(DoseEvent.medication_id == medication_id)
    events = q.order_by(DoseEvent.scheduled_for).all()
    policy = engine.get_policy(db, hid)
    now = utcnow()

    def unverified(e: DoseEvent) -> bool:
        waiting = e.reminder_sent_at and not (e.user_reported_taken_at or e.caregiver_status)
        return bool(waiting and (e.escalation or now >= e.scheduled_for + timedelta(minutes=policy.t_escalate_min)))

    meds = {m.id: m for m in db.query(Medication).filter_by(household_id=hid)}
    by_med: dict[str, dict] = {}
    for e in events:
        m = by_med.setdefault(
            e.medication_id,
            {
                "medication_id": e.medication_id,
                "name": meds[e.medication_id].name if e.medication_id in meds else "?",
                "scheduled": 0,
                "packaging_matched": 0,
                "user_reported_taken": 0,
                "caregiver_confirmed": 0,
                "unverified": 0,
            },
        )
        m["scheduled"] += 1
        m["packaging_matched"] += e.packaging_matched
        m["user_reported_taken"] += bool(e.user_reported_taken_at)
        m["caregiver_confirmed"] += e.independently_confirmed
        m["unverified"] += unverified(e)

    esc_q = db.query(Escalation).filter_by(household_id=hid)
    if priority:
        esc_q = esc_q.filter(Escalation.priority == priority)
    escs = esc_q.all()
    ev_ids = [e.id for e in events]
    deliveries: dict[str, int] = {}
    if ev_ids:
        for status, n in (
            db.query(EscalationDelivery.status, func.count())
            .join(Escalation, Escalation.id == EscalationDelivery.escalation_id)
            .filter(Escalation.dose_event_id.in_(ev_ids))
            .group_by(EscalationDelivery.status)
        ):
            deliveries[status] = n
    recent = []
    for e in events:
        for lg in e.logs:
            recent.append({"dose_event_id": e.id, "medication_id": e.medication_id, "type": lg.type, "at": lg.at})
    recent.sort(key=lambda r: r["at"], reverse=True)
    return {
        "date": day.isoformat(),
        "total_seniors": db.query(Senior).filter_by(household_id=hid, is_active=True).count(),
        "scheduled": len(events),
        "reminders_sent": sum(1 for e in events if e.reminder_sent_at),
        "packaging_matched": sum(1 for e in events if e.packaging_matched),
        "user_reported_taken": sum(1 for e in events if e.user_reported_taken_at),
        "caregiver_confirmed": sum(1 for e in events if e.independently_confirmed),
        "unverified": sum(1 for e in events if unverified(e)),
        "pending_interventions": sum(1 for x in escs if x.status != "resolved"),
        "active_escalations": sum(1 for x in escs if x.status == "open"),
        "acknowledged_escalations": sum(1 for x in escs if x.status == "acknowledged"),
        "resolved_escalations": sum(1 for x in escs if x.status == "resolved"),
        "delivery_status": deliveries,
        "by_medication": list(by_med.values()),
        "recent_activity": recent[:20],
    }


@router.get("/dashboard/trend")
def dashboard_trend(
    access: HouseholdAccess = Depends(get_household_access),
    db: Session = Depends(get_db),
    on: date | None = Query(None, alias="date"),
    days: int = Query(7, ge=1, le=60),
    senior_id: str | None = None,
    medication_id: str | None = None,
):
    """Per-day counts for the chart. There is deliberately no 'missed' series: only a caregiver's recorded
    decision produces `caregiver_not_taken`, and unconfirmed doses are reported as `unverified`."""
    access.require("adherence.read")
    end_day = on or utcnow().date()
    first = end_day - timedelta(days=days - 1)
    lo, _ = _day_bounds(first)
    _, hi = _day_bounds(end_day)
    q = db.query(DoseEvent).filter(
        DoseEvent.household_id == access.household_id, DoseEvent.scheduled_for >= lo, DoseEvent.scheduled_for < hi
    )
    if senior_id:
        q = q.filter(DoseEvent.senior_id == senior_id)
    if medication_id:
        q = q.filter(DoseEvent.medication_id == medication_id)
    policy = engine.get_policy(db, access.household_id)
    now = utcnow()
    buckets = {
        (first + timedelta(days=i)).isoformat(): dict(
            date=(first + timedelta(days=i)).isoformat(),
            scheduled=0,
            packaging_matched=0,
            user_reported_taken=0,
            caregiver_confirmed=0,
            caregiver_not_taken=0,
            unverified=0,
        )
        for i in range(days)
    }
    for e in q:
        b = buckets[e.scheduled_for.date().isoformat()]
        b["scheduled"] += 1
        b["packaging_matched"] += e.packaging_matched
        b["user_reported_taken"] += bool(e.user_reported_taken_at) and not e.caregiver_status
        b["caregiver_confirmed"] += e.caregiver_status == "taken"
        b["caregiver_not_taken"] += e.caregiver_status == "not_taken"
        waiting = e.reminder_sent_at and not (e.user_reported_taken_at or e.caregiver_status)
        b["unverified"] += bool(waiting and (e.escalation or now >= e.scheduled_for + timedelta(minutes=policy.t_escalate_min)))
    return {"days": list(buckets.values())}
