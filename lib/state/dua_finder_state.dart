import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/dua_search.dart';
import '../services/asr/phoneme_finder.dart' show foldBestScores, decideFindBest;
import '../state/reading_state.dart' show recentHeard;
import '../util/log.dart';

/// "Shazam for du'ās": listen on the shared mic, phoneme-search the recent spoken
/// tail against the WHOLE du'a corpus (existing 5 + Hisn al-Muslim, ~260), and
/// once one clearly wins for several consecutive probes name it so the list screen
/// opens its reader and keeps following along. A read-only sibling of
/// [DuaReadingState] — it never anchors or reviews, it only picks WHICH du'a is
/// being recited.
///
/// Scales via the pre-built [DuaSearch] index (shared [PhonemeFinder]: IDF 3-gram
/// prefilter → localizer rerank) instead of the old O(N) one-localizer-per-du'a
/// loop, which did not scale past a handful. Same mic lifecycle, level telemetry
/// and streak-debounced pick as [HadithFinderState].
///
/// Uses the app-global [AsrEngine] (the ONE shared phoneme model + mic, also used
/// by the Quran/du'a readers). No second ASR model is created; this state only
/// STARTS/STOPS the shared mic via the single-owner [AsrEngine.claimMic].
class DuaFinderState extends ChangeNotifier {
  DuaFinderState(this._engine);

  final AsrEngine _engine;

  Future<DuaSearch>? _loading;
  DuaSearch? _search;

  bool _listening = false;
  bool _starting = false;
  bool _heardSomething = false;
  String? _identifiedDuaId;
  String? _error;

  static const double _rmsFloor = 120;
  double _lastRms = 0; // read-only footer telemetry (see [level])
  List<String> _heardTail = const []; // recent collapsed tokens for the footer "heard" ticker
  List<DuaCandidate> _candidates = const []; // ranked candidates from the last probe — renderable
  Map<String, Set<String>> _candidateMatched = const {}; // id -> highlighted words
  DuaCandidate? _leading; // top-scoring candidate from the last probe (see [leadingDuaTitle])

  // BEST-EVER peak score each du'a id has reached this listening session — the
  // pick gate runs over this, not the current probe, so a strong earlier match
  // survives the rolling window rolling past it (mirrors HadithFinderState). Reset
  // each start().
  final Map<String, double> _bestScore = {};

  // Streak-debounce carried across probes (mirrors HadithFinderState).
  String _winner = '';
  int _winStreak = 0;

  // Tunables — conservative, DEVICE-PENDING (floor/margin live in [DuaSearch];
  // minLen/confirm here need on-device tuning against real recitations, like every
  // ASR threshold in this app). A pick fires only when the winning du'a clears the
  // [DuaSearch] confidence bar (floor + margin over the runner-up), the query has
  // reached [_minQueryLen] collapsed phonemes, and the same du'a holds for
  // [_confirm] consecutive probes.
  static const int _probeTail = 24; // recent collapsed tokens fed to the finder
  // 12 (was) let short/generic openings shared across many du'ās (e.g. an early
  // "Allahumma"-type phrase) fold a false tied peak into TWO OR MORE unrelated
  // candidates' best-ever score before the query grew distinctive — that false
  // peak then permanently blocked the real match's margin later, even once it
  // clearly won the CURRENT probe (confirmed on a real device log 2026-07-18:
  // three unrelated du'ās tied at 0.69 by length 13-18, then the true match
  // climbed to 1.13 by length 24 but needed >1.19 to clear that stale peak by
  // margin — never picked despite winning every live probe from length 22 on).
  // 20 keeps a real margin under [_probeTail] (still pickable) while skipping
  // the short ties that caused it.
  static const int _minQueryLen = 20;
  static const int _confirm = 3; // consecutive winning probes before we commit

  bool get listening => _listening;
  bool get starting => _starting;
  bool get heardSomething => _heardSomething;
  String? get identifiedDuaId => _identifiedDuaId;
  String? get error => _error;

  // Live footer telemetry (read-only). Same device-tunable 0..1 mic level as the
  // readers; the leading du'a (top score) is shown as "Hearing: <title>?" before a
  // pick is committed.
  double get level =>
      _listening ? ((_lastRms - _rmsFloor) / 1600).clamp(0.0, 1.0) : 0;
  String? get leadingDuaId => _listening ? _leading?.id : null;
  String? get leadingDuaTitle => _listening ? _leading?.meta.title : null;

  // Ranked candidates from the last probe — always available to render (the Azkar
  // tab shows them while listening, mirroring the Hadith/Quran tabs).
  List<DuaCandidate> get candidates => _listening ? _candidates : const [];

  /// The recited words matched on candidate [id] — bolded on its row exactly like a
  /// typed hit. Empty (plain text) until a probe has scored it.
  Set<String> matchedWords(String id) => _candidateMatched[id] ?? const {};

  // Most-recent decoded phonemes for the footer "heard" ticker; '' when idle.
  String get heard => _listening ? recentHeard(_heardTail) : '';

  bool _disposed = false;

  Future<DuaSearch> _ensureSearch() =>
      _loading ??= loadDuaSearch().then((s) => _search = s);

  /// Kick off the (cached, off-thread) corpus build when the Azkar tab first
  /// opens, so the first mic tap doesn't pay the decode.
  void preload() {
    if (_search != null) return;
    unawaited(_ensureSearch());
  }

