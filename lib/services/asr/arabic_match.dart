// Arabic normalization + fuzzy matching, ported from the working RN build
// (src/lib/matcher/arabic.ts + similarity.ts + match.ts). Used to match what
// sherpa transcribed against the mushaf's words.

final _harakatTatweel = RegExp('[ً-ْٰٓ-ٕـ]');
final _alefVariants = RegExp('[آأإٱ]');
final _nonArabic = RegExp('[^ء-ي]');

/// Strip diacritics/tatweel and fold alef/ya/ta-marbuta/hamza variants so a
/// correctly-recited word matches its reference despite ASR spelling drift.
String normalizeArabic(String input) {
  return input
      .replaceAll(_harakatTatweel, '')
      .replaceAll(_alefVariants, 'ا') // ا
      .replaceAll('ء', '') // ء
      .replaceAll('ى', 'ي') // ى -> ي
      .replaceAll('ة', 'ه') // ة -> ه
      .replaceAll('ؤ', 'و') // ؤ -> و
      .replaceAll('ئ', 'ي') // ئ -> ي
      .trim();
}

/// Normalized whitespace-split tokens with non-Arabic letters stripped.
List<String> tokenizeArabic(String input) {
  return normalizeArabic(input)
      .split(RegExp(r'\s+'))
      .map((t) => t.replaceAll(_nonArabic, ''))
      .where((t) => t.isNotEmpty)
      .toList();
}

int levenshtein(String a, String b) {
  final m = a.length, n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;
  var prev = List<int>.generate(n + 1, (j) => j);
  var cur = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var mn = prev[j] + 1;
      if (cur[j - 1] + 1 < mn) mn = cur[j - 1] + 1;
      if (prev[j - 1] + cost < mn) mn = prev[j - 1] + cost;
      cur[j] = mn;
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[n];
}

double similarity(String a, String b) {
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1;
  return 1 - levenshtein(a, b) / maxLen;
}

// Short reference words (رب, في, ما) are unfairly punished by ratio similarity —
// one ASR-added letter tanks it — so for these we accept a single edit outright.
const _shortWordMaxLen = 3;

/// Does spoken [token] match reference [refNorm] closely enough?
bool isArabicMatch(String refNorm, String token, {double simThreshold = 0.75}) {
  if (similarity(refNorm, token) >= simThreshold) return true;
  if (refNorm.length <= _shortWordMaxLen && levenshtein(refNorm, token) <= 1) return true;
  return false;
}
