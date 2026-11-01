from tests.conftest import PASSWORD


def test_register_login_me(api, client):
    u = api.register("a@x.com", "Alice")
    me = client.get("/api/v1/auth/me", headers=u["headers"]).json()
    assert me["email"] == "a@x.com" and me["platform_role"] is None


def test_duplicate_email_rejected(api, client):
    api.register("a@x.com")
    r = client.post("/api/v1/auth/register", json={"email": "A@x.com", "password": PASSWORD, "full_name": "B"})
    assert r.status_code == 409


def test_weak_password_rejected(client):
    r = client.post("/api/v1/auth/register", json={"email": "a@x.com", "password": "short", "full_name": "B"})
    assert r.status_code == 422


def test_wrong_password_is_401_without_user_enumeration(api, client):
    api.register("a@x.com")
    wrong_pw = client.post("/api/v1/auth/login", json={"email": "a@x.com", "password": "nope-nope-nope"})
    no_user = client.post("/api/v1/auth/login", json={"email": "z@x.com", "password": "nope-nope-nope"})
    assert wrong_pw.status_code == no_user.status_code == 401
    assert wrong_pw.json()["error"]["message"] == no_user.json()["error"]["message"]


def test_brute_force_lockout(api, client):
    api.register("a@x.com")
    for _ in range(5):
        client.post("/api/v1/auth/login", json={"email": "a@x.com", "password": "bad-bad-bad-bad"})
    r = client.post("/api/v1/auth/login", json={"email": "a@x.com", "password": PASSWORD})
    assert r.status_code == 429  # locked even with the right password


def test_refresh_rotation_rejects_reuse(api, client):
    u = api.register("a@x.com")
    r1 = client.post("/api/v1/auth/refresh", json={"refresh_token": u["refresh_token"]})
    assert r1.status_code == 200
    reuse = client.post("/api/v1/auth/refresh", json={"refresh_token": u["refresh_token"]})
    assert reuse.status_code == 401
    # reuse of a rotated token revokes the whole session
    again = client.post("/api/v1/auth/refresh", json={"refresh_token": r1.json()["refresh_token"]})
    assert again.status_code == 401


def test_logout_revokes_access_token(api, client):
    u = api.register("a@x.com")
    assert client.get("/api/v1/auth/me", headers=u["headers"]).status_code == 200
    client.post("/api/v1/auth/logout", headers=u["headers"])
    assert client.get("/api/v1/auth/me", headers=u["headers"]).status_code == 401


def test_requires_token(client):
    assert client.get("/api/v1/auth/me").status_code == 401
    assert client.get("/api/v1/auth/me", headers={"Authorization": "Bearer junk"}).status_code == 401
