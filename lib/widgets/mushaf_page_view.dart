import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/mushaf.dart';
import '../theme/app_theme.dart';
import '../theme/tajweed.dart';
import 'mushaf_layout.dart';

const _kFont = kMushafFont;
const _kBaseSize = kMushafBaseSize;

class MushafPageView extends StatelessWidget {
  final MushafPage page;
  final List<String> basmalaWords;
  final Set<String> highlighted;
  final bool hidden; // memorization mode: word text hidden until revealed
  final Set<String> revealed;
  final String? currentVerseKey; // "surah:ayah" of the ASR's current verse, for a coarser marker
  final Set<String> currentLocations; // all glyphs of the current corpus word (whole phrase highlights together)
  final Set<String> skipped; // words flagged red (jumped over during a 1-word skip)
  final void Function(MushafWord word)? onWordTap;
  final void Function(MushafWord word)? onWordLongPress;

  const MushafPageView({
    super.key,
    required this.page,
    required this.basmalaWords,
    this.highlighted = const {},
    this.hidden = false,
    this.revealed = const {},
    this.currentVerseKey,
    this.currentLocations = const {},
    this.skipped = const {},
    this.onWordTap,
    this.onWordLongPress,
  });

  static const _maxLine = 15;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.nightInk : AppColors.ink;
    final accent = AppColors.gold;
    final full = page.lines.length >= 14;
    final byLine = {for (final l in page.lines) l.line: l};

