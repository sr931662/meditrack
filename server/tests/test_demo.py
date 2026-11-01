"""Demo mode: clearly-labelled simulated providers, sample data, and Cloud Run friendliness."""

from datetime import UTC, datetime

import pytest

from app.api.v1.doses import _delivery
from app.core.config import Settings
from app.integrations.base import OutboundMessage
from app.integrations.demo import DemoProvider
from app.models import EscalationDelivery, Household, Medication, Schedule, User
from app.services import demo

STRONG = "x" * 40


def test_demo_provider_marks_messages_simulated():
    r = DemoProvider("whatsapp").send(OutboundMessage(to="+911", body="hi", idempotency_key="k1"))
    assert r.ok and r.provider_message_id.startswith("demo-")


def test_delivery_payload_flags_simulated_deliveries():
    d = EscalationDelivery(contact_name="A", channel="ivr", status="sent", attempts=1, provider_message_id="demo-k1")
    assert _delivery(d)["simulated"] is True
    d.provider_message_id = "SM123"
    assert _delivery(d)["simulated"] is False


def test_demo_provider_mode_needs_explicit_demo_flag_in_production():
    base = dict(env="production", jwt_secret=STRONG, database_url="postgresql+psycopg://u:p@h/db")
    with pytest.raises(ValueError):
        Settings(provider_mode="demo", **base)
    assert Settings(provider_mode="demo", demo_mode=True, **base).provider_mode == "demo"


def test_mock_provider_is_still_rejected_in_production_even_with_demo_flag():
    with pytest.raises(ValueError):
        Settings(
            env="production",
            jwt_secret=STRONG,
            database_url="postgresql+psycopg://u:p@h/db",
            provider_mode="mock",
            demo_mode=True,
        )


def test_seed_demo_is_idempotent_and_creates_usable_accounts(db, client):
    now = datetime(2026, 11, 1, 6, 0, tzinfo=UTC)
    demo.seed_demo(db, "Demo@12345", now=now)
    db.commit()
    demo.seed_demo(db, "Demo@12345", now=now)  # second run must not duplicate anything
    db.commit()
    assert db.query(User).filter_by(email=demo.CAREGIVER_EMAIL).count() == 1
    assert db.query(Household).count() == 1
    assert db.query(Medication).count() >= 3
    assert db.query(Schedule).count() >= 3

    for email in (demo.CAREGIVER_EMAIL, demo.SENIOR_EMAIL, demo.ADMIN_EMAIL):
        r = client.post("/api/v1/auth/login", json={"email": email, "password": "Demo@12345"})
        assert r.status_code == 200, (email, r.text)


def test_seed_demo_reanchors_schedule_to_now_so_a_dose_is_always_upcoming(db):
    demo.seed_demo(db, "Demo@12345", now=datetime(2026, 11, 1, 6, 0, tzinfo=UTC))
    db.commit()
    first = {tuple(s.times) for s in db.query(Schedule)}
    demo.seed_demo(db, "Demo@12345", now=datetime(2026, 11, 1, 15, 0, tzinfo=UTC))
    db.commit()
    assert {tuple(s.times) for s in db.query(Schedule)} != first
