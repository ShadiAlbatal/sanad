import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/dua_reading_state.dart';
import '../theme/app_theme.dart';
import 'chevron_button.dart';
import 'dua_mistakes_sheet.dart';
import 'heard_ticker.dart';
import 'hearing_indicator.dart';
import 'mic_toggle_button.dart';

/// Bottom action bar for the du'a reader: mistakes review, hide/reveal
/// (memorization) toggle, the `< << > >>` step-reveal row in hidden mode, and
/// the live-recitation mic button. A self-contained sibling of ReadingFooter,
/// bound to [DuaReadingState].
class DuaReadingFooter extends StatelessWidget {
  const DuaReadingFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final dua = context.watch<DuaReadingState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final fg = dark ? AppColors.nightInk : AppColors.ink;

    // SafeArea doesn't reliably pick up the Android edge-to-edge system nav bar
    // in this bottomNavigationBar slot (see SearchListScaffold._Footer) — pad
    // explicitly instead, above the keyboard when it's up, else the nav bar.
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final bottomInset = keyboard > 0 ? keyboard : mq.viewPadding.bottom;

    return Container(
      color: barColor,
      padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dua.hidden) ...[
            _RevealRow(dua: dua, fg: fg, dark: dark),
            const SizedBox(height: 8),
          ],
          if (dua.active) ...[
            HeardTicker(heard: dua.heard),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              _PillButton(
                icon: Icons.spellcheck_rounded,
                label: 'Mistakes',
                fg: fg,
                dark: dark,
                onTap: () => showDuaMistakesSheet(context),
              ),
              const SizedBox(width: 10),
              _PillButton(
                icon: dua.hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                label: dua.hidden ? 'Reveal' : 'Hide',
                fg: dua.hidden ? Colors.white : fg,
                dark: dark,
                active: dua.hidden,
                onTap: dua.toggleHidden,
              ),
              if (dua.active) ...[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: HearingIndicator(
                      active: true,
                      level: dua.level,
                      tracking: dua.anchored,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(dua.durationLabel,
                    style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 12),
              ] else
                const Spacer(),
              MicToggleButton(
                active: dua.active,
                starting: dua.starting,
                onTap: () => _toggleMic(context, dua),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMic(BuildContext context, DuaReadingState dua) async {
    await dua.toggleListening();
    if (dua.error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dua.error!)));
    }
  }
}

class _RevealRow extends StatelessWidget {
  final DuaReadingState dua;
  final Color fg;
  final bool dark;
  const _RevealRow({required this.dua, required this.fg, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // RTL: left-pointing chevrons reveal FORWARD, right-pointing step back.
        ChevronButton(
          icon: Icons.keyboard_double_arrow_left_rounded,
          fg: fg,
          dark: dark,
          semanticLabel: 'Reveal next segment',
          onTap: () => dua.revealForward(ayah: true),
        ),
        const SizedBox(width: 8),
        ChevronButton(
          icon: Icons.chevron_left_rounded,
          fg: fg,
          dark: dark,
          semanticLabel: 'Reveal next word',
          onTap: () => dua.revealForward(ayah: false),
        ),
        const SizedBox(width: 18),
        ChevronButton(
          icon: Icons.chevron_right_rounded,
          fg: fg,
          dark: dark,
          semanticLabel: 'Hide previous word',
          onTap: () => dua.revealBack(ayah: false),
        ),
        const SizedBox(width: 8),
        ChevronButton(
          icon: Icons.keyboard_double_arrow_right_rounded,
          fg: fg,
          dark: dark,
          semanticLabel: 'Hide previous segment',
          onTap: () => dua.revealBack(ayah: true),
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
                  style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

