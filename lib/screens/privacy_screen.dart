import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Plain-language "what leaves this app" screen, linked from Settings. Lists
/// exactly what a session report contains (only when the usage toggle is on)
/// and what is never included. In this build nothing is uploaded — reports are
/// written only to the on-device diagnostic log.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});


  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final accent = context.accent;
    final shared = [
      t.privacyShared1, t.privacyShared2, t.privacyShared3, t.privacyShared4,
      t.privacyShared5, t.privacyShared6, t.privacyShared7,
    ];
    final never = [
      t.privacyNever1, t.privacyNever2, t.privacyNever3, t.privacyNever4,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(t.dataPrivacy)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(
            t.privacyIntro,
            style: TextStyle(fontSize: 13.5, height: 1.5, color: soft),
          ),
          const SizedBox(height: 24),
          _Group(
            dark: dark,
            soft: soft,
            icon: Icons.check_circle_rounded,
            iconColor: accent,
            title: t.sharedOptIn,
            items: shared,
          ),
          const SizedBox(height: 20),
          _Group(
            dark: dark,
            soft: soft,
            icon: Icons.block_rounded,
            iconColor: AppColors.tajweedMajor,
            title: t.neverShared,
            items: never,
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
              t.privacyLocalNote,
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
