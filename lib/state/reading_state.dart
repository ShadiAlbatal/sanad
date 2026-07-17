import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/analytics.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/eval_runner.dart';
import '../services/asr/file_source.dart';
import '../services/asr/phoneme_align.dart' show PhonemeLocalizer, LocResult;
import '../services/asr/phoneme_corpus.dart';
import '../services/asr/phoneme_matcher.dart';
import '../services/asr/pronunciation_head.dart' show Deviation;
import '../services/asr/session.dart' show MistakeKind, PhonemeScore, RecitationMistake;
import '../services/asr/tajweed_review.dart';
import '../services/asr/wav.dart';
import '../util/log.dart';

/// State for the read-along / memorization footer: hidden mode (with per-word
/// reveal) and the live streaming-phoneme recitation follow-along (sherpa-onnx
/// zipformer2-ctc + the ported phoneme matcher).
class ReadingState extends ChangeNotifier {
  ReadingState(this._engine);

  final AsrEngine _engine;

  // ---- Hidden (memorization) mode ----
  bool _hidden = false;
  bool get hidden => _hidden;

  final Set<String> _revealed = {};
  bool isRevealed(String loc) => _revealed.contains(loc);
  Set<String> get revealed => _revealed;

  void toggleHidden() {
    _hidden = !_hidden;
    if (!_hidden) _revealed.clear();
    Log.d('reading', 'hidden=$_hidden');
    _notify();
  }

  void toggleWord(String loc) {
    if (!_revealed.remove(loc)) _revealed.add(loc);
    _notify();
  }

  void revealLocations(Iterable<String> locs) {
    _revealed.addAll(locs);
    _notify();
  }

  void hideLocations(Iterable<String> locs) {
    _revealed.removeAll(locs);
    _notify();
  }

  // ---- Footer step-reveal (no reciting) ----
  // The visible page's word locations in reading order; drives the < << > >>
  // reveal buttons. The screen rebuilds on page settle, so storing is enough.
  List<String> _pageWordLocs = const [];
  void setPageWords(List<String> locs) => _pageWordLocs = locs;

  void revealForward({required bool ayah}) {
    var anchorIndex = -1;
    for (var i = 0; i < _pageWordLocs.length; i++) {
      final loc = _pageWordLocs[i];
      if (_asrRead.contains(loc) || _revealed.contains(loc) || loc == _asrCurrentLocation) {
        anchorIndex = i;
      }
    }
    final add = revealForwardLocs(_pageWordLocs, _revealed, _asrRead,
        ayah: ayah, anchorIndex: anchorIndex);
    if (add.isEmpty) return;
    _revealed.addAll(add);
    Log.d('reading', 'reveal forward ${ayah ? "ayah" : "word"} +${add.length} (anchor=$anchorIndex)');
    _notify();
  }

  void revealBack({required bool ayah}) {
    final remove = revealBackLocs(_pageWordLocs, _revealed, _asrRead, ayah: ayah);
    if (remove.isEmpty) return;
    _revealed.removeAll(remove);
    Log.d('reading', 'reveal back ${ayah ? "ayah" : "word"} -${remove.length}');
    _notify();
  }

  // ---- Live streaming-phoneme recitation follow-along ----
  SurahClip? _clip;
  PhonemeMatchSession? _matcher;

  bool _asrActive = false;
  bool _liveMic = false; // true only during real mic recitation (not file diagnostic) — gates skip haptics
  bool _asrStarting = false;
  String? _asrError;
  String? _asrCurrentLocation;
  Set<String> _asrCurrentLocations = const {};
  int _markerCursor = 0; // display marker, steps forward ≤1 word/chunk (anti-teleport)
  Map<String, int> _versePage = const {}; // "s:a" -> mushaf page, for auto-follow
  int _lastAsrPage = -1;
  Set<String> _asrRead = const {};
  Set<String> _asrSkipped = const {};
  int _asrSeconds = 0;
  Timer? _asrTimer;

  int _ctxSurah = 1;

  // ---- Cross-surah re-acquisition (net-new; no ZikirAi reference) ----
  // When the live matcher (locked to _ctxSurah) stops advancing while the mic is
  // still hearing speech, probe a bounded neighbourhood of surahs and, if another
  // one clearly aligns better for several consecutive probes, switch to it. All
  // orchestration lives here — the matcher/localizer are never modified.
  static const int _reacqNeighbourhood = 5; // probe _ctxSurah±N (clamped 1..114)
  static const int _stallTokens = 40; // anchored: no progress across this many new tokens = stall
  static const int _neverAnchorTokens = 80; // never anchored after this much audio = stall
  static const double _rmsFloor = 120; // below this the mic is treated as silent (no stall)
  static const double _switchMargin = 0.3; // winner must beat current by this (per-token score)
  static const double _switchFloor = 0.9; // winner's per-token score must clear this
  static const int _confirmProbes = 3; // consecutive probe wins required before switching
  static const int _probeIntervalTokens = 12; // min new tokens between probes
  static const int _probeTail = 24; // recent tokens fed to each candidate localizer (matcher's _tail)
  static const int _maxReacqSwitches = 4; // consecutive switches WITHOUT anchoring progress before giving up (anti-ping-pong)

