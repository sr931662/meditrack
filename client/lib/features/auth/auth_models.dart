enum AppMode { admin, caregiver, senior }

class Membership {
  Membership({required this.householdId, required this.householdName, required this.role, required this.permissions, this.seniorId});

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        householdId: j['household_id'],
        householdName: j['household_name'],
        role: j['role'],
        permissions: Set<String>.from(j['permissions'] ?? const []),
        seniorId: j['senior_id'],
      );

  final String householdId;
  final String householdName;
  final String role; // owner | caregiver | senior
  final Set<String> permissions;
  final String? seniorId;

  Map<String, dynamic> toJson() => {
        'household_id': householdId,
        'household_name': householdName,
        'role': role,
        'permissions': permissions.toList(),
        'senior_id': seniorId,
      };
}

class Me {
  Me({required this.id, required this.email, required this.fullName, this.platformRole, required this.platformPermissions, required this.memberships});

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        id: j['id'],
        email: j['email'],
        fullName: j['full_name'],
        platformRole: j['platform_role'],
        platformPermissions: Set<String>.from(j['platform_permissions'] ?? const []),
        memberships: [for (final m in (j['memberships'] as List? ?? const [])) Membership.fromJson(m)],
      );

  final String id;
  final String email;
  final String fullName;
  final String? platformRole;
  final Set<String> platformPermissions;
  final List<Membership> memberships;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'platform_role': platformRole,
        'platform_permissions': platformPermissions.toList(),
        'memberships': [for (final m in memberships) m.toJson()],
      };

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

/// Which experience the signed-in user gets. The server remains the authority on every permission;
/// this only decides which screens to show.
class ActiveContext {
  ActiveContext(this.mode, {this.membership});
  final AppMode mode;
  final Membership? membership;

  String? get householdId => membership?.householdId;
  String? get seniorId => membership?.seniorId;
  bool can(String permission) => membership?.permissions.contains(permission) ?? false;
}

ActiveContext resolveContext(Me me, {String? preferHousehold}) {
  if (me.platformRole != null) return ActiveContext(AppMode.admin);
  final ms = me.memberships;
  if (ms.isEmpty) return ActiveContext(AppMode.caregiver); // new account: create a household first
  final m = ms.firstWhere((x) => x.householdId == preferHousehold, orElse: () => ms.first);
  return ActiveContext(m.role == 'senior' ? AppMode.senior : AppMode.caregiver, membership: m);
}
