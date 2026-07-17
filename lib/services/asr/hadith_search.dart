import 'dart:isolate';
import 'package:flutter/services.dart' show rootBundle;
import 'hadith_corpus.dart';
import 'phoneme_corpus.dart' show loadPhonemeUnits;
import 'phoneme_finder.dart';
import '../search/text_search.dart' show matchedDisplayWords;
import '../../util/log.dart';

/// A ranked hadith candidate: collection-qualified reference + text plus the
/// finder's per-token score. `pick != null` on the result means this one cleared
/// the confidence bar. [id] ("bukhari:2790") is the finder key — unique across
/// collections, unlike [number] which collides between Bukhari and Muslim.
class HadithCandidate {
  final String collection;
  final int number;
  final String text;
  final double score;
  const HadithCandidate(this.collection, this.number, this.text, this.score);

  String get id => '$collection:$number';
  String get label => '${hadithCollectionName(collection)} #$number';
}

/// Never a dead end: [pick] is the confident single winner (or null), and
/// [candidates] is ALWAYS the ranked top-K to show — even when nothing is
/// confident, the caller has a list to render instead of an empty screen.
class HadithSearchResult {
  final HadithCandidate? pick;
  final List<HadithCandidate> candidates;
  const HadithSearchResult(this.pick, this.candidates);
  bool get confident => pick != null;
}

/// Pure retrieval over the loaded hadith corpus (Bukhari + Muslim) — no mic, no
/// ASR engine, no UI state. Build once (holds the PhonemeFinder index), then
/// [find] a query.
///
/// [floor]/[margin] gate the confident single pick. In the finder state the gate
/// runs over BEST-EVER peak scores with duplicate docs collapsed (see
/// [decideFindBest]); [HadithSearch.find] itself still uses the per-probe
/// [decideFind] for the host retrieval tests.
///
/// Values are DEVICE-TUNED (provisional starting points, like every ASR threshold
/// here) from run_20260717_023705.log. Margin is now the PRIMARY separator; the
/// floor is a low sanity floor:
///  - floor 0.9 (was 1.3): real correct partials scored 0.6–1.3 while the rolling
///    window held the matn; the old 1.3 sat at the very top of that range so real
///    matches decayed below it before the min-length gate opened. Isnād/noise
///    chance-matches at full length stay ~0.3–0.5, well under 0.9.
///  - margin 0.5 (was 0.4): correct #1s led the next DISTINCT hadith by ~0.8–1.0;
///    noise #1s led by only ~0.05–0.10 — 0.5 cleanly separates the two.
class HadithSearch {
  final PhonemeFinder _finder;
  final Map<String, HadithEntry> _meta;
  final List<HadithEntry> allHadith; // sorted by collection then number — the browsable list
  final double floor;
  final double margin;

  HadithSearch(HadithCorpus corpus, {this.floor = 0.9, this.margin = 0.5})
      : _finder = PhonemeFinder(corpus.docs),
        _meta = corpus.byId,
        allHadith = _sortedEntries(corpus.byId);

  // Built once at construction (inside the off-thread decode) so browsing never
  // re-sorts the ~14k-entry corpus on the finder's per-mic-chunk rebuilds.
  static List<HadithEntry> _sortedEntries(Map<String, HadithEntry> byId) {
    final list = byId.values.toList()
      ..sort((a, b) {
        final c = a.collection.compareTo(b.collection);
        return c != 0 ? c : a.number.compareTo(b.number);
      });
    return list;
  }

  int get docCount => _meta.length;
  int get ngramKeys => _finder.ngramKeys;

  /// Resolve a finder id ("bukhari:2790") back to its display entry — used by the
  /// typed-search bar to open a ranked hit's reader.
  HadithEntry? entryById(String id) => _meta[id];

  /// The per-hadith follow-along clip for the reader (null on a find-only asset
  /// with no word map). Reuses the already-decoded corpus — no second asset read.
  HadithClip? clipById(String id) => _meta[id]?.clip;

  /// Duplicate key for a hadith id — see [PhonemeFinder.dupKeyOf].
  String dupKeyOf(String id) => _finder.dupKeyOf(id);

  /// The normalized display words of candidate [id] that the recited
  /// [queryPhonemes] matched — the SAME `Set<String>` contract HighlightedArabic +
  /// the typed path use, so a VOICE candidate row highlights identically. Empty
  /// when the corpus carries no word map or the query is too short.
  Set<String> matchedWords(String id, List<String> queryPhonemes) =>
      matchedDisplayWords(_finder, id, queryPhonemes);

  static Future<HadithSearch> load({double floor = 0.9, double margin = 0.5}) async =>
      HadithSearch(await loadHadithCorpus(), floor: floor, margin: margin);

  HadithSearchResult find(List<String> queryPhonemes, {int top = 5}) {
    final results = _finder.search(queryPhonemes, top: top);
    final candidates = [
      for (final r in results)
        HadithCandidate(_meta[r.id]!.collection, _meta[r.id]!.number, _meta[r.id]!.text, r.score)
    ];
    final decision = decideFind(results, floor: floor, margin: margin);
    final pick =
        decision.pick == null ? null : candidates.firstWhere((c) => c.id == decision.pick);
    return HadithSearchResult(pick, candidates);
  }
}

HadithSearch? _searchCache;
Future<HadithSearch>? _searchLoading;

/// Lazily build (once, cached) the live-search index off the UI thread. The asset
/// read + vocab load use platform channels (main isolate only); the heavy decode
/// and 3-gram index build run in an `Isolate.run` so opening the Hadith tab never
/// janks a frame. Concurrent callers (screen initState + finder preload on first
/// open) share ONE in-flight build via [_searchLoading] — without it both would
/// run the ~14 MB corpus decode + index build.
Future<HadithSearch> loadHadithSearch({double floor = 0.9, double margin = 0.5}) async {
  final cached = _searchCache;
  if (cached != null) return cached;
  final inflight = _searchLoading;
  if (inflight != null) return inflight;
  return _searchLoading = _loadHadithSearch(floor: floor, margin: margin);
}

Future<HadithSearch> _loadHadithSearch({required double floor, required double margin}) async {
  final sw = Stopwatch()..start();
  try {
    final vocab = await loadPhonemeUnits();
    final bytes = (await rootBundle.load(hadithAsset)).buffer.asUint8List();
    Log.d('hadith', 'corpus load: gz asset ${bytes.length}B, vocab ${vocab.length} units, '
        'read ${sw.elapsedMilliseconds}ms — building index off-thread…');
    final search = await Isolate.run(
        () => HadithSearch(HadithCorpus.decode(bytes, vocab), floor: floor, margin: margin));
    Log.d('hadith', 'corpus ready: ${search.docCount} docs, ${search.ngramKeys} 3-gram keys, '
        'floor=$floor margin=$margin, build ${sw.elapsedMilliseconds}ms');
    return _searchCache = search;
  } catch (e, st) {
    _searchLoading = null; // let a later caller retry the build
    Log.e('hadith', 'corpus load FAILED after ${sw.elapsedMilliseconds}ms: $e', st);
    rethrow;
  }
}
