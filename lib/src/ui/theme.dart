// The look: the logo's navy and survey gold around a dark CAD-style drawing area. Inter for text
// and JetBrains Mono for coordinates; both fonts ship with the app.
import 'package:flutter/material.dart';

import '../brand.dart';

abstract final class Tone {
  static const ink = Color(0xFF0E1B33);
  static const muted = Color(0xFF5A6A85);
  static const line = Color(0xFFE1E6EF);
  static const soft = Color(0xFFF6F8FB);
  static const background = Color(0xFFF3F5F9);
  static const error = Color(0xFFC0392B);
  static const warning = Color(0xFFC77C02);
  static const info = Color(0xFF2F6FDB);
  static const ok = Color(0xFF1C7C4A);
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BrandColors.navyLight,
    primary: BrandColors.navyLight,
    secondary: BrandColors.gold,
    surface: Colors.white,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: Tone.background,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Tone.ink, displayColor: Tone.ink),
    dividerTheme: const DividerThemeData(color: Tone.line, space: 1, thickness: 1),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

/// The gold call-to-action button (Save DXF)
ButtonStyle goldButton() => FilledButton.styleFrom(
  backgroundColor: BrandColors.gold,
  foregroundColor: const Color(0xFF1B1405),
  textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14),
);

const mono = TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12.5);
