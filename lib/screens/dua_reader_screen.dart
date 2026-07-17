import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/duas.dart';
import '../services/asr/asr_engine.dart';
import '../state/app_state.dart';
import '../state/dua_reading_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dua_reading_footer.dart';

/// One du'a, read-along. Shows the flowing RTL Arabic where each word tracks the
/// reciter (current / read / skipped) and hides/reveals per word in memorization
/// mode. Its [DuaReadingState] is scoped to this screen (per-reader provider), so
/// opening another du'a starts fresh; the shared phoneme engine (app-global
/// [AsrEngine]) is reused, not recreated, and the mic is just released on pop.
class DuaReaderScreen extends StatelessWidget {
  final Dua dua;

  /// When opened from the "recite to open" finder the user is already reciting,
  /// so begin the follow-along the moment the clip is ready — the reader claims
  /// the shared mic from the finder (single-owner [AsrEngine.claimMic], which
  /// stops the finder) and re-anchors on the live audio without a second tap.
  final bool autoStart;
  const DuaReaderScreen({super.key, required this.dua, this.autoStart = false});

  @override
  Widget build(BuildContext context) {
    context.read<AppState>().setLastDuaId(dua.id);
    return ChangeNotifierProvider(
      create: (ctx) {
        final state = DuaReadingState(ctx.read<AsrEngine>());
        final loaded = state.loadDua(dua.id);
        if (autoStart) {
          loaded.then((_) =>
              WidgetsBinding.instance.addPostFrameCallback((_) => state.startListening()));
        }
        return state;
      },
      child: _DuaReaderView(dua: dua),
    );
  }
}

class _DuaReaderView extends StatelessWidget {
  final Dua dua;
  const _DuaReaderView({required this.dua});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DuaReadingState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return Scaffold(
      appBar: AppBar(title: Text(dua.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 6,
              children: [
                for (var i = 0; i < state.words.length; i++)
                  _DuaWord(index: i, text: state.words[i], state: state, dark: dark),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _MeaningCard(dua: dua, soft: soft, dark: dark),
        ],
      ),
      bottomNavigationBar: const DuaReadingFooter(),
    );
  }
}

class _DuaWord extends StatelessWidget {
  final int index;
  final String text;
  final DuaReadingState state;
  final bool dark;
  const _DuaWord({
    required this.index,
    required this.text,
    required this.state,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final hiddenWord = state.hidden && !state.isRevealed(index);
    final isCurrent = state.currentWord == index;
    final isRead = state.readWords.contains(index);
    final isSkipped = state.skippedWords.contains(index);

    final Color? bg = hiddenWord
        ? (dark ? Colors.white : Colors.black).withValues(alpha: 0.05)
        : isCurrent
            ? (dark ? Colors.white : context.accent).withValues(alpha: dark ? 0.28 : 0.20)
            : isRead
                ? (dark ? Colors.white : context.accent).withValues(alpha: dark ? 0.16 : 0.10)
                : isSkipped
                    ? AppColors.tajweedMajor.withValues(alpha: dark ? 0.18 : 0.10)
                    : null;

    final Border? border = isCurrent
        ? Border.all(color: context.accent.withValues(alpha: 0.85), width: 1.4)
        : isSkipped
            ? Border.all(color: AppColors.tajweedMajor.withValues(alpha: 0.85), width: 1.4)
            : null;

    final Color textColor = hiddenWord
        ? Colors.transparent
        : (isSkipped && !isCurrent)
            ? AppColors.tajweedMajor
            : dark
                ? AppColors.nightInk
                : AppColors.ink;

    return GestureDetector(
      onTap: state.hidden ? () => state.toggleWord(index) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: border,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'UthmanicHafs',
            fontSize: 28,
            height: 1.95,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _MeaningCard extends StatelessWidget {
  final Dua dua;
  final Color soft;
  final bool dark;
  const _MeaningCard({required this.dua, required this.soft, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: dark ? AppColors.nightCard : AppColors.paperEdge,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: context.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dua.meaning, style: TextStyle(fontSize: 14.5, height: 1.5, color: soft)),
          const SizedBox(height: 12),
          Text(dua.source.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: context.accent,
              )),
        ],
      ),
    );
  }
}
