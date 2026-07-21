import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color tokens ported from `windows/src/styles/theme.css`.
class AppColors {
  static const bg = Color(0xFF1C1C1E);
  static const card = Color(0xFF2C2C2E);
  static const card2 = Color(0xFF3A3A3C);
  static const txt = Color(0xFFFFFFFF);

  /// Secondary text. Light enough to clear WCAG AA (4.5:1) on the *lightest*
  /// surface it ever lands on — `card2` — not just on `bg`. The previous
  /// 0xFF8A8A8E measured 3.30:1 there and 4.05:1 on `card`, both failing.
  static const dim = Color(0xFFA8A8AD);

  /// Accent for text, icons and borders drawn *on* a dark surface.
  static const accent = Color(0xFF2F8CFF);
  static const accentHover = Color(0xFF5AA3FF);

  /// Accent used as a *fill* behind white label text. The lighter `accent`
  /// only reaches 3.32:1 against white; this darker step reaches 5.13:1 while
  /// staying visibly the same blue.
  static const accentFill = Color(0xFF106BD6);
  static const sep = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
  static const good = Color(0xFF34C759);
  static const bad = Color(0xFFFF3B30);
  static const warn = Color(0xFFFF9F0A);
  static const brand = Color(0xFF6D6DF0);

  /// Translucent white overlays used to lift a surface off the background.
  /// One named scale so the same step is reused instead of a new hex literal
  /// being invented at each call site (there were five near-identical values).
  static const fill1 = Color(0x0AFFFFFF); // hairline / resting
  static const fill2 = Color(0x12FFFFFF); // subtle raise
  static const fill3 = Color(0x1FFFFFFF); // hover / selected
  static const fill4 = Color(0x22FFFFFF); // track behind progress

  /// Corner radii. `radius` is the card/dialog shape, `radiusSm` the control
  /// shape; `radiusXs` covers the small chips and tree rows that were reaching
  /// for bare numbers.
  static const double radius = 22;
  static const double radiusSm = 14;
  static const double radiusXs = 10;
  /// Fully-rounded pill. Use instead of an arbitrary large number.
  static const double radiusPill = 999;
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
    textTheme: GoogleFonts.soraTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppColors.txt, displayColor: AppColors.txt),
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
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
        ),
      ),
    ),
  );
}
