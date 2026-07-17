import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/search/text_search.dart';

/// The shared typed-search index (BM25 over normalized Arabic words): a known
/// query retrieves the right doc top-ranked, the matched-word positions/terms are
/// correct (so the UI can highlight), normalization folds diacritics/alef/hamza,
/// and full-fragment queries rank the doc sharing the most distinctive words.
void main() {
  // Distinctive matns so ranking is unambiguous; diacritics included so the test
  // also proves query↔corpus normalization is symmetric.
  const docs = [
    TextSearchDoc('a', 'اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ وَالصَّلَاةِ الْقَائِمَةِ'),
    TextSearchDoc('b', 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ سُبْحَانَ اللَّهِ الْعَظِيمِ'),
    TextSearchDoc('c', 'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ خَلَقْتَنِي'),
  ];

  test('a distinctive query retrieves its doc top-ranked', () {
    final search = TextSearch(docs);
    final hits = search.search('الدعوة التامة القائمة');
    expect(hits, isNotEmpty);
    expect(hits.first.id, 'a');
  });

  test('another distinctive query lands on its own doc', () {
    final search = TextSearch(docs);
    expect(search.search('سبحان الله العظيم').first.id, 'b');
    expect(search.search('خلقتني ربي').first.id, 'c');
  });

  test('matched words + positions are exposed for highlighting', () {
    final search = TextSearch(docs);
    final hit = search.search('الدعوة القائمة').firstWhere((h) => h.id == 'a');
    // Both query terms (normalized the same way the index normalizes) are present.
    expect(hit.matchedWords, searchWords('الدعوة القائمة').toSet());
    // Doc a normalized words: [اللهم, رب, هذه, الدعوه, التامه, والصلاه, القايمه]
    // → the 4th and 7th words match. Positions index the normalized word list.
    expect(hit.matchedWordPositions, [3, 6]);
  });

  test('normalization is symmetric: undiacriticized query still matches', () {
    final search = TextSearch(docs);
    // Query with no harakat and a bare alef must still hit the diacritized doc.
    expect(search.search('الدعوه التامه').first.id, 'a');
  });

  test('full fragment beats a single shared common word', () {
    // Two docs share a common word; the fuller fragment must pick the right one.
    const corpus = [
      TextSearchDoc('x', 'الحمد لله رب العالمين الرحمن الرحيم'),
      TextSearchDoc('y', 'الحمد لله الذي أطعمنا وسقانا وكفانا وآوانا'),
    ];
    final search = TextSearch(corpus);
    expect(search.search('الذي اطعمنا وسقانا').first.id, 'y');
    expect(search.search('رب العالمين الرحمن').first.id, 'x');
  });

  test('empty / unknown query yields no hits (caller falls back to browse)', () {
    final search = TextSearch(docs);
    expect(search.search(''), isEmpty);
    expect(search.search('   '), isEmpty);
    expect(search.search('zzz qqq'), isEmpty); // no indexed terms
  });
}
