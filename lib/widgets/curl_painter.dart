import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Paints a page-turn where [top] (the leaf being turned) wraps around a
/// vertical cylinder anchored at a moving fold line, revealing [bottom].
///
/// [progress] 0 → flat, 1 → fully turned. When [fromRight] is true the leaf
/// peels from the right edge toward the left; otherwise it peels from the left
/// edge toward the right (next page in a RTL mushaf). Both directions draw the
/// page bitmaps in their natural orientation — never mirrored.
class CurlPainter extends CustomPainter {
  final ui.Image top;
  final ui.Image bottom;
  final double progress;
  final bool fromRight;
  final Color back;

  CurlPainter({
    required this.top,
    required this.bottom,
    required this.progress,
    required this.fromRight,
    required this.back,
  });

  static const _step = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final p = progress.clamp(0.0, 1.0);
    final radius = math.max(w * 0.16, 14.0);
    final sx = top.width / w;

    // Revealed page underneath (natural orientation).
    canvas.drawImageRect(
      bottom,
      Rect.fromLTWH(0, 0, bottom.width.toDouble(), bottom.height.toDouble()),
      Rect.fromLTWH(0, 0, w, h),
      Paint(),
    );

    if (fromRight) {
      _peelRight(canvas, w, h, p, radius, sx);
    } else {
      _peelLeft(canvas, w, h, p, radius, sx);
    }
  }

  // Right edge lifts and curls to the left. Fold sweeps right → left.
  void _peelRight(Canvas c, double w, double h, double p, double r, double sx) {
    final imgH = top.height.toDouble();
    final foldX = w * (1 - p);

    _castShadow(c, foldX, w * 0.10, h, p, toRight: true);

    if (foldX > 0.5) {
      c.drawImageRect(top, Rect.fromLTWH(0, 0, foldX * sx, imgH),
          Rect.fromLTWH(0, 0, foldX, h), Paint());
    }

    double apexX = foldX;
    for (double ox = foldX; ox < w; ox += _step) {
      final angle = (ox - foldX) / r;
      if (angle > math.pi) break;
      final cos = math.cos(angle);
      final dstX = foldX - r * math.sin(angle);
      if (angle <= math.pi / 2) apexX = dstX;
      final dstW = _step * cos.abs() + 0.6;
      _strip(c, dstX - dstW, dstW, h, cos);
    }
    _sheenAndEdge(c, apexX, r, h);
  }

  // Left edge lifts and curls to the right. Fold sweeps left → right.
  void _peelLeft(Canvas c, double w, double h, double p, double r, double sx) {
    final imgH = top.height.toDouble();
    final foldX = w * p;

    _castShadow(c, foldX, w * 0.10, h, p, toRight: false);

    if (foldX < w - 0.5) {
      c.drawImageRect(top, Rect.fromLTWH(foldX * sx, 0, (w - foldX) * sx, imgH),
          Rect.fromLTWH(foldX, 0, w - foldX, h), Paint());
    }

    double apexX = foldX;
    for (double ox = foldX; ox >= _step; ox -= _step) {
      final angle = (foldX - ox) / r;
      if (angle > math.pi) break;
      final cos = math.cos(angle);
      final dstX = foldX + r * math.sin(angle);
      if (angle <= math.pi / 2) apexX = dstX;
      final dstW = _step * cos.abs() + 0.6;
      _strip(c, dstX, dstW, h, cos);
    }
    _sheenAndEdge(c, apexX, r, h);
  }

  // The lifting leaf shows its reverse (beige) side — a real page turn never
  // shows the front text reversed. Shaded by the cylinder angle for a 3D curl.
  void _strip(Canvas c, double dstX, double dstW, double h, double cos) {
    final shade = (0.34 * (1 - cos.abs())).clamp(0.0, 0.5);
    c.drawRect(
      Rect.fromLTWH(dstX, 0, dstW + 0.5, h),
      Paint()..color = Color.lerp(back, Colors.black, shade)!,
    );
  }

  // Soft contact shadow the hovering leaf casts onto the revealed page ahead
  // of the fold. Wider + gentler than a hard edge reads as a real page lifting
  // a few millimetres off the one beneath it. Deepens as the turn progresses.
  void _castShadow(
      Canvas c, double foldX, double castW, double h, double p,
      {required bool toRight}) {
    final w2 = math.min(34.0, math.max(castW, 18.0));
    final from = Offset(foldX, 0);
    final to = Offset(foldX + (toRight ? w2 : -w2), 0);
    final rect = toRight
        ? Rect.fromLTWH(foldX, 0, w2, h)
        : Rect.fromLTWH(foldX - w2, 0, w2, h);
    final a = 0.18 * p;
    c.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(from, to, [
          Colors.black.withValues(alpha: a),
          Colors.black.withValues(alpha: a * 0.35),
          Colors.transparent,
        ], [
          0.0,
          0.45,
          1.0,
        ]),
    );
  }

  void _sheenAndEdge(Canvas c, double apexX, double r, double h) {
    // Broad soft sheen across the crown of the curl (the paper catching light),
    // plus a tighter bright glint right at the apex for a glossy fold.
    final sheenW = math.max(r * 0.9, 16.0);
    c.drawRect(
      Rect.fromLTWH(apexX - sheenW / 2, 0, sheenW, h),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(apexX - sheenW / 2, 0),
          Offset(apexX + sheenW / 2, 0),
          [Colors.transparent, Colors.white.withValues(alpha: 0.30), Colors.transparent],
          [0.0, 0.5, 1.0],
        ),
    );
    final glintW = math.max(r * 0.28, 5.0);
    c.drawRect(
      Rect.fromLTWH(apexX - glintW / 2, 0, glintW, h),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(apexX - glintW / 2, 0),
          Offset(apexX + glintW / 2, 0),
          [Colors.transparent, Colors.white.withValues(alpha: 0.22), Colors.transparent],
          [0.0, 0.5, 1.0],
        ),
    );
    // The hard fold edge, with a hairline highlight on its lit side.
    c.drawLine(
      Offset(apexX, 0),
      Offset(apexX, h),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..strokeWidth = 1.6,
    );
    c.drawLine(
      Offset(apexX + 1.2, 0),
      Offset(apexX + 1.2, h),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(CurlPainter old) =>
      old.progress != progress ||
      old.top != top ||
      old.bottom != bottom ||
      old.fromRight != fromRight;
}
