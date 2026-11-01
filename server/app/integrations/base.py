from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class OutboundMessage:
    to: str
    body: str
    idempotency_key: str
    kind: str = "escalation"


@dataclass(frozen=True)
class SendResult:
    """`ok=True` means the provider ACCEPTED the message. It does not mean the human received it;
    that is only ever established by a provider delivery callback (status 'delivered')."""

    ok: bool
    provider_message_id: str | None = None
    error: str | None = None


class MessageProvider(Protocol):
    name: str

    def send(self, message: OutboundMessage) -> SendResult: ...


class NotConfiguredProvider:
    """Used in live mode when credentials are missing. It fails loudly instead of pretending to send."""

    def __init__(self, name: str, hint: str):
        self.name = name
        self._hint = hint

    def send(self, message: OutboundMessage) -> SendResult:
        return SendResult(ok=False, error=f"provider_not_configured: {self._hint}")
