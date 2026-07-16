import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/services/asr/phoneme_corpus.dart';
import 'package:tilawa_ai/services/asr/phoneme_matcher.dart';

/// Two things checked here (pure Dart, no model/device):
///  1. TRACKING (smoke): fed a surah's own reference phonemes, the matcher must
///     light words in order and reach the end. NOTE: this feeds the reference to
///     itself, so it only proves the matcher plumbing runs — NOT real-audio
///     accuracy (that's the on-device eval).
///  2. MAPPING (the real defect the reviewer found): every corpus word must map
///     to at least one well-formed mushaf "s:a:w" location, and the words the
///     matcher greens must resolve to real mushaf glyphs — across surahs that
///     are known-misaligned between corpus and mushaf (2, 112, 114), not just
///     the 7 that happen to line up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final locRe = RegExp(r'^\d+:\d+:\d+$');

  Future<void> checkMapping(int surah) async {
    final sc = await loadSurahClip(surah);
    final unmapped = sc.wordLocations.where((l) => l.isEmpty).length;
    expect(unmapped, 0, reason: 'surah $surah: every corpus word must map to a mushaf glyph');
    for (final locs in sc.wordLocations) {
      for (final l in locs) {
        expect(locRe.hasMatch(l), isTrue, reason: 'bad location "$l" in surah $surah');
        expect(l.startsWith('$surah:'), isTrue, reason: 'location "$l" not in surah $surah');
      }
    }
  }

  Future<void> checkTracking(int surah, {double minGreenFrac = 0.85}) async {
    final units = await loadPhonemeUnits();
    final sc = await loadSurahClip(surah);
    final matcher = PhonemeMatchSession(sc.clip, units);
    final ref = sc.clip.phonemes;
    MatchOutput? out;
    for (var end = 3; end < ref.length; end += 3) {
      out = matcher.apply(ref.sublist(0, end));
    }
    out = matcher.apply(ref);

    final n = sc.clip.wordCount;
    final greens = out!.states.where((s) => s == WordState.correct).length;
    final curLoc = sc.primary(out.cursor);
    // ignore: avoid_print
    print('surah $surah: $greens/$n green, cursor=${out.cursor}, curLoc=$curLoc');
    expect(greens, greaterThanOrEqualTo((n * minGreenFrac).floor()));
    expect(out.cursor, greaterThan(n ~/ 2));
    expect(curLoc, isNotNull);
  }

  // Mapping across known-MISALIGNED surahs (this is what was broken before).
  test('corpus→mushaf mapping is complete for Al-Baqara (2, merges)', () => checkMapping(2));
  test('corpus→mushaf mapping is complete for Al-Ikhlas (112, off-by-one)', () => checkMapping(112));
  test('corpus→mushaf mapping is complete for An-Nas (114, off-by-one)', () => checkMapping(114));
  test('corpus→mushaf mapping is complete for Al-Fatiha (1)', () => checkMapping(1));
  // Surahs whose alignment DROPPED mushaf words before the 2026-07-15 rebuild
  // (build_phoneme_align.py block-DP): 11 has a muqaṭṭaʿāt-plus-text opener (الٓر +
  // كِتَابٌ), 66 has āyah 5 with a long merged attribute list. Every corpus word
  // must still map to an in-surah glyph — no empties, no cross-surah leaks.
  test('corpus→mushaf mapping is complete for Hud (11, muqaṭṭaʿāt+text)', () => checkMapping(11));
  test('corpus→mushaf mapping is complete for At-Tahrim (66, long merges)', () => checkMapping(66));

  // A merged corpus word covers several mushaf glyphs; the "current" highlight
  // must be ALL of them (RN approach — the whole phrase lights together), so the
  // marker never hangs on the first glyph of a merged phrase.
  test('current highlight covers every glyph of a merged corpus word', () async {
    final sc = await loadSurahClip(2);
    final w = sc.wordLocations.indexWhere((l) => l.length >= 3); // a 3+ glyph merge
    expect(w, greaterThanOrEqualTo(0), reason: 'Al-Baqara has multi-glyph merges');
    final set = sc.glyphsOf(w);
    expect(set, equals(sc.wordLocations[w].toSet()), reason: 'highlight = all glyphs of the word');
    expect(set.length, greaterThanOrEqualTo(3));
    expect(sc.glyphsOf(-1), isEmpty);
  });

  // Tracking smoke tests.
  test('matcher tracks a perfect recitation of Al-Fatiha (1)', () => checkTracking(1));
  test('matcher tracks a perfect recitation of Al-Ikhlas (112)', () => checkTracking(112));

  // Ayah-boundary freeze on a REPEATED phrase — ported verbatim from the RN
  // reference (ZikirAi src/lib/matcher/__tests__/ayahBoundaryFreeze.test.ts).
  // This replays a REAL captured token stream (not the corpus fed to itself), so
  // unlike the smoke tests it exercises the localizer/short-tail rescue on real
  // model output. Al-Fatiha: the cursor stuck at word 7 (end of ayah 2) for 20s
  // on-device because ayah 3's opening ("ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ") is a verbatim
  // repeat of ayah 1's ending, so the long tail kept matching the earlier copy.
  // The short-tail recency rescue is what fixes it. If this fails, our localizer
  // port diverges from RN — not just a tuning gap.
  test('does not freeze at an ayah boundary on a repeated phrase (real capture, RN parity)', () async {
    const fullStream =
        'بِ س مِ للَ اا هِ ررَ ح مَ اا نِ هُ ررَ حِ ۦۦ ل حَ م دُ لِ للَ اا هِ غَ ببِ ل عَ اا لَ مِ ۦۦ ن ءَ '
        'ل حَ م دُ لِ للَ اا هِ رَ ببِ ل عَ اا لَ مِ ۦۦ ن ل حَ م دُ لِ للَ اا هِ رَ ببِ ل عَ اا لِ ۦۦ ن ءَ '
        'ررَ ح مَ اا نِ هُ ررَ حِ ۦۦ م ءَ ررَ ح مَ اا نِ ررَ حِ ۦۦ م ررَ ح';
    final toks = fullStream.split(' ');
    final units = await loadPhonemeUnits();
    final sc = await loadSurahClip(1);
    final matcher = PhonemeMatchSession(sc.clip, units);
    var maxCursor = -1;
    for (var i = 1; i <= toks.length; i++) {
      final out = matcher.apply(toks.sublist(0, i));
      if (out.cursor > maxCursor) maxCursor = out.cursor;
    }
    // ignore: avoid_print
    print('ayah-boundary: maxCursor=$maxCursor (must reach word 8 = ayah 3)');
    expect(maxCursor, greaterThanOrEqualTo(8), reason: 'must reach ayah 3, not freeze at word 7');
  });
}
