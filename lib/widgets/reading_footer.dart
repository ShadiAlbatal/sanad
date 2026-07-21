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
          if (showMic && reading.asrActive) ...[
            HeardTicker(heard: reading.asrHeard),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              // Mistakes only means anything once a recitation pass is over —
              // hide it while actively reciting instead of always reserving
              // its slot, which also makes room for the reveal chevrons below
              // to live in THIS row instead of a whole extra row above.
              if (!(showMic && reading.asrActive)) ...[
                _IconPill(
                  icon: Icons.auto_stories_rounded,
                  semanticLabel: 'Mistakes',
                  fg: fg,
                  dark: dark,
                  onTap: () => showMistakesSheet(context),
                ),
                const SizedBox(width: 10),
              ],
              _IconPill(
                icon: reading.hidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                semanticLabel: reading.hidden ? 'Reveal' : 'Hide',
                fg: reading.hidden ? Colors.white : fg,
                dark: dark,
                active: reading.hidden,
                onTap: reading.toggleHidden,
              ),
              if (showMic && reading.hidden) ...[
                const SizedBox(width: 8),
                Flexible(child: _RevealRow(reading: reading, fg: fg, dark: dark)),
              ],
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
              ] else if (!(showMic && reading.hidden))
                // Only pad out the row when the reveal chevrons AREN'T here.
                // Spacer is an Expanded(flex: 1), so beside the reveal row's
                // Flexible(flex: 1) it took half the free width for nothing and
                // the FittedBox scaled the four chevrons down to ~19x14.
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
/// āyah (double chevron), forward and back, without reciting. Now lives
/// inline in the main footer row (not a row of its own above it), so it
/// scales itself down rather than force the row to overflow on narrower
/// phones or when the hearing indicator also wants room.
class _RevealRow extends StatelessWidget {
  final ReadingState reading;
  final Color fg;
  final bool dark;
  const _RevealRow({required this.reading, required this.fg, required this.dark});

  @override
  Widget build(BuildContext context) {
    // The four chevrons encode ARABIC reading semantics directly in their icons
    // (left-pointing = forward). Pin this row to LTR so the app locale can't
    // mirror it: under an Arabic (RTL) locale the Row would reverse child order
    // while the icons stayed put, flipping "reveal forward" to the wrong side.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
      mainAxisSize: MainAxisSize.min,
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
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final Color fg;
  final bool dark;
  final bool active;
  final VoidCallback onTap;
  const _IconPill({
    required this.icon,
    required this.semanticLabel,
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
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: ExcludeSemantics(child: Icon(icon, size: 18, color: fg)),
        ),
      ),
      ),
    );
  }
}