  final Map<int, PhonemeLocalizer> _probeLoc = {};
  List<String> _tailTokens = const []; // last _probeTail collapsed tokens (for probing)
  bool _probing = false;
  int _lastReached = -1;
  int _lastReadCount = 0;
  int _lastProgressTokens = 0;
  int _lastProbeTokens = 0;
  int _reacqWinner = -1;
  int _reacqWinStreak = 0;
  int _switchCount = 0; // switches since the last genuine anchoring progress; NOT reset per-clip

  final ValueNotifier<int?> asrNavigate = ValueNotifier<int?>(null);

  // Bumps ONLY when the mushaf-visible state (read/skipped markers, current
  // location, reveal set, hidden mode, surah) actually changes. The reader
  // rebuilds its expensive page tree on THIS, not on every high-frequency
  // notifyListeners (RMS level, heard ticker, 1 s timer) — those only the footer
  // needs. Signature is cheap; a same-length content swap is still caught by
  // _ctxSurah + currentLocation, and any residual miss self-corrects on the next
  // changing chunk (~80 ms), so the mushaf can never go persistently stale.
  final ValueNotifier<int> markerTick = ValueNotifier<int>(0);
  String _markerSig = '';

  /// Every state change routes through here: bump [markerTick] iff the visible
  /// marker state changed, then notify listeners as usual (the footer relies on
  /// the full-frequency notify for its live level/heard/timer).
  void _notify() {
    final sig = '$_ctxSurah|${_asrRead.length}|${_asrSkipped.length}|'
        '${_revealed.length}|$_asrCurrentLocation|$_hidden';
    if (sig != _markerSig) {
      _markerSig = sig;
      markerTick.value++;
    }
    notifyListeners();
  }

  bool get asrActive => _asrActive;
  bool get asrStarting => _asrStarting;
  String? get asrError => _asrError;
  String? get asrHighlightedLocation => _asrCurrentLocation;
  // ALL mushaf glyphs of the current corpus word — a merged corpus word covers
  // several glyphs, so (like the RN app) the whole phrase is "current" together
  // instead of a point marker hanging on the first glyph.
  Set<String> get asrHighlightedLocations => _asrCurrentLocations;
  Set<String> get asrReadLocations => _asrRead;
  Set<String> get asrSkippedLocations => _asrSkipped;
  int get asrSeconds => _asrSeconds;

  // Live footer telemetry (read-only). asrLevel is a DEVICE-TUNABLE 0..1 mic
  // level from the same _lastRms the re-acquire stall test uses: silence (~18)
  // clamps to 0, normal speech (~700–1500) lands ~0.35–0.85. asrAnchored is true
  // once the matcher has locked onto a position — i.e. it knows where you are.
  double get asrLevel =>
      _asrActive ? ((_lastRms - _rmsFloor) / 1600).clamp(0.0, 1.0) : 0;
  bool get asrAnchored => _matcher?.anchored ?? false;

  // The most-recent decoded phonemes as a readable RTL string for the footer
  // "heard" ticker (read-only telemetry — the last ~12 already-collapsed tail
  // tokens). '' when idle.
  String get asrHeard => _asrActive ? recentHeard(_tailTokens) : '';

  String? get asrCurrentVerseKey {
    final loc = _asrCurrentLocation;
    if (loc == null) return null;
    final p = loc.split(':');
    return p.length >= 2 ? '${p[0]}:${p[1]}' : null;
  }

  // Post-recitation tajwīd review, computed once at Stop (see _buildMistakes).
  List<RecitationMistake> _mistakes = [];
  List<RecitationMistake> get mistakes => _mistakes;

  // Session PCM retained (16-bit @16kHz, capture order) so a flagged word's audio
  // span can be sliced for tap-to-hear. Bounded so a long session can't grow it
  // without limit; once the cap is hit we stop appending (playback of anything
  // past the cap is silently truncated).
  static const int _maxRetainSeconds = 600;
  static const int _maxRetainSamples = _maxRetainSeconds * 16000;
  final BytesBuilder _sessionPcm = BytesBuilder();
  int _retainedSamples = 0;
  bool _retainTruncated = false;
  Int16List? _finalizedPcm; // materialized once on first playback (session is idle by then)

