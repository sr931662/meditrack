"""Packaging verification. The provider is swappable (cloud vision, on-device model, ...). Whatever the
provider says, the result is a *packaging* match only: it never marks a dose as taken."""

import re
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from typing import Protocol

from sqlalchemy.orm import Session

from app.models import DoseEvent, Medication, VerificationResult
from app.services import engine, sysconfig

TEXT_CONFIDENCE_CAP = 0.97  # text alone is never treated as certain
BARCODE_CONFIDENCE = 0.98
_STRENGTH_RE = re.compile(r"(\d+(?:\.\d+)?)\s*(mg|mcg|µg|g|ml|iu)\b", re.I)


@dataclass
class Outcome:
    status: str
    confidence: float
    matched_medication_id: str | None
    packaging: str | None
    reasons: list[str] = field(default_factory=list)
    next_action: str = "none"


class VerificationProvider(Protocol):
    name: str
    model: str

    def verify(
        self,
        expected: Medication,
        candidates: list[Medication],
        extracted_text: str | None,
        barcode: str | None,
        high: float,
        medium: float,
    ) -> Outcome: ...


def _tokens(s: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", s.lower())


def _name_score(name: str, text: str) -> float:
    n = name.lower()
    if n in text.lower():
        return 1.0
    best = 0.0
    for tok in _tokens(text):
        if len(tok) < 3:
            continue
        score = SequenceMatcher(None, n, tok).ratio()
        if n.startswith(tok):
            score = max(score, 0.5 + 0.5 * len(tok) / len(n))
        best = max(best, score)
    return best if best >= 0.5 else best * 0.5


def _strength_match(strength: str, text: str) -> bool | None:
    want = _STRENGTH_RE.search(strength)
    found = _STRENGTH_RE.findall(text)
    if not want or not found:
        return None
    w = (float(want.group(1)), want.group(2).lower())
    return any((float(v), u.lower()) == w for v, u in found)


class TextMatchVerifier:
    """Deterministic matcher over text/barcode extracted on the device (ML Kit OCR + barcode scanner).
    Replace with a vision-model provider by implementing VerificationProvider."""

    name = "text-match"
    model = "rules-v1"

    def _score(self, med: Medication, text: str | None, barcode: str | None) -> tuple[float, list[str]]:
        reasons: list[str] = []
        if barcode and med.barcode:
            if barcode.strip() == med.barcode:
                return BARCODE_CONFIDENCE, ["Barcode matches the reference packaging"]
            reasons.append("Barcode differs from the reference packaging")
        if not text:
            return (0.1 if reasons else 0.0), reasons or ["No readable text on the packaging"]
        name = _name_score(med.name, text)
        strength = _strength_match(med.strength, text)
        s_component = {True: 1.0, None: 0.5, False: 0.0}[strength]
        if strength is False:
            reasons.append(f"Printed strength does not match the expected {med.strength}")
        elif strength is None:
            reasons.append("No strength was readable")
        if name < 0.5:
            reasons.append(f"Medicine name {med.name} not found on the packaging")
        elif name < 1.0:
            reasons.append("Medicine name only partly readable")
        conf = TEXT_CONFIDENCE_CAP * (0.7 * name + 0.3 * s_component)
        if strength is False:
            conf = min(conf, 0.84)  # a wrong strength can never be a confident match
        return round(conf, 3), reasons

    def verify(self, expected, candidates, extracted_text, barcode, high, medium) -> Outcome:
        scores = {m.id: self._score(m, extracted_text, barcode) for m in candidates}
        conf, reasons = scores[expected.id]
        first_line = next(iter((extracted_text or "").strip().splitlines()), "")[:80]
        packaging = expected.reference_packaging or first_line or None
        other = max((m for m in candidates if m.id != expected.id), key=lambda m: scores[m.id][0], default=None)
        if other is not None and scores[other.id][0] >= medium and scores[other.id][0] > conf:
            return Outcome(
                "no_match",
                conf,
                other.id,
                packaging,
                reasons + [f"Packaging looks like {other.name} {other.strength}, a different medicine"],
                "ask_caregiver",
            )
        if conf >= high:
            return Outcome("match", conf, expected.id, packaging, reasons, "none")
        if conf >= medium:
            return Outcome("uncertain", conf, None, packaging, reasons, "retake_or_secondary")
        return Outcome("no_match", conf, None, packaging, reasons, "ask_caregiver")


_provider: VerificationProvider = TextMatchVerifier()


def get_provider() -> VerificationProvider:
    return _provider


def set_provider(p: VerificationProvider) -> None:  # used by tests / alternative deployments
    global _provider
    _provider = p


def verify_dose(
    db: Session,
    event: DoseEvent,
    extracted_text: str | None,
    barcode: str | None,
    image_ref: str | None,
    actor_id: str | None,
    now,
) -> VerificationResult:
    expected = db.get(Medication, event.medication_id)
    candidates = db.query(Medication).filter_by(senior_id=event.senior_id, is_active=True).all()
    if expected.id not in {m.id for m in candidates}:
        candidates.append(expected)
    high = float(sysconfig.get(db, "verification.high_threshold"))
    medium = float(sysconfig.get(db, "verification.medium_threshold"))
    provider = get_provider()
    out = provider.verify(expected, candidates, extracted_text, barcode, high, medium)
    row = VerificationResult(
        dose_event_id=event.id,
        household_id=event.household_id,
        submitted_by=actor_id,
        status=out.status,
        confidence=out.confidence,
        matched_medication_id=out.matched_medication_id,
        extracted_text=extracted_text,
        barcode=barcode,
        packaging=out.packaging,
        reasons=out.reasons,
        next_action=out.next_action,
        provider=provider.name,
        model=provider.model,
        created_at=now,
    )
    db.add(row)
    db.flush()
    event.verifications.append(row)
    # Deliberately does NOT touch user_reported_taken_at / caregiver_status.
    engine.log_event(db, event, "packaging_verification", now, actor_id, status=out.status, confidence=out.confidence)
    return row
