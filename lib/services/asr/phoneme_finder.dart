import 'dart:math' show log;
import 'phoneme_align.dart' show PhonemeLocalizer, nwAlign, kPhonemeThreshold;

/// Domain-agnostic phoneme retrieval — "Shazam" over a corpus of thousands of
/// phoneme documents (hadith, du'ās, any phonemized text). A 3-gram inverted
/// index prefilters to a small candidate set, then the shared [PhonemeLocalizer]
/// (Smith-Waterman local align) reranks. Pure Dart: no mic, stream, or platform.

final RegExp _collapseRe = RegExp(r'(.)\1+');
String _collapse(String s) => s.replaceAllMapped(_collapseRe, (m) => m[1]!);

/// FNV-1a over the phoneme units (with a unit separator so `['ab','c']` and
/// `['a','bc']` differ). Identical sequences hash identically; the ~1/2^64
/// cross-matn collision chance over ~12k docs is negligible. Dart VM/AOT ints are
/// 64-bit and wrap on overflow, which is exactly the FNV mixing we want.
String _dupHash(List<String> phonemes) {
  var h = 0xcbf29ce484222325;
  for (final p in phonemes) {
    for (var i = 0; i < p.length; i++) {
      h = (h ^ p.codeUnitAt(i)) * 0x100000001b3;
    }
    h = (h ^ 0x20) * 0x100000001b3;
  }
  return h.toRadixString(16);
}

/// One corpus document. Phonemes are madd-collapsed at construction so the index
/// and the query normalize identically. Display metadata (title, ref, text) is
/// held by the caller keyed on [id] — the finder is retrieval only.
///
/// [words] + [phonemeToWord] are the OPTIONAL word map: `phonemeToWord[i]` is the
/// [words] index the i-th phoneme belongs to. `_collapse` rewrites each token but
/// never adds or drops one, so the collapsed [phonemes] stay 1:1 with the input
/// and therefore with [phonemeToWord] — which is what lets [matchedWordIndices]
/// map a matched ref phoneme back to its word. Empty on find-only corpora (no
/// map) — those simply get no voice-row highlight.
class FindDoc {
  final String id;
  final List<String> phonemes;
  final List<String> words;
  final List<int> phonemeToWord;
  FindDoc(this.id, List<String> phonemes, {this.words = const [], this.phonemeToWord = const []})
      : phonemes = phonemes.map(_collapse).toList();
}

class FindResult {
  final String id;
  final double score; // per-query-token localizer score
  const FindResult(this.id, this.score);
}

const int _ngram = 3;
const String _sep = ' ';

/// Phonemes of slack on each side of the localized match when windowing the
/// highlight align — enough to cover word-boundary phonemes the localizer's start
/// estimate may clip, small enough that the window stays O(query length).
const int _alignSlack = 12;

class PhonemeFinder {
  final List<FindDoc> docs;
  final Map<String, List<int>> _index = {};
  final Map<String, double> _idf = {}; // log(N/docFreq) per 3-gram
  final Map<String, String> _dupKey = {}; // id -> hash of its collapsed phonemes
  final Map<String, int> _docIndex = {}; // id -> position in [docs]
  final List<PhonemeLocalizer?> _localizers;

  PhonemeFinder(this.docs) : _localizers = List.filled(docs.length, null) {
    for (var d = 0; d < docs.length; d++) {
      final ph = docs[d].phonemes;
      _dupKey[docs[d].id] = _dupHash(ph);
      _docIndex[docs[d].id] = d;
      final seen = <String>{};
      for (var i = 0; i + _ngram <= ph.length; i++) {
        seen.add('${ph[i]}$_sep${ph[i + 1]}$_sep${ph[i + 2]}');
      }
      for (final g in seen) {
        (_index[g] ??= []).add(d);
      }
    }
    final n = docs.length;
    _index.forEach((g, list) => _idf[g] = log(n / list.length));
  }

  int get ngramKeys => _index.length;

