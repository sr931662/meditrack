# Feature Requirements & Traceability

Legend: ✅ built + tested · 🟡 built, not verifiable here (device/provider) · ⬜ not built

## Core workflow

| Requirement | State | Where |
|---|---|---|
| Voice-first reminders (TTS), text/visual, large buttons | 🟡 | `speech_service`, home, `reminder_service` |
| Speech-to-text responses + typed fallback, 5 required responses | ✅ parse / 🟡 mic | `voice_parser.dart`, `voice_sheet.dart` |
| Recurring, multi-time, weekday, tz-aware schedules | ✅ | `engine.occurrences`, `reminder_planner` |
| Timestamped event per interaction | ✅ | `dose_event_logs` |
| Camera / barcode / QR / OCR capture | 🟡 | `scan_service.dart` |
| Structured verification result + confidence + thresholds | ✅ | `verification.py`, admin config |
| Packaging match never = ingestion | ✅ | tests in `test_verification_sync_admin.py`, `dose_logic_test.dart` |
| Separate states (reminder sent, ack, matched, reported, caregiver confirmed, escalated, resolved, unverified) | ✅ | `DoseEvent` |
| T+0 / T+5 / T+45 configurable escalation, retries, idempotent, history | ✅ | `engine.py`, `test_engine.py` |
| WhatsApp / IVR via adapters, honest delivery status | ✅ mocks / 🟡 live | `integrations/` |
| Caregiver ack, notes, resolve with reason, re-verification request | ✅ | `doses.py`, `alert_screen.dart` |
| "Escalate to another caregiver" (manual) | ⬜ | contacts are auto-notified in priority order |

## RBAC
All roles in `ROLE_PERMISSION_MATRIX.md` ✅ (Healthcare Org admin: gated placeholder only).
Audited super-admin access ✅ · permission editing UI ✅ · session revocation on disable ✅ · bootstrap CLI ✅.

## Medication & household management
Medication CRUD ✅ (name, strength, form, instructions, barcode, reference text, dates, active flag, timestamps) ·
schedules ✅ · audit trail ✅ · households/members/seniors ✅ · prescribing info: `prescriber` field exists, no UI.

## Dashboard
Counts, per-medication, trend chart, delivery status, recent activity, filters (date, senior, medication) ✅.
Filter by event status/priority: API ✅, UI ⬜ (priority only via API). Real-time: ⬜ (pull-to-refresh).

## Notifications
Local notifications 🟡 · in-app ✅ · WhatsApp/IVR adapters ✅/🟡 · FCM ⬜ · templates: message composed in code
(English) – no template table ⬜ · retry ✅ · rate limiting: auth only ✅ · opt-out: per-contact `consent` ✅,
no preference centre ⬜.

## Offline-first
Local DB + outbox ✅/🟡 · local alarms 🟡 · sync, idempotency ✅ · reboot recovery via plugin boot receiver 🟡 ·
tz/DST ✅ (planner) · documented limits ✅ (`OFFLINE_AND_ANDROID.md`).

## Security & privacy
Hashing, tokens, lockout, tenant isolation, audit, config guards ✅ · HTTPS-only release manifest ✅ ·
secure token storage ✅ · upload security n/a (no uploads) · encryption at rest: relies on DB/disk (documented) ·
retention/deletion jobs ⬜ · backups documented only · compliance statements: none claimed.

## Out of scope (roadmap, prepared not built)
Vitals tracking, ageing-at-home, provider connectivity, emergency response; B2B (column + gated role only).