  Future<void> start() async {
    if (_listening || _starting) return;
    _starting = true;
    _error = null;
    _identifiedDuaId = null;
    _heardSomething = false;
    _heardTail = const [];
    _candidates = const [];
    _candidateMatched = const {};
    _leading = null;
    _bestScore.clear();
    _winner = '';
    _winStreak = 0;
    notifyListeners();
    try {
      final granted = await _engine.mic.hasPermission();
      if (!granted) {
        _error = 'Microphone permission denied';
        return;
      }
      await _engine.claimMic(stop, owner: 'dua-finder'); // stop a Quran/du'a session still holding the shared mic
      final asr = await _engine.ready();
      final search = _search ?? await _ensureSearch();
      // The screen can be popped (dispose) while the awaits resolve — release the
      // shared mic (not started here) and bail. The engine is NOT disposed.
      if (_disposed) {
        await _engine.mic.stop();
        return;
      }
      _search = search;
      asr.resetStream();
      await _engine.mic.start(_onPcm);
      _listening = true;
      Log.d('duafind', 'listening started (${search.docCount} duas, '
          'minLen=$_minQueryLen confirm=$_confirm floor=${search.floor} margin=${search.margin})');
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

  void _onPcm(Int16List pcm) {
    // !_listening drops buffered chunks after a pick/stop even though the screen
    // clears _identifiedDuaId synchronously on identify.
    if (_disposed || !_listening) return;
    final asr = _engine.asrOrNull;
    final search = _search;
    if (asr == null || search == null) return;
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

    final result = search.find(tail);
    _candidates = result.candidates; // live list stays the CURRENT probe — never a dead end
    // Matched words for ONLY the shown candidates (top ~5), for per-row highlight.
    _candidateMatched = {for (final c in _candidates) c.id: search.matchedWords(c.id, tail)};
    _leading = _candidates.isEmpty ? null : _candidates.first;

    // Fold this probe into the best-ever peaks (guarded by minLen), then gate over
    // the best-ever list with near-duplicate docs collapsed (mirrors the hadith
    // finder — one shared engine).
    foldBestScores(_bestScore, [for (final c in result.candidates) MapEntry(c.id, c.score)],
        queryLen: tail.length, minQueryLen: _minQueryLen);
    final confidentId =
        decideFindBest(_bestScore, dupKeyOf: search.dupKeyOf, floor: search.floor, margin: search.margin)
            .pick;

    final decision = decideDuaPick(
      queryLen: tail.length,
      confident: confidentId,
      minQueryLen: _minQueryLen,
      prevWinner: _winner,
      prevStreak: _winStreak,
      confirm: _confirm,
    );
    _winner = decision.winner;
    _winStreak = decision.streak;
    Log.d('duafind',
        'probe len=${tail.length} streak=${decision.winner.isEmpty ? "-" : decision.winner}x${decision.streak} '
        'confident=${confidentId ?? "-"} '
        'top=[${result.candidates.take(3).map((c) => '${c.id}:${c.score.toStringAsFixed(2)}').join(' ')}]');
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

/// Collapse runs of a repeated char to one — identical to the finder's `_collapse`
/// (phoneme_finder.dart) so probe snippets normalize the same way the indexed
/// phonemes do.
String _collapse(String s) => s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

/// Outcome of one identify probe: the du'a to open (or null), plus the debounce
/// state to carry into the next probe.
class DuaPickDecision {
  final String? pick; // du'a id to open, or null to keep listening
  final String winner; // confident du'a id this probe ('' = none)
  final int streak; // consecutive probes [winner] has held
  const DuaPickDecision(this.pick, this.winner, this.streak);
}

/// PURE pick decision (host-testable — no state, no platform channels). The
/// confidence bar (floor + margin over the runner-up) is already applied by
/// [DuaSearch.find]; this layers the two guards [decideFind] lacks — mirrors
/// [decideHadithPick]: the query must be long enough ([queryLen] >= [minQueryLen])
/// AND the same [confident] du'a must hold for [confirm] consecutive probes before
/// it is picked. Below the length gate, or with no confident du'a, the streak
/// resets.
DuaPickDecision decideDuaPick({
  required int queryLen,
  required String? confident,
  required int minQueryLen,
  required String prevWinner,
  required int prevStreak,
  required int confirm,
}) {
  if (queryLen < minQueryLen || confident == null) {
    return const DuaPickDecision(null, '', 0);
  }
  final streak = confident == prevWinner ? prevStreak + 1 : 1;
  final pick = streak >= confirm ? confident : null;
  return DuaPickDecision(pick, confident, streak);
}

/// Outcome of one localizer-scored identify probe (the pre-[DuaSearch] scoring
/// regime). Retained as a pinned pure reference: [identifyDua] below.
class DuaIdentifyDecision {
  final String? pick; // du'a id to open, or null to keep listening
  final String winner; // top qualifying du'a this probe ('' = none)
  final int streak; // consecutive probes [winner] has qualified
  const DuaIdentifyDecision(this.pick, this.winner, this.streak);
}

/// PURE identify decision over a full du'a→score map (host-testable). The scoring
/// engine changed to [DuaSearch] (top-K, not every du'a), but the qualify/debounce
/// MECHANISM this pins is unchanged: among per-token localizer [scores], the top
/// du'a QUALIFIES only when it clears the absolute [floor] AND beats the 2nd-best
/// by [margin]; a qualifying winner must hold for [confirm] CONSECUTIVE probes
/// before it is picked. Kept as the reference the finder-decision test exercises.
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
