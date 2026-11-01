"""Operator commands. The ONLY way to create the first super administrator:

    python -m app.cli create-super-admin --email you@example.com --name "Your Name"

The password is read from the MEDTRACK_BOOTSTRAP_PASSWORD environment variable or prompted for
interactively. There is no default account and no HTTP endpoint that can mint a super admin.
"""

import argparse
import getpass
import os
import sys

from app.core.db import session_factory
from app.core.errors import AppError
from app.services import bootstrap


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="app.cli")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create-super-admin")
    c.add_argument("--email", required=True)
    c.add_argument("--name", required=True)
    sub.add_parser("seed")
    sub.add_parser("seed-demo")
    args = p.parse_args(argv)

    db = session_factory()()
    try:
        bootstrap.seed_reference_data(db)
        if args.cmd == "create-super-admin":
            password = os.environ.get("MEDTRACK_BOOTSTRAP_PASSWORD") or getpass.getpass("Password: ")
            user = bootstrap.create_super_admin(db, args.email, password, args.name)
            print(f"Created super administrator {user.email}")
        if args.cmd == "seed-demo":
            from app.core.config import get_settings
            from app.services import demo

            demo.seed_demo(db, get_settings().demo_password)
            print("Demo data ready (see docs/DEMO_GUIDE.md for the accounts)")
        db.commit()
    except AppError as exc:
        db.rollback()
        print(f"error: {exc.message}", file=sys.stderr)
        return 1
    finally:
        db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
