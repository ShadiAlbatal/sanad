import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/quran_repository.dart';
import '../models/mushaf.dart';
import '../services/asr/quran_search.dart';
import '../state/quran_finder_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/highlighted_arabic.dart';
import '../widgets/search_list_scaffold.dart';
import 'quran_screen.dart';

/// The Quran TAB, rendered through the shared [SearchListScaffold] (content list +
/// unified footer) — the Quran sibling of the Du'a and Hadith tabs. Three renderings
/// through one shell, in priority order:
///  1. reciting → the finder's live ranked verse candidates (VOICE, global over all
///     114 surahs via [QuranFinderState]); a confident pick opens the reader at that
///     verse's page;
///  2. a typed query → ranked BM25 verse results with the matched words highlighted;
///  3. idle → browse the 114-surah index.
/// Never a dead end. Tapping any surah opens the reader at its start page; tapping a
/// verse result / candidate opens the reader at that verse's page. The reader
/// ([QuranScreen]) is a PUSHED route (its follow-along [ReadingState] is app-global),
/// so opening it from here hands the shared mic over cleanly (single-owner claim).
class QuranListScreen extends StatefulWidget {
  const QuranListScreen({super.key});

  @override
  State<QuranListScreen> createState() => _QuranListScreenState();
}

class _QuranListScreenState extends State<QuranListScreen> {
  QuranFinderState? _finder;
  QuranSearch? _search;
  List<Chapter>? _chapters;
  final _searchController = TextEditingController();

  Timer? _debounce;
  String _query = '';
  List<QuranTextHit> _results = const [];
  // Last voice candidates, kept after the mic stops (see hadith_search_screen).
  List<QuranCandidate> _voiceCache = const [];

