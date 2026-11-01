"""Shared fixtures. Tests run on in-memory SQLite; PostgreSQL is the production target."""

import os
from datetime import UTC, datetime

os.environ["MEDTRACK_ENV"] = "test"
os.environ["MEDTRACK_JWT_SECRET"] = "test-secret-test-secret-test-secret-123456"
os.environ["MEDTRACK_PROVIDER_MODE"] = "mock"

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.db import Base, get_db
from app.integrations.registry import get_providers, reset_providers
from app.main import create_app
from app.services import bootstrap

PASSWORD = "Str0ng-Passw0rd!"


@pytest.fixture()
def engine():
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    import app.models  # noqa: F401  (register tables)

    Base.metadata.create_all(eng)
    yield eng
    eng.dispose()


@pytest.fixture()
def session_factory(engine):
    return sessionmaker(bind=engine, expire_on_commit=False, autoflush=False)


@pytest.fixture()
def db(session_factory):
    s = session_factory()
    bootstrap.seed_reference_data(s)
    s.commit()
    yield s
    s.close()


@pytest.fixture()
def client(session_factory, db):
    app = create_app()

    def _get_db():
        s = session_factory()
        try:
            yield s
            s.commit()  # mirrors app.core.db.get_db: one transaction per request
        except Exception:
            s.rollback()
            raise
        finally:
            s.close()

    app.dependency_overrides[get_db] = _get_db
    reset_providers()
    with TestClient(app) as c:
        yield c


@pytest.fixture()
def providers():
    return get_providers()


class Api:
    """Thin helper for readable tests."""

    def __init__(self, client: TestClient):
        self.c = client

    def register(self, email, name="Test User", password=PASSWORD):
        r = self.c.post("/api/v1/auth/register", json={"email": email, "password": password, "full_name": name})
        assert r.status_code == 201, r.text
        return self.login(email, password)

    def login(self, email, password=PASSWORD):
        r = self.c.post("/api/v1/auth/login", json={"email": email, "password": password})
        assert r.status_code == 200, r.text
        d = r.json()
        return {"headers": {"Authorization": f"Bearer {d['access_token']}"}, **d}

    def household(self, owner, name="Lee family"):
        r = self.c.post("/api/v1/households", json={"name": name}, headers=owner["headers"])
        assert r.status_code == 201, r.text
        return r.json()["id"]

    def senior(self, owner, hid, name="Margaret Lee", **extra):
        body = {"full_name": name, "language": "en", "timezone": "UTC", **extra}
        r = self.c.post(f"/api/v1/households/{hid}/seniors", json=body, headers=owner["headers"])
        assert r.status_code == 201, r.text
        return r.json()

    def medication(self, owner, hid, sid, name="Amlodipine", strength="5 mg", **extra):
        body = {"senior_id": sid, "name": name, "strength": strength, "dosage_form": "tablet", **extra}
        r = self.c.post(f"/api/v1/households/{hid}/medications", json=body, headers=owner["headers"])
        assert r.status_code == 201, r.text
        return r.json()

    def schedule(self, owner, hid, med_id, times=("08:00",), **extra):
        body = {
            "medication_id": med_id,
            "times": list(times),
            "weekdays": [0, 1, 2, 3, 4, 5, 6],
            "start_date": "2026-10-01",
            "timezone": "UTC",
            **extra,
        }
        r = self.c.post(f"/api/v1/households/{hid}/schedules", json=body, headers=owner["headers"])
        assert r.status_code == 201, r.text
        return r.json()

    def policy(self, owner, hid, contacts=None, t_verify=5, t_escalate=45):
        contacts = (
            contacts
            if contacts is not None
            else [{"name": "Daniel Lee", "phone": "+15550100142", "channels": ["whatsapp", "ivr"], "priority": 1}]
        )
        r = self.c.put(
            f"/api/v1/households/{hid}/escalation-policy",
            json={"t_verify_min": t_verify, "t_escalate_min": t_escalate, "contacts": contacts},
            headers=owner["headers"],
        )
        assert r.status_code == 200, r.text
        return r.json()


@pytest.fixture()
def api(client):
    return Api(client)


@pytest.fixture()
def superadmin(client, db, api):
    bootstrap.create_super_admin(db, "root@medtrack.test", PASSWORD, "Root Admin")
    db.commit()
    return api.login("root@medtrack.test")


def utc(y, mo, d, h=0, mi=0):
    return datetime(y, mo, d, h, mi, tzinfo=UTC)
