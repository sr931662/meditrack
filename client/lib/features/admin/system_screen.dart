import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../auth/auth_controller.dart';

final _statsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(adminRepositoryProvider).stats());
final _configProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(adminRepositoryProvider).config());
final _householdsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.read(adminRepositoryProvider).households());

/// Platform health, verification thresholds, feature gates and purpose-limited support access.
class SystemScreen extends ConsumerWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = (ref.watch(authControllerProvider) as Authenticated).me.platformPermissions;
    final stats = ref.watch(_statsProvider);
    final config = ref.watch(_configProvider);
    final households = ref.watch(_householdsProvider);
    return ScreenScroll(
      onRefresh: () async {
        ref.invalidate(_statsProvider);
        ref.invalidate(_configProvider);
        ref.invalidate(_householdsProvider);
      },
      children: [
        const PageTitle('System', sub: 'Platform health and configuration'),
        if (p.contains('system.monitor'))
          stats.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorBox(e),
            data: (s) => MtCard(radius: 22, padding: const EdgeInsets.all(18), child: Wrap(spacing: 24, runSpacing: 14, children: [
              for (final e in {'Users': s['users'], 'Households': s['households'], 'Doses (24 h)': s['dose_events_24h'], 'Open alerts': s['open_escalations']}.entries)
                SizedBox(width: 130, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${e.value}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), Text(e.key, style: const TextStyle(color: Mt.muted))])),
            ])),
          ),
        if (p.contains('system_config.manage'))
          config.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => ErrorBox(e),
            data: (c) => MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('Packaging verification'),
              _num(context, ref, c, 'verification.high_threshold', 'Match above (certain)'),
              _num(context, ref, c, 'verification.medium_threshold', 'Unsure above (else ask caregiver)'),
              ToggleRow(label: 'Healthcare organisations (B2B)', sub: 'Keep off until the enterprise features are ready', value: c['features.b2b_enabled'] == true, onChanged: (v) async {
                await ref.read(adminRepositoryProvider).saveConfig({'features.b2b_enabled': v});
                ref.invalidate(_configProvider);
              }),
            ])),
          ),
        if (p.contains('support.access'))
          MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionLabel('Households (no health data shown)'),
            ...households.when(
              loading: () => [const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())],
              error: (e, _) => [Padding(padding: const EdgeInsets.all(16), child: ErrorBox(e))],
              data: (list) => [
                for (final h in list)
                  ListTile(minTileHeight: 60, title: Text(h['name']), subtitle: Text('${h['members']} members · ${h['plan']}'), trailing: TextAction('Support access', onPressed: () => _support(context, ref, h))),
              ],
            ),
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 14), child: Text('Support access is read-only, expires, needs a written reason, and is audited.', style: TextStyle(fontSize: 13, color: Mt.muted))),
          ])),
      ],
    );
  }

  Widget _num(BuildContext context, WidgetRef ref, Map c, String key, String label) => ListTile(
        minTileHeight: 60,
        title: Text(label),
        subtitle: Text(key, style: const TextStyle(fontSize: 12)),
        trailing: Text('${c[key]}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        onTap: () {
          final t = TextEditingController(text: '${c[key]}');
          String? err;
          showMtSheet(context, title: label, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(children: [
                LabeledField(label: 'Value between 0 and 1', controller: t, keyboard: const TextInputType.numberWithOptions(decimal: true)),
                if (err != null) Text(err!, style: const TextStyle(color: Mt.dangerDeep)),
                const SizedBox(height: 14),
                PrimaryButton('Save', height: 54, onPressed: () async {
                  final v = double.tryParse(t.text);
                  if (v == null || v < 0 || v > 1) return set(() => err = 'Enter a number from 0 to 1.');
                  try {
                    await ref.read(adminRepositoryProvider).saveConfig({key: v});
                    ref.invalidate(_configProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    set(() => err = errorText(e));
                  }
                }),
              ])));
        },
      );

  void _support(BuildContext context, WidgetRef ref, Map h) {
    final reason = TextEditingController();
    String? err;
    showMtSheet(context, title: 'Support access', builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(h['name'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          LabeledField(label: 'Reason (e.g. support ticket number)', controller: reason, maxLines: 2),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Mt.dangerDeep))),
          const SizedBox(height: 14),
          PrimaryButton('Grant 30 minutes of read-only access', height: 54, onPressed: () async {
            if (reason.text.trim().isEmpty) return set(() => err = 'A reason is required.');
            try {
              await ref.read(adminRepositoryProvider).grantSupportAccess(h['id'], reason.text.trim(), 30);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                toast(context, 'Access granted for 30 minutes and recorded in the audit log');
              }
            } catch (e) {
              set(() => err = errorText(e));
            }
          }),
        ])));
  }
}
