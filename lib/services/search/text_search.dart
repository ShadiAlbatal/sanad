import 'dart:math' show log;
import '../asr/arabic_match.dart' show tokenizeArabic;
import '../asr/phoneme_finder.dart' show PhonemeFinder;

/// Normalized search words for a piece of display text — the SAME normalization
/// used for the corpus and the query so a correctly-typed word matches despite
/// diacritic/alef/hamza/ta-marbuta drift (see [tokenizeArabic]).
List<String> searchWords(String text) => tokenizeArabic(text);

/// The normalized display words of finder candidate [id] that the recited
/// [queryPhonemes] matched — maps [PhonemeFinder.matchedWordIndices] through the
/// candidate's word list and normalizes each with [searchWords], yielding the SAME
/// `Set<String>` HighlightedArabic + the typed BM25 path already consume, so a
/// VOICE candidate row highlights identically. Empty when the candidate has no word
/// map or the query is too short (plain text, never a crash). Shared by the
/// Dua/Hadith/Quran voice search wrappers.
Set<String> matchedDisplayWords(PhonemeFinder finder, String id, List<String> queryPhonemes) {
  final idxs = finder.matchedWordIndices(id, queryPhonemes);
  if (idxs.isEmpty) return const {};
  final words = finder.wordsOf(id);
  final out = <String>{};
  for (final i in idxs) {
    if (i >= 0 && i < words.length) out.addAll(searchWords(words[i]));
  }
  return out;
}

/// One indexable document: an [id] the caller keys its metadata on and the
/// display [text] whose words are searched (du'a `arabic`, hadith `text`).
class TextSearchDoc {
  final String id;
  final String text;
  const TextSearchDoc(this.id, this.text);
}

/// A ranked typed-search result: the doc [id], its BM25 [score], the query terms
/// it matched ([matchedWords], normalized) and where they fall in the doc's
/// normalized word list ([matchedWordPositions]) — enough to HIGHLIGHT the hit.
class TextSearchHit {
  final String id;
  final double score;
  final List<int> matchedWordPositions;
  final Set<String> matchedWords;
  const TextSearchHit(this.id, this.score, this.matchedWordPositions, this.matchedWords);
}

/// Corpus-agnostic BM25 (Okapi) over the normalized WORDS of a corpus's display
/// text. Build once off-thread and cache (like the phoneme corpora); [search]
/// ranks the whole query fragment (every term contributes — not reduced to a few
/// keywords, which the benchmark showed loses recall). Pure Dart: no mic, no UI.
class TextSearch {
  static const double _k1 = 1.5;
  static const double _b = 0.75;

  final List<String> _ids = [];
  final List<List<String>> _docWords = []; // normalized words per doc (for highlight positions)
  final List<int> _len = [];
  final Map<String, Map<int, int>> _postings = {}; // term -> {docIndex: termFreq}
  late final double _avgdl;

  TextSearch(List<TextSearchDoc> docs) {
    var total = 0;
    for (var d = 0; d < docs.length; d++) {
      final words = searchWords(docs[d].text);
      _ids.add(docs[d].id);
      _docWords.add(words);
      _len.add(words.length);
      total += words.length;
      final tf = <String, int>{};
      for (final w in words) {
        tf[w] = (tf[w] ?? 0) + 1;
      }
      tf.forEach((term, c) => (_postings[term] ??= {})[d] = c);
    }
    _avgdl = docs.isEmpty ? 1 : total / docs.length;
  }

  int get docCount => _ids.length;

