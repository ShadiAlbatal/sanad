import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Plain-language "what leaves this app" screen, linked from Settings. Lists
/// exactly what a session report contains (only when the usage toggle is on)
/// and what is never included. In this build nothing is uploaded — reports are
/// written only to the on-device diagnostic log.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _shared = [
    'A random install id — a code for this app copy, not linked to you.',
    'Which surah or du’a you read, and how far you reached.',
    'How many sounds the app decoded, and whether it locked on.',
    'Tajwīd notes it raised (the reference letter vs the one it heard).',
    'Words skipped and how long the session was.',
    'App version and your phone’s system (Android / iOS).',
    'With “Essential app data” on: anonymous crash/error summaries '
        '(what failed and roughly where — never a full stack or your data).',
  ];

  static const _never = [
    'Your voice or any audio recording.',
    'Your name, email, or any account.',
    'Your contacts or location.',
    'Anything that identifies you personally.',
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final accent = context.accent;

    return Scaffold(
      appBar: AppBar(title: const Text('Data & Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(
            'Sanad works fully offline and needs no account. The two “Help '
            'improve” switches are optional and independent: “Performance & '
            'usage” records an anonymous summary of each recitation, and '
            '“Essential app data” records anonymous crash/error summaries. Both '
            'are off by default.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: soft),
          ),
          const SizedBox(height: 24),
          _Group(
            dark: dark,
            soft: soft,
            icon: Icons.check_circle_rounded,
            iconColor: accent,
            title: 'Shared — only if you opt in',
            items: _shared,
          ),
          const SizedBox(height: 20),
          _Group(
            dark: dark,
            soft: soft,
            icon: Icons.block_rounded,
            iconColor: AppColors.tajweedMajor,
            title: 'Never shared',
            items: _never,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (dark ? AppColors.nightCard : AppColors.paperEdge)
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'In this version nothing is uploaded anywhere — reports are written '
              'only to this device’s diagnostic log. Sending to a server stays '
              'off until a future update, and will always require this opt-in and a '
              'published privacy policy.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: soft),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final bool dark;
  final Color soft;
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> items;
  const _Group({
    required this.dark,
    required this.soft,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: dark ? AppColors.nightCard : AppColors.paperEdge,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: soft),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(line,
                        style: TextStyle(
                            fontSize: 13.5, height: 1.45, color: soft)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
