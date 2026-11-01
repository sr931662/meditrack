# Integrations — what is needed, what is verified

**Nothing below has been exercised against a live account from this repository.**

## WhatsApp (Meta Cloud API) — `server/app/integrations/live.py::WhatsAppCloudProvider`
* Need: a Meta Business account, a WhatsApp Business phone number, a permanent access token.
* Business-initiated messages must use an **approved template**. Create one named `medtrack_caregiver_check`
  (language `en`) with **one body variable `{{1}}`** (receives the alert text) and get it approved.
* Env: `MEDTRACK_WHATSAPP_PHONE_NUMBER_ID`, `MEDTRACK_WHATSAPP_ACCESS_TOKEN`.
* The API returning 2xx means *accepted*; the delivery stays `sent`. A delivery-status webhook that upgrades
  to `delivered`/`failed` is **not built**.
* Only contacts with `consent=true` are messaged.

## IVR / automated call (Twilio) — `TwilioIVRProvider`
* Need: Twilio account SID, auth token, a voice-capable caller-id number; check local rules for automated
  health-related calls and caller registration (e.g. India's TRAI/DLT).
* Env: `MEDTRACK_IVR_ACCOUNT_SID`, `MEDTRACK_IVR_AUTH_TOKEN`, `MEDTRACK_IVR_FROM_NUMBER`.
* Uses inline TwiML `<Say>`; no keypad acknowledgement yet.

## Unconfigured behaviour
In `live` mode, missing credentials make a `NotConfiguredProvider` return `provider_not_configured: …`.
The delivery is recorded as **failed** and visible to caregivers ("Some notifications failed to send. Please
call directly."). Nothing is ever reported as sent without a provider acknowledging it.
`MEDTRACK_PROVIDER_MODE=mock` is for dev/tests only and is refused when `MEDTRACK_ENV=production`.

## Firebase Cloud Messaging
Not implemented (needs a Firebase project and `google-services.json`). Add a `push` provider to
`integrations/` and a device-token table; the engine already writes `notifications` rows to fan out from.

## AI verification providers
`VerificationProvider` (`server/app/services/verification.py`) is the swap point. The shipped `text-match`
provider is deterministic (name similarity + strength + barcode) and is **not** a vision model. To use a
cloud/on-device vision model, implement `verify(...)` and call `set_provider(...)`; thresholds
(`verification.high_threshold`, `verification.medium_threshold`) stay admin-configurable and the result is
still only ever a packaging result.
