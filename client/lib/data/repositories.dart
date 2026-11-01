import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/providers.dart';
import '../features/doses/dose_models.dart';
import '../features/medications/med_models.dart';

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Household data: medications, schedules, seniors, members and the escalation policy.
class CareRepository {
  CareRepository(this._api);
  final ApiClient _api;

  String _h(String hid) => '/households/$hid';

  Future<List<Medication>> medications(String hid, {String? seniorId}) async {
    final r = await _api.get('${_h(hid)}/medications', query: {'limit': 200, 'senior_id': ?seniorId});
    return [for (final m in r['items']) Medication.fromJson(m)];
  }

  Future<List<Schedule>> schedules(String hid, {String? seniorId}) async {
    final r = await _api.get('${_h(hid)}/schedules', query: {'limit': 200, 'senior_id': ?seniorId});
    return [for (final m in r['items']) Schedule.fromJson(m)];
  }

  Future<List<Senior>> seniors(String hid) async => [for (final s in await _api.get('${_h(hid)}/seniors')) Senior.fromJson(s)];

  Future<Medication> createMedication(String hid, Map<String, dynamic> body) async => Medication.fromJson(await _api.post('${_h(hid)}/medications', data: body));
  Future<Medication> updateMedication(String hid, String id, Map<String, dynamic> body) async =>
      Medication.fromJson(await _api.patch('${_h(hid)}/medications/$id', data: body));
  Future<void> deleteMedication(String hid, String id) => _api.delete('${_h(hid)}/medications/$id');

  Future<Schedule> createSchedule(String hid, Map<String, dynamic> body) async => Schedule.fromJson(await _api.post('${_h(hid)}/schedules', data: body));
  Future<Schedule> updateSchedule(String hid, String id, Map<String, dynamic> body) async =>
      Schedule.fromJson(await _api.patch('${_h(hid)}/schedules/$id', data: body));

  Future<Map<String, dynamic>> createHousehold(String name) async => Map<String, dynamic>.from(await _api.post('/households', data: {'name': name}));

  Future<Senior> createSenior(String hid, Map<String, dynamic> body) async => Senior.fromJson(await _api.post('${_h(hid)}/seniors', data: body));

  Future<List<Map<String, dynamic>>> members(String hid) async => List<Map<String, dynamic>>.from(await _api.get('${_h(hid)}/members'));
  Future<void> addMember(String hid, String email, List<String> permissions) =>
      _api.post('${_h(hid)}/members', data: {'email': email, 'role': 'caregiver', 'permissions': permissions});
  Future<void> setMemberPermissions(String hid, String memberId, List<String> permissions) =>
      _api.patch('${_h(hid)}/members/$memberId', data: {'permissions': permissions});
  Future<void> removeMember(String hid, String memberId) => _api.delete('${_h(hid)}/members/$memberId');

  Future<Map<String, dynamic>> policy(String hid) async => Map<String, dynamic>.from(await _api.get('${_h(hid)}/escalation-policy'));
  Future<void> savePolicy(String hid, Map<String, dynamic> body) => _api.put('${_h(hid)}/escalation-policy', data: body);
}

/// Dose events, verification, escalations, dashboard and notifications.
class DoseRepository {
  DoseRepository(this._api);
  final ApiClient _api;

  String _h(String hid) => '/households/$hid';

  Future<List<DoseEvent>> eventsOn(String hid, DateTime day, {String? seniorId}) async {
    final r = await _api.get('${_h(hid)}/dose-events', query: {'date': _day(day.toUtc()), 'limit': 200, 'senior_id': ?seniorId});
    return [for (final e in r['items']) DoseEvent.fromJson(e)];
  }

  Future<DoseEvent> event(String hid, String id) async => DoseEvent.fromJson(await _api.get('${_h(hid)}/dose-events/$id'));

  Future<Verification> verify(String hid, String eventId, {String? text, String? barcode}) async => Verification.fromJson(
      await _api.post('${_h(hid)}/dose-events/$eventId/verifications', data: {if (text != null && text.isNotEmpty) 'extracted_text': text, 'barcode': ?barcode}));

  Future<void> caregiverConfirm(String hid, String eventId, String status, String note) =>
      _api.post('${_h(hid)}/dose-events/$eventId/caregiver-confirm', data: {'status': status, 'note': note});
  Future<void> requestVerification(String hid, String eventId) => _api.post('${_h(hid)}/dose-events/$eventId/request-verification');

