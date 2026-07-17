import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/session.dart';
import 'package:sanad/services/asr/tajweed_review.dart';
import 'package:sanad/state/dua_reading_state.dart';

/// Pins the pure du'a flag→mistake mapping: makhraj flags become mispronounced
/// records (word index as location, display word as expected, span×16k as
/// samples), skipped words become skipped records, and a word that is BOTH
/// flagged and skipped is only ever listed once (as skipped).
void main() {
  const words = ['اللَّهُمَّ', 'رَبَّ', 'هَٰذِهِ', 'الدَّعْوَةِ'];

  test('makhraj flag maps to a mispronounced mistake with audio span', () {
    final m = buildDuaMistakes(
      flags: [const TajweedFlag(1, 'ت', 'ط', 0.97, startSec: 1.0, endSec: 1.5)],
      words: words,
      skippedWords: const {},
      retainedSamples: 16000 * 3,
    );
    expect(m, hasLength(1));
    expect(m.first.kind, MistakeKind.mispronounced);
    expect(m.first.location, '1');
    expect(m.first.expectedText, 'رَبَّ');
    expect(m.first.heardText, 'ط');
    expect(m.first.startSample, 16000);
    expect(m.first.endSample, 24000);
    expect(m.first.hasAudio, isTrue);
  });

  test('flag without timestamps has no audio span', () {
    final m = buildDuaMistakes(
      flags: [const TajweedFlag(0, 'ه', 'ح', 0.96)],
      words: words,
      skippedWords: const {},
      retainedSamples: 16000,
    );
    expect(m.single.startSample, -1);
    expect(m.single.hasAudio, isFalse);
  });

  test('skipped words become skipped mistakes', () {
    final m = buildDuaMistakes(
      flags: const [],
      words: words,
      skippedWords: {2, 3},
      retainedSamples: 0,
    );
    expect(m.map((e) => e.kind).toSet(), {MistakeKind.skipped});
    expect(m.map((e) => e.location).toSet(), {'2', '3'});
    expect(m.map((e) => e.expectedText).toSet(), {'هَٰذِهِ', 'الدَّعْوَةِ'});
  });

  test('a word both flagged and skipped is listed once, as skipped', () {
    final m = buildDuaMistakes(
      flags: [const TajweedFlag(2, 'ذ', 'د', 0.98)],
      words: words,
      skippedWords: {2},
      retainedSamples: 0,
    );
    expect(m, hasLength(1));
    expect(m.single.kind, MistakeKind.skipped);
    expect(m.single.location, '2');
  });

  test('out-of-range indices are dropped', () {
    final m = buildDuaMistakes(
      flags: [const TajweedFlag(99, 'ب', 'ت', 0.99)],
      words: words,
      skippedWords: {42},
      retainedSamples: 0,
    );
    expect(m, isEmpty);
  });
}
