import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'privacy_screen.dart';

const _appVersion = 'v0.1';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _SectionLabel('Appearance', color: soft),
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
          _SectionLabel('Accent', color: soft),
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
          _Caption('Auto shifts the colour with the time of day.', color: soft),
          const SizedBox(height: 22),
          _SectionLabel('Language', color: soft),
          _Card(
            dark: dark,
            child: Opacity(
              opacity: 0.55,
              child: Row(
                children: [
                  Icon(Icons.language_rounded, color: soft, size: 22),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('English',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Text('More languages coming soon',
                      style: TextStyle(color: soft, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          _SectionLabel('Help improve TilawaAi', color: soft),
          _Card(
            dark: dark,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: app.shareEssential,
                  onChanged: app.setShareEssential,
                  title: const Text('Crash & error reports',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  subtitle: Text(
                      'Optional. Anonymous crash/error summaries to help fix bugs. The app works fully without this.',
                      style: TextStyle(color: soft, fontSize: 12.5)),
                ),
                Divider(height: 1, color: soft.withValues(alpha: 0.15)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: app.sharePerformance,
                  onChanged: app.setSharePerformance,
                  title: const Text('Performance & usage',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  subtitle: Text(
                      'Anonymous performance and usage to improve the app.',
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
                        const Expanded(
                          child: Text('Data & Privacy',
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
              'Anonymous, and kept on-device for now — nothing is uploaded anywhere yet. You can use the app fully without an account or sharing. See Data & Privacy.',
              color: soft),
          const SizedBox(height: 22),
          _SectionLabel('About', color: soft),
          _Card(
            dark: dark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tilawa',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 6),
                Text('A calm Quran companion — read, listen, and remember.',
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
                    applicationName: 'Tilawa',
                    applicationVersion: _appVersion,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined,
                            color: context.accent, size: 20),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text('Licenses & Attribution',
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

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
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

  static const _labels = {
    AccentChoice.auto: 'Auto',
    AccentChoice.iris: 'Iris',
    AccentChoice.emerald: 'Emerald',
    AccentChoice.coral: 'Coral',
    AccentChoice.ocean: 'Ocean',
  };

  static const _colors = {
    AccentChoice.iris: AppColors.accentIris,
    AccentChoice.emerald: AppColors.accentEmerald,
    AccentChoice.coral: AppColors.accentCoral,
    AccentChoice.ocean: AppColors.accentOcean,
  };

  @override
  Widget build(BuildContext context) {
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
            _labels[choice]!,
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

  static const _labels = {
    ThemeMode.system: ('System', Icons.brightness_auto_rounded),
    ThemeMode.light: ('Light', Icons.light_mode_rounded),
    ThemeMode.dark: ('Dark', Icons.dark_mode_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final (label, icon) = _labels[mode]!;
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
