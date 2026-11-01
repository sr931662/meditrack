import pytest

from app.models import DoseEvent, Notification
from app.services import engine
from tests.conftest import PASSWORD, utc


@pytest.fixture()
def w(api, client, db, providers):
    owner = api.register("owner@x.com", "Daniel Lee")
    hid = api.household(owner)
    senior = api.senior(owner, hid, login_email="margaret@x.com", login_password=PASSWORD)
    med = api.medication(owner, hid, senior["id"])
    api.schedule(owner, hid, med["id"], times=["08:00"])
    api.policy(owner, hid)
    for day in (25, 26):
        engine.materialize(db, utc(2026, 10, day, 7, 50))
        engine.process_due(db, utc(2026, 10, day, 8, 0), providers)
    db.commit()
    return dict(owner=owner, hid=hid, senior=senior, med=med, s=api.login("margaret@x.com"))


def events(db, w):
    db.expire_all()
    return db.query(DoseEvent).filter_by(household_id=w["hid"]).order_by(DoseEvent.scheduled_for).all()


def test_trend_keeps_evidence_levels_separate(client, db, w):
    e25, e26 = events(db, w)
    client.post(
        f"/api/v1/households/{w['hid']}/dose-events/{e25.id}/respond",
        json={"response": "taken", "occurred_at": "2026-10-25T08:05:00Z"},
        headers=w["s"]["headers"],
    )
    client.post(
        f"/api/v1/households/{w['hid']}/dose-events/{e26.id}/caregiver-confirm",
        json={"status": "not_taken", "note": "Called, she skipped it"},
        headers=w["owner"]["headers"],
    )
    r = client.get(f"/api/v1/households/{w['hid']}/dashboard/trend?days=3&date=2026-10-26", headers=w["owner"]["headers"])
    assert r.status_code == 200
    days = r.json()["days"]
    assert [d["date"] for d in days] == ["2026-10-24", "2026-10-25", "2026-10-26"]
    assert days[0]["scheduled"] == 0
    assert days[1]["user_reported_taken"] == 1 and days[1]["caregiver_confirmed"] == 0
    assert days[2]["caregiver_not_taken"] == 1 and days[2]["user_reported_taken"] == 0
    assert "missed" not in " ".join(days[2].keys())


def test_trend_requires_adherence_permission(client, w):
    r = client.get(f"/api/v1/households/{w['hid']}/dashboard/trend", headers=w["s"]["headers"])
    assert r.status_code == 403


def test_caregiver_can_request_another_verification(client, db, w):
    e25, _ = events(db, w)
    url = f"/api/v1/households/{w['hid']}/dose-events/{e25.id}/request-verification"
    assert client.post(url, headers=w["s"]["headers"]).status_code == 403  # senior cannot request on their own behalf
    assert client.post(url, headers=w["owner"]["headers"]).status_code == 200
    db.expire_all()
    n = db.query(Notification).filter_by(dose_event_id=e25.id, kind="verification_prompt", recipient_role="senior").all()
    assert len(n) >= 1
    types = [x.type for x in events(db, w)[0].logs]
    assert "verification_requested" in types


def test_filters_by_senior_and_medication(client, api, db, w):
    other = api.senior(w["owner"], w["hid"], "Grandpa")
    med2 = api.medication(w["owner"], w["hid"], other["id"], name="Metformin", strength="500 mg")
    api.schedule(w["owner"], w["hid"], med2["id"], times=["08:00"])
    engine.materialize(db, utc(2026, 10, 26, 7, 50))
    db.commit()
    base = f"/api/v1/households/{w['hid']}/dashboard?date=2026-10-26"
    assert client.get(base, headers=w["owner"]["headers"]).json()["scheduled"] == 2
    assert client.get(base + f"&senior_id={other['id']}", headers=w["owner"]["headers"]).json()["scheduled"] == 1
    assert client.get(base + f"&medication_id={w['med']['id']}", headers=w["owner"]["headers"]).json()["scheduled"] == 1


def test_senior_phone_is_optional_validated_and_returned(client, api, w):
    hid, h = w["hid"], w["owner"]["headers"]
    ok = client.post(
        f"/api/v1/households/{hid}/seniors",
        json={"full_name": "Grandpa", "language": "en", "timezone": "UTC", "phone": "+15550100999"},
        headers=h,
    )
    assert ok.status_code == 201 and ok.json()["phone"] == "+15550100999"
    bad = client.post(
        f"/api/v1/households/{hid}/seniors",
        json={"full_name": "X", "language": "en", "timezone": "UTC", "phone": "12345"},
        headers=h,
    )
    assert bad.status_code == 422
    upd = client.patch(f"/api/v1/households/{hid}/seniors/{w['senior']['id']}", json={"phone": "+15550100111"}, headers=h)
    assert upd.json()["phone"] == "+15550100111"


def test_escalation_list_names_the_senior_and_medicine(client, db, providers, w):
    engine.process_due(db, utc(2026, 10, 26, 8, 45), providers)
    db.commit()
    items = client.get(f"/api/v1/households/{w['hid']}/escalations", headers=w["owner"]["headers"]).json()["items"]
    assert items[0]["senior_name"] == "Margaret Lee"
    assert items[0]["medication"] == "Amlodipine 5 mg"
    assert items[0]["scheduled_for"].startswith("2026-10-26T08:00")
