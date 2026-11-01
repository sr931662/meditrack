import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../auth/auth_controller.dart';
import 'care_providers.dart';

final membersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final a = ref.watch(authControllerProvider);
  if (a is! Authenticated || a.ctx.householdId == null) return [];
  return ref.read(careRepositoryProvider).members(a.ctx.householdId!);
});

final policyProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final a = ref.watch(authControllerProvider) as Authenticated;
  return ref.read(careRepositoryProvider).policy(a.ctx.householdId!);
});

const grantable = {
  'medications.read': 'See medications',
  'schedules.read': 'See reminder schedules',
  'adherence.read': 'See adherence history',
  'escalation.read': 'See alerts',
  'escalation.acknowledge': 'Acknowledge alerts',
  'escalation.resolve': 'Resolve alerts',
  'verification.review': 'Confirm doses & request checks',
};

/// Household owner tools: seniors, caregivers and their permissions, and the escalation rules.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    final seniors = ref.watch(seniorsProvider);
    final members = ref.watch(membersProvider);
    final canMembers = auth.ctx.can('members.manage');
    final canSeniors = auth.ctx.can('seniors.manage');

    void refresh() {
      ref.invalidate(seniorsProvider);
      ref.invalidate(membersProvider);
      ref.invalidate(policyProvider);
    }

    return ScreenScroll(
      onRefresh: () async => refresh(),
      children: [
        const PageTitle('People', sub: 'Who is looked after, and who helps'),
        MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 14, 8, 6), child: Row(children: [
            const Expanded(child: Text('Seniors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            if (canSeniors) TextAction('Add', onPressed: () => _seniorSheet(context, ref)),
          ])),
          ...seniors.when(
            loading: () => [const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [Padding(padding: const EdgeInsets.all(16), child: ErrorBox(e))],
            data: (list) => list.isEmpty
                ? [const Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 18), child: Text('Add the person who will receive reminders.', style: TextStyle(color: Mt.muted, fontSize: 15)))]
                : [
                    for (final s in list)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
                        child: Row(children: [
                          Avatar(s.fullName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join().toUpperCase(), size: 44),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            Text('${s.hasLogin ? 'Has their own sign-in' : 'Uses caregiver account'} · ${s.timezone}${s.phone == null ? '' : ' · ${s.phone}'}', style: const TextStyle(fontSize: 13, color: Mt.muted)),
                          ])),
                          if (canSeniors) IconButton(tooltip: 'Edit phone', constraints: const BoxConstraints(minWidth: 48, minHeight: 48), icon: const Icon(Icons.phone_outlined), onPressed: () => _phoneSheet(context, ref, s.id, s.phone)),
                        ]),
                      ),
                  ],
          ),
        ])),
        if (canMembers)
          MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(18, 14, 8, 6), child: Row(children: [
              const Expanded(child: Text('Caregivers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              TextAction('Invite', onPressed: () => _memberSheet(context, ref)),
            ])),
            ...members.when(
              loading: () => [const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))],
              error: (e, _) => [Padding(padding: const EdgeInsets.all(16), child: ErrorBox(e))],
              data: (list) => [
                for (final m in list.where((m) => m['role'] != 'senior'))
                  Container(
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
                    child: ListTile(
                      minTileHeight: 64,
                      title: Text(m['full_name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(m['role'] == 'owner' ? '${m['email']} · Owner' : '${m['email']} · ${(m['permissions'] as List).length} permissions'),
                      trailing: m['role'] == 'owner' ? null : const Icon(Icons.chevron_right_rounded),
                      onTap: m['role'] == 'owner' ? null : () => _memberSheet(context, ref, existing: m),
                    ),
                  ),
              ],
            ),
          ])),
        if (auth.ctx.can('escalation.manage')) _PolicyCard(onChanged: () => ref.invalidate(policyProvider)),
      ],
    );
  }

  void _seniorSheet(BuildContext context, WidgetRef ref) {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final pw = TextEditingController();
    final tz = TextEditingController(text: 'UTC');
    var login = false;
    String? err;
    var busy = false;
    showMtSheet(context, title: 'Add a senior', builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabeledField(label: 'Full name', controller: name),
          const SizedBox(height: 12),
          LabeledField(label: 'Phone (optional)', controller: phone, hint: '+15550100142', keyboard: TextInputType.phone),
          const SizedBox(height: 12),
          LabeledField(label: 'Time zone', controller: tz, hint: 'e.g. Asia/Kolkata or America/New_York'),
          const SizedBox(height: 8),
          ToggleRow(label: 'Give them their own sign-in', sub: 'So reminders also work on their own phone', value: login, onChanged: (v) => set(() => login = v)),
          if (login) ...[
            LabeledField(label: 'Their email', controller: email, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            LabeledField(label: 'Password', controller: pw, obscure: true, hint: 'At least 10 characters, letters and numbers'),
          ],
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Mt.dangerDeep))),
          const SizedBox(height: 14),
          PrimaryButton('Add senior', height: 54, loading: busy, onPressed: () async {
            if (name.text.trim().isEmpty) return set(() => err = 'Enter their name.');
            set(() {
              busy = true;
              err = null;
            });
            try {
              final a = ref.read(authControllerProvider) as Authenticated;
              await ref.read(careRepositoryProvider).createSenior(a.ctx.householdId!, {
                'full_name': name.text.trim(),
                'timezone': tz.text.trim(),
                'language': 'en',
                if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
                if (login) 'login_email': email.text.trim(),
                if (login) 'login_password': pw.text,
              });
              ref.invalidate(seniorsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              set(() {
                err = errorText(e);
                busy = false;
              });
            }
          }),
        ])));
  }

  void _phoneSheet(BuildContext context, WidgetRef ref, String seniorId, String? current) {
    final c = TextEditingController(text: current);
    String? err;
    showMtSheet(context, title: 'Phone number', builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(children: [
          LabeledField(label: 'Phone', controller: c, hint: '+15550100142', keyboard: TextInputType.phone),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Mt.dangerDeep))),
          const SizedBox(height: 14),
          PrimaryButton('Save', height: 54, onPressed: () async {
            try {
              final a = ref.read(authControllerProvider) as Authenticated;
              await ref.read(apiClientProvider).patch('/households/${a.ctx.householdId}/seniors/$seniorId', data: {'phone': c.text.trim()});
              ref.invalidate(seniorsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              set(() => err = errorText(e));
            }
          }),
        ])));
  }

  void _memberSheet(BuildContext context, WidgetRef ref, {Map<String, dynamic>? existing}) {
    final email = TextEditingController(text: existing?['email']);
    final perms = <String>{...List<String>.from(existing?['permissions'] ?? const <String>[])};
    String? err;
    showMtSheet(context, title: existing == null ? 'Invite a caregiver' : 'Edit permissions', builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (existing == null) ...[
            LabeledField(label: 'Their MediTrack email', controller: email, keyboard: TextInputType.emailAddress, hint: 'They need to create an account first'),
            const SizedBox(height: 12),
          ] else
            Text(existing['full_name'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('They can only do what you tick. You can change this at any time.', style: TextStyle(fontSize: 14, color: Mt.muted)),
          for (final e in grantable.entries) CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: Text(e.value), value: perms.contains(e.key), onChanged: (v) => set(() => v! ? perms.add(e.key) : perms.remove(e.key))),
          if (err != null) Text(err!, style: const TextStyle(color: Mt.dangerDeep)),
          const SizedBox(height: 10),
          PrimaryButton(existing == null ? 'Send invite' : 'Save permissions', height: 54, onPressed: () async {
            try {
              final a = ref.read(authControllerProvider) as Authenticated;
              final repo = ref.read(careRepositoryProvider);
              existing == null ? await repo.addMember(a.ctx.householdId!, email.text.trim(), perms.toList()) : await repo.setMemberPermissions(a.ctx.householdId!, existing['id'], perms.toList());
              ref.invalidate(membersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              set(() => err = errorText(e));
            }
          }),
          if (existing != null)
            TextAction('Remove from household', color: Mt.dangerDeep, onPressed: () async {
              final a = ref.read(authControllerProvider) as Authenticated;
              final ok = await confirmDialog(ctx, title: 'Remove ${existing['full_name']}?', body: 'They will lose access immediately.', label: 'Remove', color: Mt.danger);
              if (!ok) return;
              await ref.read(careRepositoryProvider).removeMember(a.ctx.householdId!, existing['id']);
              ref.invalidate(membersProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            }),
        ])));
  }
}