  /// Drop the retained session voice PCM (data minimization). Safe once
  /// tap-to-hear is no longer reachable — leaving the reader, backgrounding, or
  /// dispose — since mistake playback only needs it while the reader is open.
  void clearRetainedPcm() {
    _sessionPcm.clear();
    _retainedSamples = 0;
    _retainTruncated = false;
    _finalizedPcm = null;
  }

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

  String get asrTimeLabel {
    final m = (_asrSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_asrSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// The open page's surah is the recitation reference (clip). Reloading it while
  /// a session runs re-anchors on the new surah.
  void setCurrentPage({required int page, required int surah}) {
    // A turn WE triggered to follow the reciter or re-acquire (page ==
    // _lastAsrPage) must not touch _ctxSurah or re-anchor: the matcher is already
    // on the right surah, and on a shared landing page (juz 30, where a short
    // surah starts mid-page) chapterForPageSync would mis-derive a later surah
    // and desync _ctxSurah from the live clip.
    if (_asrActive && page == _lastAsrPage) return;
    final surahChanged = surah != _ctxSurah;
    _ctxSurah = surah;
    if (_asrActive && surahChanged) {
      _switchCount = 0;
      _loadClipAndMatcher(surah).then((_) {
        _engine.asrOrNull?.resetStream();
        Log.d('read', 'surah changed while active -> re-anchor surah $surah');
        _notify();
      });
    }
  }

  void warmAsrEngine() => _engine.warm();

  Future<void> _loadClipAndMatcher(int surah) async {
    await _engine.ensureData();
    if (_versePage.isEmpty) _versePage = await loadVersePages();
    final clip = await loadSurahClip(surah);
    _clip = clip;
    _matcher = PhonemeMatchSession(clip.clip, _engine.units);
    _asrCurrentLocation = null; // no marker until the matcher actually locks on
    _asrCurrentLocations = const {};
    _markerCursor = 0;
    _lastAsrPage = -1;
    _asrRead = const {};
    _resetReacqState();
  }

  void _resetReacqState() {
    _lastReached = -1;
    _lastReadCount = 0;
    _lastProgressTokens = 0;
    _lastProbeTokens = 0;
    _reacqWinner = -1;
    _reacqWinStreak = 0;
    _prevTokens = 0;
    _lastTokens = 0;
    _tailTokens = const [];
  }

  Future<void> toggleAsr() async {
    if (_asrActive) {
      await stopAsrListening();
    } else {
      await startAsrListening();
    }
  }

  Future<void> startAsrListening() async {
    if (_asrActive || _asrStarting) return;
    _asrStarting = true;
    _asrError = null;
    _mistakes = [];
    _sessionPcm.clear();
    _retainedSamples = 0;
    _retainTruncated = false;
    _finalizedPcm = null;
    _notify();
    try {
      final granted = await _engine.mic.hasPermission();
      if (!granted) {
        _asrError = 'Microphone permission denied';
        return;
      }
      await _engine.claimMic(stopAsrListening, owner: 'quran'); // stop a du'a session still holding the shared mic
      final asr = await _engine.ready();
      _switchCount = 0;
      await _loadClipAndMatcher(_ctxSurah);
      asr.resetStream();
      await _engine.mic.start(_onPcm);
      _asrActive = true;
      _liveMic = true;
      _startAsrTimer();
      Log.d('asr', 'listening started (surah $_ctxSurah, ${_clip?.clip.wordCount} words)');
    } catch (e, st) {
      Log.e('asr', e, st);
      _asrError = e.toString();
      try {
        await _engine.mic.stop();
      } catch (_) {}
      _asrActive = false;
    } finally {
      _asrStarting = false;
      _notify();
    }
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
    // Verbose: log every NEW phoneme the model emitted this chunk (delta, not the
    // whole cumulative string — that would grow unbounded per 80ms chunk).
    if (tokens.length > _prevTokens) {
      Log.t('phon', '+${tokens.length - _prevTokens} "${tokens.sublist(_prevTokens).join()}" '
          '(total=${tokens.length} rms=${_lastRms.toStringAsFixed(0)})');
    }
    _prevTokens = tokens.length;
    _lastTokens = tokens.length;
    if (tokens.isEmpty) return;
    final tailStart = tokens.length <= _probeTail ? 0 : tokens.length - _probeTail;
    _tailTokens = [for (var i = tailStart; i < tokens.length; i++) _collapseTok(tokens[i])];
    _applyOut(matcher.apply(tokens));
    if (!_probing &&
        _switchCount < _maxReacqSwitches &&
        _stalled() &&
        _lastTokens - _lastProbeTokens >= _probeIntervalTokens) {
      _probeAndMaybeSwitch();
    }
  }

  void _retain(Int16List pcm) {
    if (_retainedSamples >= _maxRetainSamples) {
      if (!_retainTruncated) {
        _retainTruncated = true;
        Log.d('asr', 'PCM retention cap ($_maxRetainSeconds s) hit — mistake playback truncated');
      }
      return;
    }
    _sessionPcm.add(Uint8List.view(pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes));
    _retainedSamples += pcm.length;
  }

  bool _stalled() => reacqStalled(
        rms: _lastRms,
        rmsFloor: _rmsFloor,
        anchored: _matcher?.anchored ?? false,
        tokens: _lastTokens,
        lastProgressTokens: _lastProgressTokens,
        stallTokens: _stallTokens,
        neverAnchorTokens: _neverAnchorTokens,
      );

  Future<PhonemeLocalizer> _probeLocalizer(int surah) async {
    final cached = _probeLoc[surah];
    if (cached != null) return cached;
    final clip = await loadSurahClip(surah);
    final loc = PhonemeLocalizer(
      clip.clip.phonemes.map(_collapseTok).toList(),
      (r) => clip.clip.phonemeToWord[r],
    );
    _probeLoc[surah] = loc;
    return loc;
  }

  Future<void> _probeAndMaybeSwitch() async {
    final tail = _tailTokens;
    if (tail.length < 6) return;
    _probing = true;
    try {
      final lo = math.max(1, _ctxSurah - _reacqNeighbourhood);
      final hi = math.min(114, _ctxSurah + _reacqNeighbourhood);
      final scores = <int, double>{};
      final results = <int, LocResult>{};
      for (var s = lo; s <= hi; s++) {
        final loc = await _probeLocalizer(s);
        final r = loc.localizeScored(tail);
        results[s] = r;
        scores[s] = r.score / tail.length;
      }
      _lastProbeTokens = _lastTokens;
      final decision = decideReacquire(
        current: _ctxSurah,
        scores: scores,
        prevWinner: _reacqWinner,
        prevWinStreak: _reacqWinStreak,
        switchMargin: _switchMargin,
        switchFloor: _switchFloor,
        confirmProbes: _confirmProbes,
      );
      _reacqWinner = decision.winner;
      _reacqWinStreak = decision.winStreak;
      Log.d('recite',
          'REACQ probe surah=$_ctxSurah win=$lo..$hi streak=${decision.winner}x${decision.winStreak} '
          'scores=${[for (var s = lo; s <= hi; s++) '$s:${(scores[s] ?? 0).toStringAsFixed(2)}'].join(' ')}');
      final c = decision.switchTo;
      if (c != null && _asrActive) await _reacquireSwitch(c, scores[c] ?? 0, results[c]);
    } finally {
      _probing = false;
    }
  }

  // Land on the mushaf page of the reciter's localized position in the new surah
  // (from the probe's matched word), not the surah's first page — a mid-surah
  // re-acquire shouldn't yank the reader back to āyah 1.
  int? _landingPage(int surah, LocResult? loc) {
    final clip = _clip;
    if (loc != null && loc.word >= 0 && clip != null && loc.word < clip.wordLocations.length) {
      final locs = clip.wordLocations[loc.word];
      if (locs.isNotEmpty) {
        final p = locs.first.split(':');
        final page = _versePage['${p[0]}:${p[1]}'];
        if (page != null) return page;
      }
    }
    return _versePage['$surah:1'];
  }

  Future<void> _reacquireSwitch(int c, double score, LocResult? loc) async {
    Log.d('recite', 'RE-ACQUIRE surah $_ctxSurah -> $c (score ${score.toStringAsFixed(2)})');
    await _loadClipAndMatcher(c);
    _ctxSurah = c;
    _switchCount++;
    _engine.asrOrNull?.resetStream();
    final page = _landingPage(c, loc);
    if (page != null) {
      _lastAsrPage = page;
      asrNavigate.value = page;
    }
    _notify();
  }

  double _lastRms = 0;
  int _lastTokens = 0;
  int _prevTokens = 0;

  void _applyOut(MatchOutput out) {
    final clip = _clip;
    if (clip == null) return;
    final read = <String>{};
    final skipped = <String>{};
    for (var i = 0; i < out.states.length && i < clip.wordLocations.length; i++) {
      final locs = clip.wordLocations[i];
      if (out.states[i] == WordState.correct) {
        read.addAll(locs);
      } else if (out.states[i] == WordState.skipped) {
        skipped.addAll(locs);
      }
    }
    _asrRead = read;
    _asrSkipped = skipped;
    // Only show the marker once the matcher has locked on — otherwise the warm-up
    // cursor (word 0) pins a false marker to the first word of the loaded surah.
    final anchored = _matcher?.anchored ?? false;
    // Re-acquisition progress signal: the frontier or greened count advancing
    // means we're still tracking this surah — record it so a later stall (no
    // forward movement while audio keeps flowing) can be detected.
    final reached = _matcher?.reached ?? -1;
    if (reached > _lastReached || read.length > _lastReadCount) {
      _lastReached = math.max(_lastReached, reached);
      _lastReadCount = math.max(_lastReadCount, read.length);
      _lastProgressTokens = _lastTokens;
      _reacqWinner = -1;
      _reacqWinStreak = 0;
      _switchCount = 0; // genuine progress → this IS the right surah; re-arm re-acquisition
    }
    if (!anchored) {
      _markerCursor = out.cursor;
      _asrCurrentLocation = null;
      _asrCurrentLocations = const {};
    } else {
      // Anti-teleport catch-up after a waqf-pause burst (see [advanceMarker]).
      _markerCursor = advanceMarker(_markerCursor, out.cursor);
      _asrCurrentLocation = clip.primary(_markerCursor); // first glyph, for auto-scroll
      _asrCurrentLocations = clip.glyphsOf(_markerCursor); // whole current word
      // Follow the reciter across pages: when the marker's verse sits on a new
      // page, ask the reader to turn there.
      final loc = _asrCurrentLocation;
      if (loc != null) {
        final p = loc.split(':');
        final page = _versePage['${p[0]}:${p[1]}'];
        if (page != null && page != _lastAsrPage) {
          _lastAsrPage = page;
          asrNavigate.value = page;
        }
      }
    }
    if (_hidden) {
      _revealed.addAll(read);
      _revealed.addAll(skipped); // show skipped words (rendered red), not blank
      final loc = _asrCurrentLocation;
      if (loc != null) _revealed.add(loc);
    }
    final m = _matcher;
    Log.t('recite', 'cursor=${out.cursor} cur=$_asrCurrentLocation read=${read.length} skip=${skipped.length}'
        '${m == null ? '' : ' head=${m.head} reach=${m.reached} ay=${m.curAyah} '
            'loc=${m.lastLocWord}/${m.lastLocScore.toStringAsFixed(0)}'} toks=$_lastTokens rms=${_lastRms.toStringAsFixed(0)}');
    // Verbose: log every word state-change event with its mushaf glyph(s).
    var newSkip = false;
    for (final e in out.events) {
      final locs = e.wordIndex < clip.wordLocations.length ? clip.wordLocations[e.wordIndex] : const <String>[];
      final kind = e.type == PhonemeEventType.correct
          ? 'GREEN'
          : e.type == PhonemeEventType.skipped
              ? 'SKIP'
              : 'skip-attempt';
      if (e.type == PhonemeEventType.skipped) newSkip = true;
      Log.t('word', '$kind w${e.wordIndex} -> ${locs.join(",")}');
    }
    if (newSkip && _liveMic) {
      HapticFeedback.mediumImpact();
      Log.d('haptic', 'skip buzz');
    }
    _notify();
  }

  /// Post-recitation review (once at Stop): makhraj-substitution flags over the
  /// finalized phoneme transcript, plus the words the matcher marked skipped.
  void _buildMistakes(MatchOutput out, List<String> tokens) {
    final clip = _clip, matcher = _matcher;
    if (clip == null || matcher == null) return;
    // Never anchored → no reliable reference span; ZikirAi returns nothing here.
    if (matcher.reached < 0) {
      _mistakes = [];
      Log.d('mistakes', 'review: never anchored, no mistakes (tokens=${tokens.length})');
      return;
    }
    final mistakes = <RecitationMistake>[];
    // Skipped-word indices first, so a word the matcher jumped over is never ALSO
    // listed as a makhraj mispronunciation.
    final skippedWords = <int>{
      for (var i = 0; i < out.states.length && i < clip.wordLocations.length; i++)
        if (out.states[i] == WordState.skipped) i
    };
    final flags = reviewTajweed(
      clip.clip,
      clip.words,
      tokens.join(' '), // space-join is lossless; '' re-merges adjacent units on retokenize
      _engine.units,
      _engine.reliability,
      timestamps: _engine.asrOrNull?.lastTimestamps,
      maxWordIndex: matcher.reached,
      minWordIndex: matcher.anchor >= 0 ? matcher.anchor : null,
    );
    for (final f in flags) {
      if (skippedWords.contains(f.wordIndex)) continue;
      final locs =
          f.wordIndex < clip.wordLocations.length ? clip.wordLocations[f.wordIndex] : const <String>[];
      if (locs.isEmpty) continue;
      var startSample = -1, endSample = -1;
      if (f.startSec != null && f.endSec != null && _retainedSamples > 0) {
        startSample = (f.startSec! * 16000).round().clamp(0, _retainedSamples);
        endSample = (f.endSec! * 16000).round().clamp(startSample, _retainedSamples);
      }
      mistakes.add(RecitationMistake(
        kind: MistakeKind.mispronounced,
        location: locs.first,
        expectedText: f.wordIndex < clip.words.length ? clip.words[f.wordIndex] : '',
        heardText: f.heard,
        prob: null,
        phonemes: [PhonemeScore(f.ref, -1, 0, Deviation.major)],
        startSample: startSample,
        endSample: endSample,
      ));
    }
    var skips = 0;
    for (final i in skippedWords) {
      final locs = clip.wordLocations[i];
      if (locs.isEmpty) continue;
      skips++;
      mistakes.add(RecitationMistake(
        kind: MistakeKind.skipped,
        location: locs.first,
        expectedText: i < clip.words.length ? clip.words[i] : '',
        heardText: '',
        prob: null,
        phonemes: const [],
        startSample: -1,
        endSample: -1,
      ));
    }
    _mistakes = mistakes;
    Log.d('mistakes', 'review: ${flags.length} makhraj flag(s), $skips skipped '
        '(reached=${matcher.reached}, tokens=${tokens.length})');
  }

  void _startAsrTimer() {
    _asrSeconds = 0;
    _asrTimer?.cancel();
    _asrTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _asrSeconds++;
      _notify();
    });
  }

