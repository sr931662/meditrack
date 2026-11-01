import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/providers.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../services/service_providers.dart';
import '../doses/dose_logic.dart';
import 'dose_widgets.dart';
import 'today_controller.dart';

/// Design "Medications" screen for seniors: today's doses with simple filters. Read-only: a senior
/// cannot add, edit or remove medicines (that stays with caregivers).
class DosesListScreen extends ConsumerStatefulWidget {
  const DosesListScreen({super.key});
  @override
  ConsumerState<DosesListScreen> createState() => _DosesListScreenState();
}

class _DosesListScreenState extends ConsumerState<DosesListScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = ref.watch(todayProvider);
    return ScreenScroll(
      onRefresh: () => syncEverything(ref.read),
      children: today.when(
        loading: () => const [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))],
        error: (e, _) => [ErrorBox(e, onRetry: () => ref.invalidate(todayProvider))],
        data: (s) {
          bool match(DoseView d, String f) {
            final ui = d.ui(now);
            return switch (f) {
              'Upcoming' => ui == DoseUi.upcoming || ui == DoseUi.snoozed || ui == DoseUi.due,
              'Reported' => ui == DoseUi.reportedTaken || ui == DoseUi.caregiverConfirmed,
              'Not confirmed' => ui == DoseUi.escalated || ui == DoseUi.due,
              _ => true,
            };
          }

          final list = s.doses.where((d) => match(d, _filter)).toList();
          return [
            PageTitle('Medications', sub: '${fmtDate(now)} · ${s.doses.where((d) => match(d, 'Reported')).length} of ${s.doses.length} reported'),
            SyncBanner(fromCache: s.fromCache, pending: s.pendingSync),
            ChipRow<String>(
              options: [for (final f in const ['All', 'Upcoming', 'Reported', 'Not confirmed']) (f, '$f ${s.doses.where((d) => match(d, f)).length}')],
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
            ),
            if (list.isEmpty)
              EmptyBox(_filter == 'Not confirmed' ? 'Nothing waiting' : 'No doses here', _filter == 'All' ? 'Your caregiver has not added any medicine yet.' : 'Try another filter.')
            else
              for (final d in list) DoseRow(dose: d, now: now, card: true, showTime: true, onTap: () => context.push(R.dose(d.key))),
          ];
        },
      ),
    );
  }
}
