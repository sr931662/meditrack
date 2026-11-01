from datetime import datetime

from sqlalchemy import JSON, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base, UTCDateTime, new_id, utcnow


class DoseEvent(Base):
    """One scheduled dose. Every fact about it is recorded in its own column so that, for example,
    'packaging matched' can never be confused with 'taken'. `display_status` is derived, never stored."""

    __tablename__ = "dose_events"
    __table_args__ = (UniqueConstraint("schedule_id", "scheduled_for"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"), index=True)
    senior_id: Mapped[str] = mapped_column(String(36), index=True)
    medication_id: Mapped[str] = mapped_column(String(36), index=True)
    schedule_id: Mapped[str] = mapped_column(String(36), index=True)
    scheduled_for: Mapped[datetime] = mapped_column(UTCDateTime, index=True)

    reminder_sent_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    acknowledged_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    verification_prompted_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    user_reported_taken_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    snoozed_until: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    help_requested_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    help_reason: Mapped[str | None] = mapped_column(String(32), nullable=True)
    caregiver_status: Mapped[str | None] = mapped_column(String(16), nullable=True)  # taken | not_taken
    caregiver_confirmed_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)

    logs = relationship("DoseEventLog", back_populates="dose_event", order_by="DoseEventLog.at", cascade="all, delete-orphan")
    verifications = relationship("VerificationResult", order_by="VerificationResult.created_at", cascade="all, delete-orphan")
    escalation = relationship("Escalation", uselist=False, back_populates="dose_event")

    @property
    def packaging_matched(self) -> bool:
        return any(v.status == "match" for v in self.verifications)

    @property
    def independently_confirmed(self) -> bool:
        return self.caregiver_status == "taken"

    @property
    def display_status(self) -> str:
        """Ordered most-final first. 'missed' is deliberately not producible without a human decision."""
        if self.resolved_at:
            return "resolved"
        if self.caregiver_status == "taken":
            return "caregiver_confirmed_taken"
        if self.caregiver_status == "not_taken":
            return "caregiver_confirmed_not_taken"
        if self.escalation is not None:
            return "escalated"
        if self.user_reported_taken_at:
            return "user_reported_taken"
        if self.acknowledged_at:
            return "acknowledged"
        if self.reminder_sent_at:
            return "reminded"
        return "scheduled"


class DoseEventLog(Base):
    """Append-only, timestamped history of everything that happened to a dose."""

    __tablename__ = "dose_event_logs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    dose_event_id: Mapped[str] = mapped_column(ForeignKey("dose_events.id"), index=True)
    type: Mapped[str] = mapped_column(String(48))
    at: Mapped[datetime] = mapped_column(UTCDateTime)
    actor_user_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    recorded_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)

    dose_event = relationship("DoseEvent", back_populates="logs")


class VerificationResult(Base):
    __tablename__ = "verification_results"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    dose_event_id: Mapped[str] = mapped_column(ForeignKey("dose_events.id"), index=True)
    household_id: Mapped[str] = mapped_column(String(36), index=True)
    submitted_by: Mapped[str | None] = mapped_column(String(36), nullable=True)
    status: Mapped[str] = mapped_column(String(16))  # match | uncertain | no_match
    confidence: Mapped[float] = mapped_column(Float)
    matched_medication_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    extracted_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    barcode: Mapped[str | None] = mapped_column(String(64), nullable=True)
    packaging: Mapped[str | None] = mapped_column(String(200), nullable=True)
    reasons: Mapped[list] = mapped_column(JSON, default=list)
    next_action: Mapped[str] = mapped_column(String(32), default="none")
    provider: Mapped[str] = mapped_column(String(64))
    model: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class Job(Base):
    """Database-backed outbox: survives restarts and deploys; claimed by workers via status + lock."""

    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    kind: Mapped[str] = mapped_column(String(24))  # reminder | verify | escalate
    dose_event_id: Mapped[str] = mapped_column(ForeignKey("dose_events.id"), index=True)
    run_at: Mapped[datetime] = mapped_column(UTCDateTime, index=True)
    status: Mapped[str] = mapped_column(String(12), default="pending", index=True)  # pending | done | cancelled
    dedupe_key: Mapped[str] = mapped_column(String(100), unique=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)


class Escalation(Base):
    __tablename__ = "escalations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    dose_event_id: Mapped[str] = mapped_column(ForeignKey("dose_events.id"), unique=True)  # one per dose, ever
    household_id: Mapped[str] = mapped_column(String(36), index=True)
    reason: Mapped[str] = mapped_column(String(64))
    priority: Mapped[str] = mapped_column(String(12), default="normal")
    status: Mapped[str] = mapped_column(String(16), default="open", index=True)  # open | acknowledged | resolved
    triggered_at: Mapped[datetime] = mapped_column(UTCDateTime)
    acknowledged_by: Mapped[str | None] = mapped_column(String(36), nullable=True)
    acknowledged_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    resolved_by: Mapped[str | None] = mapped_column(String(36), nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    outcome: Mapped[str | None] = mapped_column(String(32), nullable=True)
    resolution_note: Mapped[str | None] = mapped_column(Text, nullable=True)

    dose_event = relationship("DoseEvent", back_populates="escalation")
    deliveries = relationship("EscalationDelivery", cascade="all, delete-orphan")


class EscalationDelivery(Base):
    __tablename__ = "escalation_deliveries"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    escalation_id: Mapped[str] = mapped_column(ForeignKey("escalations.id"), index=True)
    contact_name: Mapped[str] = mapped_column(String(200))
    to: Mapped[str] = mapped_column(String(32))
    channel: Mapped[str] = mapped_column(String(16))
    # pending -> sent (provider accepted) -> delivered (provider webhook) | failed
    status: Mapped[str] = mapped_column(String(12), default="pending", index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    provider_message_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    idempotency_key: Mapped[str] = mapped_column(String(160), unique=True)
    next_attempt_at: Mapped[datetime | None] = mapped_column(UTCDateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)


class Notification(Base):
    """In-app notification history (also the source for push/FCM fan-out)."""

    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(String(36), index=True)
    senior_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    recipient_role: Mapped[str] = mapped_column(String(16))  # senior | caregivers
    kind: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)
    dose_event_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class SyncReceipt(Base):
    """Idempotency ledger for offline events (client_event_id is generated on the device)."""

    __tablename__ = "sync_receipts"
    __table_args__ = (UniqueConstraint("household_id", "client_event_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(String(36))
    client_event_id: Mapped[str] = mapped_column(String(100))
    result: Mapped[str] = mapped_column(String(16))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