  Future<void> stopAsrListening() async {
    if (!_asrActive) return;
    // Clear synchronously before the first await: a re-entrant Stop (double mic
    // tap, or a cross-pipeline claimMic preempting this in-flight Stop) must not
    // run the finish/review/analytics block a second time for one session.
    _asrActive = false;
    await _engine.mic.stop();
    _liveMic = false; // stop is silent — the final apply below must not buzz a skip
    final asr = _engine.asrOrNull, matcher = _matcher;
    if (asr != null && matcher != null) {
      final tokens = asr.finish();
      if (tokens.isNotEmpty) {
        final out = matcher.apply(tokens);
        _applyOut(out);
        _buildMistakes(out, tokens);
        if (Analytics.instance.usageConsent) {
          unawaited(Analytics.instance.recordSession(buildSessionReport(
            kind: 'quran',
            ref: '$_ctxSurah',
            reached: matcher.reached,
            tokens: tokens.length,
            anchored: matcher.anchored,
            skipped: _mistakes.where((m) => m.kind == MistakeKind.skipped).length,
            mistakes: _mistakes,
            durationMs: _asrSeconds * 1000,
            platform: Platform.operatingSystem,
          )));
        }
      }
      // Dump the full cumulative token stream so a freeze can be replayed
      // host-side through both this matcher and the RN reference (definitive
      // parity check). Copy the string into a *.test.ts/_test.dart fixture.
      Log.d('asr', 'TOKENSTREAM surah=$_ctxSurah n=${tokens.length}: ${tokens.join(' ')}');
    }
    // Clear the moving marker so it doesn't sit lit on the last word after the
    // session ends (the read/skip washes stay to review what was recited).
    _asrCurrentLocation = null;
    _asrCurrentLocations = const {};
    _asrTimer?.cancel();
    _engine.releaseMic(stopAsrListening);
    Log.d('asr', 'listening stopped');
    Log.flushFile();
    _notify();
  }

