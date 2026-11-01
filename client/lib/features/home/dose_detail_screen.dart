import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../doses/dose_logic.dart';
import '../doses/dose_models.dart';
import '../auth/auth_controller.dart';
import 'dose_widgets.dart';
import 'today_controller.dart';

/// Design "Medication details": what it is, where it stands, and the few things a senior can do.
class DoseDetailScreen extends ConsumerWidget {
  const DoseDetailScreen({super.key, required this.doseKey});
  final String doseKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = ref.watch(todayProvider);
    final dose = today.value?.doses.where((d) => d.key == doseKey).firstOrNull;
    if (dose == null) {
      return PageFrame(title: 'Medication details', children: [
        if (today.isLoading) const Center(child: CircularProgressIndicator()) else const EmptyBox('Not available', 'This dose is no longer on today\'s list.'),
      ]);
    }
    final ui = dose.ui(now);
    final st = styleFor(ui);
    final m = dose.medication;
    final canAct = doseCanRespond(ui);

    Future<void> respond(String r) async {
      await performResponse(ref, dose, r);
      if (context.mounted) toast(context, responseLabels[r]!);
    }

    return PageFrame(
      title: 'Medication details',
      onRefresh: () => ref.read(todayProvider.notifier).refresh(),
      children: [
        if (today.value?.fromCache == true || dose.syncPending) SyncBanner(fromCache: today.value?.fromCache == true, pending: dose.syncPending ? 1 : 0),
        MtCard(
          radius: 26,
          padding: const EdgeInsets.all(20),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFF1F7FF)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PillIcon(m.appearance, size: 76),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.2)),
                if ((m.purpose ?? '').isNotEmpty) Text('For ${m.purpose!.toLowerCase()}', style: const TextStyle(fontSize: 16, color: Mt.muted)),
              ])),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusPill(doseUiLabel(ui), fg: st.fg, bg: st.bg, icon: st.icon, big: true),
              // Shown as its own, clearly separate fact: a box that looks right says nothing about swallowing.
              if (dose.packagingMatched) const StatusPill('Packaging matched', fg: Mt.blueText, bg: Mt.tintBlue, icon: Icons.inventory_2_outlined, big: true),
            ]),
            if (doseUiCaption(ui).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(doseUiCaption(ui), style: const TextStyle(fontSize: 14, color: Mt.muted2))),
            if (dose.packagingMatched) const Padding(padding: EdgeInsets.only(top: 6), child: Text('A packaging match only shows the box looks right. It does not show the medicine was taken.', style: TextStyle(fontSize: 14, color: Mt.muted2))),
            if (dose.helpRequested) const Padding(padding: EdgeInsets.only(top: 6), child: Text('You asked for help. Your caregiver has been told.', style: TextStyle(fontSize: 14, color: Mt.warn, fontWeight: FontWeight.w600))),
          ]),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: [
            for (final (k, v) in [('Reminder', fmtTime(dose.local)), ('Amount', m.quantity ?? m.dosageForm), ('When', m.prescribedInstructions ?? 'As scheduled'), ('Repeats', dose.schedule.weekdays.length == 7 ? 'Daily' : '${dose.schedule.weekdays.length} days a week')])
              MtCard(radius: 18, shadow: false, padding: const EdgeInsets.all(14), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(fontSize: 14, color: Mt.muted)), Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)])),
          ],
        ),
        if (canAct)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PrimaryButton("I've taken it", icon: Icons.check_rounded, onPressed: () async {
              final yes = await confirmDialog(context, title: 'Record ${m.title} as taken?', body: 'This tells your caregiver you took it. Only confirm if you have.', label: 'Yes, I took it');
              if (yes) await respond('taken');
            }),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlineBtn('Check box', icon: Icons.photo_camera_outlined, onPressed: () => context.push(R.verify(dose.key)))),
              const SizedBox(width: 10),
              Expanded(child: OutlineBtn('Remind later', icon: Icons.schedule_rounded, onPressed: () => respond('remind_later'))),
            ]),
            const SizedBox(height: 10),
            OutlineBtn('I need help', icon: Icons.support_agent_rounded, color: Mt.dangerDeep, border: Mt.dangerBorder, onPressed: () => _helpSheet(context, respond)),
          ]),
        _History(dose: dose),
      ],
    );
  }

  void _helpSheet(BuildContext context, Future<void> Function(String) respond) {
    showMtSheet(context, title: 'Get help', builder: (c) {
      Widget opt(String label, String r, IconData icon) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlineBtn(label, icon: icon, onPressed: () async {
              Navigator.pop(c);
              await respond(r);
            }),
          );
      return Column(children: [
        const Align(alignment: Alignment.centerLeft, child: Text('Tell your caregiver what is wrong. They will be contacted right away.', style: TextStyle(fontSize: 15, color: Mt.muted2))),
        const SizedBox(height: 14),
        opt('I need help', 'help', Icons.support_agent_rounded),
        opt('I cannot find my medicine', 'cannot_find', Icons.search_rounded),
        opt('I am not feeling well', 'unwell', Icons.sentiment_dissatisfied_outlined),
        const Text('In an emergency, call your local emergency number.', style: TextStyle(fontSize: 14, color: Mt.muted)),
      ]);
    });
  }
}

