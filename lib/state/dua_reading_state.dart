import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/analytics.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/phoneme_corpus.dart';
import '../services/asr/phoneme_matcher.dart';
import '../services/asr/pronunciation_head.dart' show Deviation;
import '../services/asr/session.dart' show MistakeKind, PhonemeScore, RecitationMistake;
import '../services/asr/tajweed_review.dart';
import '../services/asr/wav.dart';
import '../state/reading_state.dart'
    show revealForwardLocs, revealBackLocs, recentHeard, advanceMarker;
import '../util/log.dart';

/// Parallel, self-contained recitation pipeline for ONE du'a at a time — a
/// simpler sibling of [ReadingState]. A du'a is a single flat phoneme clip
/// (no mushaf pages, no cross-surah re-acquisition, no page-follow), and its
/// corpus word IS its display word (1:1), so everything here is word-index based
/// instead of "s:a:w" location based.
///
/// Uses the app-global [AsrEngine] — the ONE shared [SherpaAsr] + mic, also used
/// by the Quran [ReadingState]. The two pipelines are never active at once, so no
/// second phoneme model is ever created; this state only STARTS/STOPS the shared
/// mic, it never disposes the engine or mic.
class DuaReadingState extends ChangeNotifier {
  DuaReadingState(this._engine);

  final AsrEngine _engine;

  DuaClip? _clip;
  String? _duaId;
  PhonemeMatchSession? _matcher;

  bool _active = false;
  bool _starting = false;
  bool _liveMic = false; // gates skip haptics to the real mic, not the Stop flush
  String? _error;

  // ---- Hidden (memorization) mode ----
  bool _hidden = false;
  final Set<int> _revealed = {};

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
  bool get hidden => _hidden;
  Set<int> get readWords => _readWords;
  Set<int> get skippedWords => _skippedWords;
  int? get currentWord => _currentWord;
  bool isRevealed(int i) => _revealed.contains(i);

  bool get active => _active;
  bool get starting => _starting;
  String? get error => _error;

  // Live footer telemetry (read-only). Same device-tunable 0..1 mapping as the
  // Quran reader; anchored is true once the matcher has locked onto a word.
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

  // ---- Post-recitation review + PCM retention (mirrors ReadingState) ----
  List<RecitationMistake> _mistakes = [];
  List<RecitationMistake> get mistakes => _mistakes;

  static const int _maxRetainSeconds = 600;
  static const int _maxRetainSamples = _maxRetainSeconds * 16000;
  final BytesBuilder _sessionPcm = BytesBuilder();
  int _retainedSamples = 0;
  bool _retainTruncated = false;
  Int16List? _finalizedPcm;

  bool canPlayMistake(RecitationMistake m) => m.hasAudio && _retainedSamples > 0;

  Uint8List? mistakeWav(RecitationMistake m) {
    if (!m.hasAudio || _retainedSamples == 0) return null;
    final all = _finalizedPcm ??= () {
      final bytes = _sessionPcm.toBytes();
      return Int16List.view(bytes.buffer, bytes.offsetInBytes, _retainedSamples);
    }();
    final start = m.startSample.clamp(0, _retainedSamples);
    final end = m.endSample.clamp(start, _retainedSamples);
    if (end <= start) return null;
    return encodeWav(Int16List.sublistView(all, start, end));
  }

