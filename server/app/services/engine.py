"""Reminder / verify / escalate engine.

Design rules (see docs/ARCHITECTURE.md):
* Every function takes an explicit `now`, so behaviour is deterministic and testable.
* Work is driven by the `jobs` table (a transactional outbox), never by an in-memory scheduler, so a
  restart or deploy loses nothing. Jobs are claimed with SELECT ... FOR UPDATE SKIP LOCKED on PostgreSQL.
* Every side effect is guarded by state already in the database (job status, unique escalation per dose,
  unique delivery idempotency keys), so replays and concurrent workers cannot duplicate escalations.
* An unconfirmed dose is described as "not confirmed", never as "missed". Only a human can record that.
"""

from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.integrations.base import OutboundMessage
from app.integrations.registry import Providers
from app.models import (
    DoseEvent,
    DoseEventLog,
    Escalation,
    EscalationDelivery,
    EscalationPolicy,
    Job,
    Medication,
    Notification,
    Schedule,
    Senior,
)

MAX_DELIVERY_ATTEMPTS = 5
RETRY_BACKOFF_MIN = 5  # n-th failure waits n * 5 minutes
LOOKBACK_MIN = 5
SNOOZE_MIN = 10

FINAL_FOR_ESCALATION = ("caregiver_status", "resolved_at")


def log_event(db: Session, event: DoseEvent, type_: str, at: datetime, actor_id: str | None = None, **data) -> DoseEventLog:
    row = DoseEventLog(dose_event_id=event.id, type=type_, at=at, actor_user_id=actor_id, data=data)
    event.logs.append(row)  # cascades into the session
    return row


def get_policy(db: Session, household_id: str) -> EscalationPolicy:
    p = db.query(EscalationPolicy).filter_by(household_id=household_id).first()
    if p is None:
        p = EscalationPolicy(household_id=household_id, t_verify_min=5, t_escalate_min=45, contacts=[])
        db.add(p)
        db.flush()
    return p


# ---- materialisation ------------------------------------------------------------------------------


def _local_to_utc(d: date, hhmm: str, tz: ZoneInfo) -> datetime:
    h, m = (int(x) for x in hhmm.split(":"))
    return datetime.combine(d, time(h, m), tzinfo=tz).astimezone(UTC)


def occurrences(schedule: Schedule, start: datetime, end: datetime) -> list[datetime]:
    tz = ZoneInfo(schedule.timezone)
    first = start.astimezone(tz).date() - timedelta(days=1)
    last = end.astimezone(tz).date() + timedelta(days=1)
    out = []
    d = first
    while d <= last:
        in_range = d >= schedule.start_date and (schedule.end_date is None or d <= schedule.end_date)
        if in_range and d.weekday() in schedule.weekdays:
            for hhmm in schedule.times:
                t = _local_to_utc(d, hhmm, tz)
                if start <= t <= end:
                    out.append(t)
        d += timedelta(days=1)
    return sorted(out)


def _add_job(db: Session, kind: str, event: DoseEvent, run_at: datetime, key: str | None = None) -> None:
    dedupe = key or f"{event.id}:{kind}"
    if db.query(Job.id).filter_by(dedupe_key=dedupe).first():
        return
    db.add(Job(kind=kind, dose_event_id=event.id, run_at=run_at, dedupe_key=dedupe))


def create_dose_event(db: Session, schedule: Schedule, scheduled_for: datetime, *, with_jobs: bool = True) -> DoseEvent:
    existing = db.query(DoseEvent).filter_by(schedule_id=schedule.id, scheduled_for=scheduled_for).first()
    if existing:
        return existing
    event = DoseEvent(
        household_id=schedule.household_id,
        senior_id=schedule.senior_id,
        medication_id=schedule.medication_id,
        schedule_id=schedule.id,
        scheduled_for=scheduled_for,
    )
    try:
        with db.begin_nested():
            db.add(event)
            db.flush()
    except IntegrityError:  # another worker created it first
        return db.query(DoseEvent).filter_by(schedule_id=schedule.id, scheduled_for=scheduled_for).one()
    if with_jobs:
        policy = get_policy(db, schedule.household_id)
        _add_job(db, "reminder", event, scheduled_for)
        _add_job(db, "verify", event, scheduled_for + timedelta(minutes=policy.t_verify_min))
        _add_job(db, "escalate", event, scheduled_for + timedelta(minutes=policy.t_escalate_min))
    return event


