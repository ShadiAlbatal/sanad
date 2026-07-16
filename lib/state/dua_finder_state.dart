import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../data/duas.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/phoneme_align.dart' show PhonemeLocalizer;
import '../services/asr/phoneme_corpus.dart';
import '../state/reading_state.dart' show recentHeard;
import '../util/log.dart';

/// "Shazam for du'ās": listen on the shared mic, phoneme-localize the recent
/// token tail against EVERY du'a at once, and once one clearly wins for several
/// consecutive probes, name it so the list screen can open its reader and keep
/// following along. A read-only sibling of [DuaReadingState] — it never anchors
/// or reviews, it only picks WHICH du'a is being recited.
///
/// Uses the app-global [AsrEngine] (the ONE shared [SherpaAsr] + mic, also used
/// by the Quran [ReadingState] and the du'a reader). No second phoneme model is
/// ever created; this state only STARTS/STOPS the shared mic and hands it off to
/// the reader via the single-owner [AsrEngine.claimMic] mechanism.
class DuaFinderState extends ChangeNotifier {
  DuaFinderState(this._engine);

  final AsrEngine _engine;

  // One localizer per du'a, built once from its phoneme clip (cached across
  // sessions). Mirrors ReadingState._probeLocalizer's collapsed-phoneme setup.
  final Map<String, PhonemeLocalizer> _localizers = {};

  bool _listening = false;
  bool _starting = false;
  bool _heardSomething = false;
  String? _identifiedDuaId;
  String? _error;

  static const double _rmsFloor = 120;
  double _lastRms = 0; // read-only footer telemetry (see [level])
  String? _leadingDuaId; // top-scoring candidate from the last probe (see [leadingDuaId])
  List<String> _heardTail = const []; // recent collapsed tokens for the footer "heard" ticker (read-only)

  // Debounce state for [identifyDua] across probes.
  String _winner = '';
  int _winStreak = 0;

  // Tunables — conservative, DEVICE-PENDING (floor/margin/confirm need on-device
  // tuning against real recitations, exactly like the cross-surah re-acquire
  // thresholds). A pick fires only when the top du'a's per-token localizer score
  // clears [_floor], beats the runner-up by [_margin], and holds for [_confirm]
  // consecutive probes.
  static const int _probeTail = 24; // recent collapsed tokens fed to each localizer
  static const double _floor = 1.2; // per-token score the winner must clear
  static const double _margin = 0.4; // per-token lead over the 2nd-best du'a
  static const int _confirm = 3; // consecutive winning probes before we commit

  bool get listening => _listening;
  bool get starting => _starting;
  bool get heardSomething => _heardSomething;
  String? get identifiedDuaId => _identifiedDuaId;
  String? get error => _error;

  // Live footer telemetry (read-only). Same device-tunable 0..1 mic level as the
  // readers; leadingDuaId is the current best-guess du'a (top localizer score),
  // shown as "Hearing: <title>?" before a pick is committed.
  double get level =>
      _listening ? ((_lastRms - _rmsFloor) / 1600).clamp(0.0, 1.0) : 0;
  String? get leadingDuaId => _listening ? _leadingDuaId : null;

  // Most-recent decoded phonemes for the footer "heard" ticker; '' when idle.
  String get heard => _listening ? recentHeard(_heardTail) : '';

  bool _disposed = false;

