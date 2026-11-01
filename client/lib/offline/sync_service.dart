import '../core/network/api_client.dart';
import 'local_store.dart';
import 'outbox.dart';

typedef PostJson = Future<dynamic> Function(String path, Map<String, dynamic> body);

class SyncReport {
  const SyncReport({this.applied = 0, this.duplicates = 0, this.rejected = 0, this.failed = 0, this.offline = false});
  final int applied, duplicates, rejected, failed;
  final bool offline;
  bool get hadWork => applied + duplicates + rejected + failed > 0;
}

/// Uploads the outbox. Delivery is at-least-once; the server de-duplicates on `client_event_id`, so the
/// net effect is exactly-once. An event leaves the queue only when the server answered for it.
class SyncService {
  SyncService(this._store, this._post);
  final LocalStore _store;
  final PostJson _post;
  Future<SyncReport>? _inflight;

  /// Concurrent callers (connectivity change + app resume + manual retry) share one run.
  Future<SyncReport> flush() => _inflight ??= _run().whenComplete(() => _inflight = null);

  Future<SyncReport> _run() async {
    var applied = 0, dup = 0, rej = 0, failed = 0;
    var offline = false;
    final byHousehold = <String, List<OutboxEvent>>{};
    for (final e in await _store.pending()) {
      byHousehold.putIfAbsent(e.householdId, () => []).add(e);
    }
    for (final entry in byHousehold.entries) {
      try {
        final res = await _post('/households/${entry.key}/sync/events', {
          'events': [for (final e in entry.value) e.toSyncJson()],
        });
        final results = {for (final r in (res['results'] as List)) r['client_event_id'] as String: r['result'] as String};
        for (final e in entry.value) {
          switch (results[e.clientEventId]) {
            case 'applied':
              e.status = OutboxStatus.synced;
              applied++;
            case 'duplicate':
              e.status = OutboxStatus.synced;
              dup++;
            case 'rejected':
              e.status = OutboxStatus.rejected;
              e.lastError = 'Rejected by the server';
              rej++;
            default: // no answer for this id: keep it and try again
              e.attempts++;
              failed++;
          }
          await _store.updateOutbox(e);
        }
      } on ApiException catch (ex) {
        final permanent = ex.status != null && ex.status! >= 400 && ex.status! < 500 && ex.status != 401 && ex.status != 408 && ex.status != 429;
        for (final e in entry.value) {
          e.attempts++;
          e.lastError = ex.message;
          if (permanent) {
            e.status = OutboxStatus.rejected;
            rej++;
          } else {
            failed++;
          }
          await _store.updateOutbox(e);
        }
        if (!permanent) offline = true;
      }
    }
    return SyncReport(applied: applied, duplicates: dup, rejected: rej, failed: failed, offline: offline);
  }
}
