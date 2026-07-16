import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/services/asr/phoneme_corpus.dart';
import 'package:tilawa_ai/services/asr/phoneme_matcher.dart';
import 'package:tilawa_ai/services/asr/tajweed_review.dart';

/// Pure unit tests for the post-recitation tajwīd review, ported from the
/// validated ZikirAi cases (src/lib/matcher/tajweedReview.ts). A tiny synthetic
/// clip + vocab exercises each mask directly — no ReadingState, no model.
///
/// Vocab is all single letters, so the greedy tokenizer splits a transcript into
/// individual chars (whitespace skipped) and every reference position is one letter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reliability asset loads and parses, floored below the min-sample size',
      () async {
    final rel = await loadPhonemeReliability();
    // ب has enough samples (seen=24) to trust its measured reliability.
    expect(rel['ب'], 1.0);
    // ط's raw point estimate is 1.0, but at only seen=6 that is not enough
    // evidence to trust — the loader floors it to 0 (reliability-unknown) so
    // the review's threshold gate silences it, same as a genuinely blind letter.
    expect(rel['ط'], 0.0);
    expect(rel['ق']! < 0.95, isTrue); // blind (thin evidence AND a low raw estimate)
    expect(rel.length, greaterThan(20));
  });

  test('a single-observation "lucky" 100% letter is floored to unreliable',
      () async {
    // ج/ث/ز each have exactly one observation in the source table (seen=1,
    // ok=1) -- a raw reliability of 1.0 that reflects zero real evidence. This
    // is the exact false-trust case the min-sample floor exists to prevent.
    final rel = await loadPhonemeReliability();
    expect(rel['ج'], 0.0);
    expect(rel['ث'], 0.0);
    expect(rel['ز'], 0.0);
  });

  const units = ['ب', 'ا', 'ط', 'ت', 'ق', 'ن', 'و', 'ي', 'د', 'ز'];
  // ن is exactly at the 0.95 threshold (reliable); ق below it (blind).
  const reliability = <String, double>{
    'ب': 1.0, 'ا': 0.99, 'ط': 1.0, 'ت': 0.9, 'ق': 0.6,
    'ن': 0.95, 'و': 0.95, 'ي': 0.96, 'د': 0.9, 'ز': 1.0,
  };

  // Build a clip from (wordString, phonemes) pairs.
  (PhonemeClip, List<String>) build(List<(String, List<String>)> spec) {
    final phonemes = <String>[];
    final p2w = <int>[];
    final words = <String>[];
    for (var w = 0; w < spec.length; w++) {
      words.add(spec[w].$1);
      for (final ph in spec[w].$2) {
        phonemes.add(ph);
        p2w.add(w);
      }
    }
    final clip = PhonemeClip(
      wordCount: spec.length,
      phonemes: phonemes,
      phonemeToWord: p2w,
      ayahBoundaries: const [0],
    );
    return (clip, words);
  }

  test('(a) correct transcript → 0 flags', () {
    final (clip, words) = build([
      ('بَاب', ['ب', 'ا', 'ب']),
      ('طَاب', ['ط', 'ا', 'ب']),
      ('قَاب', ['ق', 'ا', 'ب']),
    ]);
    final flags = reviewTajweed(clip, words, 'باب طاب قاب', units, reliability);
    expect(flags, isEmpty);
  });

  test('(b) makhraj substitution ط→ت on a reliable letter → 1 flag', () {
    final (clip, words) = build([
      ('بَاب', ['ب', 'ا', 'ب']),
      ('طَاب', ['ط', 'ا', 'ب']),
      ('قَاب', ['ق', 'ا', 'ب']),
    ]);
    final flags = reviewTajweed(clip, words, 'باب تاب قاب', units, reliability);
    expect(flags.length, 1);
    expect(flags.first.wordIndex, 1);
    expect(flags.first.ref, 'ط');
    expect(flags.first.heard, 'ت');
    expect(flags.first.reliability, 1.0);
  });

  test('(c) same substitution on a below-threshold (blind) letter ق → 0 flags', () {
    final (clip, words) = build([
      ('بَاب', ['ب', 'ا', 'ب']),
      ('طَاب', ['ط', 'ا', 'ب']),
      ('قَاب', ['ق', 'ا', 'ب']),
    ]);
    // ق→د on word 2; ق reliability 0.6 < 0.95, so it stays silent.
    final flags = reviewTajweed(clip, words, 'باب طاب داب', units, reliability);
    expect(flags, isEmpty);
  });

  test('(d) substitution inside a whitespace-merged junction word → 0 flags', () {
    final (clip, words) = build([
      ('بَاب', ['ب', 'ا', 'ب']),
      ('نَا وَا', ['ن', 'ا', 'و', 'ا']), // space → junction unit
    ]);
    // ن→ت on the junction word; ن is reliable (0.95), so only the junction mask
    // (letter-by-letter compare invalid across an assimilation) can suppress it.
    final flags = reviewTajweed(clip, words, 'باب تاوا', units, reliability);
    expect(flags, isEmpty);
  });

  test('(e) madd bleed (long madd heard as a glide) → 0 flags', () {
    final (clip, words) = build([
      ('طَاب', ['ط', 'ا', 'ب']),
    ]);
    // ب heard as و: reliable and a real makhraj change, but the previous ref is a
    // madd (ا) and the heard letter is a madd glide (و) → masked as madd bleed.
    final flags = reviewTajweed(clip, words, 'طاو', units, reliability);
    expect(flags, isEmpty);
  });

  test('(f) a deletion and an insertion → 0 flags (only substitutions count)', () {
    final (clip, words) = build([
      ('طَاب', ['ط', 'ا', 'ب']),
    ]);
    // Deletion: the ا is dropped.
    expect(reviewTajweed(clip, words, 'طب', units, reliability), isEmpty);
    // Insertion: an extra ا is added.
    expect(reviewTajweed(clip, words, 'طااب', units, reliability), isEmpty);
  });

  test('maxWordIndex bounds the alignment to the recited span', () {
    final (clip, words) = build([
      ('طَاب', ['ط', 'ا', 'ب']),
      ('قَاب', ['ق', 'ا', 'ب']),
    ]);
    // Only word 0 recited (with a ط→ت slip); word 1 must not manufacture flags
    // from its un-recited reference phonemes.
    final flags = reviewTajweed(clip, words, 'تاب', units, reliability, maxWordIndex: 0);
    expect(flags.length, 1);
    expect(flags.first.wordIndex, 0);
    expect(flags.first.ref, 'ط');
  });

  test('minWordIndex bounds the alignment on a mid-start recitation', () {
    final (clip, words) = build([
      ('بَاب', ['ب', 'ا', 'ب']),
      ('طَاب', ['ط', 'ا', 'ب']),
    ]);
    // Reciter started at word 1 (with a ط→ت slip); the un-recited word 0 must not
    // corrupt the alignment path. Without the minWordIndex bound, the leading
    // ب-ا-ب reference would drag flags onto correct content.
    final flags = reviewTajweed(clip, words, 'تاب', units, reliability, minWordIndex: 1);
    expect(flags.length, 1);
    expect(flags.first.wordIndex, 1);
    expect(flags.first.ref, 'ط');
  });

  test('two independent makhraj slips → two flags', () {
    final (clip, words) = build([
      ('طَاب', ['ط', 'ا', 'ب']),
      ('بَاز', ['ب', 'ا', 'ز']),
    ]);
    // ط→ت in word 0, ز→د in word 1 (both reliable).
    final flags = reviewTajweed(clip, words, 'تاب باد', units, reliability);
    expect(flags.map((f) => (f.wordIndex, f.ref, f.heard)).toList(),
        [(0, 'ط', 'ت'), (1, 'ز', 'د')]);
  });

  test('timestamps → flag carries the word audio span (single cluster)', () {
    final (clip, words) = build([
      ('بَاب', ['ب', 'ا', 'ب']),
      ('طَاب', ['ط', 'ا', 'ب']),
      ('قَاب', ['ق', 'ا', 'ب']),
    ]);
    // ط→ت on word 1. Tokens: ب ا ب ت ا ب ق ا ب (index 3 = the ت anchor); word 1
    // tokens are 3,4,5 (one contiguous cluster).
    final ts = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8];
    final flags = reviewTajweed(clip, words, 'باب تاب قاب', units, reliability, timestamps: ts);
    expect(flags.length, 1);
    final f = flags.first;
    // startSec = ts[3] - 0.25; endSec = ts[6] + 0.25 (hi+1=6 < len).
    expect(f.startSec, closeTo(0.3 - 0.25, 1e-9));
    expect(f.endSec, closeTo(0.6 + 0.25, 1e-9));
  });

  test('re-read: span uses only the anchor cluster, not min..max', () {
    // Word 0 = د ا ب ر. The reciter says "دا", then a long detour of foreign
    // tokens (aligned as insertions), then finishes "بـز" (ر→ز slip). The word's
    // own tokens land in TWO separated clusters {0,1} and {7,8}; min..max would
    // stretch the span across the whole detour, but the flag (anchor token 8)
    // must play only its own cluster {7,8}.
    final localUnits = ['د', 'ا', 'ب', 'ر', 'ت', 'ز', 'ن'];
    const localRel = <String, double>{
      'د': 1.0, 'ا': 0.99, 'ب': 1.0, 'ر': 1.0, 'ت': 1.0, 'ز': 1.0, 'ن': 0.95,
    };
    final (clip, words) = build([
      ('دَابِر', ['د', 'ا', 'ب', 'ر']),
      ('نَا', ['ن', 'ا']),
    ]);
    // Tokens: د ا ت ت ت ت ت ب ز  → indices 0..8. Word-0 ref tokens: 0,1 (د,ا) and
    // 7,8 (ب, ز→ر). The five ت are insertions.
    final ts = [0.0, 0.1, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1];
    final flags =
        reviewTajweed(clip, words, 'دا ت ت ت ت ت ب ز', localUnits, localRel, timestamps: ts, maxWordIndex: 0);
    expect(flags.length, 1);
    final f = flags.first;
    expect(f.ref, 'ر');
    expect(f.heard, 'ز');
    // Anchor cluster is {7,8}: startSec = ts[7] - 0.25 = 1.75 (NOT ~0 from ts[0]).
    expect(f.startSec, closeTo(2.0 - 0.25, 1e-9));
    // hi=8 is the last token, so endSec = ts[8] + 0.4 + 0.25.
    expect(f.endSec, closeTo(2.1 + 0.4 + 0.25, 1e-9));
  });

  test('span extends the full contiguous cluster below a late-word flag', () {
    // A 6-phoneme word whose flagged letter is the LAST one, all tokens
    // consecutive (0..5), anchor 5. The low edge must chain all the way to token
    // 0 — an ascending one-hop low-loop would stop at token 2 and front-truncate.
    final localUnits = ['د', 'ا', 'ب', 'ر', 'ن', 'ز', 'ت'];
    const localRel = <String, double>{
      'د': 1.0, 'ا': 0.99, 'ب': 1.0, 'ر': 1.0, 'ن': 1.0, 'ز': 1.0, 'ت': 1.0,
    };
    final (clip, words) = build([
      ('دابرنز', ['د', 'ا', 'ب', 'ر', 'ن', 'ز']),
    ]);
    // ز→ت on the last phoneme (token 5). Tokens: د ا ب ر ن ت.
    final ts = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5];
    final flags =
        reviewTajweed(clip, words, 'د ا ب ر ن ت', localUnits, localRel, timestamps: ts);
    expect(flags.length, 1);
    final f = flags.first;
    expect(f.ref, 'ز');
    // lo must reach token 0 → startSec = ts[0] - 0.25 = 0.75, not ts[2]-0.25.
    expect(f.startSec, closeTo(1.0 - 0.25, 1e-9));
  });

  test('no timestamps → flag carries no audio span', () {
    final (clip, words) = build([
      ('طَاب', ['ط', 'ا', 'ب']),
    ]);
    final flags = reviewTajweed(clip, words, 'تاب', units, reliability);
    expect(flags.single.startSec, isNull);
    expect(flags.single.endSec, isNull);
  });
}
