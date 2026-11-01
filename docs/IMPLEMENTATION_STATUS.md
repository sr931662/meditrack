# MediTrack — Implementation Status

_Last updated 2026-10-31. This file records what is actually built and verified, and what is not._

## Verification summary (all run in this repository)

| Check | Result |
|---|---|
| Backend tests (`server/`, `pytest`) | **87 passed** |
| Backend lint (`ruff check`, `ruff format`) | clean |
| Alembic migrations 0001–0002 | upgrade + downgrade tested; **no drift vs. models** (test) |
| Flutter tests (`client/`, `flutter test`) | **55 passed** |
| Flutter static analysis (`flutter analyze`) | **no issues** |
| Android debug APK (`flutter build apk --debug`) | **built** |
| Android release APK (`flutter build apk --release`) | **built** (100 MB universal APK, R8 on). Signed with the **debug key** because no `key.properties` exists, so **not distributable** |
| Demo build (2026-11-01) | `dist/MediTrack-demo.apk`: arm64 release, R8, **signed with the project demo keystore** (apksigner verified), demo sign-in buttons, in-app "Server" setting |
| Live demo-mode E2E (`server/scripts/e2e_demo.py`, uvicorn + SQLite, embedded worker) | seeded dose ignored -> verify prompt -> escalation with **simulated** WhatsApp+IVR deliveries -> acknowledge -> resolve: **passed** (dose never shown as "missed") |
| Live API smoke (migrate → bootstrap CLI → uvicorn → login → `/me` → audit) | passed against SQLite |

## Demo / Cloud Run support (added 2026-11-01)
Demo mode (`MEDTRACK_DEMO_MODE`, `PROVIDER_MODE=demo`), embedded worker, auto-migrate, `$PORT` Dockerfile,
`deploy/cloudrun.sh`, `docs/CLOUD_RUN.md`, `docs/DEMO_GUIDE.md`, custom launcher icon, release keystore, simulated-delivery labelling.
**The Cloud Run deployment itself has not been executed** (no GCP project / Docker here).

## What has NOT been verified

* **The app has never been run on a device or emulator.** No Android device was available; UI behaviour is covered by widget tests only. Camera, OCR, barcode, TTS/STT, notifications and alarms are compiled in but **unverified on hardware**.
* **PostgreSQL has not been run.** Docker and Postgres are not installed here; the suite runs on SQLite. Code uses portable SQLAlchemy; `FOR UPDATE SKIP LOCKED` is only exercised on Postgres. `docker-compose.yml` is untested.
* **WhatsApp and IVR providers are not verified against live accounts** (no credentials). Only the abstraction, request code and mocks exist. Passing mock tests proves orchestration, not integration.
* **FCM push is not implemented** (no Firebase project). Reminders use local alarms; caregiver alerts use WhatsApp/IVR adapters + in-app notifications.
* **Real-time dashboard** is pull-to-refresh/polling-on-open, not WebSocket/SSE.
* The pitch-deck PDF in the design project was not read; the T+0 / T+5 / T+45 timings come from the task brief.

## Completed (implemented + tested)

| Area | Status |
|---|---|
| Auth: register, login, 15-min access JWT, rotating refresh tokens with reuse detection, logout, per-request session check, brute-force lockout, Argon2id | ✅ |
| Bootstrap super admin via CLI only (no default credentials, no HTTP route) | ✅ |
| Central RBAC: DB-backed role→permission map, per-member caregiver grants, immediate effect, household membership + object-level scoping (no IDOR), senior self-scoping | ✅ |
| Admin: users CRUD-lite, disable/enable (revokes sessions), platform-role assignment (super-admin only), role permission editing, audit log, system config, time-boxed read-only **support access with mandatory reason** | ✅ |
| Households, members (invite by email of an existing account), seniors (+optional own login, phone) | ✅ |
| Medications + schedules CRUD (soft delete, validation, pagination/sort/filter, audit) | ✅ |
| Dose lifecycle with **separate evidence fields**; derived status never yields "missed" without a human decision | ✅ |
| Durable job outbox (reminder / T+verify / T+escalate), tz + DST-correct occurrences, idempotent materialisation, restart-safe | ✅ |
| Escalation: one per dose (DB-unique), priority-ordered contacts, per-channel deliveries with idempotency keys, bounded retry/backoff, honest statuses (`sent` ≠ `delivered`), consent flag, no-contact case recorded | ✅ |
| Caregiver ack → note → resolve (reason required), request-another-verification | ✅ |
| Verification: provider interface, rule-based text/barcode matcher, thresholds configurable by admin, structured result, never sets "taken" | ✅ |
| Offline sync endpoint: per-event idempotency (`client_event_id`), device-time ordering, per-event results | ✅ |
| Dashboard + trend endpoints (filters: date, senior, medication, priority) | ✅ |
| Flutter: all design screens implemented natively (Home, Medications/detail/form, Verify, Notifications, Alert flow, Profile, voice/defer/outcome sheets) — see `DESIGN_SYSTEM.md` for deviations | ✅ (widget-tested) |
| Flutter: role shells (Senior / Caregiver / Admin) with permission-driven tabs | ✅ |
| Flutter offline: SQLite outbox, cached schedule, sync service (single-flight, grouped, idempotent), local alarm planner (tz/DST), connectivity/resume triggers | ✅ logic tested; ⚠ platform plumbing unverified on device |
| Packaging/CI: Dockerfile, compose, `.env.example`, GitHub Actions workflow, Alembic | ✅ written; CI/compose not executed |

