# Project Audit (Phase 0)

## Starting state

The repository contained only an empty `temp/` folder: **no Flutter code, no backend, no database, no API
contracts**. The only existing asset was the Claude Design project
(`e426e630-…`), read through the design sync tool:

| File | Content |
|---|---|
| `MediTrack.dc.html` (1,003 lines) | Complete interactive prototype: 8 screens, 6 bottom sheets, 1 dialog, all styles and logic |
| `support.js` | The design-canvas runtime (React shim). Not product code; **not** ported |
| `uploads/MediTrack Pitch Deck (1).pdf`, `uploads/pasted-….png` | Reference material (not read; see status doc) |

Both design files were saved to `design/` unchanged so the implementation can be diffed against them.

## What the design contains

* **Persona**: one senior (Margaret Lee, 74) with a caregiver (Daniel Lee) seen only through an "alert" screen.
* **Screens**: Home, Medications (list), Medication details, Verify dose, Analytics, Notifications & Safety,
  Caregiver alert, Profile. **Sheets**: voice assistant, remind-later, add/edit medication form, demo clock,
  simulated call, record outcome. **Dialog**: confirm.
* **Flow**: REMIND → VERIFY → ESCALATE → RESOLVE shown as a 4-step progress on the alert screen.
* **Behaviour**: all local (localStorage), a *demo clock*, *simulated* verification (user picks Match /
  Uncertain / No match) and simulated calls/messages. It labels itself a prototype.

## Gaps vs. the product brief

| Gap | Resolution |
|---|---|
| No backend, auth, roles, households, multi-tenancy | Built (`server/`) |
| Verification is a picker, not computer vision | On-device OCR + barcode (ML Kit), server rule-based matcher behind a provider interface |
| Wording "Taken / Verified" for self-reported doses | Replaced with "Reported taken"; separate packaging / caregiver states |
| No offline sync design (state only in the browser) | SQLite outbox + idempotent sync |
| No admin / household-owner / multi-senior UI | Designed in the same language (see `DESIGN_SYSTEM.md`) |
| Prototype-only controls (demo clock, reset, outcome simulator, "Call (simulated)") | Removed; real `tel:` call, real server state |
| No language catalogue | Not done (English only) — documented |

## Risks and dependencies

* Android Gradle: this machine cannot download Gradle 9; the project is pinned to the cached **Gradle 8.14 +
  AGP 8.13.1 + Kotlin 2.2.20** (documented in `DEPLOYMENT.md`). Re-evaluate when network access is normal.
* Native plugins (ML Kit, mobile_scanner, speech, TTS, notifications) compile but are unverified on hardware.
* Messaging providers need business accounts and (WhatsApp) pre-approved templates.
* Medication safety wording needs clinical review before real use.
* No Docker/Postgres locally; Postgres behaviour (locking) is untested here.
