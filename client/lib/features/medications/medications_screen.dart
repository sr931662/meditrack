import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../../services/service_providers.dart';
import '../auth/auth_controller.dart';
import '../household/care_providers.dart';
import 'med_models.dart';

const _quantities = ['1 tablet', '2 tablets', '1 capsule', '½ tablet', '5 ml'];
const _instructions = ['Before breakfast', 'After breakfast', 'With lunch', 'After lunch', 'After dinner', 'At bedtime', 'Any time'];
const _repeats = {'Daily': [0, 1, 2, 3, 4, 5, 6], 'Weekdays': [0, 1, 2, 3, 4], 'Weekends': [5, 6]};

String repeatLabel(List<int> days) {
  for (final e in _repeats.entries) {
    if (e.value.length == days.length && e.value.every(days.contains)) return e.key;
  }
  return '${days.length} days a week';
}

/// Caregiver view of medicines + their reminder schedules. Every write is permission-checked by the
/// server; the UI also hides actions the caregiver was not granted.
class MedicationsScreen extends ConsumerWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider) as Authenticated;
    final meds = ref.watch(medicationsProvider);
    final schedules = ref.watch(schedulesProvider).value ?? [];
    final seniors = ref.watch(seniorsProvider).value ?? [];
    final canAdd = auth.ctx.can('medications.create') && auth.ctx.can('schedules.manage');
    final canEdit = auth.ctx.can('medications.update');

    Future<void> refresh() async {
      ref.invalidate(medicationsProvider);
      ref.invalidate(schedulesProvider);
    }

    return ScreenScroll(
      onRefresh: refresh,
      children: [
        PageTitle('Medications', sub: 'Set up by caregivers · never changed by the app',
            trailing: canAdd && seniors.isNotEmpty
                ? SizedBox(height: 46, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Mt.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: () => _openForm(context, ref, seniors: seniors), icon: const Icon(Icons.add_rounded), label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))))
                : null),
        ...meds.when(
          loading: () => [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [ErrorBox(e, onRetry: refresh)],
          data: (list) {
            if (seniors.isEmpty && list.isEmpty) return [const EmptyBox('Add a senior first', 'Go to People to add the person who will take these medicines.')];
            if (list.isEmpty) return [EmptyBox('No medications yet', canAdd ? 'Tap Add to set up the first medicine and its reminder times.' : 'Nothing has been set up.')];
            return [
              for (final s in seniors)
                if (list.any((m) => m.seniorId == s.id)) ...[
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Mt.muted2))),
                  for (final m in list.where((m) => m.seniorId == s.id))
                    Builder(builder: (c) {
                      final sch = schedules.where((x) => x.medicationId == m.id).firstOrNull;
                      return MtCard(
                        radius: 20,
                        child: Tappable(
                          semanticLabel: '${m.title}, ${sch == null ? 'no reminder times' : sch.times.map(fmtHm).join(', ')}',
                          onTap: canEdit ? () => _openForm(context, ref, seniors: seniors, med: m, schedule: sch) : null,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                            child: Row(children: [
                              PillIcon(m.appearance),
                              const SizedBox(width: 13),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                if (m.subtitle.isNotEmpty) Text(m.subtitle, style: const TextStyle(fontSize: 15, color: Mt.muted)),
                                Text(sch == null ? 'No reminder times set' : '${sch.times.map(fmtHm).join(', ')} · ${repeatLabel(sch.weekdays)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: sch == null ? Mt.warn : Mt.muted2)),
                              ])),
                              if (canEdit) const Icon(Icons.edit_outlined, color: Mt.faint, size: 20),
                            ]),
                          ),
                        ),
                      );
                    }),
                ],
            ];
          },
        ),
      ],
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref, {required List<Senior> seniors, Medication? med, Schedule? schedule}) {
    return showMtSheet(context, title: med == null ? 'Add medication' : 'Edit medication', builder: (_) => _MedForm(seniors: seniors, med: med, schedule: schedule));
  }
}

