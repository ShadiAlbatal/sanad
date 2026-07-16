import 'dart:math' as math;
import 'arabic_match.dart' show similarity;
import 'phoneme_align.dart' show createPhonemeTokenizer;
import 'phoneme_matcher.dart' show PhonemeClip;

/// POST-RECITATION tajwīd review, ported from the RN build
/// (src/lib/matcher/tajweedReview.ts). Runs ONCE at Stop over the FINALIZED
/// phoneme transcript (never the live word-states — position ≠ verdict). A
/// makhraj slip is flagged ONLY where the model is trustworthy, so it is silent
/// rather than crying wolf on the letters it can't hear.
///
/// The recipe (validated off-device against real audio: 0 false alarms on
/// correct al-Kursī, real catches ط→ت / ظ→ز on wrong audio — NOTE: ط and ظ's
/// entries in the reliability table rest on only 6 and 2 observations
/// respectively; loadPhonemeReliability() now floors any letter below
/// [_minReliabilitySamples] observations to reliability-unknown regardless of
/// its raw ok/seen ratio (a lucky small sample was reading as "100% reliable"
/// and could flag a CORRECT reciter — see phoneme_corpus.dart), so ط/ظ's own
/// catches are currently SILENCED too until more eval audio raises their
/// sample size — the honest cost of that fix, not a contradiction of it):
///   1. align the model's phonemes to the reference (edit distance);
///   2. consider SUBSTITUTIONS only — never deletions (routine model noise) or
///      insertions (openings/breaths);
///   3. compare at MAKHRAJ level: strip harakāt/madd-length and fold the madd
///      glides ۦ→ي, ۥ→و (same makhraj, not an error). Same makhraj → not a slip;
///   4. flag only if the reference letter's measured reliability ≥ THRESHOLD —
///      the model garbles ص ض ق غ ك even on correct audio, so those stay silent;
///   5. mask the two false-alarm sources that survive on correct audio:
///      - junction smear: the aligner smears subs across a ghunna/idghām region,
///        which is exactly a whitespace-MERGED display unit (سِنَةٌۭ وَلَا is one
///        unit *because* of the assimilation) — a letter-by-letter compare is
///        invalid there;
///      - madd bleed: a long madd bleeding into the next letter, heard as a glide.
class TajweedFlag {
  final int wordIndex;
  final String ref; // reference makhraj (bare consonant)
  final String heard; // what the model emitted
  final double reliability; // model's per-letter reliability
  // Audio span of the flagged word in the recording (seconds), present only when
  // per-token timestamps were supplied — drives tap-to-hear-your-word playback.
  final double? startSec;
  final double? endSec;
  const TajweedFlag(this.wordIndex, this.ref, this.heard, this.reliability,
      {this.startSec, this.endSec});
}

const double _threshold = 0.95;
const Set<String> _madd = {'ا', 'و', 'ي'};
final RegExp _mn = RegExp(r'\p{Mn}', unicode: true);

String _collapse(String s) => s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
String _skeleton(String tok) => _collapse(tok.replaceAll(_mn, ''));
// Glyph normalization to the base letter: fold the madd glides ۦ→ي, ۥ→و, and the
// noon-ghunna glyph ں→ن. The corpus writes an assimilating/hidden noon as ں
// (ARABIC NOON GHUNNA) — but that is the SAME letter and makhraj as ن; ghunna is
// a nasalization ṣifa, not a makhraj change. The model hears a plain noon (ن)
// there, so without this fold a correct noon flags as ں→ن (real device FP at
// 2:104:8 ٱنظُرْنَا).
String _makhraj(String tok) =>
    _skeleton(tok).replaceAll('ۦ', 'ي').replaceAll('ۥ', 'و').replaceAll('ں', 'ن');

// Consonant pairs THIS phoneme model interchanges on CORRECT audio, verified
// against a real Al-Baqara device run (run_20260715_154405, min1497/max1563):
//   ب↔م — both bilabial (shafatān), differ only in nasality; the model swaps
//         them even when the reciter is right (FP at 2:105:19 بِرَحْمَتِهِۦ).
//   ش↔ف — two voiceless fricatives the model interchanges (FP at 2:102:60
//         ٱشْتَرَىٰهُ). Their makhārij differ, so this is NOT a makhraj fold: it is a
//         model-blindness mask. The reliability table rates ش/ب ≈1.0, but ش is an
//         outlier — every other fricative (ف ح خ ص س ه …) already sits <0.95 — so
//         the per-letter gate can't catch these. The table is confusion-blind and
//         really wants regeneration from a confusion matrix; this is the interim
//         guard. Kept deliberately narrow: it excludes ت/د/ط, which the model
//         distinguishes reliably and whose ط→ت slip is the review's flagship catch.
const Set<String> _modelConfusable = {'بم', 'مب', 'شف', 'فش'};
bool _confusable(String a, String b) => _modelConfusable.contains('$a$b');

