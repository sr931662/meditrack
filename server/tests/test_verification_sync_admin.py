import pytest

from app.models import DoseEvent, DoseEventLog, User
from app.services import engine
from tests.conftest import PASSWORD, utc


@pytest.fixture()
def w(api, client, db, providers):
    owner = api.register("owner@x.com", "Daniel Lee")
    hid = api.household(owner)
    senior = api.senior(owner, hid, login_email="margaret@x.com", login_password=PASSWORD)
    med = api.medication(owner, hid, senior["id"], name="Amlodipine", strength="5 mg", barcode="8901234567890")
    sched = api.schedule(owner, hid, med["id"], times=["08:00"])
    api.policy(owner, hid)
    engine.materialize(db, utc(2026, 10, 26, 7, 50))
    engine.process_due(db, utc(2026, 10, 26, 8, 0), providers)
    db.commit()
    ev = db.query(DoseEvent).filter_by(household_id=hid).one()
    return dict(owner=owner, hid=hid, senior=senior, med=med, sched=sched, eid=ev.id, s=api.login("margaret@x.com"))


def verify(client, w, **body):
    return client.post(
        f"/api/v1/households/{w['hid']}/dose-events/{w['eid']}/verifications", json=body, headers=w["s"]["headers"]
    )


def get_event(client, w):
    return client.get(f"/api/v1/households/{w['hid']}/dose-events/{w['eid']}", headers=w["owner"]["headers"]).json()


# ---- verification -------------------------------------------------------------------------------


def test_match_is_structured_and_is_not_proof_of_ingestion(client, w):
    r = verify(client, w, extracted_text="AMLODIPINE TABLETS IP 5 mg  Store below 30C")
    assert r.status_code == 201, r.text
    v = r.json()
    assert v["status"] == "match" and v["confidence"] >= 0.85
    assert v["matched_medication_id"] == w["med"]["id"]
    assert v["provider"] and v["model"] and v["created_at"] and "extracted_text" in v and "reasons" in v
    ev = get_event(client, w)
    assert ev["packaging_matched"] is True
    assert ev["user_reported_taken_at"] is None and ev["caregiver_status"] is None
    assert ev["display_status"] != "user_reported_taken"
    assert ev["independently_confirmed"] is False


def test_barcode_exact_match_is_high_confidence(client, w):
    v = verify(client, w, barcode="8901234567890").json()
    assert v["status"] == "match" and v["confidence"] >= 0.95


def test_wrong_medicine_is_no_match_and_asks_caregiver(client, w):
    v = verify(client, w, extracted_text="METFORMIN HYDROCHLORIDE 500 mg").json()
    assert v["status"] == "no_match" and v["next_action"] == "ask_caregiver"
    assert v["reasons"]
    ev = get_event(client, w)
    assert ev["packaging_matched"] is False


def test_partial_read_is_uncertain_and_requests_second_image(client, w):
    v = verify(client, w, extracted_text="AMLO").json()
    assert v["status"] == "uncertain" and v["next_action"] == "retake_or_secondary"


def test_wrong_strength_is_not_a_match(client, w):
    v = verify(client, w, extracted_text="AMLODIPINE 10 mg").json()
    assert v["status"] != "match"
    assert any("strength" in r.lower() for r in v["reasons"])


def test_empty_verification_rejected(client, w):
    assert verify(client, w).status_code == 422


def test_confidence_thresholds_are_configurable(client, w, superadmin):
    client.put("/api/v1/admin/config", json={"values": {"verification.high_threshold": 0.999}}, headers=superadmin["headers"])
    v = verify(client, w, extracted_text="AMLODIPINE TABLETS 5 mg").json()
    assert v["status"] == "uncertain"


def test_caregiver_confirmation_is_a_separate_state(client, w):
    verify(client, w, extracted_text="AMLODIPINE 5 mg")
    r = client.post(
        f"/api/v1/households/{w['hid']}/dose-events/{w['eid']}/caregiver-confirm",
        json={"status": "taken", "note": "Spoke with her by phone"},
        headers=w["owner"]["headers"],
    )
    assert r.status_code == 200
    ev = get_event(client, w)
    assert ev["display_status"] == "caregiver_confirmed_taken" and ev["independently_confirmed"] is True
    assert ev["packaging_matched"] is True


def test_senior_cannot_caregiver_confirm(client, w):
    r = client.post(
        f"/api/v1/households/{w['hid']}/dose-events/{w['eid']}/caregiver-confirm",
        json={"status": "taken", "note": "x"},
        headers=w["s"]["headers"],
    )
    assert r.status_code == 403


