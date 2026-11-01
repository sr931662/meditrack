import pytest
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect

from alembic import command
from app.core.config import Settings
from app.core.db import Base
from app.models import AuditLog, User
from tests.conftest import PASSWORD


def _alembic_cfg(url):
    cfg = Config("alembic.ini")
    cfg.cmd_opts = type("o", (), {"x": [f"url={url}"]})()
    return cfg


def test_migrations_match_models_and_downgrade_cleanly(tmp_path):
    url = f"sqlite:///{tmp_path / 'm.db'}"
    cfg = _alembic_cfg(url)
    command.upgrade(cfg, "head")
    eng = create_engine(url)
    with eng.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == [], f"models drifted from migrations: {diff}"
    assert "dose_events" in inspect(eng).get_table_names()
    command.downgrade(cfg, "base")
    assert "dose_events" not in inspect(create_engine(url)).get_table_names()


def test_bootstrap_cli_creates_super_admin_once(db, session_factory, monkeypatch, capsys):
    from app import cli

    monkeypatch.setattr(cli, "session_factory", lambda: session_factory)
    monkeypatch.setenv("MEDTRACK_BOOTSTRAP_PASSWORD", PASSWORD)
    assert cli.main(["create-super-admin", "--email", "Boss@x.com", "--name", "Boss"]) == 0
    db.expire_all()
    u = db.query(User).filter_by(email="boss@x.com").one()
    assert u.platform_role == "super_admin"
    assert db.query(AuditLog).filter_by(action="user.bootstrap_super_admin").count() == 1
    assert cli.main(["create-super-admin", "--email", "boss@x.com", "--name", "Boss"]) == 1  # no overwrite


def test_cli_rejects_weak_bootstrap_password(session_factory, monkeypatch):
    from app import cli

    monkeypatch.setattr(cli, "session_factory", lambda: session_factory)
    monkeypatch.setenv("MEDTRACK_BOOTSTRAP_PASSWORD", "short")
    assert cli.main(["create-super-admin", "--email", "a@x.com", "--name", "A"]) == 1


def test_bootstrap_has_no_http_surface(client):
    r = client.post(
        "/api/v1/auth/register", json={"email": "a@x.com", "password": PASSWORD, "full_name": "A", "platform_role": "super_admin"}
    )
    assert r.status_code == 201
    token = client.post("/api/v1/auth/login", json={"email": "a@x.com", "password": PASSWORD}).json()["access_token"]
    me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"}).json()
    assert me["platform_role"] is None  # extra field ignored: self-registration can never create an admin


@pytest.mark.parametrize(
    "kwargs",
    [
        {"jwt_secret": "change-me"},
        {"jwt_secret": "short"},
        {"jwt_secret": "x" * 40, "provider_mode": "mock", "database_url": "postgresql+psycopg://u:p@h/db"},
        {"jwt_secret": "x" * 40, "database_url": "sqlite:///x.db"},
    ],
)
def test_production_refuses_insecure_configuration(kwargs):
    with pytest.raises(ValueError):
        Settings(env="production", _env_file=None, **{"database_url": "postgresql+psycopg://u:p@h/db", **kwargs})


def test_live_mode_without_credentials_never_fakes_success(monkeypatch):
    from app.core.config import get_settings
    from app.integrations.base import OutboundMessage
    from app.integrations.registry import build_providers

    monkeypatch.setattr(get_settings(), "provider_mode", "live")
    p = build_providers()
    r = p.whatsapp.send(OutboundMessage(to="+15550100001", body="x", idempotency_key="k"))
    assert r.ok is False and "provider_not_configured" in r.error
