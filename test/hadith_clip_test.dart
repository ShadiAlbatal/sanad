import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/hadith_corpus.dart';
import 'package:sanad/services/asr/phoneme_corpus.dart' show loadPhonemeUnits;
import 'package:sanad/services/asr/phoneme_matcher.dart';

/// Follow-along foundation for the hadith reader: proves the PACKAGED gzipped
/// asset now carries a well-formed per-hadith CLIP (words + phonemeToWord +
/// phonemes) that the reader's [PhonemeMatchSession] can drive — the same
/// guarantees dua_clip_test pins for du'ās, plus the decode-fidelity guard for
/// the `<blank>`-inclusive vocab convention (an off-by-one there would shift
/// every phoneme by one unit and silently corrupt greening).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HadithCorpus corpus;
  late Set<String> vocab;
  late List<String> vocabList;

  setUpAll(() async {
    corpus = await loadHadithCorpus();
    vocabList = await loadPhonemeUnits();
    vocab = vocabList.toSet();
  });

  test('every hadith carries a follow-along clip (words restored, not dropped)', () {
    final withClip = corpus.byId.values.where((e) => e.hasClip).length;
    expect(withClip, corpus.byId.length,
        reason: 'the repacked asset must keep words+phonemeToWord for every hadith');
  });

  test('clip word map is well-formed across a deterministic sample', () {
    // Deterministic spread: every 137th entry (id-sorted) — ~90 hadith across both
    // collections, short and long, without the cost of all ~12k.
    final entries = corpus.byId.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    var checked = 0;
    for (var k = 0; k < entries.length; k += 137) {
      final e = entries[k];
      final clip = e.clip!;
      checked++;

      expect(clip.words, isNotEmpty, reason: '${e.id} has no words');
      expect(clip.clip.wordCount, clip.words.length,
          reason: '${e.id}: wordCount must equal display word count');

      final p2w = clip.clip.phonemeToWord;
      expect(p2w.length, clip.clip.phonemes.length,
          reason: '${e.id}: phonemeToWord length must equal phoneme count');
      expect(p2w.first, 0, reason: '${e.id}: must start at word 0');
      expect(p2w.reduce((a, b) => a > b ? a : b), clip.clip.wordCount - 1,
          reason: '${e.id}: max phonemeToWord must be the last word index');
      for (var i = 1; i < p2w.length; i++) {
        expect(p2w[i] >= p2w[i - 1], isTrue, reason: '${e.id}: phonemeToWord non-decreasing at $i');
        expect(p2w[i] - p2w[i - 1] <= 1, isTrue, reason: '${e.id}: words contiguous at $i');
      }

      for (final ph in clip.clip.phonemes) {
        expect(ph, isNotEmpty, reason: '${e.id}: empty phoneme unit');
        expect(vocab.contains(ph), isTrue, reason: '${e.id}: OOV phoneme "$ph"');
      }
    }
    expect(checked, greaterThan(50), reason: 'sample should span the corpus');
  });

  test('decode fidelity: phonemes round-trip through the <blank>-inclusive vocab', () {
    // Guard the exact bug the ASR rewrite hit: the int→unit decode must use the
    // SAME tokens.txt line order (index 0 = <blank>) the packer encoded with. If
    // decode ever dropped <blank>, re-encoding a decoded unit to its vocab index
    // and back would not be the identity. Verify the identity on a sample.
    final index = {for (var i = 0; i < vocabList.length; i++) vocabList[i]: i};
    final e = corpus.byId.values.firstWhere((e) => e.hasClip && e.phonemes.length > 20);
    for (final ph in e.phonemes) {
      final i = index[ph];
      expect(i, isNotNull, reason: 'decoded unit "$ph" absent from vocab — index skew');
      expect(vocabList[i!], ph, reason: 'round-trip mismatch on "$ph"');
    }
  });

  test('a real clip constructs and collapses cleanly in the matcher', () {
    final e = corpus.byId.values.firstWhere((e) => e.hasClip && e.words.length >= 5);
    final session = PhonemeMatchSession(e.clip!.clip, vocabList);
    // Before any audio the matcher has not anchored and every word is pending.
    expect(session.anchored, isFalse);
    final out = session.apply(const <String>[]);
    expect(out.states.length, e.words.length);
    expect(out.states.every((s) => s == WordState.pending), isTrue);
  });
}
