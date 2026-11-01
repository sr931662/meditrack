import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../auth/auth_controller.dart';
import '../doses/dose_models.dart';

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth is! Authenticated || auth.ctx.householdId == null) return [];
  return ref.read(doseRepositoryProvider).notifications(auth.ctx.householdId!);
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    return PageFrame(
      title: 'Notifications',
      onRefresh: () async => ref.refresh(notificationsProvider.future),
      children: list.when(
        loading: () => const [Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))],
        error: (e, _) => [ErrorBox(e, onRetry: () => ref.invalidate(notificationsProvider))],
        data: (items) => items.isEmpty
            ? const [EmptyBox('Nothing here', 'New reminders and updates will appear here.')]
            : [
                for (final n in items)
                  MtCard(
                    radius: 20,
                    padding: const EdgeInsets.all(14),
                    color: n.kind == 'escalation' ? const Color(0xFFFFF8F7) : Colors.white,
                    border: n.kind == 'escalation' ? Mt.dangerBorder : Mt.border,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: n.kind == 'escalation' ? Mt.dangerBg : n.kind == 'reminder' ? Mt.warnBg : Mt.tintBlue, borderRadius: BorderRadius.circular(14)),
                        child: Icon(n.kind == 'escalation' ? Icons.warning_amber_rounded : n.kind == 'reminder' ? Icons.schedule_rounded : Icons.photo_camera_outlined, size: 21, color: n.kind == 'escalation' ? Mt.dangerDeep : n.kind == 'reminder' ? Mt.warn : Mt.blueText),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_kind(n.kind)} · ${fmtTime(n.createdAt)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: n.kind == 'escalation' ? Mt.dangerDeep : Mt.muted2, letterSpacing: .4)),
                        const SizedBox(height: 4),
                        Text(n.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(n.body, style: const TextStyle(fontSize: 15, color: Mt.muted2, height: 1.4)),
                      ])),
                    ]),
                  ),
              ],
      ),
    );
  }

  String _kind(String k) => switch (k) { 'escalation' => 'ALERT', 'reminder' => 'REMINDER', 'verification_prompt' => 'CHECK', _ => 'INFO' };
}
