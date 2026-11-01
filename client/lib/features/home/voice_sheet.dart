import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';
import '../../services/service_providers.dart';
import 'dose_widgets.dart';
import 'today_controller.dart';
import 'voice_parser.dart';

Future<void> showVoiceSheet(BuildContext context, WidgetRef ref) => showMtSheet(context, title: 'Voice assistant', builder: (_) => const _VoiceBody());

enum _Phase { idle, listening, interpreted, unavailable, nothing }

class _VoiceBody extends ConsumerStatefulWidget {
  const _VoiceBody();
  @override
  ConsumerState<_VoiceBody> createState() => _VoiceBodyState();
}

class _VoiceBodyState extends ConsumerState<_VoiceBody> {
  final _input = TextEditingController();
  _Phase _phase = _Phase.idle;
  String _heard = '';
  String _source = 'typed';
  VoiceIntent? _intent;
  DoseView? _target;

  @override
  void dispose() {
    ref.read(speechServiceProvider).stopListening();
    _input.dispose();
    super.dispose();
  }

  DoseView? _nextDose() {
    final s = ref.read(todayProvider).value;
    final now = DateTime.now();
    return s?.next(now);
  }

  void _interpret(String text, String source) {
    final intent = parseVoiceCommand(text);
    setState(() {
      _heard = text;
      _source = source;
      _intent = intent;
      _target = _nextDose();
      _phase = _Phase.interpreted;
      _input.clear();
    });
  }

  Future<void> _mic() async {
    final speech = ref.read(speechServiceProvider);
    if (_phase == _Phase.listening) {
      await speech.stopListening();
      return;
    }
    if (!await speech.canListen) {
      setState(() => _phase = _Phase.unavailable);
      return;
    }
    setState(() {
      _phase = _Phase.listening;
      _heard = '';
    });
    await speech.listen(
      (text, isFinal) {
        if (!mounted) return;
        setState(() => _heard = text);
        if (isFinal) text.trim().isEmpty ? setState(() => _phase = _Phase.nothing) : _interpret(text.trim(), 'speech');
      },
      (_) => mounted ? setState(() => _phase = _Phase.nothing) : null,
    );
  }

  ({String title, String detail, bool canRun}) _describe() {
    final i = _intent!;
    final d = _target;
    String need(String t) => d == null ? 'No dose is due today. Contact your caregiver if you need help.' : t;
    switch (i.kind) {
      case VoiceKind.taken:
        return d == null
            ? (title: 'Nothing left to confirm', detail: 'All of today\'s doses are already recorded.', canRun: false)
            : (title: 'Record ${d.medication.title} as reported taken', detail: 'Scheduled for ${_t(d)}. It will be logged as self-reported, not independently confirmed.', canRun: true);
      case VoiceKind.remindLater:
        return d == null
            ? (title: 'No dose to remind you about', detail: need(''), canRun: false)
            : (title: 'Remind me again in $snoozeMinutes minutes', detail: 'For ${d.medication.title}. Reminders repeat every $snoozeMinutes minutes.', canRun: true);
      case VoiceKind.help:
        return (title: 'Ask your caregiver for help', detail: need('Your caregiver will be told right away.'), canRun: d != null);
      case VoiceKind.unwell:
        return (title: 'Tell your caregiver you are not feeling well', detail: need('Your caregiver will be told right away. For an emergency, call your local emergency number.'), canRun: d != null);
      case VoiceKind.cannotFind:
        return (title: 'Tell your caregiver you cannot find your medicine', detail: need('Your caregiver will be told right away.'), canRun: d != null);
      case VoiceKind.showNext:
        return d == null
            ? (title: 'No more medicines today', detail: 'Every dose scheduled for today is recorded.', canRun: false)
            : (title: 'Open ${d.medication.title}', detail: 'Your next medicine.', canRun: true);
      case VoiceKind.unknown:
        return (title: "I didn't find a command I can act on", detail: 'Try "I have taken my medicine", "Remind me again", "I need help" or "I cannot find my medicine".', canRun: false);
    }
  }

