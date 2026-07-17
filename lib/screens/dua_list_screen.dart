import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/duas.dart';
import '../services/asr/dua_corpus.dart';
import '../services/asr/dua_search.dart';
import '../services/search/corpus_text_search.dart';
import '../services/search/text_search.dart';
import '../state/dua_finder_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/highlighted_arabic.dart';
import '../widgets/search_list_scaffold.dart';
import 'dua_reader_screen.dart';

/// The Azkar tab's root: the browsable list of du'ās & adhkār (existing 5 + Hisn
/// al-Muslim, ~260), sourced from the bundled du'a corpus, rendered through the
/// shared [SearchListScaffold] (content list + unified footer). Tapping a card
/// opens its reader. The footer's mic runs the "recite to open" finder
/// ([DuaFinderState]); this screen also listens for the finder's pick and opens
/// that du'a's reader, already following along.
class DuaListScreen extends StatefulWidget {
  const DuaListScreen({super.key});

  @override
  State<DuaListScreen> createState() => _DuaListScreenState();
}

class _DuaListScreenState extends State<DuaListScreen> {
  DuaFinderState? _finder;
  DuaSearch? _search;
  TextSearch? _textSearch;
  final _searchController = TextEditingController();

  Timer? _debounce;
  String _query = '';
  List<TextSearchHit> _results = const [];
  // Last voice candidates, kept after the mic stops (see hadith_search_screen).
  List<DuaCandidate> _voiceCache = const [];

  @override
  void initState() {
    super.initState();
    // Same cached, off-thread corpus the finder uses — rendered here for browsing.
    loadDuaSearch().then((s) {
      if (mounted) setState(() => _search = s);
    }).catchError((Object e) {
      Log.e('dualist', 'corpus load failed: $e');
    });
    // The typed-search BM25 index (built off-thread from the same corpus).
    loadDuaTextSearch().then((t) {
      if (mounted) setState(() => _textSearch = t);
    }).catchError((Object e) {
      Log.e('dualist', 'text index load failed: $e');
    });
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final query = q.trim();
      setState(() {
        _query = query;
        _results = query.isEmpty ? const [] : (_textSearch?.search(query) ?? const []);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final finder = context.read<DuaFinderState>();
    if (!identical(finder, _finder)) {
      _finder?.removeListener(_onFinder);
      _finder = finder;
      _finder!.addListener(_onFinder);
      finder.preload();
    }
  }

  Dua _duaFromMeta(DuaMeta m) => Dua(
        id: m.id,
        title: m.title,
        source: m.source,
        arabic: m.arabic,
        meaning: m.meaning,
      );

  void _onFinder() {
    final finder = _finder;
    final id = finder?.identifiedDuaId;
    if (finder == null || id == null) return;
    final meta = _search?.metaById(id);
    finder.clearIdentified(); // consume the pick so we open exactly once
    if (meta == null) return;
    _open(_duaFromMeta(meta), autoStart: true);
  }

  // See QuranListScreen._opening — same rapid-double-tap guard against stacked
  // pushes while the reader takes a beat to open.
  bool _opening = false;

  void _open(Dua dua, {bool autoStart = false}) {
    if (_opening) return;
    _opening = true;
    // Tapping a candidate while still reciting (before the finder auto-picks) left
    // the search mic running under the pushed reader — only the auto-pick path
    // stopped it. Stop explicitly here too; a no-op once the finder has already
    // stopped itself (e.g. the confident-pick autoStart path).
    final finder = _finder;
    if (finder != null && finder.listening) finder.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => DuaReaderScreen(dua: dua, autoStart: autoStart)))
          .then((_) {
        if (mounted) setState(() => _opening = false);
      });
    });
  }

  @override
  void dispose() {
    _finder?.removeListener(_onFinder);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleMic(DuaFinderState finder) async {
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

  String _finderLabel(DuaFinderState finder) {
    if (!finder.heardSomething) return 'Listening…';
    final title = finder.leadingDuaTitle;
    if (title != null) return 'Hearing: $title?';
    return 'Matching…';
  }

  @override
  Widget build(BuildContext context) {
    final finder = context.watch<DuaFinderState>();
    if (finder.listening && finder.candidates.isNotEmpty) _voiceCache = finder.candidates;
    final showCandidates = _query.isEmpty && _voiceCache.isNotEmpty;
    final searching = _query.isNotEmpty;
    final metas = _search?.allDuas;

    // Three renderings through one card + scaffold, in priority order (mirrors the
    // Hadith/Quran tabs):
    //  1. voice matches (live or last-recited) — each row bolds the words the
    //     recitation matched (finder.matchedWords, via the corpus word map);
    //  2. a typed query → ranked BM25 results with the matched words highlighted;
    //  3. idle → browse the whole corpus. Never a dead end.
    final int count;
    final IndexedWidgetBuilder builder;
    if (showCandidates) {
      count = _voiceCache.length;
      builder = (_, i) => _DuaCard(
            dua: _duaFromMeta(_voiceCache[i].meta),
            matched: finder.matchedWords(_voiceCache[i].id),
            onTap: () => _open(_duaFromMeta(_voiceCache[i].meta)),
          );
    } else if (searching) {
      count = _results.length;
      builder = (_, i) {
        final hit = _results[i];
        final meta = _search!.metaById(hit.id)!;
        return _DuaCard(
            dua: _duaFromMeta(meta),
            matched: hit.matchedWords,
            onTap: () => _open(_duaFromMeta(meta)));
      };
    } else {
      count = metas?.length ?? 0;
      builder = (_, i) => _DuaCard(
          dua: _duaFromMeta(metas![i]), onTap: () => _open(_duaFromMeta(metas[i])));
    }

    return SearchListScaffold(
      title: 'Duas & Adhkār',
      subtitle: 'Recite to open, or tap a du\'ā — words light up as you read',
      loading: !showCandidates && metas == null,
      itemCount: count,
      itemBuilder: builder,
      emptyState: searching ? const _NoMatches() : null,
      listening: finder.listening,
      starting: finder.starting,
      level: finder.level,
      heard: finder.heard,
      hearingLabel: _finderLabel(finder),
      onMicTap: () => _toggleMic(finder),
      micIdleLabel: 'Recite to find a du\'ā',
      searchController: _searchController,
      onSearchChanged: _onSearchChanged,
      searchHint: 'Search du\'ās',
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
        child: Text('No matches — clear the search to browse all',
            textAlign: TextAlign.center, style: TextStyle(color: soft, fontSize: 14)),
      ),
    );
  }
}

class _DuaCard extends StatelessWidget {
  final Dua dua;
  final Set<String> matched; // typed-search matched words to highlight ('' when browsing)
  final VoidCallback onTap;
  const _DuaCard({required this.dua, required this.onTap, this.matched = const {}});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(dua.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.chevron_right_rounded, color: soft),
              ],
            ),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.rtl,
              child: HighlightedArabic(
                text: dua.arabic,
                matched: matched,
                highlight: context.accent,
                style: const TextStyle(
                  fontFamily: 'UthmanicHafs',
                  fontSize: 22,
                  height: 1.9,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(dua.source.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: context.accent,
                )),
          ],
        ),
      ),
    );
  }
}
