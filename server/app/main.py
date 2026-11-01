import logging
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.api.v1 import admin, auth, care, doses, households
from app.core.config import get_settings
from app.core.db import get_db
from app.core.errors import install_error_handlers

AUTH_LIMIT_PER_MINUTE = 60


log = logging.getLogger("medtrack")


def _startup() -> tuple | None:
    """Optional start-up work for single-service hosts such as Cloud Run (all off by default)."""
    s = get_settings()
    if s.auto_migrate:
        from alembic.config import Config

        from alembic import command

        command.upgrade(Config("alembic.ini"), "head")
        log.info("database migrated")
    if s.demo_mode:
        from app.core.db import session_factory
        from app.services import bootstrap, demo

        db = session_factory()()
        try:
            bootstrap.seed_reference_data(db)
            demo.seed_demo(db, s.demo_password)
            db.commit()
            log.warning("DEMO MODE: sample accounts/data seeded; providers=%s", s.provider_mode)
        finally:
            db.close()
    if s.embedded_worker:
        from app import worker

        return worker.start_embedded()
    return None


def create_app() -> FastAPI:
    settings = get_settings()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        handle = _startup()
        yield
        if handle:
            handle[1].set()

    app = FastAPI(
        title="MediTrack API", version="1.0.0", docs_url=None if settings.env == "production" else "/docs", lifespan=lifespan
    )
    install_error_handlers(app)
    if settings.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_methods=["*"], allow_headers=["*"])

    # Per-process limiter for credential endpoints. Behind multiple replicas use the gateway / Redis limiter
    # (documented in docs/DEPLOYMENT.md); account lockout in the DB is the cross-replica protection.
    hits: dict[str, deque] = defaultdict(deque)

    @app.middleware("http")
    async def rate_limit_auth(request: Request, call_next):
        if request.url.path.startswith("/api/v1/auth/") and request.method == "POST":
            key = request.client.host if request.client else "unknown"
            now, q = time.monotonic(), hits[key]
            while q and now - q[0] > 60:
                q.popleft()
            if len(q) >= AUTH_LIMIT_PER_MINUTE:
                return JSONResponse({"error": {"code": "rate_limited", "message": "Too many requests"}}, status_code=429)
            q.append(now)
        return await call_next(request)

    for r in (auth.router, households.router, care.router, doses.router, admin.router):
        app.include_router(r, prefix="/api/v1")

    @app.get("/health", tags=["ops"])
    def health():
        return {"status": "ok"}

    @app.get("/ready", tags=["ops"])
    def ready(db: Session = Depends(get_db)):
        db.execute(text("SELECT 1"))
        return {"status": "ready", "database": "ok"}

    return app


app = create_app()
