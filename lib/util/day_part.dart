import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

enum DayPart { fajr, morning, afternoon, evening, night }

DayPart dayPartOf(DateTime t) {
  final h = t.hour;
  if (h >= 4 && h < 7) return DayPart.fajr;
  if (h >= 7 && h < 12) return DayPart.morning;
  if (h >= 12 && h < 16) return DayPart.afternoon;
  if (h >= 16 && h < 20) return DayPart.evening;
  return DayPart.night;
}

String greetingFor(AppLocalizations t, DayPart p) => switch (p) {
      DayPart.fajr => t.greetingDawn,
      DayPart.morning => t.greetingMorning,
      DayPart.afternoon => t.greetingAfternoon,
      DayPart.evening => t.greetingEvening,
      DayPart.night => t.greetingNight,
    };

class AdhkarSuggestion {
  final String label;
  final String category;
  final IconData icon;
  const AdhkarSuggestion({
    required this.label,
    required this.category,
    required this.icon,
  });
}

/// [AdhkarSuggestion.category] is a DATA key handed to
/// AdzkarScreen(initialCategory:) — it selects a category and is never
/// shown, so it stays English while [label] is localized.
AdhkarSuggestion suggestionFor(AppLocalizations t, DayPart p) {
  switch (p) {
    case DayPart.fajr:
    case DayPart.morning:
      return AdhkarSuggestion(
        label: t.morningAdhkar,
        category: 'Morning & Evening',
        icon: Icons.wb_sunny_rounded,
      );
    case DayPart.evening:
      return AdhkarSuggestion(
        label: t.eveningAdhkar,
        category: 'Morning & Evening',
        icon: Icons.wb_twilight_rounded,
      );
    case DayPart.night:
      return AdhkarSuggestion(
        label: t.nightIstighfar,
        category: 'Tasbih',
        icon: Icons.nightlight_round,
      );
    case DayPart.afternoon:
      return AdhkarSuggestion(
        label: t.rememberAllah,
        category: 'Tasbih',
        icon: Icons.spa_rounded,
      );
  }
}