  @override
  void initState() {
    super.initState();
    // The 114-surah browse list.
    context.read<QuranRepository>().chapters().then((c) {
      if (mounted) setState(() => _chapters = c);
    }).catchError((Object e) {
      Log.e('quranlist', 'chapters load failed: $e');
    });
    // The global voice + typed search index — the same cached, off-thread build the
    // finder uses (loadQuranSearch is memoized), rendered here for the typed bar.
    loadQuranSearch().then((s) {
      if (mounted) setState(() => _search = s);
    }).catchError((Object e) {
      Log.e('quranlist', 'search index load failed: $e');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final finder = context.read<QuranFinderState>();
    if (!identical(finder, _finder)) {
      _finder?.removeListener(_onFinder);
      _finder = finder;
      _finder!.addListener(_onFinder);
      finder.preload(); // build the index off-thread on first tab open
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final query = q.trim();
      setState(() {
        _query = query;
        _results = query.isEmpty ? const [] : (_search?.searchText(query) ?? const []);
      });
    });
  }

  void _onFinder() {
    final finder = _finder;
    final pick = finder?.pick;
    if (finder == null || pick == null) return;
    // A pushed reader (on top) owns the pick; don't double-navigate from under it.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    finder.clearPick();
    _open(pick.page);
  }

  // Opening the reader takes a beat (asset decode, curl setup) with no visible
  // feedback in between — without this guard a user who taps again (thinking the
  // first tap missed) stacks a duplicate push per extra tap, so Back has to pop
  // through all of them. One in-flight navigation at a time.
  bool _opening = false;

  void _open(int page) {
    if (_opening) return;
    _opening = true;
    final finder = _finder;
    if (finder != null && finder.listening) finder.stop(); // clean mic handoff to the reader
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => QuranScreen(initialPage: page)))
          .then((_) {
        if (mounted) setState(() => _opening = false);
      });
    });
    // A bare GestureDetector tap changes nothing visually, so Flutter schedules no
    // frame — and the post-frame callback above then never fires until the next
    // unrelated input (a stray swipe) forces one, which is why tap-to-open hung
    // for seconds. Force a frame so the push runs on the very next tick.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _finder?.removeListener(_onFinder);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleMic(QuranFinderState finder) async {
    if (finder.listening) {
      await finder.stop();
      return;
    }
    setState(() => _voiceCache = const []); // fresh recitation → drop the last matches
    await finder.start();
    if (finder.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(finder.error!)));
    }
  }

  // Surah name for a 1-based surah number (chapters are stored in order); a bare
  // "Surah N" until the index has loaded.
  String _surahName(int surah) {
    final list = _chapters;
    if (list == null || surah < 1 || surah > list.length) return 'Surah $surah';
    return list[surah - 1].nameSimple;
  }

  String _verseLabel(int surah, int ayah) => '${_surahName(surah)} · Ayah $ayah';

  String _finderLabel(QuranFinderState finder) {
    if (!finder.heardSomething) return 'Listening…';
    final lead = finder.leading;
    return lead == null ? 'Matching…' : 'Hearing: ${_verseLabel(lead.surah, lead.ayah)}?';
  }

  @override
  Widget build(BuildContext context) {
    final finder = context.watch<QuranFinderState>();
    if (finder.listening && finder.candidates.isNotEmpty) _voiceCache = finder.candidates;
    final showCandidates = _query.isEmpty && _voiceCache.isNotEmpty;
    final searching = _query.isNotEmpty;
    final chapters = _chapters;

    final int count;
    final IndexedWidgetBuilder builder;
    if (showCandidates) {
      count = _voiceCache.length;
      builder = (_, i) => _VerseCard(
            label: _verseLabel(_voiceCache[i].surah, _voiceCache[i].ayah),
            text: _voiceCache[i].text,
            matched: finder.matchedWords(_voiceCache[i].id),
            onTap: () => _open(_voiceCache[i].page),
          );
    } else if (searching) {
      count = _results.length;
      builder = (_, i) {
        final hit = _results[i];
        return _VerseCard(
          label: _verseLabel(hit.meta.surah, hit.meta.ayah),
          text: hit.meta.text,
          matched: hit.matchedWords,
          onTap: () => _open(hit.meta.page),
        );
      };
    } else {
      count = chapters?.length ?? 0;
      builder = (_, i) => _SurahCard(chapter: chapters![i], onTap: () => _open(chapters[i].startPage));
    }

    return SearchListScaffold(
      title: 'Quran',
      subtitle: 'Recite a verse to find it, or tap a surah to read',
      loading: !showCandidates && !searching && chapters == null,
      itemCount: count,
      itemBuilder: builder,
      emptyState: searching ? const _NoMatches() : null,
      listening: finder.listening,
      starting: finder.starting,
      level: finder.level,
      heard: finder.heard,
      hearingLabel: _finderLabel(finder),
      onMicTap: () => _toggleMic(finder),
      micIdleLabel: 'Recite to find a verse',
      searchController: _searchController,
      onSearchChanged: _onSearchChanged,
      searchHint: 'Search the Quran',
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text('No matches — clear the search to browse surahs',
            textAlign: TextAlign.center, style: TextStyle(color: soft, fontSize: 14)),
      ),
    );
  }
}

/// A browse row for one of the 114 surahs: gold badge number, name + translation +
/// verse count. Mirrors the surah-index sheet's row inside the shared card shell.
class _SurahCard extends StatelessWidget {
  final Chapter chapter;
  final VoidCallback onTap;
  const _SurahCard({required this.chapter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _SurahBadge(number: chapter.id),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chapter.nameSimple,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${chapter.translated} · ${chapter.versesCount} verses',
                      style: TextStyle(color: soft, fontSize: 12.5)),
                ],
              ),
            ),
            Text(chapter.nameArabic,
                style: const TextStyle(fontFamily: 'UthmanicHafs', fontSize: 22)),
          ],
        ),
      ),
    );
  }
}

/// A verse result / voice candidate: a surah·ayah reference over the verse text,
/// with the matched words highlighted — typed BM25 terms, or (for a voice
/// candidate) the words the recitation matched.
class _VerseCard extends StatelessWidget {
  final String label;
  final String text;
  final Set<String> matched;
  final VoidCallback onTap;
  const _VerseCard(
      {required this.label, required this.text, required this.onTap, this.matched = const {}});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: context.accent,
                      )),
                ),
                Icon(Icons.chevron_right_rounded, color: soft),
              ],
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: HighlightedArabic(
                text: text,
                matched: matched,
                highlight: context.accent,
                style: const TextStyle(
                  fontFamily: 'UthmanicHafs',
                  fontSize: 21,
                  height: 1.9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The diamond-outlined surah number badge, matching the surah-index sheet.
class _SurahBadge extends StatelessWidget {
  final int number;
  const _SurahBadge({required this.number});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.gold, width: 1.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Text('$number',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
