// Pure dhikr phrase matching for the voice counter. The word model transcribes
// a spoken segment to Arabic text; this maps that text to how many of each
// tasbih phrase were said, so "سبحان الله سبحان الله" counts subḥānallāh twice.
// Kept pure (no I/O, no model) so the normalize + count logic is host-testable.

/// Strip tashkīl/tatwīl and fold the orthographic variants an ASR transcript
/// wobbles between (hamza-carrying alifs → bare alif, alif maqṣūra → yāʾ, tāʾ
/// marbūṭa → hāʾ) so matching is spelling-robust.
String normalizeArabic(String s) {
  final sb = StringBuffer();
  for (final r in s.runes) {
    // Harakāt (fatḥa..sukūn), dagger alif, tatwīl, and stray hamza marks — drop.
    if ((r >= 0x064B && r <= 0x0652) ||
        r == 0x0670 ||
        r == 0x0640 ||
        (r >= 0x0653 && r <= 0x0655)) {
      continue;
    }
    var c = r;
    if (c == 0x0623 || c == 0x0625 || c == 0x0622 || c == 0x0671) c = 0x0627; // أإآٱ → ا
    if (c == 0x0649) c = 0x064A; // ى → ي
    if (c == 0x0629) c = 0x0647; // ة → ه
    sb.writeCharCode(c);
  }
  return sb.toString();
}

List<String> normalizedWords(String s) =>
    normalizeArabic(s).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

class _Pattern {
  final String id; // matches a Dhikr.id in adhkar_data.dart
  final List<String> seq; // normalized word sequence
  const _Pattern(this.id, this.seq);
}

// Normalized word sequences for each countable tasbih phrase. Order doesn't
// matter — matching always prefers the LONGEST pattern at each position, so the
// 4-word tahlīl wins over the الله-containing 2-word phrases inside it, and each
// spoken phrase is consumed once (non-overlapping).
const _patterns = <_Pattern>[
  _Pattern('tahlil', ['لا', 'اله', 'الا', 'الله']),
  _Pattern('salawat', ['صلى', 'الله', 'عليه', 'وسلم']),
  _Pattern('salawat', ['اللهم', 'صل']),
  _Pattern('subhanallah', ['سبحان', 'الله']),
  _Pattern('alhamdulillah', ['الحمد', 'لله']),
  _Pattern('alhamdulillah', ['الحمد', 'الله']),
  _Pattern('allahuakbar', ['الله', 'اكبر']),
  _Pattern('istighfar', ['استغفر', 'الله']),
];

bool _matchAt(List<String> words, int i, List<String> seq) {
  if (i + seq.length > words.length) return false;
  for (var k = 0; k < seq.length; k++) {
    var w = words[i + k];
    // A chained phrase carries a conjunction wāw fused onto its first word
    // ("سبحان الله وَالحمد لله" → "والحمد"); accept it so chained tasbīḥ counts.
    if (k == 0 && w.length > seq[k].length && w.startsWith('و') && w.substring(1) == seq[k]) {
      w = seq[k];
    }
    if (w != seq[k]) return false;
  }
  return true;
}

/// Count how many of each dhikr id appear in a transcript, non-overlapping and
/// longest-match-first. Returns id → occurrences (only ids that occurred).
Map<String, int> countDhikr(String transcript) {
  final words = normalizedWords(transcript);
  final counts = <String, int>{};
  var i = 0;
  while (i < words.length) {
    _Pattern? best;
    for (final p in _patterns) {
      if (p.seq.length > (best?.seq.length ?? 0) && _matchAt(words, i, p.seq)) {
        best = p;
      }
    }
    if (best != null) {
      counts[best.id] = (counts[best.id] ?? 0) + 1;
      i += best.seq.length;
    } else {
      i++;
    }
  }
  return counts;
}
