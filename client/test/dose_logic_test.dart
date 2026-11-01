import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/features/doses/dose_logic.dart';

void main() {
  final t0 = DateTime(2026, 10, 26, 8, 0);
  DoseFacts facts({
    DateTime? snoozedUntil,
    DateTime? reportedTakenAt,
    String? caregiverStatus,
    bool escalated = false,
    bool packagingMatched = false,
  }) =>
      DoseFacts(
        scheduledFor: t0,
        snoozedUntil: snoozedUntil,
        reportedTakenAt: reportedTakenAt,
        caregiverStatus: caregiverStatus,
        escalated: escalated,
        packagingMatched: packagingMatched,
      );

  test('before the scheduled time a dose is upcoming', () {
    expect(deriveDoseUi(facts(), DateTime(2026, 10, 26, 7, 0)), DoseUi.upcoming);
  });

  test('after the scheduled time with no response it is awaiting, not missed', () {
    final ui = deriveDoseUi(facts(), DateTime(2026, 10, 26, 9, 0));
    expect(ui, DoseUi.due);
    expect(doseUiLabel(ui).toLowerCase(), isNot(contains('miss')));
  });

  test('a packaging match alone never makes a dose taken', () {
    final ui = deriveDoseUi(facts(packagingMatched: true), DateTime(2026, 10, 26, 8, 10));
    expect(ui, DoseUi.due);
  });

  test('self-report is labelled as a report, never as verified or confirmed', () {
    final ui = deriveDoseUi(facts(reportedTakenAt: DateTime(2026, 10, 26, 8, 12)), DateTime(2026, 10, 26, 9));
    expect(ui, DoseUi.reportedTaken);
    final label = doseUiLabel(ui).toLowerCase();
    expect(label, contains('reported'));
    expect(label, isNot(contains('verified')));
    expect(label, isNot(contains('confirmed')));
    expect(doseUiCaption(ui).toLowerCase(), contains('not independently confirmed'));
  });

  test('escalated doses read as "caregiver alerted" and never as missed', () {
    final ui = deriveDoseUi(facts(escalated: true), DateTime(2026, 10, 26, 9));
    expect(ui, DoseUi.escalated);
    expect(doseUiLabel(ui).toLowerCase(), isNot(contains('miss')));
  });

  test('only a caregiver decision can produce a not-taken state', () {
    expect(deriveDoseUi(facts(caregiverStatus: 'not_taken'), DateTime(2026, 10, 26, 9)), DoseUi.caregiverNotTaken);
    expect(deriveDoseUi(facts(caregiverStatus: 'taken'), DateTime(2026, 10, 26, 9)), DoseUi.caregiverConfirmed);
    for (final ui in DoseUi.values.where((u) => u != DoseUi.caregiverNotTaken)) {
      expect(doseUiLabel(ui).toLowerCase(), isNot(contains('not taken')));
    }
  });

  test('caregiver confirmation outranks everything else', () {
    final f = facts(caregiverStatus: 'taken', escalated: true, reportedTakenAt: DateTime(2026, 10, 26, 8, 5));
    expect(deriveDoseUi(f, DateTime(2026, 10, 26, 9)), DoseUi.caregiverConfirmed);
  });

  test('snooze keeps the dose upcoming until the snooze time', () {
    final f = facts(snoozedUntil: DateTime(2026, 10, 26, 8, 30));
    expect(deriveDoseUi(f, DateTime(2026, 10, 26, 8, 10)), DoseUi.snoozed);
    expect(deriveDoseUi(f, DateTime(2026, 10, 26, 8, 31)), DoseUi.due);
  });
}
