from datetime import date, datetime

from sqlalchemy import JSON, Boolean, Date, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base, UTCDateTime, new_id, utcnow


class Household(Base):
    """Tenant boundary: every care record carries household_id and is only reachable through membership."""

    __tablename__ = "households"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(200))
    organization_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)  # B2B-ready
    plan: Mapped[str] = mapped_column(String(32), default="free")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class Membership(Base):
    __tablename__ = "memberships"
    __table_args__ = (UniqueConstraint("household_id", "user_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    role: Mapped[str] = mapped_column(String(16))  # owner | caregiver | senior
    permissions: Mapped[list] = mapped_column(JSON, default=list)  # explicit grants (caregivers)
    senior_id: Mapped[str | None] = mapped_column(String(36), nullable=True)  # set for role=senior
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)

    user = relationship("User", lazy="joined")


class Senior(Base):
    __tablename__ = "seniors"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"), index=True)
    user_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    full_name: Mapped[str] = mapped_column(String(200))
    birth_year: Mapped[int | None] = mapped_column(Integer, nullable=True)
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    language: Mapped[str] = mapped_column(String(16), default="en")
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class Medication(Base):
    __tablename__ = "medications"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"), index=True)
    senior_id: Mapped[str] = mapped_column(ForeignKey("seniors.id"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    strength: Mapped[str] = mapped_column(String(64))
    dosage_form: Mapped[str] = mapped_column(String(32))
    quantity: Mapped[str | None] = mapped_column(String(64), nullable=True)
    purpose: Mapped[str | None] = mapped_column(String(200), nullable=True)
    prescribed_instructions: Mapped[str | None] = mapped_column(Text, nullable=True)  # as recorded by a caregiver
    prescriber: Mapped[str | None] = mapped_column(String(200), nullable=True)
    barcode: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    reference_packaging: Mapped[str | None] = mapped_column(Text, nullable=True)  # label text / image reference
    appearance: Mapped[str | None] = mapped_column(String(32), nullable=True)  # UI pill colour token
    start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)


class Schedule(Base):
    __tablename__ = "schedules"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"), index=True)
    medication_id: Mapped[str] = mapped_column(ForeignKey("medications.id"), index=True)
    senior_id: Mapped[str] = mapped_column(String(36), index=True)
    times: Mapped[list] = mapped_column(JSON)  # ["08:00", "20:00"] local wall-clock
    weekdays: Mapped[list] = mapped_column(JSON)  # 0=Mon .. 6=Sun
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    require_verification: Mapped[bool] = mapped_column(Boolean, default=False)
    reminder_message: Mapped[str | None] = mapped_column(String(300), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class EscalationPolicy(Base):
    __tablename__ = "escalation_policies"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.id"), unique=True)
    t_verify_min: Mapped[int] = mapped_column(Integer, default=5)
    t_escalate_min: Mapped[int] = mapped_column(Integer, default=45)
    # [{name, phone, channels:[whatsapp|ivr], priority, consent}]
    contacts: Mapped[list] = mapped_column(JSON, default=list)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)