  Future<void> loadDua(String id) async {
    await _engine.ensureData();
    final clip = await loadDuaClip(id);
    _clip = clip;
    _duaId = id;
    _matcher = PhonemeMatchSession(clip.clip, _engine.units, logTag: 'duaread');
    _resetFollow();
    _revealed.clear();
    Log.d('dua', 'loaded $id (${clip.words.length} words)');
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

  // ---- Hidden mode ----
  void toggleHidden() {
    _hidden = !_hidden;
    if (!_hidden) _revealed.clear();
    notifyListeners();
  }

  void toggleWord(int i) {
    if (!_revealed.remove(i)) _revealed.add(i);
    notifyListeners();
  }

  // The reveal helpers are pure and location-string based; a du'a has no āyah
  // grouping (single segment), so encode each word as "0:<segment>:<index>" —
  // three parts so _ayahKey (which needs a colon) is safe and `>>`/`<<` reveal or
  // hide the whole segment (i.e. the whole du'a) while `>`/`<` step one word.
  int _segmentOf(int wordIndex) {
    final b = _clip?.clip.ayahBoundaries ?? const [0];
    var a = 0;
    for (var k = 1; k < b.length; k++) {
      if (wordIndex >= b[k]) {
        a = k;
      } else {
        break;
      }
    }
    return a;
  }

  String _loc(int i) => '0:${_segmentOf(i)}:$i';
  int _idx(String loc) => int.parse(loc.split(':').last);

  void revealForward({required bool ayah}) {
    final page = [for (var i = 0; i < words.length; i++) _loc(i)];
    final revealed = {for (final i in _revealed) _loc(i)};
    final read = {for (final i in _readWords) _loc(i)};
    var anchorIndex = -1;
    for (var i = 0; i < words.length; i++) {
      if (_revealed.contains(i) || _readWords.contains(i) || _currentWord == i) anchorIndex = i;
    }
    final add = revealForwardLocs(page, revealed, read, ayah: ayah, anchorIndex: anchorIndex);
    if (add.isEmpty) return;
    _revealed.addAll(add.map(_idx));
    notifyListeners();
  }

  void revealBack({required bool ayah}) {
    final page = [for (var i = 0; i < words.length; i++) _loc(i)];
    final revealed = {for (final i in _revealed) _loc(i)};
    final read = {for (final i in _readWords) _loc(i)};
    final remove = revealBackLocs(page, revealed, read, ayah: ayah);
    if (remove.isEmpty) return;
    _revealed.removeAll(remove.map(_idx));
    notifyListeners();
  }

  // ---- Live follow ----
  Future<void> toggleListening() async {
    if (_active) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (_disposed || _active || _starting || _clip == null) return;
    _starting = true;
    _error = null;
    _mistakes = [];
    _sessionPcm.clear();
    _retainedSamples = 0;
    _retainTruncated = false;
    _finalizedPcm = null;
    notifyListeners();
    try {
      final granted = await _engine.mic.hasPermission();
      if (!granted) {
        _error = 'Microphone permission denied';
        return;
      }
      await _engine.claimMic(stopListening, owner: 'dua-reader'); // stop a Quran session still holding the shared mic
      final asr = await _engine.ready();
      // The screen can be popped (dispose) while ready() awaits — release the
      // shared mic (not yet started here) and bail instead of starting on a dead
      // state. The shared engine is NOT disposed; it lives on for the next reader.
      if (_disposed) {
        await _engine.mic.stop();
        return;
      }
      _matcher!.reset();
      _resetFollow();
      asr.resetStream();
      await _engine.mic.start(_onPcm);
      _active = true;
      _liveMic = true;
      _startTimer();
      Log.d('dua', 'listening started (${_clip!.words.length} words)');
    } catch (e, st) {
      Log.e('dua', e, st);
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
    // run the finish/review/analytics block a second time for one session.
    _active = false;
    await _engine.mic.stop();
    // The reader can be popped (Provider disposes this state) while the above
    // await is in flight — bail before touching ChangeNotifier state, mirrors
    // the ready() guard in startListening. Without this, notifyListeners() below
    // throws "used after being disposed".
    if (_disposed) return;
    _liveMic = false; // the final flush apply below must not buzz a skip
    final asr = _engine.asrOrNull, matcher = _matcher;
    if (asr != null && matcher != null) {
      final tokens = asr.finish();
      if (tokens.isNotEmpty) {
        final out = matcher.apply(tokens);
        _applyOut(out);
        _buildMistakes(out, tokens);
        if (Analytics.instance.usageConsent) {
          unawaited(Analytics.instance.recordSession(buildSessionReport(
            kind: 'dua',
            ref: _duaId ?? '',
            reached: matcher.reached,
            tokens: tokens.length,
            anchored: matcher.anchored,
            skipped: _mistakes.where((m) => m.kind == MistakeKind.skipped).length,
            mistakes: _mistakes,
            durationMs: _seconds * 1000,
            platform: Platform.operatingSystem,
          )));
        }
      }
    }
    _currentWord = null;
    _timer?.cancel();
    _engine.releaseMic(stopListening);
    Log.d('dua', 'listening stopped');
    Log.flushFile();
    notifyListeners();
  }

  void _onPcm(Int16List pcm) {
    final asr = _engine.asrOrNull, matcher = _matcher;
    if (asr == null || matcher == null) return;
    _retain(pcm);
    final tokens = asr.accept(pcm);
    var sumsq = 0.0;
    for (final s in pcm) {
      sumsq += s * s;
    }
    _lastRms = pcm.isEmpty ? 0 : math.sqrt(sumsq / pcm.length);
    if (tokens.length > _prevTokens) {
      Log.t('phon', '[dua] +${tokens.length - _prevTokens} "${tokens.sublist(_prevTokens).join()}" '
          '(total=${tokens.length} rms=${_lastRms.toStringAsFixed(0)})');
    }
    _prevTokens = tokens.length;
    if (tokens.isEmpty) return;
    const tail = 12;
    final tailStart = tokens.length <= tail ? 0 : tokens.length - tail;
    _heardTail
      ..clear()
      ..addAll([for (var i = tailStart; i < tokens.length; i++) _collapse(tokens[i])]);
    _applyOut(matcher.apply(tokens));
  }

  void _retain(Int16List pcm) {
    if (_retainedSamples >= _maxRetainSamples) {
      if (!_retainTruncated) {
        _retainTruncated = true;
        Log.d('dua', 'PCM retention cap ($_maxRetainSeconds s) hit — playback truncated');
      }
      return;
    }
    _sessionPcm.add(Uint8List.view(pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes));
    _retainedSamples += pcm.length;
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
    if (_hidden) {
      _revealed.addAll(read);
      _revealed.addAll(skipped);
      if (_currentWord != null) _revealed.add(_currentWord!);
    }
    final m = _matcher;
    Log.t('duaread', 'cursor=${out.cursor} cur=$_currentWord read=${_readWords.length} '
        'skip=${_skippedWords.length} anchored=$anchored'
        '${m == null ? '' : ' head=${m.head} reach=${m.reached} '
            'loc=${m.lastLocWord}/${m.lastLocScore.toStringAsFixed(0)}'} '
        'rms=${_lastRms.toStringAsFixed(0)}');
    var newSkip = false;
    for (final e in out.events) {
      if (e.type == PhonemeEventType.skipped) newSkip = true;
    }
    if (newSkip && _liveMic) {
      HapticFeedback.mediumImpact();
      Log.d('dua', 'skip buzz');
    }
    notifyListeners();
  }

  void _buildMistakes(MatchOutput out, List<String> tokens) {
    final clip = _clip, matcher = _matcher;
    if (clip == null || matcher == null) return;
    if (matcher.reached < 0) {
      _mistakes = [];
      Log.d('dua', 'review: never anchored, no mistakes (tokens=${tokens.length})');
      return;
    }
    final skippedWords = <int>{
      for (var i = 0; i < out.states.length && i < clip.words.length; i++)
        if (out.states[i] == WordState.skipped) i
    };
    final flags = reviewTajweed(
      clip.clip,
      clip.words,
      tokens.join(' '),
      _engine.units,
      _engine.reliability,
      timestamps: _engine.asrOrNull?.lastTimestamps,
      maxWordIndex: matcher.reached,
      minWordIndex: matcher.anchor >= 0 ? matcher.anchor : null,
    );
    _mistakes = buildDuaMistakes(
      flags: flags,
      words: clip.words,
      skippedWords: skippedWords,
      retainedSamples: _retainedSamples,
    );
    Log.d('dua', 'review: ${flags.length} makhraj flag(s), ${skippedWords.length} skipped '
        '(reached=${matcher.reached}, tokens=${tokens.length})');
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
    // Free the retained voice PCM when leaving the du'a reader (data minimization).
    _sessionPcm.clear();
    _retainedSamples = 0;
    _finalizedPcm = null;
    super.dispose();
  }
}

/// Collapse runs of a repeated char to one — identical to the matcher's private
/// `_collapse`, so the footer "heard" ticker tokens read the same way the
/// reference phonemes are normalized.
String _collapse(String s) => s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

/// PURE mapping of tajwīd review output to reviewable mistakes for a du'a
/// (host-testable — no state, no platform channels). Makhraj-substitution flags
/// become [MistakeKind.mispronounced] records (word index as the location
/// string, display word as the expected text, flag audio span × 16k as the
/// sample range); [skippedWords] become [MistakeKind.skipped] records. A word
/// the matcher jumped over is never ALSO listed as a mispronunciation.
List<RecitationMistake> buildDuaMistakes({
  required List<TajweedFlag> flags,
  required List<String> words,
  required Set<int> skippedWords,
  required int retainedSamples,
}) {
  final mistakes = <RecitationMistake>[];
  for (final f in flags) {
    if (skippedWords.contains(f.wordIndex)) continue;
    if (f.wordIndex < 0 || f.wordIndex >= words.length) continue;
    var startSample = -1, endSample = -1;
    if (f.startSec != null && f.endSec != null && retainedSamples > 0) {
      startSample = (f.startSec! * 16000).round().clamp(0, retainedSamples);
      endSample = (f.endSec! * 16000).round().clamp(startSample, retainedSamples);
    }
    mistakes.add(RecitationMistake(
      kind: MistakeKind.mispronounced,
      location: '${f.wordIndex}',
      expectedText: words[f.wordIndex],
      heardText: f.heard,
      prob: null,
      phonemes: [PhonemeScore(f.ref, -1, 0, Deviation.major)],
      startSample: startSample,
      endSample: endSample,
    ));
  }
  for (final i in skippedWords) {
    if (i < 0 || i >= words.length) continue;
    mistakes.add(RecitationMistake(
      kind: MistakeKind.skipped,
      location: '$i',
      expectedText: words[i],
      heardText: '',
      prob: null,
      phonemes: const [],
      startSample: -1,
      endSample: -1,
    ));
  }
  return mistakes;
}
