import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/core/network/api_client.dart';
import 'package:meditrack/offline/local_store.dart';
import 'package:meditrack/offline/outbox.dart';
import 'package:meditrack/offline/sync_service.dart';

class FakeServer {
  final List<Map<String, dynamic>> received = [];
  final Set<String> seen = {};
  bool offline = false;
  Set<String> reject = {};

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    if (offline) throw ApiException("Can't reach the server.", isNetwork: true);
    final results = <Map<String, dynamic>>[];
    for (final e in body['events'] as List) {
      final id = e['client_event_id'] as String;
      received.add(Map<String, dynamic>.from(e));
      if (reject.contains(id)) {
        results.add({'client_event_id': id, 'result': 'rejected'});
      } else if (!seen.add(id)) {
        results.add({'client_event_id': id, 'result': 'duplicate'});
      } else {
        results.add({'client_event_id': id, 'result': 'applied'});
      }
    }
    return {'results': results};
  }
}

void main() {
  late MemoryLocalStore store;
  late FakeServer server;
  late Outbox outbox;
  late SyncService sync;
  var tick = 0;

  setUp(() {
    store = MemoryLocalStore();
    server = FakeServer();
    tick = 0;
    outbox = Outbox(store, newId: () => 'cid-${++tick}');
    sync = SyncService(store, server.post);
  });

  Future<OutboxEvent> record(String response, {int minute = 0}) => outbox.record(
        householdId: 'h1',
        scheduleId: 's1',
        scheduledFor: DateTime.utc(2026, 10, 26, 8),
        response: response,
        occurredAt: DateTime.utc(2026, 10, 26, 8, minute),
      );

  test('an offline response is stored locally and not lost', () async {
    server.offline = true;
    await record('taken');
    final report = await sync.flush();
    expect(report.offline, isTrue);
    expect((await store.pending()).length, 1);
    expect((await store.pending()).first.attempts, 1);
    expect((await store.pending()).first.lastError, isNotNull);
  });

  test('events sync when connectivity returns, exactly once', () async {
    server.offline = true;
    await record('acknowledged', minute: 1);
    await record('taken', minute: 12);
    await sync.flush();
    server.offline = false;
    final report = await sync.flush();
    expect(report.applied, 2);
    expect(await store.pending(), isEmpty);
    expect(server.received.map((e) => e['response']), ['acknowledged', 'taken']);
  });

  test('a retry after a lost response is a duplicate on the server, and clears the queue', () async {
    await record('taken');
    // Simulate: the server applied it but the response never reached the device.
    server.seen.add('cid-1');
    final report = await sync.flush();
    expect(report.duplicates, 1);
    expect(await store.pending(), isEmpty);
  });

  test('re-sending the same queue reuses the same client ids (idempotency keys)', () async {
    server.offline = true;
    await record('taken');
    await sync.flush();
    await sync.flush();
    server.offline = false;
    await sync.flush();
    server.offline = true;
    expect(server.seen, {'cid-1'});
  });

  test('a rejected event is parked, surfaced, and not retried forever', () async {
    await record('taken');
    server.reject = {'cid-1'};
    final r1 = await sync.flush();
    expect(r1.rejected, 1);
    expect(await store.pending(), isEmpty);
    expect((await store.rejected()).single.clientEventId, 'cid-1');
    server.received.clear();
    await sync.flush();
    expect(server.received, isEmpty);
  });

  test('device time is preserved so ordering survives delayed upload', () async {
    await record('taken', minute: 30);
    await sync.flush();
    expect(server.received.single['occurred_at'], '2026-10-26T08:30:00.000Z');
    expect(server.received.single['schedule_id'], 's1');
    expect(server.received.single['scheduled_for'], '2026-10-26T08:00:00.000Z');
  });

  test('events are grouped per household', () async {
    await outbox.record(householdId: 'h1', scheduleId: 's1', scheduledFor: DateTime.utc(2026, 10, 26, 8), response: 'taken', occurredAt: DateTime.utc(2026, 10, 26, 8, 5));
    await outbox.record(householdId: 'h2', scheduleId: 's9', scheduledFor: DateTime.utc(2026, 10, 26, 8), response: 'taken', occurredAt: DateTime.utc(2026, 10, 26, 8, 6));
    final paths = <String>[];
    final s = SyncService(store, (p, b) {
      paths.add(p);
      return server.post(p, b);
    });
    await s.flush();
    expect(paths.toSet(), {'/households/h1/sync/events', '/households/h2/sync/events'});
  });

  test('concurrent flushes do not double-send', () async {
    await record('taken');
    await Future.wait([sync.flush(), sync.flush()]);
    expect(server.received.length, 1);
  });

  test('pending count reflects the queue for the sync-status indicator', () async {
    await record('taken');
    await record('acknowledged');
    expect(await store.pendingCount(), 2);
  });
}
