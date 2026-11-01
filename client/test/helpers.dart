import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/core/network/api_client.dart';
import 'package:meditrack/core/providers.dart';
import 'package:meditrack/core/storage/token_store.dart';
import 'package:meditrack/core/theme/app_theme.dart';
import 'package:meditrack/features/auth/auth_controller.dart';
import 'package:meditrack/features/auth/auth_models.dart';
import 'package:meditrack/features/home/today_controller.dart';
import 'package:meditrack/features/medications/med_models.dart';
import 'package:meditrack/offline/local_store.dart';

class FakeAuth extends AuthController {
  FakeAuth(this._state);
  final AuthState _state;
  @override
  AuthState build() => _state;
}

class FakeToday extends TodayController {
  FakeToday(this._state);
  final TodayState _state;
  @override
  Future<TodayState> build() async => _state;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> respond(DoseView d, String response) async {}
}

class MemoryIdentityCache implements IdentityCache {
  Me? me;
  @override
  Future<Me?> read() async => me;
  @override
  Future<void> write(Me m) async => me = m;
  @override
  Future<void> clear() async => me = null;
}

Me meOf({String? platformRole, Set<String> platform = const {}, List<Membership> memberships = const []}) =>
    Me(id: 'u1', email: 'u@x.com', fullName: 'Margaret Lee', platformRole: platformRole, platformPermissions: platform, memberships: memberships);

Authenticated authed(Me me) => Authenticated(me, resolveContext(me));

Membership seniorMembership() => Membership(householdId: 'h1', householdName: 'Lee', role: 'senior', permissions: {'doses.respond', 'medications.read'}, seniorId: 's1');
Membership ownerMembership() => Membership(householdId: 'h1', householdName: 'Lee', role: 'owner', permissions: {
      'adherence.read', 'medications.read', 'medications.create', 'medications.update', 'medications.delete', 'schedules.read', 'schedules.manage',
      'escalation.read', 'escalation.acknowledge', 'escalation.resolve', 'escalation.manage', 'verification.review', 'members.manage', 'seniors.manage',
    });
Membership caregiverMembership(Set<String> perms) => Membership(householdId: 'h1', householdName: 'Lee', role: 'caregiver', permissions: perms);

final medA = Medication(id: 'm1', seniorId: 's1', name: 'Amlodipine', strength: '5 mg', dosageForm: 'tablet', quantity: '1 tablet', prescribedInstructions: 'After breakfast', appearance: 'blue');
Schedule schedA() => Schedule(id: 'sc1', medicationId: 'm1', seniorId: 's1', times: ['08:00'], weekdays: [0, 1, 2, 3, 4, 5, 6], startDate: DateTime(2026, 1, 1), timezone: 'UTC');

bool _fontLoaded = false;

/// Use the real Figtree metrics so layout tests reflect the device, not the wide default test font.
Future<void> loadFonts() async {
  if (_fontLoaded) return;
  final loader = FontLoader('Figtree')..addFont(rootBundle.load('assets/fonts/Figtree.ttf'));
  await loader.load();
  _fontLoaded = true;
}

Future<void> pumpScreen(WidgetTester tester, Widget child, {List<Override> overrides = const []}) async {
  await loadFonts();
  tester.view.physicalSize = const Size(1320, 2800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [localStoreProvider.overrideWithValue(MemoryLocalStore()), ...overrides],
    child: MaterialApp(theme: buildTheme(), home: Scaffold(body: child)),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

typedef Handler = FutureOr<ResponseBody> Function(RequestOptions o);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Handler handler;
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

ApiClient fakeApi(FakeAdapter adapter, {TokenStore? tokens}) {
  final c = ApiClient(baseUrl: 'http://x/api/v1', tokens: tokens ?? MemoryTokenStore());
  c.rawDio.httpClientAdapter = adapter;
  c.rawRefreshDio.httpClientAdapter = adapter;
  return c;
}
