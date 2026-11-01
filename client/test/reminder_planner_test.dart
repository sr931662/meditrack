import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/features/medications/med_models.dart';
import 'package:meditrack/offline/reminder_planner.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Schedule sched({
  String id = 's1',
  List<String> times = const ['08:00'],
  List<int> weekdays = const [0, 1, 2, 3, 4, 5, 6],
  String tz = 'UTC',
  DateTime? end,
  String? msg,
}) =>
    Schedule(
      id: id,
      medicationId: 'm1',
      seniorId: 'sr',
      times: times,
      weekdays: weekdays,
      startDate: DateTime(2026, 10, 1),
      endDate: end,
      timezone: tz,
      reminderMessage: msg,
    );

final med = Medication(id: 'm1', seniorId: 'sr', name: 'Amlodipine', strength: '5 mg', dosageForm: 'tablet');

void main() {
  setUpAll(tzdata.initializeTimeZones);
  final now = DateTime.utc(2026, 10, 26, 0, 0); // a Monday

  List<ReminderPlan> plan(List<Schedule> s, {Map<String, Medication>? meds, int days = 2, int max = 60}) =>
      planReminders(schedules: s, medications: meds ?? {'m1': med}, nowUtc: now, days: days, maxCount: max);

  test('plans every occurrence in the window in time order', () {
    final p = plan([sched(times: ['20:00', '08:00'])]);
    expect(p.map((x) => x.atUtc.toIso8601String()), [
      '2026-10-26T08:00:00.000Z',
      '2026-10-26T20:00:00.000Z',
      '2026-10-27T08:00:00.000Z',
      '2026-10-27T20:00:00.000Z',
    ]);
  });

  test('timezone aware: 08:00 IST is 02:30 UTC', () {
    expect(plan([sched(tz: 'Asia/Kolkata')]).first.atUtc, DateTime.utc(2026, 10, 26, 2, 30));
  });

  test('DST: same wall clock, shifted UTC offset', () {
    final p = planReminders(
        schedules: [sched(tz: 'America/New_York')], medications: {'m1': med}, nowUtc: DateTime.utc(2026, 10, 31), days: 3, maxCount: 60);
    expect(p[0].atUtc, DateTime.utc(2026, 10, 31, 12)); // EDT
    expect(p[1].atUtc, DateTime.utc(2026, 11, 1, 13)); // EST
  });

  test('respects weekdays and end date', () {
    expect(plan([sched(weekdays: [0])], days: 8).length, 2); // Mon 26 Oct + Mon 2 Nov
    expect(plan([sched(end: DateTime(2026, 10, 26))], days: 5).length, 1);
  });

  test('skips inactive or unknown medications', () {
    expect(plan([sched()], meds: {}).isEmpty, isTrue);
    final off = Medication(id: 'm1', seniorId: 'sr', name: 'X', strength: '1', dosageForm: 'tablet', isActive: false);
    expect(plan([sched()], meds: {'m1': off}).isEmpty, isTrue);
  });

  test('caps the number of scheduled alarms (Android limits pending alarms)', () {
    expect(plan([sched(times: ['06:00', '09:00', '12:00', '15:00', '18:00', '21:00'])], days: 30, max: 25).length, 25);
  });

  test('ids are stable and unique per occurrence', () {
    final a = plan([sched()]);
    final b = plan([sched()]);
    expect(a.map((x) => x.id), b.map((x) => x.id));
    expect(a.map((x) => x.id).toSet().length, a.length);
    expect(a.every((x) => x.id > 0 && x.id < 0x7fffffff), isTrue);
  });

  test('message uses the caregiver-written text when present', () {
    expect(plan([sched(msg: 'Grandma, time for your blood pressure pill')]).first.body, 'Grandma, time for your blood pressure pill');
    expect(plan([sched()]).first.body, contains('Amlodipine 5 mg'));
  });

  test('payload lets a tapped notification open the right dose', () {
    final p = plan([sched()]).first;
    expect(p.payload, 's1|${p.atUtc.toIso8601String()}');
  });
}