  /// DEBUG: feed a bundled recording through the live path (streaming sherpa →
  /// phoneme matcher) so the marker can be traced without reciting live.
  Future<void> runFileDiagnostic(String assetPath, {String? label}) async {
    if (_asrActive || _asrStarting) return;
    _asrStarting = true;
    _asrError = null;
    _notify();
    try {
      final asr = await _engine.ready();
      await _loadClipAndMatcher(_ctxSurah);
      asr.resetStream();
      final clip = await loadWavAsset(assetPath);
      Log.d('diag', '=== FILE DIAGNOSTIC ${label ?? assetPath} '
          '(${clip.seconds.toStringAsFixed(1)}s, surah $_ctxSurah) ===');
      _asrActive = true;
      _asrStarting = false;
      _startAsrTimer();
      _notify();
      const chunk = 1600; // 100ms
      for (var off = 0; off < clip.pcm.length; off += chunk) {
        if (!_asrActive) break;
        final end = off + chunk < clip.pcm.length ? off + chunk : clip.pcm.length;
        final tokens = asr.accept(Int16List.sublistView(clip.pcm, off, end));
        if (tokens.isNotEmpty) _applyOut(_matcher!.apply(tokens));
        await Future.delayed(const Duration(milliseconds: 5));
      }
      final tail = asr.finish();
      if (tail.isNotEmpty) _applyOut(_matcher!.apply(tail));
      Log.d('diag', '=== FILE DIAGNOSTIC done: cur=$_asrCurrentLocation read=${_asrRead.length} ===');
    } catch (e, st) {
      Log.e('diag', e, st);
      _asrError = e.toString();
    } finally {
      _asrTimer?.cancel();
      _asrActive = false;
      _asrStarting = false;
      await Log.flushFile();
      _notify();
    }
  }