class _History extends ConsumerWidget {
  const _History({required this.dose});
  final DoseView dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final id = dose.server?.id;
    return MtCard(
      radius: 22,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 8), child: Text('History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        if (id == null || auth is! Authenticated)
          const Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 16), child: Text('The full history appears here once this phone has synced.', style: TextStyle(fontSize: 15, color: Mt.muted)))
        else
          FutureBuilder<DoseEvent>(
            key: ValueKey('${id}_${dose.syncPending}_${dose.reportedTakenAt}'),
            future: ref.read(doseRepositoryProvider).event(auth.ctx.householdId!, id),
            builder: (c, snap) {
              if (!snap.hasData) return Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 16), child: Text(snap.hasError ? 'History is unavailable offline.' : 'Loading…', style: const TextStyle(color: Mt.muted, fontSize: 15)));
              final items = snap.data!.timeline.reversed.toList();
              return Column(children: [for (final t in items) _Row(t)]);
            },
          ),
      ]),
    );
  }
}

String timelineText(TimelineEntry t) => switch (t.type) {
      'reminder_sent' => 'Reminder sent',
      'reminder_repeated' => 'Reminder repeated',
      'acknowledged' => 'You acknowledged the reminder',
      'user_reported_taken' => 'You reported it taken (self-reported)',
      'snoozed' => 'You asked to be reminded again',
      'help_requested' => 'You asked for help',
      'verification_prompt' => 'Asked to check the medicine box',
      'verification_requested' => 'Your caregiver asked you to check the box',
      'packaging_verification' => switch (t.data['status']) { 'match' => 'Packaging matched (not proof it was taken)', 'uncertain' => 'Packaging check was unclear', _ => 'Packaging did not match' },
      'escalation_triggered' => 'Your caregiver was alerted',
      'escalation_acknowledged' => 'Your caregiver saw the alert',
      'escalation_resolved' => 'Your caregiver reviewed this dose',
      'caregiver_confirmed' => t.data['status'] == 'taken' ? 'Caregiver confirmed it was taken' : 'Caregiver recorded it as not taken',
      'caregiver_note' => 'Caregiver added a note',
      'delivery_sent' => 'Alert sent via ${t.data['channel']}',
      'delivery_failed' => 'An alert could not be sent (${t.data['channel']}); retrying',
      'late_response' => 'Late response recorded',
      _ => t.type.replaceAll('_', ' '),
    };

class _Row extends StatelessWidget {
  const _Row(this.t);
  final TimelineEntry t;
  @override
  Widget build(BuildContext context) {
    final warn = t.type.contains('escalation') || t.type.contains('failed') || t.type.contains('help');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: warn ? Mt.orange : t.type.contains('caregiver') || t.type.contains('reported') ? Mt.blue : const Color(0xFFB9C7DA))),
        const SizedBox(width: 12),
        Expanded(child: Text(timelineText(t), style: const TextStyle(fontSize: 15))),
        Text(fmtTime(t.at), style: const TextStyle(fontSize: 14, color: Mt.muted)),
      ]),
    );
  }
}
