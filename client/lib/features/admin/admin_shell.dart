import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../profile/profile_screen.dart';
import '../shell/nav.dart';
import 'audit_screen.dart';
import 'roles_screen.dart';
import 'system_screen.dart';
import 'users_screen.dart';

/// Platform administration. Tabs follow the admin's permissions; the API enforces them regardless.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    final p = auth.me.platformPermissions;
    final tabs = <(NavItem, Widget)>[
      if (p.contains('users.read')) (const NavItem('Users', Icons.people_outline_rounded, Icons.people_rounded), const UsersScreen()),
      if (p.contains('roles.manage')) (const NavItem('Roles', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings_rounded), const RolesScreen()),
      if (p.contains('audit_logs.read')) (const NavItem('Audit', Icons.fact_check_outlined, Icons.fact_check_rounded), const AuditScreen()),
      if (p.contains('system_config.manage') || p.contains('system.monitor')) (const NavItem('System', Icons.tune_outlined, Icons.tune_rounded), const SystemScreen()),
      (const NavItem('Profile', Icons.person_outline_rounded, Icons.person_rounded), const ProfileScreen()),
    ];
    return TabShell(items: [for (final t in tabs) t.$1], pages: [for (final t in tabs) t.$2]);
  }
}
