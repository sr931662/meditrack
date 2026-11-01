import re
from datetime import date, datetime
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# pydantic's EmailStr needs email-validator; keep dependencies small with a pragmatic pattern.
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")
HHMM_RE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def _email(v: str) -> str:
    v = v.strip().lower()
    if not EMAIL_RE.match(v):
        raise ValueError("Invalid email address")
    return v


def _tz(v: str) -> str:
    try:
        ZoneInfo(v)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise ValueError(f"Unknown timezone '{v}'") from exc
    return v


def _check_times(cls, v):
    for t in v:
        if not HHMM_RE.match(t):
            raise ValueError(f"'{t}' is not a valid HH:MM time")
    return sorted(set(v))


def _check_weekdays(cls, v):
    if any(d < 0 or d > 6 for d in v):
        raise ValueError("weekdays must be 0 (Mon) to 6 (Sun)")
    return sorted(set(v))


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---- auth ---------------------------------------------------------------------------------------
class RegisterIn(BaseModel):
    email: str
    password: str
    full_name: str = Field(min_length=1, max_length=200)
    _e = field_validator("email")(_email)


class LoginIn(BaseModel):
    email: str
    password: str


class RefreshIn(BaseModel):
    refresh_token: str


# ---- households ---------------------------------------------------------------------------------
class HouseholdIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)


class MemberIn(BaseModel):
    email: str
    role: Literal["caregiver", "owner"] = "caregiver"
    permissions: list[str] = []
    _e = field_validator("email")(_email)


class MemberPatch(BaseModel):
    permissions: list[str]


def _phone(v):
    if v is not None and not PHONE_RE.match(v):
        raise ValueError("Phone must be in E.164 format, e.g. +15550100142")
    return v


class SeniorIn(BaseModel):
    full_name: str = Field(min_length=1, max_length=200)
    phone: str | None = None
    birth_year: int | None = Field(None, ge=1900, le=2100)
    language: str = Field("en", max_length=16)
    timezone: str = "UTC"
    login_email: str | None = None
    login_password: str | None = None
    _tz = field_validator("timezone")(_tz)
    _ph = field_validator("phone")(lambda cls, v: _phone(v))

    @model_validator(mode="after")
    def _login_pair(self):
        if bool(self.login_email) != bool(self.login_password):
            raise ValueError("login_email and login_password must be provided together")
        if self.login_email:
            self.login_email = _email(self.login_email)
        return self


class SeniorPatch(BaseModel):
    full_name: str | None = Field(None, min_length=1, max_length=200)
    phone: str | None = None
    _ph = field_validator("phone")(lambda cls, v: _phone(v))
    language: str | None = None
    timezone: str | None = None
    birth_year: int | None = None

    @field_validator("timezone")
    @classmethod
    def _t(cls, v):
        return _tz(v) if v else v


