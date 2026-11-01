"""Reference-data seeding and the one sanctioned way to create the first Super Administrator."""

from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.core.permissions import DEFAULT_ROLE_PERMISSIONS, SUPER_ADMIN
from app.core.security import hash_password, password_problem
from app.models import RolePermission, User
from app.services import audit


def seed_reference_data(db: Session) -> None:
    """Insert default role permissions for roles that have none yet. Never overwrites admin changes."""
    existing_roles = {r for (r,) in db.query(RolePermission.role).distinct()}
    for role, perms in DEFAULT_ROLE_PERMISSIONS.items():
        if role in existing_roles:
            continue
        for p in perms:
            db.add(RolePermission(role=role, permission=p))
    db.flush()


def create_super_admin(db: Session, email: str, password: str, full_name: str) -> User:
    """Called only from the CLI (`python -m app.cli create-super-admin`). The password is supplied by the
    operator at run time; there is no default account and no HTTP route that can do this."""
    problem = password_problem(password)
    if problem:
        raise AppError(problem)
    email = email.strip().lower()
    if db.query(User).filter_by(email=email).first():
        raise AppError("A user with this email already exists")
    user = User(email=email, full_name=full_name, password_hash=hash_password(password), platform_role=SUPER_ADMIN)
    db.add(user)
    db.flush()
    audit.record(db, actor_id=None, action="user.bootstrap_super_admin", target_type="user", target_id=user.id)
    return user
