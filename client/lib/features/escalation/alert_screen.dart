import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../auth/auth_controller.dart';
import '../doses/dose_models.dart';
import '../home/dose_detail_screen.dart' show timelineText;
import '../household/care_providers.dart';

final _alertProvider = FutureProvider.autoDispose.family<(Escalation, DoseEvent), String>((ref, id) async {
  final auth = ref.watch(authControllerProvider) as Authenticated;
  return ref.read(doseRepositoryProvider).escalation(auth.ctx.householdId!, id);
});

const _outcomes = {
  'taken_confirmed': 'I confirmed they took it',
  'not_taken_confirmed': 'I confirmed they did not take it',
  'no_action_needed': 'No action needed',
  'unreachable_follow_up': "Couldn't reach them. Will follow up",
};

/// Design "Caregiver alert": REMIND -> VERIFY -> ESCALATE -> RESOLVE. Every step is recorded server-side.
class AlertScreen extends ConsumerWidget {
  const AlertScreen({super.key, required this.escalationId});
  final String escalationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    final hid = auth.ctx.householdId!;
    final data = ref.watch(_alertProvider(escalationId));
    final repo = ref.read(doseRepositoryProvider);

    Future<void> run(Future<void> Function() action, String ok) async {
      try {
        await action();
        ref.invalidate(_alertProvider(escalationId));
        ref.invalidate(escalationsProvider);
        ref.invalidate(dashboardProvider);
        if (context.mounted) toast(context, ok);
      } catch (e) {
        if (context.mounted) toast(context, errorText(e));
      }
    }

