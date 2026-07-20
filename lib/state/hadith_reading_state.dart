import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/hadith_corpus.dart';
import '../services/asr/hadith_search.dart';
import '../services/asr/phoneme_matcher.dart';
import '../state/reading_state.dart' show recentHeard, advanceMarker;
import '../util/log.dart';

/// Live follow-along for ONE hadith at a time — the reader lights each matn word
/// as the reciter reaches it. A trimmed sibling of [DuaReadingState]: a hadith is
/// a single flat phoneme clip whose corpus word IS its display word (1:1), so
/// everything here is word-index based. No memorization/hide mode and no
/// post-recitation tajwīd review (a hadith isn't recited for tajwīd) — just the
/// green/cursor follow.
///
/// The hadith text carries the isnād before the matn; a reciter typically recites
/// only the matn, so the isnād words simply never green. That is expected until
/// the future matn-only data swap — it is NOT special-cased here.
///
/// Uses the app-global [AsrEngine] — the ONE shared [SherpaAsr] + mic, also used
/// by the Quran/du'a readers and the hadith finder. While this reader is open its
/// follow-along OWNS the shared mic (claimed from the finder via [AsrEngine.claimMic]);
/// it only STARTS/STOPS the mic, never disposes the engine.
class HadithReadingState extends ChangeNotifier {
  HadithReadingState(this._engine);

  final AsrEngine _engine;

  HadithClip? _clip;
  PhonemeMatchSession? _matcher;

  bool _active = false;
  bool _starting = false;
  String? _error;

  // ---- Live follow state ----
  Set<int> _readWords = const {};
  Set<int> _skippedWords = const {};
  int? _currentWord;
  int _markerCursor = 0;

  // Last ~12 collapsed phoneme tokens for the footer "heard" ticker (read-only).
  final List<String> _heardTail = [];

  static const double _rmsFloor = 120;
  double _lastRms = 0; // read-only footer telemetry (see [level])
  int _prevTokens = 0; // cumulative token count last chunk — for the "heard delta" trace

  int _seconds = 0;
  Timer? _timer;

  List<String> get words => _clip?.words ?? const [];
  Set<int> get readWords => _readWords;
  Set<int> get skippedWords => _skippedWords;
  int? get currentWord => _currentWord;

  bool get active => _active;
  bool get starting => _starting;
  String? get error => _error;
  bool get hasClip => _clip != null;

  // Live footer telemetry (read-only). Same device-tunable 0..1 mapping as the
  // Quran/du'a readers; anchored is true once the matcher has locked onto a word.
  double get level =>
      _active ? ((_lastRms - _rmsFloor) / 1600).clamp(0.0, 1.0) : 0;
  bool get anchored => _matcher?.anchored ?? false;

  // Most-recent decoded phonemes for the footer "heard" ticker; '' when idle.
  String get heard => _active ? recentHeard(_heardTail) : '';

