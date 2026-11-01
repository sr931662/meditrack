import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../data/repositories.dart';
import '../../services/service_providers.dart';
import '../auth/auth_controller.dart';
import '../doses/dose_models.dart';
import '../home/dose_widgets.dart';
import '../home/today_controller.dart';

/// Packaging check. Text and barcode are read ON THE DEVICE; the server only matches them against the
/// caregiver's reference record. A match proves the box looks right, nothing more.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, required this.doseKey});
  final String doseKey;
  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  Verification? _result;
  bool _busy = false;
  String? _error;

  Future<void> _check(DoseView dose, {String? text, String? barcode}) async {
    final auth = ref.read(authControllerProvider) as Authenticated;
    final eventId = dose.server?.id;
    if (eventId == null) {
      setState(() => _error = "Checking the box needs an internet connection. You can still tell us you've taken it, or ask your caregiver.");
      return;
    }
    if ((text ?? '').trim().isEmpty && barcode == null) {
      setState(() => _error = "I couldn't read any text. Try again with better light, holding the box steady.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(doseRepositoryProvider).verify(auth.ctx.householdId!, eventId, text: text, barcode: barcode);
      if (mounted) setState(() => _result = r);
      await ref.read(todayProvider.notifier).refresh();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo(DoseView d) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await ref.read(scanServiceProvider).readPackagingText();
      if (text == null) return setState(() => _busy = false);
      await _check(d, text: text);
    } catch (_) {
      if (mounted) {
        setState(() {
            _busy = false;
            _error = 'The camera could not be used. Check the camera permission, or scan the barcode instead.';
          });
      }
    }
  }

  Future<void> _barcode(DoseView d) async {
    final code = await ref.read(scanServiceProvider).scanBarcode(context);
    if (code != null) await _check(d, barcode: code);
  }

  @override
  Widget build(BuildContext context) {
    final dose = ref.watch(todayProvider).value?.doses.where((d) => d.key == widget.doseKey).firstOrNull;
    if (dose == null) return const PageFrame(title: 'Check medicine', children: [EmptyBox('Not available', 'This dose is no longer on today\'s list.')]);
    final r = _result;
    final (fg, bg, border, icon, title) = switch (r?.status) {
      'match' => (Mt.okDeep, Mt.okBg, Mt.okBorder, Icons.check_rounded, 'The box matches ${dose.medication.title}'),
      'uncertain' => (Mt.unverifiedFg, const Color(0xFFFFF6EE), const Color(0xFFF6D9C2), Icons.priority_high_rounded, 'Not sure yet'),
      _ => (Mt.dangerDeep, const Color(0xFFFFF4F2), Mt.dangerBorder, Icons.close_rounded, "This doesn't look like ${dose.medication.title}"),
    };
    return PageFrame(title: 'Check medicine', children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFEEF5FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFD6E6FB))),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF24406A), size: 20),
          SizedBox(width: 10),
          Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: 'This checks the box, not whether you took it. ', style: TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: 'Take a photo of the label or scan the barcode. You will still need to tell us when you take the medicine.')]), style: TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF24406A)))),
        ]),
      ),
      MtCard(radius: 18, shadow: false, padding: const EdgeInsets.all(12), child: Row(children: [
        PillIcon(dose.medication.appearance, size: 46),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(dose.medication.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), Text(dose.medication.subtitle, style: const TextStyle(fontSize: 14, color: Mt.muted))])),
      ])),
      if (_busy)
        const MtCard(padding: EdgeInsets.all(24), child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Checking the medicine…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))]))
      else if (r == null) ...[
        PrimaryButton('Take a photo of the label', icon: Icons.photo_camera_outlined, onPressed: () => _photo(dose)),
        OutlineBtn('Scan the barcode', icon: Icons.qr_code_scanner_rounded, onPressed: () => _barcode(dose)),
      ] else ...[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22), border: Border.all(color: border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, color: fg, size: 26), const SizedBox(width: 10), Expanded(child: Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: fg)))]),
            const SizedBox(height: 10),
            Text(
              r.status == 'match'
                  ? 'The label matches the medicine your caregiver set up. This does not show that you have taken it.'
                  : r.status == 'uncertain'
                      ? 'I could not read enough to be sure. Nothing has been recorded as taken.'
                      : 'Please check the label before taking anything. Nothing has been recorded as taken.',
              style: const TextStyle(fontSize: 15, height: 1.45, color: Mt.ink2),
            ),
            for (final reason in r.reasons) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $reason', style: const TextStyle(fontSize: 14, color: Mt.muted2))),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Match confidence', style: TextStyle(fontSize: 14, color: Mt.muted2)), Text('${(r.confidence * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700))]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: r.confidence, minHeight: 6, backgroundColor: Colors.black12, valueColor: AlwaysStoppedAnimation(fg))),
            const SizedBox(height: 8),
            Text('Checked by ${r.provider} (${r.model})', style: const TextStyle(fontSize: 12, color: Mt.muted)),
          ]),
        ),
        if (r.status == 'match') PrimaryButton('Tell us I took it', icon: Icons.check_rounded, onPressed: () async {
              final navigator = Navigator.of(context);
              final yes = await confirmDialog(context, title: 'Record ${dose.medication.title} as taken?', body: 'Only confirm if you have actually taken it.', label: 'Yes, I took it');
              if (!yes) return;
              await performResponse(ref, dose, 'taken');
              if (context.mounted) {
                toast(context, responseLabels['taken']!);
                navigator.pop();
              }
            }),
        if (r.nextAction == 'ask_caregiver' || r.status == 'uncertain') OutlineBtn('Ask my caregiver to check', icon: Icons.support_agent_rounded, color: Mt.dangerDeep, border: Mt.dangerBorder, onPressed: () async {
              final navigator = Navigator.of(context);
              await performResponse(ref, dose, 'help');
              if (context.mounted) {
                toast(context, responseLabels['help']!);
                navigator.pop();
              }
            }),
        OutlineBtn('Try again', onPressed: () => setState(() => _result = null)),
      ],
      if (_error != null) Semantics(liveRegion: true, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Mt.dangerBg, borderRadius: BorderRadius.circular(16)), child: Text(_error!, style: const TextStyle(fontSize: 15, color: Mt.dangerDeep)))),
    ]);
  }
}
