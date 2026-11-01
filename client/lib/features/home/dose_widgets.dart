import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../services/service_providers.dart';
import '../doses/dose_logic.dart';
import 'today_controller.dart';

class DoseStyle {
  const DoseStyle(this.fg, this.bg, this.icon);
  final Color fg;
  final Color bg;
  final IconData icon;
}

DoseStyle styleFor(DoseUi ui) => switch (ui) {
      DoseUi.upcoming || DoseUi.snoozed => const DoseStyle(Mt.upcomingFg, Mt.upcomingBg, Icons.schedule_rounded),
      DoseUi.due => const DoseStyle(Mt.warn, Mt.warnBg, Icons.warning_amber_rounded),
      DoseUi.reportedTaken => const DoseStyle(Mt.blueText, Mt.tintBlue, Icons.check_rounded),
      DoseUi.caregiverConfirmed => const DoseStyle(Mt.okDeep, Mt.okBg, Icons.verified_rounded),
      DoseUi.caregiverNotTaken => const DoseStyle(Mt.dangerDeep, Mt.dangerBg, Icons.info_outline_rounded),
      DoseUi.resolved => const DoseStyle(Mt.okDeep, Mt.okBg, Icons.check_circle_outline_rounded),
      DoseUi.escalated => const DoseStyle(Mt.unverifiedFg, Mt.unverifiedBg, Icons.warning_amber_rounded),
    };

String pillLabel(DoseView d, DoseUi ui) => ui == DoseUi.upcoming ? fmtTime(d.local) : doseUiLabel(ui);

/// A dose row as in the design: pill tile, "Name strength", "amount · instructions", status pill.
class DoseRow extends StatelessWidget {
  const DoseRow({super.key, required this.dose, required this.now, required this.onTap, this.showTime = false, this.card = false});
  final DoseView dose;
  final DateTime now;
  final VoidCallback onTap;
  final bool showTime;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final ui = dose.ui(now);
    final st = styleFor(ui);
    final m = dose.medication;
    final label = '${m.title}, ${m.subtitle}, ${fmtTime(dose.local)}, ${doseUiLabel(ui)}${dose.syncPending ? ', waiting to upload' : ''}';
    final row = Padding(
      padding: EdgeInsets.fromLTRB(card ? 14 : 18, 13, 12, 13),
      child: Row(children: [
        PillIcon(m.appearance, size: 52),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (m.subtitle.isNotEmpty) Text(m.subtitle, style: const TextStyle(fontSize: 15, color: Mt.muted)),
            if (showTime) Text('${fmtTime(dose.local)}${dose.syncPending ? ' · waiting to upload' : ''}', style: const TextStyle(fontSize: 14, color: Mt.muted2, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 8),
        StatusPill(pillLabel(dose, ui), fg: st.fg, bg: st.bg, icon: ui == DoseUi.upcoming ? Icons.schedule_rounded : st.icon),
        const Icon(Icons.chevron_right_rounded, color: Mt.faint, size: 20),
      ]),
    );
    final tappable = Tappable(radius: card ? 20 : 0, semanticLabel: label, onTap: onTap, child: ExcludeSemantics(child: row));
    return card ? MtCard(radius: 20, child: tappable) : tappable;
  }
}

/// Banner shown when the app is running from saved data or has responses waiting to upload.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key, required this.fromCache, required this.pending});
  final bool fromCache;
  final int pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!fromCache && pending == 0) return const SizedBox.shrink();
    final text = [
      if (fromCache) 'Offline: showing your saved schedule. Reminders still work.',
      if (pending > 0) '$pending ${pending == 1 ? 'response is' : 'responses are'} saved and will upload when you are online.',
    ].join(' ');
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Mt.warnBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Mt.warnBorder)),
        child: Row(children: [
          Icon(fromCache ? Icons.cloud_off_rounded : Icons.cloud_upload_outlined, color: Mt.warn, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Mt.warn, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

/// Records a response (offline-safe) and, for "remind me again", also sets a local alarm.
Future<void> performResponse(WidgetRef ref, DoseView d, String response) async {
  await ref.read(todayProvider.notifier).respond(d, response);
  if (response == 'remind_later') {
    final at = DateTime.now().toUtc().add(const Duration(minutes: snoozeMinutes));
    await ref.read(reminderServiceProvider).scheduleOneOff(
          id: (d.key.hashCode ^ at.millisecondsSinceEpoch) & 0x7fffffff,
          atUtc: at,
          title: 'Time for ${d.medication.name}',
          body: 'Reminder: your ${d.medication.title}.',
          payload: d.key,
        );
  }
}

const responseLabels = {
  'taken': 'Dose recorded as reported taken',
  'remind_later': 'We will remind you again in $snoozeMinutes minutes',
  'help': 'Help requested. Your caregiver has been told',
  'cannot_find': 'Your caregiver has been told you cannot find it',
  'unwell': 'Your caregiver has been told you are not feeling well',
  'acknowledged': 'Reminder acknowledged',
};
