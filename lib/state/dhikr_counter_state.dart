import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../data/prefs.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/word_asr.dart';
import '../services/dhikr/dhikr_match.dart';
import '../util/log.dart';

/// Drives the voice tasbīḥ counter. Records on the shared mic and, on each
/// natural PAUSE between phrases (simple energy VAD), transcribes just that
/// spoken segment with the offline [WordAsr] and counts the tasbīḥ phrases in it
/// (see [countDhikr]) — so the user recites freely and the tallies climb, no
/// per-phrase button. Tapping a card also bumps its tally. Counts are persisted.
///
/// Segmenting on pauses (vs. re-transcribing the whole growing buffer like voice
/// SEARCH does) keeps every transcribe tiny, so a minutes-long dhikr session
/// stays real-time instead of re-decoding an ever-growing clip.
class DhikrCounterState extends ChangeNotifier {
  DhikrCounterState(this._prefs, this._engine, this._word)
      : _counts = Map<String, int>.of(_prefs.dhikrCounts);

  final Prefs _prefs;
  final AsrEngine _engine;
  final WordAsr _word;

  final Map<String, int> _counts;

  // VAD / segmentation tuning (mono PCM16 @ 16 kHz). Device-tunable.
  static const _speakRms = 260.0; // above this = speech present in the chunk
  static const _endSilenceSamples = 8000; // 0.5s of quiet after speech ends a segment
  static const _maxSegSamples = 128000; // 8s hard cap so a no-pause chant still flushes
  static const _minSegSamples = 3200; // <0.2s = noise, don't bother transcribing
  static const _pollEvery = Duration(milliseconds: 250);

  bool _recording = false;
  bool _busy = false;
  double _level = 0;
  String? _error;
  String _heard = '';
  final List<int> _seg = [];
  bool _hadSpeech = false;
  int _silenceSamples = 0;
  Timer? _poll;
  int _gen = 0;

  int count(String id) => _counts[id] ?? 0;
  int get total => _counts.values.fold(0, (a, b) => a + b);
  bool get recording => _recording;
  bool get busy => _busy;
  double get level => _level;
  String? get error => _error;
  String get heard => _heard; // last transcribed segment ("what was said")

  /// Manual increment (tapping a card) — same tallies as the voice path.
  void bump(String id, [int n = 1]) {
    if (n <= 0) return;
    _counts[id] = (_counts[id] ?? 0) + n;
    _prefs.setDhikrCounts(_counts);
    notifyListeners();
  }

  void resetAll() {
    if (_counts.isEmpty) return;
    _counts.clear();
    _prefs.setDhikrCounts(_counts);
    notifyListeners();
  }

  Future<void> toggleMic() => _recording || _busy ? stop() : start();

  Future<void> start() async {
    if (_recording || _busy) return;
    final gen = ++_gen;
    _error = null;
    _busy = true;
    _heard = '';
    _resetSegment();
    notifyListeners();
    try {
      if (!await _engine.mic.hasPermission()) {
        if (gen == _gen) _error = 'Microphone permission denied';
        return;
      }
      if (gen != _gen) return;
      await _word.ensureLoaded();
      if (gen != _gen) {
        if (!_busy && !_recording) _handOff();
        return;
      }
      await _engine.claimMic(_release, owner: 'dhikr-counter');
      if (gen != _gen) {
        _engine.releaseMic(_release);
        return;
      }
      _seg.clear();
      await _engine.mic.start(_onPcm);
      if (gen != _gen) {
        await _engine.mic.stop();
        _engine.releaseMic(_release);
        return;
      }
      _recording = true;
      _poll = Timer.periodic(_pollEvery, (_) => _maybeFlush());
      Log.d('dhikr', 'counter listening');
    } catch (e, st) {
      Log.e('dhikr', e, st);
      _error = e.toString();
      try {
        await _engine.mic.stop();
      } catch (_) {}
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!_recording && !_busy) return;
    _gen++;
    _recording = false;
    _poll?.cancel();
    _busy = true;
    _level = 0;
    notifyListeners();
    try {
      await _engine.mic.stop();
      _engine.releaseMic(_release);
      _flushSegment(); // count the final in-flight phrase
    } catch (e, st) {
      Log.e('dhikr', e, st);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Leaving the counter tab: stop + free the word model and rebuild the phoneme
  /// engine, so a reader opened next runs follow-along on a clean sherpa runtime
  /// (the two models must never contend — mirrors VoiceSearchState.cancel).
  Future<void> cancel() async {
    _gen++;
    final wasActive = _recording || _busy;
    _recording = false;
    _poll?.cancel();
    _busy = false;
    _level = 0;
    _handOff();
    if (wasActive) {
      try {
        await _engine.mic.stop();
      } catch (_) {}
      _engine.releaseMic(_release);
    }
    notifyListeners();
  }

  void _handOff() {
    if (!_word.loaded) return;
    _word.dispose();
    _engine.invalidateEngine();
    Log.d('dhikr', 'counter handed off — word model freed');
  }

  Future<void> _release() async {
    if (_recording) {
      _gen++;
      _recording = false;
      _poll?.cancel();
      try {
        await _engine.mic.stop();
      } catch (_) {}
      notifyListeners();
    }
  }

  void _onPcm(Int16List pcm) {
    _seg.addAll(pcm);
    var sumsq = 0.0;
    for (final s in pcm) {
      sumsq += s * s;
    }
    final rms = pcm.isEmpty ? 0.0 : math.sqrt(sumsq / pcm.length);
    _level = ((rms - 120) / 1600).clamp(0.0, 1.0);
    if (rms > _speakRms) {
      _hadSpeech = true;
      _silenceSamples = 0;
    } else if (_hadSpeech) {
      _silenceSamples += pcm.length;
    }
    notifyListeners(); // level meter
  }

  // Off the mic callback (on the poll timer): flush a completed utterance — one
  // ended by a pause, or a no-pause chant that hit the length cap.
  void _maybeFlush() {
    if (!_recording) return;
    final ended = _hadSpeech && _silenceSamples >= _endSilenceSamples;
    final tooLong = _seg.length >= _maxSegSamples;
    if (ended || tooLong) _flushSegment();
  }

  void _flushSegment() {
    if (!_hadSpeech || _seg.length < _minSegSamples) {
      _resetSegment();
      return;
    }
    final snapshot = Int16List.fromList(_seg);
    _resetSegment();
    final text = _word.transcribe(snapshot);
    if (text.isEmpty) return;
    _heard = text;
    final counts = countDhikr(text);
    if (counts.isNotEmpty) {
      counts.forEach((id, n) => _counts[id] = (_counts[id] ?? 0) + n);
      _prefs.setDhikrCounts(_counts);
      Log.d('dhikr', 'segment "$text" -> $counts');
    }
    notifyListeners();
  }

  void _resetSegment() {
    _seg.clear();
    _hadSpeech = false;
    _silenceSamples = 0;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
