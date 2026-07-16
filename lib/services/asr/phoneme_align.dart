import 'dart:typed_data';
import 'arabic_match.dart' show similarity;

/// Phoneme-matching primitives ported verbatim from the working RN build
/// (src/lib/matcher/phonemeAlign.ts, phonemeTokenizer.ts, phonemeLocalize.ts).

const double kPhonemeThreshold = 0.75;

/// Greedy longest-match tokenizer over the model's Arabic-script phoneme units
/// (209 of 251 are multi-char tajweed clusters, so a shorter unit is a prefix of
/// a longer one — split by longest match, not by character).
List<String> Function(String) createPhonemeTokenizer(List<String> units) {
  final vocab = units.toSet();
  var maxLen = 0;
  for (final u in units) {
    if (u.length > maxLen) maxLen = u.length;
  }
  return (String text) {
    final tokens = <String>[];
    var i = 0;
    while (i < text.length) {
      if (RegExp(r'\s').hasMatch(text[i])) {
        i += 1;
        continue;
      }
      var matched = '';
      final hi = maxLen < text.length - i ? maxLen : text.length - i;
      for (var len = hi; len >= 1; len--) {
        final cand = text.substring(i, i + len);
        if (vocab.contains(cand)) {
          matched = cand;
          break;
        }
      }
      if (matched.isNotEmpty) {
        tokens.add(matched);
        i += matched.length;
      } else {
        i += 1;
      }
    }
    return tokens;
  };
}

const _nwMatch = 10;
const _nwMismatch = -1000;
const _nwGap = -1;

/// Needleman-Wunsch: matched (tokenIndex, refIndex) pairs of the spoken chunk
/// against reference phonemes from [start] on. Sub-threshold pairs never chosen.
List<List<int>> nwAlign(List<String> tokens, List<String> refNorms, int start, double threshold) {
  final t = tokens.length;
  final window = refNorms.sublist(start);
  final r = window.length;
  bool isMatch(String a, String b) => similarity(b, a) >= threshold;

  final dp = List.generate(t + 1, (_) => List<int>.filled(r + 1, 0));
  final back = List.generate(t + 1, (_) => List<int>.filled(r + 1, 0));
  for (var i = 0; i <= t; i++) {
    dp[i][0] = i * _nwGap;
  }
  for (var j = 0; j <= r; j++) {
    dp[0][j] = j * _nwGap;
  }
  for (var i = 1; i <= t; i++) {
    for (var j = 1; j <= r; j++) {
      final s = isMatch(tokens[i - 1], window[j - 1]) ? _nwMatch : _nwMismatch;
      final diag = dp[i - 1][j - 1] + s;
      final up = dp[i - 1][j] + _nwGap;
      final left = dp[i][j - 1] + _nwGap;
      var best = diag;
      var dir = 0;
      if (up > best) {
        best = up;
        dir = 1;
      }
      if (left > best) {
        best = left;
        dir = 2;
      }
      dp[i][j] = best;
      back[i][j] = dir;
    }
  }
  var bj = 0;
  for (var j = 1; j <= r; j++) {
    if (dp[t][j] >= dp[t][bj]) bj = j;
  }
  final pairs = <List<int>>[];
  var i = t, j = bj;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && back[i][j] == 0) {
      if (isMatch(tokens[i - 1], window[j - 1])) pairs.add([i - 1, start + (j - 1)]);
      i--;
      j--;
    } else if (i > 0 && (j == 0 || back[i][j] == 1)) {
      i--;
    } else {
      j--;
    }
  }
  return pairs.reversed.toList();
}

/// Localizer result: reference word index (-1 none), raw ref position, score.
class LocResult {
  final int word;
  final int refPos;
  final double score;
  const LocResult(this.word, this.refPos, this.score);
}

const _locMatch = 3;
const _locMismatch = -3;
const _locGap = -3;

/// Smith-Waterman "Method C" localizer — given a snippet of recent phoneme
/// tokens, returns the reference word it belongs to, robust to heavy repetition.
class PhonemeLocalizer {
  final List<String> ref;
  final int Function(int) refWordOf;
  final double threshold;
  final Map<String, Uint8List> _maskCache = {};

  PhonemeLocalizer(this.ref, this.refWordOf, {this.threshold = kPhonemeThreshold});

  Uint8List _maskFor(String tok) {
    final cached = _maskCache[tok];
    if (cached != null) return cached;
    final n = ref.length;
    final mk = Uint8List(n);
    final per = <String, int>{};
    for (var j = 0; j < n; j++) {
      var v = per[ref[j]];
      if (v == null) {
        v = similarity(tok, ref[j]) >= threshold ? 1 : 0;
        per[ref[j]] = v;
      }
      mk[j] = v;
    }
    _maskCache[tok] = mk;
    return mk;
  }

  LocResult localizeScored(List<String> snippet) {
    final m = snippet.length;
    final n = ref.length;
    if (m == 0 || n == 0) return const LocResult(-1, -1, 0);
    var prev = Float64List(n + 1);
    var prevStart = Int32List(n + 1);
    var cur = Float64List(n + 1);
    var curStart = Int32List(n + 1);
    var best = 0.0;
    var bestStartRef = -1;
    for (var i = 1; i <= m; i++) {
      final mk = _maskFor(snippet[i - 1]);
      cur[0] = 0;
      curStart[0] = 0;
      for (var j = 1; j <= n; j++) {
        final s = mk[j - 1] != 0 ? _locMatch : _locMismatch;
        final dv = prev[j - 1] + s;
        final dStart = prev[j - 1] > 0 ? prevStart[j - 1] : j - 1;
        final uv = prev[j] + _locGap;
        final uStart = prevStart[j];
        final lv = cur[j - 1] + _locGap;
        final lStart = curStart[j - 1];
        var v = 0.0;
        var st = j;
        if (dv > v) {
          v = dv;
          st = dStart;
        }
        if (uv > v) {
          v = uv;
          st = uStart;
        }
        if (lv > v) {
          v = lv;
          st = lStart;
        }
        cur[j] = v;
        curStart[j] = st;
        if (v > best) {
          best = v;
          bestStartRef = st;
        }
      }
      final t = prev;
      prev = cur;
      cur = t;
      final ts = prevStart;
      prevStart = curStart;
      curStart = ts;
    }
    if (best <= 0) return const LocResult(-1, -1, 0);
    return LocResult(refWordOf(bestStartRef), bestStartRef, best);
  }
}
