import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/data/quran_repository.dart';
import 'package:tilawa_ai/widgets/mushaf_layout.dart';

/// Host-side page-render scan: loads the real mushaf font and every page's
/// data, then flags any page whose layout would overflow or leave ragged lines
/// at a typical phone reading width. Not a pass/fail gate — it prints the list
/// so the problem pages can be found without a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scan all mushaf pages for overflow / ragged lines', () async {
    final loader = FontLoader('UthmanicHafs')
      ..addFont(rootBundle.load('assets/fonts/uthmanic_hafs.ttf'));
    await loader.load();

    final repo = QuranRepository();

    // Sweep a few widths bracketing common phones (screen width − 44 chrome).
    for (final width in const [340.0, 350.0, 372.0]) {
      final problems = <String>[];
      var worst = 0.0, worstPage = 0;
      var smallest = kMushafBaseSize, smallestPage = 0;
      for (var p = 1; p <= QuranRepository.totalPages; p++) {
        final page = await repo.page(p);
        final scan = scanPage(page, width);
        if (scan.fontSize < smallest) {
          smallest = scan.fontSize;
          smallestPage = p;
        }
        if (!scan.clean) {
          final detail = scan.issues
              .map((i) => i.overflowPx > 0.5
                  ? 'L${i.line}:+${i.overflowPx.toStringAsFixed(1)}px'
                  : 'L${i.line}:ragged${(i.fillRatio * 100).round()}%')
              .join(' ');
          problems.add('p$p f=${scan.fontSize.toStringAsFixed(1)} $detail');
          if (scan.maxOverflow > worst) {
            worst = scan.maxOverflow;
            worstPage = p;
          }
        }
      }
      // ignore: avoid_print
      print('\n===== width=$width : ${problems.length} problem page(s), '
          'worst +${worst.toStringAsFixed(1)}px @p$worstPage, '
          'smallest font ${smallest.toStringAsFixed(1)}pt @p$smallestPage =====');
      for (final s in problems.take(60)) {
        // ignore: avoid_print
        print(s);
      }
    }
  });
}
