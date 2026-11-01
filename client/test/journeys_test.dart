import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/core/providers.dart';
import 'package:meditrack/core/storage/token_store.dart';
import 'package:meditrack/data/repositories.dart';
import 'package:meditrack/features/admin/admin_shell.dart';
import 'package:meditrack/features/auth/login_screen.dart';
import 'package:meditrack/features/doses/dose_models.dart';
import 'package:meditrack/features/home/dose_detail_screen.dart';
import 'package:meditrack/features/home/doses_list_screen.dart';
import 'package:meditrack/features/home/home_screen.dart';
import 'package:meditrack/features/home/today_controller.dart';
import 'package:meditrack/features/shell/caregiver_shell.dart';
import 'package:meditrack/features/verification/verify_screen.dart';
import 'package:meditrack/services/scan_service.dart';
import 'package:meditrack/services/service_providers.dart';
import 'package:meditrack/services/speech_service.dart';

import 'helpers.dart';

class _NoSpeech implements SpeechService {
  @override
  Future<bool> get canListen async => false;
  @override
  Future<void> listen(void Function(String, bool) onResult, void Function(String) onError) async {}
  @override
  Future<void> speak(String text, {double rate = .5}) async {}
  @override
  Future<void> stopListening() async {}
  @override
  Future<void> stopSpeaking() async {}
}

DoseEvent event_() => event();

DoseEvent event({String? caregiver, bool escalated = false, bool matched = false, DateTime? reported}) => DoseEvent(
      id: 'e1',
      scheduleId: 'sc1',
      medicationId: 'm1',
      seniorId: 's1',
      scheduledFor: DateTime.now().toUtc(),
      displayStatus: 'x',
      packagingMatched: matched,
      userReportedTakenAt: reported,
      caregiverStatus: caregiver,
      escalation: escalated
          ? Escalation(id: 'x1', doseEventId: 'e1', status: 'open', priority: 'normal', reason: 'no_confirmation', triggeredAt: DateTime.now())
          : null,
    );

DoseView dose({DoseEvent? server, DateTime? reported, bool pending = false}) {
  final at = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
  return DoseView(medication: medA, schedule: schedA(), scheduledUtc: at, reportedTakenAt: reported, syncPending: pending, server: server);
}

List<Override> seniorOverrides(TodayState s) => [
      authControllerProvider.overrideWith(() => FakeAuth(authed(meOf(memberships: [seniorMembership()])))),
      todayProvider.overrideWith(() => FakeToday(s)),
      speechServiceProvider.overrideWithValue(_NoSpeech()),
    ];

