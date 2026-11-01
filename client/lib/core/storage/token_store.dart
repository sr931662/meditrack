import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens(this.access, this.refresh);
  final String access;
  final String refresh;
}

abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}

/// Android Keystore-backed storage (via EncryptedSharedPreferences).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<Tokens?> read() async {
    final a = await _s.read(key: 'access');
    final r = await _s.read(key: 'refresh');
    return (a == null || r == null) ? null : Tokens(a, r);
  }

  @override
  Future<void> write(Tokens t) async {
    await _s.write(key: 'access', value: t.access);
    await _s.write(key: 'refresh', value: t.refresh);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: 'access');
    await _s.delete(key: 'refresh');
  }
}

class MemoryTokenStore implements TokenStore {
  Tokens? _t;
  @override
  Future<Tokens?> read() async => _t;
  @override
  Future<void> write(Tokens t) async => _t = t;
  @override
  Future<void> clear() async => _t = null;
}
