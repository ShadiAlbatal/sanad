import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/hadith_reading_state.dart';
import '../theme/app_theme.dart';
import 'heard_ticker.dart';
import 'hearing_indicator.dart';
import 'mic_toggle_button.dart';

/// Bottom action bar for the hadith reader: the live follow-along mic plus its
/// level/heard telemetry. A trimmed sibling of the du'a [DuaReadingFooter] (no
/// hide/mistakes controls — a hadith isn't memorized or tajwīd-reviewed here),
/// bound to [HadithReadingState]. While this reader is open its mic owns the
/// shared audio (claimed from the hadith finder).
class HadithReadingFooter extends StatelessWidget {
  final String idlePrompt;
  const HadithReadingFooter({super.key, this.idlePrompt = 'Recite to follow along'});

  @override
  Widget build(BuildContext context) {
    final read = context.watch<HadithReadingState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final fg = dark ? AppColors.nightInk : AppColors.ink;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

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
          if (read.active) ...[
            HeardTicker(heard: read.heard),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              if (read.active) ...[
                Expanded(
                  child: HearingIndicator(
                    active: true,
                    level: read.level,
                    tracking: read.anchored,
                  ),
                ),
                const SizedBox(width: 10),
                Text(read.durationLabel,
                    style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 12),
              ] else
                Expanded(
                  child: Text(idlePrompt,
                      style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w500)),
                ),
              MicToggleButton(
                active: read.active,
                starting: read.starting,
                onTap: () => _toggleMic(context, read),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMic(BuildContext context, HadithReadingState read) async {
    await read.toggleListening();
    if (read.error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(read.error!)));
    }
  }
}
