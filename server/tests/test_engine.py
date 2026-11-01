"""Reminder -> verify -> escalate -> resolve lifecycle. The engine takes an explicit `now`."""

import pytest

from app.models import AuditLog, DoseEvent, Escalation, EscalationDelivery, Notification
from app.services import engine
from tests.conftest import utc

DAY = (2026, 10, 26)


@pytest.fixture()
def w(api, client):
    owner = api.register("owner@x.com", "Daniel Lee")
    hid = api.household(owner)
    senior = api.senior(owner, hid, login_email="margaret@x.com", login_password="Str0ng-Passw0rd!")
    med = api.medication(owner, hid, senior["id"])
    api.schedule(owner, hid, med["id"], times=["08:00"])
    api.policy(owner, hid)
    return dict(owner=owner, hid=hid, senior=senior, med=med, senior_auth=api.login("margaret@x.com"))


def event(db, w):
    db.expire_all()
    return db.query(DoseEvent).filter_by(household_id=w["hid"]).one()


def at(h, m=0):
    return utc(*DAY, h, m)


def prime(db, providers, w):
    engine.materialize(db, at(7, 50))
    db.commit()


def test_materialize_is_idempotent(db, w, providers):
    engine.materialize(db, at(7, 50))
    engine.materialize(db, at(7, 51))
    db.commit()
    assert db.query(DoseEvent).filter_by(household_id=w["hid"]).count() == 1


def test_t0_reminder_sets_reminder_sent_only(db, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(8, 0), providers)
    db.commit()
    e = event(db, w)
    assert e.reminder_sent_at is not None
    assert e.acknowledged_at is None and e.user_reported_taken_at is None and e.caregiver_status is None
    assert db.query(Notification).filter_by(household_id=w["hid"], kind="reminder").count() == 1


def test_nothing_fires_early(db, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(7, 59), providers)
    db.commit()
    assert event(db, w).reminder_sent_at is None


def test_t5_secondary_verification_prompt(db, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(8, 5), providers)
    db.commit()
    e = event(db, w)
    assert e.verification_prompted_at is not None
    assert e.escalation is None