  /// DEBUG: transcribe a clip through streaming sherpa and log the phonemes.
  Future<void> runSherpaTest(String assetPath, {String? label}) async {
    if (_sherpaBusy) return;
    _sherpaBusy = true;
    _notify();
    try {
      Log.d('sherpa', '=== SHERPA TEST ${label ?? assetPath} ===');
      final clip = await loadWavAsset(assetPath);
      final asr = await _engine.ready();
      asr.resetStream();
      final sw = Stopwatch()..start();
      const chunk = 3200;
      for (var off = 0; off < clip.pcm.length; off += chunk) {
        final end = off + chunk < clip.pcm.length ? off + chunk : clip.pcm.length;
        asr.accept(Int16List.sublistView(clip.pcm, off, end));
      }
      final tokens = asr.finish();
      Log.d('sherpa', 'HEARD (${sw.elapsedMilliseconds}ms, ${tokens.length} phonemes): "${tokens.join()}"');
      await Log.flushFile();
    } catch (e, st) {
      Log.e('sherpa', e, st);
    } finally {
      _sherpaBusy = false;
      _notify();
    }
  }

  bool _sherpaBusy = false;
  bool get sherpaBusy => _sherpaBusy;

  bool _evalBusy = false;
  bool get evalBusy => _evalBusy;