void main() {
  group('senior home wording', () {
    testWidgets('a self-reported dose reads "Reported taken", never verified/confirmed/missed', (tester) async {
      final s = TodayState(doses: [dose(reported: DateTime.now())], fromCache: false, pendingSync: 0);
      await pumpScreen(tester, SeniorHomeScreen(onOpenProfile: () {}), overrides: seniorOverrides(s));
      expect(find.text('Reported taken'), findsWidgets);
      expect(find.textContaining('Missed'), findsNothing);
      expect(find.textContaining('missed'), findsNothing);
      expect(find.text('Taken'), findsNothing);
    });

    testWidgets('an escalated dose says the caregiver was alerted and does not call it missed', (tester) async {
      final s = TodayState(doses: [dose(server: event(escalated: true))], fromCache: false, pendingSync: 0);
      await pumpScreen(tester, SeniorHomeScreen(onOpenProfile: () {}), overrides: seniorOverrides(s));
      expect(find.text('Caregiver alerted'), findsWidgets);
      expect(find.textContaining('issed'), findsNothing);
    });

    testWidgets('offline: shows saved schedule + waiting responses, reminders still described as working', (tester) async {
      final s = TodayState(doses: [dose(pending: true)], fromCache: true, pendingSync: 2);
      await pumpScreen(tester, SeniorHomeScreen(onOpenProfile: () {}), overrides: seniorOverrides(s));
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(find.textContaining('2 responses are saved'), findsOneWidget);
    });

    testWidgets('seniors only get Respond actions on the detail page: taken, check box, remind, help', (tester) async {
      final d = dose();
      final s = TodayState(doses: [d], fromCache: false, pendingSync: 0);
      await pumpScreen(tester, DoseDetailScreen(doseKey: d.key), overrides: seniorOverrides(s));
      expect(find.text("I've taken it"), findsOneWidget);
      expect(find.text('Check box'), findsOneWidget);
      expect(find.text('Remind later'), findsOneWidget);
      expect(find.text('I need help'), findsOneWidget);
      expect(find.textContaining('Edit'), findsNothing);
      expect(find.textContaining('Remove'), findsNothing);
    });

    testWidgets('a packaging match is shown as a separate fact with a clear disclaimer', (tester) async {
      final d = dose(server: event(matched: true));
      final s = TodayState(doses: [d], fromCache: false, pendingSync: 0);
      await pumpScreen(tester, DoseDetailScreen(doseKey: d.key), overrides: [...seniorOverrides(s), doseRepositoryProvider.overrideWithValue(_FakeDoseRepo(null))]);
      expect(find.text('Packaging matched'), findsOneWidget);
      expect(find.textContaining('does not show the medicine was taken'), findsOneWidget);
      expect(find.text('Awaiting'), findsOneWidget); // still awaiting: a match is not a dose taken
    });

    testWidgets('medicines tab is read-only for seniors (no add/edit)', (tester) async {
      final s = TodayState(doses: [dose()], fromCache: false, pendingSync: 0);
      await pumpScreen(tester, const DosesListScreen(), overrides: seniorOverrides(s));
      expect(find.text('Add'), findsNothing);
    });
  });

  group('verification screen', () {
    testWidgets('a match says it is not proof of ingestion and offers a separate "I took it" action', (tester) async {
      final d = dose(server: event());
      final s = TodayState(doses: [d], fromCache: false, pendingSync: 0);
      final repo = _FakeDoseRepo(Verification(status: 'match', confidence: .97, reasons: const [], nextAction: 'none', provider: 'text-match', model: 'rules-v1', createdAt: DateTime.now()));
      await pumpScreen(tester, VerifyScreen(doseKey: d.key), overrides: [
        ...seniorOverrides(s),
        doseRepositoryProvider.overrideWithValue(repo),
        scanServiceProvider.overrideWithValue(_FakeScan('AMLODIPINE TABLETS 5 mg')),
      ]);
      await tester.tap(find.text('Take a photo of the label'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('does not show that you have taken it'), findsOneWidget);
      expect(find.text('Tell us I took it'), findsOneWidget);
      expect(find.textContaining('97%'), findsOneWidget);
      expect(find.textContaining('text-match'), findsOneWidget);
    });

    testWidgets('a non-match offers caregiver help and never offers to record the dose', (tester) async {
      final d = dose(server: event());
      final s = TodayState(doses: [d], fromCache: false, pendingSync: 0);
      final repo = _FakeDoseRepo(Verification(status: 'no_match', confidence: .2, reasons: const ['Medicine name Amlodipine not found'], nextAction: 'ask_caregiver', provider: 'text-match', model: 'rules-v1', createdAt: DateTime.now()));
      await pumpScreen(tester, VerifyScreen(doseKey: d.key), overrides: [
        ...seniorOverrides(s),
        doseRepositoryProvider.overrideWithValue(repo),
        scanServiceProvider.overrideWithValue(_FakeScan('METFORMIN 500 mg')),
      ]);
      await tester.tap(find.text('Take a photo of the label'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Ask my caregiver to check'), findsOneWidget);
      expect(find.text('Tell us I took it'), findsNothing);
      expect(find.textContaining('Nothing has been recorded as taken'), findsOneWidget);
    });

    testWidgets('verification needs a server record: explains it instead of pretending', (tester) async {
      final d = dose(); // no server event yet (never synced)
      final s = TodayState(doses: [d], fromCache: true, pendingSync: 0);
      await pumpScreen(tester, VerifyScreen(doseKey: d.key), overrides: [
        ...seniorOverrides(s),
        scanServiceProvider.overrideWithValue(_FakeScan('AMLODIPINE 5 mg')),
      ]);
      await tester.tap(find.text('Take a photo of the label'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('needs an internet connection'), findsOneWidget);
    });
  });

  group('role based navigation', () {
    testWidgets('caregiver with read-only grants only sees tabs for what they can use', (tester) async {
      final me = meOf(memberships: [caregiverMembership({'medications.read'})]);
      await pumpScreen(tester, const CaregiverShell(), overrides: [authControllerProvider.overrideWith(() => FakeAuth(authed(me)))]);
      expect(find.text('Medicines'), findsWidgets);
      expect(find.text('Overview'), findsNothing);
      expect(find.text('Alerts'), findsNothing);
      expect(find.text('People'), findsNothing);
    });

    testWidgets('household owner sees every caregiver tab', (tester) async {
      final owner = ownerMembership();
      final me = meOf(memberships: [owner]);
      await pumpScreen(tester, const CaregiverShell(), overrides: [authControllerProvider.overrideWith(() => FakeAuth(authed(me)))]);
      for (final t in ['Overview', 'Medicines', 'Alerts', 'People', 'Profile']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
    });

    testWidgets('operations admin sees only the tabs their permissions allow', (tester) async {
      final me = meOf(platformRole: 'ops_admin', platform: {'users.read', 'households.read'});
      await pumpScreen(tester, const AdminShell(), overrides: [authControllerProvider.overrideWith(() => FakeAuth(authed(me)))]);
      expect(find.text('Users'), findsWidgets);
      expect(find.text('Roles'), findsNothing);
      expect(find.text('Audit'), findsNothing);
    });

    testWidgets('a caregiver with no household yet is taken to household setup', (tester) async {
      final me = meOf();
      await pumpScreen(tester, const CaregiverShell(), overrides: [authControllerProvider.overrideWith(() => FakeAuth(authed(me)))]);
      expect(find.text('Set up your household'), findsOneWidget);
    });
  });

  group('sign in', () {
    testWidgets('wrong password shows the server message and stays signed out', (tester) async {
      final adapter = FakeAdapter((o) => jsonBody(401, {'error': {'code': 'unauthorized', 'message': 'Incorrect email or password'}}));
      await pumpScreen(tester, const LoginScreen(), overrides: [
        apiClientProvider.overrideWithValue(fakeApi(adapter)),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        identityCacheProvider.overrideWithValue(MemoryIdentityCache()),
      ]);
      await tester.enterText(find.byType(TextField).at(0), 'a@x.com');
      await tester.enterText(find.byType(TextField).at(1), 'bad-password-1');
      await tester.tap(find.text('Sign in').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Incorrect email or password'), findsOneWidget);
    });

    testWidgets('empty form asks for details without calling the server', (tester) async {
      final adapter = FakeAdapter((o) => jsonBody(500, {}));
      await pumpScreen(tester, const LoginScreen(), overrides: [
        apiClientProvider.overrideWithValue(fakeApi(adapter)),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        identityCacheProvider.overrideWithValue(MemoryIdentityCache()),
      ]);
      await tester.tap(find.text('Sign in').last);
      await tester.pump();
      expect(find.text('Enter your email and password.'), findsOneWidget);
      expect(adapter.calls, isEmpty);
    });
  });
}

class _FakeScan implements ScanService {
  _FakeScan(this.text);
  final String text;
  @override
  Future<String?> readPackagingText() async => text;
  @override
  Future<String?> scanBarcode(BuildContext context) async => null;
}

class _FakeDoseRepo implements DoseRepository {
  _FakeDoseRepo(this.result) : history = null;
  final Verification? result;
  final DoseEvent? history;
  @override
  Future<DoseEvent> event(String hid, String id) async => history ?? event_();
  @override
  Future<Verification> verify(String hid, String eventId, {String? text, String? barcode}) async => result!;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}
