import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// App logger. Three destinations:
///  - console (`adb logcat` / `flutter logs`),
///  - an in-memory ring buffer rendered by the on-device Debug Log screen,
///  - a FILE on external storage so a whole run can be `adb pull`ed to a PC
///    after testing (nothing is sent anywhere automatically).
///
/// Levels: [d]/[e] always on; [t] high-volume trace, gated by [traceOn].
///
/// The buffer is mutated in place and the UI notifier + file are flushed on a
/// timer (not per line) — logging a token must stay O(1), or the firehose
/// would slow the very recitation we're trying to observe.
class Log {
  static final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>([]);
  static const _max = 5000;
  static bool traceOn = true;

  /// Diagnostics (the external-storage file sink + the on-device Debug Log
  /// screen that can export recitation traces) are DEV-ONLY: on in debug builds,
  /// or in any build via `--dart-define=DIAG=true`. A plain release/store build
  /// is silent — no verse/token recitation history is written anywhere.
  static bool get diagEnabled => kDebugMode || const bool.fromEnvironment('DIAG');

  static final List<String> _buf = [];
  static bool _dirty = false;
  static Timer? _flush;
  static bool _flushing = false; // a flush() is in flight — don't writeln into the sink meanwhile

  // File sink.
  static IOSink? _sink;
  static String? logFilePath; // shown on the Debug Log screen
  static bool _fileDirty = false;

  /// Open a per-run log file under the app's external files dir (adb-pullable
  /// without root). Call once from main() before runApp. Best-effort — logging
  /// keeps working (memory + console) even if the file can't be opened.
  static Future<void> initFileSink() async {
    try {
      Directory? base = await getExternalStorageDirectory();
      base ??= await getApplicationDocumentsDirectory();
      final logs = Directory('${base.path}/logs');
      if (!logs.existsSync()) logs.createSync(recursive: true);
      final f = File('${logs.path}/run_${_stamp()}.log');
      _sink = f.openWrite(mode: FileMode.append);
      logFilePath = f.path;
      _sink!.writeln('=== TilawaAi run ${DateTime.now().toIso8601String()} ===');
      d('log', 'file sink -> ${f.path}');
    } catch (e) {
      debugPrint('Log.initFileSink failed: $e');
    }
  }

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  static void d(String tag, String msg) => _write(tag, msg);

  /// High-volume trace — skipped entirely when [traceOn] is false.
  static void t(String tag, String msg) {
    if (!traceOn) return;
    _write(tag, msg);
  }

  static void _write(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$ts  [$tag] $msg';
    debugPrint(line);
    _buf.add(line);
    if (_buf.length > _max) _buf.removeRange(0, _buf.length - _max);
    _dirty = true;
    // Write only when no flush() is in flight — a writeln during a pending flush
    // is what throws "StreamSink is bound to a stream". Drop the rare in-window
    // line (still in the memory buffer) rather than throw into the caller or,
    // worse, kill the sink for the whole run.
    if (_sink != null && !_flushing) {
      try {
        _sink!.writeln(line);
        _fileDirty = true;
      } catch (_) {}
    }
    _flush ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_dirty) {
        _dirty = false;
        lines.value = List<String>.of(_buf);
      }
      if (_fileDirty && _sink != null && !_flushing) {
        _fileDirty = false;
        _flushing = true;
        _sink!.flush().then((_) {}, onError: (_) {}).whenComplete(() => _flushing = false);
      }
    });
  }

  static void e(String tag, Object error, [StackTrace? st]) {
    _write(tag, 'ERROR: $error');
    if (st != null) {
      debugPrint('$st');
      if (_sink != null && !_flushing) {
        try {
          _sink!.writeln('$st');
          _fileDirty = true;
        } catch (_) {}
      }
    }
  }

  /// Force the current file buffer to disk (call on session stop so a run is
  /// safely on disk even if the app is killed before the timer fires).
  static Future<void> flushFile() async {
    if (_sink == null || _flushing) return;
    _fileDirty = false;
    _flushing = true;
    try {
      await _sink!.flush();
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  static void clear() {
    _buf.clear();
    lines.value = const [];
  }
}
