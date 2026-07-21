import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/asr/session.dart';
import '../state/dua_reading_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../l10n/app_localizations.dart';

void showDuaMistakesSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<DuaReadingState>(),
      child: const _DuaMistakesSheet(),
    ),
  );
}

class _DuaMistakesSheet extends StatefulWidget {
  const _DuaMistakesSheet();
  @override
  State<_DuaMistakesSheet> createState() => _DuaMistakesSheetState();
}

class _DuaMistakesSheetState extends State<_DuaMistakesSheet> {
  final AudioPlayer _player = AudioPlayer();
  int? _playing;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(int index, RecitationMistake m) async {
    final wav = context.read<DuaReadingState>().mistakeWav(m);
    if (wav == null) return;
    Log.d('dua', 'play mistake ${m.location} (${m.kind.name}) ${wav.length}B');
    setState(() => _playing = index);
    try {
      await _player.stop();
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (e, st) {
      Log.e('dua', e, st);
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
    final dua = context.watch<DuaReadingState>();
    final mistakes = dua.mistakes;
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
                    t.noMistakesDua,
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
                itemBuilder: (context, i) => _DuaMistakeTile(
                  mistake: mistakes[i],
                  playing: _playing == i,
                  canPlay: dua.canPlayMistake(mistakes[i]),
                  onPlay: () => _play(i, mistakes[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DuaMistakeTile extends StatelessWidget {
  final RecitationMistake mistake;
  final bool playing;
  final bool canPlay;
  final VoidCallback onPlay;
  const _DuaMistakeTile({
    required this.mistake,
    required this.playing,
    required this.canPlay,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
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
                if (mistake.expectedText.isNotEmpty)
                  Text(mistake.expectedText,
                      style: const TextStyle(fontFamily: 'UthmanicHafs', fontSize: 24)),
                const SizedBox(height: 3),
                _detail(t),
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
    final (color, icon) = switch (mistake.kind) {
      MistakeKind.mispronounced => (AppColors.tajweedMajor, Icons.record_voice_over_rounded),
      MistakeKind.skipped => (AppColors.tajweedMajor, Icons.skip_next_rounded),
      MistakeKind.offText => (AppColors.gold, Icons.help_outline_rounded),
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

  Widget _detail(AppLocalizations t) {
    switch (mistake.kind) {
      case MistakeKind.mispronounced:
        final bad = mistake.badPhonemes;
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
      case MistakeKind.skipped:
        return Text(t.skippedWord,
            style: TextStyle(fontSize: 12.5, color: AppColors.tajweedMajor));
      case MistakeKind.offText:
        return Text(t.offTextDua,
            style: TextStyle(fontSize: 12.5, color: AppColors.gold));
    }
  }
}
