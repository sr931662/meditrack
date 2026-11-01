# Offline operation & Android limits

## What works without a connection

* The schedule and medication list are cached in SQLite after any successful load.
* `planReminders` turns the cached schedules into **local alarms** (3-day window, max 60) via
  `flutter_local_notifications` (`zonedSchedule`, exact when the user allows it, else inexact).
* A senior's responses are written to the **outbox** first (SQLite, `client_event_id` idempotency key). The
  UI updates from the outbox immediately; upload is a separate step.
* On reconnect, app resume and app start the outbox is flushed in device-time order. The server answers per
  event; only `applied`/`duplicate` events leave the queue, `rejected` ones are parked and surfaced, network
  failures stay queued with an attempt counter. A lost response causes a retry that the server reports as
  `duplicate`, so nothing is duplicated and no spurious escalation is created (tests on both sides).

## What is *not* guaranteed (be honest with users and stakeholders)

* **Android may delay or drop alarms.** Doze, OEM battery managers (Xiaomi, Oppo, Samsung "sleeping apps"…),
  force-stop and "battery saver" can postpone notifications. Exact alarms need *Alarms & reminders* to be allowed
  (Android 12+); otherwise reminders become inexact (can be minutes late). The Profile screen explains this and
  links the user to grant permissions. Nothing here can promise a reminder at the exact second.
* **Reboot**: the plugin's boot receiver re-creates already scheduled notifications. The 3-day window is only
  extended when the app is opened again (start/resume/connectivity). There is **no WorkManager task** yet, so a
  phone that is never opened for > 3 days will run out of local alarms. (Planned: periodic background refresh.)
* **Time-zone / DST change**: alarms are stored as absolute UTC instants; they are rebuilt on next resume. A
  change while the app is closed is corrected at the next open.
* **Voice**: spoken reminders play when the app is open (e.g. tapping the notification); a notification alone
  shows text + sound, it does not speak.
* **Server-side escalation requires connectivity** from the *server* to providers, not from the phone: if the
  phone is offline at T+45 the caregiver is still alerted (the server never received a response).
  Conversely, a "taken" recorded offline after the escalation fired is stored as a self-report and shown to the
  caregiver, but it does not close the alert; only the caregiver resolves it. If the caregiver had already settled
  the dose, the late response is only logged (`late_response`) and changes nothing.
* Verification (OCR text matching) needs a connection to the server. Without it the app says so and still lets
  the senior report or ask for help.

## Permissions used

`INTERNET`, `ACCESS_NETWORK_STATE`, `CAMERA`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
`RECEIVE_BOOT_COMPLETED`, `VIBRATE`. Camera/mic are requested by their plugins when first used.