def test_t45_escalation_notifies_caregiver_without_declaring_missed(db, client, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    e = event(db, w)
    assert e.escalation is not None
    assert e.display_status == "escalated"
    assert "missed" not in e.display_status
    channels = {d.channel for d in e.escalation.deliveries}
    assert channels == {"whatsapp", "ivr"}
    for d in e.escalation.deliveries:
        # accepted by the provider is NOT the same as delivered to the person
        assert d.status == "sent" and d.provider_message_id
    msg = providers.whatsapp.sent[0]
    assert "missed" not in msg.body.lower() and "not confirmed" in msg.body.lower()


def test_escalation_is_idempotent(db, w, providers):
    prime(db, providers, w)
    for minute in (45, 46, 50, 59):
        engine.process_due(db, at(8, minute), providers)
        db.commit()
    assert db.query(Escalation).count() == 1
    assert db.query(EscalationDelivery).count() == 2
    assert len(providers.whatsapp.sent) == 1 and len(providers.ivr.sent) == 1


def test_concurrent_worker_replay_does_not_duplicate(db, w, providers, session_factory):
    prime(db, providers, w)
    other = session_factory()
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    engine.process_due(other, at(8, 45), providers)  # second worker, same instant
    other.commit()
    other.close()
    assert db.query(Escalation).count() == 1 and len(providers.whatsapp.sent) == 1


def test_failed_delivery_is_never_marked_sent_and_is_retried(db, w, providers):
    providers.whatsapp.behavior = "fail"
    prime(db, providers, w)
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    db.expire_all()
    wa = db.query(EscalationDelivery).filter_by(channel="whatsapp").one()
    assert wa.status == "failed" and wa.attempts == 1 and wa.last_error
    assert db.query(EscalationDelivery).filter_by(channel="ivr").one().status == "sent"
    providers.whatsapp.behavior = "ok"
    engine.process_due(db, at(8, 50), providers)  # retry backoff elapsed
    db.commit()
    db.expire_all()
    wa = db.query(EscalationDelivery).filter_by(channel="whatsapp").one()
    assert wa.status == "sent" and wa.attempts == 2
    assert len(providers.ivr.sent) == 1  # ivr not re-sent


def test_delivery_retries_are_bounded(db, w, providers):
    providers.whatsapp.behavior = "fail"
    prime(db, providers, w)
    for m in range(45, 59):
        engine.process_due(db, at(8, m), providers)
        db.commit()
    for h in range(9, 14):
        engine.process_due(db, at(h, 0), providers)
        db.commit()
    db.expire_all()
    wa = db.query(EscalationDelivery).filter_by(channel="whatsapp").one()
    assert wa.status == "failed" and wa.attempts == engine.MAX_DELIVERY_ATTEMPTS


def test_unconfigured_provider_reports_failure_not_success(db, w, providers):
    providers.ivr.behavior = "not_configured"
    prime(db, providers, w)
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    d = db.query(EscalationDelivery).filter_by(channel="ivr").one()
    assert d.status == "failed" and "not_configured" in d.last_error


def test_user_response_before_threshold_prevents_escalation(db, client, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(8, 0), providers)
    db.commit()
    e = event(db, w)
    r = client.post(
        f"/api/v1/households/{w['hid']}/dose-events/{e.id}/respond",
        json={"response": "taken", "occurred_at": "2026-10-26T08:10:00Z"},
        headers=w["senior_auth"]["headers"],
    )
    assert r.status_code == 200, r.text
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    e = event(db, w)
    assert e.escalation is None
    assert e.display_status == "user_reported_taken"
    assert e.independently_confirmed is False  # self-report is never presented as confirmed


def test_help_response_escalates_immediately(db, client, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(8, 0), providers)
    db.commit()
    e = event(db, w)
    r = client.post(
        f"/api/v1/households/{w['hid']}/dose-events/{e.id}/respond",
        json={"response": "unwell", "occurred_at": "2026-10-26T08:02:00Z"},
        headers=w["senior_auth"]["headers"],
    )
    assert r.status_code == 200
    engine.process_due(db, at(8, 3), providers)
    db.commit()
    assert event(db, w).escalation is not None
    assert "unwell" in providers.whatsapp.sent[0].body.lower() or "not feeling well" in providers.whatsapp.sent[0].body.lower()


def test_remind_later_defers_escalation_clock(db, client, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(8, 0), providers)
    db.commit()
    e = event(db, w)
    client.post(
        f"/api/v1/households/{w['hid']}/dose-events/{e.id}/respond",
        json={"response": "remind_later", "occurred_at": "2026-10-26T08:03:00Z"},
        headers=w["senior_auth"]["headers"],
    )
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    assert event(db, w).escalation is None  # snoozed, escalation moved to 08:03 + 45


def test_acknowledge_and_resolve_flow_with_audit_trail(db, client, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    e = event(db, w)
    hid, h = w["hid"], w["owner"]["headers"]
    esc_id = e.escalation.id
    assert client.get(f"/api/v1/households/{hid}/escalations?status=open", headers=h).json()["total"] == 1
    # cannot resolve before acknowledging
    r = client.post(
        f"/api/v1/households/{hid}/escalations/{esc_id}/resolve", json={"outcome": "taken_confirmed", "note": "x"}, headers=h
    )
    assert r.status_code == 409
    assert client.post(f"/api/v1/households/{hid}/escalations/{esc_id}/acknowledge", headers=h).status_code == 200
    # idempotent acknowledge
    assert client.post(f"/api/v1/households/{hid}/escalations/{esc_id}/acknowledge", headers=h).status_code == 200
    n = client.post(f"/api/v1/households/{hid}/escalations/{esc_id}/notes", json={"note": "Called, no answer"}, headers=h)
    assert n.status_code == 201
    # resolution requires a reason
    assert (
        client.post(
            f"/api/v1/households/{hid}/escalations/{esc_id}/resolve", json={"outcome": "not_taken_confirmed"}, headers=h
        ).status_code
        == 422
    )
    r = client.post(
        f"/api/v1/households/{hid}/escalations/{esc_id}/resolve",
        json={"outcome": "not_taken_confirmed", "note": "She confirmed she skipped it"},
        headers=h,
    )
    assert r.status_code == 200, r.text
    e = event(db, w)
    # only now, after a human recorded it, is the dose classified as not taken
    assert e.display_status == "resolved"
    assert e.caregiver_status == "not_taken"
    actions = [x.type for x in sorted(e.logs, key=lambda x: x.at)]
    for expected in ("reminder_sent", "escalation_triggered", "escalation_acknowledged", "caregiver_note", "escalation_resolved"):
        assert expected in actions, actions
    assert db.query(AuditLog).filter_by(action="escalation.resolved").count() == 1


def test_resolved_event_is_not_escalated_again(db, client, w, providers):
    prime(db, providers, w)
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    esc_id = event(db, w).escalation.id
    h, hid = w["owner"]["headers"], w["hid"]
    client.post(f"/api/v1/households/{hid}/escalations/{esc_id}/acknowledge", headers=h)
    client.post(
        f"/api/v1/households/{hid}/escalations/{esc_id}/resolve", json={"outcome": "taken_confirmed", "note": "ok"}, headers=h
    )
    engine.process_due(db, at(9, 30), providers)
    db.commit()
    assert db.query(Escalation).count() == 1 and len(providers.whatsapp.sent) == 1


def test_configurable_escalation_timing(db, api, w, providers):
    api.policy(w["owner"], w["hid"], t_verify=2, t_escalate=20)
    prime(db, providers, w)
    engine.process_due(db, at(8, 19), providers)
    db.commit()
    assert event(db, w).escalation is None
    engine.process_due(db, at(8, 20), providers)
    db.commit()
    assert event(db, w).escalation is not None


def test_multiple_contacts_in_priority_order(db, api, w, providers):
    api.policy(
        w["owner"],
        w["hid"],
        contacts=[
            {"name": "Sis", "phone": "+15550100002", "channels": ["whatsapp"], "priority": 2},
            {"name": "Daniel", "phone": "+15550100001", "channels": ["whatsapp"], "priority": 1},
        ],
    )
    prime(db, providers, w)
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    assert [m.to for m in providers.whatsapp.sent] == ["+15550100001", "+15550100002"]


def test_no_contacts_configured_is_recorded_not_faked(db, api, w, providers):
    api.policy(w["owner"], w["hid"], contacts=[])
    prime(db, providers, w)
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    e = event(db, w)
    assert e.escalation is not None and e.escalation.deliveries == []
    assert any(lg.type == "escalation_no_contacts" for lg in e.logs)


def test_opt_out_contact_is_not_messaged(db, api, w, providers):
    api.policy(
        w["owner"],
        w["hid"],
        contacts=[{"name": "Daniel", "phone": "+15550100001", "channels": ["whatsapp"], "priority": 1, "consent": False}],
    )
    prime(db, providers, w)
    engine.process_due(db, at(8, 45), providers)
    db.commit()
    assert providers.whatsapp.sent == []
    assert any(lg.type == "escalation_no_contacts" for lg in event(db, w).logs)


def test_timezone_aware_scheduling(db, api, client):
    owner = api.register("tz@x.com")
    hid = api.household(owner)
    s = api.senior(owner, hid, timezone="Asia/Kolkata")
    med = api.medication(owner, hid, s["id"])
    api.schedule(owner, hid, med["id"], times=["08:00"], timezone="Asia/Kolkata")
    engine.materialize(db, utc(2026, 10, 26, 0, 0))
    db.commit()
    e = db.query(DoseEvent).filter_by(household_id=hid).one()
    assert e.scheduled_for == utc(2026, 10, 26, 2, 30)  # 08:00 IST


def test_dst_transition_keeps_local_wall_clock(db, api, client):
    owner = api.register("dst@x.com")
    hid = api.household(owner)
    s = api.senior(owner, hid, timezone="America/New_York")
    med = api.medication(owner, hid, s["id"])
    api.schedule(owner, hid, med["id"], times=["08:00"], timezone="America/New_York")
    engine.materialize(db, utc(2026, 10, 31, 0, 0), horizon_hours=72)  # US DST ends 2026-11-01 at 02:00
    db.commit()
    times = sorted(e.scheduled_for for e in db.query(DoseEvent).filter_by(household_id=hid))
    assert times[0] == utc(2026, 10, 31, 12, 0)  # 08:00 EDT (UTC-4)
    assert times[1] == utc(2026, 11, 1, 13, 0)  # 08:00 EST (UTC-5): same wall clock, shifted UTC
    assert times[2] == utc(2026, 11, 2, 13, 0)


def test_weekday_filter_and_date_range(db, api, client):
    owner = api.register("wd@x.com")
    hid = api.household(owner)
    s = api.senior(owner, hid)
    med = api.medication(owner, hid, s["id"])
    r = client.post(
        f"/api/v1/households/{hid}/schedules",
        json={
            "medication_id": med["id"],
            "times": ["08:00"],
            "weekdays": [0],
            "start_date": "2026-10-01",
            "end_date": "2026-10-31",
            "timezone": "UTC",
        },
        headers=owner["headers"],
    )
    assert r.status_code == 201
    engine.materialize(db, utc(2026, 10, 26, 0, 0), horizon_hours=24 * 14)  # Mon 26 Oct ... Mon 9 Nov
    db.commit()
    dates = sorted(e.scheduled_for.date().isoformat() for e in db.query(DoseEvent).filter_by(household_id=hid))
    assert dates == ["2026-10-26"]  # Mondays only, nothing after end_date
