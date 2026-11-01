# Architecture

```
MedTrack/
├─ client/   Flutter (Android) – feature-first, Riverpod, go_router, Dio, sqflite
├─ server/   FastAPI + SQLAlchemy 2 + Alembic (PostgreSQL in prod, SQLite in tests)
├─ design/   Claude Design export (MediTrack.dc.html, support.js) – source of truth for UI
└─ docs/
```

## Server (`server/app`)

```
core/          config (env, prod guards), db (UTC DateTime type), security (Argon2id, JWT), errors, permissions registry
models/        identity (users, sessions, role_permissions, audit, support grants, config)
               care (households, memberships, seniors, medications, schedules, escalation policy)
               events (dose_events + logs, verifications, jobs, escalations, deliveries, notifications, sync receipts)
services/      auth, authz, audit, bootstrap, sysconfig, engine, doses, verification, sync
integrations/  base (interfaces), mock (tests/dev only), live (WhatsApp Cloud, Twilio), registry
api/v1/        auth, households, care, doses, admin  (+ deps.py: auth/authz dependencies)
worker.py      stateless loop: materialize → process_due(jobs) → retry deliveries
cli.py         create-super-admin, seed
```

### Reminder → Verify → Escalate → Resolve

1. `materialize(now, horizon)` creates `dose_events` for each active schedule occurrence (local wall-clock
   + IANA tz → UTC, DST-safe, unique `(schedule_id, scheduled_for)`) and three **jobs**:
   `reminder @T+0`, `verify @T+t_verify (5)`, `escalate @T+t_escalate (45)`. Policy per household, editable;
   changes re-time pending jobs.
2. `process_due(now)` claims due jobs (`FOR UPDATE SKIP LOCKED` on Postgres), runs the handler in a savepoint,
   marks them done. Failures leave the job pending for the next tick.
3. `escalate` creates **one** `Escalation` per dose (DB unique) → in-app caregiver notification → one
   `EscalationDelivery` per (contact × channel) with a unique idempotency key → provider adapter.
   Provider `ok` ⇒ status `sent` (accepted, **not** delivered). Failure ⇒ `failed` + backoff (5·n min),
   max 5 attempts. No contacts / no consent ⇒ recorded as `escalation_no_contacts`, never faked.
4. A senior response before T+45 (taken / snooze) prevents escalation; `help|unwell|cannot_find` pulls it
   forward immediately; snooze moves it to snooze+45.
5. Caregiver: acknowledge → (notes, request re-check) → resolve with outcome + mandatory note. Only
   `taken_confirmed` / `not_taken_confirmed` set `caregiver_status`.

### Evidence model (why "image match ⇒ taken" cannot happen)

`dose_events` stores independent facts: `reminder_sent_at`, `acknowledged_at`, `user_reported_taken_at`,
`caregiver_status`, `help_requested_at`, resolution, plus related `verification_results` (`packaging_matched`
is derived). `display_status` is a property over them and has no "missed". Verification code never writes
the taken/caregiver fields (tested).

### Offline sync

Device keeps an outbox keyed by `client_event_id`. `POST /households/{id}/sync/events` applies events in
device-time order, answers per event `applied | duplicate | rejected`, never fails the whole batch, and
stores a receipt for idempotency. Events may reference `schedule_id + scheduled_for` when the server record
was never downloaded. Conflict rule: server is append-only; a response arriving after a caregiver settled
the dose is logged as `late_response` and changes nothing.

## Client (`client/lib`)

```
core/      theme (tokens from design), network (ApiClient: bearer, single-flight refresh), storage, widgets, util
data/      repositories (Care, Dose, Admin)
features/  auth, home (senior), medications, doses (status logic), verification, escalation, notifications,
           analytics (caregiver overview), household (people), admin, profile, shell
offline/   local_store (sqflite + memory), outbox, sync_service, reminder_planner (pure)
services/  speech (TTS/STT), reminder_service (local alarms), scan_service (ML Kit OCR + barcode)
app/       routes (go_router, auth redirect), app (lifecycle/connectivity hooks)
```

* No business rules in widgets: status wording lives in `doses/dose_logic.dart`, voice intents in
  `home/voice_parser.dart`, reminder planning in `offline/reminder_planner.dart` — all unit-tested.
* UI permission checks only choose which tabs/buttons to show; the server re-checks everything.
* Secrets: none in the app. Tokens in Android Keystore-backed secure storage; API URL via `--dart-define`.

## Security controls

Argon2id, 15-min JWT + rotating refresh with reuse detection, per-request session lookup (instant
revocation), account lockout, in-process auth rate limiter (gateway limiter required for multi-replica),
generic login errors, production config guards (no default secret / mock providers / SQLite), audit rows
written in the same transaction as the action (action fails if audit fails), support access time-boxed +
reasoned, application logs record ids and event types rather than names or medication details (no automated log-redaction filter yet; uvicorn access logs contain request paths), HTTPS-only release manifest
(cleartext only in debug).

## Extension points

Stage 2 (vitals): new `vitals` module + tables, reuse `households`/permissions. Stage 3: `organization_id`
on households and `org_admin` role are already present (gated). Verification provider, message providers,
and storage are interfaces.
