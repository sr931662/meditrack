"""Authorization, IDOR and tenant isolation."""

import pytest

from tests.conftest import PASSWORD


@pytest.fixture()
def world(api, client):
    owner = api.register("owner@x.com", "Daniel Lee")
    hid = api.household(owner)
    senior = api.senior(owner, hid)
    med = api.medication(owner, hid, senior["id"])
    other = api.register("other@x.com", "Mallory")
    other_hid = api.household(other, "Other family")
    return dict(owner=owner, hid=hid, senior=senior, med=med, other=other, other_hid=other_hid)


def _add_caregiver(client, w, perms, email="cg@x.com"):
    r = client.post("/api/v1/auth/register", json={"email": email, "password": PASSWORD, "full_name": "Sis"})
    assert r.status_code == 201
    r = client.post(
        f"/api/v1/households/{w['hid']}/members",
        json={"email": email, "role": "caregiver", "permissions": perms},
        headers=w["owner"]["headers"],
    )
    assert r.status_code == 201, r.text
    login = client.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD}).json()
    return {"Authorization": f"Bearer {login['access_token']}"}, r.json()


def test_cross_household_access_denied(client, world):
    w = world
    h = w["other"]["headers"]
    for url in (
        f"/api/v1/households/{w['hid']}",
        f"/api/v1/households/{w['hid']}/medications",
        f"/api/v1/households/{w['hid']}/seniors",
        f"/api/v1/households/{w['hid']}/dashboard",
    ):
        assert client.get(url, headers=h).status_code in (403, 404), url


def test_idor_medication_id_from_other_household(client, world):
    """Using my own household in the path with someone else's medication id must not leak it."""
    w = world
    r = client.get(f"/api/v1/households/{w['other_hid']}/medications/{w['med']['id']}", headers=w["other"]["headers"])
    assert r.status_code == 404
    r = client.patch(
        f"/api/v1/households/{w['other_hid']}/medications/{w['med']['id']}",
        json={"name": "Hacked"},
        headers=w["other"]["headers"],
    )
    assert r.status_code == 404


def test_cannot_create_medication_for_foreign_senior(client, world):
    w = world
    r = client.post(
        f"/api/v1/households/{w['other_hid']}/medications",
        json={"senior_id": w["senior"]["id"], "name": "X", "strength": "1 mg", "dosage_form": "tablet"},
        headers=w["other"]["headers"],
    )
    assert r.status_code in (400, 404, 422)


def test_secondary_caregiver_limited_to_granted_permissions(client, world):
    w = world
    h, _ = _add_caregiver(client, w, ["medications.read", "adherence.read"])
    assert client.get(f"/api/v1/households/{w['hid']}/medications", headers=h).status_code == 200
    body = {"senior_id": w["senior"]["id"], "name": "X", "strength": "1 mg", "dosage_form": "tablet"}
    assert client.post(f"/api/v1/households/{w['hid']}/medications", json=body, headers=h).status_code == 403
    assert (
        client.post(
            f"/api/v1/households/{w['hid']}/members",
            json={"email": "owner@x.com", "role": "owner", "permissions": []},
            headers=h,
        ).status_code
        == 403
    )
    mems = client.get(f"/api/v1/households/{w['hid']}/members", headers=w["owner"]["headers"]).json()
    cg = next(m for m in mems if m["email"] == "cg@x.com")
    assert (
        client.patch(
            f"/api/v1/households/{w['hid']}/members/{cg['id']}", json={"permissions": ["medications.update"]}, headers=h
        ).status_code
        == 403
    )
    assert (
        client.put(
            f"/api/v1/households/{w['hid']}/escalation-policy",
            json={"t_verify_min": 1, "t_escalate_min": 2, "contacts": []},
            headers=h,
        ).status_code
        == 403
    )


def test_caregiver_cannot_be_granted_ungrantable_permissions(client, world):
    w = world
    client.post("/api/v1/auth/register", json={"email": "cg@x.com", "password": PASSWORD, "full_name": "Sis"})
    r = client.post(
        f"/api/v1/households/{w['hid']}/members",
        json={"email": "cg@x.com", "role": "caregiver", "permissions": ["billing.manage", "users.disable"]},
        headers=w["owner"]["headers"],
    )
    assert r.status_code == 422


def test_permission_changes_apply_immediately_without_new_token(client, world):
    w = world
    h, member = _add_caregiver(client, w, ["medications.read"])
    assert client.get(f"/api/v1/households/{w['hid']}/medications", headers=h).status_code == 200
    client.patch(f"/api/v1/households/{w['hid']}/members/{member['id']}", json={"permissions": []}, headers=w["owner"]["headers"])
    assert client.get(f"/api/v1/households/{w['hid']}/medications", headers=h).status_code == 403


def test_senior_cannot_use_caregiver_functionality(client, api, world):
    w = world
    s = client.post(
        f"/api/v1/households/{w['hid']}/seniors",
        json={
            "full_name": "Grandpa",
            "language": "en",
            "timezone": "UTC",
            "login_email": "grandpa@x.com",
            "login_password": PASSWORD,
        },
        headers=w["owner"]["headers"],
    )
    assert s.status_code == 201, s.text
    h = api.login("grandpa@x.com")["headers"]
    base = f"/api/v1/households/{w['hid']}"
    body = {"senior_id": s.json()["id"], "name": "X", "strength": "1", "dosage_form": "tablet"}
    assert client.post(f"{base}/medications", json=body, headers=h).status_code == 403
    assert client.get(f"{base}/members", headers=h).status_code == 403
    assert client.get(f"{base}/dashboard", headers=h).status_code == 403
    assert client.get(f"{base}/escalations", headers=h).status_code == 403
    assert client.get("/api/v1/admin/users", headers=h).status_code == 403


def test_regular_user_cannot_reach_admin_api(client, world):
    h = world["owner"]["headers"]
    assert client.get("/api/v1/admin/users", headers=h).status_code == 403
    assert client.get("/api/v1/admin/audit-logs", headers=h).status_code == 403
    assert client.put("/api/v1/admin/config", json={"values": {}}, headers=h).status_code == 403


def test_superadmin_does_not_get_health_data_without_support_grant(client, world, superadmin):
    w = world
    r = client.get(f"/api/v1/households/{w['hid']}/medications", headers=superadmin["headers"])
    assert r.status_code == 403
    # purpose-limited, audited, time-boxed support access
    g = client.post(
        "/api/v1/admin/support-access",
        json={"household_id": w["hid"], "reason": "Ticket #123: user cannot see reminders", "minutes": 30},
        headers=superadmin["headers"],
    )
    assert g.status_code == 201, g.text
    assert client.get(f"/api/v1/households/{w['hid']}/medications", headers=superadmin["headers"]).status_code == 200
    # read-only: still cannot modify
    body = {"senior_id": w["senior"]["id"], "name": "X", "strength": "1", "dosage_form": "tablet"}
    assert client.post(f"/api/v1/households/{w['hid']}/medications", json=body, headers=superadmin["headers"]).status_code == 403
    logs = client.get("/api/v1/admin/audit-logs?action=support_access.granted", headers=superadmin["headers"]).json()
    assert logs["items"] and logs["items"][0]["data"]["reason"].startswith("Ticket #123")


def test_support_access_requires_reason(client, world, superadmin):
    r = client.post(
        "/api/v1/admin/support-access",
        json={"household_id": world["hid"], "reason": "", "minutes": 30},
        headers=superadmin["headers"],
    )
    assert r.status_code == 422
