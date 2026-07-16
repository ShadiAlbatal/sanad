import '../data/quran_repository.dart';
import '../models/mushaf.dart';
import '../util/log.dart';
import '../widgets/mushaf_layout.dart';

/// Sweep every mushaf page at the given available text [width] and log the ones
/// whose layout would overflow (pixel issues) or leave ragged/misaligned lines.
/// Read-only — it uses the exact geometry the renderer uses ([scanPage]), so a
/// page flagged here is a page that mis-renders on screen. Triggered from the
/// Debug Log screen; results land in the log.
Future<void> runPageRenderScan(QuranRepository repo, double width) async {
  Log.d('render',
      '=== PAGE RENDER SCAN width=${width.toStringAsFixed(1)}px over ${QuranRepository.totalPages} pages ===');
  var overflowPages = 0;
  var raggedPages = 0;
  var worstPx = 0.0;
  var worstPage = 0;
  var smallestFont = kMushafBaseSize;
  var smallestFontPage = 0;

  for (var p = 1; p <= QuranRepository.totalPages; p++) {
    final MushafPage page;
    try {
      page = await repo.page(p);
    } catch (e) {
      Log.e('render', 'page $p load failed: $e');
      continue;
    }
    final scan = scanPage(page, width);
    if (scan.fontSize < smallestFont) {
      smallestFont = scan.fontSize;
      smallestFontPage = p;
    }
    if (scan.hasOverflow) {
      overflowPages++;
      if (scan.maxOverflow > worstPx) {
        worstPx = scan.maxOverflow;
        worstPage = p;
      }
    }
    if (scan.hasRagged) raggedPages++;
    if (!scan.clean) {
      final detail = scan.issues
          .map((i) => i.overflowPx > 0.5
              ? 'L${i.line}:+${i.overflowPx.toStringAsFixed(1)}px'
              : 'L${i.line}:ragged(${(i.fillRatio * 100).toStringAsFixed(0)}%)')
          .join(' ');
      Log.d('render', 'page $p font=${scan.fontSize.toStringAsFixed(1)} $detail');
    }
    if (p % 100 == 0) {
      Log.d('render', '…scanned $p/${QuranRepository.totalPages}');
    }
  }

  Log.d('render',
      '=== SCAN done: overflow=$overflowPages page(s) (worst +${worstPx.toStringAsFixed(1)}px @p$worstPage) · '
      'ragged=$raggedPages page(s) · smallest font=${smallestFont.toStringAsFixed(1)}pt @p$smallestFontPage ===');
  await Log.flushFile();
}