## Pending / not done

* On-device verification of everything under "NOT verified".
* FCM push; WebSocket/SSE live dashboard.
* Image upload for verification (only on-device OCR text/barcode is sent; the photo is deleted locally). The brief's "secure file uploads" are therefore **not applicable yet**; if photo retention is wanted it needs a storage backend, content-type/size checks and malware scanning.
* "Escalate to another caregiver" as a manual action (automatic priority-ordered contacts exist).
* Invitation tokens for people without an account (members must register first).
* Consent management UI/records beyond the per-contact `consent` flag; data-retention/deletion jobs; backup automation (documented only).
* Multilingual UI strings and dialect providers: language/locale is stored per senior and passed to TTS/STT, but **no translated string catalogue exists** (English only).
* Healthcare Organisation Admin: `org_admin` role + `organization_id` column exist and are **feature-gated off**; no organisation features are built.
* Subscriptions/billing: permission names exist; nothing implemented.
* Workmanager-style background refresh of local alarms (see `OFFLINE_AND_ANDROID.md`).
* Redis, error-monitoring integration (hook point only), per-replica rate limiting beyond the in-process auth limiter + DB lockout.
* Release signing key, Play Store listing, app icon (default Flutter launcher icon).

## Known issues / limitations

* Release APK in the repo state is debug-signed (no key). Use `--split-per-abi` for distribution sizes.
* Senior cannot undo a mistaken "taken" (events are append-only by design; the design's "Undo" was dropped).
* "Remind me again" always uses the fixed 10-minute snooze, even if the user says another duration.
* Dashboard "day" boundaries are UTC, not each senior's local day.
* `sent` deliveries are never upgraded to `delivered` yet: the provider status-callback endpoint is not built.
* Kotlin incremental-cache stack traces appear during Android builds on this machine (project on `D:`, pub cache on `C:`); builds still succeed.

## Integration status

| Integration | State |
|---|---|
| WhatsApp Cloud API | adapter written (template `medtrack_caregiver_check` must exist + be approved); **unverified**, needs `MEDTRACK_WHATSAPP_*` |
| Twilio voice (IVR) | adapter written; **unverified**, needs `MEDTRACK_IVR_*` |
| FCM | not implemented |
| ML Kit OCR / barcode | compiled; unverified on device |
| Android TTS / STT | compiled; unverified on device |
| Postgres | configured, untested here |

## Architectural decisions

1. **Sync SQLAlchemy 2 + FastAPI threadpool**, not async: simpler transactions, adequate for this workload.
2. **Outbox table instead of an in-memory scheduler**; workers are stateless and can be scaled (`SKIP LOCKED`).
3. **Evidence kept in separate columns**, status derived — makes "packaging match ⇒ taken" unrepresentable.
4. **Permissions in DB**, checked per request — changes and revocations apply without new tokens.
5. **OCR/barcode on device**; server only matches text. Avoids storing photos of health products.
6. **Riverpod + go_router + Dio + sqflite**, feature-first folders.
7. Server timestamps UTC; schedules store local wall-clock + IANA tz so DST is handled by `zoneinfo`.

## Outstanding production requirements

Real secrets (`JWT_SECRET`, provider keys), Postgres + backups + restore drill, TLS termination, signed release key, WhatsApp template approval and IVR number, push (FCM) if wanted, error monitoring, load/penetration testing, a legal/compliance review for the deployment jurisdiction (this repository claims **no** HIPAA/DPDP/DSCI certification), clinical safety review of wording, accessibility audit with real 65+ users.
