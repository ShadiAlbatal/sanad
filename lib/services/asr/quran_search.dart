import 'dart:isolate';
import 'package:flutter/services.dart' show rootBundle;
import 'phoneme_corpus.dart' show loadVersePages;
import 'phoneme_finder.dart';
import 'quran_corpus.dart';
import '../search/text_search.dart';
import '../../util/log.dart';

/// A ranked Quran verse candidate: navigation metadata + the finder's per-token
/// score. `pick != null` on a [QuranSearchResult] means this verse cleared the
/// confidence bar. [id] is "surah:ayah" — the finder key and the reader jump key.
class QuranCandidate {
  final QuranVerseMeta meta;
  final double score;
  const QuranCandidate(this.meta, this.score);

  String get id => meta.id;
  int get surah => meta.surah;
  int get ayah => meta.ayah;
  int get page => meta.page;
  String get text => meta.text;
}

/// Never a dead end: [pick] is the confident single winner (or null), and
/// [candidates] is ALWAYS the ranked top-K to show.
class QuranSearchResult {
  final QuranCandidate? pick;
  final List<QuranCandidate> candidates;
  const QuranSearchResult(this.pick, this.candidates);
  bool get confident => pick != null;
}

/// One typed-search hit: the verse [meta] plus the matched query terms and where
/// they fall in the verse's normalized word list — enough to HIGHLIGHT and open it.
class QuranTextHit {
  final QuranVerseMeta meta;
  final double score;
  final List<int> matchedWordPositions;
  final Set<String> matchedWords;
  const QuranTextHit(this.meta, this.score, this.matchedWordPositions, this.matchedWords);

  String get id => meta.id;
}

/// GLOBAL Quran voice + text search over all 114 surahs / ~6,236 verses — the
/// Quran sibling of [HadithSearch]/[DuaSearch]. A shared [PhonemeFinder] over the
/// verse [FindDoc]s identifies a recited verse anywhere in the Quran (IDF 3-gram
/// prefilter → localizer rerank → [decideFind] gate), and a [TextSearch] BM25
/// index over the same verse text serves the typed bar. Pure retrieval: no mic,
/// no ASR engine, no UI state — build once (holds both indexes), then [find] a
/// recited span or [searchText] a typed phrase.
///
/// [floor]/[margin] mirror the recalibrated hadith/du'a gates (0.9/0.5) — margin
/// is the primary separator, floor a low sanity floor. Provisional-by-analogy
/// (the finders share one engine, so the score regime is the same) — DEVICE-PENDING
/// like every ASR threshold here. Note the Quran has genuine repeated verses (e.g.
/// Ar-Rahman's refrain, the Basmala) that are exact duplicates; [decideFindBest]
/// collapses them via [dupKeyOf] so a repeat is never counted as its own runner-up.
class QuranSearch {
  final PhonemeFinder _finder;
  final TextSearch _text;
  final List<QuranVerseMeta> allVerses; // surah/ayah order — the browsable list
  final Map<String, QuranVerseMeta> _meta;
  final double floor;
  final double margin;

  QuranSearch(QuranCorpus corpus, {this.floor = 0.9, this.margin = 0.5})
      : _finder = PhonemeFinder(corpus.docs),
        _text = TextSearch([for (final v in corpus.verses) TextSearchDoc(v.id, v.text)]),
        allVerses = corpus.verses,
        _meta = corpus.byId;

  int get verseCount => _meta.length;
  int get ngramKeys => _finder.ngramKeys;

  /// Resolve a finder id ("2:255") back to its verse — used to open a hit's reader.
  QuranVerseMeta? verseById(String id) => _meta[id];

  /// Duplicate key for a verse id — see [PhonemeFinder.dupKeyOf].
  String dupKeyOf(String id) => _finder.dupKeyOf(id);

  /// The normalized display words of verse candidate [id] that the recited
  /// [queryPhonemes] matched — same `Set<String>` contract as the typed BM25 path,
  /// so a VOICE candidate row highlights identically. Empty on a too-short query.
  Set<String> matchedWords(String id, List<String> queryPhonemes) =>
      matchedDisplayWords(_finder, id, queryPhonemes);

  static Future<QuranSearch> load({double floor = 0.9, double margin = 0.5}) async =>
      QuranSearch(await loadQuranCorpus(), floor: floor, margin: margin);

  /// Voice: rank verses against a recited phoneme span, with the confident single
  /// pick gated by [decideFind] (floor + margin over the runner-up).
  QuranSearchResult find(List<String> queryPhonemes, {int top = 5}) {
    final results = _finder.search(queryPhonemes, top: top);
    final candidates = [for (final r in results) QuranCandidate(_meta[r.id]!, r.score)];
    final decision = decideFind(results, floor: floor, margin: margin);
    final pick =
        decision.pick == null ? null : candidates.firstWhere((c) => c.id == decision.pick);
    return QuranSearchResult(pick, candidates);
  }

  /// Typed: BM25 over verse text, returning the matched-word positions per hit for
  /// highlighting. Empty / no-term query yields no hits (caller browses the list).
  List<QuranTextHit> searchText(String query, {int top = 100}) => [
        for (final h in _text.search(query, top: top))
          QuranTextHit(_meta[h.id]!, h.score, h.matchedWordPositions, h.matchedWords)
      ];
}

QuranSearch? _searchCache;
Future<QuranSearch>? _searchLoading;

/// Lazily build (once, cached) the global Quran search index off the UI thread —
/// mirrors loadHadithSearch. The 114 asset reads + verse-index read use platform
/// channels (main isolate only); the decode, 3-gram index build and BM25 build run
/// in an `Isolate.run` so opening the Quran search never janks a frame. Concurrent
/// callers share ONE in-flight build via [_searchLoading].
Future<QuranSearch> loadQuranSearch({double floor = 0.9, double margin = 0.5}) async {
  final cached = _searchCache;
  if (cached != null) return cached;
  final inflight = _searchLoading;
  if (inflight != null) return inflight;
  return _searchLoading = _loadQuranSearch(floor: floor, margin: margin);
}

Future<QuranSearch> _loadQuranSearch({required double floor, required double margin}) async {
  final sw = Stopwatch()..start();
  try {
    final versePages = await loadVersePages();
    final surahJson = <String>[];
    for (var s = 1; s <= 114; s++) {
      final tag = s.toString().padLeft(3, '0');
      surahJson.add(await rootBundle.loadString('assets/asr/quran_phonemes/$tag.json'));
    }
    Log.d('quranfind', 'assets read: 114 surah files + verse index, '
        'read ${sw.elapsedMilliseconds}ms — building index off-thread…');
    final search = await Isolate.run(
        () => QuranSearch(QuranCorpus.decode(surahJson, versePages), floor: floor, margin: margin));
    Log.d('quranfind', 'corpus ready: ${search.verseCount} verses, ${search.ngramKeys} 3-gram keys, '
        'floor=$floor margin=$margin, build ${sw.elapsedMilliseconds}ms');
    return _searchCache = search;
  } catch (e, st) {
    _searchLoading = null; // let a later caller retry the build
    Log.e('quranfind', 'corpus load FAILED after ${sw.elapsedMilliseconds}ms: $e', st);
    rethrow;
  }
}
