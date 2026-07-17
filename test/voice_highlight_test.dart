import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/phoneme_finder.dart';
import 'package:sanad/services/search/text_search.dart';

/// Piece 3b: the voice finder maps a recited span back to the WORDS it matched on
/// a candidate, so a voice candidate row highlights like a typed hit.
/// [PhonemeFinder.matchedWordIndices] does the phoneme→word mapping;
/// [matchedDisplayWords] normalizes those words into the `Set<String>` the
/// HighlightedArabic widget consumes.
void main() {
  // A 4-word doc: two phonemes per word, each phoneme a distinct token so
  // similarity() only matches identical tokens (no spurious cross-matches).
  final finder = PhonemeFinder([
    FindDoc('doc',
        ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
        words: const ['w0', 'w1', 'w2', 'w3'],
        phonemeToWord: const [0, 0, 1, 1, 2, 2, 3, 3]),
    FindDoc('nomap', ['a', 'b', 'c', 'd']), // find-only, no word map
  ]);

  group('matchedWordIndices', () {
    test('an interior span resolves to exactly its words', () {
      // The phonemes of words 1 and 2.
      expect(finder.matchedWordIndices('doc', const ['c', 'd', 'e', 'f']), {1, 2});
    });

    test('the full phoneme sequence resolves to every word', () {
      expect(finder.matchedWordIndices('doc', const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']),
          {0, 1, 2, 3});
    });

    test('a leading span resolves to the leading words only', () {
      expect(finder.matchedWordIndices('doc', const ['a', 'b', 'c']), {0, 1});
    });

    test('a too-short query (< 3 phonemes) yields no highlight', () {
      expect(finder.matchedWordIndices('doc', const ['c', 'd']), isEmpty);
      expect(finder.matchedWordIndices('doc', const []), isEmpty);
    });

    test('an unknown id yields no highlight', () {
      expect(finder.matchedWordIndices('missing', const ['a', 'b', 'c']), isEmpty);
    });

    test('a doc with no word map yields no highlight (never a crash)', () {
      expect(finder.matchedWordIndices('nomap', const ['a', 'b', 'c']), isEmpty);
    });

    test('a sub-span far from index 0 in a long doc resolves to exactly its words', () {
      // A long matn (300 words × 2 unique phonemes = 600 phonemes) so the query
      // matches a span deep inside — proves the windowed align returns the SAME
      // words a full-matn align would, not just that it is cheaper. Unique tokens
      // mean similarity() only matches identical phonemes (no spurious hits).
      const nWords = 300;
      // Each phoneme is a UNIQUE single code point: two distinct single chars have
      // similarity 0 (< threshold) and a char matches only itself (similarity 1),
      // so nwAlign/the localizer only ever match a query phoneme to its own ref
      // phoneme — no fuzzy cross-matches to muddy the "windowed == full" proof.
      String tok(int p) => String.fromCharCode(0x100 + p);
      final phonemes = <String>[];
      final phonemeToWord = <int>[];
      final words = <String>[];
      for (var w = 0; w < nWords; w++) {
        words.add('w$w');
        phonemes.add(tok(2 * w));
        phonemes.add(tok(2 * w + 1));
        phonemeToWord.add(w);
        phonemeToWord.add(w);
      }
      final longFinder = PhonemeFinder([
        FindDoc('long', phonemes, words: words, phonemeToWord: phonemeToWord),
      ]);
      // Recite words 200 and 201 — their phonemes sit at ref index 400..403, far
      // from 0. The window is built around the localized position; the result must
      // equal the two recited words (identical to what a full-matn align returns).
      expect(
        longFinder.matchedWordIndices(
            'long', [tok(400), tok(401), tok(402), tok(403)]),
        {200, 201},
      );
    });
  });

  group('matchedDisplayWords (normalized Set<String> for HighlightedArabic)', () {
    // Arabic display words so the normalization path (searchWords) is exercised.
    final f = PhonemeFinder([
      FindDoc('dua',
          ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
          words: const ['رَبِّ', 'ٱغْفِرْ', 'لِي', 'وَٱرْحَمْ'],
          phonemeToWord: const [0, 0, 1, 1, 2, 3, 3]),
    ]);

    test('matched word indices become the normalized display words', () {
      final matched = matchedDisplayWords(f, 'dua', const ['a', 'b', 'c', 'd']);
      final expected = {...searchWords('رَبِّ'), ...searchWords('ٱغْفِرْ')};
      expect(matched, expected);
      // Words 2 and 3 were not recited, so they are not highlighted.
      expect(matched.intersection({...searchWords('لِي'), ...searchWords('وَٱرْحَمْ')}), isEmpty);
    });

    test('a short query yields an empty set (plain text)', () {
      expect(matchedDisplayWords(f, 'dua', const ['a']), isEmpty);
    });
  });
}
