import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/login_screen.dart' show Wordmark;
import '../doses/dose_models.dart';
import '../household/care_providers.dart';
import '../home/dose_detail_screen.dart' show timelineText;
import '../shell/nav.dart';

const _cReported = Mt.blue;
const _cConfirmed = Mt.ok;
const _cUnverified = Mt.orange;
const _cNotTaken = Color(0xFFDC4F40);

/// Caregiver dashboard (design "Analytics" + safety status). Self-report, packaging match and caregiver
/// confirmation are always separate numbers; nothing sums them into a single "taken".
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    final f = ref.watch(dashFilterProvider);
    final dash = ref.watch(dashboardProvider);
    final trend = ref.watch(trendProvider);
    final seniors = ref.watch(seniorsProvider).value ?? [];
    final meds = ref.watch(medicationsProvider).value ?? [];
    final ctrl = ref.read(dashFilterProvider.notifier);

    Future<void> refresh() async {
      ref.invalidate(dashboardProvider);
      ref.invalidate(trendProvider);
      ref.invalidate(escalationsProvider);
    }

    return ScreenScroll(
      onRefresh: refresh,
      children: [
        Row(children: [
          const Wordmark(),
          const Spacer(),
          Semantics(button: true, label: 'Notifications', child: GestureDetector(onTap: () => context.push(R.notifications), child: Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE6EEF9))), child: const Icon(Icons.notifications_none_rounded, size: 26)))),
          const SizedBox(width: 10),
          GestureDetector(onTap: () => ref.read(shellTabProvider.notifier).set(4), child: Avatar(auth.me.initials)),
        ]),
        PageTitle('Overview', sub: auth.ctx.membership?.householdName),
        _DateBar(day: f.day, onChange: (d) => ctrl.set(f.copyWith(day: d))),
        if (seniors.length > 1) ChipRow<String?>(options: [(null, 'Everyone'), for (final s in seniors) (s.id, s.fullName.split(' ').first)], value: f.seniorId, onChanged: (v) => ctrl.set(f.copyWith(seniorId: v))),
        if (meds.length > 1) ChipRow<String?>(options: [(null, 'All medicines'), for (final m in meds) (m.id, m.name)], value: f.medicationId, onChanged: (v) => ctrl.set(f.copyWith(medicationId: v))),
        ...dash.when(
          loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [ErrorBox(e, onRetry: refresh)],
          data: (d) => [
            _SafetyCard(d: d, onTap: () => ref.read(shellTabProvider.notifier).set(2)),
            _Stats(d: d),
            _TrendCard(trend: trend, range: f.range, onRange: (r) => ctrl.set(f.copyWith(range: r))),
            _ByMedication(d: d),
            _Delivery(d: d),
            _Recent(d: d),
          ],
        ),
      ],
    );
  }
}

class _DateBar extends StatelessWidget {
  const _DateBar({required this.day, required this.onChange});
  final DateTime day;
  final ValueChanged<DateTime> onChange;
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
    return Row(children: [
      IconButton(tooltip: 'Previous day', iconSize: 28, constraints: const BoxConstraints(minWidth: 48, minHeight: 48), onPressed: () => onChange(day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left_rounded)),
      Expanded(
        child: GestureDetector(
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2024), lastDate: today);
            if (p != null) onChange(DateTime(p.year, p.month, p.day));
          },
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Mt.inputBorder)),
            child: Text(isToday ? 'Today · ${fmtDate(day)}' : fmtDate(day), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      IconButton(tooltip: 'Next day', iconSize: 28, constraints: const BoxConstraints(minWidth: 48, minHeight: 48), onPressed: isToday ? null : () => onChange(day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right_rounded)),
    ]);
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.d, required this.onTap});
  final Dashboard d;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final act = d.pendingInterventions > 0;
    final title = act ? 'Action needed' : 'All good';
    final text = act ? '${d.pendingInterventions} alert${d.pendingInterventions == 1 ? '' : 's'} need a caregiver. ${d.activeEscalations} not yet acknowledged.' : 'No open alerts.';
    return Semantics(
      button: true,
      label: 'Safety status: $title. $text',
      child: GestureDetector(
        onTap: onTap,
        child: MtCard(
          padding: const EdgeInsets.all(16),
          color: act ? const Color(0xFFFFF8F7) : Colors.white,
          border: act ? Mt.dangerBorder : Mt.border,
          child: ExcludeSemantics(
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: act ? Mt.dangerBg : const Color(0xFFE3F5EE), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.shield_outlined, color: act ? Mt.dangerDeep : Mt.ok)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: act ? Mt.dangerDeep : Mt.ok)), Text(text, style: const TextStyle(fontSize: 14, color: Mt.muted))])),
              const Icon(Icons.chevron_right_rounded, color: Mt.faint),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, {this.sub});
  final String label;
  final int value;
  final Color color;
  final String? sub;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        child: MtCard(
          radius: 18,
          shadow: false,
          padding: const EdgeInsets.all(14),
          child: ExcludeSemantics(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))), const SizedBox(width: 8), Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: Mt.muted)))]),
              const SizedBox(height: 4),
              Text('$value', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1)),
              if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12, color: Mt.muted)),
            ]),
          ),
        ),
      );
}

