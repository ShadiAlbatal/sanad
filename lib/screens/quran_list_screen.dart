import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/quran_repository.dart';
import '../models/mushaf.dart';
import '../services/asr/quran_search.dart';
import '../services/search/bookmarks.dart';
import '../services/search/search_history.dart';
import '../state/app_state.dart';
import '../state/voice_search_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/bookmark_star.dart';
import '../widgets/highlighted_arabic.dart';
import '../widgets/search_list_scaffold.dart';
import 'quran_screen.dart';
import 'voice_search_list_mixin.dart';
import '../l10n/app_localizations.dart';

/// The Quran TAB, rendered through the shared [SearchListScaffold] (content list +
/// unified footer) — the Quran sibling of the Du'a and Hadith tabs. Three
/// renderings through one shell, in priority order:
///  1. reciting → live ranked verse candidates (VOICE, global over all 114 surahs
///     via [VoiceSearchListMixin]); a confident pick opens the reader at that
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

class _QuranListScreenState extends State<QuranListScreen>
    with VoiceSearchListMixin<QuranListScreen, QuranTextHit> {
  QuranSearch? _search;
  List<Chapter>? _chapters;
  List<Map<String, dynamic>> _history = const [];
  List<Map<String, dynamic>> _bookmarks = const [];

  @override
  void initState() {
    super.initState();
    // The 114-surah browse list.
    context.read<QuranRepository>().chapters().then((c) {
      if (mounted) setState(() => _chapters = c);
    }).catchError((Object e) {
      Log.e('quranlist', 'chapters load failed: $e');
    });
    // The global voice + typed search index — the same cached, off-thread build,
    // memoized (loadQuranSearch), rendered here for the typed bar.
    loadQuranSearch().then((s) {
      if (mounted) setState(() => _search = s);
    }).catchError((Object e) {
      Log.e('quranlist', 'search index load failed: $e');
    });
    final prefs = context.read<AppState>().prefs;
    _history = decodeHistory(prefs.quranHistory);
    _bookmarks = decodeHistory(prefs.quranBookmarks);
  }

  void _recordHistory(int page, String label) {
    final prefs = context.read<AppState>().prefs;
    final updated = pushHistory(prefs.quranHistory, {'key': '$page', 'page': page, 'label': label});
    prefs.setQuranHistory(updated);
    setState(() => _history = decodeHistory(updated));
  }

  bool _isBookmarked(String key) => _bookmarks.any((e) => e['key'] == key);

  // key is identity ('surah:3' / 'ayah:2:255'), NOT the page — several surahs
  // share a mushaf start page (112/113/114 all open page 604), so a page key
  // would make them one bookmark that clobbers the others. page rides along
  // as a separate field for _open.
  void _toggleBookmark(String key, int page, String label) {
    final prefs = context.read<AppState>().prefs;
    final before = prefs.quranBookmarks.length;
    final updated =
        toggleBookmark(prefs.quranBookmarks, {'key': key, 'page': page, 'label': label});
    prefs.setQuranBookmarks(updated);
    Log.d(logTag,
        'bookmark ${updated.length > before ? '+' : '-'}$key -> ${updated.length} saved');
    setState(() => _bookmarks = decodeHistory(updated));
  }

  @override
  int get voiceTab => Tabs.quran;
  @override
  String get logTag => 'quranlist';
  @override
  List<QuranTextHit> runSearch(String q) => _search?.searchText(q) ?? const [];
  @override
  ({String id, double score}) scoreOf(QuranTextHit hit) =>
      (id: hit.id, score: hit.score);
  @override
  void openHit(QuranTextHit hit) => _open(
      hit.meta.page,
      _verseLabel(AppLocalizations.of(context)!, hit.meta.surah, hit.meta.ayah),
      autoStart: true);

  // autoStart (mic on, follow-along begins immediately) ONLY for a confident
  // voice-search open — the user was already reciting. A tap from browse or
  // typed search leaves the mic off; the reader still offers a manual mic tap.
  void _open(int page, String label, {bool autoStart = false}) {
    _recordHistory(page, label);
    openRoute((_) => QuranScreen(initialPage: page, autoStart: autoStart));
  }

  // Surah name for a 1-based surah number (chapters are stored in order); a bare
  // "Surah N" until the index has loaded.
  String _surahName(AppLocalizations t, int surah) {
    final list = _chapters;
    if (list == null || surah < 1 || surah > list.length) return t.surahNumber(surah);
    return list[surah - 1].nameSimple;
  }

  String _verseLabel(AppLocalizations t, int surah, int ayah) =>
      '${_surahName(t, surah)} · ${t.ayahNumber(ayah)}';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final voice = context.watch<VoiceSearchState>();
    final chapters = _chapters;
    final leadExpanded = voice.recording && voiceQuery;

    final int count;
    final IndexedWidgetBuilder builder;
    if (searching) {
      count = results.length;
      builder = (_, i) {
        final hit = results[i];
        final label = _verseLabel(t, hit.meta.surah, hit.meta.ayah);
        final key = 'ayah:${hit.meta.surah}:${hit.meta.ayah}';
        return _VerseCard(
          label: label,
          text: hit.meta.text,
          matched: hit.matchedWords,
          onTap: () => _open(hit.meta.page, label),
          expanded: leadExpanded && i == 0,
          confidence: voiceQuery && i < rings.length ? rings[i] : null,
          bookmarked: _isBookmarked(key),
          onToggleBookmark: () => _toggleBookmark(key, hit.meta.page, label),
        );
      };
    } else {
      count = chapters?.length ?? 0;
      builder = (_, i) => _SurahCard(
          chapter: chapters![i],
          onTap: () => _open(chapters[i].startPage, chapters[i].nameSimple),
          bookmarked: _isBookmarked('surah:${chapters[i].id}'),
          onToggleBookmark: () => _toggleBookmark(
              'surah:${chapters[i].id}', chapters[i].startPage, chapters[i].nameSimple));
    }
    final countLabel = searching
        ? t.resultCount(count)
        : (chapters != null ? t.surahsCount(count) : null);

    return SearchListScaffold(
      title: t.tabQuran,
      loading: !searching && chapters == null,
      itemCount: count,
      itemBuilder: builder,
      scrollController: scrollController,
      countLabel: countLabel,
      history: _history,
      bookmarks: _bookmarks,
      labelOf: (e) => e['label'] as String,
      onOpenEntry: (e) {
        Log.d(logTag, 'menu open ${e['key']} (page ${e['page']})');
        _open(e['page'] as int, e['label'] as String);
      },
      onRemoveBookmark: (e) =>
          _toggleBookmark(e['key'] as String, e['page'] as int, e['label'] as String),
      emptyState: searching ? const _NoMatches() : null,
      listening: voice.recording,
      starting: voice.busy,
      level: voice.level,
      heard: '',
      hearingLabel: voice.recording ? t.listeningTapToSearch : t.preparing,
      onMicTap: toggleMic,
      micIdleLabel: t.reciteToFindVerse,
      searchController: searchController,
      onSearchChanged: onSearchChanged,
      searchHint: t.searchQuran,
      onClear: clearSearch,
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(t.noMatchesBrowseSurahs,
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
  final bool bookmarked;
  final VoidCallback? onToggleBookmark;
  const _SurahCard(
      {required this.chapter, required this.onTap, this.bookmarked = false, this.onToggleBookmark});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
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
                  Text('${chapter.translated} · ${t.versesCount(chapter.versesCount)}',
                      style: TextStyle(color: soft, fontSize: 12.5)),
                ],
              ),
            ),
            if (onToggleBookmark != null)
              BookmarkStar(bookmarked: bookmarked, onToggle: onToggleBookmark!),
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
  final bool expanded; // the live leading result: show more matching text
  final double? confidence; // 0..1 trust ring (null = no ring)
  final bool bookmarked;
  final VoidCallback? onToggleBookmark;
  const _VerseCard(
      {required this.label,
      required this.text,
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(16),
          border: expanded ? Border.all(color: context.accent.withValues(alpha: 0.6), width: 1.4) : null,
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
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: HighlightedArabic(
                text: text,
                matched: matched,
                highlight: context.accent,
                maxLines: expanded ? 8 : 2,
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
