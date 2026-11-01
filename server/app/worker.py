"""Reminder / escalation worker. Run as its own process (separate from the API):

    python -m app.worker

It is stateless: all scheduling state lives in the database `jobs` table, so it can be restarted or
scaled to several replicas at any time (jobs are claimed with FOR UPDATE SKIP LOCKED on PostgreSQL).
"""

import logging
import signal
import threading
import time

from app.core.db import session_factory, utcnow
from app.integrations.registry import get_providers
from app.services import bootstrap, engine

log = logging.getLogger("medtrack.worker")
TICK_SECONDS = 15
MATERIALIZE_EVERY_SECONDS = 300


def tick(materialize: bool) -> dict:
    db = session_factory()()
    try:
        now = utcnow()
        if materialize:
            engine.materialize(db, now)
            db.commit()
        stats = engine.process_due(db, now, get_providers())
        db.commit()
        return stats
    except Exception:
        db.rollback()
        log.exception("worker tick failed")
        return {}
    finally:
        db.close()


def run_loop(stop: threading.Event) -> None:
    """Tick until `stop` is set. Shared by the standalone worker and the API's embedded worker."""
    db = session_factory()()
    try:
        bootstrap.seed_reference_data(db)
        db.commit()
    finally:
        db.close()
    last_mat = float("-inf")
    while not stop.is_set():
        do_mat = time.monotonic() - last_mat >= MATERIALIZE_EVERY_SECONDS
        stats = tick(do_mat)
        if do_mat:
            last_mat = time.monotonic()
        if stats.get("jobs") or stats.get("retried"):
            log.info("tick: %s", stats)
        stop.wait(TICK_SECONDS)


def start_embedded() -> tuple[threading.Thread, threading.Event]:
    stop = threading.Event()
    t = threading.Thread(target=run_loop, args=(stop,), name="medtrack-worker", daemon=True)
    t.start()
    return t, stop


def run() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    stop = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    run_loop(stop)


if __name__ == "__main__":
    run()
