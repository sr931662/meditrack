import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../services/service_providers.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

final pendingCountProvider = FutureProvider.autoDispose<int>((ref) => ref.read(localStoreProvider).pendingCount());

/// Profile / settings. Seniors get accessibility + voice + reminder health; caregivers and admins also
/// see their role. No technical configuration is exposed to seniors.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    final me = auth.me;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final isSenior = auth.ctx.mode == AppMode.senior;
    final roleText = switch (auth.ctx.mode) {
      AppMode.admin => me.platformRole == 'super_admin' ? 'Super administrator' : 'Operations administrator',
      AppMode.senior => 'Senior · ${auth.ctx.membership?.householdName ?? ''}',
      AppMode.caregiver => auth.ctx.membership == null ? 'Caregiver · no household yet' : '${auth.ctx.membership!.role == 'owner' ? 'Household owner' : 'Caregiver'} · ${auth.ctx.membership!.householdName}',
    };

    return ScreenScroll(gap: 16, children: [
      const PageTitle('Profile'),
      MtCard(
        padding: const EdgeInsets.all(18),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFF1F7FF)]),
        child: Row(children: [
          Avatar(me.initials, size: 64),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(me.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(me.email, style: const TextStyle(fontSize: 15, color: Mt.muted)),
            Text(roleText, style: const TextStyle(fontSize: 14, color: Mt.muted2)),
          ])),
        ]),
      ),
      MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionLabel('Accessibility'),
        ToggleRow(label: 'Larger text', sub: 'Increase text and control size', value: settings.largeText, onChanged: (v) => notifier.update(settings.copyWith(largeText: v))),
        ToggleRow(label: 'Reduce motion', sub: 'Turn off animations', value: settings.reduceMotion, onChanged: (v) => notifier.update(settings.copyWith(reduceMotion: v))),
      ])),
      if (isSenior)
        MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Voice & reminders'),
          ToggleRow(label: 'Spoken reminders', sub: settings.spoken ? 'Reminders are read aloud when the app is open' : 'Reminders show on screen only', value: settings.spoken, onChanged: (v) => notifier.update(settings.copyWith(spoken: v))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Voice speed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegControl<String>(semanticLabel: 'Voice speed', options: const [('Slower', 'Slower'), ('Normal', 'Normal'), ('Faster', 'Faster')], value: settings.voiceSpeed, onChanged: (v) => notifier.update(settings.copyWith(voiceSpeed: v))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: OutlineBtn('Test the voice', icon: Icons.volume_up_rounded, onPressed: () => ref.read(speechServiceProvider).speak('Time for your medicine.', rate: settings.ttsRate)),
          ),
        ])),
      if (isSenior) _ReminderHealth(pending: pending),
      MtCard(
        radius: 22,
        color: Mt.tint,
        border: const Color(0xFFE1EBF8),
        shadow: false,
        padding: const EdgeInsets.all(16),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PRIVACY & SECURITY', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Mt.muted2, letterSpacing: .8)),
          SizedBox(height: 8),
          Text('Your reminders are stored on this phone so they work without internet. Responses are sent to your caregiver\'s account over an encrypted connection. Photos of medicine boxes are read on this phone and are not uploaded; only the text or barcode is sent to be matched.', style: TextStyle(fontSize: 15, height: 1.5, color: Mt.ink2)),
        ]),
      ),
      if ((me.memberships.length) > 1 && !isSenior)
        MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Household'),
          for (final m in me.memberships)
            ListTile(
              minTileHeight: 56,
              title: Text(m.householdName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(m.role),
              trailing: auth.ctx.householdId == m.householdId ? const Icon(Icons.check_circle_rounded, color: Mt.blue) : null,
              onTap: () => ref.read(authControllerProvider.notifier).switchHousehold(m.householdId),
            ),
        ])),
      OutlineBtn('Sign out', icon: Icons.logout_rounded, color: Mt.dangerDeep, border: Mt.dangerBorder, onPressed: () async {
        final yes = await confirmDialog(context, title: 'Sign out?', body: pending > 0 ? '$pending response${pending == 1 ? '' : 's'} not uploaded yet will stay on this phone and upload next time you sign in.' : 'You will need to sign in again.', label: 'Sign out', color: Mt.danger);
        if (yes) await ref.read(authControllerProvider.notifier).logout();
      }),
    ]);
  }
}

/// Shows whether the things reminders depend on are in place, and is honest about Android's limits.
class _ReminderHealth extends ConsumerWidget {
  const _ReminderHealth({required this.pending});
  final int pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MtCard(
        radius: 22,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Reminder health'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(pending == 0 ? 'Everything you reported has been uploaded.' : '$pending response${pending == 1 ? '' : 's'} saved on this phone, waiting to upload.', style: const TextStyle(fontSize: 15, color: Mt.ink2)),
              const SizedBox(height: 10),
              const Text('Android can delay reminders if battery saver is on. If reminders arrive late, allow MediTrack to run without battery restrictions and allow "Alarms & reminders" in system settings.', style: TextStyle(fontSize: 14, color: Mt.muted, height: 1.4)),
              const SizedBox(height: 12),
              OutlineBtn('Allow reminders', icon: Icons.notifications_active_outlined, onPressed: () async {
                final ok = await ref.read(reminderServiceProvider).requestPermissions();
                final n = await rescheduleLocalReminders(ref.read);
                if (context.mounted) toast(context, ok ? 'Reminders on. $n scheduled on this phone.' : 'Notifications are off. Turn them on in system settings.');
              }),
              const SizedBox(height: 8),
              OutlineBtn('Sync now', icon: Icons.sync_rounded, onPressed: () async {
                await syncEverything(ref.read);
                ref.invalidate(pendingCountProvider);
                if (context.mounted) toast(context, 'Synced');
              }),
            ]),
          ),
        ]),
      );
}
