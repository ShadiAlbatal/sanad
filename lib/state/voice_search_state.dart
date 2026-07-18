import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/word_asr.dart';
import '../util/log.dart';

/// Voice SEARCH driver: record a recitation on the shared mic and transcribe it
/// to Arabic text with the offline [WordAsr]. The text is exposed as [transcript]
/// (notified on change); a list screen mirrors it into its search field so the
/// EXISTING BM25 typed-search path renders ranked, highlighted results — voice
/// and typed search converge on one engine.
///
/// LIVE: because transcription runs ~60× realtime, the whole growing buffer is
/// re-transcribed every [_interimEvery] while recording, so results narrow AS
/// YOU RECITE instead of only on stop. A final pass runs on stop. Uses the
/// app-global [AsrEngine]'s shared mic (claimed for the duration); the word model
/// and the reader's phoneme model never RUN at once, so [cancel] hands the mic +
/// engine over on the way into a reader.
class VoiceSearchState extends ChangeNotifier {
  VoiceSearchState(this._engine, this._word);

  final AsrEngine _engine;
  final WordAsr _word;

  static const _interimEvery = Duration(seconds: 2);

  bool _recording = false;
  bool _busy = false; // loading the model or transcribing
  bool _transcribing = false; // an interim pass is running — don't overlap
  double _level = 0;
  String? _error;
  String _transcript = '';
  final List<int> _buf = [];
  Timer? _interimTimer;
  // Bumped by stop/cancel/preempt. start() captures it and re-checks after every
  // await, so a cancel during the (~1s) model-load window aborts the start instead
  // of leaving a hot mic running (e.g. app backgrounded mid-load).
  int _gen = 0;

  bool get recording => _recording;
  bool get busy => _busy;
  double get level => _level; // 0..1 mic level for the footer meter
  String? get error => _error;
  String get transcript => _transcript; // latest interim or final text

  /// Start capturing. First call also loads the ~125MB word model (~1s), during
  /// which [busy] is true; recording begins once it's ready.
  Future<void> start() async {
    if (_recording || _busy) {
      Log.d('voicesearch', 'start ignored (recording=$_recording busy=$_busy)');
      return;
    }
    Log.d('voicesearch', 'START requested');
    final gen = ++_gen;
    _error = null;
    _busy = true;
    _level = 0;
    _transcript = '';
    notifyListeners();
    try {
      final granted = await _engine.mic.hasPermission();
      if (gen != _gen) return; // aborted (cancel) during permission check
      Log.d('voicesearch', 'mic permission granted=$granted');
      if (!granted) {
        _error = 'Microphone permission denied';
        return;
      }
      await _word.ensureLoaded();
      if (gen != _gen) {
        Log.d('voicesearch', 'start aborted — cancelled during model load');
        return;
      }
      await _engine.claimMic(_release, owner: 'voice-search');
      if (gen != _gen) {
        _engine.releaseMic(_release);
        return;
      }
      _buf.clear();
      await _engine.mic.start(_onPcm);
      if (gen != _gen) {
        await _engine.mic.stop();
        _engine.releaseMic(_release);
        return;
      }
      _recording = true;
      _interimTimer = Timer.periodic(_interimEvery, (_) => _transcribeInterim());
      Log.d('voicesearch', 'recording started (live interim every ${_interimEvery.inSeconds}s)');
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

  /// Stop capturing and run a final transcription. The result is in [transcript].
  Future<void> stop() async {
    if (!_recording) return;
    _gen++;
    _recording = false;
    _interimTimer?.cancel();
    _busy = true;
    _level = 0;
    notifyListeners();
    try {
      await _engine.mic.stop();
      _engine.releaseMic(_release);
      Log.d('voicesearch', 'stopped — captured '
          '${(_buf.length / 16000).toStringAsFixed(1)}s (${_buf.length} samples)');
      if (_buf.isNotEmpty) {
        final text = _word.transcribe(Int16List.fromList(_buf));
        if (text.isNotEmpty) _transcript = text;
      }
      Log.d('voicesearch', 'final transcript -> "$_transcript"');
      Log.flushFile();
    } catch (e, st) {
      Log.e('voicesearch', e, st);
      _error = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Stop recording and release the mic WITHOUT a final transcription — used when
  /// the user taps a result to open its reader (locks the shown results) or leaves
  /// a search tab. Frees the shared mic and hands the engine over to the reader's
  /// phoneme follow-along.
  Future<void> cancel() async {
    _gen++; // abort any in-flight start()
    final wasActive = _recording || _busy;
    if (wasActive) {
      Log.d('voicesearch', 'cancel — locking results, releasing mic for follow-along');
    }
    _recording = false;
    _interimTimer?.cancel();
    _busy = false;
    _level = 0;
    // Invalidate SYNCHRONOUSLY — before any await — so the phoneme engine is
    // rebuilt before the reader we're about to open calls AsrEngine.ready(). If
    // this ran after `await mic.stop()`, the reader's warm ready() could grab the
    // recognizer we then dispose, killing follow-along (the exact 0-token bug).
    _handOffToFollowAlong();
    if (wasActive) {
      try {
        await _engine.mic.stop();
      } catch (_) {}
      _engine.releaseMic(_release);
    }
    notifyListeners();
  }

  // Free the ~125MB FastConformer model and rebuild a fresh phoneme recognizer so
  // reader follow-along runs on a clean, uncontended sherpa runtime. Only one of
  // the two models RUNS at a time (search vs reader); this also drops the word
  // model's ~125MB when leaving search. Reloads (~1s) on the next voice search.
  void _handOffToFollowAlong() {
    if (!_word.loaded) return; // word model never ran — phoneme engine is already clean
    _word.dispose();
    _engine.invalidateEngine();
    Log.d('voicesearch', 'handed off — word model freed, phoneme engine rebuilt on next use');
  }

  void _transcribeInterim() {
    if (_transcribing || !_recording || _buf.isEmpty) return;
    _transcribing = true;
    try {
      final snapshot = Int16List.fromList(_buf);
      final text = _word.transcribe(snapshot);
      if (text.isNotEmpty && text != _transcript) {
        _transcript = text;
        notifyListeners();
      }
    } catch (e, st) {
      Log.e('voicesearch', e, st);
    } finally {
      _transcribing = false;
    }
  }

  Future<void> _release() async {
    if (_recording) {
      Log.d('voicesearch', 'preempted — recording dropped (mic claimed by another owner)');
      _gen++;
      _recording = false;
      _interimTimer?.cancel();
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

  @override
  void dispose() {
    _interimTimer?.cancel();
    super.dispose();
  }
}