# ---- medications / schedules --------------------------------------------------------------------
class MedicationBase(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    strength: str = Field(min_length=1, max_length=64)
    dosage_form: str = Field(min_length=1, max_length=32)
    quantity: str | None = None
    purpose: str | None = None
    prescribed_instructions: str | None = None
    prescriber: str | None = None
    barcode: str | None = Field(None, max_length=64)
    reference_packaging: str | None = None
    appearance: str | None = Field(None, max_length=32)
    start_date: date | None = None
    end_date: date | None = None


class MedicationIn(MedicationBase):
    senior_id: str

    @model_validator(mode="after")
    def _dates(self):
        if self.start_date and self.end_date and self.end_date < self.start_date:
            raise ValueError("end_date cannot be before start_date")
        return self


class MedicationPatch(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=200)
    strength: str | None = Field(None, min_length=1, max_length=64)
    dosage_form: str | None = None
    quantity: str | None = None
    purpose: str | None = None
    prescribed_instructions: str | None = None
    prescriber: str | None = None
    barcode: str | None = None
    reference_packaging: str | None = None
    appearance: str | None = None
    start_date: date | None = None
    end_date: date | None = None
    is_active: bool | None = None


class MedicationOut(ORM, MedicationBase):
    id: str
    senior_id: str
    household_id: str
    is_active: bool
    created_at: datetime
    updated_at: datetime


class ScheduleBase(BaseModel):
    times: list[str] = Field(min_length=1, max_length=12)
    weekdays: list[int] = Field(default=[0, 1, 2, 3, 4, 5, 6], min_length=1)
    start_date: date
    end_date: date | None = None
    timezone: str = "UTC"
    require_verification: bool = False
    reminder_message: str | None = Field(None, max_length=300)

    _times = field_validator("times")(_check_times)
    _wd = field_validator("weekdays")(_check_weekdays)
    _tz = field_validator("timezone")(_tz)


class ScheduleIn(ScheduleBase):
    medication_id: str


class SchedulePatch(BaseModel):
    times: list[str] | None = None
    weekdays: list[int] | None = None
    end_date: date | None = None
    timezone: str | None = None
    require_verification: bool | None = None
    reminder_message: str | None = None
    is_active: bool | None = None

    _t = field_validator("times")(lambda cls, v: _check_times(cls, v) if v is not None else v)
    _w = field_validator("weekdays")(lambda cls, v: _check_weekdays(cls, v) if v is not None else v)

    @field_validator("timezone")
    @classmethod
    def _z(cls, v):
        return _tz(v) if v else v


class ScheduleOut(ORM, ScheduleBase):
    id: str
    household_id: str
    medication_id: str
    senior_id: str
    is_active: bool


# ---- escalation ---------------------------------------------------------------------------------
class ContactIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    phone: str
    channels: list[Literal["whatsapp", "ivr"]] = Field(min_length=1)
    priority: int = Field(1, ge=1, le=10)
    consent: bool = True  # caregiver has agreed to be contacted on these channels

    @field_validator("phone")
    @classmethod
    def _p(cls, v):
        if not PHONE_RE.match(v):
            raise ValueError("Phone must be in E.164 format, e.g. +15550100142")
        return v


class PolicyIn(BaseModel):
    t_verify_min: int = Field(5, ge=1, le=240)
    t_escalate_min: int = Field(45, ge=1, le=720)
    contacts: list[ContactIn] = []

    @model_validator(mode="after")
    def _order(self):
        if self.t_escalate_min <= self.t_verify_min:
            raise ValueError("t_escalate_min must be greater than t_verify_min")
        return self


class RespondIn(BaseModel):
    response: Literal["acknowledged", "taken", "help", "cannot_find", "unwell", "remind_later"]
    occurred_at: datetime | None = None


class VerificationIn(BaseModel):
    extracted_text: str | None = Field(None, max_length=5000)
    barcode: str | None = Field(None, max_length=64)
    image_ref: str | None = Field(None, max_length=300)

    @model_validator(mode="after")
    def _any(self):
        if not (self.extracted_text or self.barcode or self.image_ref):
            raise ValueError("Provide extracted_text, barcode or image_ref")
        return self


class CaregiverConfirmIn(BaseModel):
    status: Literal["taken", "not_taken"]
    note: str = Field(min_length=1, max_length=1000)


class ResolveIn(BaseModel):
    outcome: Literal["taken_confirmed", "not_taken_confirmed", "no_action_needed", "unreachable_follow_up"]
    note: str = Field(min_length=1, max_length=1000)


class NoteIn(BaseModel):
    note: str = Field(min_length=1, max_length=1000)


class SyncEventIn(BaseModel):
    client_event_id: str = Field(min_length=1, max_length=100)
    type: Literal["respond"] = "respond"
    response: Literal["acknowledged", "taken", "help", "cannot_find", "unwell", "remind_later"]
    dose_event_id: str | None = None
    schedule_id: str | None = None
    scheduled_for: datetime | None = None
    occurred_at: datetime | None = None


class SyncIn(BaseModel):
    events: list[SyncEventIn] = Field(max_length=500)


# ---- admin --------------------------------------------------------------------------------------
class AdminUserIn(BaseModel):
    email: str
    full_name: str = Field(min_length=1, max_length=200)
    password: str
    platform_role: Literal["super_admin", "ops_admin", "org_admin"] | None = None
    _e = field_validator("email")(_email)


class AdminUserPatch(BaseModel):
    full_name: str | None = Field(None, min_length=1)
    platform_role: Literal["super_admin", "ops_admin", "org_admin", "none"] | None = None


class ReasonIn(BaseModel):
    reason: str = Field(min_length=1, max_length=500)

    @field_validator("reason")
    @classmethod
    def _r(cls, v):
        if not v.strip():
            raise ValueError("A reason is required")
        return v.strip()


class RolePermsIn(BaseModel):
    permissions: list[str]


class ConfigIn(BaseModel):
    values: dict


class SupportAccessIn(ReasonIn):
    household_id: str
    minutes: int = Field(30, ge=5, le=240)
