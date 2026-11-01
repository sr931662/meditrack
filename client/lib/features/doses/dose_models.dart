DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

class Delivery {
  Delivery({required this.contactName, required this.channel, required this.status, required this.attempts, this.lastError, this.simulated = false});
  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
      contactName: j['contact_name'], channel: j['channel'], status: j['status'], attempts: j['attempts'], lastError: j['last_error'], simulated: j['simulated'] == true);
  final String contactName;
  final String channel;
  final String status; // pending | sent | delivered | failed
  final int attempts;
  final String? lastError;

  /// Demo-mode delivery: accepted by a simulated provider, nothing was sent to a real phone.
  final bool simulated;
}

class Escalation {
  Escalation({
    required this.id,
    required this.doseEventId,
    required this.status,
    required this.priority,
    required this.reason,
    required this.triggeredAt,
    this.acknowledgedAt,
    this.resolvedAt,
    this.outcome,
    this.resolutionNote,
    this.deliveries = const [],
    this.seniorName = '',
    this.seniorPhone,
    this.medication = '',
    this.scheduledFor,
  });

  factory Escalation.fromJson(Map<String, dynamic> j) => Escalation(
        id: j['id'],
        doseEventId: j['dose_event_id'],
        status: j['status'],
        priority: j['priority'],
        reason: j['reason'],
        triggeredAt: _dt(j['triggered_at'])!,
        acknowledgedAt: _dt(j['acknowledged_at']),
        resolvedAt: _dt(j['resolved_at']),
        outcome: j['outcome'],
        resolutionNote: j['resolution_note'],
        deliveries: [for (final d in (j['deliveries'] as List? ?? const [])) Delivery.fromJson(d)],
        seniorName: j['senior_name'] ?? '',
        seniorPhone: j['senior_phone'],
        medication: j['medication'] ?? '',
        scheduledFor: _dt(j['scheduled_for']),
      );

  final String seniorName;
  final String? seniorPhone;
  final String medication;
  final DateTime? scheduledFor;
  final String id;
  final String doseEventId;
  final String status; // open | acknowledged | resolved
  final String priority;
  final String reason;
  final DateTime triggeredAt;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final String? outcome;
  final String? resolutionNote;
  final List<Delivery> deliveries;

  bool get isHelpRequest => reason.startsWith('help_requested');
}

class Verification {
  Verification({required this.status, required this.confidence, required this.reasons, required this.nextAction, required this.provider, required this.model, this.packaging, required this.createdAt});
  factory Verification.fromJson(Map<String, dynamic> j) => Verification(
        status: j['status'],
        confidence: (j['confidence'] as num).toDouble(),
        reasons: List<String>.from(j['reasons'] ?? const []),
        nextAction: j['next_action'],
        provider: j['provider'],
        model: j['model'],
        packaging: j['packaging'],
        createdAt: _dt(j['created_at'])!,
      );
  final String status; // match | uncertain | no_match
  final double confidence;
  final List<String> reasons;
  final String nextAction; // none | retake_or_secondary | ask_caregiver
  final String provider;
  final String model;
  final String? packaging;
  final DateTime createdAt;
}

class TimelineEntry {
  TimelineEntry(this.type, this.at, this.data);
  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(j['type'], _dt(j['at'])!, Map<String, dynamic>.from(j['data'] ?? {}));
  final String type;
  final DateTime at;
  final Map<String, dynamic> data;
}

/// Server record of one scheduled dose. Each fact is a separate field on purpose.
class DoseEvent {
  DoseEvent({
    required this.id,
    required this.scheduleId,
    required this.medicationId,
    required this.seniorId,
    required this.scheduledFor,
    required this.displayStatus,
    this.reminderSentAt,
    this.acknowledgedAt,
    required this.packagingMatched,
    this.userReportedTakenAt,
    this.caregiverStatus,
    this.helpRequestedAt,
    this.snoozedUntil,
    this.escalation,
    this.verifications = const [],
    this.timeline = const [],
  });