  String get durationLabel {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Load the follow-along clip for a hadith id ("bukhari:2790"). Reuses the
  /// already-decoded, cached corpus (the finder/search screen builds it off-thread
  /// on first tab open) — no second asset read. A hadith with no word map in the
  /// asset (older find-only build) leaves [hasClip] false and the reader stays a
  /// plain read view.
  Future<void> loadHadith(String id) async {
    await _engine.ensureData();
    final search = await loadHadithSearch();
    final clip = search.clipById(id);
    _clip = clip;
    if (clip != null) {
      _matcher = PhonemeMatchSession(clip.clip, _engine.units, logTag: 'hadithread');
      Log.d('hadithread', 'loaded $id (${clip.words.length} words)');
    } else {
      _matcher = null;
      Log.d('hadithread', 'loaded $id (no clip — follow-along unavailable)');
    }
    _resetFollow();
    notifyListeners();
  }

  void _resetFollow() {
    _readWords = const {};
    _skippedWords = const {};
    _currentWord = null;
    _markerCursor = 0;
    _heardTail.clear();
    _prevTokens = 0;
  }

  Future<void> toggleListening() async {
    if (_active) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (_disposed || _active || _starting || _matcher == null) return;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      final granted = await _engine.mic.hasPermission();
      if (!granted) {
        _error = 'Microphone permission denied';
        return;
      }
      await _engine.claimMic(stopListening, owner: 'hadith-reader'); // take the mic from the finder / any other session
      final asr = await _engine.ready();
      // The screen can be popped (dispose) while ready() awaits — release the
      // shared mic (not yet started here) and bail. The engine is NOT disposed.
      if (_disposed) {
        await _engine.mic.stop();
        return;
      }
      _matcher!.reset();
      _resetFollow();
      asr.resetStream();
      await _engine.mic.start(_onPcm);
      _active = true;
      _startTimer();
      Log.d('hadithread', 'listening started (${_clip!.words.length} words)');
    } catch (e, st) {
      Log.e('hadithread', e, st);
      _error = e.toString();
      try {
        await _engine.mic.stop();
      } catch (_) {}
      _active = false;
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stopListening() async {
    if (!_active) return;
    // Clear synchronously before the first await: a re-entrant Stop (double mic
    // tap, or a cross-pipeline claimMic preempting this in-flight Stop) must not
    // run the finish block twice for one session.
    _active = false;
    await _engine.mic.stop();
    // The reader can be popped (Provider disposes this state) while the above
    // await is in flight — bail before touching ChangeNotifier state, mirrors
    // the ready() guard in startListening. Without this, notifyListeners() below
    // throws "used after being disposed".
    if (_disposed) return;
    final asr = _engine.asrOrNull, matcher = _matcher;
    if (asr != null && matcher != null) {
      final tokens = asr.finish();
      if (tokens.isNotEmpty) _applyOut(matcher.apply(tokens));
    }
    _currentWord = null;
    _timer?.cancel();
    _engine.releaseMic(stopListening);
    Log.d('hadithread', 'listening stopped');
    Log.flushFile();
    notifyListeners();
  }

  void _onPcm(Int16List pcm) {
    final asr = _engine.asrOrNull, matcher = _matcher;
    if (asr == null || matcher == null) return;
    final tokens = asr.accept(pcm);
    var sumsq = 0.0;
    for (final s in pcm) {
      sumsq += s * s;
    }
    _lastRms = pcm.isEmpty ? 0 : math.sqrt(sumsq / pcm.length);
    if (tokens.length > _prevTokens) {
      Log.t('phon', '[hadith] +${tokens.length - _prevTokens} "${tokens.sublist(_prevTokens).join()}" '
          '(total=${tokens.length} rms=${_lastRms.toStringAsFixed(0)})');
    }
    _prevTokens = tokens.length;
    if (tokens.isEmpty) return;
    const tail = 12;
    final tailStart = tokens.length <= tail ? 0 : tokens.length - tail;
    _heardTail
      ..clear()
      ..addAll([for (var i = tailStart; i < tokens.length; i++) _collapse(tokens[i])]);
    // Readable, already-collapsed form of the recent tail: the phoneme units are
    // Arabic-scripted, and _collapse already folds the madd repeats, so this reads
    // cleanly without manual repeat-collapsing.
    Log.t('phon', '[hadith] collapsed tail: "${_heardTail.join()}"');
    _applyOut(matcher.apply(tokens));
  }

  void _applyOut(MatchOutput out) {
    final clip = _clip;
    if (clip == null) return;
    final read = <int>{};
    final skipped = <int>{};
    for (var i = 0; i < out.states.length && i < clip.words.length; i++) {
      if (out.states[i] == WordState.correct) {
        read.add(i);
      } else if (out.states[i] == WordState.skipped) {
        skipped.add(i);
      }
    }
    _readWords = read;
    _skippedWords = skipped;
    final anchored = _matcher?.anchored ?? false;
    if (!anchored) {
      _markerCursor = out.cursor;
      _currentWord = null;
    } else {
      // Anti-teleport catch-up after a waqf-pause burst (see [advanceMarker]).
      _markerCursor = advanceMarker(_markerCursor, out.cursor);
      _currentWord = _markerCursor.clamp(0, clip.words.length - 1);
    }
    final m = _matcher;
    Log.t('hadithread', 'cursor=${out.cursor} cur=$_currentWord read=${_readWords.length} '
        'skip=${_skippedWords.length} anchored=$anchored'
        '${m == null ? '' : ' head=${m.head} reach=${m.reached} '
            'loc=${m.lastLocWord}/${m.lastLocScore.toStringAsFixed(0)}'} '
        'rms=${_lastRms.toStringAsFixed(0)}');
    notifyListeners();
  }

  void _startTimer() {
    _seconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      _seconds++;
      notifyListeners();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _engine.releaseMic(stopListening); // drop the claim so the engine holds no ref to this disposed state
    if (_active) _engine.mic.stop(); // release the shared mic; the engine lives on
    super.dispose();
  }
}

/// Collapse runs of a repeated char to one — identical to the matcher's private
/// `_collapse`, so the footer "heard" ticker tokens read the same way the
/// reference phonemes are normalized.
String _collapse(String s) => s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