  Future<void> start() async {
    if (_listening || _starting) return;
    _starting = true;
    _error = null;
    _identifiedDuaId = null;
    _heardSomething = false;
    _heardTail = const [];
    _winner = '';
    _winStreak = 0;
    notifyListeners();
    try {
      final granted = await _engine.mic.hasPermission();
      if (!granted) {
        _error = 'Microphone permission denied';
        return;
      }
      await _engine.claimMic(stop); // stop a Quran/du'a session still holding the shared mic
      final asr = await _engine.ready();
      // The screen can be popped (dispose) while ready() awaits — release the
      // shared mic (not started here) and bail. The engine is NOT disposed.
      if (_disposed) {
        await _engine.mic.stop();
        return;
      }
      await _ensureLocalizers();
      asr.resetStream();
      await _engine.mic.start(_onPcm);
      _listening = true;
      Log.d('duafind', 'listening started (${_localizers.length} duas)');
    } catch (e, st) {
      Log.e('duafind', e, st);
      _error = e.toString();
      try {
        await _engine.mic.stop();
      } catch (_) {}
      _listening = false;
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() async {
    if (!_listening) return;
    await _engine.mic.stop();
    _listening = false;
    _engine.releaseMic(stop);
    Log.d('duafind', 'listening stopped');
    if (!_disposed) notifyListeners();
  }

  /// Called by the list screen after it has navigated to the matched reader, so
  /// returning to the list doesn't re-fire the open. Silent (no rebuild needed —
  /// the identify notify already reverted the header to its idle control).
  void clearIdentified() {
    _identifiedDuaId = null;
    _winner = '';
    _winStreak = 0;
  }

  Future<void> _ensureLocalizers() async {
    if (_localizers.isNotEmpty) return;
    for (final dua in duas) {
      final clip = await loadDuaClip(dua.id);
      _localizers[dua.id] = PhonemeLocalizer(
        clip.clip.phonemes.map(_collapse).toList(),
        (r) => clip.clip.phonemeToWord[r],
      );
    }
  }

  void _onPcm(Int16List pcm) {
    // !_listening drops buffered chunks after a pick/stop even though the screen
    // clears _identifiedDuaId synchronously on identify.
    if (_disposed || !_listening) return;
    final asr = _engine.asrOrNull;
    if (asr == null) return;
    final tokens = asr.accept(pcm);
    var sumsq = 0.0;
    for (final s in pcm) {
      sumsq += s * s;
    }
    _lastRms = pcm.isEmpty ? 0 : math.sqrt(sumsq / pcm.length);
    if (tokens.isEmpty) return;
    if (!_heardSomething) {
      _heardSomething = true;
      notifyListeners();
    }
    final tailStart = tokens.length <= _probeTail ? 0 : tokens.length - _probeTail;
    final tail = [for (var i = tailStart; i < tokens.length; i++) _collapse(tokens[i])];
    _heardTail = tail;
    if (tail.length < 6) return;

    final scores = <String, double>{};
    var leadScore = double.negativeInfinity;
    for (final e in _localizers.entries) {
      final s = e.value.localizeScored(tail).score / tail.length;
      scores[e.key] = s;
      if (s > leadScore) {
        leadScore = s;
        _leadingDuaId = e.key;
      }
    }
    final decision = identifyDua(
      scores: scores,
      prevWinner: _winner,
      prevStreak: _winStreak,
      floor: _floor,
      margin: _margin,
      confirm: _confirm,
    );
    _winner = decision.winner;
    _winStreak = decision.streak;
    Log.d('duafind',
        'probe streak=${decision.winner.isEmpty ? "-" : decision.winner}x${decision.streak} '
        'scores=${[for (final id in _localizers.keys) '$id:${(scores[id] ?? 0).toStringAsFixed(2)}'].join(' ')}');
    final pick = decision.pick;
    if (pick != null) {
      _identifiedDuaId = pick;
      _listening = false;
      unawaited(_engine.mic.stop()); // release the mic; the reader re-claims it on autoStart
      Log.d('duafind', 'IDENTIFIED $pick');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _engine.releaseMic(stop);
    if (_listening) _engine.mic.stop(); // release the shared mic; the engine lives on
    super.dispose();
  }
}

/// Collapse runs of a repeated char to one — identical to the matcher's private
/// `_collapse` (phoneme_matcher.dart) so probe snippets are normalized the same
/// way the reference phonemes are.
String _collapse(String s) => s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

/// Outcome of one identify probe: the du'a to open (or null), plus the debounce
/// state to carry into the next probe.
class DuaIdentifyDecision {
  final String? pick; // du'a id to open, or null to keep listening
  final String winner; // top qualifying du'a this probe ('' = none)
  final int streak; // consecutive probes [winner] has qualified
  const DuaIdentifyDecision(this.pick, this.winner, this.streak);
}

/// PURE identify decision (host-testable — no state, no platform channels).
/// Mirrors [decideReacquire] but with NO "current" baseline: among per-token
/// localizer [scores], the top du'a QUALIFIES only when it (a) clears the
/// absolute [floor] and (b) beats the 2nd-best du'a by [margin]. A qualifying
/// winner must hold for [confirm] CONSECUTIVE probes before it is picked; a probe
/// with no qualifier, or a change of winner, resets the streak.
DuaIdentifyDecision identifyDua({
  required Map<String, double> scores,
  required String prevWinner,
  required int prevStreak,
  required double floor,
  required double margin,
  required int confirm,
}) {
  String top = '';
  double best = double.negativeInfinity;
  double second = double.negativeInfinity;
  scores.forEach((id, score) {
    if (score > best) {
      second = best;
      best = score;
      top = id;
    } else if (score > second) {
      second = score;
    }
  });
  final qualifies = top.isNotEmpty && best >= floor && best >= second + margin;
  if (!qualifies) return const DuaIdentifyDecision(null, '', 0);
  final streak = top == prevWinner ? prevStreak + 1 : 1;
  final pick = streak >= confirm ? top : null;
  return DuaIdentifyDecision(pick, top, streak);
}