    // Fixed mushaf layout must not be affected by the device font-scale setting.
    return MediaQuery.withNoTextScaling(child: _body(dark, ink, accent, full, byLine));
  }

  Widget _body(bool dark, Color ink, Color accent, bool full,
      Map<int, MushafLine> byLine) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth - 4;
        final pageSize = pageFontSize(page.lines, w);
        if (!full) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final l in page.lines) ...[
                      _line(l, ink, accent, dark, w, pageSize, centered: true),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        final maxLine = page.lines.fold<int>(
          _maxLine,
          (m, l) => l.line > m ? l.line : m,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (var i = 1; i <= maxLine; i++)
                Expanded(
                  child: Center(
                    child: byLine[i] == null
                        ? const SizedBox.shrink()
                        : _line(byLine[i]!, ink, accent, dark, w, pageSize),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _line(MushafLine l, Color ink, Color accent, bool dark, double w,
      double size,
      {bool centered = false}) {
    switch (l.type) {
      case LineType.surahHeader:
        return _SurahHeader(text: l.text, accent: accent, ink: ink);
      case LineType.opener:
        return _SurahOpener(
            text: l.text, basmala: basmalaWords, accent: accent, ink: ink, dark: dark);
      case LineType.basmala:
        return _BasmalaLine(words: basmalaWords, ink: ink, dark: dark);
      case LineType.text:
        return _AyahLine(
          line: l,
          ink: ink,
          dark: dark,
          width: w,
          size: size,
          centered: centered,
          highlighted: highlighted,
          hidden: hidden,
          revealed: revealed,
          currentVerseKey: currentVerseKey,
          currentLocations: currentLocations,
          skipped: skipped,
          onWordTap: onWordTap,
          onWordLongPress: onWordLongPress,
        );
    }
  }
}

class _AyahLine extends StatelessWidget {
  final MushafLine line;
  final Color ink;
  final bool dark;
  final double width;
  final double size; // shared page font size (see pageFontSize)
  final bool centered;
  final Set<String> highlighted;
  final bool hidden;
  final Set<String> revealed;
  final String? currentVerseKey;
  final Set<String> currentLocations;
  final Set<String> skipped;
  final void Function(MushafWord word)? onWordTap;
  final void Function(MushafWord word)? onWordLongPress;

  const _AyahLine({
    required this.line,
    required this.ink,
    required this.dark,
    required this.width,
    required this.size,
    required this.centered,
    required this.highlighted,
    required this.hidden,
    required this.revealed,
    required this.currentVerseKey,
    required this.currentLocations,
    required this.skipped,
    required this.onWordTap,
    required this.onWordLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final n = line.words.length;
    // The page font size is already chosen so every line fits (see
    // pageFontSize); here we just measure this line's total unit width at that
    // size to decide justify-vs-centre and to compute exact gaps. Shared with
    // the page-render diagnostic so what it flags is what renders.
    final contentWidth = lineContentWidth(line, size);

    final accent = context.accent;
    final units = [for (final word in line.words) _wordUnit(word, size, accent)];
    final justify = !centered && n > 1 && contentWidth >= width * 0.60 && contentWidth <= width;

    if (justify) {
      // Manual justification: distribute the leftover space as explicit gaps
      // rather than Row(spaceBetween) inside a fixed-width box — the latter
      // throws a RenderFlex overflow if the measured content is even a
      // fraction of a pixel wider than the box (the ~1.9px overflow seen on
      // dense pages). Here gap >= 0 is guaranteed since contentWidth <= width.
      final gap = ((width - contentWidth) / (n - 1)).clamp(0.0, double.infinity);
      final spaced = <Widget>[];
      for (var i = 0; i < units.length; i++) {
        spaced.add(units[i]);
        if (i != units.length - 1) spaced.add(SizedBox(width: gap));
      }
      // FittedBox scaleDown is the backstop: the gaps fill the line to ~width,
      // and if the rendered content drifts a fraction past the box (per-glyph
      // rounding, tajweed-split spans), it scales to fit instead of throwing a
      // RenderFlex overflow (the hazard stripes seen on dense pages).
      return SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            textDirection: TextDirection.rtl,
            mainAxisSize: MainAxisSize.min,
            children: spaced,
          ),
        ),
      );
    }
    // Short / final lines: natural spacing, centred (matches the printed page).
    // FittedBox scaleDown is a final backstop against any residual overflow.
    final gap = size * 0.22;
    final spaced = <Widget>[];
    for (var i = 0; i < units.length; i++) {
      spaced.add(units[i]);
      if (i != units.length - 1) spaced.add(SizedBox(width: gap));
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisSize: MainAxisSize.min,
        children: spaced,
      ),
    );
  }

  Widget _wordUnit(MushafWord word, double size, Color accent) {
    final isEnd = mushafHasAyahNumber(word.uthmani);
    final isCurrent = currentLocations.contains(word.location);
    final concealed = hidden && !revealed.contains(word.location);
    final isSkipped = skipped.contains(word.location);

    final Widget core = hidden
        ? _hiddenWord(word, size, concealed: concealed, isSkipped: isSkipped)
        : _revealWord(word, size, isCurrent: isCurrent, accent: accent);

    // Ayah-number badge (verse separator) is always shown — in hidden mode it's
    // the only thing on the page besides the words the reciter has revealed.
    final unit = isEnd
        ? Row(
            textDirection: TextDirection.rtl,
            mainAxisSize: MainAxisSize.min,
            children: [
              core,
              const SizedBox(width: kBadgeGap),
              _AyahBadge(number: word.ayah, size: size, ink: ink),
            ],
          )
        : core;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onWordTap == null ? null : () => onWordTap!(word),
      onLongPress:
          onWordLongPress == null ? null : () => onWordLongPress!(word),
      child: unit,
    );
  }

  // Hidden (memorization) mode: NO boxes, NO washes, NO underline — just reveal
  // the word. Unread words stay invisible (blank, but hold their footprint so
  // the layout doesn't shift when revealed). A word the reciter jumped over
  // (skipped) is revealed in RED instead of staying hidden, so a genuine miss is
  // visible rather than looking like an un-recited word.
  Widget _hiddenWord(MushafWord word, double size, {required bool concealed, required bool isSkipped}) {
    if (concealed) {
      final ww = (word.measuredBaseWidth ?? measureMushaf(word.plain, _kBaseSize)) / _kBaseSize * size;
      return SizedBox(width: ww, height: size);
    }
    final red = AppColors.tajweedMajor;
    return Text.rich(
      TextSpan(
        children: [
          for (final s in word.spans)
            TextSpan(
              text: s.text,
              style: TextStyle(color: isSkipped ? red : (Tajweed.colorFor(s.rule, dark) ?? ink)),
            ),
        ],
        style: TextStyle(fontFamily: _kFont, fontSize: size, height: 1.0),
      ),
      textDirection: TextDirection.rtl,
    );
  }

  // Reveal (normal) mode: the ASR current-word marker (wash + emerald outline),
  // a fainter gold wash over the whole current verse, and skipped-word feedback.
  Widget _revealWord(MushafWord word, double size,
      {required bool isCurrent, required Color accent}) {
    final on = highlighted.contains(word.location);
    final onVerse = currentVerseKey != null && '${word.surah}:${word.ayah}' == currentVerseKey;
    final isSkipped = skipped.contains(word.location);

    final wordText = Text.rich(
      TextSpan(
        children: [
          for (final s in word.spans)
            TextSpan(
              text: s.text,
              style: TextStyle(color: Tajweed.colorFor(s.rule, dark) ?? ink),
            ),
        ],
        style: TextStyle(fontFamily: _kFont, fontSize: size, height: 1.0),
      ),
      textDirection: TextDirection.rtl,
    );

    final Color? bg = isCurrent
        ? (dark ? Colors.white : accent).withValues(alpha: dark ? 0.28 : 0.20)
        : on
            ? (dark ? Colors.white : accent).withValues(alpha: dark ? 0.16 : 0.10)
            : null;
    // Marker outline on the current word; else a red box for a skip.
    // (The current word can't also be skipped.)
    final Border? border = isCurrent
        ? Border.all(color: accent.withValues(alpha: 0.85), width: 1.4)
        : isSkipped
            ? Border.all(color: AppColors.tajweedMajor.withValues(alpha: 0.85), width: 1.4)
            : null;

    final highlightedWord = Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: border),
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: wordText,
    );

    // Verse-level marker: a faint gold wash over every word of the current
    // ayah. No extra padding — it must not change the word's footprint.
    return onVerse
        ? Container(
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: dark ? 0.14 : 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: highlightedWord,
          )
        : highlightedWord;
  }
}

