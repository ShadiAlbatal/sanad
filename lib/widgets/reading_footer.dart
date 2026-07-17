import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/reading_state.dart';
import '../theme/app_theme.dart';
import 'chevron_button.dart';
import 'heard_ticker.dart';
import 'hearing_indicator.dart';
import 'mic_toggle_button.dart';
import 'mistakes_sheet.dart';

/// Bottom action bar shown on the Quran and Adzkar tabs: mistakes review,
/// hide/reveal (memorization) toggle, and — on the Quran tab only — the
/// single live-recitation-tracking mic button.
class ReadingFooter extends StatelessWidget {
  final bool showMic;
  const ReadingFooter({super.key, this.showMic = false});

  @override
  Widget build(BuildContext context) {
    final reading = context.watch<ReadingState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final fg = dark ? AppColors.nightInk : AppColors.ink;

    // Pad above the Android edge-to-edge system nav bar / keyboard (see
    // SearchListScaffold._Footer) — this footer previously had no bottom-inset
    // handling at all.
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final bottomInset = keyboard > 0 ? keyboard : mq.viewPadding.bottom;

    return Container(
      color: barColor,
      padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMic && reading.hidden) ...[
            _RevealRow(reading: reading, fg: fg, dark: dark),
            const SizedBox(height: 8),
          ],
          if (showMic && reading.asrActive) ...[
            HeardTicker(heard: reading.asrHeard),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              _PillButton(
                icon: Icons.auto_stories_rounded,
                label: 'Mistakes',
                fg: fg,
                dark: dark,
                onTap: () => showMistakesSheet(context),
              ),
              const SizedBox(width: 10),
              _PillButton(
                icon: reading.hidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                label: reading.hidden ? 'Reveal' : 'Hide',
                fg: reading.hidden ? Colors.white : fg,
                dark: dark,
                active: reading.hidden,
                onTap: reading.toggleHidden,
              ),
              if (showMic && reading.asrActive) ...[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: HearingIndicator(
                      active: true,
                      level: reading.asrLevel,
                      tracking: reading.asrAnchored,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(reading.asrTimeLabel,
                    style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 12),
              ] else
                const Spacer(),
              if (showMic)
                MicToggleButton(
                  active: reading.asrActive,
                  starting: reading.asrStarting,
                  onTap: () => _toggleMic(context, reading),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMic(BuildContext context, ReadingState reading) async {
    await reading.toggleAsr();
    if (reading.asrError != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reading.asrError!)),
      );
    }
  }

}

/// Step-reveal row for hidden mode: hide/reveal by word (single chevron) or by
/// āyah (double chevron), forward and back, without reciting.
class _RevealRow extends StatelessWidget {
  final ReadingState reading;
  final Color fg;
  final bool dark;
  const _RevealRow({required this.reading, required this.fg, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // RTL: reading runs right→left, so the LEFT-pointing chevrons reveal
        // FORWARD (next word/āyah) and the RIGHT-pointing ones step back.
        ChevronButton(
          icon: Icons.keyboard_double_arrow_left_rounded,
          fg: fg,
          dark: dark,
          semanticLabel: 'Reveal next ayah',
          onTap: () => reading.revealForward(ayah: true),
        ),
        const SizedBox(width: 8),
        ChevronButton(
          icon: Icons.chevron_left_rounded,
          fg: fg,
          dark: dark,
          semanticLabel: 'Reveal next word',
          onTap: () => reading.revealForward(ayah: false),
        ),
        const SizedBox(width: 18),
        ChevronButton(
          icon: Icons.chevron_right_rounded,
          fg: fg,
          dark: dark,
          semanticLabel: 'Hide previous word',
          onTap: () => reading.revealBack(ayah: false),
        ),
        const SizedBox(width: 8),
        ChevronButton(
          icon: Icons.keyboard_double_arrow_right_rounded,
          fg: fg,
          dark: dark,
          semanticLabel: 'Hide previous ayah',
          onTap: () => reading.revealBack(ayah: true),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color fg;
  final bool dark;
  final bool active;
  final VoidCallback onTap;
  const _PillButton({
    required this.icon,
    required this.label,
    required this.fg,
    required this.dark,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? context.accent
        : (dark ? Colors.white : Colors.black).withValues(alpha: 0.06);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

