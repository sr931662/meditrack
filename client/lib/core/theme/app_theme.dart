import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme({bool largeText = false}) {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Figtree',
    colorScheme: ColorScheme.fromSeed(seedColor: Mt.blue, primary: Mt.blue, surface: Colors.white),
    scaffoldBackgroundColor: Mt.page,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Mt.ink, displayColor: Mt.ink),
    splashFactory: InkRipple.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Mt.inputBorder, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Mt.inputBorder, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Mt.blue, width: 2.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5604F), width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5604F), width: 2.5)),
      errorStyle: const TextStyle(fontSize: 14, color: Mt.dangerDeep),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Mt.ink,
      contentTextStyle: const TextStyle(fontFamily: 'Figtree', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
