import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../services/service_providers.dart';
import '../auth/auth_controller.dart';
import '../auth/login_screen.dart';
import '../doses/dose_logic.dart';
import '../shell/nav.dart';
import 'dose_widgets.dart';
import 'today_controller.dart';
import 'voice_sheet.dart';

class SeniorHomeScreen extends ConsumerStatefulWidget {
  const SeniorHomeScreen({super.key, required this.onOpenProfile});
  final VoidCallback onOpenProfile;
  @override
  ConsumerState<SeniorHomeScreen> createState() => _SeniorHomeScreenState();
}

class _SeniorHomeScreenState extends ConsumerState<SeniorHomeScreen> {
  final _spoken = <String>{};

  void _speakDue(TodayState s, DateTime now, String name) {
    final settings = ref.read(settingsProvider);
    if (!settings.spoken) return;
    for (final d in s.doses) {
      if (d.ui(now) == DoseUi.due && _spoken.add(d.key)) {
        ref.read(speechServiceProvider).speak('$name, time for your ${d.medication.name} ${d.medication.strength}.', rate: settings.ttsRate);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    final today = ref.watch(todayProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final firstName = auth.me.fullName.split(' ').first;

    return ScreenScroll(
      onRefresh: () => syncEverything(ref.read),
      gap: 18,
      children: [
        Row(children: [
          const Wordmark(),
          const Spacer(),
          _BellButton(),
          const SizedBox(width: 10),
          GestureDetector(onTap: widget.onOpenProfile, child: Semantics(button: true, label: 'Open profile', child: Avatar(auth.me.initials))),
        ]),
        today.when(
          loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorBox(e, onRetry: () => ref.invalidate(todayProvider)),
          data: (s) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _speakDue(s, now, firstName));
            return _Body(state: s, now: now, name: firstName);
          },
        ),
      ],
    );
  }
}

class _BellButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
        button: true,
        label: 'Notifications',
        child: GestureDetector(
          onTap: () => context.push(R.notifications),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE6EEF9)), boxShadow: Mt.shadow(.10, 18, 6)),
            child: const Icon(Icons.notifications_none_rounded, size: 26, color: Mt.ink),
          ),
        ),
      );
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.now, required this.name});
  final TodayState state;
  final DateTime now;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doses = state.doses;
    final uis = {for (final d in doses) d.key: d.ui(now)};
    final reported = doses.where((d) => const {DoseUi.reportedTaken, DoseUi.caregiverConfirmed}.contains(uis[d.key])).length;
    final featured = state.next(now) ?? (doses.isEmpty ? null : doses.last);
    final upcoming = doses.where((d) => !const {DoseUi.reportedTaken, DoseUi.caregiverConfirmed, DoseUi.resolved}.contains(uis[d.key])).toList();
    final escalated = doses.any((d) => uis[d.key] == DoseUi.escalated);
    final pending = doses.where((d) => uis[d.key] == DoseUi.due).length;
    final ok = doses.isNotEmpty && reported == doses.length;

    final safety = escalated
        ? (title: 'Caregiver alerted', color: Mt.dangerDeep, tile: const Color(0xFFFDECE9), text: 'A dose is not confirmed. Your caregiver was told.')
        : pending > 0
            ? (title: 'Pending', color: Mt.warn, tile: Mt.warnBg, text: '$pending dose${pending > 1 ? 's' : ''} waiting for you.')
            : (title: 'All good', color: Mt.ok, tile: const Color(0xFFE3F5EE), text: 'No unconfirmed doses right now.');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SyncBanner(fromCache: state.fromCache, pending: state.pendingSync),
      if (state.fromCache || state.pendingSync > 0) const SizedBox(height: 18),
      _Hero(greeting: greeting(now, name), chipOk: !(escalated || pending > 0), pending: pending),
      const SizedBox(height: 18),
      MtCard(
        child: Column(children: [
          Tappable(
            radius: 0,
            onTap: () => ref.read(shellTabProvider.notifier).set(1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEDF5FF), Color(0xFFF7FAFF)])),
              child: Row(children: [
                const Expanded(child: Text("Today's Medication", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                Text('$reported of ${doses.length} reported', style: const TextStyle(fontSize: 15, color: Mt.muted2)),
              ]),
            ),
          ),
          LinearProgressIndicator(value: doses.isEmpty ? 0 : reported / doses.length, minHeight: 4, backgroundColor: Mt.track, valueColor: const AlwaysStoppedAnimation(Mt.blue)),
          if (featured != null)
            DoseRow(dose: featured, now: now, showTime: true, onTap: () => context.push(R.dose(featured.key)))
          else
            const Padding(padding: EdgeInsets.all(18), child: Text('No medication is scheduled for today.', style: TextStyle(fontSize: 16, color: Mt.muted))),
        ]),
      ),
      const SizedBox(height: 18),
      _VoiceButton(onTap: () => showVoiceSheet(context, ref)),
      const SizedBox(height: 18),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _RingCard(done: reported, total: doses.length)),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Safety status: ${safety.title}. ${safety.text}',
            child: GestureDetector(
              onTap: () => context.push(R.notifications),
              child: MtCard(
                radius: 22,
                padding: const EdgeInsets.all(14),
                child: ExcludeSemantics(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 42, height: 42, decoration: BoxDecoration(color: safety.tile, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.shield_outlined, color: safety.color, size: 22)),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Safety Status', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 8),
                    Text(safety.title, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: safety.color, height: 1.1)),
                    const SizedBox(height: 6),
                    Text(safety.text, style: const TextStyle(fontSize: 14, color: Mt.muted, height: 1.35)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 18),
      MtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
            child: Row(children: [
              const Expanded(child: Text('Upcoming Medications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              TextAction('View All', onPressed: () => ref.read(shellTabProvider.notifier).set(1)),
            ]),
          ),
          for (final d in upcoming.take(4)) Container(decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))), child: DoseRow(dose: d, now: now, onTap: () => context.push(R.dose(d.key)))),
          if (upcoming.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
              child: Text(ok ? 'Every dose for today has been reported.' : 'Nothing else is scheduled for today.', style: const TextStyle(fontSize: 15, color: Mt.muted)),
            ),
        ]),
      ),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.chipOk, required this.pending});
  final String greeting;
  final bool chipOk;
  final int pending;

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
          Positioned(
            right: -16,
            top: -2,
            child: ExcludeSemantics(
              child: SizedBox(
                width: 184,
                height: 180,
                child: Stack(children: [
                  Positioned(right: 10, top: 6, child: Container(width: 150, height: 150, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(center: Alignment(-.24, -.36), colors: [Color(0xFFF1F7FF), Color(0xFFD3E5FF), Color(0xFFBCD8FD)], stops: [0, .58, 1])))),
                  Positioned(
                    left: 22,
                    top: 72,
                    child: Transform.rotate(angle: -.24, child: Container(width: 134, height: 84, decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFE2ECFA)]), boxShadow: [BoxShadow(color: const Color(0xFF1864DC).withValues(alpha: .22), blurRadius: 30, offset: const Offset(0, 20))]))),
                  ),
                  const Positioned(left: 40, top: 80, child: PillIcon('blue', size: 74)),
                  Positioned(
                    right: 2,
                    top: 20,
                    child: Transform.rotate(
                      angle: .1,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(16), boxShadow: Mt.shadow(.18, 24, 10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 28, height: 28, decoration: BoxDecoration(color: chipOk ? Mt.blue : const Color(0xFFE8913A), shape: BoxShape.circle), child: Icon(chipOk ? Icons.check_rounded : Icons.priority_high_rounded, color: Colors.white, size: 16)),
                          const SizedBox(width: 8),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(chipOk ? 'On track' : 'Check needed', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(chipOk ? 'Today' : '$pending pending', style: const TextStyle(fontSize: 13, color: Mt.muted)),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 178),
            child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: .6,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(greeting, style: const TextStyle(fontSize: 17, color: Mt.muted, fontWeight: FontWeight.w500)),
                const SizedBox(height: 7),
                Semantics(header: true, child: const Text('Stay on track today.', style: TextStyle(fontSize: 32, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -.6))),
                const SizedBox(height: 7),
                const Text('Your health, our priority.', style: TextStyle(fontSize: 16, color: Mt.muted)),
              ]),
            ),
            ),
          ),
        ]);
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Remind Me Now. Use voice to log or set a reminder',
        child: Container(
          decoration: BoxDecoration(gradient: Mt.gradientPrimary, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Mt.blue.withValues(alpha: .34), blurRadius: 32, offset: const Offset(0, 16))]),
          child: Tappable(
            radius: 24,
            onTap: onTap,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
                child: Row(children: [
                  Container(width: 54, height: 54, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .17), borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 30)),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Remind Me Now', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700)),
                      SizedBox(height: 3),
                      Text('Use voice to log or set a reminder', style: TextStyle(color: Colors.white, fontSize: 15)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _RingCard extends StatelessWidget {
  const _RingCard({required this.done, required this.total});
  final int done;
  final int total;
  @override
  Widget build(BuildContext context) {
    final frac = total == 0 ? 0.0 : done / total;
    return Semantics(
      label: 'Today so far: $done of $total doses reported',
      child: MtCard(
        radius: 22,
        padding: const EdgeInsets.all(14),
        child: ExcludeSemantics(
          child: Row(children: [
            SizedBox(
              width: 68,
              height: 68,
              child: Stack(alignment: Alignment.center, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: frac),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => CircularProgressIndicator(value: v, strokeWidth: 8, strokeCap: StrokeCap.round, backgroundColor: const Color(0xFFE3EEFC), valueColor: const AlwaysStoppedAnimation(Mt.blue), constraints: const BoxConstraints.tightFor(width: 68, height: 68)),
                ),
                Text('${(frac * 100).round()}%', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Today so far', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2)),
                const SizedBox(height: 3),
                Text('$done of $total reported', style: const TextStyle(fontSize: 14, color: Mt.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
