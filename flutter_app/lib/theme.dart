import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color tokens ported from `windows/src/styles/theme.css`.
class AppColors {
  static const bg = Color(0xFF1C1C1E);
  static const card = Color(0xFF2C2C2E);
  static const card2 = Color(0xFF3A3A3C);
  static const txt = Color(0xFFFFFFFF);
  static const dim = Color(0xFF8A8A8E);
  static const accent = Color(0xFF2F8CFF);
  static const accentHover = Color(0xFF5AA3FF);
  static const sep = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
  static const good = Color(0xFF34C759);
  static const bad = Color(0xFFFF3B30);
  static const warn = Color(0xFFFF9F0A);
  static const brand = Color(0xFF6D6DF0);

  static const double radius = 22;
  static const double radiusSm = 14;
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: AppColors.accent,
      surface: AppColors.card,
      onSurface: AppColors.txt,
      secondary: AppColors.brand,
      error: AppColors.bad,
    ),
    // Sora: a clean geometric designer font, cached to disk after first load.
    textTheme: GoogleFonts.soraTextTheme(base.textTheme).apply(
      bodyColor: AppColors.txt,
      displayColor: AppColors.txt,
    ),
    cardColor: AppColors.card,
    dividerColor: AppColors.sep,
    iconTheme: const IconThemeData(color: AppColors.txt),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x12FFFFFF),
      hintStyle: const TextStyle(color: AppColors.dim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        borderSide: const BorderSide(color: AppColors.sep),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        borderSide: const BorderSide(color: AppColors.sep),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
        ),
      ),
    ),
  );
}