  String _t(DoseView d) => TimeOfDay.fromDateTime(d.local).format(context);

  Future<void> _run() async {
    final i = _intent!;
    final d = _target;
    if (d == null) return;
    final nav = Navigator.of(context);
    final router = GoRouter.of(context);
    if (i.kind == VoiceKind.showNext) {
      nav.pop();
      router.push(R.dose(d.key));
      return;
    }
    final response = switch (i.kind) {
      VoiceKind.taken => 'taken',
      VoiceKind.remindLater => 'remind_later',
      VoiceKind.help => 'help',
      VoiceKind.unwell => 'unwell',
      _ => 'cannot_find',
    };
    await performResponse(ref, d, response);
    if (!mounted) return;
    nav.pop();
    toast(context, responseLabels[response]!);
  }

  @override
  Widget build(BuildContext context) {
    final listening = _phase == _Phase.listening;
    final (msg, color) = switch (_phase) {
      _Phase.idle => ('Tap the microphone and speak', Mt.ink2),
      _Phase.listening => ('Listening… tap again to stop', Mt.blueText),
      _Phase.interpreted => ('Check the action below before confirming', Mt.ink2),
      _Phase.unavailable => ("Voice input isn't available on this phone. Type a command below instead.", Mt.warn),
      _Phase.nothing => ("I didn't hear anything. Try again or type below.", Mt.warn),
    };
    final desc = _intent == null ? null : _describe();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Column(children: [
          Semantics(
            button: true,
            label: listening ? 'Stop listening' : 'Start voice input',
            child: GestureDetector(
              onTap: _mic,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: listening ? [Mt.blueDark, const Color(0xFF0E4FB3)] : [Mt.blueLight, Mt.blue]), boxShadow: [BoxShadow(color: Mt.blue.withValues(alpha: .38), blurRadius: 30, offset: const Offset(0, 14))]),
                child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(msg, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color))),
        ]),
      ),
      if (_heard.isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Mt.tint, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1EBF8))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_source == 'speech' ? 'YOU SAID' : 'YOU TYPED', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Mt.muted, letterSpacing: .6)),
            Text('"$_heard"', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
      if (desc != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: desc.canRun ? const Color(0xFFBFD8FA) : Mt.warnBorder, width: 1.5), boxShadow: Mt.shadow(.10, 26, 10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(desc.canRun ? 'I UNDERSTOOD' : 'NOT SURE', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Mt.muted, letterSpacing: .6)),
            const SizedBox(height: 4),
            Text(desc.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(desc.detail, style: const TextStyle(fontSize: 15, color: Mt.muted2, height: 1.4)),
            if (desc.canRun) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlineBtn('Cancel', color: Mt.muted2, height: 50, onPressed: () => setState(() {
                      _intent = null;
                      _phase = _Phase.idle;
                      _heard = '';
                    }))),
                const SizedBox(width: 8),
                Expanded(child: PrimaryButton('Confirm', height: 50, onPressed: _run)),
              ]),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 16),
      const Text('Or type a command', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _input, style: const TextStyle(fontSize: 16), textInputAction: TextInputAction.send, onSubmitted: (t) => t.trim().isEmpty ? null : _interpret(t.trim(), 'typed'), decoration: const InputDecoration(hintText: 'e.g. I have taken my medicine', hintStyle: TextStyle(color: Mt.faint)))),
        const SizedBox(width: 8),
        SizedBox(height: 52, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: Mt.ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: () => _input.text.trim().isEmpty ? null : _interpret(_input.text.trim(), 'typed'), child: const Text('Send', style: TextStyle(fontWeight: FontWeight.w700)))),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in const ['I have taken my medicine', 'Remind me again', 'I need help', 'I cannot find my medicine', 'I am not feeling well'])
          ActionChip(label: Text(s), labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Mt.blueText), backgroundColor: Mt.tint, side: const BorderSide(color: Mt.outline), shape: const StadiumBorder(), materialTapTargetSize: MaterialTapTargetSize.padded, onPressed: () => _interpret(s, 'typed')),
      ]),
    ]);
  }
}
