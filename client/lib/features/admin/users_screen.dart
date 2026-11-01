import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../auth/auth_controller.dart';

final adminUsersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, q) => ref.read(adminRepositoryProvider).users(q: q));

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    final p = auth.me.platformPermissions;
    final users = ref.watch(adminUsersProvider(_q));
    return ScreenScroll(
      onRefresh: () async => ref.refresh(adminUsersProvider(_q).future),
      children: [
        PageTitle('Users', sub: 'Accounts across the platform', trailing: p.contains('users.create') ? SizedBox(height: 46, child: FilledButton.icon(onPressed: () => _create(context, ref, auth.me.platformRole == 'super_admin'), icon: const Icon(Icons.add_rounded), label: const Text('New'), style: FilledButton.styleFrom(backgroundColor: Mt.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))))) : null),
        TextField(onChanged: (v) => setState(() => _q = v.trim()), decoration: const InputDecoration(hintText: 'Search by email', prefixIcon: Icon(Icons.search_rounded))),
        ...users.when(
          loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [ErrorBox(e, onRetry: () => ref.invalidate(adminUsersProvider(_q)))],
          data: (list) => [
            for (final u in list)
              MtCard(
                radius: 20,
                child: ListTile(
                  minTileHeight: 68,
                  leading: Avatar(initialsOf(u['full_name']), size: 44),
                  title: Text(u['full_name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${u['email']}${u['platform_role'] == null ? '' : ' · ${u['platform_role']}'}${u['is_active'] ? '' : ' · DISABLED'}'),
                  trailing: u['is_active'] ? null : const Icon(Icons.block_rounded, color: Mt.dangerDeep),
                  onTap: () => _detail(context, ref, u, p),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _create(BuildContext context, WidgetRef ref, bool isSuper) {
    final email = TextEditingController(), name = TextEditingController(), pw = TextEditingController();
    String role = 'none';
    String? err;
    showMtSheet(context, title: 'Create user', builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabeledField(label: 'Full name', controller: name),
          const SizedBox(height: 12),
          LabeledField(label: 'Email', controller: email, keyboard: TextInputType.emailAddress),
          const SizedBox(height: 12),
          LabeledField(label: 'Temporary password', controller: pw, obscure: true),
          if (isSuper) ...[
            const SizedBox(height: 12),
            const Text('Platform role', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegControl<String>(options: const [('none', 'None'), ('ops_admin', 'Operations')], value: role, onChanged: (v) => set(() => role = v)),
          ],
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Mt.dangerDeep))),
          const SizedBox(height: 14),
          PrimaryButton('Create user', height: 54, onPressed: () async {
            try {
              await ref.read(adminRepositoryProvider).createUser({'email': email.text.trim(), 'full_name': name.text.trim(), 'password': pw.text, if (role != 'none') 'platform_role': role});
              ref.invalidate(adminUsersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              set(() => err = errorText(e));
            }
          }),
        ])));
  }

  void _detail(BuildContext context, WidgetRef ref, Map<String, dynamic> u, Set<String> p) {
    final active = u['is_active'] as bool;
    showMtSheet(context, title: u['full_name'], builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(u['email'], style: const TextStyle(fontSize: 15, color: Mt.muted)),
          Text('Role: ${u['platform_role'] ?? 'household user'}', style: const TextStyle(fontSize: 15, color: Mt.muted2)),
          if (!active) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Disabled: ${u['disabled_reason'] ?? ''}', style: const TextStyle(color: Mt.dangerDeep))),
          const SizedBox(height: 16),
          if (p.contains('users.disable') && active)
            OutlineBtn('Disable account', icon: Icons.block_rounded, color: Mt.dangerDeep, border: Mt.dangerBorder, onPressed: () {
              Navigator.pop(ctx);
              _disable(context, ref, u);
            }),
          if (p.contains('users.disable') && !active)
            PrimaryButton('Re-enable account', onPressed: () async {
              await ref.read(adminRepositoryProvider).enable(u['id']);
              ref.invalidate(adminUsersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            }),
          const SizedBox(height: 6),
          const Text('Disabling signs the person out on every device straight away. Every change is written to the audit log.', style: TextStyle(fontSize: 13, color: Mt.muted)),
        ]));
  }

  void _disable(BuildContext context, WidgetRef ref, Map<String, dynamic> u) {
    final reason = TextEditingController();
    String? err;
    showMtSheet(context, title: 'Disable ${u['full_name']}', builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabeledField(label: 'Reason (recorded in the audit log)', controller: reason, maxLines: 2),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Mt.dangerDeep))),
          const SizedBox(height: 14),
          PrimaryButton('Disable account', color: Mt.danger, height: 54, onPressed: () async {
            if (reason.text.trim().isEmpty) return set(() => err = 'A reason is required.');
            try {
              await ref.read(adminRepositoryProvider).disable(u['id'], reason.text.trim());
              ref.invalidate(adminUsersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              set(() => err = errorText(e));
            }
          }),
        ])));
  }
}