class _PolicyCard extends ConsumerWidget {
  const _PolicyCard({required this.onChanged});
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(policyProvider);
    return MtCard(radius: 22, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 14, 8, 6), child: Row(children: [
        const Expanded(child: Text('Alert rules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        TextAction('Edit', onPressed: () => policy.hasValue ? _edit(context, ref, policy.value!) : null),
      ])),
      ...policy.when(
        loading: () => [const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))],
        error: (e, _) => [Padding(padding: const EdgeInsets.all(16), child: ErrorBox(e))],
        data: (p) => [
          Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 8), child: Text('Ask for a packaging check after ${p['t_verify_min']} min. If still not confirmed after ${p['t_escalate_min']} min, contact:', style: const TextStyle(fontSize: 15, color: Mt.ink2, height: 1.4))),
          if ((p['contacts'] as List).isEmpty) const Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 16), child: Text('No contacts yet. Nobody will be messaged until you add one.', style: TextStyle(fontSize: 14, color: Mt.warn, fontWeight: FontWeight.w600))),
          for (final c in (p['contacts'] as List))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
              child: Row(children: [Expanded(child: Text('${c['priority']}. ${c['name']}  ${c['phone']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))), Text((c['channels'] as List).join(' + '), style: const TextStyle(fontSize: 13, color: Mt.muted))]),
            ),
        ],
      ),
    ]));
  }

  void _edit(BuildContext context, WidgetRef ref, Map<String, dynamic> p) {
    final verify = TextEditingController(text: '${p['t_verify_min']}');
    final esc = TextEditingController(text: '${p['t_escalate_min']}');
    final contacts = [for (final c in (p['contacts'] as List)) Map<String, dynamic>.from(c)];
    final name = TextEditingController();
    final phone = TextEditingController();
    var wa = true, ivr = false;
    String? err;
    showMtSheet(context, title: 'Alert rules', builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: LabeledField(label: 'Check box after (min)', controller: verify, keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: LabeledField(label: 'Alert after (min)', controller: esc, keyboard: TextInputType.number)),
          ]),
          const SizedBox(height: 16),
          const Text('Who to contact (in order)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          for (var i = 0; i < contacts.length; i++)
            ListTile(contentPadding: EdgeInsets.zero, title: Text('${contacts[i]['name']}  ${contacts[i]['phone']}'), subtitle: Text((contacts[i]['channels'] as List).join(' + ')), trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.close_rounded), onPressed: () => set(() => contacts.removeAt(i)))),
          const Divider(),
          LabeledField(label: 'Name', controller: name),
          const SizedBox(height: 10),
          LabeledField(label: 'Phone', controller: phone, hint: '+15550100142', keyboard: TextInputType.phone),
          CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('WhatsApp message'), value: wa, onChanged: (v) => set(() => wa = v!)),
          CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('Automated phone call'), value: ivr, onChanged: (v) => set(() => ivr = v!)),
          const Text('Only add people who agreed to be contacted on these channels.', style: TextStyle(fontSize: 13, color: Mt.muted)),
          OutlineBtn('Add contact', onPressed: () {
            if (name.text.trim().isEmpty || phone.text.trim().isEmpty || (!wa && !ivr)) return set(() => err = 'Enter a name, phone and at least one channel.');
            set(() {
              contacts.add({'name': name.text.trim(), 'phone': phone.text.trim(), 'channels': [if (wa) 'whatsapp', if (ivr) 'ivr'], 'priority': contacts.length + 1, 'consent': true});
              name.clear();
              phone.clear();
              err = null;
            });
          }),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Mt.dangerDeep))),
          const SizedBox(height: 14),
          PrimaryButton('Save rules', height: 54, onPressed: () async {
            try {
              final a = ref.read(authControllerProvider) as Authenticated;
              await ref.read(careRepositoryProvider).savePolicy(a.ctx.householdId!, {'t_verify_min': int.tryParse(verify.text) ?? 5, 't_escalate_min': int.tryParse(esc.text) ?? 45, 'contacts': contacts});
              onChanged();
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              set(() => err = errorText(e));
            }
          }),
        ])));
  }
}
