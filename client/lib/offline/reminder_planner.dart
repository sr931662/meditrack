import 'package:timezone/timezone.dart' as tz;

import '../features/medications/med_models.dart';

class ReminderPlan {
  const ReminderPlan({required this.id, required this.atUtc, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime atUtc;
  final String title;
  final String body;
  final String payload; // "scheduleId|scheduledForUtcIso"
}

/// Pure function: which local alarms should exist right now. Mirrors the server's occurrence rules
/// (wall-clock times in the schedule's timezone, weekday filter, start/end dates, DST-safe).
/// Android limits pending alarms and doze can defer them, so the window is deliberately small and is
/// rebuilt on every app start, after a sync, and by the boot receiver.
List<ReminderPlan> planReminders({
  required List<Schedule> schedules,
  required Map<String, Medication> medications,
  required DateTime nowUtc,
  int days = 3,
  int maxCount = 60,
}) {
  final end = nowUtc.add(Duration(days: days));
  final out = <ReminderPlan>[];
  for (final s in schedules) {
    final med = medications[s.medicationId];
    if (med == null || !med.isActive) continue;
    for (final at in occurrencesBetween(s, nowUtc, end)) {
      out.add(ReminderPlan(
        id: _stableId('${s.id}|${at.millisecondsSinceEpoch}'),
        atUtc: at,
        title: 'Time for ${med.name}',
        body: s.reminderMessage ?? 'Time for your ${med.name} ${med.strength}.',
        payload: '${s.id}|${at.toIso8601String()}',
      ));
    }
  }
  out.sort((a, b) => a.atUtc.compareTo(b.atUtc));
  return out.take(maxCount).toList();
}

/// FNV-1a, folded to a positive 31-bit int (Android notification ids are 32-bit signed).
int _stableId(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final id = h & 0x7fffffff;
  return id == 0 ? 1 : id;
}

/// Every UTC instant at which [s] fires within [startUtc, endUtc] (inclusive).
List<DateTime> occurrencesBetween(Schedule s, DateTime startUtc, DateTime endUtc) {
  final loc = s.timezone == 'UTC' ? tz.UTC : tz.getLocation(s.timezone);
  final startLocal = tz.TZDateTime.from(startUtc, loc);
  final spanDays = endUtc.difference(startUtc).inDays;
  final out = <DateTime>[];
  for (var i = -1; i <= spanDays + 1; i++) {
    final d = tz.TZDateTime(loc, startLocal.year, startLocal.month, startLocal.day + i);
    final day = DateTime(d.year, d.month, d.day);
    if (day.isBefore(s.startDate) || (s.endDate != null && day.isAfter(s.endDate!))) continue;
    if (!s.weekdays.contains(d.weekday - 1)) continue;
    for (final hhmm in s.times) {
      final p = hhmm.split(':');
      final ms = tz.TZDateTime(loc, d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1])).millisecondsSinceEpoch;
      final at = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      if (!at.isBefore(startUtc) && !at.isAfter(endUtc)) out.add(at);
    }
  }
  out.sort();
  return out;
}