class _MedForm extends ConsumerStatefulWidget {
  const _MedForm({required this.seniors, this.med, this.schedule});
  final List<Senior> seniors;
  final Medication? med;
  final Schedule? schedule;
  @override
  ConsumerState<_MedForm> createState() => _MedFormState();
}

class _MedFormState extends ConsumerState<_MedForm> {
  late final _name = TextEditingController(text: widget.med?.name);
  late final _strength = TextEditingController(text: widget.med?.strength);
  late final _purpose = TextEditingController(text: widget.med?.purpose);
  late final _barcode = TextEditingController(text: widget.med?.barcode);
  late String _seniorId = widget.med?.seniorId ?? widget.seniors.first.id;
  late String _qty = _quantities.contains(widget.med?.quantity) ? widget.med!.quantity! : _quantities.first;
  late String _instr = _instructions.contains(widget.med?.prescribedInstructions) ? widget.med!.prescribedInstructions! : 'After breakfast';
  late String _repeat = widget.schedule == null ? 'Daily' : repeatLabel(widget.schedule!.weekdays);
  late String _color = widget.med?.appearance ?? 'blue';
  late List<String> _times = [...(widget.schedule?.times ?? ['08:00'])];
  final _errors = <String, String>{};
  bool _busy = false;
  String? _serverError;

