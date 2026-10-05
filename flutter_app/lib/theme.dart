import 'package:flutter/material.dart';

/// Color tokens ported from `windows/src/styles/theme.css`.
class AppColors {
  static const bg = Color(0xFF0A0A0F);
  static const card = Color(0xFF101011);
  static const card2 = Color(0xFF202025);
  static const txt = Color(0xFFF3ECE5);

  /// Secondary text. Light enough to clear WCAG AA (4.5:1) on the *lightest*
  /// surface it ever lands on — `card2` — not just on `bg`. The previous
  /// 0xFF8A8A8E measured 3.30:1 there and 4.05:1 on `card`, both failing.
  static const dim = Color(0xFFA8A8AD);

  /// Accent for text, icons and borders drawn *on* a dark surface.
  static const accent = Color(0xFFB8AEC8);
  static const accentHover = Color(0xFFD8CEDF);

  /// Accent used as a *fill* behind white label text. The lighter `accent`
  /// only reaches 3.32:1 against white; this darker step reaches 5.13:1 while
  /// staying visibly the same blue.
  static const accentFill = Color(0xFF554B62);
  static const sep = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
  static const good = Color(0xFF9EB99D);
  static const bad = Color(0xFFE19C9C);
  static const warn = Color(0xFFCAB68C);
  static const brand = Color(0xFFD8B3C4);

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

  static AppPalette of(BuildContext context) =>
      AppPalette(Theme.of(context).brightness);
}

class AppPalette {
  const AppPalette(this.brightness);
  final Brightness brightness;
  bool get light => brightness == Brightness.light;
  Color get bg => light ? const Color(0xFFF7F7F9) : AppColors.bg;
  Color get card => light ? const Color(0xFFEEEEF1) : AppColors.card;
  Color get card2 => light ? const Color(0xFFE3E1E7) : AppColors.card2;
  Color get txt => light ? const Color(0xFF1B191E) : AppColors.txt;
  Color get dim => light ? const Color(0xFF625C69) : AppColors.dim;
  Color get accent => light ? const Color(0xFF655773) : AppColors.accent;
  Color get accentHover =>
      light ? const Color(0xFF51425F) : AppColors.accentHover;
  Color get accentFill => AppColors.accentFill;
  Color get sep => light ? const Color(0x1A1B191E) : AppColors.sep;
  Color get good => light ? const Color(0xFF466644) : AppColors.good;
  Color get bad => light ? const Color(0xFF9D3C46) : AppColors.bad;
  Color get warn => light ? const Color(0xFF776039) : AppColors.warn;
  Color get brand => light ? const Color(0xFF82596F) : AppColors.brand;
  Color get fill1 => light ? const Color(0x061B191E) : AppColors.fill1;
  Color get fill2 => light ? const Color(0x0A1B191E) : AppColors.fill2;
  Color get fill3 => light ? const Color(0x121B191E) : AppColors.fill3;
  Color get fill4 => light ? const Color(0x221B191E) : AppColors.fill4;
}

ThemeData buildTheme({Brightness brightness = Brightness.dark}) {
  final colors = AppPalette(brightness);
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Nunito Sans',
  );
  return base.copyWith(
    scaffoldBackgroundColor: colors.bg,
    canvasColor: colors.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: colors.accent,
      surface: colors.card,
      onSurface: colors.txt,
      secondary: colors.brand,
      error: colors.bad,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: colors.txt,
      displayColor: colors.txt,
    ),
    cardColor: colors.card,
    dividerColor: colors.sep,
    iconTheme: IconThemeData(color: colors.txt),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.fill2,
      hintStyle: TextStyle(color: colors.dim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        borderSide: BorderSide(color: colors.sep),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        borderSide: BorderSide(color: colors.sep),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
        borderSide: BorderSide(color: colors.accent),
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
