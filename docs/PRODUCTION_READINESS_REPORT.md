# MediTrack — Production-Readiness Report

_2026-10-31. Re-run in this repository today. Percentages are my judgement, scored on two scales:_
* **Built** = code exists and is covered by automated tests.
* **Prod-ready** = proven in a real environment (device, Postgres, live providers) and safe to put in front of users.

## Checks re-run today

| Check | Result |
|---|---|
| Server tests | 81 passed |
| Server lint | clean |
| Client tests | 53 passed |
| Client analysis | no issues |
| TODO/FIXME markers | 0 |
| Code size | ~3.8k lines Python, ~6.1k lines Dart (excluding tests) |
| Not run (not installed here) | coverage, dependency audit (pip-audit), security scan (bandit), load test, Postgres, Docker, device/emulator |

## Completeness by area

| # | Area | Built | Prod-ready | Main gap |
|---|---|---|---|---|
| 1 | Authentication and sessions | 90% | 65% | No password reset, email verification or MFA |
| 2 | Roles, permissions, tenant isolation | 95% | 75% | Not penetration-tested |
| 3 | Admin console (users, roles, audit, config, support access) | 85% | 60% | Never used in a real UI session |
| 4 | Households, members, seniors | 75% | 55% | No invitation tokens (members must register first) |
| 5 | Medications and schedules | 90% | 65% | Not exercised on a device |
| 6 | Dose lifecycle and evidence model | 95% | 75% | Mostly pure logic, well tested |
| 7 | Reminder engine and job queue | 90% | 55% | `SKIP LOCKED` only works on Postgres, which was never run |
| 8 | Escalation and caregiver resolution | 85% | 40% | WhatsApp/phone adapters never run live; no delivery-status webhook |
| 9 | Packaging verification | 65% | 30% | Rule-based text match only; on-device OCR and barcode unverified; no photo storage |
| 10 | Offline-first and sync | 80% | 50% | Alarm refresh needs the app opened every 3 days; reboot, Doze and OEM battery limits untested |
| 11 | Dashboard and analytics | 65% | 45% | No live updates; day boundaries are UTC |
| 12 | In-app notifications | 70% | 45% | |
| 13 | Push notifications (FCM) | 0% | 0% | Not built |
| 14 | Voice (speak and listen) | 60% | 25% | Never tested on hardware; reminders speak only with app open |
| 15 | Flutter UI vs the Claude Design | 85% | 55% | Widget-tested only; no device or accessibility pass with real 65+ users |
| 16 | Multi-language | 10% | 5% | English only |
| 17 | Healthcare-organisation admin and billing | 5% | 0% | Role exists but switched off |
| 18 | Privacy, consent, retention | 25% | 10% | Per-contact consent flag only; no retention or deletion jobs; no legal review |
| 19 | Database and migrations | 90% | 60% | Verified on SQLite only |
| 20 | Deployment, CI, containers | 60% | 25% | Dockerfile, compose and CI written but never executed |
| 21 | Observability and security hardening | 40% | 25% | No error monitoring, in-process rate limiter only, no load or penetration test |
| 22 | Android release engineering | 35% | 15% | Debug-signed release APK, default icon, no store listing |
| 23 | Documentation | 90% | 85% | Honest and current |

## Overall

| Measure | Score |
|---|---|
| **Feature completeness** (built and tested against the brief, weighted by importance) | **about 68%** |
| **Production-readiness** (proven in a real environment) | **about 40%** |

## Verdict

**Not ready for real patients.** It is a solid, well-tested foundation that is suitable for a pilot with test accounts.
The core logic is the strongest part: the dose-evidence rules, permissions, escalation and sync are tested.
The weakest part is that nothing has touched real hardware, a real database or real providers.

## Blocking items before any real-user pilot

1. Run on real Android devices (OEMs, Doze, reboot, camera/OCR, voice, alarms).
2. Run on Postgres with the worker running twice; restore a backup.
3. Test live WhatsApp (approved template) and phone-call delivery, and add the status webhook.
4. Add password reset, plus a decision on MFA and email verification.
5. Add a signing key, TLS, secrets management and error monitoring.
6. Run a dependency audit, penetration test and load test.
7. Get a legal and compliance review, and a clinical safety review of the wording.
8. Test accessibility with real elderly users.

## Next after that
Push notifications (FCM), background alarm refresh, invitation tokens, translations, consent and retention, organisation features.
