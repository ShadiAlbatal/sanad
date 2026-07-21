import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/asr/pronunciation_head.dart';
import '../services/asr/session.dart';
import '../state/reading_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../l10n/app_localizations.dart';

void showMistakesSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<ReadingState>(),
      child: const _MistakesSheet(),
    ),
  );
}

class _MistakesSheet extends StatefulWidget {
  const _MistakesSheet();
  @override
  State<_MistakesSheet> createState() => _MistakesSheetState();
}

class _MistakesSheetState extends State<_MistakesSheet> {
  final AudioPlayer _player = AudioPlayer();
  int? _playing; // index of the mistake currently playing

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(int index, RecitationMistake m) async {
    final wav = context.read<ReadingState>().mistakeWav(m);
    if (wav == null) return;
    Log.d('mistakes', 'play ${m.location} (${m.kind.name}) ${wav.length}B');
    setState(() => _playing = index);
    try {
      await _player.stop();
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (e, st) {
      Log.e('mistakes', e, st);
      if (mounted) setState(() => _playing = null);
      return;
    }
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final reading = context.watch<ReadingState>();
    final mistakes = reading.mistakes;
    final h = MediaQuery.of(context).size.height * 0.7;

    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Icon(Icons.spellcheck_rounded, color: context.accent),
                const SizedBox(width: 10),
                Text(t.mistakes,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${mistakes.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
              ],
            ),
          ),
          if (mistakes.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t.noMistakesQuran,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: mistakes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _MistakeTile(
                  mistake: mistakes[i],
                  playing: _playing == i,
                  canPlay: reading.canPlayMistake(mistakes[i]),
                  onPlay: () => _play(i, mistakes[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MistakeTile extends StatelessWidget {
  final RecitationMistake mistake;
  final bool playing;
  final bool canPlay;
  final VoidCallback onPlay;
  const _MistakeTile({
    required this.mistake,
    required this.playing,
    required this.canPlay,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _kindBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (mistake.expectedText.isNotEmpty)
                      Text(mistake.expectedText,
                          style: const TextStyle(fontFamily: 'UthmanicHafs', fontSize: 24)),
                    const SizedBox(width: 8),
                    if (mistake.location.isNotEmpty)
                      Text(mistake.location,
                          style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                  ],
                ),
                const SizedBox(height: 3),
                _detail(t, dark),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(playing ? Icons.stop_circle_rounded : Icons.play_circle_rounded,
                size: 34, color: canPlay ? context.accent : AppColors.inkSoft.withValues(alpha: 0.4)),
            onPressed: canPlay ? onPlay : null,
            tooltip: canPlay ? t.hearIt : t.audioUnavailable,
          ),
        ],
      ),
    );
  }

  Widget _kindBadge() {
    final (color, icon, label) = switch (mistake.kind) {
      MistakeKind.mispronounced => (AppColors.tajweedMajor, Icons.record_voice_over_rounded, 'say'),
      MistakeKind.skipped => (AppColors.tajweedMajor, Icons.skip_next_rounded, 'skip'),
      MistakeKind.offText => (AppColors.gold, Icons.help_outline_rounded, 'off'),
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _detail(AppLocalizations t, bool dark) {
    switch (mistake.kind) {
      case MistakeKind.mispronounced:
        final bad = mistake.badPhonemes;
        // Post-recitation makhraj flag: no neural probability (prob == null), so
        // show the reference letter that was mis-articulated vs the makhraj heard.
        if (mistake.prob == null) {
          return Row(
            children: [
              Text(t.makhrajExpected,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              if (bad.isNotEmpty)
                Text(bad.first.piece,
                    style: const TextStyle(
                        fontFamily: 'UthmanicHafs', fontSize: 18, color: AppColors.tajweedMajor)),
              if (mistake.heardText.isNotEmpty) ...[
                Text(t.heardArrow,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                Text(mistake.heardText,
                    style: const TextStyle(
                        fontFamily: 'UthmanicHafs', fontSize: 18, color: AppColors.inkSoft)),
              ],
            ],
          );
        }
        final pct = '${(mistake.prob! * 100).round()}% ';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pct + t.pronunciation,
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
            if (bad.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final p in bad.take(6)) _phonemeChip(p),
                  ],
                ),
              ),
            if (mistake.heardText.isNotEmpty && mistake.heardText != mistake.expectedText)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.heardLabel(mistake.heardText),
                    style: const TextStyle(fontFamily: 'UthmanicHafs', fontSize: 15, color: AppColors.inkSoft)),
              ),
          ],
        );
      case MistakeKind.skipped:
        return Text(t.skippedWord,
            style: TextStyle(fontSize: 12.5, color: AppColors.tajweedMajor));
      case MistakeKind.offText:
        return Text(t.offTextVerse,
            style: TextStyle(fontSize: 12.5, color: AppColors.gold));
    }
  }

  Widget _phonemeChip(PhonemeScore p) {
    final color = p.deviation == Deviation.major ? AppColors.tajweedMajor : AppColors.tajweedMinor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '${p.piece.isEmpty ? "·" : p.piece}  ${(p.prob * 100).round()}%',
        style: TextStyle(fontFamily: 'UthmanicHafs', fontSize: 14, color: color),
      ),
    );
  }
}
