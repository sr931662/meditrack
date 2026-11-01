/// Build-time environment. Never put secrets here: the app only ever holds user tokens.
/// Override per build: `flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api/v1`
class Env {
  Env._();

  /// 10.0.2.2 is the Android emulator's alias for the host machine.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000/api/v1');
  static const environment = String.fromEnvironment('APP_ENV', defaultValue: 'development');
  /// Demo builds show one-tap sign-in buttons for the seeded demo accounts (`--dart-define=DEMO_LOGINS=true`).
  static const demoLogins = bool.fromEnvironment('DEMO_LOGINS');
  static bool get isProduction => environment == 'production';
}