  /// Duplicate key for [id]: an exact hash of its (already madd-collapsed) phoneme
  /// sequence, so two docs storing the SAME matn share a key. Used by
  /// [decideFindBest] to collapse near-identical corpus copies (e.g. the same
  /// Firdaws hadith filed under two Bukhari numbers) before the margin test, so a
  /// doc is never its own runner-up. Unknown ids fall back to the id itself (a
  /// unique key — never collapsed). Exact-hash only: it catches identical matns,
  /// NOT near-variants (isnād-only differences); those collapse fully after the
  /// planned fawazahmed0 matn-only corpus swap. O(N) at construction.
  String dupKeyOf(String id) => _dupKey[id] ?? id;

  /// The candidate's display words (its word map), or empty when the corpus ships
  /// no map (find-only) — the caller maps [matchedWordIndices] through this.
  List<String> wordsOf(String id) {
    final d = _docIndex[id];
    return d == null ? const [] : docs[d].words;
  }

  /// The reference WORD indices of doc [id] that the recited [queryPhonemes]
  /// actually matched — for highlighting a shown voice candidate the SAME way the
  /// typed search highlights its BM25 hits. First LOCALIZES the query within the
  /// candidate (reusing the cached [PhonemeLocalizer]) to find the approximate ref
  /// start, then aligns the (collapsed) query with [nwAlign] over a small WINDOW
  /// around it (± [_alignSlack]) rather than the whole matn — a long hadith is up
  /// to ~7.7k phonemes, and a full DP matrix per shown candidate per mic probe is
  /// wasteful. The window covers the true match region (the localizer's own
  /// scoring found it), so the mapped word set is identical to a full align for the
  /// real match; only the cost drops (r ≈ query.length + 2·slack, not the matn
  /// length). Each matched ref phoneme maps through `phonemeToWord`. A wrong
  /// candidate localizes weakly and lights up few or no words. Empty on a doc with
  /// no word map, a too-short query, or when the localizer finds nothing (no
  /// highlight, never a crash).
  Set<int> matchedWordIndices(String id, List<String> queryPhonemes) {
    final d = _docIndex[id];
    if (d == null) return const {};
    final doc = docs[d];
    if (doc.phonemeToWord.isEmpty || doc.phonemes.isEmpty) return const {};
    final q = queryPhonemes.map(_collapse).toList();
    if (q.length < _ngram) return const {};
    final loc = _localizers[d] ??= PhonemeLocalizer(doc.phonemes, (_) => 0);
    final refPos = loc.localizeScored(q).refPos;
    if (refPos < 0) return const {};
    final n = doc.phonemes.length;
    final refLo = refPos - _alignSlack < 0 ? 0 : refPos - _alignSlack;
    final hi = refPos + q.length + _alignSlack;
    final refHi = hi > n ? n : hi;
    final window = doc.phonemes.sublist(refLo, refHi);
    final words = <int>{};
    for (final pair in nwAlign(q, window, 0, kPhonemeThreshold)) {
      final refIdx = refLo + pair[1];
      if (refIdx >= 0 && refIdx < doc.phonemeToWord.length) words.add(doc.phonemeToWord[refIdx]);
    }
    return words;
  }

