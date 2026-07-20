import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/data/duas.dart';
import 'package:sanad/services/asr/phoneme_corpus.dart';
import 'package:sanad/services/asr/phoneme_matcher.dart';

/// Data-foundation checks for the du'a corpus (pure Dart, no model/device):
///  - every du'a in the content list loads its phoneme clip;
///  - wordCount == number of display words (1:1 corpus↔display);
///  - phonemeToWord is non-decreasing, contiguous per word, and covers exactly
///    words 0..wordCount-1 (no gaps, no stray indices);
///  - every phoneme unit is non-empty AND exists in the model vocab (0 OOV) —
///    the guarantee the recitation model can actually follow the du'a.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('content list has the 5 validated duas', () {
    expect(duas.length, 5);
    expect(duas.first.id, 'dua-after-adhan');
  });

  test('every phoneme unit is in the model vocab (0 OOV across all duas)', () async {
    final vocab = (await loadPhonemeUnits()).toSet();
    var oov = 0;
    for (final d in duas) {
      final dc = await loadDuaClip(d.id);
      for (final p in dc.clip.phonemes) {
        if (!vocab.contains(p)) oov++;
      }
    }
    expect(oov, 0, reason: 'model vocab must contain every corpus phoneme');
  });

  for (final d in duas) {
    test('loadDuaClip(${d.id}) is well-formed', () async {
      final vocab = (await loadPhonemeUnits()).toSet();
      final dc = await loadDuaClip(d.id);

      expect(dc.id, d.id);
      expect(dc.words, isNotEmpty);
      expect(dc.clip.wordCount, dc.words.length,
          reason: 'wordCount must equal display word count');

      final p2w = dc.clip.phonemeToWord;
      expect(p2w.length, dc.clip.phonemes.length);
      expect(p2w.first, 0, reason: 'must start at word 0');
      expect(p2w.reduce((a, b) => a > b ? a : b), dc.clip.wordCount - 1,
          reason: 'max phonemeToWord must be last word index');
      for (var i = 1; i < p2w.length; i++) {
        expect(p2w[i] >= p2w[i - 1], isTrue,
            reason: 'phonemeToWord must be non-decreasing at $i');
        expect(p2w[i] - p2w[i - 1] <= 1, isTrue,
            reason: 'words must be contiguous (no skipped word) at $i');
      }

      for (final ph in dc.clip.phonemes) {
        expect(ph, isNotEmpty, reason: 'no empty phoneme unit');
        expect(vocab.contains(ph), isTrue, reason: 'OOV phoneme "$ph" in ${d.id}');
      }
    });
  }

  // Device logs (2026-07-20) showed dua-aslamtu-nafsi's follow-along never
  // anchoring — cursor crept via best-match but no two consecutive words
  // ever crossed the green threshold, despite a real recitation the whole
  // session. Isolate whether that's the matcher/data (reproducible with a
  // PERFECT self-fed input, like the Quran smoke tests in
  // phoneme_matcher_test.dart) or real-audio recognition noise this can't
  // catch: if it anchors and greens end-to-end here, the matcher is sound
  // and the device failure was in the ASR pass, not this logic.
  for (final d in duas) {
    test('matcher anchors + tracks a perfect recitation of ${d.id}', () async {
      final units = await loadPhonemeUnits();
      final dc = await loadDuaClip(d.id);
      final matcher = PhonemeMatchSession(dc.clip, units);
      final ref = dc.clip.phonemes;
      MatchOutput? out;
      for (var end = 3; end < ref.length; end += 3) {
        out = matcher.apply(ref.sublist(0, end));
      }
      out = matcher.apply(ref);
      final n = dc.clip.wordCount;
      final greens = out.states.where((s) => s == WordState.correct).length;
      expect(matcher.anchored, isTrue, reason: '${d.id}: must anchor on a clean recitation');
      expect(greens, n, reason: '${d.id}: every word must green on a perfect recitation');
      expect(out.cursor, n - 1);
    });
  }
}
