import pytest


@pytest.fixture()
def w(api):
    owner = api.register("owner@x.com", "Daniel Lee")
    hid = api.household(owner)
    senior = api.senior(owner, hid)
    return dict(owner=owner, hid=hid, senior=senior)


def test_medication_crud_and_audit(client, api, w, superadmin, db):
    h = w["owner"]["headers"]
    med = api.medication(
        w["owner"], w["hid"], w["senior"]["id"], prescribed_instructions="After breakfast", barcode="8901234567890"
    )
    base = f"/api/v1/households/{w['hid']}/medications"
    assert client.get(f"{base}/{med['id']}", headers=h).json()["barcode"] == "8901234567890"
    r = client.patch(f"{base}/{med['id']}", json={"strength": "10 mg"}, headers=h)
    assert r.status_code == 200 and r.json()["strength"] == "10 mg"
    assert client.delete(f"{base}/{med['id']}", headers=h).status_code == 204
    # soft-deleted: hidden from default list, history retained
    assert client.get(base, headers=h).json()["items"] == []
    assert len(client.get(base + "?include_inactive=true", headers=h).json()["items"]) == 1
    actions = [
        a.action
        for a in db.query(__import__("app.models", fromlist=["AuditLog"]).AuditLog)
        .filter_by(household_id=w["hid"])
        .order_by("at")
    ]
    assert {"medication.created", "medication.updated", "medication.deleted"} <= set(actions)


def test_medication_validation(client, w):
    h = w["owner"]["headers"]
    base = f"/api/v1/households/{w['hid']}/medications"
    bad = {"senior_id": w["senior"]["id"], "name": "", "strength": "5 mg", "dosage_form": "tablet"}
    assert client.post(base, json=bad, headers=h).status_code == 422
    bad = {
        "senior_id": w["senior"]["id"],
        "name": "X",
        "strength": "5 mg",
        "dosage_form": "tablet",
        "start_date": "2026-10-10",
        "end_date": "2026-10-01",
    }
    assert client.post(base, json=bad, headers=h).status_code == 422


def test_medication_pagination_and_filter(client, api, w):
    other = api.senior(w["owner"], w["hid"], "Grandpa")
    for i in range(5):
        api.medication(w["owner"], w["hid"], w["senior"]["id"], name=f"Med{i}")
    api.medication(w["owner"], w["hid"], other["id"], name="GrandpaMed")
    h = w["owner"]["headers"]
    base = f"/api/v1/households/{w['hid']}/medications"
    page = client.get(base + f"?senior_id={w['senior']['id']}&limit=2&offset=0&sort=name", headers=h).json()
    assert page["total"] == 5 and len(page["items"]) == 2 and page["items"][0]["name"] == "Med0"


def test_schedule_validation_and_crud(client, api, w):
    med = api.medication(w["owner"], w["hid"], w["senior"]["id"])
    h = w["owner"]["headers"]
    base = f"/api/v1/households/{w['hid']}/schedules"
    bad = {"medication_id": med["id"], "times": ["25:99"], "weekdays": [0], "start_date": "2026-10-01", "timezone": "UTC"}
    assert client.post(base, json=bad, headers=h).status_code == 422
    bad = {**bad, "times": ["08:00"], "timezone": "Mars/Base"}
    assert client.post(base, json=bad, headers=h).status_code == 422
    s = api.schedule(w["owner"], w["hid"], med["id"], times=["20:00", "08:00"])
    assert s["times"] == ["08:00", "20:00"]  # normalised + sorted
    assert client.patch(f"{base}/{s['id']}", json={"times": ["09:00"]}, headers=h).json()["times"] == ["09:00"]
    assert client.delete(f"{base}/{s['id']}", headers=h).status_code == 204


def test_household_onboarding_scenario(client, api):
    """Scenario 1: registration -> household -> senior -> invite caregiver -> meds -> schedules."""
    owner = api.register("owner@x.com", "Daniel Lee")
    hid = api.household(owner)
    senior = api.senior(owner, hid, birth_year=1952)
    api.register("sis@x.com", "Sister")
    inv = client.post(
        f"/api/v1/households/{hid}/members",
        json={"email": "sis@x.com", "role": "caregiver", "permissions": ["medications.read", "adherence.read"]},
        headers=owner["headers"],
    )
    assert inv.status_code == 201
    med = api.medication(owner, hid, senior["id"])
    api.schedule(owner, hid, med["id"], times=["08:00", "20:00"])
    sis = api.login("sis@x.com")
    mine = client.get("/api/v1/households", headers=sis["headers"]).json()
    assert [h["id"] for h in mine] == [hid]
    assert len(client.get(f"/api/v1/households/{hid}/medications", headers=sis["headers"]).json()["items"]) == 1
    assert client.get(f"/api/v1/households/{hid}/schedules", headers=sis["headers"]).status_code == 403
    me = client.get("/api/v1/auth/me", headers=sis["headers"]).json()
    assert set(me["memberships"][0]["permissions"]) == {"medications.read", "adherence.read"}
