import 'package:flutter/material.dart';

enum DayPart { fajr, morning, afternoon, evening, night }

DayPart dayPartOf(DateTime t) {
  final h = t.hour;
  if (h >= 4 && h < 7) return DayPart.fajr;
  if (h >= 7 && h < 12) return DayPart.morning;
  if (h >= 12 && h < 16) return DayPart.afternoon;
  if (h >= 16 && h < 20) return DayPart.evening;
  return DayPart.night;
}

String greetingFor(DayPart p) {
  switch (p) {
    case DayPart.fajr:
      return 'A blessed dawn';
    case DayPart.morning:
      return 'Good morning';
    case DayPart.afternoon:
      return 'Good afternoon';
    case DayPart.evening:
      return 'A blessed evening';
    case DayPart.night:
      return 'A peaceful night';
  }
}

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

AdhkarSuggestion suggestionFor(DayPart p) {
  switch (p) {
    case DayPart.fajr:
    case DayPart.morning:
      return const AdhkarSuggestion(
        label: 'Morning adhkār',
        category: 'Morning & Evening',
        icon: Icons.wb_sunny_rounded,
      );
    case DayPart.evening:
      return const AdhkarSuggestion(
        label: 'Evening adhkār',
        category: 'Morning & Evening',
        icon: Icons.wb_twilight_rounded,
      );
    case DayPart.night:
      return const AdhkarSuggestion(
        label: 'Night — istighfār',
        category: 'Tasbih',
        icon: Icons.nightlight_round,
      );
    case DayPart.afternoon:
      return const AdhkarSuggestion(
        label: 'Remember Allah',
        category: 'Tasbih',
        icon: Icons.spa_rounded,
      );
  }
}
