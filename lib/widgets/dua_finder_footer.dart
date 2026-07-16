import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/duas.dart';
import '../state/dua_finder_state.dart';
import '../theme/app_theme.dart';
import 'heard_ticker.dart';
import 'hearing_indicator.dart';
import 'mic_toggle_button.dart';

/// Bottom control for the Azkar (du'a list) tab, styled to match the Quran
/// read-along [ReadingFooter] bar. The mic runs the "recite to open" finder —
/// it listens across every du'a at once and, once one is identified, the list
/// opens its reader. No Mistakes/Hide-Reveal pills: there is no open du'a on the
/// list to act on (those live in the reader's DuaReadingFooter).
class DuaFinderFooter extends StatelessWidget {
  const DuaFinderFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final finder = context.watch<DuaFinderState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return Container(
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
                    label: _finderLabel(finder),
                  ),
                )
              else
                Flexible(
                  child: Text('Recite to open a du\'ā',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w500)),
                ),
              const SizedBox(width: 14),
              MicToggleButton(
                active: finder.listening,
                starting: finder.starting,
                onTap: () => _toggleMic(context, finder),
                idleLabel: 'Recite to find a du\'ā',
                activeLabel: 'Stop listening',
                startingLabel: 'Starting',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // The finder never anchors a position, so tracking stays false; the label
  // carries the progress instead: naming the leading du'a once one is heard.
  String _finderLabel(DuaFinderState finder) {
    if (!finder.heardSomething) return 'Listening…';
    final id = finder.leadingDuaId;
    if (id != null) {
      for (final d in duas) {
        if (d.id == id) return 'Hearing: ${d.title}?';
      }
    }
    return 'Matching…';
  }

  Future<void> _toggleMic(BuildContext context, DuaFinderState finder) async {
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

