import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/quran_corpus.dart';
import 'package:sanad/services/asr/quran_search.dart';

/// The GLOBAL Quran search engine (piece 4a): the whole Quran splits into ~6,236
/// verses on the shared [PhonemeFinder] + a BM25 text index, so a recited or typed
/// verse can be located ANYWHERE — not just in the current surah. Mirrors
/// dua_search_test / hadith_search_test.
///
///  1. The corpus builds from the already-bundled per-surah phoneme files, holds
///     all 114 surahs' verses, and carries per-verse navigation (surah/ayah/page).
///  2. A verse's OWN phoneme span retrieves that verse top-1 & confident among all
///     6,236 — the end-to-end guarantee the finder can identify a recited verse
///     globally.
///  3. A distinctive verse phrase retrieves the right verse through the BM25 index.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('global Quran verse corpus', () {
    test('builds all 114 surahs into ~6,236 verses with navigation metadata', () async {
      final corpus = await loadQuranCorpus();
      expect(corpus.verses.length, 6236, reason: 'the whole Quran, verse-per-doc');
      expect(corpus.docs.length, corpus.verses.length);

      // Known verses are present and navigable.
      for (final id in const ['1:1', '2:255', '114:6']) {
        final v = corpus.byId[id];
        expect(v, isNotNull, reason: '$id must be indexed');
        expect(v!.text, isNotEmpty);
        expect(v.page, greaterThan(0), reason: '$id must carry a mushaf page');
      }
      // Ayat al-Kursi sits on its real mushaf page (42), verses stay in order.
      expect(corpus.byId['2:255']!.page, 42);
      expect(corpus.verses.first.id, '1:1');
      expect(corpus.verses.last.id, '114:6');
    });
  });

  group('QuranSearch retrieval', () {
    test("a verse's own phoneme span retrieves it top-1 & confident globally", () async {
      final corpus = await loadQuranCorpus();
      final search = QuranSearch(corpus);
      final byId = {for (final d in corpus.docs) d.id: d.phonemes};

      // Distinctive, long verses (unique across the Quran, well over the localizer's
      // min length) must both rank #1 and clear the floor+margin bar on their own
      // span — proving retrieval among all 6,236 verses, not luck.
      for (final id in const ['2:255', '2:282', '24:35', '3:8']) {
        final result = search.find(byId[id]!);
        expect(result.candidates.first.id, id, reason: '$id must rank itself first');
        expect(result.pick?.id, id, reason: '$id span must be a confident pick');
        expect(result.pick?.page, greaterThan(0), reason: 'pick carries a page to jump to');
      }
    });

    test('a distinctive verse phrase retrieves the right verse via BM25', () async {
      final corpus = await loadQuranCorpus();
      final search = QuranSearch(corpus);

      // Ayat al-Kursi's own words are distinctive enough that BM25 ranks it first.
      final ayatAlKursi = corpus.byId['2:255']!;
      final hits = search.searchText(ayatAlKursi.text);
      expect(hits.first.id, '2:255', reason: 'the verse text must retrieve the verse');
      expect(hits.first.matchedWordPositions, isNotEmpty, reason: 'positions for highlight');

      // A short distinctive fragment also lands the intended verse.
      final iqra = search.searchText('اقرأ باسم ربك الذي خلق');
      expect(iqra.first.id, '96:1');
    });
  });
}
