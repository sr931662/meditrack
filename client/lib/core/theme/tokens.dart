import 'package:flutter/material.dart';

/// Design tokens lifted from `design/MediTrack.dc.html` (Claude Design export).
/// Keep names aligned with docs/DESIGN_SYSTEM.md.
class Mt {
  Mt._();

  // Brand + text
  static const blue = Color(0xFF1877F2);
  static const blueDark = Color(0xFF1463D8);
  static const blueLight = Color(0xFF3D95FB);
  static const blueText = Color(0xFF1462D6);
  static const ink = Color(0xFF101B2D);
  static const ink2 = Color(0xFF2A3B55);
  static const muted = Color(0xFF647A99);
  static const muted2 = Color(0xFF45608A);
  static const faint = Color(0xFF8FA2BD);

  // Surfaces
  static const page = Color(0xFFEAF1FB);
  static const card = Colors.white;
  static const border = Color(0xFFE4ECF8);
  static const hairline = Color(0xFFEEF3FA);
  static const track = Color(0xFFEEF3FA);
  static const inputBorder = Color(0xFFD6E2F2);
  static const outline = Color(0xFFD6E5F8);
  static const tint = Color(0xFFF6F9FF);
  static const tintBlue = Color(0xFFE4F0FF);

  // Status
  static const ok = Color(0xFF138A68);
  static const okDeep = Color(0xFF0F7457);
  static const okBg = Color(0xFFEEF9F4);
  static const okBorder = Color(0xFFC9EBDD);
  static const warn = Color(0xFF855000);
  static const warnBg = Color(0xFFFFF1D3);
  static const warnBorder = Color(0xFFF3E3C0);
  static const orange = Color(0xFFEE8B3A);
  static const unverifiedFg = Color(0xFFA3420F);
  static const unverifiedBg = Color(0xFFFDE9DC);
  static const danger = Color(0xFFD9473A);
  static const dangerDeep = Color(0xFFB5362A);
  static const dangerBg = Color(0xFFFDE8E6);
  static const dangerBorder = Color(0xFFF6CFC8);
  static const upcomingFg = Color(0xFF3F5A82);
  static const upcomingBg = Color(0xFFEFF4FB);

  static const gradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blueLight, blue, blueDark],
  );

  static List<BoxShadow> shadow([double a = .10, double blur = 34, double dy = 14]) =>
      [BoxShadow(color: const Color(0xFF1C54A0).withValues(alpha: a), blurRadius: blur, offset: Offset(0, dy))];

  static const radiusCard = 24.0;
  static const radiusTile = 16.0;
  static const minTap = 48.0;
}

/// Pill appearance tokens (`PILLS` in the design). Stored on the server as `appearance`.
class PillStyle {
  const PillStyle(this.key, this.label, this.tile, this.a, this.b, {this.capsule = true});
  final String key;
  final String label;
  final Color tile;
  final Gradient a;
  final Gradient b;
  final bool capsule;

  static const _white = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFD8E4F5)]);

  static final all = <String, PillStyle>{
    'blue': const PillStyle('blue', 'Blue capsule', Color(0xFFE8F2FF),
        LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF62AAFF), Color(0xFF1668E3)]), _white),
    'pink': const PillStyle('pink', 'Pink tablet', Color(0xFFFDECEF),
        RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFFFB8C2), Color(0xFFE2566B)]), _white, capsule: false),
    'white': const PillStyle('white', 'White tablet', Color(0xFFEEF2F7),
        RadialGradient(center: Alignment(-.3, -.4), colors: [Colors.white, Color(0xFFD3DDEA)]), _white, capsule: false),
    'amber': const PillStyle('amber', 'Amber capsule', Color(0xFFFFF5E2),
        LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFD27A), Color(0xFFE2961A)]),
        LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFF2E6D2)])),
  };

  static PillStyle of(String? key) => all[key] ?? all['blue']!;
}
