"""Black-box check of a running demo server: waits for the seeded dose, ignores it, and confirms the
reminder -> verify prompt -> caregiver escalation -> resolve loop with SIMULATED deliveries.
    python scripts/e2e_demo.py http://localhost:8000
Takes ~10 minutes (the demo policy is 2 / 6 minutes)."""

import sys
import time

import httpx

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/") + "/api/v1"
PW = "Demo@12345"


def login(email):
    r = httpx.post(f"{BASE}/auth/login", json={"email": email, "password": PW}, timeout=20)
    r.raise_for_status()
    return {"Authorization": "Bearer " + r.json()["access_token"]}


cg = login("caregiver@demo.meditrack.app")
hh = httpx.get(f"{BASE}/households", headers=cg).json()[0]["id"]
print("household", hh)
deadline = time.time() + 15 * 60
esc = None
while time.time() < deadline:
    es = httpx.get(f"{BASE}/households/{hh}/escalations", headers=cg).json()
    items = es["items"] if isinstance(es, dict) else es
    if items:
        esc = items[0]
        break
    time.sleep(20)
assert esc, "no escalation appeared"
detail = httpx.get(f"{BASE}/households/{hh}/escalations/{esc['id']}", headers=cg).json()
print("escalation", detail["status"], [(d["channel"], d["status"], d["simulated"]) for d in detail["deliveries"]])
assert detail["deliveries"] and all(d["simulated"] for d in detail["deliveries"])
ev = httpx.get(f"{BASE}/households/{hh}/dose-events/{detail['dose_event_id']}", headers=cg).json()
print("dose status:", ev.get("display_status"))
assert ev.get("display_status") != "missed"
httpx.post(f"{BASE}/households/{hh}/escalations/{esc['id']}/acknowledge", headers=cg).raise_for_status()
r = httpx.post(
    f"{BASE}/households/{hh}/escalations/{esc['id']}/resolve",
    headers=cg,
    json={"outcome": "taken_confirmed", "note": "Called mum, she took it."},
)
print("resolve", r.status_code, r.text[:200])
r.raise_for_status()
print("E2E OK")