def test_successful_reminder_journey(client, w, providers):
    """Scenario 2."""
    base = f"/api/v1/households/{w['hid']}/dose-events/{w['eid']}"
    assert client.post(base + "/respond", json={"response": "acknowledged"}, headers=w["s"]["headers"]).status_code == 200
    assert verify(client, w, extracted_text="AMLODIPINE 5 mg").json()["status"] == "match"
    assert client.post(base + "/respond", json={"response": "taken"}, headers=w["s"]["headers"]).status_code == 200
    ev = get_event(client, w)
    assert ev["acknowledged_at"] and ev["packaging_matched"] and ev["user_reported_taken_at"]
    assert ev["display_status"] == "user_reported_taken" and ev["independently_confirmed"] is False
    dash = client.get(f"/api/v1/households/{w['hid']}/dashboard?date=2026-10-26", headers=w["owner"]["headers"]).json()
    assert dash["packaging_matched"] == 1 and dash["user_reported_taken"] == 1 and dash["caregiver_confirmed"] == 0


# ---- offline sync -------------------------------------------------------------------------------


def test_offline_events_sync_without_duplication(client, db, w, providers):
    """Scenario 4."""
    url = f"/api/v1/households/{w['hid']}/sync/events"
    batch = {
        "events": [
            {
                "client_event_id": "c-1",
                "dose_event_id": w["eid"],
                "type": "respond",
                "response": "acknowledged",
                "occurred_at": "2026-10-26T08:01:00Z",
            },
            {
                "client_event_id": "c-2",
                "dose_event_id": w["eid"],
                "type": "respond",
                "response": "taken",
                "occurred_at": "2026-10-26T08:12:00Z",
            },
        ]
    }
    r1 = client.post(url, json=batch, headers=w["s"]["headers"])
    assert r1.status_code == 200 and [x["result"] for x in r1.json()["results"]] == ["applied", "applied"]
    r2 = client.post(url, json=batch, headers=w["s"]["headers"])  # retry after a lost response
    assert [x["result"] for x in r2.json()["results"]] == ["duplicate", "duplicate"]
    db.expire_all()
    assert db.query(DoseEventLog).filter_by(dose_event_id=w["eid"], type="user_reported_taken").count() == 1
    engine.process_due(db, utc(2026, 10, 26, 8, 45), providers)
    db.commit()
    assert get_event(client, w)["escalation"] is None  # no duplicate / spurious escalation


def test_offline_event_uses_device_time_for_ordering(client, w):
    url = f"/api/v1/households/{w['hid']}/sync/events"
    client.post(
        url,
        json={
            "events": [
                {
                    "client_event_id": "c-9",
                    "dose_event_id": w["eid"],
                    "type": "respond",
                    "response": "taken",
                    "occurred_at": "2026-10-26T08:12:00Z",
                }
            ]
        },
        headers=w["s"]["headers"],
    )
    assert get_event(client, w)["user_reported_taken_at"].startswith("2026-10-26T08:12")


def test_sync_can_create_dose_event_from_local_schedule(client, db, w):
    url = f"/api/v1/households/{w['hid']}/sync/events"
    ev = {
        "client_event_id": "c-5",
        "schedule_id": w["sched"]["id"],
        "scheduled_for": "2026-10-27T08:00:00Z",
        "type": "respond",
        "response": "taken",
        "occurred_at": "2026-10-27T08:05:00Z",
    }
    assert client.post(url, json={"events": [ev]}, headers=w["s"]["headers"]).json()["results"][0]["result"] == "applied"
    assert client.post(url, json={"events": [ev]}, headers=w["s"]["headers"]).json()["results"][0]["result"] == "duplicate"
    assert db.query(DoseEvent).filter_by(household_id=w["hid"]).count() == 2


def test_sync_rejects_foreign_dose_event(client, api, w):
    other = api.register("m@x.com")
    ohid = api.household(other)
    r = client.post(
        f"/api/v1/households/{ohid}/sync/events",
        json={"events": [{"client_event_id": "x", "dose_event_id": w["eid"], "type": "respond", "response": "taken"}]},
        headers=other["headers"],
    )
    assert r.status_code == 200 and r.json()["results"][0]["result"] == "rejected"


def test_sync_reports_per_event_errors_without_failing_batch(client, w):
    url = f"/api/v1/households/{w['hid']}/sync/events"
    batch = {
        "events": [
            {"client_event_id": "e-1", "dose_event_id": "nope", "type": "respond", "response": "taken"},
            {
                "client_event_id": "e-2",
                "dose_event_id": w["eid"],
                "type": "respond",
                "response": "taken",
                "occurred_at": "2026-10-26T08:12:00Z",
            },
        ]
    }
    res = client.post(url, json=batch, headers=w["s"]["headers"]).json()["results"]
    assert res[0]["result"] == "rejected" and res[1]["result"] == "applied"


# ---- admin / scenario 5 -------------------------------------------------------------------------


