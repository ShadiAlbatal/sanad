import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../util/log.dart';
import 'curl_painter.dart';

class CurlController {
  _CurlPageViewState? _s;
  void _bind(_CurlPageViewState s) => _s = s;
  void _unbind(_CurlPageViewState s) {
    if (_s == s) _s = null;
  }

  int get page => _s?._current ?? 0;
  void jumpTo(int page) => _s?._jumpTo(page);
}

/// Single-page right-to-left mushaf pager. One page fills the screen; every
/// swipe turns exactly one page with a paper curl:
///  • forward (drag right → next page): the page peels from its LEFT edge and
///    the fold sweeps rightward, revealing the next page.
///  • back (drag left → previous page): peels from the RIGHT edge, fold sweeps
///    left.
/// Only the current page and its two neighbours are kept live.
class CurlPageView extends StatefulWidget {
  final int itemCount;
  final int initialPage;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onPageChanged;
  final CurlController? controller;

  const CurlPageView({
    super.key,
    required this.itemCount,
    required this.initialPage,
    required this.itemBuilder,
    this.onPageChanged,
    this.controller,
  });

  @override
  State<CurlPageView> createState() => _CurlPageViewState();
}

class _CurlPageViewState extends State<CurlPageView>
    with SingleTickerProviderStateMixin {
  final _curKey = GlobalKey();
  final _prevKey = GlobalKey();
  final _nextKey = GlobalKey();

  late int _current = widget.initialPage;

  ui.Image? _curImg, _prevImg, _nextImg;

  bool _dragging = false;
  double _progress = 0;
  bool _forward = true;
  int? _target;
  double _accum = 0;
  bool _decided = false;
  int _captureToken = 0;
  bool _neighboursReady = false; // build neighbours only after the settle frame
  bool _bridge = false; // paint the settled bitmap over the swap-in frame

  // NOT `late` — a lazy controller whose first access is dispose()'s _anim.dispose()
  // (reader opened and popped without ever animating a curl) builds a Ticker via an
  // inherited-widget lookup on an already-deactivated element → "deactivated widget's
  // ancestor" crash. Build it eagerly in initState while the element is active.
  late final AnimationController _anim;
  double _animFrom = 0, _animTo = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_onAnim);
    widget.controller?._bind(this);
    _scheduleCapture();
  }

  void _scheduleCapture() {
    final token = ++_captureToken; // one token per settle; retries share it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _captureToken) return;
      if (!_neighboursReady) setState(() => _neighboursReady = true);
      _captureAll(token);
    });
    Future.delayed(const Duration(milliseconds: 500),
        () => _captureAll(token));
  }

  @override
  void dispose() {
    widget.controller?._unbind(this);
    _anim.dispose();
    _curImg?.dispose();
    _prevImg?.dispose();
    _nextImg?.dispose();
    super.dispose();
  }

  Future<ui.Image?> _capture(GlobalKey key) async {
    final obj = key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    final pr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    try {
      return await obj.toImage(pixelRatio: pr.toDouble());
    } catch (e) {
      Log.e('capture', e);
      return null;
    }
  }

  Future<void> _captureAll(int token) async {
    if (!mounted || token != _captureToken || _dragging) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || token != _captureToken || _dragging) return;
    final cur = await _capture(_curKey);
    final prev = _current > 0 ? await _capture(_prevKey) : null;
    final next =
        _current < widget.itemCount - 1 ? await _capture(_nextKey) : null;
    if (!mounted || token != _captureToken || _dragging) {
      cur?.dispose();
      prev?.dispose();
      next?.dispose();
      return;
    }
    _curImg?.dispose();
    _prevImg?.dispose();
    _nextImg?.dispose();
    _curImg = cur;
    _prevImg = prev;
    _nextImg = next;
    Log.d('capture',
        'page ${_current + 1}: cur=${_dim(cur)} prev=${_dim(prev)} next=${_dim(next)}');
  }

  String _dim(ui.Image? i) => i == null ? 'null' : '${i.width}x${i.height}';

  void _settleTo(int page, {ui.Image? knownImg}) {
    if (_curImg != null && !identical(_curImg, knownImg)) _curImg!.dispose();
    if (_prevImg != null && !identical(_prevImg, knownImg)) _prevImg!.dispose();
    if (_nextImg != null && !identical(_nextImg, knownImg)) _nextImg!.dispose();
    _curImg = knownImg;
    _prevImg = null;
    _nextImg = null;
    _current = page;
    _neighboursReady = false;
    Log.d('page', 'settle -> ${page + 1} (adopted img=${knownImg != null})');
    widget.onPageChanged?.call(page);
    setState(() {});
    _scheduleCapture();
  }

  void _jumpTo(int page) {
    if (page == _current || page < 0 || page >= widget.itemCount) return;
    _anim.stop();
    _dragging = false;
    _progress = 0;
    _target = null;
    _settleTo(page);
  }

  void _onDragStart(DragStartDetails d) {
    _accum = 0;
    _decided = false;
    _target = null;
    _bridge = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _accum += d.delta.dx;
    final w = context.size?.width ?? 1;
    if (!_decided) {
      if (_accum.abs() < 8) return;
      _decided = true;
      final forward = _accum > 0; // RTL: drag right advances to the next page
      final target = forward ? _current + 1 : _current - 1;
      if (target < 0 || target >= widget.itemCount) {
        _target = null;
        return;
      }
      _forward = forward;
      _target = target;
      final top = _curImg;
      final bot = forward ? _nextImg : _prevImg;
      final curl = top != null && bot != null;
      Log.d('turn',
          'drag ${_current + 1}->${target + 1} ${forward ? "next" : "prev"} curl=$curl imgs(top=${top != null},bot=${bot != null})');
      if (curl) {
        setState(() {
          _dragging = true;
          _progress = (_accum.abs() / w).clamp(0.0, 1.0);
        });
      }
    } else if (_dragging) {
      setState(() => _progress = (_accum.abs() / w).clamp(0.0, 1.0));
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final w = context.size?.width ?? 1;
    final target = _target;
    if (target == null) {
      _resetDrag();
      return;
    }
    final v = d.velocity.pixelsPerSecond.dx;
    final flung = _forward ? v > 320 : v < -320; // RTL: rightward fling = next

    if (_dragging) {
      final commit = _progress > 0.5 || flung;
      _animFrom = _progress;
      _animTo = commit ? 1.0 : 0.0;
      _anim.duration = Duration(
          milliseconds: (120 * (_animTo - _animFrom).abs() + 70).round());
      _anim.forward(from: 0);
    } else {
      // Images weren't captured yet, so there's no curl to animate — still turn
      // the page instantly if the swipe was decisive, so it isn't dropped.
      final pass = _accum.abs() > w * 0.18 || flung;
      if (pass) {
        _settleTo(target, knownImg: _forward ? _nextImg : _prevImg);
      }
      _resetDrag();
    }
  }

  void _resetDrag() {
    _accum = 0;
    _decided = false;
    _target = null;
  }

  void _onAnim() {
    setState(() => _progress = _animFrom + (_animTo - _animFrom) * _anim.value);
    if (_anim.isCompleted) {
      final commit = _animTo == 1.0;
      final target = _target;
      _dragging = false;
      _progress = 0;
      _resetDrag();
      if (commit && target != null) {
        _bridge = true;
        _settleTo(target, knownImg: _forward ? _nextImg : _prevImg);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _bridge) setState(() => _bridge = false);
        });
      } else {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final back = Color.lerp(bg, Colors.black, dark ? 0.45 : 0.12)!;
    final showNeighbours = _neighboursReady || _dragging;
    // The turning leaf is always the current page; it peels to reveal the
    // target neighbour underneath. forward peels from the LEFT edge.
    final top = _curImg;
    final bot = _forward ? _nextImg : _prevImg;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showNeighbours && _current > 0)
            RepaintBoundary(
              key: _prevKey,
              child: widget.itemBuilder(context, _current - 1),
            ),
          if (showNeighbours && _current < widget.itemCount - 1)
            RepaintBoundary(
              key: _nextKey,
              child: widget.itemBuilder(context, _current + 1),
            ),
          Positioned.fill(child: ColoredBox(color: bg)),
          Offstage(
            offstage: _dragging,
            child: RepaintBoundary(
              key: _curKey,
              child: widget.itemBuilder(context, _current),
            ),
          ),
          if (_dragging && top != null && bot != null)
            Positioned.fill(
              child: CustomPaint(
                painter: CurlPainter(
                  top: top,
                  bottom: bot,
                  progress: _progress,
                  // forward → peel from the LEFT edge (fold sweeps left→right);
                  // back → peel from the RIGHT edge. This is the corrected RTL
                  // direction (the old code peeled forward from the right).
                  fromRight: !_forward,
                  back: back,
                ),
              ),
            ),
          if (_bridge && !_dragging && _curImg != null)
            Positioned.fill(
              child: RawImage(image: _curImg, fit: BoxFit.fill),
            ),
        ],
      ),
    );
  }
}
