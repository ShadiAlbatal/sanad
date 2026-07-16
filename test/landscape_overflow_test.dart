import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/data/quran_repository.dart';
import 'package:tilawa_ai/models/mushaf.dart';
import 'package:tilawa_ai/widgets/mushaf_page_view.dart';

/// Host-side landscape fit check: short surahs (<14 lines) took the non-scrolling
/// `!full` branch, which stacked fixed-gap lines with no height constraint and
/// overflowed the short landscape viewport. Pumps every short page at a
/// landscape-shaped box and asserts no RenderFlex overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MushafPage> shortPages;

  setUpAll(() async {
    final loader = FontLoader('UthmanicHafs')
      ..addFont(rootBundle.load('assets/fonts/uthmanic_hafs.ttf'));
    await loader.load();

    final repo = QuranRepository();
    shortPages = [];
    for (var p = 1; p <= QuranRepository.totalPages; p++) {
      final page = await repo.page(p);
      if (page.lines.length < 14) shortPages.add(page);
    }
  });

  testWidgets('short surah pages fit a landscape viewport without overflow',
      (tester) async {
    expect(shortPages, isNotEmpty, reason: 'no short (<14 line) pages found');

    // Landscape phone: wide, short. This is the geometry that overflowed
    // (~800x360 logical is a typical landscape phone reader area).
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final failed = <String>[];
    for (final page in shortPages) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MushafPageView(page: page, basmalaWords: const []),
          ),
        ),
      );
      final ex = tester.takeException();
      if (ex != null) {
        failed.add('p${page.page} (${page.lines.length} lines): $ex');
      }
    }

    expect(failed, isEmpty,
        reason: 'landscape overflow on ${failed.length} page(s):\n'
            '${failed.take(20).join('\n')}');
  });
}
