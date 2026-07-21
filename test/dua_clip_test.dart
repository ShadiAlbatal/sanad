import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/data/duas.dart';
import 'package:sanad/services/asr/dua_search.dart';
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

  test('content list has the 6 validated duas', () {
    expect(duas.length, 6);
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

  // The anchor lock wants two consecutive green words, which a ONE-word clip
  // can never supply — so these du'ās anchored=false / greens=0 even on a
  // perfect self-fed recitation: no marker, no green, and skip-advance
  // recovery unreachable too (_stuckChunks resets while _anchor < 0). They are
  // reachable from the Azkar tab like any other du'ā, so this is a live
  // follow-along dead end, not a corpus-only curiosity.
  // The loop above covers the 6-entry `duas` const, which NO screen reads — the
  // Azkar tab browses all 260 corpus entries and can open any of them. Sweep the
  // real browsable list so a du'a that can't be followed is caught here instead
  // of on a device. Known-bad ids are named with their cause: any NEW failure
  // breaks the build, and repairing one forces this list to shrink.
  const knownIncomplete = {
    // Only 3 phonemes long, so this HARNESS never reaches the matcher's
    // "enough audio to localize" gate (tail >= 6 tokens) — a real stream does,
    // and the test below proves it anchors and greens there.
    'hisn-197': 'clip is shorter than the 6-token localize gate; fine on a real stream',
    // Repeated-phrase du'as (hisn-31 is الله أكبر x3). The frontier does walk to
    // the end via skip-advance, but the later occurrences are credited to the
    // FIRST copy, so those words mark skipped instead of green. Same family as
    // the documented backward false-green limitation — not a fixable stall.
    'hisn-31': 'repeated phrases x3: 22/31 green, rest marked skipped',
    'hisn-53': 'repeated phrases: 30/34 green',
    'hisn-74': 'repeated phrases over 137 words: 98/137 green',
  };

  test('every browsable du\'a anchors and greens on a perfect recitation', () async {
    final units = await loadPhonemeUnits();
    final ids = (await loadDuaSearch()).allDuas.map((m) => m.id).toList();
    expect(ids.length, greaterThan(250), reason: 'the whole corpus must be swept');
    final incomplete = <String>[];
    for (final id in ids) {
      final dc = await loadDuaClip(id);
      final ref = dc.clip.phonemes;
      final matcher = PhonemeMatchSession(dc.clip, units);
      for (var end = 3; end < ref.length; end += 3) {
        matcher.apply(ref.sublist(0, end));
      }
      // Mic chunks keep arriving after the last word is spoken, so the frontier
      // gets the same chance to catch up here that it has on a device.
      MatchOutput? out;
      for (var k = 0; k < 9; k++) {
        out = matcher.apply(ref);
      }
      final n = dc.clip.wordCount;
      final greens = out!.states.where((s) => s == WordState.correct).length;
      if (!matcher.anchored || greens != n) incomplete.add(id);
    }
    expect(incomplete.toSet(), knownIncomplete.keys.toSet(),
        reason: 'du\'as that cannot be fully followed changed — see knownIncomplete');
  });

  test("a du'a shorter than the score floor still anchors (hisn-197)", () async {
    // The localizer scores kLocMatch (3) per matched phoneme, so this 3-phoneme
    // du'a tops out at 9 — under the flat _scoreFloor of 12, which meant the
    // matcher rejected a PERFECT recitation of it forever. The floor is now
    // capped at what a full match of the clip is worth. Feed a stream long
    // enough to clear the separate "enough audio" gate, as a device does.
    final units = await loadPhonemeUnits();
    final dc = await loadDuaClip('hisn-197');
    final ref = dc.clip.phonemes;
    expect(ref.length, lessThan(4), reason: 'hisn-197 must still be the short case');
    final stream = [...ref, ...ref];
    final matcher = PhonemeMatchSession(dc.clip, units);
    MatchOutput? out;
    for (var end = 1; end <= stream.length; end++) {
      out = matcher.apply(stream.sublist(0, end));
    }
    expect(matcher.anchored, isTrue, reason: 'a short clip must still lock on');
    expect(out!.states.single, WordState.correct);
  });

  for (final id in const ['hisn-11', 'hisn-142']) {
    test('single-word du\'a $id anchors and greens its only word', () async {
      final units = await loadPhonemeUnits();
      final dc = await loadDuaClip(id);
      expect(dc.clip.wordCount, 1, reason: '$id must still be a one-word clip');
      final matcher = PhonemeMatchSession(dc.clip, units);
      final ref = dc.clip.phonemes;
      MatchOutput? out;
      for (var end = 3; end < ref.length; end += 3) {
        out = matcher.apply(ref.sublist(0, end));
      }
      out = matcher.apply(ref);
      expect(matcher.anchored, isTrue, reason: '$id: must anchor on a clean recitation');
      expect(out.states.single, WordState.correct,
          reason: '$id: its only word must green on a perfect recitation');
    });
  }
}
