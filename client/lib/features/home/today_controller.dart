import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../data/repositories.dart';
import '../../offline/outbox.dart';
import '../../offline/reminder_planner.dart';
import '../auth/auth_controller.dart';
import '../doses/dose_logic.dart';
import '../doses/dose_models.dart';
import '../medications/med_models.dart';

/// One scheduled dose as the senior sees it, assembled from three sources of truth:
/// the cached schedule, responses queued on this device, and (when online) the server's record.
class DoseView {
  DoseView({
    required this.medication,
    required this.schedule,
    required this.scheduledUtc,
    this.acknowledgedAt,
    this.reportedTakenAt,
    this.snoozedUntil,
    this.helpRequested = false,
    this.syncPending = false,
    this.server,
  });

  final Medication medication;
  final Schedule schedule;
  final DateTime scheduledUtc;
  DateTime? acknowledgedAt;
  DateTime? reportedTakenAt;
  DateTime? snoozedUntil;
  bool helpRequested;
  bool syncPending;
  DoseEvent? server;

  String get key => '${schedule.id}|${scheduledUtc.toIso8601String()}';
  DateTime get local => scheduledUtc.toLocal();
  bool get packagingMatched => server?.packagingMatched ?? false;

  DoseFacts get facts => DoseFacts(
        scheduledFor: scheduledUtc,
        snoozedUntil: snoozedUntil,
        reportedTakenAt: reportedTakenAt,
        caregiverStatus: server?.caregiverStatus,
        escalated: server?.escalation != null && server!.escalation!.status != 'resolved',
        resolved: server?.displayStatus == 'resolved',
        packagingMatched: packagingMatched,
      );

  DoseUi ui(DateTime now) => deriveDoseUi(facts, now.toUtc());
}

class TodayState {
  const TodayState({required this.doses, required this.fromCache, required this.pendingSync});
  final List<DoseView> doses;
  final bool fromCache; // true when the server could not be reached and cached data is shown
  final int pendingSync;

  DoseView? next(DateTime now) {
    final open = doses.where((d) => doseNeedsAttention(d.ui(now))).toList();
    if (open.isNotEmpty) return open.first;
    final up = doses.where((d) => d.ui(now) == DoseUi.upcoming || d.ui(now) == DoseUi.snoozed);
    return up.isEmpty ? null : up.first;
  }
}

const snoozeMinutes = 10; // keep equal to the server's SNOOZE_MIN

class TodayController extends AsyncNotifier<TodayState> {
  @override
  Future<TodayState> build() => _load();

  Future<void> refresh() async => state = AsyncData(await _load());

  Future<TodayState> _load() async {
    final auth = ref.read(authControllerProvider);
    if (auth is! Authenticated || auth.ctx.householdId == null) return const TodayState(doses: [], fromCache: false, pendingSync: 0);
    final hid = auth.ctx.householdId!;
    final sid = auth.ctx.seniorId;
    final store = ref.read(localStoreProvider);
    final care = ref.read(careRepositoryProvider);
    final doseRepo = ref.read(doseRepositoryProvider);

    var fromCache = false;
    List<Medication> meds;
    List<Schedule> schedules;
    var events = <DoseEvent>[];
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    try {
      meds = await care.medications(hid, seniorId: sid);
      schedules = await care.schedules(hid, seniorId: sid);
      await store.putSnapshot('meds:$hid', jsonEncode([for (final m in meds) m.toJson()]));
      await store.putSnapshot('schedules:$hid', jsonEncode([for (final s in schedules) s.toJson()]));
      try {
        final days = {dayStart.toUtc(), dayEnd.subtract(const Duration(seconds: 1)).toUtc()}.map((d) => DateTime.utc(d.year, d.month, d.day));
        for (final d in days.toSet()) {
          events.addAll(await doseRepo.eventsOn(hid, d, seniorId: sid));
        }
      } on ApiException {
        events = []; // schedule is still correct; only server-side status is unavailable
      }
    } on ApiException catch (e) {
      if (!e.isNetwork && e.status != null) rethrow;
      fromCache = true;
      meds = _decode(await store.getSnapshot('meds:$hid'), Medication.fromJson);
      schedules = _decode(await store.getSnapshot('schedules:$hid'), Schedule.fromJson);
    }

    final medById = {for (final m in meds) m.id: m};
    final serverByKey = {for (final e in events) '${e.scheduleId}|${e.scheduledFor.toUtc().millisecondsSinceEpoch}': e};
    final outbox = await store.since(hid, dayStart.subtract(const Duration(days: 1)).toUtc());

    final doses = <DoseView>[];
    for (final s in schedules) {
      final m = medById[s.medicationId];
      if (m == null || !m.isActive) continue;
      for (final at in occurrencesBetween(s, dayStart.toUtc(), dayEnd.toUtc())) {
        if (at.isAtSameMomentAs(dayEnd.toUtc())) continue;
        final v = DoseView(medication: m, schedule: s, scheduledUtc: at, server: serverByKey['${s.id}|${at.millisecondsSinceEpoch}']);
        final ev = v.server;
        if (ev != null) {
          v.acknowledgedAt = ev.acknowledgedAt;
          v.reportedTakenAt = ev.userReportedTakenAt;
          v.snoozedUntil = ev.snoozedUntil;
          v.helpRequested = ev.helpRequestedAt != null;
        }
        for (final o in outbox.where((o) => o.scheduleId == s.id && o.scheduledFor.isAtSameMomentAs(at) && o.status != OutboxStatus.rejected)) {
          if (o.status == OutboxStatus.pending) v.syncPending = true;
          switch (o.response) {
            case 'acknowledged':
              v.acknowledgedAt ??= o.occurredAt;
            case 'taken':
              v.reportedTakenAt ??= o.occurredAt;
            case 'remind_later':
              v.snoozedUntil = o.occurredAt.add(const Duration(minutes: snoozeMinutes));
            default:
              v.helpRequested = true;
          }
        }
        doses.add(v);
      }
    }
    doses.sort((a, b) => a.scheduledUtc.compareTo(b.scheduledUtc));
    return TodayState(doses: doses, fromCache: fromCache, pendingSync: await store.pendingCount());
  }

  List<T> _decode<T>(String? raw, T Function(Map<String, dynamic>) f) =>
      raw == null ? <T>[] : [for (final j in jsonDecode(raw) as List) f(Map<String, dynamic>.from(j))];

  /// Recording a response only needs the local write to succeed; upload happens in the background.
  Future<void> respond(DoseView d, String response) async {
    final auth = ref.read(authControllerProvider) as Authenticated;
    await ref.read(outboxProvider).record(
          householdId: auth.ctx.householdId!,
          scheduleId: d.schedule.id,
          scheduledFor: d.scheduledUtc,
          response: response,
          occurredAt: DateTime.now().toUtc(),
          doseEventId: d.server?.id,
        );
    await refresh();
    unawaited(ref.read(syncServiceProvider).flush().then((_) => refresh()).catchError((_) {}));
  }
}

final todayProvider = AsyncNotifierProvider<TodayController, TodayState>(TodayController.new);