  Future<List<Escalation>> escalations(String hid, {String? status}) async {
    final r = await _api.get('${_h(hid)}/escalations', query: {'limit': 100, 'status': ?status});
    return [for (final e in r['items']) Escalation.fromJson(e)];
  }

  Future<(Escalation, DoseEvent)> escalation(String hid, String id) async {
    final r = await _api.get('${_h(hid)}/escalations/$id');
    return (Escalation.fromJson(r), DoseEvent.fromJson(r['event']));
  }

  Future<void> acknowledge(String hid, String id) => _api.post('${_h(hid)}/escalations/$id/acknowledge');
  Future<void> addNote(String hid, String id, String note) => _api.post('${_h(hid)}/escalations/$id/notes', data: {'note': note});
  Future<void> resolve(String hid, String id, String outcome, String note) =>
      _api.post('${_h(hid)}/escalations/$id/resolve', data: {'outcome': outcome, 'note': note});

  Future<Dashboard> dashboard(String hid, DateTime day, {String? seniorId, String? medicationId}) async => Dashboard.fromJson(await _api.get(
      '${_h(hid)}/dashboard',
      query: {'date': _day(day), 'senior_id': ?seniorId, 'medication_id': ?medicationId}));

  Future<List<Map<String, dynamic>>> trend(String hid, DateTime end, int days, {String? seniorId, String? medicationId}) async {
    final r = await _api.get('${_h(hid)}/dashboard/trend',
        query: {'date': _day(end), 'days': days, 'senior_id': ?seniorId, 'medication_id': ?medicationId});
    return List<Map<String, dynamic>>.from(r['days']);
  }

  Future<List<AppNotification>> notifications(String hid) async {
    final r = await _api.get('${_h(hid)}/notifications', query: {'limit': 100});
    return [for (final n in r['items']) AppNotification.fromJson(n)];
  }
}

/// Platform administration.
class AdminRepository {
  AdminRepository(this._api);
  final ApiClient _api;

  Future<List<Map<String, dynamic>>> users({String? q}) async =>
      List<Map<String, dynamic>>.from((await _api.get('/admin/users', query: {'limit': 100, if (q != null && q.isNotEmpty) 'q': q}))['items']);
  Future<void> createUser(Map<String, dynamic> body) => _api.post('/admin/users', data: body);
  Future<void> disable(String id, String reason) => _api.post('/admin/users/$id/disable', data: {'reason': reason});
  Future<void> enable(String id) => _api.post('/admin/users/$id/enable');
  Future<void> setPlatformRole(String id, String role) => _api.patch('/admin/users/$id', data: {'platform_role': role});

  Future<Map<String, dynamic>> roles() async => Map<String, dynamic>.from(await _api.get('/admin/roles'));
  Future<void> setRolePermissions(String role, List<String> perms) => _api.put('/admin/roles/$role/permissions', data: {'permissions': perms});

  Future<List<Map<String, dynamic>>> auditLogs({String? action}) async =>
      List<Map<String, dynamic>>.from((await _api.get('/admin/audit-logs', query: {'limit': 100, if (action != null && action.isNotEmpty) 'action': action}))['items']);

  Future<Map<String, dynamic>> config() async => Map<String, dynamic>.from((await _api.get('/admin/config'))['values']);
  Future<void> saveConfig(Map<String, dynamic> values) => _api.put('/admin/config', data: {'values': values});
  Future<Map<String, dynamic>> stats() async => Map<String, dynamic>.from(await _api.get('/admin/stats'));
  Future<List<Map<String, dynamic>>> households() async => List<Map<String, dynamic>>.from((await _api.get('/admin/households', query: {'limit': 100}))['items']);
  Future<void> grantSupportAccess(String householdId, String reason, int minutes) =>
      _api.post('/admin/support-access', data: {'household_id': householdId, 'reason': reason, 'minutes': minutes});
}

final careRepositoryProvider = Provider((ref) => CareRepository(ref.read(apiClientProvider)));
final doseRepositoryProvider = Provider((ref) => DoseRepository(ref.read(apiClientProvider)));
final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.read(apiClientProvider)));
