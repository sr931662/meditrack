# Demo guide

APK: `dist/MediTrack-demo.apk` (arm64 Android 7+, signed with the project's demo key, demo sign-in buttons enabled).
Install: copy to the phone and open it (allow "install unknown apps"), or `adb install dist/MediTrack-demo.apk`.
First run: Sign-in screen → **Server** → paste your Cloud Run URL (or `http://<PC-IP>:8000` for a local server).

| Account | Email | Password |
|---|---|---|
| Senior (Kamla Sharma) | senior@demo.meditrack.app | Demo@12345 |
| Caregiver (Priya Sharma) | caregiver@demo.meditrack.app | Demo@12345 |
| Platform admin | admin@demo.meditrack.app | Demo@12345 |

## Three-minute story
Every server start re-anchors the sample schedule to "now": Metformin is due ~3 minutes after start, Amlodipine
after ~70, Atorvastatin after ~200. The demo policy is **verify prompt after 2 min, caregiver alert after 6 min**
(production defaults are 5 / 45; editable in People → Alert rules).

1. **Senior phone**: sign in as Kamla → Home shows the next dose → when due, tap *Taken* / *Remind me later*, or use
   *Verify packaging* (camera). A packaging match or "taken" shows as *Reported taken*, never "confirmed".
2. **Do nothing** on a dose: after 2 min the app asks for verification; after 6 min a caregiver alert is created.
3. **Caregiver phone**: sign in as Priya → Alerts → open it. Deliveries read "Simulated (demo mode)". Acknowledge,
   add a note, **Resolve** with an outcome. The dose shows *Not confirmed* until the caregiver decides, never "Missed".
4. **Admin**: Users, Roles & permissions (edit and see it apply immediately), Audit log, System settings.
5. **Offline**: turn on airplane mode, respond to a dose, turn it off, and it syncs without duplicates.

## What is simulated in the demo
WhatsApp and phone-call alerts (no real message is sent). Everything else is the real code path.
`server/scripts/e2e_demo.py` replays steps 2–3 against a running server.
