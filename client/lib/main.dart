import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/storage/server_url_store.dart';
import 'offline/local_store.dart';
import 'services/service_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    // Hook for crash reporting (e.g. Sentry/Crashlytics) in production builds.
  };
  final store = await SqfliteLocalStore.open();
  final savedUrl = await ServerUrlStore.read();
  final container = ProviderContainer(overrides: [
    localStoreProvider.overrideWithValue(store),
    if (savedUrl != null) apiBaseUrlProvider.overrideWithBuild((_, _) => savedUrl),
  ]);
  await container.read(settingsProvider.notifier).load();
  container.read(authControllerProvider.notifier).restore().then((_) => syncEverything(container.read));
  runApp(UncontrolledProviderScope(container: container, child: const MediTrackApp()));
}