class _Stats extends StatelessWidget {
  const _Stats({required this.d});
  final Dashboard d;
  @override
  Widget build(BuildContext context) => Column(children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.75,
          children: [
            _Stat('Scheduled doses', d.scheduled, Mt.faint, sub: '${d.totalSeniors} ${d.totalSeniors == 1 ? 'senior' : 'seniors'} · ${d.remindersSent} reminders sent'),
            _Stat('Reported by senior', d.userReported, _cReported, sub: 'Self-reported only'),
            _Stat('Packaging matched', d.packagingMatched, Mt.blueLight, sub: 'Box looked right'),
            _Stat('Confirmed by caregiver', d.caregiverConfirmed, _cConfirmed, sub: 'Independently checked'),
            _Stat('Not confirmed', d.unverified, _cUnverified, sub: 'Waiting or alerted'),
            _Stat('Open alerts', d.pendingInterventions, _cNotTaken, sub: '${d.resolvedEscalations} resolved'),
          ],
        ),
        const SizedBox(height: 10),
        const Text('A packaging match and a senior’s report are not proof the medicine was swallowed. Only “Confirmed by caregiver” has been checked by a person.', style: TextStyle(fontSize: 13, color: Mt.muted, height: 1.4)),
      ]);
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend, required this.range, required this.onRange});
  final AsyncValue<List<Map<String, dynamic>>> trend;
  final int range;
  final ValueChanged<int> onRange;

  @override
  Widget build(BuildContext context) => MtCard(
        padding: const EdgeInsets.all(18),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFF1F7FF)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegControl<int>(semanticLabel: 'Date range', options: const [(7, '7 days'), (14, '14 days'), (30, '30 days')], value: range, onChanged: onRange),
          const SizedBox(height: 16),
          trend.when(
            loading: () => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorBox(e),
            data: (days) {
              final totalScheduled = days.fold<int>(0, (a, d) => a + (d['scheduled'] as int));
              final cap = days.fold<int>(3, (a, d) => (d['scheduled'] as int) > a ? d['scheduled'] as int : a);
              final reported = days.fold<int>(0, (a, d) => a + (d['user_reported_taken'] as int));
              final confirmed = days.fold<int>(0, (a, d) => a + (d['caregiver_confirmed'] as int));
              final unv = days.fold<int>(0, (a, d) => a + (d['unverified'] as int));
              final nt = days.fold<int>(0, (a, d) => a + (d['caregiver_not_taken'] as int));
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$totalScheduled scheduled doses', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 4, children: [_Key(_cReported, 'Reported $reported'), _Key(_cConfirmed, 'Confirmed $confirmed'), _Key(_cUnverified, 'Not confirmed $unv'), _Key(_cNotTaken, 'Recorded not taken $nt')]),
                const SizedBox(height: 14),
                Semantics(
                  label: 'Bar chart of daily doses over $range days: $reported reported by senior, $confirmed confirmed by caregiver, $unv not confirmed, $nt recorded as not taken',
                  child: ExcludeSemantics(
                    child: SizedBox(
                      height: 150,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (var i = 0; i < days.length; i++)
                          Expanded(
                            child: Tooltip(
                              message: '${days[i]['date']}: ${days[i]['user_reported_taken']} reported, ${days[i]['caregiver_confirmed']} confirmed, ${days[i]['unverified']} not confirmed',
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: range == 30 ? 1.5 : range == 14 ? 2.5 : 5),
                                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  SizedBox(
                                    height: 120,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(range == 30 ? 3 : 8),
                                      child: Container(
                                        color: Mt.track,
                                        child: Column(verticalDirection: VerticalDirection.up, children: [
                                          for (final (k, c) in [('caregiver_confirmed', _cConfirmed), ('user_reported_taken', _cReported), ('unverified', _cUnverified), ('caregiver_not_taken', _cNotTaken)])
                                            if ((days[i][k] as int) > 0) Expanded(flex: days[i][k] as int, child: Container(margin: const EdgeInsets.only(top: 1), color: c)),
                                          Expanded(flex: ((cap - (days[i]['scheduled'] as int)).clamp(0, 99)) + _rest(days[i]), child: const SizedBox()),
                                        ]),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(height: 16, child: Text(_label(days, i, range), style: TextStyle(fontSize: 12, color: i == days.length - 1 ? Mt.blueText : Mt.muted, fontWeight: i == days.length - 1 ? FontWeight.w700 : FontWeight.w500), maxLines: 1, overflow: TextOverflow.visible)),
                                ]),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ]),
      );

  /// Scheduled doses with no recorded evidence yet, drawn as empty space in the bar.
  static int _rest(Map<String, dynamic> d) {
    final used = (d['caregiver_confirmed'] as int) + (d['user_reported_taken'] as int) + (d['unverified'] as int) + (d['caregiver_not_taken'] as int);
    return ((d['scheduled'] as int) - used).clamp(0, 99);
  }

  static String _label(List<Map<String, dynamic>> days, int i, int range) {
    final dt = DateTime.parse(days[i]['date'] as String);
    if (i == days.length - 1) return 'Today';
    if (range == 7) return weekdayShort(dt);
    return (days.length - 1 - i) % (range == 14 ? 3 : 7) == 0 ? '${dt.day}' : '';
  }
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 14, color: Mt.ink2))]);
}

