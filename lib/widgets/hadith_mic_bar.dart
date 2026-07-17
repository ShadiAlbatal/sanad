import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/hadith_finder_state.dart';
import '../theme/app_theme.dart';
import 'heard_ticker.dart';
import 'hearing_indicator.dart';
import 'mic_toggle_button.dart';

/// The "recite to find a hadith" control, shared by the Hadith search screen and
/// the Hadith reader (so a reader can voice-jump to another hadith without backing
/// out). Styled to match the Quran/du'a footers. Reads the ONE shared
/// [HadithFinderState] provided app-wide, so both surfaces drive the same mic.
class HadithMicBar extends StatelessWidget {
  final String idlePrompt;
  const HadithMicBar({super.key, this.idlePrompt = 'Recite a hadith to find it'});

  @override
  Widget build(BuildContext context) {
    final finder = context.watch<HadithFinderState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return SafeArea(
      top: false,
      child: Container(
        color: barColor,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (finder.listening) ...[
              HeardTicker(heard: finder.heard),
              const SizedBox(height: 4),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (finder.listening)
                  Flexible(
                    child: HearingIndicator(
                      active: true,
                      level: finder.level,
                      tracking: false,
                      label: _label(finder),
                    ),
                  )
                else
                  Flexible(
                    child: Text(idlePrompt,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w500)),
                  ),
                const SizedBox(width: 14),
                MicToggleButton(
                  active: finder.listening,
                  starting: finder.starting,
                  onTap: () => _toggle(context, finder),
                  idleLabel: 'Recite to find a hadith',
                  activeLabel: 'Stop listening',
                  startingLabel: 'Starting',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _label(HadithFinderState finder) {
    if (!finder.heardSomething) return 'Listening…';
    final lead = finder.leading;
    return lead == null ? 'Matching…' : 'Hearing: ${lead.label}?';
  }

  Future<void> _toggle(BuildContext context, HadithFinderState finder) async {
    if (finder.listening) {
      await finder.stop();
      return;
    }
    await finder.start();
    if (finder.error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(finder.error!)));
    }
  }
}
