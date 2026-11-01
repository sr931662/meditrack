import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/mt_widgets.dart';
import '../features/admin/admin_shell.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/login_screen.dart';
import '../features/escalation/alert_screen.dart';
import '../features/home/dose_detail_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/shell/caregiver_shell.dart';
import '../features/shell/senior_shell.dart';
import '../features/verification/verify_screen.dart';

/// Single source of route names/paths.
class R {
  R._();
  static const login = '/login';
  static const root = '/';
  static const notifications = '/notifications';
  static String dose(String key) => '/dose/${Uri.encodeComponent(key)}';
  static String verify(String key) => '/verify/${Uri.encodeComponent(key)}';
  static String alert(String id) => '/alert/$id';
}

/// Bridges Riverpod auth state to go_router so redirects re-run on sign-in/out.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  return GoRouter(
    initialLocation: R.root,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final atLogin = state.matchedLocation == R.login;
      if (auth is AuthLoading) return null;
      if (auth is Unauthenticated) return atLogin ? null : R.login;
      return atLogin ? R.root : null;
    },
    routes: [
      GoRoute(path: R.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: R.root,
        builder: (context, _) => Consumer(builder: (context, ref, _) {
          final auth = ref.watch(authControllerProvider);
          if (auth is! Authenticated) return const _Splash();
          return switch (auth.ctx.mode) {
            AppMode.admin => const AdminShell(),
            AppMode.senior => const SeniorShell(),
            AppMode.caregiver => const CaregiverShell(),
          };
        }),
      ),
      GoRoute(path: R.notifications, builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/dose/:key', builder: (_, s) => DoseDetailScreen(doseKey: Uri.decodeComponent(s.pathParameters['key']!))),
      GoRoute(path: '/verify/:key', builder: (_, s) => VerifyScreen(doseKey: Uri.decodeComponent(s.pathParameters['key']!))),
      GoRoute(path: '/alert/:id', builder: (_, s) => AlertScreen(escalationId: s.pathParameters['id']!)),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Wordmark(size: 34)));
}

/// Standard screen frame for pushed routes (back button, gradient background, 20 px gutter).
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.children, this.trailing, this.onRefresh});
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Mt.page,
        body: PageBackground(
          child: SafeArea(
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), child: BackHeader(title, trailing: trailing)),
              Expanded(
                child: Builder(builder: (context) {
                  final list = ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    itemCount: children.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (_, i) => children[i],
                  );
                  return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
                }),
              ),
            ]),
          ),
        ),
      );
}
