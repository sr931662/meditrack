import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lets a demo APK be pointed at any deployed backend without rebuilding.
class ServerUrlStore {
  ServerUrlStore._();
  static const _key = 'server_url';
  static const _s = FlutterSecureStorage();

  /// Accepts `https://host`, `https://host/` or the full `.../api/v1` form; returns the API base URL, or null if invalid.
  static String? normalize(String input) {
    var v = input.trim();
    if (v.isEmpty) return null;
    if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'https://$v';
    final uri = Uri.tryParse(v);
    if (uri == null || uri.host.isEmpty) return null;
    v = v.replaceAll(RegExp(r'/+$'), '');
    return v.endsWith('/api/v1') ? v : '$v/api/v1';
  }

  static Future<String?> read() async {
    try {
      return await _s.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String url) => _s.write(key: _key, value: url);
}
