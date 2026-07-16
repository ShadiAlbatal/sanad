import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/services/asr/phoneme_corpus.dart';
import 'package:tilawa_ai/services/asr/tajweed_review.dart';

// REGRESSION: replay the real device Al-Baqara run (run_20260715_154405.log,
// TOKENSTREAM surah=2 n=315). It ORIGINALLY produced 3 FALSE makhraj flags at
// 2:102:60 (ش→ف) / 2:104:8 (ں→ن) / 2:105:19 (ب→م) — the reciter made no error
// there. anchor=minWordIndex=1497, reached=maxWordIndex=1563. After the fix
// (noon-ghunna fold + the model-confusable ش↔ف / ب↔م masks) it must yield 0.
const transcript = 'ءِ للَ اا بِ ءِ ذ نِ للَ اا هِ يَ تَ للَ مُ ۥۥ نَ مَ اا يَ ضُ ررُ هُ م وَ لَ اا يَ ںںں فَ عُ هُ م وَ لَ قَ دڇ عَ لِ مُ ۥۥ نَ مَ نِ ف تَ رَ اا هُ مَ اا لَ هُ ۥۥ فِ ل ءَ اا خِ رَ تِ مِ ن خَ لَ اا قڇ لَ سَ مَ اا شَ رَ و بِ هِ ۦۦۦۦ ءَ ںںں فُ سَ اا هُ م تَ و كَ اا نُ ۥۥ يَ ع لَ مُ ۥۥ ن وَ لَ و ءَ ننننَ هُ م ءَ اا مَ نُ ۥۥ تتَ قُ ۥۥ نَ مَ تُ ۥۥ بَ تُ ممممِ ن عِ ںںں بِ للَ اا هِ خَ ي رُ وووَ لَ و ءَ ننننَ هُ م ءَ اا مَ نُ ۥۥ وَ تتَ قَ و لَ مَ تُ ۥۥ بَ تُ ممممِ ن عِ ںںں دِ للَ اا هِ خَ ي رُ لَ و كَ اا نُ ۥۥ يَ ع لَ مُ ۥۥ ن اااا ءَ ييُ هَ للَ ذِ ۦۦ نَ ءَ اا مَ نُ ۥۥ لَ اا تَ قُ ۥۥ لُ ۥۥ رَ اا عِ نَ اا وَ قُ ۥۥ لُ ن ظُ رُ ر ن اا وَ س مَ عُ ۥۥ وَ لِ ل كَ اا فِ رِ ۦۦ نَ عَ ذَ اا بُ ن ءَ لِ ۦۦ م مَ اا يَ وَ ددُ للَ ذِ ۦۦ نَ كَ فَ رُ ۥۥ مِ ن ءَ ه لِ ل كِ تَ اا بِ وَ لَ دڇ ل مُ ش رِ كِ ۦۦ نَ ءَ يييُ نَ ززِ لَ عَ لَ ي كُ ممممِ ن خَ ي رِ ممممِ ررَ ببِ كُ م للَ اا هُ يَ خ تَ صصُ مِ رَ ح مَ تِ هِ ۦۦ مَ يييَ شَ اااا ءُ وَ للَ اا هُ ذُ ل فَ طُ لِ ل عَ ظِ ۦۦ م';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real Al-Baqara device stream (min1497/max1563) produces 0 false flags', () async {
    final clip = await loadSurahClip(2);
    final units = await loadPhonemeUnits();
    final rel = await loadPhonemeReliability();
    final flags = reviewTajweed(clip.clip, clip.words, transcript, units, rel,
        minWordIndex: 1497, maxWordIndex: 1563);
    final located = [
      for (final f in flags) '${clip.wordLocations[f.wordIndex]} ${f.ref}->${f.heard}'
    ];
    expect(flags, isEmpty, reason: 'expected no makhraj flags, got $located');
  });
}
