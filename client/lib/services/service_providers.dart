import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../core/providers.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import '../features/home/today_controller.dart';
import '../features/medications/med_models.dart';
import '../offline/reminder_planner.dart';
import 'reminder_service.dart';
import 'scan_service.dart';
import 'speech_service.dart';

final speechServiceProvider = Provider<SpeechService>((_) => DeviceSpeechService());
final reminderServiceProvider = Provider<ReminderService>((_) => ReminderService());
final scanServiceProvider = Provider<ScanService>((_) => DeviceScanService());

class AppSettings {
  const AppSettings({this.largeText = false, this.reduceMotion = false, this.spoken = true, this.voiceSpeed = 'Normal'});
  final bool largeText;
  final bool reduceMotion;
  final bool spoken;
  final String voiceSpeed; // Slower | Normal | Faster

  double get ttsRate => switch (voiceSpeed) { 'Slower' => .38, 'Faster' => .62, _ => .5 };

  AppSettings copyWith({bool? largeText, bool? reduceMotion, bool? spoken, String? voiceSpeed}) => AppSettings(
        largeText: largeText ?? this.largeText,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        spoken: spoken ?? this.spoken,
        voiceSpeed: voiceSpeed ?? this.voiceSpeed,
      );

  Map<String, dynamic> toJson() => {'largeText': largeText, 'reduceMotion': reduceMotion, 'spoken': spoken, 'voiceSpeed': voiceSpeed};
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
      largeText: j['largeText'] ?? false, reduceMotion: j['reduceMotion'] ?? false, spoken: j['spoken'] ?? true, voiceSpeed: j['voiceSpeed'] ?? 'Normal');
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  Future<void> load() async {
    final raw = await ref.read(localStoreProvider).getSnapshot('settings');
    if (raw != null) state = AppSettings.fromJson(jsonDecode(raw));
  }

  Future<void> update(AppSettings s) async {
    state = s;
    await ref.read(localStoreProvider).putSnapshot('settings', jsonEncode(s.toJson()));
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Rebuilds the on-device alarm schedule from the cached schedules. Safe to call often.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

Future<int> rescheduleLocalReminders(Reader read) async {
  final auth = read(authControllerProvider);
  if (auth is! Authenticated || auth.ctx.mode != AppMode.senior || auth.ctx.householdId == null) return 0;
  final hid = auth.ctx.householdId!;
  final store = read(localStoreProvider);
  final medsRaw = await store.getSnapshot('meds:$hid');
  final schedRaw = await store.getSnapshot('schedules:$hid');
  if (medsRaw == null || schedRaw == null) return 0;
  final meds = {
    for (final j in jsonDecode(medsRaw) as List) (j['id'] as String): Medication.fromJson(Map<String, dynamic>.from(j)),
  };
  final schedules = [for (final j in jsonDecode(schedRaw) as List) Schedule.fromJson(Map<String, dynamic>.from(j))];
  final plans = planReminders(schedules: schedules, medications: meds, nowUtc: DateTime.now().toUtc());
  return read(reminderServiceProvider).apply(plans);
}

/// Keeps reminders, the outbox and the "today" list consistent: runs on start, resume and reconnect.
Future<void> syncEverything(Reader read) async {
  try {
    await read(syncServiceProvider).flush();
  } catch (_) {}
  try {
    await read(todayProvider.notifier).refresh();
  } catch (_) {}
  try {
    await rescheduleLocalReminders(read);
  } catch (_) {}
}
