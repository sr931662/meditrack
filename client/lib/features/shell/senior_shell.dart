import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/service_providers.dart';
import '../home/doses_list_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import 'nav.dart';

/// Three tabs only. Seniors never see dashboards, billing or configuration.
class SeniorShell extends ConsumerStatefulWidget {
  const SeniorShell({super.key});
  @override
  ConsumerState<SeniorShell> createState() => _SeniorShellState();
}

class _SeniorShellState extends ConsumerState<SeniorShell> {
  @override
  void initState() {
    super.initState();
    // Ask for the permissions that reminders depend on, once the screen is up.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(reminderServiceProvider).requestPermissions();
      await syncEverything(ref.read);
    });
  }

  @override
  Widget build(BuildContext context) => TabShell(
        items: const [
          NavItem('Home', Icons.home_outlined, Icons.home_rounded),
          NavItem('Medicines', Icons.medication_outlined, Icons.medication_rounded),
          NavItem('Profile', Icons.person_outline_rounded, Icons.person_rounded),
        ],
        pages: [
          SeniorHomeScreen(onOpenProfile: () => ref.read(shellTabProvider.notifier).set(2)),
          const DosesListScreen(),
          const ProfileScreen(),
        ],
      );
}
