import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../services/service_providers.dart';
import 'routes.dart';

class MediTrackApp extends ConsumerStatefulWidget {
  const MediTrackApp({super.key});
  @override
  ConsumerState<MediTrackApp> createState() => _MediTrackAppState();
}

class _MediTrackAppState extends ConsumerState<MediTrackApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Upload queued responses and rebuild local alarms whenever connectivity returns.
    Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) syncEverything(ref.read);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume also covers timezone / DST changes that happened while the app was in the background.
    if (state == AppLifecycleState.resumed) syncEverything(ref.read);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'MediTrack',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: settings.largeText ? TextScaler.linear((mq.textScaler.scale(1) * 1.2).clamp(1.0, 2.0)) : mq.textScaler,
            disableAnimations: settings.reduceMotion || mq.disableAnimations,
          ),
          child: child!,
        );
      },
    );
  }
}