  /// IDF-weighted 3-gram prefilter: candidates are scored by the summed inverse
  /// document frequency of their SHARED grams, not a raw shared-gram count. Isnād
  /// boilerplate (a gram in thousands of docs) has idf≈0 and contributes nothing,
  /// so the distinctive matn grams a reciter actually says decide the top-K —
  /// otherwise the true matn hadith drowns under isnād-sharing neighbours (see
  /// phoneme_finder_scale_test's isnād-robustness case). The true doc still holds
  /// the max weight (it contains every query gram), so recall@K is unchanged.
  List<FindResult> search(List<String> queryPhonemes, {int k = 50, int top = 5}) {
    final q = queryPhonemes.map(_collapse).toList();
    if (q.length < _ngram) return const [];

    final tally = <int, double>{};
    for (var i = 0; i + _ngram <= q.length; i++) {
      final g = '${q[i]}$_sep${q[i + 1]}$_sep${q[i + 2]}';
      final docsForGram = _index[g];
      if (docsForGram == null) continue;
      final w = _idf[g]!;
      for (final d in docsForGram) {
        tally[d] = (tally[d] ?? 0) + w;
      }
    }
    if (tally.isEmpty) return const [];

    final cands = tally.keys.toList()
      ..sort((a, b) {
        final c = tally[b]!.compareTo(tally[a]!);
        return c != 0 ? c : docs[a].id.compareTo(docs[b].id);
      });
    final kk = cands.length < k ? cands.length : k;
    final results = <FindResult>[];
    for (var ci = 0; ci < kk; ci++) {
      final d = cands[ci];
      final loc = _localizers[d] ??= PhonemeLocalizer(docs[d].phonemes, (_) => 0);
      results.add(FindResult(docs[d].id, loc.localizeScored(q).score / q.length));
    }
    results.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return results.length <= top ? results : results.sublist(0, top);
  }
}

/// Outcome of a find: a confident winner id, or null when the top candidates are
/// too close / too weak to name one (caller shows the ranked list instead).
class FindDecision {
  final String? pick;
  final bool confident;
  const FindDecision(this.pick, this.confident);
}

/// PURE find decision (host-testable). Mirrors [identifyDua]'s qualify test minus
/// the cross-probe streak (a search is one shot, not a debounced stream): the top
/// of ranked [results] is a confident winner only when it clears the absolute
/// [floor] AND beats the runner-up by [margin]. A lone result qualifies on floor.
FindDecision decideFind(List<FindResult> results, {required double floor, required double margin}) {
  if (results.isEmpty) return const FindDecision(null, false);
  final best = results.first.score;
  final confident =
      best >= floor && (results.length < 2 || best >= results[1].score + margin);
  return FindDecision(confident ? results.first.id : null, confident);
}

/// Fold one probe's candidate [scores] (id -> per-token score) into the running
/// session-best map [best], keeping the MAX each id has ever reached. Guarded by
/// the length gate: below [minQueryLen] a query is too short for the localizer to
/// mean anything (a 5-phoneme span can chance-match a doc at 2.4), so those probes
/// must NOT poison the peak map — only spans long enough to pick from accumulate.
void foldBestScores(
  Map<String, double> best,
  Iterable<MapEntry<String, double>> scores, {
  required int queryLen,
  required int minQueryLen,
}) {
  if (queryLen < minQueryLen) return;
  for (final e in scores) {
    final prev = best[e.key];
    if (prev == null || e.value > prev) best[e.key] = e.value;
  }
}

/// The confident find over the BEST-EVER peak scores (biggest lever — this is what
/// survives the rolling window decaying past the distinctive matn into the isnād
/// tail). Ranks candidate ids by their session-best score, COLLAPSES near-identical
/// docs (same [dupKeyOf]) keeping the max so a duplicate matn is never counted as
/// its own runner-up, then applies the same floor + margin-over-runner-up gate as
/// [decideFind] — but the runner-up is now the best DISTINCT hadith. A lone
/// distinct candidate qualifies on floor alone.
FindDecision decideFindBest(
  Map<String, double> bestScore, {
  required String Function(String id) dupKeyOf,
  required double floor,
  required double margin,
}) {
  if (bestScore.isEmpty) return const FindDecision(null, false);
  final ranked = bestScore.keys.toList()
    ..sort((a, b) {
      final c = bestScore[b]!.compareTo(bestScore[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  final seenKeys = <String>{};
  final distinct = <String>[];
  for (final id in ranked) {
    if (seenKeys.add(dupKeyOf(id))) distinct.add(id);
  }
  final best = bestScore[distinct.first]!;
  final confident = best >= floor &&
      (distinct.length < 2 || best >= bestScore[distinct[1]]! + margin);
  return FindDecision(confident ? distinct.first : null, confident);
}
