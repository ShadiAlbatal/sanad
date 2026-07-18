import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/word_asr.dart';
import '../util/log.dart';

/// Voice SEARCH driver: record a recitation on the shared mic, then transcribe
/// the whole buffer to Arabic text with the offline [WordAsr] on stop. The text
/// is handed to the caller (a list screen), which drops it into its search field
/// so the EXISTING BM25 typed-search path renders the ranked, highlighted results
/// — voice and typed search converge on one engine.
///
/// Unlike the phoneme finders this replaces, there is NO live per-chunk probing:
/// just record → stop → one transcription. Uses the app-global [AsrEngine]'s
/// shared mic (claimed for the duration) so it never collides with reader
/// follow-along, which is never active at the same time.
class VoiceSearchState extends ChangeNotifier {
  VoiceSearchState(this._engine, this._word);

  final AsrEngine _engine;
  final WordAsr _word;

  bool _recording = false;
  bool _busy = false; // loading the model or transcribing
  double _level = 0;
  String? _error;
  final List<int> _buf = [];

  bool get recording => _recording;
  bool get busy => _busy;
  double get level => _level; // 0..1 mic level for the footer meter
  String? get error => _error;

  /// Start capturing. First call also loads the ~125MB word model (~1s), during
  /// which [busy] is true; recording begins once it's ready.
  Future<void> start() async {
    if (_recording || _busy) return;
    _error = null;
    _busy = true;
    _level = 0;
    notifyListeners();
    try {
      if (!await _engine.mic.hasPermission()) {
        _error = 'Microphone permission denied';
        return;
      }
      await _word.ensureLoaded();
      await _engine.claimMic(_release, owner: 'voice-search');
      _buf.clear();
      await _engine.mic.start(_onPcm);
      _recording = true;
    } catch (e, st) {
      Log.e('voicesearch', e, st);
      _error = e.toString();
      try {
        await _engine.mic.stop();
      } catch (_) {}
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Stop capturing and transcribe. Returns the recognized text ('' if nothing
  /// was said or on error).
  Future<String> stopAndTranscribe() async {
    if (!_recording) return '';
    _recording = false;
    _busy = true;
    _level = 0;
    notifyListeners();
    var text = '';
    try {
      await _engine.mic.stop();
      _engine.releaseMic(_release);
      if (_buf.isNotEmpty) {
        text = _word.transcribe(Int16List.fromList(_buf));
      }
    } catch (e, st) {
      Log.e('voicesearch', e, st);
      _error = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
    return text;
  }

  Future<void> _release() async {
    if (_recording) {
      _recording = false;
      try {
        await _engine.mic.stop();
      } catch (_) {}
      notifyListeners();
    }
  }

  void _onPcm(Int16List pcm) {
    _buf.addAll(pcm);
    var sumsq = 0.0;
    for (final s in pcm) {
      sumsq += s * s;
    }
    final rms = pcm.isEmpty ? 0.0 : math.sqrt(sumsq / pcm.length);
    _level = ((rms - 120) / 1600).clamp(0.0, 1.0);
    notifyListeners();
  }
}