  /// Rank docs against a raw query string. Empty query (or one with no indexed
  /// terms) yields no hits, so the caller falls back to the full browse list.
  ///
  /// Plain BM25 is bag-of-words: it can't tell "A said B said C" from "C said B
  /// said A", so an isnād chain recited in order scores no differently from a
  /// DIFFERENT doc sharing the same handful of narrator names in a different
  /// order — and BM25's length normalization then favors whichever doc is
  /// shorter, not whichever one actually matches. A live recitation IS
  /// sequential, though, so re-rank the top BM25 candidates by how much of the
  /// query they match as an in-order (not necessarily contiguous) run — a doc
  /// that reproduces the query's word order gets boosted well above one that
  /// merely contains the same words scrambled.
  List<TextSearchHit> search(String query, {int top = 100}) {
    final orderedTerms = searchWords(query);
    final terms = orderedTerms.toSet();
    if (terms.isEmpty) return const [];
    final n = _ids.length;
    final scores = <int, double>{};
    final matched = <int, Set<String>>{};
    for (final term in terms) {
      final posting = _postings[term];
      if (posting == null) continue;
      final df = posting.length;
      final idf = log(1 + (n - df + 0.5) / (df + 0.5));
      posting.forEach((d, freq) {
        final dl = _len[d];
        final denom = freq + _k1 * (1 - _b + _b * dl / _avgdl);
        scores[d] = (scores[d] ?? 0) + idf * (freq * (_k1 + 1)) / denom;
        (matched[d] ??= <String>{}).add(term);
      });
    }
    if (scores.isEmpty) return const [];

    final preRanked = scores.keys.toList()
      ..sort((a, b) {
        final c = scores[b]!.compareTo(scores[a]!);
        return c != 0 ? c : _ids[a].compareTo(_ids[b]);
      });
    final kk = preRanked.length < top ? preRanked.length : top;

    // Only the pre-ranked top-K need the sequence check — the true match for a
    // sequential query is always somewhere in here since it shares the same
    // terms, just possibly out-ranked by a shorter, differently-ordered doc.
    final boosted = <int, double>{};
    for (var i = 0; i < kk; i++) {
      final d = preRanked[i];
      final seqFrac = _orderedMatchFraction(orderedTerms, terms, _docWords[d]);
      boosted[d] = scores[d]! * (1 + 2.0 * seqFrac * seqFrac);
    }
    final ranked = boosted.keys.toList()
      ..sort((a, b) {
        final c = boosted[b]!.compareTo(boosted[a]!);
        return c != 0 ? c : _ids[a].compareTo(_ids[b]);
      });

    final hits = <TextSearchHit>[];
    for (final d in ranked) {
      final terms = matched[d]!;
      final words = _docWords[d];
      final positions = <int>[];
      for (var w = 0; w < words.length; w++) {
        if (terms.contains(words[w])) positions.add(w);
      }
      hits.add(TextSearchHit(_ids[d], boosted[d]!, positions, terms));
    }
    return hits;
  }

  /// Longest run of [orderedQueryTerms] found at strictly increasing positions
  /// in [docWords] — a longest common subsequence — as a fraction of the query
  /// length: "does this doc reproduce the query's word order". Repeated query
  /// terms (duplicate narrator names) each consume a distinct doc occurrence.
  ///
  /// Must be a true LCS, not a leftmost-greedy scan. An isnād query repeats
  /// عن/حدثنا, and if such a term's FIRST occurrence in the doc sits late, a
  /// greedy cursor advances past everything after it and reports near-zero
  /// order for the very doc that matches best — on the real hadith corpus that
  /// demoted the correct matn from rank 1 to rank 40.
  ///
  /// O(query × doc terms): doc words absent from [queryTerms] can't extend any
  /// subsequence, so they leave the row unchanged and are skipped.
  double _orderedMatchFraction(
      List<String> orderedQueryTerms, Set<String> queryTerms, List<String> docWords) {
    final q = orderedQueryTerms.length;
    if (q == 0) return 0;
    final row = List<int>.filled(q + 1, 0);
    for (final w in docWords) {
      if (!queryTerms.contains(w)) continue;
      var diag = 0; // previous row at i-1, before this row overwrites it
      for (var i = 1; i <= q; i++) {
        final up = row[i];
        row[i] = orderedQueryTerms[i - 1] == w
            ? diag + 1
            : (up >= row[i - 1] ? up : row[i - 1]);
        diag = up;
      }
    }
    return row[q] / q;
  }
}