// same() collapses first, then accepts ≥ 0.75 similarity — identical semantics
// to arabic_match.similarity (checked: standard Levenshtein, maxLen==0 → 1), so
// the existing helper is reused rather than duplicating the edit distance.
bool _same(String a, String b) => similarity(_collapse(a), _collapse(b)) >= 0.75;

class _AlignCol {
  final int? ref;
  final String? tok;
  final int? tokIdx; // index into the token stream (for timestamp lookup)
  final bool match;
  const _AlignCol(this.ref, this.tok, this.tokIdx, this.match);
}

// Substitution cost is 1.5, not 1 (deletion/insertion stay at 1). Plain
// Levenshtein lets "explain a spurious duplicate token as an insertion, then
// match the real token" TIE with "explain it as a substitution on the real
// token" — both cost 2 — and the tie is resolved by traceback order, which can
// discard a free match and turn a correctly-said letter (at a shadda gemination
// point) into a false substitution flag. 1.5 keeps a genuine substitution
// cheaper than being split into two gaps (2) while breaking that tie.
const double _subCost = 1.5;

// Column reconstruction the matcher's nwAlign doesn't give: each column is a ref
// paired with a token (substitution/match), a ref with no token (deletion), or a
// token with no ref (insertion). The review needs the substitution columns.
List<_AlignCol> _align(List<String> tokens, List<String> ref) {
  final t = tokens.length, r = ref.length;
  final dp = List.generate(t + 1, (_) => List<double>.filled(r + 1, 0));
  for (var i = 0; i <= t; i++) {
    dp[i][0] = i.toDouble();
  }
  for (var j = 0; j <= r; j++) {
    dp[0][j] = j.toDouble();
  }
  for (var i = 1; i <= t; i++) {
    for (var j = 1; j <= r; j++) {
      final sub = dp[i - 1][j - 1] + (_same(tokens[i - 1], ref[j - 1]) ? 0 : _subCost);
      var best = sub;
      final del = dp[i - 1][j] + 1;
      if (del < best) best = del;
      final ins = dp[i][j - 1] + 1;
      if (ins < best) best = ins;
      dp[i][j] = best;
    }
  }
  final cols = <_AlignCol>[];
  var i = t, j = r;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] + (_same(tokens[i - 1], ref[j - 1]) ? 0 : _subCost)) {
      cols.add(_AlignCol(j - 1, tokens[i - 1], i - 1, _same(tokens[i - 1], ref[j - 1])));
      i--;
      j--;
    } else if (j > 0 && dp[i][j] == dp[i][j - 1] + 1) {
      cols.add(_AlignCol(j - 1, null, null, false));
      j--;
    } else {
      cols.add(_AlignCol(null, tokens[i - 1], i - 1, false));
      i--;
    }
  }
  return cols.reversed.toList();
}

// Time span (seconds) of the word AT THE FLAG'S OWN ATTEMPT. NOT min..max over
// all tokens aligned to the word — a re-read session (wrong → go back →
// corrected) aligns the same reference word to tokens from TWO attempts, so
// min..max would stretch across both. Instead take only the CONTIGUOUS token
// cluster (gap ≤ 3 tokens) containing the flag's own substitution token, so
// tap-to-hear plays exactly the attempt the flag was judged on. _contextPadSec
// gives breathing room — a bare 0.3s letter-clip is unintelligible.
const double _contextPadSec = 0.25;
(double, double)? _wordSpan(
  List<_AlignCol> cols,
  PhonemeClip clip,
  int wordIndex,
  int anchorTok,
  List<double> timestamps,
) {
  final toks = <int>[];
  for (final col in cols) {
    if (col.ref != null && col.tokIdx != null && clip.phonemeToWord[col.ref!] == wordIndex) {
      toks.add(col.tokIdx!);
    }
  }
  if (toks.isEmpty) return null;
  toks.sort();
  var lo = anchorTok, hi = anchorTok;
  var best = 1 << 30;
  for (final t in toks) {
    final d = (t - anchorTok).abs();
    if (d < best) {
      best = d;
      lo = hi = t;
    }
  }
  // Chain the low edge DOWN (descending) and the high edge UP (ascending) so a
  // fully contiguous cluster (each hop ≤ 3) extends all the way to both ends —
  // an ascending low-loop would only hop once below the anchor and front-truncate
  // the clip on a late-word flag.
  for (var k = toks.length - 1; k >= 0; k--) {
    final t = toks[k];
    if (t < lo && lo - t <= 3) lo = t;
  }
  for (final t in toks) {
    if (t > hi && t - hi <= 3) hi = t;
  }
  if (lo >= timestamps.length) return null;
  final startSec = math.max(0.0, timestamps[lo] - _contextPadSec);
  final rawEnd = hi + 1 < timestamps.length
      ? timestamps[hi + 1]
      : timestamps[math.min(hi, timestamps.length - 1)] + 0.4;
  return (startSec, rawEnd + _contextPadSec);
}