class _AyahBadge extends StatelessWidget {
  final int number;
  final double size;
  final Color ink;
  const _AyahBadge({required this.number, required this.size, required this.ink});

  @override
  Widget build(BuildContext context) {
    // The ayah number is its own separator — no drawn shape wrapped around it.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size * 0.08),
      child: Text(
        toArabicDigits(number),
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: size * 0.62,
          color: AppColors.gold,
          height: 1.0,
        ),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  final Color color;
  _StarPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rO = size.width / 2;
    final rI = rO * 0.62;
    final path = Path();
    const points = 8;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? rO : rI;
      final a = (i * 3.14159265 / points) - 3.14159265 / 2;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}

class _BasmalaLine extends StatelessWidget {
  final List<String> words;
  final Color ink;
  final bool dark;
  const _BasmalaLine({required this.words, required this.ink, required this.dark});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < words.length; i++) ...[
              for (final s in Tajweed.parse(words[i]))
                TextSpan(
                  text: s.text,
                  style: TextStyle(color: Tajweed.colorFor(s.rule, dark) ?? ink),
                ),
              if (i != words.length - 1) const TextSpan(text: ' '),
            ],
          ],
          style: const TextStyle(fontFamily: _kFont, fontSize: 26, height: 1.0),
        ),
        textDirection: TextDirection.rtl,
      ),
    );
  }
}

class _SurahHeader extends StatelessWidget {
  final String text;
  final Color accent;
  final Color ink;
  const _SurahHeader({required this.text, required this.accent, required this.ink});

  @override
  Widget build(BuildContext context) {
    // Clean centered band: the surah name flanked by small star medallions and
    // hairline rules that fade out toward the page edges — no heavy frame.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          Expanded(child: _rule(fadeLeft: true)),
          const SizedBox(width: 12),
          _medallion(),
          const SizedBox(width: 14),
          Text(text,
              style: TextStyle(fontFamily: _kFont, fontSize: 24, color: ink)),
          const SizedBox(width: 14),
          _medallion(),
          const SizedBox(width: 12),
          Expanded(child: _rule(fadeLeft: false)),
        ],
      ),
    );
  }

  Widget _rule({required bool fadeLeft}) {
    final solid = accent.withValues(alpha: 0.5);
    final clear = accent.withValues(alpha: 0.0);
    return Container(
      height: 1.2,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: fadeLeft ? [clear, solid] : [solid, clear]),
      ),
    );
  }

  Widget _medallion() => SizedBox(
        width: 16,
        height: 16,
        child: CustomPaint(painter: _StarPainter(accent.withValues(alpha: 0.8))),
      );
}

/// Combined surah opener (name + basmala on one line-slot) for the surahs the
/// KFGQPC layout packs into a single top line. Scaled to fit the one row.
class _SurahOpener extends StatelessWidget {
  final String text;
  final List<String> basmala;
  final Color accent;
  final Color ink;
  final bool dark;
  const _SurahOpener(
      {required this.text,
      required this.basmala,
      required this.accent,
      required this.ink,
      required this.dark});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _medallion(accent),
              const SizedBox(width: 10),
              Text(text,
                  style: TextStyle(fontFamily: _kFont, fontSize: 20, color: ink)),
              const SizedBox(width: 10),
              _medallion(accent),
            ],
          ),
          const SizedBox(height: 1),
          _BasmalaLine(words: basmala, ink: ink, dark: dark),
        ],
      ),
    );
  }

  Widget _medallion(Color accent) => SizedBox(
        width: 13,
        height: 13,
        child: CustomPaint(painter: _StarPainter(accent.withValues(alpha: 0.8))),
      );
}
