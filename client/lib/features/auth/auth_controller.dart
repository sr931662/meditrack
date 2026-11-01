import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/token_store.dart';
import 'auth_models.dart';

export '../../core/providers.dart' show authControllerProvider;

sealed class AuthState {
  const AuthState();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class Unauthenticated extends AuthState {
  const Unauthenticated({this.message});
  final String? message;
}

class Authenticated extends AuthState {
  const Authenticated(this.me, this.ctx);
  final Me me;
  final ActiveContext ctx;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthLoading();

  ApiClient get _api => ref.read(apiClientProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  /// Called at launch: resume a stored session if its tokens still work.
  Future<void> restore() async {
    final t = await _tokens.read();
    if (t == null) {
      state = const Unauthenticated();
      return;
    }
    try {
      await _loadMe();
    } on ApiException catch (e) {
      // Offline start must not log a senior out: keep the session and use the cached identity.
      if (e.isNetwork) {
        final cached = await ref.read(identityCacheProvider).read();
        if (cached != null) {
          state = Authenticated(cached, resolveContext(cached));
          return;
        }
      }
      state = const Unauthenticated();
    }
  }

  Future<void> login(String email, String password) async {
    final r = await _api.post('/auth/login', data: {'email': email.trim(), 'password': password}, auth: false);
    await _tokens.write(Tokens(r['access_token'], r['refresh_token']));
    await _loadMe();
  }

  Future<void> register(String email, String password, String fullName) async {
    await _api.post('/auth/register', data: {'email': email.trim(), 'password': password, 'full_name': fullName.trim()}, auth: false);
    await login(email, password);
  }

  Future<void> _loadMe() async {
    final me = Me.fromJson(await _api.get('/auth/me'));
    await ref.read(identityCacheProvider).write(me);
    state = Authenticated(me, resolveContext(me));
  }

  Future<void> reload() => _loadMe();

  void switchHousehold(String householdId) {
    final s = state;
    if (s is Authenticated) state = Authenticated(s.me, resolveContext(s.me, preferHousehold: householdId));
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } on ApiException {
      // Best effort: the server session expires on its own. Local tokens are always cleared.
    }
    await _tokens.clear();
    await ref.read(identityCacheProvider).clear();
    state = const Unauthenticated();
  }

  void sessionExpired() {
    state = const Unauthenticated(message: 'Your session has expired. Please sign in again.');
  }
}
