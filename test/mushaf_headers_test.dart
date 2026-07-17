import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/data/quran_repository.dart';
import 'package:sanad/models/mushaf.dart';

/// Pins the mushaf surah-opener integrity across all 604 pages: every one of the
/// 114 surahs must have EXACTLY ONE name line (a surah-header or a combined
/// surah-opener), on its own start page, showing its name — and no page may
/// exceed the 15-line Madani grid. This guards the fix that restored 17 missing
/// openers and removed 13 duplicate name banners misplaced at page bottoms.
String _stripDiacritics(String s) {
  const marks = 'ًٌٍَُِّْٰـ';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (marks.contains(c)) continue;
    b.write(c == 'ٱ' || c == 'أ' || c == 'إ' ? 'ا' : c);
  }
  return b.toString().replaceAll('سورة', '').trim();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every surah has exactly one correct name opener, no page > 15 lines',
      () async {
    final repo = QuranRepository();
    final chapters = await repo.chapters();

    final nameLines = <int, List<(int page, int line, String text)>>{};
    for (var p = 1; p <= QuranRepository.totalPages; p++) {
      final page = await repo.page(p);
      expect(page.lines.length, lessThanOrEqualTo(15), reason: 'page $p > 15 lines');
      for (final l in page.lines) {
        if (l.type == LineType.surahHeader || l.type == LineType.opener) {
          (nameLines[l.surah!] ??= []).add((p, l.line, l.text));
        }
      }
    }

    for (final c in chapters) {
      final hits = nameLines[c.id] ?? const [];
      expect(hits.length, 1,
          reason: 'surah ${c.id} (${c.nameSimple}) has ${hits.length} name lines: $hits');
      final (page, _, text) = hits.first;
      expect(page, c.startPage,
          reason: 'surah ${c.id} name on page $page, expected start ${c.startPage}');
      expect(_stripDiacritics(text).contains(_stripDiacritics(c.nameArabic)), isTrue,
          reason: 'surah ${c.id} header "$text" does not contain "${c.nameArabic}"');
    }

    // exactly 114 name lines total (one per surah, no strays)
    final total = nameLines.values.fold<int>(0, (s, v) => s + v.length);
    expect(total, 114);
  });
}
