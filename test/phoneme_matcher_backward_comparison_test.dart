import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/phoneme_corpus.dart';
import 'package:sanad/services/asr/phoneme_matcher.dart';

/// A fair, in-repo comparison of the shipped FOLLOW-ANYWHERE (backward-
/// tracking) matcher against a WORD-TRACK-style SIDESTEP (forward-only)
/// variant — same engine, same tuning, just `allowBackward: false` (see
/// PhonemeMatchSession's doc comment). Two things checked:
///
///  1. The exact false-green repro from the 2026-07-20 investigation (see
///     memory `asr-matcher-cursor-contracts`): does sidestep actually avoid
///     it, given the two scenarios feed a BYTE-IDENTICAL token stream to the
///     matcher (that's the proven reason a matcher-only fix is impossible —
///     there's no way to tell "went back to re-read" from "read forward
///     through a repeat" from the stream alone)?
///  2. A natural-stumble scenario over a REAL surah (a reciter hesitates and
///     repeats the last couple of words, then continues) — the kind of
///     recitation backward-tracking exists to serve. This is NOT the old
///     cross-repo "Kursi 24/46→8/46" number (that tested a different,
///     forward-PEGGED commit-horizon retrofit, not this sidestep contract) —
///     it is a fresh measurement of THIS specific alternative.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('false-green repro (byte-identical stream, two intents)', () {
    // 7 words of 3 phonemes each (realistic word length — a single-phoneme
    // word needs a 100% match per _greenNeed, too strict to ever anchor).
    // w0..w4 distinct; w5 repeats w0's phonemes, w6 repeats w1's — so
    // reciting the WHOLE clip straight through (scenario B) produces the
    // exact same stream as reciting w0-w4 then re-reading w0,w1 (scenario A).
    const units = ['a1', 'a2', 'a3', 'b1', 'b2', 'b3', 'c1', 'c2', 'c3', 'd1', 'd2', 'd3', 'e1', 'e2', 'e3'];
    const w0 = ['a1', 'a2', 'a3'];
    const w1 = ['b1', 'b2', 'b3'];
    const w2 = ['c1', 'c2', 'c3'];
    const w3 = ['d1', 'd2', 'd3'];
    const w4 = ['e1', 'e2', 'e3'];
    final phonemes = [...w0, ...w1, ...w2, ...w3, ...w4, ...w0, ...w1];
    final clip = PhonemeClip(
      wordCount: 7,
      phonemes: phonemes,
      phonemeToWord: [
        for (var w = 0; w < 5; w++) ...List.filled(3, w),
        ...List.filled(3, 5),
        ...List.filled(3, 6),
      ],
      ayahBoundaries: const [],
    );
    // Recite w0-w4, then EITHER re-read w0,w1 (backward) OR continue forward
    // into the genuine repeat at w5/w6 — the stream is identical either way.
    final stream = [...w0, ...w1, ...w2, ...w3, ...w4, ...w0, ...w1];

    test('shipped follow-anywhere false-greens w5/w6 as "reached"', () {
      final m = PhonemeMatchSession(clip, units); // allowBackward: true (default)
      MatchOutput? out;
      for (var i = 1; i <= stream.length; i++) {
        out = m.apply(stream.sublist(0, i));
      }
      // ignore: avoid_print
      print('follow-anywhere: reached=${m.reached} head=${m.head} '
          'states=${out!.states}');
      expect(m.reached, greaterThanOrEqualTo(5),
          reason: 'the documented false-green: w5/w6 read as reached even '
              'when the audio was actually a backward re-read of w0/w1');
    });

    test('sidestep (forward-only) never advances past the real frontier on the same stream', () {
      final m = PhonemeMatchSession(clip, units, allowBackward: false);
      MatchOutput? out;
      for (var i = 1; i <= stream.length; i++) {
        out = m.apply(stream.sublist(0, i));
      }
      // ignore: avoid_print
      print('sidestep: reached=${m.reached} head=${m.head} states=${out!.states}');
      // Whichever the true intent was, sidestep can't be fooled into
      // crediting w5/w6 from a stream that's consistent with "re-read w0/w1"
      // — it has no window behind the frontier to have matched w0/w1 again
      // in the first place, so the repeat's audio simply doesn't extend the
      // frontier past where "a b c d e" alone would have left it.
      expect(m.reached, lessThan(5),
          reason: 'sidestep must NOT credit w5/w6 as reached from this stream');
    });
  });

  group('natural stumble-and-repeat over a real surah', () {
    // Al-Ikhlas (112): short, no internal repeats of its own (a clean surah
    // to isolate the INJECTED stumble from any pre-existing textual repeats).
    Future<({int greens, int n, bool anchored})> run(
        String label, bool allowBackward) async {
      final units = await loadPhonemeUnits();
      final sc = await loadSurahClip(112);
      final ref = sc.clip.phonemes;
      final p2w = sc.clip.phonemeToWord;
      final n = sc.clip.wordCount;
      final m = PhonemeMatchSession(sc.clip, units, allowBackward: allowBackward);

      // First phoneme index of each word, so we can cut the stream at word
      // boundaries (mirrors PhonemeMatchSession's own _wordPhonemes grouping).
      int firstPhonemeOf(int word) => p2w.indexOf(word);

      // Simulate: recite forward through 60% of the surah, hesitate, repeat
      // the last 3 words, then recite the rest — a very common, ordinary
      // stumble, not a pathological repeated-phrase case.
      final stumbleWord = (n * 0.6).floor().clamp(3, n - 1);
      final cutIdx = firstPhonemeOf(stumbleWord);
      final repeatFromIdx = firstPhonemeOf((stumbleWord - 3).clamp(0, stumbleWord));
      final cleanForward = ref.sublist(0, cutIdx);
      final repeatChunk = ref.sublist(repeatFromIdx, cutIdx);
      final rest = ref.sublist(cutIdx);
      final stream = [...cleanForward, ...repeatChunk, ...rest];

      MatchOutput? out;
      for (var i = 3; i <= stream.length; i += 3) {
        out = m.apply(stream.sublist(0, i));
      }
      out = m.apply(stream);
      final greens = out.states.where((s) => s == WordState.correct).length;
      // ignore: avoid_print
      print('$label: greens=$greens/$n cursor=${out.cursor} anchored=${m.anchored}');
      return (greens: greens, n: n, anchored: m.anchored);
    }

    test('follow-anywhere vs sidestep on an ordinary stumble-and-repeat', () async {
      final anywhere = await run('follow-anywhere', true);
      final sidestep = await run('sidestep       ', false);
      // These two groups used to be print-only: a regression could stall the
      // sidestep frontier completely and the file still reported success, even
      // though reading_state.dart ships allowBackward:false for the Qur'an
      // reader. Floors, not exact counts — the point is to catch a collapse
      // (a broken window drops sidestep to 2/46), not to freeze a tuning number.
      expect(anywhere.anchored, isTrue, reason: 'follow-anywhere must lock on');
      expect(sidestep.anchored, isTrue, reason: 'sidestep must lock on');
      expect(anywhere.greens, greaterThanOrEqualTo((anywhere.n * 0.85).floor()));
      expect(sidestep.greens, greaterThanOrEqualTo((sidestep.n * 0.80).floor()));
    });
  });

  group('heavier load: multiple stumbles over Ayat al-Kursi (2:255)', () {
    // The old cross-repo number this whole comparison exists to re-check
    // ("Kursi 24/46→8/46") was measured on Ayat al-Kursi specifically — a
    // long single ayah (~46-50 words), the kind a careful reciter often
    // self-corrects on more than once. Isolate just that ayah from surah 2
    // and inject THREE stumbles spread across it (not one), so the
    // comparison is under a load closer to what that number represented —
    // while still being a fresh, in-repo measurement of THIS variant, not
    // a re-run of the old (different) forward-pegged retrofit.
    Future<({int greens, int n, bool anchored})> run(
        String label, bool allowBackward) async {
      final units = await loadPhonemeUnits();
      final sc = await loadSurahClip(2);
      final ayahIdx = 254; // 0-indexed ayah 255
      final vStart = sc.clip.ayahBoundaries[ayahIdx];
      final vEnd = ayahIdx + 1 < sc.clip.ayahBoundaries.length
          ? sc.clip.ayahBoundaries[ayahIdx + 1] - 1
          : sc.clip.wordCount - 1;
      final p2w = sc.clip.phonemeToWord;
      final phFirst = p2w.indexOf(vStart);
      final phLast = p2w.lastIndexOf(vEnd);

      final n = vEnd - vStart + 1;
      final ayahPhonemes = sc.clip.phonemes.sublist(phFirst, phLast + 1);
      final ayahP2w = [for (final w in p2w.sublist(phFirst, phLast + 1)) w - vStart];
      final clip = PhonemeClip(
        wordCount: n,
        phonemes: ayahPhonemes,
        phonemeToWord: ayahP2w,
        ayahBoundaries: const [0], // isolated as its own single span
      );
      final m = PhonemeMatchSession(clip, units, allowBackward: allowBackward);

      int firstPhonemeOf(int word) => ayahP2w.indexOf(word);
      // Stumble at ~25%, ~50%, ~75% through the ayah, each re-reading the
      // previous 3 words before continuing — three self-corrections across
      // one long ayah, not just one.
      final stream = <String>[];
      var pos = 0;
      for (final frac in [0.25, 0.5, 0.75]) {
        final cut = firstPhonemeOf((n * frac).floor().clamp(3, n - 1));
        final repeatFrom = firstPhonemeOf(((n * frac).floor() - 3).clamp(0, n - 1));
        stream.addAll(ayahPhonemes.sublist(pos, cut));
        stream.addAll(ayahPhonemes.sublist(repeatFrom, cut)); // the re-read
        pos = cut;
      }
      stream.addAll(ayahPhonemes.sublist(pos));

      MatchOutput? out;
      for (var i = 3; i <= stream.length; i += 3) {
        out = m.apply(stream.sublist(0, i));
      }
      out = m.apply(stream);
      final greens = out.states.where((s) => s == WordState.correct).length;
      // ignore: avoid_print
      print('$label: greens=$greens/$n cursor=${out.cursor} anchored=${m.anchored}');
      return (greens: greens, n: n, anchored: m.anchored);
    }

    test('follow-anywhere vs sidestep under 3 stumbles across Ayat al-Kursi', () async {
      final anywhere = await run('follow-anywhere', true);
      final sidestep = await run('sidestep       ', false);
      // These two groups used to be print-only: a regression could stall the
      // sidestep frontier completely and the file still reported success, even
      // though reading_state.dart ships allowBackward:false for the Qur'an
      // reader. Floors, not exact counts — the point is to catch a collapse
      // (a broken window drops sidestep to 2/46), not to freeze a tuning number.
      expect(anywhere.anchored, isTrue, reason: 'follow-anywhere must lock on');
      expect(sidestep.anchored, isTrue, reason: 'sidestep must lock on');
      expect(anywhere.greens, greaterThanOrEqualTo((anywhere.n * 0.85).floor()));
      expect(sidestep.greens, greaterThanOrEqualTo((sidestep.n * 0.80).floor()));
    });
  });
}
