"""Real provider adapters. Written against the vendors' public HTTP APIs but NOT verified against live
accounts in this repository (no credentials available). See docs/INTEGRATIONS.md for required setup."""

import httpx

from app.integrations.base import OutboundMessage, SendResult

TIMEOUT = 10.0


class WhatsAppCloudProvider:
    """Meta WhatsApp Cloud API. Business-initiated messages MUST use a pre-approved template; the template
    name below has to exist in the WhatsApp Business account before this can deliver anything."""

    name = "whatsapp"
    TEMPLATE = "medtrack_caregiver_check"

    def __init__(self, phone_number_id: str, access_token: str):
        self._url = f"https://graph.facebook.com/v20.0/{phone_number_id}/messages"
        self._token = access_token

    def send(self, message: OutboundMessage) -> SendResult:
        payload = {
            "messaging_product": "whatsapp",
            "to": message.to.lstrip("+"),
            "type": "template",
            "template": {
                "name": self.TEMPLATE,
                "language": {"code": "en"},
                "components": [{"type": "body", "parameters": [{"type": "text", "text": message.body}]}],
            },
        }
        try:
            r = httpx.post(self._url, json=payload, headers={"Authorization": f"Bearer {self._token}"}, timeout=TIMEOUT)
        except httpx.HTTPError as exc:
            return SendResult(ok=False, error=f"network_error: {exc.__class__.__name__}")
        if r.status_code >= 400:
            return SendResult(ok=False, error=f"http_{r.status_code}: {r.text[:200]}")
        msgs = r.json().get("messages") or [{}]
        return SendResult(ok=True, provider_message_id=msgs[0].get("id"))


class TwilioIVRProvider:
    """Automated voice call through Twilio's Calls API using inline TwiML."""

    name = "ivr"

    def __init__(self, account_sid: str, auth_token: str, from_number: str):
        self._sid, self._token, self._from = account_sid, auth_token, from_number

    def send(self, message: OutboundMessage) -> SendResult:
        from xml.sax.saxutils import escape

        twiml = f"<Response><Say>{escape(message.body)}</Say></Response>"
        try:
            r = httpx.post(
                f"https://api.twilio.com/2010-04-01/Accounts/{self._sid}/Calls.json",
                data={"To": message.to, "From": self._from, "Twiml": twiml},
                auth=(self._sid, self._token),
                timeout=TIMEOUT,
            )
        except httpx.HTTPError as exc:
            return SendResult(ok=False, error=f"network_error: {exc.__class__.__name__}")
        if r.status_code >= 400:
            return SendResult(ok=False, error=f"http_{r.status_code}: {r.text[:200]}")
        return SendResult(ok=True, provider_message_id=r.json().get("sid"))
