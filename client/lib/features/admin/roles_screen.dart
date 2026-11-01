import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../auth/auth_controller.dart';

final rolesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(adminRepositoryProvider).roles());

/// Permission management. Edits apply immediately to every signed-in user of that role (no re-login).
class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(rolesProvider);
    final canEdit = (ref.watch(authControllerProvider) as Authenticated).me.platformPermissions.contains('permissions.manage');
    return ScreenScroll(
      onRefresh: () async => ref.refresh(rolesProvider.future),
      children: [
        const PageTitle('Roles & permissions', sub: 'What each role may do'),
        ...data.when(
          loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [ErrorBox(e, onRetry: () => ref.invalidate(rolesProvider))],
          data: (d) => [
            for (final r in (d['roles'] as List))
              MtCard(
                radius: 20,
                child: ListTile(
                  minTileHeight: 68,
                  title: Text(_title(r['role']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${r['scope']} role · ${(r['permissions'] as List).length} permissions${r['role'] == 'caregiver' ? ' (granted per person)' : ''}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _edit(context, ref, r, List<String>.from((d['available'] as Map)[r['scope']]), canEdit && r['role'] != 'super_admin' && r['role'] != 'caregiver'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _title(String r) => r.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

  void _edit(BuildContext context, WidgetRef ref, Map r, List<String> available, bool editable) {
    final sel = <String>{...List<String>.from(r['permissions'])};
    String? err;
    showMtSheet(context, title: _title(r['role']), builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!editable) Text(r['role'] == 'super_admin' ? 'The super administrator role is fixed so the platform can never be locked out.' : r['role'] == 'caregiver' ? 'Caregiver permissions are granted per person by the household owner.' : 'You do not have permission to edit roles.', style: const TextStyle(fontSize: 14, color: Mt.muted)),
          for (final p in available) CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: Text(p), value: sel.contains(p), onChanged: editable ? (v) => set(() => v! ? sel.add(p) : sel.remove(p)) : null),
          if (err != null) Text(err!, style: const TextStyle(color: Mt.dangerDeep)),
          if (editable) ...[
            const SizedBox(height: 12),
            PrimaryButton('Save permissions', height: 54, onPressed: () async {
              try {
                await ref.read(adminRepositoryProvider).setRolePermissions(r['role'], sel.toList());
                ref.invalidate(rolesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                set(() => err = errorText(e));
              }
            }),
          ],
        ])));
  }
}
