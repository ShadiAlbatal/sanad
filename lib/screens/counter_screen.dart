import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/adhkar_data.dart';
import '../state/dhikr_counter_state.dart';
import '../theme/app_theme.dart';
import '../widgets/heard_ticker.dart';
import '../widgets/hearing_indicator.dart';
import '../widgets/mic_toggle_button.dart';

/// The Counter tab: tasbīḥ tallies that climb by TAP or by VOICE. Tap the mic and
/// recite freely — سبحان الله, الحمد لله, الله أكبر … — and each recognized phrase
/// bumps its own (unlimited, persisted) count. Morning/Evening adhkār live
/// elsewhere; this tab is only the short repeated dhikr.
class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  static final List<Dhikr> _items =
      adhkarCategories.firstWhere((c) => c.title == 'Tasbih').items;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DhikrCounterState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Counter',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  ),
                  if (state.total > 0)
                    TextButton.icon(
                      onPressed: () => _confirmReset(context, state),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Reset'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Tap a card or the mic and recite — it counts as you go.',
                  style: TextStyle(color: soft, fontSize: 13.5)),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                itemCount: _items.length,
                itemBuilder: (_, i) => _CounterCard(
                  dhikr: _items[i],
                  count: state.count(_items[i].id),
                  onTap: () => state.bump(_items[i].id),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _MicFooter(state: state),
    );
  }

  Future<void> _confirmReset(BuildContext context, DhikrCounterState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all counts?'),
        content: const Text('This clears every tasbīḥ tally back to zero.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) state.resetAll();
  }
}

class _CounterCard extends StatelessWidget {
  final Dhikr dhikr;
  final int count;
  final VoidCallback onTap;
  const _CounterCard({required this.dhikr, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final has = count > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: has ? context.accent.withValues(alpha: 0.55) : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text(
                      dhikr.arabic,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontFamily: 'UthmanicHafs', fontSize: 24, height: 1.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(dhikr.translit,
                      style: TextStyle(
                          fontStyle: FontStyle.italic, color: soft, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              constraints: const BoxConstraints(minWidth: 54),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: has ? context.accent : context.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: has ? Colors.white : context.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicFooter extends StatelessWidget {
  final DhikrCounterState state;
  const _MicFooter({required this.state});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.viewPadding.bottom;
    final listening = state.recording;

    return Container(
      color: barColor,
      padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (listening) ...[
            HeardTicker(heard: state.heard),
            const SizedBox(height: 4),
            HearingIndicator(
              active: true,
              level: state.level,
              tracking: false,
              label: 'Listening — recite freely',
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  listening ? 'Counting what you recite…' : 'Tap the mic and recite',
                  style: TextStyle(color: soft, fontSize: 13.5),
                ),
              ),
              const SizedBox(width: 10),
              MicToggleButton(
                active: listening,
                starting: state.busy && !listening,
                onTap: state.toggleMic,
                idleLabel: 'Count by voice',
                activeLabel: 'Stop counting',
                startingLabel: 'Starting',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
