import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import '../offline/local_store.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import 'config/env.dart';
import 'network/api_client.dart';
import 'storage/token_store.dart';

/// Last known identity, so an offline cold start still opens the senior's reminders.
abstract class IdentityCache {
  Future<Me?> read();
  Future<void> write(Me me);
  Future<void> clear();
}

class SecureIdentityCache implements IdentityCache {
  final _s = const FlutterSecureStorage();
  @override
  Future<Me?> read() async {
    final raw = await _s.read(key: 'identity');
    return raw == null ? null : Me.fromJson(jsonDecode(raw));
  }

  @override
  Future<void> write(Me me) => _s.write(key: 'identity', value: jsonEncode(me.toJson()));
  @override
  Future<void> clear() => _s.delete(key: 'identity');
}

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());
final identityCacheProvider = Provider<IdentityCache>((_) => SecureIdentityCache());

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// API base URL: the value saved from the sign-in screen's "Server" dialog wins over the build-time default.
class ApiBaseUrl extends Notifier<String> {
  @override
  String build() => Env.apiBaseUrl;
  void set(String url) => state = url;
}

final apiBaseUrlProvider = NotifierProvider<ApiBaseUrl, String>(ApiBaseUrl.new);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      baseUrl: ref.watch(apiBaseUrlProvider),
      tokens: ref.read(tokenStoreProvider),
      onSessionExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
    ));

/// Overridden in main() with the opened SQLite store (and with an in-memory one in tests).
final localStoreProvider = Provider<LocalStore>((_) => throw UnimplementedError('localStoreProvider must be overridden'));

final outboxProvider = Provider<Outbox>((ref) => Outbox(ref.read(localStoreProvider)));

final syncServiceProvider = Provider<SyncService>((ref) {
  final api = ref.read(apiClientProvider);
  return SyncService(ref.read(localStoreProvider), (path, body) => api.post(path, data: body));
});

/// Current time, refreshed every 30 s so "Upcoming → Awaiting" flips on its own.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

DateTime nowOf(Ref ref) => ref.watch(clockProvider).value ?? DateTime.now();
