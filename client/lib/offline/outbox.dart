import 'dart:math';

import 'local_store.dart';

enum OutboxStatus { pending, synced, rejected }

/// One response recorded on the device (possibly while offline). `clientEventId` is the idempotency key.
class OutboxEvent {
  OutboxEvent({
    required this.clientEventId,
    required this.householdId,
    required this.scheduleId,
    required this.scheduledFor,
    required this.response,
    required this.occurredAt,
    this.doseEventId,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.lastError,
  });

  final String clientEventId;
  final String householdId;
  final String scheduleId;
  final DateTime scheduledFor; // UTC
  final String response; // acknowledged | taken | help | cannot_find | unwell | remind_later
  final DateTime occurredAt; // UTC, device clock
  final String? doseEventId;
  OutboxStatus status;
  int attempts;
  String? lastError;

  Map<String, dynamic> toSyncJson() => {
        'client_event_id': clientEventId,
        'type': 'respond',
        'response': response,
        'schedule_id': scheduleId,
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        if (doseEventId != null) 'dose_event_id': doseEventId,
      };

  Map<String, dynamic> toRow() => {
        'client_event_id': clientEventId,
        'household_id': householdId,
        'schedule_id': scheduleId,
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        'response': response,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'dose_event_id': doseEventId,
        'status': status.name,
        'attempts': attempts,
        'last_error': lastError,
      };

  factory OutboxEvent.fromRow(Map<String, Object?> r) => OutboxEvent(
        clientEventId: r['client_event_id'] as String,
        householdId: r['household_id'] as String,
        scheduleId: r['schedule_id'] as String,
        scheduledFor: DateTime.parse(r['scheduled_for'] as String).toUtc(),
        response: r['response'] as String,
        occurredAt: DateTime.parse(r['occurred_at'] as String).toUtc(),
        doseEventId: r['dose_event_id'] as String?,
        status: OutboxStatus.values.byName(r['status'] as String),
        attempts: r['attempts'] as int,
        lastError: r['last_error'] as String?,
      );
}

String randomEventId() {
  final r = Random.secure();
  return 'c-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

/// Durable queue of device events. Writing here is the ONLY thing a response needs to succeed;
/// uploading is a separate, retried step (see SyncService).
class Outbox {
  Outbox(this._store, {String Function()? newId}) : _newId = newId ?? randomEventId;
  final LocalStore _store;
  final String Function() _newId;

  Future<OutboxEvent> record({
    required String householdId,
    required String scheduleId,
    required DateTime scheduledFor,
    required String response,
    required DateTime occurredAt,
    String? doseEventId,
  }) async {
    final e = OutboxEvent(
      clientEventId: _newId(),
      householdId: householdId,
      scheduleId: scheduleId,
      scheduledFor: scheduledFor.toUtc(),
      response: response,
      occurredAt: occurredAt.toUtc(),
      doseEventId: doseEventId,
    );
    await _store.insertOutbox(e);
    return e;
  }
}
