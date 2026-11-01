/// Client-side mirror of the server's evidence model. The vocabulary is deliberate:
///  * a self-report is "reported", never "verified" or "confirmed";
///  * "not taken" can only come from a caregiver decision;
///  * an unconfirmed dose is never called "missed".
enum DoseUi { upcoming, snoozed, due, reportedTaken, caregiverConfirmed, caregiverNotTaken, resolved, escalated }

class DoseFacts {
  const DoseFacts({
    required this.scheduledFor,
    this.snoozedUntil,
    this.reportedTakenAt,
    this.caregiverStatus,
    this.escalated = false,
    this.resolved = false,
    this.packagingMatched = false, // informational only: never changes the state
  });

  final DateTime scheduledFor;
  final DateTime? snoozedUntil;
  final DateTime? reportedTakenAt;
  final String? caregiverStatus; // taken | not_taken
  final bool escalated;
  final bool resolved;
  final bool packagingMatched;
}

DoseUi deriveDoseUi(DoseFacts f, DateTime now) {
  if (f.caregiverStatus == 'taken') return DoseUi.caregiverConfirmed;
  if (f.caregiverStatus == 'not_taken') return DoseUi.caregiverNotTaken;
  if (f.resolved) return DoseUi.resolved;
  if (f.escalated) return DoseUi.escalated;
  if (f.reportedTakenAt != null) return DoseUi.reportedTaken;
  if (f.snoozedUntil != null && now.isBefore(f.snoozedUntil!)) return DoseUi.snoozed;
  return now.isBefore(f.scheduledFor) ? DoseUi.upcoming : DoseUi.due;
}

String doseUiLabel(DoseUi ui) => switch (ui) {
      DoseUi.upcoming => 'Upcoming',
      DoseUi.snoozed => 'Snoozed',
      DoseUi.due => 'Awaiting',
      DoseUi.reportedTaken => 'Reported taken',
      DoseUi.caregiverConfirmed => 'Confirmed by caregiver',
      DoseUi.caregiverNotTaken => 'Recorded as not taken',
      DoseUi.resolved => 'Reviewed by caregiver',
      DoseUi.escalated => 'Caregiver alerted',
    };

String doseUiCaption(DoseUi ui) => switch (ui) {
      DoseUi.reportedTaken => 'Self-reported · not independently confirmed',
      DoseUi.escalated => 'Not yet confirmed. Your caregiver has been asked to check in.',
      DoseUi.due => 'Please confirm once you have taken it.',
      DoseUi.caregiverNotTaken => 'Recorded by your caregiver after checking.',
      DoseUi.caregiverConfirmed => 'Your caregiver checked this dose.',
      DoseUi.resolved => 'Your caregiver has reviewed this.',
      _ => '',
    };

bool doseNeedsAttention(DoseUi ui) => ui == DoseUi.due || ui == DoseUi.escalated;
bool doseCanRespond(DoseUi ui) => ui == DoseUi.upcoming || ui == DoseUi.snoozed || ui == DoseUi.due || ui == DoseUi.escalated;