  @override
  void dispose() {
    for (final c in [_name, _strength, _purpose, _barcode]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    _errors.clear();
    if (_name.text.trim().length < 2) _errors['name'] = 'Enter the medicine name.';
    if (!RegExp(r'\d').hasMatch(_strength.text)) _errors['strength'] = 'Include a strength, for example 10 mg.';
    if (_times.isEmpty) _errors['times'] = 'Add at least one reminder time.';
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final auth = ref.read(authControllerProvider) as Authenticated;
    final hid = auth.ctx.householdId!;
    final repo = ref.read(careRepositoryProvider);
    final senior = widget.seniors.firstWhere((s) => s.id == _seniorId);
    final medBody = {
      'name': _name.text.trim(),
      'strength': _strength.text.trim(),
      'dosage_form': _qty.contains('capsule') ? 'capsule' : _qty.contains('ml') ? 'liquid' : 'tablet',
      'quantity': _qty,
      'purpose': _purpose.text.trim().isEmpty ? null : _purpose.text.trim(),
      'prescribed_instructions': _instr,
      'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      'appearance': _color,
    };
    setState(() {
      _busy = true;
      _serverError = null;
    });
    try {
      final editing = widget.med != null;
      final med = editing ? await repo.updateMedication(hid, widget.med!.id, medBody) : await repo.createMedication(hid, {...medBody, 'senior_id': _seniorId});
      final schedBody = {'times': _times, 'weekdays': _repeats[_repeat]};
      if (widget.schedule != null) {
        await repo.updateSchedule(hid, widget.schedule!.id, schedBody);
      } else {
        final n = DateTime.now();
        await repo.createSchedule(hid, {...schedBody, 'medication_id': med.id, 'start_date': '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}', 'timezone': senior.timezone});
      }
      ref.invalidate(medicationsProvider);
      ref.invalidate(schedulesProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, editing ? 'Changes saved' : '${med.name} added');
      }
    } catch (e) {
      if (mounted) setState(() => _serverError = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final yes = await confirmDialog(context, title: 'Remove ${widget.med!.name}?', body: 'Its reminders stop. Past history and the audit trail are kept.', label: 'Remove', color: Mt.danger);
    if (!yes) return;
    final auth = ref.read(authControllerProvider) as Authenticated;
    try {
      await ref.read(careRepositoryProvider).deleteMedication(auth.ctx.householdId!, widget.med!.id);
      ref.invalidate(medicationsProvider);
      ref.invalidate(schedulesProvider);
      if (mounted) {
        Navigator.pop(context);
        toast(context, '${widget.med!.name} removed');
      }
    } catch (e) {
      if (mounted) setState(() => _serverError = errorText(e));
    }
  }

  Future<void> _addTime() async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (!_times.contains(v)) _times = ([..._times, v]..sort());
      _errors.remove('times');
    });
  }

  Future<void> _scan() async {
    final code = await ref.read(scanServiceProvider).scanBarcode(context);
    if (code != null) setState(() => _barcode.text = code);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.med != null;
    Widget dropdown(String label, String value, List<String> opts, ValueChanged<String> on, {Map<String, String>? names}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(initialValue: value, isExpanded: true, items: [for (final o in opts) DropdownMenuItem(value: o, child: Text(names?[o] ?? o, overflow: TextOverflow.ellipsis))], onChanged: (v) => on(v!), decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!editing && widget.seniors.length > 1) ...[dropdown('For', _seniorId, [for (final s in widget.seniors) s.id], (v) => setState(() => _seniorId = v), names: {for (final s in widget.seniors) s.id: s.fullName}), const SizedBox(height: 14)],
      LabeledField(label: 'Medicine name', controller: _name, hint: 'e.g. Lisinopril', error: _errors['name']),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: LabeledField(label: 'Strength', controller: _strength, hint: 'e.g. 10 mg', error: _errors['strength'])),
        const SizedBox(width: 10),
        Expanded(child: dropdown('Amount', _qty, _quantities, (v) => setState(() => _qty = v))),
      ]),
      const SizedBox(height: 14),
      LabeledField(label: 'What is it for? (optional)', controller: _purpose, hint: 'e.g. Blood pressure'),
      const SizedBox(height: 14),
      dropdown('Instructions (as prescribed)', _instr, _instructions, (v) => setState(() => _instr = v)),
      const SizedBox(height: 14),
      const Text('Reminder times', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in _times) InputChip(label: Text(fmtHm(t), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), onDeleted: _times.length > 1 ? () => setState(() => _times.remove(t)) : null, deleteButtonTooltipMessage: 'Remove ${fmtHm(t)}', shape: const StadiumBorder(), materialTapTargetSize: MaterialTapTargetSize.padded),
        ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('Add time'), onPressed: _addTime, shape: const StadiumBorder(), materialTapTargetSize: MaterialTapTargetSize.padded),
      ]),
      if (_errors['times'] != null) Text(_errors['times']!, style: const TextStyle(color: Mt.dangerDeep, fontSize: 14)),
      const SizedBox(height: 14),
      const Text('Repeats', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      SegControl<String>(semanticLabel: 'Repeats', options: [for (final k in _repeats.keys) (k, k)], value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
      const SizedBox(height: 14),
      const Text('Pill colour', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(children: [
        for (final p in PillStyle.all.values)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Semantics(
              button: true,
              selected: _color == p.key,
              label: p.label,
              child: GestureDetector(onTap: () => setState(() => _color = p.key), child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: _color == p.key ? Mt.blue : Colors.transparent, width: 2)), child: PillIcon(p.key, size: 44))),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: LabeledField(label: 'Barcode (optional)', controller: _barcode, hint: 'Used to check the box', keyboard: TextInputType.number)),
        const SizedBox(width: 8),
        SizedBox(height: 56, width: 56, child: OutlinedButton(onPressed: _scan, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Icon(Icons.qr_code_scanner_rounded, semanticLabel: 'Scan barcode'))),
      ]),
      if (_serverError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Semantics(liveRegion: true, child: Text(_serverError!, style: const TextStyle(color: Mt.dangerDeep, fontSize: 15)))),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: OutlineBtn('Cancel', color: Mt.muted2, onPressed: () => Navigator.pop(context))),
        const SizedBox(width: 10),
        Expanded(child: PrimaryButton(editing ? 'Save changes' : 'Add medication', height: 54, loading: _busy, onPressed: _save)),
      ]),
      if (editing && ref.read(authControllerProvider) is Authenticated && (ref.read(authControllerProvider) as Authenticated).ctx.can('medications.delete'))
        TextAction('Remove this medication', color: Mt.dangerDeep, onPressed: _remove),
    ]);
  }
}
