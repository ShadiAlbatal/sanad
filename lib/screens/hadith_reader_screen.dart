import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/hadith_corpus.dart' show hadithCollectionName;
import '../state/app_state.dart';
import '../state/hadith_finder_state.dart';
import '../state/hadith_reading_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/hadith_reading_footer.dart';

/// One hadith, read-along. Shows the matn (RTL Arabic) where each word tracks the
/// reciter (current / read) exactly like the du'a reader, plus its `Bukhari #n` /
/// `Muslim #n` reference. Its [HadithReadingState] is scoped to this screen and,
/// while open, its follow-along OWNS the shared mic (claimed from the hadith
/// finder) — so reciting greens the matn rather than jumping. The hadith text
/// carries the isnād first; a reciter usually recites only the matn, so the isnād
/// words simply won't green (expected until the matn-only data swap).
///
/// The finder's pick listener is retained so a voice-jump routed from the search
/// screen still opens the matched hadith here; within the reader the mic follows
/// along (single-owner [AsrEngine.claimMic]).
class HadithReaderScreen extends StatefulWidget {
  final String collection;
  final int number;
  final String text;

  /// When opened from the "recite to find" finder the user is already reciting,
  /// so begin the follow-along the moment the clip is ready (mirrors the du'a
  /// reader) — the reader claims the shared mic from the finder and re-anchors on
  /// the live audio without a second tap.
  final bool autoStart;
  const HadithReaderScreen(
      {super.key,
      required this.collection,
      required this.number,
      required this.text,
      this.autoStart = false});

  String get label => '${hadithCollectionName(collection)} #$number';
  String get _id => '$collection:$number';

  @override
  State<HadithReaderScreen> createState() => _HadithReaderScreenState();
}

class _HadithReaderScreenState extends State<HadithReaderScreen> {
  HadithFinderState? _finder;

  @override
  void initState() {
    super.initState();
    final sw = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Log.d('hadithread', 'reader first frame painted in ${sw.elapsedMilliseconds}ms '
          '(${widget.text.length} chars)');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final finder = context.read<HadithFinderState>();
    if (!identical(finder, _finder)) {
      _finder?.removeListener(_onFinder);
      _finder = finder;
      _finder!.addListener(_onFinder);
    }
  }

  void _onFinder() {
    final finder = _finder;
    final pick = finder?.pick;
    if (finder == null || pick == null) return;
    // Only the visible (top) route reacts; the search screen under us stays put.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    finder.clearPick();
    if (pick.id == widget._id) return; // already showing this hadith
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => HadithReaderScreen(
              collection: pick.collection, number: pick.number, text: pick.text)));
    });
  }

  @override
  void dispose() {
    _finder?.removeListener(_onFinder);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.read<AppState>().setLastHadithId(widget._id);
    return ChangeNotifierProvider(
      create: (ctx) {
        final state = HadithReadingState(ctx.read<AsrEngine>());
        final loaded = state.loadHadith(widget._id);
        if (widget.autoStart) {
          loaded.then((_) =>
              WidgetsBinding.instance.addPostFrameCallback((_) => state.startListening()));
        }
        return state;
      },
      child: _HadithReaderView(
          label: widget.label, collection: widget.collection, number: widget.number, text: widget.text),
    );
  }
}

class _HadithReaderView extends StatelessWidget {
  final String label;
  final String collection;
  final int number;
  final String text;
  const _HadithReaderView(
      {required this.label,
      required this.collection,
      required this.number,
      required this.text});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HadithReadingState>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            // Word-level render once the follow-along clip is loaded (each word
            // greens as recited); a plain block until then / on a find-only asset.
            child: state.hasClip
                ? Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < state.words.length; i++)
                        _HadithWord(index: i, text: state.words[i], state: state, dark: dark),
                    ],
                  )
                : Text(
                    text,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: 'UthmanicHafs', fontSize: 26, height: 2.1),
                  ),
          ),
          const SizedBox(height: 20),
          Text('${hadithCollectionName(collection).toUpperCase()} · #$number',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: context.accent,
              )),
        ],
      ),
      bottomNavigationBar: const HadithReadingFooter(),
    );
  }
}

class _HadithWord extends StatelessWidget {
  final int index;
  final String text;
  final HadithReadingState state;
  final bool dark;
  const _HadithWord({
    required this.index,
    required this.text,
    required this.state,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = state.currentWord == index;
    final isRead = state.readWords.contains(index);

    final Color? bg = isCurrent
        ? (dark ? Colors.white : context.accent).withValues(alpha: dark ? 0.28 : 0.20)
        : isRead
            ? (dark ? Colors.white : context.accent).withValues(alpha: dark ? 0.16 : 0.10)
            : null;

    final Border? border = isCurrent
        ? Border.all(color: context.accent.withValues(alpha: 0.85), width: 1.4)
        : null;

    final Color textColor = dark ? AppColors.nightInk : AppColors.ink;

    return Container(
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
          fontSize: 26,
          height: 2.05,
          color: textColor,
        ),
      ),
    );
  }
}
