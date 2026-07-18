import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/dua_corpus.dart';
import 'package:sanad/services/asr/dua_search.dart';
import 'package:sanad/services/asr/phoneme_corpus.dart' show loadDuaClip;

/// The packaged du'a corpus actually loads, decodes its int-encoded phonemes
/// back to the RIGHT units (the pack-time index must match Dart's blank-
/// inclusive loadPhonemeUnits), and the READER-side phoneme strings live ASR
/// emits retrieve their du'a top-1 & confident through the shared
/// [PhonemeFinder] — the end-to-end guarantee reader follow-along can identify a
/// du'a among the whole corpus.

/// FindDoc madd-collapses runs of identical units at construction, and the query
/// is collapsed the same way, so a fidelity check against the raw reader clip
/// must collapse it too (mirrors phoneme_finder's `_collapse`).
final _collapseRe = RegExp(r'(.)\1+');
List<String> _collapse(List<String> p) =>
    [for (final s in p) s.replaceAllMapped(_collapseRe, (m) => m[1]!)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('packaged du\'a corpus', () {
    test('loads and holds the whole corpus (existing 5 + Hisn)', () async {
      final corpus = await loadDuaCorpus();
      expect(corpus.docs.length, greaterThan(200),
          reason: 'comprehensive Hisn al-Muslim coverage');
      expect(corpus.byId.containsKey('dua-after-adhan'), isTrue,
          reason: 'existing du\'as preserved in the combined corpus');
      // Metadata is populated for browsing.
      final m = corpus.byId['dua-after-adhan']!;
      expect(m.title, isNotEmpty);
      expect(m.arabic, isNotEmpty);
    });

    // The corpus packs phonemes as ints; decode maps them back through the
    // blank-inclusive vocab. Pin that convention directly: a du'a's decoded
    // corpus phonemes must EQUAL the reader clip's own phoneme strings (both
    // madd-collapsed). An off-by-one vocab index shifts every unit and this
    // fails — the exact bug that silently emptied dua voice-search.
    for (final id in const ['dua-after-adhan', 'hisn-1', 'hisn-10', 'hisn-100']) {
      test('decode fidelity: $id corpus phonemes == its reader clip', () async {
        final corpus = await loadDuaCorpus();
        final reader = (await loadDuaClip(id)).clip.phonemes;
        final decoded = corpus.docs.firstWhere((d) => d.id == id).phonemes;
        expect(decoded, _collapse(reader),
            reason: 'decoded corpus units must match the reader clip strings');
      });
    }

    test('reader-side phoneme strings rank their du\'a top-1', () async {
      final corpus = await loadDuaCorpus();
      final search = DuaSearch(corpus);

      // Query with the phoneme STRINGS the reader/live-ASR path emits (read from
      // assets/asr/dua_phonemes/<id>.json), NOT the corpus's own self-decoded
      // span. This exercises the real int→unit decode of the doc side against
      // independent reference strings, so a vocab-index shift (garbage docs →
      // zero shared 3-grams → empty results) is caught here. Includes hisn-100,
      // which has a near-identical twin in Hisn (hisn-71) so it is not a
      // confident pick, but must still rank itself first.
      for (final id in const ['dua-after-adhan', 'hisn-100', 'hisn-1', 'hisn-10']) {
        final query = (await loadDuaClip(id)).clip.phonemes;
        final result = search.find(query);
        expect(result.candidates.first.id, id,
            reason: '$id reader phonemes must rank it first');
      }
    });

    test('a distinctive du\'a\'s reader span is a confident pick', () async {
      final corpus = await loadDuaCorpus();
      final search = DuaSearch(corpus);

      // Distinctive du'as (no near-duplicate in the corpus) must clear the
      // floor + margin bar on their own reader span — the finder can name them,
      // not just rank them. Proves the fixed decode is not merely top-1 by luck.
      for (final id in const ['dua-after-adhan', 'hisn-1', 'hisn-30']) {
        final query = (await loadDuaClip(id)).clip.phonemes;
        final result = search.find(query);
        expect(result.pick?.id, id,
            reason: '$id full reader span must be a confident pick');
      }
    });
  });
}
