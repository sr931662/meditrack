import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../doses/dose_models.dart';
import '../household/care_providers.dart';

/// Caregiver "Alerts" tab: escalations that need a person, newest first.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});
  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(escalationsProvider);
    return ScreenScroll(
      onRefresh: () async => ref.refresh(escalationsProvider.future),
      children: [
        const PageTitle('Alerts', sub: 'Doses that were not confirmed in time'),
        ...all.when(
          loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [ErrorBox(e, onRetry: () => ref.invalidate(escalationsProvider))],
          data: (list) {
            bool match(Escalation e, String f) => f == 'all' || (f == 'open' ? e.status != 'resolved' : e.status == 'resolved');
            final shown = list.where((e) => match(e, _filter)).toList();
            return [
              ChipRow<String>(options: [('open', 'Needs attention ${list.where((e) => match(e, 'open')).length}'), ('resolved', 'Resolved ${list.where((e) => match(e, 'resolved')).length}'), ('all', 'All')], value: _filter, onChanged: (v) => setState(() => _filter = v)),
              if (shown.isEmpty) EmptyBox(_filter == 'open' ? 'No open alerts' : 'Nothing here', 'Alerts appear when a dose is not confirmed in time, or when a senior asks for help.')
              else for (final e in shown) _AlertCard(e),
            ];
          },
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard(this.e);
  final Escalation e;
  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (e.status) {
      'open' => (e.isHelpRequest ? 'Help requested' : 'Needs attention', Mt.dangerDeep, Mt.dangerBg),
      'acknowledged' => ('Acknowledged', Mt.warn, Mt.warnBg),
      _ => ('Resolved', Mt.okDeep, Mt.okBg),
    };
    return MtCard(
      radius: 20,
      color: e.status == 'open' ? const Color(0xFFFFF8F7) : Colors.white,
      border: e.status == 'open' ? Mt.dangerBorder : Mt.border,
      child: Tappable(
        semanticLabel: '${e.seniorName}, ${e.medication}, $label',
        onTap: () => context.push(R.alert(e.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatusPill(label, fg: fg, bg: bg),
              const SizedBox(height: 8),
              Text(e.seniorName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(e.medication, style: const TextStyle(fontSize: 15, color: Mt.ink2)),
              Text('Due ${e.scheduledFor == null ? '' : fmtTime(e.scheduledFor!)} · alerted ${fmtTime(e.triggeredAt)}', style: const TextStyle(fontSize: 14, color: Mt.muted)),
              if (e.deliveries.any((d) => d.status == 'failed')) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Some notifications failed to send. Please call directly.', style: TextStyle(fontSize: 13, color: Mt.dangerDeep, fontWeight: FontWeight.w600))),
            ])),
            const Icon(Icons.chevron_right_rounded, color: Mt.faint),
          ]),
        ),
      ),
    );
  }
}
