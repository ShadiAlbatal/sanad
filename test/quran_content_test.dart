import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/data/quran_repository.dart';

/// Content-integrity gate for the actual Qur'an scripture: loads all 604
/// bundled mushaf pages and asserts every word's Uthmani text exactly matches
/// a canonical reference (assets/data/quran_content_reference.json, generated
/// by tool/gen_content_reference.py from the CURRENT bundled data, cross-
/// checked against the quran.com API word counts at generation time -- see
/// the 2026-07-16 surah-opener verification).
///
/// Before this test, the only content check was tool/verify_all.py: a manual,
/// network-dependent Python script outside `flutter test`. A future page-data
/// edit that corrupts a glyph or drops an āyah — the worst-case defect for a
/// Qur'an app — now fails this suite offline and deterministically instead of
/// silently shipping.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every word across all 604 pages matches the canonical reference text',
      () async {
    final raw = await rootBundle
        .loadString('assets/data/quran_content_reference.json');
    final reference = (json.decode(raw) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));

    final repo = QuranRepository();
    final mismatches = <String>[];
    final live = <String>{};

    for (var p = 1; p <= QuranRepository.totalPages; p++) {
      final page = await repo.page(p);
      for (final line in page.lines) {
        for (final word in line.words) {
          live.add(word.location);
          final expected = reference[word.location];
          if (expected == null) {
            mismatches.add('${word.location}: not in reference (new word?)');
          } else if (expected != word.uthmani) {
            mismatches.add(
                '${word.location}: expected "$expected", got "${word.uthmani}"');
          }
        }
      }
    }

    final missing = reference.keys.toSet().difference(live);
    if (missing.isNotEmpty) {
      mismatches.add('${missing.length} reference location(s) missing from '
          'the live pages, e.g. ${missing.take(5).join(", ")}');
    }

    expect(mismatches, isEmpty,
        reason: '${mismatches.length} content mismatch(es):\n'
            '${mismatches.take(20).join("\n")}'
            '${mismatches.length > 20 ? "\n… (${mismatches.length - 20} more)" : ""}');
    expect(reference.length, 77429);
  });
}
