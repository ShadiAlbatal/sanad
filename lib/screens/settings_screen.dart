import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'privacy_screen.dart';

const _appVersion = 'v0.1';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = AppLocalizations.of(context)!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _SectionLabel(t.appearance, color: soft),
          _Card(
            dark: dark,
            child: Column(
              children: [
                for (final mode in ThemeMode.values)
                  _ThemeOption(
                    mode: mode,
                    selected: app.themeMode == mode,
                    onTap: () => app.setThemeMode(mode),
                    soft: soft,
                    showDivider: mode != ThemeMode.values.last,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _SectionLabel(t.accent, color: soft),
          _Card(
            dark: dark,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final choice in AccentChoice.values)
                    _AccentSwatch(
                      choice: choice,
                      selected: app.accentChoice == choice,
                      onTap: () => app.setAccentChoice(choice),
                      soft: soft,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _Caption(t.accentAutoCaption, color: soft),
          const SizedBox(height: 22),
          _SectionLabel(t.language, color: soft),
          _Card(
            dark: dark,
            child: Column(
              children: [
                for (final code in const ['ar', 'en'])
                  _LanguageOption(
                    code: code,
                    label: code == 'ar' ? t.languageArabic : t.languageEnglish,
                    selected: app.locale.languageCode == code,
                    onTap: () => app.setLocale(Locale(code)),
                    soft: soft,
                    showDivider: code == 'ar',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _SectionLabel(t.helpImprove, color: soft),
          _Card(
            dark: dark,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: app.shareEssential,
                  onChanged: app.setShareEssential,
                  title: Text(t.crashReports,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  subtitle: Text(
                      t.crashReportsBody,
                      style: TextStyle(color: soft, fontSize: 12.5)),
                ),
                Divider(height: 1, color: soft.withValues(alpha: 0.15)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: app.sharePerformance,
                  onChanged: app.setSharePerformance,
                  title: Text(t.performanceUsage,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  subtitle: Text(
                      t.performanceUsageBody,
                      style: TextStyle(color: soft, fontSize: 12.5)),
                ),
                Divider(height: 1, color: soft.withValues(alpha: 0.15)),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            color: context.accent, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(t.dataPrivacy,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        Icon(Icons.chevron_right_rounded, color: soft, size: 22),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Caption(
              t.privacyCaption,
              color: soft),
          const SizedBox(height: 22),
          _SectionLabel(t.about, color: soft),
          _Card(
            dark: dark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.appName,
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 6),
                Text(t.appTagline,
                    style: TextStyle(color: soft, fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 10),
                Text(_appVersion,
                    style: TextStyle(
                        color: context.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                Divider(height: 22, color: soft.withValues(alpha: 0.15)),
                InkWell(
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Sanad',
                    applicationVersion: _appVersion,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined,
                            color: context.accent, size: 20),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(t.licenses,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        Icon(Icons.chevron_right_rounded, color: soft, size: 22),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Same row shape as [_ThemeOption]. Each label is written in its OWN language
/// (العربية / English) rather than translated, so it stays recognisable to
/// someone stuck in a language they can't read.
class _LanguageOption extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color soft;
  final bool showDivider;
  const _LanguageOption({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.soft,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(Icons.language_rounded,
                    color: selected ? context.accent : soft, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      textDirection:
                          code == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 15)),
                ),
                Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected ? context.accent : soft,
                    size: 22),
              ],
            ),
          ),
          if (showDivider)
            Divider(height: 1, color: soft.withValues(alpha: 0.15)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
      child: Text(text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: color,
          )),
    );
  }
}

class _Card extends StatelessWidget {
  final bool dark;
  final Widget child;
  const _Card({required this.dark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? AppColors.nightCard : AppColors.paperEdge,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _Caption extends StatelessWidget {
  final String text;
  final Color color;
  const _Caption(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text,
          style: TextStyle(fontSize: 12, height: 1.4, color: color)),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  final AccentChoice choice;
  final bool selected;
  final VoidCallback onTap;
  final Color soft;
  const _AccentSwatch({
    required this.choice,
    required this.selected,
    required this.onTap,
    required this.soft,
  });


  static const _colors = {
    AccentChoice.iris: AppColors.accentIris,
    AccentChoice.emerald: AppColors.accentEmerald,
    AccentChoice.coral: AppColors.accentCoral,
    AccentChoice.ocean: AppColors.accentOcean,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final label = switch (choice) {
      AccentChoice.auto => t.accentAuto,
      AccentChoice.iris => t.accentIris,
      AccentChoice.emerald => t.accentEmerald,
      AccentChoice.coral => t.accentCoral,
      AccentChoice.ocean => t.accentOcean,
    };
    final color = _colors[choice];
    // Named swatches show their fixed preset; the Auto swatch's ring/label track
    // the live accent (which, on Auto, is the current time-of-day colour).
    final ring = color ?? context.accent;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? ring : soft.withValues(alpha: 0.25),
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Center(
              child: color == null
                  ? Icon(Icons.wb_twilight_rounded, color: soft, size: 22)
                  : Container(
                      width: 26,
                      height: 26,
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: color),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? ring : soft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;
  final Color soft;
  final bool showDivider;
  const _ThemeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
    required this.soft,
    required this.showDivider,
  });

  static const _icons = {
    ThemeMode.system: Icons.brightness_auto_rounded,
    ThemeMode.light: Icons.light_mode_rounded,
    ThemeMode.dark: Icons.dark_mode_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final label = switch (mode) {
      ThemeMode.system => t.themeSystem,
      ThemeMode.light => t.themeLight,
      ThemeMode.dark => t.themeDark,
    };
    final icon = _icons[mode]!;
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    color: selected ? context.accent : soft, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 15)),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded,
                      color: context.accent, size: 22)
                else
                  Icon(Icons.circle_outlined, color: soft, size: 22),
              ],
            ),
          ),
          if (showDivider)
            Divider(height: 1, color: soft.withValues(alpha: 0.15)),
        ],
      ),
    );
  }
}
