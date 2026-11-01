"""Sample data for presentations (MEDTRACK_DEMO_MODE=true). Idempotent; re-running re-anchors the
dose times to "now" so there is always a dose coming up. Never used outside demo mode."""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.core.db import utcnow
from app.core.permissions import SUPER_ADMIN
from app.models import Household, Medication, Membership, Schedule, Senior, User
from app.services import auth as auth_service
from app.services import engine

TZ = "Asia/Kolkata"
CAREGIVER_EMAIL = "caregiver@demo.meditrack.app"
SENIOR_EMAIL = "senior@demo.meditrack.app"
ADMIN_EMAIL = "admin@demo.meditrack.app"
HOUSEHOLD_NAME = "Sharma Family (demo)"
CONTACT_PHONE = "+919000000001"  # fictional; demo providers never send anything

# name, strength, form, purpose, appearance, offset minutes from now (first dose), second-dose offset or None
_MEDS = [
    ("Metformin", "500 mg", "tablet", "Blood sugar", "white", 3, 600),
    ("Amlodipine", "5 mg", "tablet", "Blood pressure", "pink", 70, None),
    ("Atorvastatin", "10 mg", "tablet", "Cholesterol", "blue", 200, None),
]


def _user(db: Session, email: str, name: str, password: str, platform_role: str | None = None) -> User:
    u = db.query(User).filter_by(email=email).first()
    return u or auth_service.create_user(db, email=email, password=password, full_name=name, platform_role=platform_role)


def _hhmm(base: datetime, minutes: int) -> str:
    return (base + timedelta(minutes=minutes)).astimezone(ZoneInfo(TZ)).strftime("%H:%M")


def seed_demo(db: Session, password: str, now: datetime | None = None) -> None:
    now = now or utcnow()
    caregiver = _user(db, CAREGIVER_EMAIL, "Priya Sharma", password)
    senior_user = _user(db, SENIOR_EMAIL, "Kamla Sharma", password)
    _user(db, ADMIN_EMAIL, "Demo Administrator", password, platform_role=SUPER_ADMIN)

    household = db.query(Household).filter_by(name=HOUSEHOLD_NAME).first()
    if household is None:
        household = Household(name=HOUSEHOLD_NAME)
        db.add(household)
        db.flush()
        db.add(Membership(household_id=household.id, user_id=caregiver.id, role="owner"))
    senior = db.query(Senior).filter_by(household_id=household.id).first()
    if senior is None:
        senior = Senior(
            household_id=household.id, user_id=senior_user.id, full_name="Kamla Sharma", birth_year=1950,
            phone="+919000000002", language="en", timezone=TZ,
        )  # fmt: skip
        db.add(senior)
        db.flush()
        db.add(Membership(household_id=household.id, user_id=senior_user.id, role="senior", senior_id=senior.id))

    # Short timings so the whole REMIND -> VERIFY -> ESCALATE loop can be shown live in a few minutes.
    policy = engine.get_policy(db, household.id)
    policy.t_verify_min, policy.t_escalate_min = 2, 6
    policy.contacts = [
        {
            "name": "Priya Sharma (daughter)",
            "phone": CONTACT_PHONE,
            "channels": ["whatsapp", "ivr"],
            "priority": 1,
            "consent": True,
        }
    ]

    today = now.astimezone(ZoneInfo(TZ)).date()
    for name, strength, form, purpose, look, first, second in _MEDS:
        med = db.query(Medication).filter_by(household_id=household.id, name=name).first()
        if med is None:
            med = Medication(
                household_id=household.id, senior_id=senior.id, name=name, strength=strength, dosage_form=form,
                purpose=purpose, appearance=look, reference_packaging=f"{name} {strength}", start_date=today,
            )  # fmt: skip
            db.add(med)
            db.flush()
        times = [_hhmm(now, first)] + ([_hhmm(now, second)] if second else [])
        sch = db.query(Schedule).filter_by(medication_id=med.id).first()
        if sch is None:
            sch = Schedule(
                household_id=household.id, medication_id=med.id, senior_id=senior.id, times=times,
                weekdays=list(range(7)), start_date=today, timezone=TZ, require_verification=(name == "Metformin"),
            )  # fmt: skip
            db.add(sch)
        else:
            sch.times = times
            sch.start_date = min(sch.start_date, today)
    db.flush()
