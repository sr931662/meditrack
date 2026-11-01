# Role & Permission Matrix

Permissions live in the `role_permissions` table (seeded from `server/app/core/permissions.py`) and are
read on **every request**; nothing is trusted from the JWT except identity + session id. Household
roles are scoped by `memberships` (household_id, user_id, role); non-members receive **404**.

## Platform roles (`users.platform_role`)

| Permission | super_admin | ops_admin (default) | org_admin |
|---|:--:|:--:|:--:|
| users.read | ✅ | ✅ | – |
| users.create / users.update / users.disable | ✅ | – | – |
| roles.manage / permissions.manage | ✅ | – | – |
| households.read (metadata only, **no health data**) | ✅ | ✅ | – |
| audit_logs.read | ✅ | – | – |
| system_config.manage / integrations.manage | ✅ | – | – |
| system.monitor | ✅ | ✅ | – |
| support.access (time-boxed, read-only, reason required, audited) | ✅ | ✅ | – |

* The **super_admin** permission set is fixed (cannot be edited) so the platform cannot be locked out.
* Only a super admin can assign any platform role; assigning changes revokes that user's sessions.
* `ops_admin` permissions are editable by a super admin at runtime and take effect immediately.
* `org_admin` is **feature-gated** (`features.b2b_enabled=false`): it cannot be assigned, and has no permissions.
* No platform role sees medications/adherence without a support grant (`POST /admin/support-access`), which is read-only, expires (5–240 min) and writes an audit row.

## Household roles (`memberships.role`)

| Permission | owner | caregiver (per-person grants) | senior |
|---|:--:|:--:|:--:|
| households.read / households.manage | ✅ | – | – |
| members.manage (invite, permissions, remove) | ✅ | never | – |
| seniors.manage | ✅ | never | – |
| medications.read | ✅ | grantable | ✅ own only |
| medications.create / update / delete | ✅ | never | – |
| schedules.read | ✅ | grantable | ✅ own only |
| schedules.manage | ✅ | never | – |
| reminders.read | ✅ | grantable | ✅ own only |
| adherence.read (dashboard, dose history) | ✅ | grantable | – |
| verification.submit | ✅ | – | ✅ own only |
| verification.review (caregiver-confirm, request re-check) | ✅ | grantable | – |
| escalation.read / acknowledge / resolve | ✅ | grantable | – |
| escalation.manage (timings + contacts) | ✅ | never | – |
| doses.respond (acknowledge / taken / help / snooze, sync) | ✅ | – | ✅ own only |
| billing.manage, reports.read | ✅ | reports.read grantable | – |

"Grantable" set = `CAREGIVER_GRANTABLE` in code; attempts to grant anything else return 422.
A caregiver cannot edit their own permissions (needs `members.manage`).

## Enforcement points

* `get_auth` – signature, expiry, session not revoked, user active.
* `require_platform(perm)` – platform endpoints.
* `get_household_access` – membership lookup → `HouseholdAccess.require(perm)`.
* Every query is filtered by `household_id` (and `senior_id` for senior role) → no IDOR.
* Tests: `tests/test_rbac.py`, `test_verification_sync_admin.py` (cross-household, IDOR, caregiver limits, privilege escalation, immediate permission change, senior limits, admin limits, support grant).
