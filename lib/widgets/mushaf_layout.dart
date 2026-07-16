import 'package:flutter/widgets.dart';
import '../models/mushaf.dart';

/// Shared mushaf line-geometry: the single source of truth for how a page's
/// font size is chosen and how wide each line's content is. Used both by the
/// renderer ([MushafPageView]) and by the page-render diagnostic, so the
/// diagnostic reports the exact overflow the renderer would draw.

const kMushafFont = 'UthmanicHafs';
const kMushafBaseSize = 29.0;

// Per-line layout constants (must agree between sizing and layout or lines
// overflow their width).
const double kPad = 2.0; // horizontal padding per word unit (both sides)
const double kBadgeGap = 3.0; // gap between a word and its trailing ayah badge
const double kMinGap = 2.0; // minimum inter-word gap reserved when sizing
const double kFitSafety = 6.0; // slack so sub-pixel rounding never overflows

final _arabicDigit = RegExp(r'[٠-٩]');

String toArabicDigits(int n) {
  const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return n.toString().split('').map((c) => d[int.parse(c)]).join();
}

/// A word carrying an Arabic-Indic digit is an ayah end-marker (verse badge).
bool mushafHasAyahNumber(String uthmani) => _arabicDigit.hasMatch(uthmani);

double measureMushaf(String text, double size) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontFamily: kMushafFont, height: 1.0).copyWith(fontSize: size),
    ),
    textDirection: TextDirection.rtl,
  )..layout();
  return tp.width;
}

/// The base-size text width of a line's words (cached on each word) plus its
/// ayah-badge numerals. Returns (textAtBase, badgeNumAtBase, badgeCount).
(double, double, int) _lineBaseWidths(MushafLine line) {
  var textAtBase = 0.0;
  var badgeNumAtBase = 0.0;
  var badges = 0;
  for (final word in line.words) {
    textAtBase += word.measuredBaseWidth ??= measureMushaf(word.plain, kMushafBaseSize);
    if (_arabicDigit.hasMatch(word.uthmani)) {
      badges++;
      badgeNumAtBase += measureMushaf(toArabicDigits(word.ayah), kMushafBaseSize * 0.62);
    }
  }
  return (textAtBase, badgeNumAtBase, badges);
}

/// Largest font size at which [line] fits [width].
double fitSizeFor(MushafLine line, double width) {
  final n = line.words.length;
  if (n == 0) return kMushafBaseSize;
  final (textAtBase, badgeNumAtBase, badges) = _lineBaseWidths(line);
  final coeff = textAtBase / kMushafBaseSize + badgeNumAtBase / kMushafBaseSize + badges * 0.16;
  final fixed = kPad * n + kBadgeGap * badges + kMinGap * (n - 1) + kFitSafety;
  if (coeff <= 0) return kMushafBaseSize;
  final fit = (width - fixed) / coeff;
  return fit.clamp(12.0, kMushafBaseSize);
}

/// One font size for the whole page: the largest that lets every text line fit.
double pageFontSize(Iterable<MushafLine> lines, double width) {
  var size = kMushafBaseSize;
  for (final l in lines) {
    if (l.type != LineType.text) continue;
    final s = fitSizeFor(l, width);
    if (s < size) size = s;
  }
  return size;
}

/// Rendered width of a line's content at [size] (matches _AyahLine.build).
double lineContentWidth(MushafLine line, double size) {
  final n = line.words.length;
  if (n == 0) return 0;
  final (textAtBase, badgeNumAtBase, badges) = _lineBaseWidths(line);
  final scale = size / kMushafBaseSize;
  return (textAtBase + badgeNumAtBase) * scale + size * 0.16 * badges + kPad * n + kBadgeGap * badges;
}

/// A layout problem found on one line of a page.
class LineIssue {
  final int line;
  final double overflowPx; // >0 = content wider than the box (pixel/overflow)
  final double fillRatio; // content / available width
  final bool ragged; // very short non-final line (looks unaligned)
  final double fontSize;
  const LineIssue(this.line, this.overflowPx, this.fillRatio, this.ragged, this.fontSize);
}

/// Per-page layout report at a given available [width].
class PageScan {
  final int page;
  final double fontSize;
  final List<LineIssue> issues;
  const PageScan(this.page, this.fontSize, this.issues);

  double get maxOverflow =>
      issues.fold(0.0, (m, i) => i.overflowPx > m ? i.overflowPx : m);
  bool get hasOverflow => maxOverflow > 0.5;
  bool get hasRagged => issues.any((i) => i.ragged);
  bool get clean => issues.isEmpty;
}

/// Scan a page for overflow (pixel issues) and ragged lines (potential font
/// misalignment) at the given available text [width]. Pure/read-only — the
/// same measurements the renderer uses, so overflow here is overflow on screen.
PageScan scanPage(MushafPage page, double width) {
  final size = pageFontSize(page.lines, width);
  final issues = <LineIssue>[];
  // Short pages (< 14 lines) render every line centred (see MushafPageView),
  // so justify/ragged doesn't apply there — only overflow matters.
  final full = page.lines.length >= 14;
  final textLines = [for (final l in page.lines) if (l.type == LineType.text) l];
  final lastLine = textLines.isEmpty
      ? -1
      : textLines.map((l) => l.line).reduce((a, b) => a > b ? a : b);
  for (final l in textLines) {
    final n = l.words.length;
    final cw = lineContentWidth(l, size);
    final overflow = cw - width;
    final fill = width <= 0 ? 0.0 : cw / width;
    final justify = full && n > 1 && cw >= width * 0.60 && cw <= width;
    // Ragged = a mid-page line that neither justifies nor nearly fills the
    // width. Excludes centred short pages and each page's final line (a short
    // last ayah before a surah break is expected to be centred, not a bug).
    final ragged = full && !justify && n >= 5 && fill < 0.42 && l.line != lastLine;
    if (overflow > 0.5 || ragged) {
      issues.add(LineIssue(l.line, overflow, fill, ragged, size));
    }
  }
  return PageScan(page.page, size, issues);
}
