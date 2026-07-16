import 'package:flutter/material.dart';

class AppColors {
  // Warm paper (light) — the mushaf page tone
  static const paper = Color(0xFFF6F1E5);
  static const paperEdge = Color(0xFFEDE4CE);
  static const ink = Color(0xFF1F2421);
  static const inkSoft = Color(0xFF5B6560);

  // Violet-ink (dark)
  static const night = Color(0xFF14131A);
  static const nightCard = Color(0xFF1E1C27);
  static const nightInk = Color(0xFFECE7F5);
  static const nightInkSoft = Color(0xFF9E97B4);

  // Accent — emerald/gold, classic mushaf
  static const emerald = Color(0xFF1F7A5A);
  static const gold = Color(0xFFB08828);

  // Accent presets (design-system hues at ~70% sat / ~45% light). Persisted as
  // a user choice; not yet applied to the live theme.
  static const accentIris = Color(0xFF9B22C3); // ~285°
  static const accentEmerald = emerald; // ~158°
  static const accentCoral = Color(0xFFC37822); // ~32°
  static const accentOcean = Color(0xFF2230C3); // ~235°

  // Live tajweed/pronunciation feedback (per-word, from the ASR pronunciation head)
  static const tajweedOk = Color(0xFF1F7A5A); // same as emerald
  static const tajweedMinor = Color(0xFFC98A1E);
  static const tajweedMajor = Color(0xFFC0392B);
}

/// The live accent is carried by `colorScheme.primary`; widgets read it via
/// `context.accent` rather than a fixed `AppColors` value.
extension AccentContext on BuildContext {
  Color get accent => Theme.of(this).colorScheme.primary;
}

class AppTheme {
  static ThemeData light(Color accent) {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: AppColors.gold,
        surface: AppColors.paper,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      navigationBarTheme: _navBar(
        bg: AppColors.paperEdge,
        selected: accent,
        unselected: AppColors.inkSoft,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        centerTitle: true,
      ),
    );
  }

  // A hue legible as small text on the light paper can be too dark to read on
  // the night surface (deep blue/violet especially — blue carries little
  // luminance). Lift the accent to a lightness floor for the dark theme so every
  // `context.accent` (text + chrome) stays readable on nightCard.
  static Color _accentForDark(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    return hsl.lightness >= 0.6 ? accent : hsl.withLightness(0.6).toColor();
  }

  static ThemeData dark(Color accent) {
    final base = ThemeData.dark(useMaterial3: true);
    final a = _accentForDark(accent);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.night,
      colorScheme: base.colorScheme.copyWith(
        primary: a,
        secondary: AppColors.gold,
        surface: AppColors.nightCard,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.nightInk,
        displayColor: AppColors.nightInk,
      ),
      navigationBarTheme: _navBar(
        bg: AppColors.nightCard,
        selected: a,
        unselected: AppColors.nightInkSoft,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.nightInk,
        centerTitle: true,
      ),
    );
  }

  static NavigationBarThemeData _navBar({
    required Color bg,
    required Color selected,
    required Color unselected,
  }) {
    return NavigationBarThemeData(
      backgroundColor: bg,
      indicatorColor: selected.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? selected : unselected,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? selected : unselected,
        ),
      ),
    );
  }
}
