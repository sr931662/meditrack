import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories.dart';
import '../auth/auth_controller.dart';
import '../doses/dose_models.dart';
import '../medications/med_models.dart';

String? _hid(Ref ref) {
  final a = ref.watch(authControllerProvider);
  return a is Authenticated ? a.ctx.householdId : null;
}

final seniorsProvider = FutureProvider.autoDispose<List<Senior>>((ref) async {
  final h = _hid(ref);
  return h == null ? [] : ref.read(careRepositoryProvider).seniors(h);
});

final medicationsProvider = FutureProvider.autoDispose<List<Medication>>((ref) async {
  final h = _hid(ref);
  return h == null ? [] : ref.read(careRepositoryProvider).medications(h);
});

final schedulesProvider = FutureProvider.autoDispose<List<Schedule>>((ref) async {
  final h = _hid(ref);
  return h == null ? [] : ref.read(careRepositoryProvider).schedules(h);
});

final escalationsProvider = FutureProvider.autoDispose<List<Escalation>>((ref) async {
  final h = _hid(ref);
  return h == null ? [] : ref.read(doseRepositoryProvider).escalations(h);
});

/// Dashboard filters: day, senior, medication, chart range.
class DashFilter {
  const DashFilter({required this.day, this.seniorId, this.medicationId, this.range = 7});
  final DateTime day;
  final String? seniorId;
  final String? medicationId;
  final int range;

  DashFilter copyWith({DateTime? day, Object? seniorId = _keep, Object? medicationId = _keep, int? range}) => DashFilter(
        day: day ?? this.day,
        seniorId: identical(seniorId, _keep) ? this.seniorId : seniorId as String?,
        medicationId: identical(medicationId, _keep) ? this.medicationId : medicationId as String?,
        range: range ?? this.range,
      );
  static const _keep = Object();
}

class DashFilterController extends Notifier<DashFilter> {
  @override
  DashFilter build() {
    final n = DateTime.now();
    return DashFilter(day: DateTime(n.year, n.month, n.day));
  }

  void set(DashFilter f) => state = f;
}

final dashFilterProvider = NotifierProvider<DashFilterController, DashFilter>(DashFilterController.new);

final dashboardProvider = FutureProvider.autoDispose<Dashboard>((ref) async {
  final h = _hid(ref);
  final f = ref.watch(dashFilterProvider);
  if (h == null) throw StateError('No household');
  return ref.read(doseRepositoryProvider).dashboard(h, f.day, seniorId: f.seniorId, medicationId: f.medicationId);
});

final trendProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final h = _hid(ref);
  final f = ref.watch(dashFilterProvider);
  if (h == null) return [];
  return ref.read(doseRepositoryProvider).trend(h, f.day, f.range, seniorId: f.seniorId, medicationId: f.medicationId);
});
