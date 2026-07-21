import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/duas.dart';
import '../services/asr/dua_corpus.dart';
import '../services/asr/dua_search.dart';
import '../services/search/bookmarks.dart';
import '../services/search/corpus_text_search.dart';
import '../services/search/search_history.dart';
import '../services/search/text_search.dart';
import '../state/app_state.dart';
import '../state/voice_search_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/bookmark_star.dart';
import '../widgets/highlighted_arabic.dart';
import '../widgets/search_list_scaffold.dart';
import 'dua_reader_screen.dart';
import 'voice_search_list_mixin.dart';

/// The Azkar tab's root: the browsable list of du'ās & adhkār (Hisn al-Muslim,
/// ~260) from the bundled du'a corpus, rendered through the shared
/// [SearchListScaffold] (content list + unified footer). Voice + typed search
/// run through [VoiceSearchListMixin] (FastConformer live-transcription →
/// BM25); tapping a card — or a confident voice match — opens its reader,
/// already following along.
class DuaListScreen extends StatefulWidget {
  const DuaListScreen({super.key});

  @override
  State<DuaListScreen> createState() => _DuaListScreenState();
}

class _DuaListScreenState extends State<DuaListScreen>
    with VoiceSearchListMixin<DuaListScreen, TextSearchHit> {
  DuaSearch? _search;
  TextSearch? _textSearch;
  List<Map<String, dynamic>> _history = const [];
  List<Map<String, dynamic>> _bookmarks = const [];

  @override
  void initState() {
    super.initState();
    // Same cached, off-thread corpus the search uses — rendered here for browsing.
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
    final prefs = context.read<AppState>().prefs;
    _history = decodeHistory(prefs.duaHistory);
    _bookmarks = decodeHistory(prefs.duaBookmarks);
  }

  void _recordHistory(Dua dua) {
    final prefs = context.read<AppState>().prefs;
    final updated = pushHistory(prefs.duaHistory, {'key': dua.id, 'label': dua.title});
    prefs.setDuaHistory(updated);
    setState(() => _history = decodeHistory(updated));
  }

  bool _isBookmarked(String id) => _bookmarks.any((e) => e['key'] == id);

  // Entry-based so removal from the sheet needs no corpus lookup — the stored
  // entry already carries key+label; the card path just builds the same entry.
  void _toggleBookmarkEntry(Map<String, dynamic> entry) {
    final prefs = context.read<AppState>().prefs;
    final updated = toggleBookmark(prefs.duaBookmarks, entry);
    prefs.setDuaBookmarks(updated);
    setState(() => _bookmarks = decodeHistory(updated));
  }

  void _toggleBookmark(Dua dua) =>
      _toggleBookmarkEntry({'key': dua.id, 'label': dua.title});

  @override
  int get voiceTab => Tabs.dua;
  @override
  String get logTag => 'dualist';
  @override
  List<TextSearchHit> runSearch(String q) => _textSearch?.search(q) ?? const [];
  @override
  ({String id, double score}) scoreOf(TextSearchHit hit) =>
      (id: hit.id, score: hit.score);
  @override
  void openHit(TextSearchHit hit) {
    final meta = _search?.metaById(hit.id);
    if (meta != null) _open(_duaFromMeta(meta), autoStart: true);
  }

  Dua _duaFromMeta(DuaMeta m) => Dua(
        id: m.id,
        title: m.title,
        source: m.source,
        arabic: m.arabic,
        meaning: m.meaning,
      );

  // autoStart (mic on, follow-along begins immediately) ONLY for a confident
  // voice-search open — the user was already reciting. A tap from browse or
  // typed search leaves the mic off; the reader still offers a manual mic tap.
  void _open(Dua dua, {bool autoStart = false}) {
    _recordHistory(dua);
    openRoute((_) => DuaReaderScreen(dua: dua, autoStart: autoStart));
  }

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceSearchState>();
    final metas = _search?.allDuas;
    final leadExpanded = voice.recording && voiceQuery;

    final int count;
    final IndexedWidgetBuilder builder;
    if (searching) {
      count = results.length;
      builder = (_, i) {
        final hit = results[i];
        final meta = _search!.metaById(hit.id)!;
        final dua = _duaFromMeta(meta);
        return _DuaCard(
          dua: dua,
          matched: hit.matchedWords,
          onTap: () => _open(dua),
          expanded: leadExpanded && i == 0,
          confidence: voiceQuery && i < rings.length ? rings[i] : null,
          bookmarked: _isBookmarked(dua.id),
          onToggleBookmark: () => _toggleBookmark(dua),
        );
      };
    } else {
      count = metas?.length ?? 0;
      builder = (_, i) {
        final dua = _duaFromMeta(metas![i]);
        return _DuaCard(
          dua: dua,
          onTap: () => _open(dua),
          bookmarked: _isBookmarked(dua.id),
          onToggleBookmark: () => _toggleBookmark(dua),
        );
      };
    }
    final countLabel = searching
        ? '$count result${count == 1 ? '' : 's'}'
        : (metas != null ? '$count duas' : null);

    return SearchListScaffold(
      title: 'Duas & Adhkār',
      loading: metas == null,
      itemCount: count,
      itemBuilder: builder,
      scrollController: scrollController,
      countLabel: countLabel,
      history: _history,
      bookmarks: _bookmarks,
      // label-first; ?? title keeps du'ā history persisted before the field
      // was unified on 'label' still rendering.
      labelOf: (e) => (e['label'] ?? e['title']) as String,
      onOpenEntry: (e) {
        final meta = _search?.metaById(e['key'] as String);
        if (meta != null) _open(_duaFromMeta(meta));
      },
      onRemoveBookmark: _toggleBookmarkEntry,
      emptyState: searching ? const _NoMatches() : null,
      listening: voice.recording,
      starting: voice.busy,
      level: voice.level,
      heard: '',
      hearingLabel: voice.recording ? 'Listening… tap to search' : 'Preparing…',
      onMicTap: toggleMic,
      micIdleLabel: 'Recite to find a du\'ā',
      searchController: searchController,
      onSearchChanged: onSearchChanged,
      searchHint: 'Search du\'ās',
      onClear: clearSearch,
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
  final bool expanded; // the live leading result: show more matching text
  final double? confidence; // 0..1 trust ring (null = no ring)
  final bool bookmarked;
  final VoidCallback? onToggleBookmark;
  const _DuaCard(
      {required this.dua,
      required this.onTap,
      this.matched = const {},
      this.expanded = false,
      this.confidence,
      this.bookmarked = false,
      this.onToggleBookmark});

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
          border: expanded ? Border.all(color: context.accent.withValues(alpha: 0.6), width: 1.4) : null,
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
                if (onToggleBookmark != null)
                  BookmarkStar(bookmarked: bookmarked, onToggle: onToggleBookmark!),
                if (confidence != null)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      value: confidence!.clamp(0.0, 1.0),
                      strokeWidth: 2.5,
                      backgroundColor: soft.withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation(context.accent),
                    ),
                  )
                else
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
                maxLines: expanded ? 8 : 2,
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
