"""Demo-mode providers: they accept every message and label it as SIMULATED (`demo-` id prefix).
Nothing is sent to a real phone. The API exposes `simulated: true` and the app says so; a simulated
delivery is never presented as a real WhatsApp message or phone call."""

from app.integrations.base import OutboundMessage, SendResult

DEMO_ID_PREFIX = "demo-"


class DemoProvider:
    def __init__(self, name: str):
        self.name = name

    def send(self, message: OutboundMessage) -> SendResult:
        return SendResult(ok=True, provider_message_id=f"{DEMO_ID_PREFIX}{message.idempotency_key}"[:128])