// First/last phoneme index belonging to a word (phonemeToWord is contiguous per
// word, so a single scan finds both ends).
List<int> _wordPhonemeBounds(PhonemeClip clip, int wordIndex) {
  var lo = -1, hi = -1;
  for (var i = 0; i < clip.phonemeToWord.length; i++) {
    if (clip.phonemeToWord[i] == wordIndex) {
      if (lo < 0) lo = i;
      hi = i;
    }
  }
  return [lo, hi];
}

/// [words]: the reference word STRING per corpus word (`SurahClip.words`); a
/// whitespace-merged (junction) unit contains a space, which the junction mask
/// reads. [reliability]: letter → measured per-letter reliability.
/// [maxWordIndex]/[minWordIndex] bound the ALIGNMENT ITSELF (not just filter
/// flags after): a partial/mid-start recitation otherwise leaves un-recited
/// reference phonemes in the alignment, and that noise corrupts the path for
/// genuinely-correct later content too.
List<TajweedFlag> reviewTajweed(
  PhonemeClip clip,
  List<String> words,
  String transcript,
  List<String> units,
  Map<String, double> reliability, {
  List<double>? timestamps,
  int? maxWordIndex,
  int? minWordIndex,
}) {
  final tokens = createPhonemeTokenizer(units)(transcript);
  final ref = clip.phonemes;
  final refLo = minWordIndex != null ? _wordPhonemeBounds(clip, minWordIndex)[0] : 0;
  final refHi = maxWordIndex != null ? _wordPhonemeBounds(clip, maxWordIndex)[1] : ref.length - 1;
  final rawCols = _align(tokens, ref.sublist(refLo, refHi + 1));
  // Normalize back to full-clip ref indices so every downstream lookup is unchanged.
  final cols = [
    for (final c in rawCols) c.ref == null ? c : _AlignCol(c.ref! + refLo, c.tok, c.tokIdx, c.match)
  ];
  final withSpans = timestamps != null && timestamps.isNotEmpty;
  double rel(String letter) => reliability[letter] ?? 0;

  final flags = <TajweedFlag>[];
  for (final col in cols) {
    if (col.ref == null || col.match || col.tok == null) continue; // insertion / match / deletion
    final wordIndex = clip.phonemeToWord[col.ref!];
    // makhraj folds ۦ→ي, ۥ→و for the same-makhraj test only; reliability + label
    // use the unfolded skeleton, so a reference position that IS a madd glide
    // (ۦ/ۥ) is gated on its own (below-threshold) reliability, not the base letter's.
    final refId = _skeleton(ref[col.ref!]);
    final heardId = _skeleton(col.tok!);
    final refMk = _makhraj(ref[col.ref!]);
    final heardMk = _makhraj(col.tok!);
    if (refMk == heardMk) continue; // same makhraj (vowel/madd/noon-ghunna only)
    if (_confusable(refId, heardId)) continue; // model interchanges this pair — see note
    if (rel(refId) < _threshold) continue; // blind letter — stay silent
    if (RegExp(r'\s').hasMatch(words[wordIndex])) continue; // junction smear
    final prevMk = col.ref! > 0 ? _makhraj(ref[col.ref! - 1]) : '';
    if (_madd.contains(heardMk) && _madd.contains(prevMk)) continue; // madd bleed
    final span = withSpans && col.tokIdx != null
        ? _wordSpan(cols, clip, wordIndex, col.tokIdx!, timestamps)
        : null;
    flags.add(TajweedFlag(wordIndex, refId, heardId, rel(refId),
        startSec: span?.$1, endSec: span?.$2));
  }
  return flags;
}