def test_admin_lifecycle_and_audit(client, db, superadmin):
    h = superadmin["headers"]
    r = client.post(
        "/api/v1/admin/users",
        json={"email": "ops@x.com", "full_name": "Ops", "password": PASSWORD, "platform_role": "ops_admin"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    uid = r.json()["id"]
    ops = client.post("/api/v1/auth/login", json={"email": "ops@x.com", "password": PASSWORD}).json()
    oh = {"Authorization": f"Bearer {ops['access_token']}"}
    # ops admin: can read users, cannot manage roles/permissions
    assert client.get("/api/v1/admin/users", headers=oh).status_code == 200
    assert (
        client.put("/api/v1/admin/roles/ops_admin/permissions", json={"permissions": ["users.read"]}, headers=oh).status_code
        == 403
    )
    assert client.put("/api/v1/admin/config", json={"values": {"x": 1}}, headers=oh).status_code == 403
    # super admin revokes a permission -> takes effect immediately for the live token
    client.put("/api/v1/admin/roles/ops_admin/permissions", json={"permissions": ["users.read"]}, headers=h)
    assert client.get("/api/v1/admin/users", headers=oh).status_code == 200
    client.put("/api/v1/admin/roles/ops_admin/permissions", json={"permissions": []}, headers=h)
    assert client.get("/api/v1/admin/users", headers=oh).status_code == 403
    # disabling kills the session and blocks login
    assert client.post(f"/api/v1/admin/users/{uid}/disable", json={"reason": "left company"}, headers=h).status_code == 200
    assert client.get("/api/v1/auth/me", headers=oh).status_code == 401
    assert client.post("/api/v1/auth/refresh", json={"refresh_token": ops["refresh_token"]}).status_code == 401
    assert client.post("/api/v1/auth/login", json={"email": "ops@x.com", "password": PASSWORD}).status_code == 403
    assert client.post(f"/api/v1/admin/users/{uid}/enable", headers=h).status_code == 200
    assert client.post("/api/v1/auth/login", json={"email": "ops@x.com", "password": PASSWORD}).status_code == 200
    actions = [x["action"] for x in client.get("/api/v1/admin/audit-logs?limit=100", headers=h).json()["items"]]
    for a in ("user.created", "role.permissions_changed", "user.disabled", "user.enabled"):
        assert a in actions, actions


def test_disable_requires_reason_and_cannot_disable_self(client, superadmin):
    h = superadmin["headers"]
    me = client.get("/api/v1/auth/me", headers=h).json()
    assert client.post(f"/api/v1/admin/users/{me['id']}/disable", json={"reason": "x"}, headers=h).status_code == 400
    assert client.post(f"/api/v1/admin/users/{me['id']}/disable", json={}, headers=h).status_code == 422


def test_admin_operation_cannot_bypass_audit(client, db, superadmin, monkeypatch):
    from app.services import audit

    def boom(*a, **k):
        raise RuntimeError("audit store down")

    monkeypatch.setattr(audit, "record", boom)
    with pytest.raises(RuntimeError):
        client.post(
            "/api/v1/admin/users",
            json={"email": "ghost@x.com", "full_name": "G", "password": PASSWORD, "platform_role": "ops_admin"},
            headers=superadmin["headers"],
        )
    db.expire_all()
    assert db.query(User).filter_by(email="ghost@x.com").count() == 0


def test_super_admin_role_cannot_be_assigned_by_non_super(client, db, superadmin):
    h = superadmin["headers"]
    client.post(
        "/api/v1/admin/users",
        json={"email": "ops@x.com", "full_name": "Ops", "password": PASSWORD, "platform_role": "ops_admin"},
        headers=h,
    )
    # grant ops_admin users.create + roles.manage and still can't mint a super admin
    client.put(
        "/api/v1/admin/roles/ops_admin/permissions",
        json={"permissions": ["users.read", "users.create", "users.update"]},
        headers=h,
    )
    ops = client.post("/api/v1/auth/login", json={"email": "ops@x.com", "password": PASSWORD}).json()
    oh = {"Authorization": f"Bearer {ops['access_token']}"}
    r = client.post(
        "/api/v1/admin/users",
        json={"email": "evil@x.com", "full_name": "E", "password": PASSWORD, "platform_role": "super_admin"},
        headers=oh,
    )
    assert r.status_code == 403


def test_org_admin_is_feature_gated(client, superadmin):
    r = client.post(
        "/api/v1/admin/users",
        json={"email": "org@x.com", "full_name": "O", "password": PASSWORD, "platform_role": "org_admin"},
        headers=superadmin["headers"],
    )
    assert r.status_code == 403  # B2B not activated


def test_health_and_readiness(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/ready").json()["database"] == "ok"