class _ByMedication extends StatelessWidget {
  const _ByMedication({required this.d});
  final Dashboard d;
  @override
  Widget build(BuildContext context) => MtCard(
        radius: 22,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 6), child: Text('By medication', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          if (d.byMedication.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(18, 4, 18, 16), child: Text('No doses scheduled for this day.', style: TextStyle(color: Mt.muted))),
          for (final m in d.byMedication)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text(m.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), Text('${m.scheduled} scheduled', style: const TextStyle(fontSize: 14, color: Mt.muted))]),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(height: 8, child: Row(children: [
                  if (m.confirmed > 0) Expanded(flex: m.confirmed, child: Container(color: _cConfirmed)),
                  if (m.reported > 0) Expanded(flex: m.reported, child: Container(color: _cReported)),
                  if (m.unverified > 0) Expanded(flex: m.unverified, child: Container(color: _cUnverified)),
                  Expanded(flex: (m.scheduled - m.confirmed - m.reported - m.unverified).clamp(0, 99) + (m.scheduled == 0 ? 1 : 0), child: Container(color: Mt.track)),
                ]))),
                const SizedBox(height: 6),
                Text('Reported ${m.reported} · Confirmed ${m.confirmed} · Not confirmed ${m.unverified} · Packaging matched ${m.matched}', style: const TextStyle(fontSize: 14, color: Mt.muted)),
              ]),
            ),
        ]),
      );
}

class _Delivery extends StatelessWidget {
  const _Delivery({required this.d});
  final Dashboard d;
  @override
  Widget build(BuildContext context) {
    if (d.deliveryStatus.isEmpty) return const SizedBox.shrink();
    return MtCard(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Alert delivery', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('“Sent” means the messaging provider accepted it, not that it was read.', style: TextStyle(fontSize: 13, color: Mt.muted)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in d.deliveryStatus.entries)
            StatusPill('${e.key[0].toUpperCase()}${e.key.substring(1)} ${e.value}', fg: e.key == 'failed' ? Mt.dangerDeep : e.key == 'delivered' ? Mt.okDeep : Mt.blueText, bg: e.key == 'failed' ? Mt.dangerBg : e.key == 'delivered' ? Mt.okBg : Mt.tintBlue),
        ]),
      ]),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.d});
  final Dashboard d;
  @override
  Widget build(BuildContext context) => MtCard(
        radius: 22,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 8), child: Text('Recent activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          if (d.recent.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 16), child: Text('Nothing has happened yet today.', style: TextStyle(color: Mt.muted))),
          for (final t in d.recent.take(10))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: t.type.contains('escalation') || t.type.contains('failed') ? Mt.orange : Mt.blue)),
                const SizedBox(width: 12),
                Expanded(child: Text(timelineText(t).replaceAll('You ', 'Senior ').replaceAll('Your caregiver', 'A caregiver'), style: const TextStyle(fontSize: 15))),
                Text(fmtTime(t.at), style: const TextStyle(fontSize: 14, color: Mt.muted)),
              ]),
            ),
        ]),
      );
}
