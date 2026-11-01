"""Central permission registry. The role->permission mapping lives in the database (seeded from here)
so administrators can change it at runtime; every check reads the database, never the token."""

# ---- platform-level -----------------------------------------------------------------------------
PLATFORM_PERMISSIONS = [
    "users.read",
    "users.create",
    "users.update",
    "users.disable",
    "roles.manage",
    "permissions.manage",
    "households.read",
    "households.manage",
    "audit_logs.read",
    "integrations.manage",
    "system_config.manage",
    "system.monitor",
    "support.access",
    "subscriptions.manage",
]

# ---- household-level ----------------------------------------------------------------------------
HOUSEHOLD_PERMISSIONS = [
    "households.read",
    "households.manage",
    "members.manage",
    "seniors.manage",
    "medications.read",
    "medications.create",
    "medications.update",
    "medications.delete",
    "schedules.read",
    "schedules.manage",
    "reminders.read",
    "reminders.manage",
    "adherence.read",
    "verification.read",
    "verification.review",
    "verification.submit",
    "escalation.read",
    "escalation.acknowledge",
    "escalation.resolve",
    "escalation.manage",
    "doses.respond",
    "reports.read",
    "billing.manage",
]

ALL_PERMISSIONS = sorted(set(PLATFORM_PERMISSIONS) | set(HOUSEHOLD_PERMISSIONS))

# Permissions an owner may hand to a secondary caregiver. Ownership/billing/member management never.
CAREGIVER_GRANTABLE = {
    "medications.read",
    "schedules.read",
    "reminders.read",
    "adherence.read",
    "verification.read",
    "verification.review",
    "escalation.read",
    "escalation.acknowledge",
    "escalation.resolve",
    "reports.read",
}

PLATFORM_ROLES = ("super_admin", "ops_admin", "org_admin")
HOUSEHOLD_ROLES = ("owner", "caregiver", "senior")
SUPER_ADMIN = "super_admin"
ORG_ADMIN = "org_admin"  # feature-gated (B2B) until `features.b2b_enabled` is switched on

DEFAULT_ROLE_PERMISSIONS: dict[str, list[str]] = {
    "super_admin": PLATFORM_PERMISSIONS,
    "ops_admin": ["users.read", "households.read", "system.monitor", "support.access"],
    "org_admin": [],  # populated when B2B is activated
    "owner": HOUSEHOLD_PERMISSIONS,
    "caregiver": [],  # per-member grants, validated against CAREGIVER_GRANTABLE
    "senior": ["medications.read", "schedules.read", "reminders.read", "doses.respond", "verification.submit"],
}

# What support staff may do inside a household under a time-boxed, audited grant. Read-only.
SUPPORT_READ_PERMISSIONS = {
    "households.read",
    "medications.read",
    "schedules.read",
    "reminders.read",
    "adherence.read",
    "verification.read",
    "escalation.read",
}
