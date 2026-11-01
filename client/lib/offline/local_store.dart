import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'outbox.dart';

/// Device persistence: the outbox of unsent responses plus cached server snapshots so the senior
/// experience works without a connection.
abstract class LocalStore {
  Future<void> insertOutbox(OutboxEvent e);
  Future<void> updateOutbox(OutboxEvent e);
  Future<List<OutboxEvent>> pending();
  Future<List<OutboxEvent>> rejected();
  Future<List<OutboxEvent>> since(String householdId, DateTime sinceUtc);
  Future<int> pendingCount();
  Future<void> putSnapshot(String key, String json);
  Future<String?> getSnapshot(String key);
  Future<void> clearAll();
}

class MemoryLocalStore implements LocalStore {
  final Map<String, OutboxEvent> _out = {};
  final Map<String, String> _snap = {};

  @override
  Future<void> insertOutbox(OutboxEvent e) async => _out[e.clientEventId] = e;
  @override
  Future<void> updateOutbox(OutboxEvent e) async => _out[e.clientEventId] = e;
  @override
  Future<List<OutboxEvent>> pending() async =>
      _out.values.where((e) => e.status == OutboxStatus.pending).toList()..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  @override
  Future<List<OutboxEvent>> rejected() async => _out.values.where((e) => e.status == OutboxStatus.rejected).toList();
  @override
  Future<List<OutboxEvent>> since(String householdId, DateTime sinceUtc) async =>
      _out.values.where((e) => e.householdId == householdId && !e.occurredAt.isBefore(sinceUtc)).toList();
  @override
  Future<int> pendingCount() async => (await pending()).length;
  @override
  Future<void> putSnapshot(String key, String json) async => _snap[key] = json;
  @override
  Future<String?> getSnapshot(String key) async => _snap[key];
  @override
  Future<void> clearAll() async {
    _out.clear();
    _snap.clear();
  }
}

class SqfliteLocalStore implements LocalStore {
  SqfliteLocalStore._(this._db);
  final Database _db;

  static Future<SqfliteLocalStore> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'meditrack.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE outbox(
          client_event_id TEXT PRIMARY KEY, household_id TEXT NOT NULL, schedule_id TEXT NOT NULL,
          scheduled_for TEXT NOT NULL, response TEXT NOT NULL, occurred_at TEXT NOT NULL, dose_event_id TEXT,
          status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT)''');
        await db.execute('CREATE INDEX outbox_status ON outbox(status, occurred_at)');
        await db.execute('CREATE TABLE snapshots(key TEXT PRIMARY KEY, json TEXT NOT NULL)');
      },
    );
    return SqfliteLocalStore._(db);
  }

  @override
  Future<void> insertOutbox(OutboxEvent e) => _db.insert('outbox', e.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);

  @override
  Future<void> updateOutbox(OutboxEvent e) =>
      _db.update('outbox', e.toRow(), where: 'client_event_id = ?', whereArgs: [e.clientEventId]);

  Future<List<OutboxEvent>> _q(String where, List<Object?> args) async =>
      [for (final r in await _db.query('outbox', where: where, whereArgs: args, orderBy: 'occurred_at')) OutboxEvent.fromRow(r)];

  @override
  Future<List<OutboxEvent>> pending() => _q('status = ?', ['pending']);
  @override
  Future<List<OutboxEvent>> rejected() => _q('status = ?', ['rejected']);
  @override
  Future<List<OutboxEvent>> since(String householdId, DateTime sinceUtc) =>
      _q('household_id = ? AND occurred_at >= ?', [householdId, sinceUtc.toUtc().toIso8601String()]);

  @override
  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery("SELECT COUNT(*) FROM outbox WHERE status = 'pending'")) ?? 0;

  @override
  Future<void> putSnapshot(String key, String json) =>
      _db.insert('snapshots', {'key': key, 'json': json}, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<String?> getSnapshot(String key) async {
    final r = await _db.query('snapshots', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['json'] as String;
  }

  @override
  Future<void> clearAll() async {
    await _db.delete('outbox');
    await _db.delete('snapshots');
  }
}