def materialize(db: Session, now: datetime, horizon_hours: int = 24) -> int:
    """Create dose events (and their jobs) for every active schedule occurring in the window. Idempotent."""
    start, end = now - timedelta(minutes=LOOKBACK_MIN), now + timedelta(hours=horizon_hours)
    created = 0
    q = (
        db.query(Schedule)
        .join(Medication, Medication.id == Schedule.medication_id)
        .filter(Schedule.is_active.is_(True), Medication.is_active.is_(True))
    )
    for sch in q:
        for t in occurrences(sch, start, end):
            before = db.query(DoseEvent.id).filter_by(schedule_id=sch.id, scheduled_for=t).first()
            if before is None:
                create_dose_event(db, sch, t)
                created += 1
    db.flush()
    return created


def reschedule_pending(db: Session, household_id: str) -> None:
    """Apply a changed escalation policy to doses that have not been escalated or finished yet."""
    policy = get_policy(db, household_id)
    events = db.query(DoseEvent).filter_by(household_id=household_id, resolved_at=None, caregiver_status=None).all()
    for e in events:
        for kind, minutes in (("verify", policy.t_verify_min), ("escalate", policy.t_escalate_min)):
            job = db.query(Job).filter_by(dedupe_key=f"{e.id}:{kind}", status="pending").first()
            if job:
                base = (
                    e.snoozed_until - timedelta(minutes=SNOOZE_MIN)
                    if (kind == "escalate" and e.snoozed_until)
                    else e.scheduled_for
                )
                job.run_at = base + timedelta(minutes=minutes)


def move_escalation_job(db: Session, event: DoseEvent, run_at: datetime) -> None:
    job = db.query(Job).filter_by(dedupe_key=f"{event.id}:escalate", status="pending").first()
    if job:
        job.run_at = run_at


def add_reminder_job(db: Session, event: DoseEvent, run_at: datetime) -> None:
    _add_job(db, "reminder", event, run_at, key=f"{event.id}:reminder:{run_at.isoformat()}")


# ---- processing -----------------------------------------------------------------------------------


def _notify(db: Session, event: DoseEvent, recipient: str, kind: str, title: str, body: str, now: datetime) -> None:
    db.add(
        Notification(
            household_id=event.household_id,
            senior_id=event.senior_id,
            recipient_role=recipient,
            kind=kind,
            title=title,
            body=body,
            dose_event_id=event.id,
            created_at=now,
        )
    )


def _context(db: Session, event: DoseEvent) -> tuple[Senior, Medication, Schedule | None]:
    return db.get(Senior, event.senior_id), db.get(Medication, event.medication_id), db.get(Schedule, event.schedule_id)


def _local_time_text(event: DoseEvent, senior: Senior) -> str:
    return event.scheduled_for.astimezone(ZoneInfo(senior.timezone)).strftime("%I:%M %p").lstrip("0")


def _is_settled(event: DoseEvent) -> bool:
    return bool(event.caregiver_status or event.resolved_at)


def process_due(db: Session, now: datetime, providers: Providers) -> dict:
    stats = {"jobs": 0, "retried": 0}
    db.flush()
    db.expire_all()  # always act on committed state written by API sessions, never a stale snapshot
    jobs = (
        db.query(Job)
        .filter(Job.status == "pending", Job.run_at <= now)
        .order_by(Job.run_at)
        .with_for_update(skip_locked=True)
        .all()
    )
    for job in jobs:
        event = db.get(DoseEvent, job.dose_event_id)
        try:
            with db.begin_nested():
                _HANDLERS[job.kind](db, event, job, now, providers)
        except Exception:  # leave the job pending so the next tick retries; never swallow silently
            import logging

            logging.getLogger("medtrack.engine").exception("job %s (%s) failed", job.id, job.kind)
            continue
        job.status = "done"
        job.finished_at = now
        stats["jobs"] += 1
    stats["retried"] = retry_failed_deliveries(db, now, providers)
    db.flush()
    return stats


def _do_reminder(db, event, job, now, providers):
    if _is_settled(event) or event.user_reported_taken_at:
        job.status = "cancelled"
        return
    senior, med, sched = _context(db, event)
    repeat = event.reminder_sent_at is not None
    event.reminder_sent_at = event.reminder_sent_at or now
    log_event(db, event, "reminder_repeated" if repeat else "reminder_sent", now)
    msg = sched.reminder_message if sched and sched.reminder_message else f"Time for your {med.name} {med.strength}."
    _notify(db, event, "senior", "reminder", f"Time for {med.name}", msg, now)


