import 'dart:isolate';
import 'package:flutter/services.dart' show rootBundle;
import 'dua_corpus.dart';
import 'phoneme_corpus.dart' show loadPhonemeUnits;
import 'phoneme_finder.dart';
import '../search/text_search.dart' show matchedDisplayWords;
import '../../util/log.dart';

/// A ranked du'a candidate: display metadata + the finder's per-token score.
/// `pick != null` on a [DuaSearchResult] means this one cleared the confidence
/// bar. [id] is the corpus id (existing `dua-*` or `hisn-N`) — the reader key.
class DuaCandidate {
  final DuaMeta meta;
  final double score;
  const DuaCandidate(this.meta, this.score);

  String get id => meta.id;
}

/// Never a dead end: [pick] is the confident single winner (or null), and
/// [candidates] is ALWAYS the ranked top-K to show.
class DuaSearchResult {
  final DuaCandidate? pick;
  final List<DuaCandidate> candidates;
  const DuaSearchResult(this.pick, this.candidates);
  bool get confident => pick != null;
}

/// Pure retrieval over the whole du'a corpus (existing 5 + Hisn al-Muslim) — no
/// mic, no ASR engine, no UI state. The scale replacement for the old O(N)
/// one-localizer-per-du'a loop: a shared [PhonemeFinder] (IDF 3-gram prefilter →
/// localizer rerank) so identifying among ~260 du'as costs the same as among 5.
/// Sibling of [HadithSearch]; in the finder state the gate runs over BEST-EVER
/// peak scores with duplicate docs collapsed (see [decideFindBest]);
/// [DuaSearch.find] itself still uses the per-probe [decideFind] for host tests.
///
/// [floor]/[margin] mirror the recalibrated hadith gates (0.9/0.5) — margin is the
/// primary separator, floor a low sanity floor. The hadith values were tuned on
/// device logs; there is no equivalent du'a device capture yet, so these are
/// provisional-by-analogy (the finders share one engine, so the score regime is
/// the same) — DEVICE-PENDING like every ASR threshold here.
class DuaSearch {
  final PhonemeFinder _finder;
  final List<DuaMeta> allDuas; // corpus order — the browsable list
  final Map<String, DuaMeta> _meta;
  final double floor;
  final double margin;

  DuaSearch(DuaCorpus corpus, {this.floor = 0.9, this.margin = 0.5})
      : _finder = PhonemeFinder(corpus.docs),
        allDuas = corpus.metas,
        _meta = corpus.byId;

  int get docCount => _meta.length;
  int get ngramKeys => _finder.ngramKeys;

  DuaMeta? metaById(String id) => _meta[id];

  /// Duplicate key for a du'a id — see [PhonemeFinder.dupKeyOf].
  String dupKeyOf(String id) => _finder.dupKeyOf(id);

  /// The normalized display words of candidate [id] that the recited
  /// [queryPhonemes] matched — same `Set<String>` contract as the typed path, so a
  /// VOICE candidate row highlights identically. Empty when the corpus carries no
  /// word map or the query is too short.
  Set<String> matchedWords(String id, List<String> queryPhonemes) =>
      matchedDisplayWords(_finder, id, queryPhonemes);

  static Future<DuaSearch> load({double floor = 0.9, double margin = 0.5}) async =>
      DuaSearch(await loadDuaCorpus(), floor: floor, margin: margin);

  DuaSearchResult find(List<String> queryPhonemes, {int top = 5}) {
    final results = _finder.search(queryPhonemes, top: top);
    final candidates = [for (final r in results) DuaCandidate(_meta[r.id]!, r.score)];
    final decision = decideFind(results, floor: floor, margin: margin);
    final pick =
        decision.pick == null ? null : candidates.firstWhere((c) => c.id == decision.pick);
    return DuaSearchResult(pick, candidates);
  }
}

DuaSearch? _searchCache;
Future<DuaSearch>? _searchLoading;

/// Lazily build (once, cached) the du'a live-search index off the UI thread —
/// mirrors loadHadithSearch. The asset read + vocab load use platform channels
/// (main isolate only); the decode + 3-gram index build run in an `Isolate.run`
/// so opening the Azkar tab never janks a frame. Concurrent callers (screen
/// initState + finder preload on first open) share ONE in-flight build via
/// [_searchLoading] — without it both would run the corpus decode + index build.
Future<DuaSearch> loadDuaSearch({double floor = 0.9, double margin = 0.5}) async {
  final cached = _searchCache;
  if (cached != null) return cached;
  final inflight = _searchLoading;
  if (inflight != null) return inflight;
  return _searchLoading = _loadDuaSearch(floor: floor, margin: margin);
}

Future<DuaSearch> _loadDuaSearch({required double floor, required double margin}) async {
  final sw = Stopwatch()..start();
  try {
    final vocab = await loadPhonemeUnits();
    final bytes = (await rootBundle.load(duaAsset)).buffer.asUint8List();
    final search = await Isolate.run(
        () => DuaSearch(DuaCorpus.decode(bytes, vocab), floor: floor, margin: margin));
    Log.d('duafind', 'corpus ready: ${search.docCount} duas, ${search.ngramKeys} 3-gram keys, '
        'floor=$floor margin=$margin, build ${sw.elapsedMilliseconds}ms');
    return _searchCache = search;
  } catch (e, st) {
    _searchLoading = null; // let a later caller retry the build
    Log.e('duafind', 'corpus load FAILED after ${sw.elapsedMilliseconds}ms: $e', st);
    rethrow;
  }
}