    return PageFrame(
      title: 'Caregiver alert',
      onRefresh: () async => ref.refresh(_alertProvider(escalationId).future),
      children: data.when(
        loading: () => const [Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))],
        error: (e, _) => [ErrorBox(e, onRetry: () => ref.invalidate(_alertProvider(escalationId)))],
        data: (pair) {
          final (esc, ev) = pair;
          final resolved = esc.status == 'resolved';
          final ack = esc.status != 'open';
          final since = (resolved ? esc.resolvedAt! : DateTime.now()).difference(esc.scheduledFor ?? esc.triggeredAt);
          final (stageLabel, title, fg, tile, heroBg, heroBorder, icon) = switch (esc.status) {
            'open' => (esc.isHelpRequest ? 'HELP REQUESTED' : 'ESCALATED', esc.isHelpRequest ? '${esc.seniorName} asked for help' : 'Dose not confirmed', Mt.dangerDeep, Mt.dangerBg, const Color(0xFFFFF4F2), Mt.dangerBorder, Icons.warning_amber_rounded),
            'acknowledged' => ('ACKNOWLEDGED', 'Check in with ${esc.seniorName.split(' ').first}', Mt.warn, Mt.warnBg, const Color(0xFFFFF9EE), Mt.warnBorder, Icons.schedule_rounded),
            _ => ('RESOLVED', 'Case closed', Mt.okDeep, const Color(0xFFE3F5EE), const Color(0xFFF0FAF6), Mt.okBorder, Icons.check_rounded),
          };
          return [
            MtCard(
              radius: 26,
              padding: const EdgeInsets.all(20),
              color: heroBg,
              border: heroBorder,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: fg, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(stageLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg, letterSpacing: .8)), Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))])),
                ]),
                const SizedBox(height: 14),
                Text(
                  resolved
                      ? '${esc.medication}. ${_outcomes[esc.outcome] ?? ''}.'
                      : '${esc.seniorName} hasn\'t confirmed ${esc.medication}${esc.scheduledFor == null ? '' : ', due ${fmtTime(esc.scheduledFor!)}'}. We can\'t tell whether it was taken, so please check in gently.',
                  style: const TextStyle(fontSize: 16, height: 1.45, color: Mt.ink2),
                ),
                const SizedBox(height: 14),
                GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.4, children: [
                  for (final (k, v) in [
                    (resolved ? 'Time to resolve' : 'Since reminder', fmtDuration(since)),
                    ('Packaging', ev.packagingMatched ? 'Matched (not proof)' : 'Not checked'),
                    ('Senior said', ev.userReportedTakenAt != null ? 'Taken (self-reported)' : 'Nothing yet'),
                    ('Caregiver check', ev.caregiverStatus == 'taken' ? 'Confirmed taken' : ev.caregiverStatus == 'not_taken' ? 'Recorded not taken' : 'Not yet checked'),
                  ])
                    Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .85), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black.withValues(alpha: .06))), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(fontSize: 13, color: Mt.muted)), Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                ]),
              ]),
            ),
            _Steps(esc: esc, ev: ev),
            if (!ack && auth.ctx.can('escalation.acknowledge')) PrimaryButton('Acknowledge alert', onPressed: () => run(() => repo.acknowledge(hid, esc.id), 'Alert acknowledged')),
            if (ack && !resolved) ...[
              if (auth.ctx.can('escalation.acknowledge'))
                PrimaryButton(esc.seniorPhone == null ? 'No phone number saved' : 'Call ${esc.seniorName.split(' ').first}', icon: Icons.call_rounded, onPressed: esc.seniorPhone == null ? null : () => launchUrl(Uri(scheme: 'tel', path: esc.seniorPhone))),
              if (esc.seniorPhone == null) const Text('Add a phone number for this person under People to call from here.', style: TextStyle(fontSize: 14, color: Mt.muted)),
              if (auth.ctx.can('verification.review')) OutlineBtn('Ask them to show the box again', icon: Icons.photo_camera_outlined, onPressed: () => run(() => repo.requestVerification(hid, esc.doseEventId), 'Request sent')),
              if (auth.ctx.can('escalation.acknowledge')) OutlineBtn('Add a note', icon: Icons.edit_note_rounded, onPressed: () => _noteSheet(context, (n) => run(() => repo.addNote(hid, esc.id, n), 'Note added'))),
              if (auth.ctx.can('escalation.resolve')) PrimaryButton('Record outcome & resolve', color: Mt.ok, onPressed: () => _resolveSheet(context, (o, n) => run(() => repo.resolve(hid, esc.id, o, n), 'Alert resolved'))),
            ],
            if (resolved)
              MtCard(color: Mt.okBg, border: Mt.okBorder, shadow: false, padding: const EdgeInsets.all(18), radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Resolution summary', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Mt.okDeep)),
                const SizedBox(height: 6),
                Text('${_outcomes[esc.outcome] ?? esc.outcome}. "${esc.resolutionNote ?? ''}"', style: const TextStyle(fontSize: 15, height: 1.5, color: Mt.ink2)),
              ])),
            _Deliveries(esc),
            MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 8), child: Text('Activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              for (final t in ev.timeline.reversed.where((t) => t.type != 'reminder_repeated'))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 72, child: Text(fmtTime(t.at), style: const TextStyle(fontSize: 14, color: Mt.muted))),
                    Expanded(child: Text(t.type == 'caregiver_note' ? 'Note: "${t.data['note']}"' : _caregiverText(t), style: const TextStyle(fontSize: 15))),
                  ]),
                ),
            ])),
          ];
        },
      ),
    );
  }

  String _caregiverText(TimelineEntry t) => timelineText(t).replaceAll('You ', 'Senior ').replaceAll('Your caregiver', 'A caregiver').replaceAll('Asked to check', 'Senior asked to check');

  void _noteSheet(BuildContext context, Future<void> Function(String) save) {
    final c = TextEditingController();
    showMtSheet(context, title: 'Add a note', builder: (ctx) => Column(children: [
          LabeledField(label: 'Note', controller: c, maxLines: 3, hint: 'e.g. Called, no answer'),
          const SizedBox(height: 14),
          PrimaryButton('Save note', height: 54, onPressed: () async {
            if (c.text.trim().isEmpty) return;
            Navigator.pop(ctx);
            await save(c.text.trim());
          }),
        ]));
  }

  void _resolveSheet(BuildContext context, Future<void> Function(String, String) resolve) {
    String? outcome;
    final note = TextEditingController();
    String? err;
    showMtSheet(context, title: 'Record outcome', builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('What did you find out?', style: TextStyle(fontSize: 15, color: Mt.muted2)),
          const SizedBox(height: 8),
          for (final e in _outcomes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                selected: outcome == e.key,
                button: true,
                child: GestureDetector(
                  onTap: () => set(() {
                    outcome = e.key;
                    err = null;
                  }),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: outcome == e.key ? const Color(0xFFF1F7FF) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: outcome == e.key ? Mt.blue : Mt.inputBorder, width: 1.5)),
                    child: Row(children: [
                      Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: outcome == e.key ? Mt.blue : Mt.inputBorder, width: 2)), child: outcome == e.key ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: Mt.blue))) : null),
                      const SizedBox(width: 12),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              ),
            ),
          if (err != null) Text(err!, style: const TextStyle(color: Mt.dangerDeep, fontSize: 14)),
          const SizedBox(height: 6),
          LabeledField(label: 'What happened? (required)', controller: note, maxLines: 2, hint: 'e.g. She took it with lunch and forgot to tap'),
          const SizedBox(height: 14),
          const Text('Resolving records this outcome permanently in the audit trail. The app never changes or suggests changes to medication.', style: TextStyle(fontSize: 13, color: Mt.muted)),
          const SizedBox(height: 12),
          PrimaryButton('Resolve alert', color: Mt.ok, height: 54, onPressed: () async {
            if (outcome == null) return set(() => err = 'Choose an outcome to continue.');
            if (note.text.trim().isEmpty) return set(() => err = 'Add a short note about what happened.');
            Navigator.pop(ctx);
            await resolve(outcome!, note.text.trim());
          }),
        ])));
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.esc, required this.ev});
  final Escalation esc;
  final DoseEvent ev;
  @override
  Widget build(BuildContext context) {
    final resolved = esc.status == 'resolved';
    final steps = [
      ('REMIND', fmtTime(esc.scheduledFor ?? esc.triggeredAt), Mt.blue, Mt.blueText),
      ('VERIFY', ev.packagingMatched ? 'Box matched' : 'Not verified', ev.packagingMatched ? Mt.blue : const Color(0xFFF2A93B), ev.packagingMatched ? Mt.blueText : Mt.warn),
      ('ESCALATE', fmtTime(esc.triggeredAt), Mt.blue, Mt.blueText),
      ('RESOLVE', resolved ? fmtTime(esc.resolvedAt!) : 'Open', resolved ? Mt.ok : esc.status == 'open' ? const Color(0xFFE1E8F2) : const Color(0xFFF2A93B), resolved ? Mt.okDeep : Mt.muted),
    ];
    return Semantics(
      label: 'Safety loop progress',
      child: Row(children: [
        for (final s in steps)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 6, decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 6),
                Text(s.$1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .4, color: s.$4)),
                Text(s.$2, style: const TextStyle(fontSize: 13, color: Mt.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Deliveries extends StatelessWidget {
  const _Deliveries(this.esc);
  final Escalation esc;
  @override
  Widget build(BuildContext context) {
    if (esc.deliveries.isEmpty) {
      return MtCard(color: Mt.warnBg, border: Mt.warnBorder, shadow: false, radius: 18, padding: const EdgeInsets.all(14), child: const Text('No caregiver contact was configured for this alert, so no messages were sent. Add contacts under People › Alert rules.', style: TextStyle(fontSize: 14, color: Mt.warn, fontWeight: FontWeight.w600)));
    }
    String text(Delivery d) => d.simulated && d.status == 'sent'
        ? 'Simulated (demo mode) - no real ${d.channel == 'ivr' ? 'call' : 'message'} was sent'
        : switch (d.status) {
          'sent' => 'Handed to ${d.channel == 'ivr' ? 'phone call' : 'WhatsApp'} provider (not confirmed read)',
          'delivered' => 'Delivered',
          'failed' => 'Failed after ${d.attempts} ${d.attempts == 1 ? 'try' : 'tries'}${d.lastError == null ? '' : ': ${d.lastError}'}',
          _ => 'Waiting to send',
        };
    return MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 8), child: Text('Notifications sent', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
      for (final d in esc.deliveries)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
          child: Row(children: [
            Icon(d.channel == 'ivr' ? Icons.call_outlined : Icons.chat_outlined, size: 20, color: d.status == 'failed' ? Mt.dangerDeep : Mt.muted2),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(d.contactName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), Text(text(d), style: TextStyle(fontSize: 13, color: d.status == 'failed' ? Mt.dangerDeep : Mt.muted))])),
          ]),
        ),
    ]));
  }
}