def _do_verify(db, event, job, now, providers):
    if _is_settled(event) or event.user_reported_taken_at or event.verification_prompted_at:
        job.status = "cancelled"
        return
    senior, med, _ = _context(db, event)
    event.verification_prompted_at = now
    log_event(db, event, "verification_prompt", now)
    _notify(
        db,
        event,
        "senior",
        "verification_prompt",
        f"Check your {med.name}",
        "Please show the medicine box to the camera, or tell us you have taken it.",
        now,
    )


def _compose_message(senior: Senior, med: Medication, event: DoseEvent) -> str:
    when = _local_time_text(event, senior)
    if event.help_requested_at:
        why = {"unwell": "said they are not feeling well", "cannot_find": "cannot find their medicine"}.get(
            event.help_reason or "", "asked for help"
        )
        return f"MediTrack: {senior.full_name} {why} ({med.name} {med.strength}, due {when}). Please contact them."
    return (
        f"MediTrack: {senior.full_name} has not confirmed {med.name} {med.strength} due at {when}. "
        "We cannot tell whether it was taken. Please check in with them."
    )


def _do_escalate(db, event, job, now, providers):
    if event.escalation is not None:
        job.status = "cancelled"
        return
    help_needed = event.help_requested_at is not None
    if _is_settled(event) or (event.user_reported_taken_at and not help_needed):
        job.status = "cancelled"
        return
    senior, med, _ = _context(db, event)
    reason = f"help_requested:{event.help_reason}" if help_needed else "no_confirmation"
    esc = Escalation(
        dose_event_id=event.id,
        household_id=event.household_id,
        reason=reason,
        priority="high" if help_needed else "normal",
        triggered_at=now,
    )
    try:
        with db.begin_nested():
            db.add(esc)
            db.flush()
    except IntegrityError:
        job.status = "cancelled"
        return
    db.refresh(event)
    log_event(db, event, "escalation_triggered", now, reason=reason)
    _notify(db, event, "caregivers", "escalation", f"Check in with {senior.full_name}", _compose_message(senior, med, event), now)

    policy = get_policy(db, event.household_id)
    contacts = sorted((c for c in policy.contacts if c.get("consent", True)), key=lambda c: c.get("priority", 99))
    created = 0
    for c in contacts:
        for channel in c.get("channels", []):
            delivery = EscalationDelivery(
                escalation_id=esc.id,
                contact_name=c["name"],
                to=c["phone"],
                channel=channel,
                idempotency_key=f"{esc.id}:{c['phone']}:{channel}",
            )
            db.add(delivery)
            db.flush()
            esc.deliveries.append(delivery)
            _attempt(db, delivery, esc, event, senior, med, now, providers)
            created += 1
    if not created:
        log_event(db, event, "escalation_no_contacts", now)


def _attempt(db, delivery, esc, event, senior, med, now, providers) -> None:
    provider = providers.for_channel(delivery.channel)
    delivery.attempts += 1
    if provider is None:
        result_ok, err, mid = False, f"unsupported_channel: {delivery.channel}", None
    else:
        r = provider.send(
            OutboundMessage(to=delivery.to, body=_compose_message(senior, med, event), idempotency_key=delivery.idempotency_key)
        )
        result_ok, err, mid = r.ok, r.error, r.provider_message_id
    if result_ok:
        delivery.status, delivery.provider_message_id, delivery.last_error, delivery.next_attempt_at = "sent", mid, None, None
        log_event(db, event, "delivery_sent", now, channel=delivery.channel, to=delivery.to)
    else:
        delivery.status, delivery.last_error = "failed", err
        delivery.next_attempt_at = (
            now + timedelta(minutes=RETRY_BACKOFF_MIN * delivery.attempts) if delivery.attempts < MAX_DELIVERY_ATTEMPTS else None
        )
        log_event(
            db, event, "delivery_failed", now, channel=delivery.channel, to=delivery.to, error=err, attempt=delivery.attempts
        )


def retry_failed_deliveries(db: Session, now: datetime, providers: Providers) -> int:
    rows = (
        db.query(EscalationDelivery)
        .filter(
            EscalationDelivery.status == "failed",
            EscalationDelivery.attempts < MAX_DELIVERY_ATTEMPTS,
            EscalationDelivery.next_attempt_at <= now,
        )
        .with_for_update(skip_locked=True)
        .all()
    )
    for d in rows:
        esc = db.get(Escalation, d.escalation_id)
        if esc.status == "resolved":
            d.next_attempt_at = None
            continue
        event = db.get(DoseEvent, esc.dose_event_id)
        senior, med, _ = _context(db, event)
        _attempt(db, d, esc, event, senior, med, now, providers)
    return len(rows)


_HANDLERS = {"reminder": _do_reminder, "verify": _do_verify, "escalate": _do_escalate}
