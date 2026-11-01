enum VoiceKind { taken, remindLater, help, unwell, cannotFind, showNext, unknown }

class VoiceIntent {
  const VoiceIntent(this.kind, {this.minutes});
  final VoiceKind kind;
  final int? minutes;
}

const defaultRemindMinutes = 15;

/// Maps what a senior says or types to one of the allowed responses. Anything ambiguous is `unknown`:
/// the UI then asks instead of guessing, because a wrong "taken" would hide a missed dose.
VoiceIntent parseVoiceCommand(String raw) {
  final t = raw.toLowerCase().replaceAll('’', "'").trim();
  if (t.isEmpty) return const VoiceIntent(VoiceKind.unknown);

  if (RegExp(r"(not feeling well|don'?t feel well|do not feel well|feel(ing)? (sick|unwell|ill|dizzy|faint)|\bunwell\b|chest pain)").hasMatch(t)) {
    return const VoiceIntent(VoiceKind.unwell);
  }
  if (RegExp(r"(can'?t|cannot|can not|couldn'?t|unable to) find|\blost my\b|where (is|are) my").hasMatch(t)) {
    return const VoiceIntent(VoiceKind.cannotFind);
  }
  if (RegExp(r'\b(help|emergency)\b').hasMatch(t)) return const VoiceIntent(VoiceKind.help);

  if (RegExp(r'remind|snooze|\blater\b').hasMatch(t)) {
    final mins = RegExp(r'(\d+)\s*(min|minute)').firstMatch(t);
    final hrs = RegExp(r'(\d+)\s*(hour|hr)').firstMatch(t);
    final anHour = RegExp(r'\b(an|one) hour\b').hasMatch(t);
    final m = mins != null
        ? int.parse(mins.group(1)!)
        : hrs != null
            ? int.parse(hrs.group(1)!) * 60
            : anHour
                ? 60
                : defaultRemindMinutes;
    return VoiceIntent(VoiceKind.remindLater, minutes: m.clamp(1, 240));
  }

  if (RegExp(r'\b(show|open)\b.*\b(medicine|medication|pill|dose)|\bnext (medicine|medication|pill|dose)\b').hasMatch(t)) {
    return const VoiceIntent(VoiceKind.showNext);
  }

  final saidTaken = RegExp(r'\b(taken|took|take|had)\b').hasMatch(t);
  final negated = RegExp(r"\b(not|never|no|yet)\b|n't\b").hasMatch(t);
  final future = RegExp(r"\b(going to|about to|will|gonna|shall|should|need to|have to|must|want to)\b").hasMatch(t);
  if (saidTaken && !negated && !future) return const VoiceIntent(VoiceKind.taken);

  return const VoiceIntent(VoiceKind.unknown);
}