  factory DoseEvent.fromJson(Map<String, dynamic> j) => DoseEvent(
        id: j['id'],
        scheduleId: j['schedule_id'],
        medicationId: j['medication_id'],
        seniorId: j['senior_id'],
        scheduledFor: _dt(j['scheduled_for'])!,
        displayStatus: j['display_status'],
        reminderSentAt: _dt(j['reminder_sent_at']),
        acknowledgedAt: _dt(j['acknowledged_at']),
        packagingMatched: j['packaging_matched'] ?? false,
        userReportedTakenAt: _dt(j['user_reported_taken_at']),
        caregiverStatus: j['caregiver_status'],
        helpRequestedAt: _dt(j['help_requested_at']),
        snoozedUntil: _dt(j['snoozed_until']),
        escalation: j['escalation'] == null ? null : Escalation.fromJson(j['escalation']),
        verifications: [for (final v in (j['verifications'] as List? ?? const [])) Verification.fromJson(v)],
        timeline: [for (final t in (j['timeline'] as List? ?? const [])) TimelineEntry.fromJson(t)],
      );

  final String id;
  final String scheduleId;
  final String medicationId;
  final String seniorId;
  final DateTime scheduledFor;
  final String displayStatus;
  final DateTime? reminderSentAt;
  final DateTime? acknowledgedAt;
  final bool packagingMatched;
  final DateTime? userReportedTakenAt;
  final String? caregiverStatus;
  final DateTime? helpRequestedAt;
  final DateTime? snoozedUntil;
  final Escalation? escalation;
  final List<Verification> verifications;
  final List<TimelineEntry> timeline;
}

class AppNotification {
  AppNotification({required this.id, required this.kind, required this.title, required this.body, required this.createdAt, this.doseEventId});
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
      id: j['id'], kind: j['kind'], title: j['title'], body: j['body'], createdAt: _dt(j['created_at'])!, doseEventId: j['dose_event_id']);
  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? doseEventId;
}

class MedAdherence {
  MedAdherence({required this.name, required this.scheduled, required this.matched, required this.reported, required this.confirmed, required this.unverified});
  factory MedAdherence.fromJson(Map<String, dynamic> j) => MedAdherence(
      name: j['name'], scheduled: j['scheduled'], matched: j['packaging_matched'], reported: j['user_reported_taken'], confirmed: j['caregiver_confirmed'], unverified: j['unverified']);
  final String name;
  final int scheduled, matched, reported, confirmed, unverified;
}

/// Dashboard counters. Packaging match, self-report and caregiver confirmation are separate numbers.
class Dashboard {
  Dashboard({
    required this.totalSeniors,
    required this.scheduled,
    required this.remindersSent,
    required this.packagingMatched,
    required this.userReported,
    required this.caregiverConfirmed,
    required this.unverified,
    required this.pendingInterventions,
    required this.activeEscalations,
    required this.resolvedEscalations,
    required this.deliveryStatus,
    required this.byMedication,
    required this.recent,
  });

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        totalSeniors: j['total_seniors'],
        scheduled: j['scheduled'],
        remindersSent: j['reminders_sent'],
        packagingMatched: j['packaging_matched'],
        userReported: j['user_reported_taken'],
        caregiverConfirmed: j['caregiver_confirmed'],
        unverified: j['unverified'],
        pendingInterventions: j['pending_interventions'],
        activeEscalations: j['active_escalations'],
        resolvedEscalations: j['resolved_escalations'],
        deliveryStatus: Map<String, int>.from(j['delivery_status'] ?? {}),
        byMedication: [for (final m in (j['by_medication'] as List)) MedAdherence.fromJson(m)],
        recent: [for (final r in (j['recent_activity'] as List)) TimelineEntry.fromJson(r)],
      );

  final int totalSeniors, scheduled, remindersSent, packagingMatched, userReported, caregiverConfirmed, unverified;
  final int pendingInterventions, activeEscalations, resolvedEscalations;
  final Map<String, int> deliveryStatus;
  final List<MedAdherence> byMedication;
  final List<TimelineEntry> recent;
}
