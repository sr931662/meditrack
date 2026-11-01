import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';

final auditProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, action) => ref.read(adminRepositoryProvider).auditLogs(action: action));

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String _action = '';

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(auditProvider(_action));
    return ScreenScroll(
      onRefresh: () async => ref.refresh(auditProvider(_action).future),
      children: [
        const PageTitle('Audit log', sub: 'Every sensitive action, newest first'),
        ChipRow<String>(options: const [('', 'All'), ('user.created', 'Users created'), ('user.disabled', 'Disabled'), ('role.permissions_changed', 'Permissions'), ('support_access.granted', 'Support access')], value: _action, onChanged: (v) => setState(() => _action = v)),
        ...logs.when(
          loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [ErrorBox(e, onRetry: () => ref.invalidate(auditProvider(_action)))],
          data: (list) => list.isEmpty
              ? [const EmptyBox('Nothing recorded', 'Actions will appear here as they happen.')]
              : [
                  for (final l in list)
                    MtCard(
                      radius: 18,
                      shadow: false,
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Expanded(child: Text(l['action'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))), Text(fmtTime(DateTime.parse(l['at']).toLocal()), style: const TextStyle(fontSize: 13, color: Mt.muted))]),
                        const SizedBox(height: 2),
                        Text('${DateTime.parse(l['at']).toLocal().toString().substring(0, 10)} · actor ${(l['actor_user_id'] ?? 'system').toString().substring(0, 8)}${l['target_type'] == null ? '' : ' · ${l['target_type']}'}', style: const TextStyle(fontSize: 13, color: Mt.muted)),
                        if ((l['data'] as Map).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text((l['data'] as Map).entries.map((e) => '${e.key}: ${e.value}').join(' · '), style: const TextStyle(fontSize: 13, color: Mt.ink2))),
                      ]),
                    ),
                ],
        ),
      ],
    );
  }
}
