from dataclasses import dataclass

from app.core.config import get_settings
from app.integrations.base import MessageProvider, NotConfiguredProvider
from app.integrations.demo import DemoProvider
from app.integrations.live import TwilioIVRProvider, WhatsAppCloudProvider
from app.integrations.mock import MockProvider


@dataclass
class Providers:
    whatsapp: MessageProvider
    ivr: MessageProvider

    def for_channel(self, channel: str) -> MessageProvider | None:
        return {"whatsapp": self.whatsapp, "ivr": self.ivr}.get(channel)


_providers: Providers | None = None


def build_providers() -> Providers:
    s = get_settings()
    if s.provider_mode == "demo":
        return Providers(DemoProvider("whatsapp"), DemoProvider("ivr"))
    if s.provider_mode == "mock":
        return Providers(MockProvider("whatsapp"), MockProvider("ivr"))
    wa = (
        WhatsAppCloudProvider(s.whatsapp_phone_number_id, s.whatsapp_access_token)
        if s.whatsapp_phone_number_id and s.whatsapp_access_token
        else NotConfiguredProvider("whatsapp", "set MEDTRACK_WHATSAPP_PHONE_NUMBER_ID and MEDTRACK_WHATSAPP_ACCESS_TOKEN")
    )
    ivr = (
        TwilioIVRProvider(s.ivr_account_sid, s.ivr_auth_token, s.ivr_from_number)
        if s.ivr_account_sid and s.ivr_auth_token and s.ivr_from_number
        else NotConfiguredProvider("ivr", "set MEDTRACK_IVR_ACCOUNT_SID, MEDTRACK_IVR_AUTH_TOKEN, MEDTRACK_IVR_FROM_NUMBER")
    )
    return Providers(wa, ivr)


def get_providers() -> Providers:
    global _providers
    if _providers is None:
        _providers = build_providers()
    return _providers


def reset_providers() -> None:
    global _providers
    _providers = None
