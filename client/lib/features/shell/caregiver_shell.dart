import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../analytics/overview_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/login_screen.dart';
import '../escalation/alerts_screen.dart';
import '../household/people_screen.dart';
import '../medications/medications_screen.dart';
import '../profile/profile_screen.dart';
import 'nav.dart';

/// Tabs are chosen from the caregiver's granted permissions (convenience only; the API enforces them).
class CaregiverShell extends ConsumerWidget {
  const CaregiverShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    if (auth.ctx.membership == null) return const _CreateHousehold();
    final c = auth.ctx;
    final tabs = <(NavItem, Widget)>[
      if (c.can('adherence.read')) (const NavItem('Overview', Icons.dashboard_outlined, Icons.dashboard_rounded), const OverviewScreen()),
      if (c.can('medications.read')) (const NavItem('Medicines', Icons.medication_outlined, Icons.medication_rounded), const MedicationsScreen()),
      if (c.can('escalation.read')) (const NavItem('Alerts', Icons.notifications_none_rounded, Icons.notifications_rounded), const AlertsScreen()),
      if (c.can('members.manage') || c.can('seniors.manage')) (const NavItem('People', Icons.group_outlined, Icons.group_rounded), const PeopleScreen()),
      (const NavItem('Profile', Icons.person_outline_rounded, Icons.person_rounded), const ProfileScreen()),
    ];
    return TabShell(items: [for (final t in tabs) t.$1], pages: [for (final t in tabs) t.$2]);
  }
}

/// First run for a new caregiver account: create the household that everything else hangs off.
class _CreateHousehold extends ConsumerStatefulWidget {
  const _CreateHousehold();
  @override
  ConsumerState<_CreateHousehold> createState() => _CreateHouseholdState();
}

class _CreateHouseholdState extends ConsumerState<_CreateHousehold> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give the household a name.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careRepositoryProvider).createHousehold(_name.text.trim());
      await ref.read(authControllerProvider.notifier).reload();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PageBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Center(child: Wordmark(size: 30)),
                    const SizedBox(height: 24),
                    MtCard(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Set up your household', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('A household is the family you care for. You will add the person who takes medicine, their medicines and who should be alerted next.', style: TextStyle(fontSize: 15, color: Mt.muted, height: 1.4)),
                      const SizedBox(height: 16),
                      LabeledField(label: 'Household name', controller: _name, hint: 'e.g. Lee family'),
                      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Mt.dangerDeep))),
                      const SizedBox(height: 16),
                      PrimaryButton('Create household', loading: _busy, onPressed: _create),
                      TextAction('Sign out', color: Mt.muted2, onPressed: () => ref.read(authControllerProvider.notifier).logout()),
                    ])),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
