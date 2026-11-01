"""In-memory providers for tests and local development ONLY (rejected when env=production).
Passing a test against these proves our orchestration, not that a live provider works."""

from app.integrations.base import OutboundMessage, SendResult


class MockProvider:
    def __init__(self, name: str):
        self.name = name
        self.sent: list[OutboundMessage] = []
        self.behavior = "ok"  # ok | fail | not_configured

    def send(self, message: OutboundMessage) -> SendResult:
        if self.behavior == "not_configured":
            return SendResult(ok=False, error="provider_not_configured: mock")
        if self.behavior == "fail":
            return SendResult(ok=False, error="mock provider error 503")
        self.sent.append(message)
        return SendResult(ok=True, provider_message_id=f"mock-{self.name}-{len(self.sent)}")