  /// Run the full eval suite (every bundled clip → pipeline → timestamped eval
  /// file + deep log). Used by the Debug Log "Run eval" button / ps1 harness.
  Future<void> runEval() async {
    if (_evalBusy || _asrActive || _asrStarting) return;
    _evalBusy = true;
    _notify();
    try {
      final asr = await _engine.ready();
      final path = await EvalRunner(asr, _engine.units).runAll();
      Log.d('eval', 'eval written: $path');
    } catch (e, st) {
      Log.e('eval', e, st);
    } finally {
      _evalBusy = false;
      _notify();
    }
  }

  void stopFileDiagnostic() {
    if (_asrActive) {
      _asrActive = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _asrTimer?.cancel();
    asrNavigate.dispose();
    markerTick.dispose();
    if (_asrActive) _engine.mic.stop(); // release the shared mic; the engine lives on
    super.dispose();
  }
}

/// Collapse runs of a repeated char to one, matching the matcher's private
/// `_collapse` (phoneme_matcher.dart). Kept identical, not exported, so probe
/// snippets are normalized the same way the matcher normalizes its reference.
/// Regex hoisted so it compiles once, not per token on every chunk.
final RegExp _collapseTokRe = RegExp(r'(.)\1+');
String _collapseTok(String s) => s.replaceAllMapped(_collapseTokRe, (m) => m[1]!);

/// The most-recent [count] collapsed phoneme tokens joined into one string — the
/// "what the model just heard" footer ticker. The tokens carry their own
/// harakāt, so a plain `join('')` reads approximately as the recited word. PURE
/// (host-testable); shared by all three recitation footers.
String recentHeard(List<String> tail, {int count = 12}) =>
    (tail.length <= count ? tail : tail.sublist(tail.length - count)).join();

/// Advance the moving read-marker from [marker] toward the matcher's [cursor]
/// WITHOUT teleporting: after a waqf pause the model bursts several next-verse
/// words at once, so close HALF the gap per chunk (snappy catch-up) for a
/// small-to-medium gap, jump a big gap (>8) at once as a real relocation, and
/// follow a backward move immediately. PURE + host-tested; shared by the Quran
/// and du'a readers so their catch-up tuning can never drift apart.
int advanceMarker(int marker, int cursor) {
  if (cursor <= marker) return cursor;
  final gap = cursor - marker;
  return marker +
      (gap > 8
          ? gap
          : gap > 2
              ? (gap / 2).ceil()
              : 1);
}

/// PURE stall test (host-testable). The live matcher has stopped tracking the
/// current surah if the mic is hearing speech ([rms] ≥ [rmsFloor]) AND either it
/// is anchored but hasn't advanced for [stallTokens] new tokens, or it never
/// anchored after [neverAnchorTokens] of audio.
bool reacqStalled({
  required double rms,
  required double rmsFloor,
  required bool anchored,
  required int tokens,
  required int lastProgressTokens,
  required int stallTokens,
  required int neverAnchorTokens,
}) {
  if (rms < rmsFloor) return false;
  if (anchored) return tokens - lastProgressTokens >= stallTokens;
  return tokens >= neverAnchorTokens;
}

/// Outcome of one re-acquisition probe: whether to switch, and the updated
/// debounce state to carry into the next probe.
class ReacquireDecision {
  final int? switchTo; // surah to switch to, or null to stay
  final int winner; // best qualifying challenger this probe (-1 = none)
  final int winStreak; // consecutive probes [winner] has led
  const ReacquireDecision(this.switchTo, this.winner, this.winStreak);
}

/// PURE decision for cross-surah re-acquisition (host-testable — no ReadingState,
/// no platform channels). Given per-token alignment [scores] for each candidate
/// surah (including [current]) and the running debounce state, decide whether to
/// switch surah. A challenger is nominated only when it (a) is not the current
/// surah, (b) clears the absolute [switchFloor], and (c) beats the current
/// surah's score by [switchMargin]. A nominated challenger must win
/// [confirmProbes] CONSECUTIVE probes before the switch fires; any probe with no
/// qualifying challenger, or a change of winner, resets the streak.
ReacquireDecision decideReacquire({
  required int current,
  required Map<int, double> scores,
  required int prevWinner,
  required int prevWinStreak,
  required double switchMargin,
  required double switchFloor,
  required int confirmProbes,
}) {
  final currentScore = scores[current] ?? 0.0;
  int challenger = -1;
  double best = double.negativeInfinity;
  scores.forEach((surah, score) {
    if (surah == current) return;
    if (score > best) {
      best = score;
      challenger = surah;
    }
  });
  final qualifies =
      challenger != -1 && best >= switchFloor && best >= currentScore + switchMargin;
  if (!qualifies) return const ReacquireDecision(null, -1, 0);
  final streak = challenger == prevWinner ? prevWinStreak + 1 : 1;
  final switchTo = streak >= confirmProbes ? challenger : null;
  return ReacquireDecision(switchTo, challenger, streak);
}

String _ayahKey(String loc) {
  final p = loc.split(':');
  return '${p[0]}:${p[1]}';
}

/// Words to REVEAL stepping forward through [page] (reading order): the first
/// still-hidden word AFTER [anchorIndex] (the furthest point already reached —
/// read/revealed/marker), or — by āyah — every still-hidden word of its āyah. A
/// word the reciter already got ([read]) counts as shown and is never
/// re-revealed. [anchorIndex] = -1 reveals from the page top (unchanged). If
/// nothing is hidden after the anchor, falls back to the first hidden word
/// overall so a tap still reveals something.
Set<String> revealForwardLocs(
    List<String> page, Set<String> revealed, Set<String> read,
    {required bool ayah, int anchorIndex = -1}) {
  bool hidden(String loc) => !revealed.contains(loc) && !read.contains(loc);
  String? first;
  for (var i = anchorIndex + 1; i < page.length; i++) {
    if (hidden(page[i])) {
      first = page[i];
      break;
    }
  }
  if (first == null) {
    for (final loc in page) {
      if (hidden(loc)) {
        first = loc;
        break;
      }
    }
  }
  if (first == null) return const {};
  if (!ayah) return {first};
  final key = _ayahKey(first);
  return {
    for (final l in page)
      if (_ayahKey(l) == key && hidden(l)) l
  };
}

/// Words to HIDE stepping back: the last MANUALLY revealed word (in [revealed]
/// but not in [read]), or — by āyah — its āyah's manual reveals. A recited word
/// ([read]) is never hidden.
Set<String> revealBackLocs(
    List<String> page, Set<String> revealed, Set<String> read,
    {required bool ayah}) {
  String? last;
  for (var i = page.length - 1; i >= 0; i--) {
    final loc = page[i];
    if (revealed.contains(loc) && !read.contains(loc)) {
      last = loc;
      break;
    }
  }
  if (last == null) return const {};
  if (!ayah) return {last};
  final key = _ayahKey(last);
  return {
    for (final l in page)
      if (_ayahKey(l) == key && revealed.contains(l) && !read.contains(l)) l
  };
}
