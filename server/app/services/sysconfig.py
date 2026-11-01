from sqlalchemy.orm import Session

from app.models import SystemConfig

DEFAULTS: dict[str, object] = {
    "verification.high_threshold": 0.85,
    "verification.medium_threshold": 0.55,
    "features.b2b_enabled": False,
    "escalation.default_verify_min": 5,
    "escalation.default_escalate_min": 45,
}


def get(db: Session, key: str):
    row = db.get(SystemConfig, key)
    return row.value if row is not None else DEFAULTS.get(key)


def all_values(db: Session) -> dict:
    out = dict(DEFAULTS)
    for row in db.query(SystemConfig).all():
        out[row.key] = row.value
    return out


def set_value(db: Session, key: str, value) -> None:
    row = db.get(SystemConfig, key)
    if row is None:
        db.add(SystemConfig(key=key, value=value))
    else:
        row.value = value
    db.flush()
