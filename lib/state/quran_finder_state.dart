import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/phoneme_finder.dart' show foldBestScores, decideFindBest;
import '../services/asr/quran_search.dart';
import '../state/reading_state.dart' show recentHeard;
import '../util/log.dart';

/// "Shazam for the Quran": listen on the shared mic, phoneme-search the recent
/// spoken tail against ALL 114 surahs / ~6,236 verses, and once one verse clearly
/// wins for several consecutive probes name it so the list screen opens the reader
/// at that verse's page. A read-only sibling of [HadithFinderState]/[DuaFinderState]
/// — same mic lifecycle, level telemetry and streak-debounced pick — scoring via
/// the pre-built global [QuranSearch] index instead of per-item localizers. It only
/// picks WHICH verse is being recited; the reader's own follow-along ([ReadingState])
/// does the word-level tracking once opened.
///
/// Uses the app-global [AsrEngine] (the ONE shared phoneme model + mic, also used by
/// the Quran reader's follow-along and the du'a/hadith finders). No second ASR model
/// is created; this state only STARTS/STOPS the shared mic via the single-owner
/// [AsrEngine.claimMic], so a live reader session is preempted when the list mic
/// starts and vice versa.
class QuranFinderState extends ChangeNotifier {
  QuranFinderState(this._engine);

  final AsrEngine _engine;

  Future<QuranSearch>? _loading;
  QuranSearch? _search;

  bool _listening = false;
  bool _starting = false;
  bool _heardSomething = false;
  String? _error;

  static const double _rmsFloor = 120;
  double _lastRms = 0; // read-only footer telemetry (see [level])
  int _prevTokens = 0; // cumulative token count last probe — for the "heard delta" trace
  List<String> _heardTail = const []; // recent collapsed tokens (query + "heard" ticker)
  List<QuranCandidate> _candidates = const []; // ALWAYS renderable — never a dead end
  Map<String, Set<String>> _candidateMatched = const {}; // id -> highlighted words
  QuranCandidate? _pick; // committed confident match; consume via clearPick()

  // BEST-EVER peak score each verse id has reached this listening session. The pick
  // gate runs over THIS (not the current probe) so a strong earlier match survives
  // the rolling window decaying past it (mirrors the hadith/du'a finders). Reset
  // each start().
  final Map<String, double> _bestScore = {};

  // Streak-debounce carried across probes (mirrors HadithFinderState).
  String? _winner; // verse id ("2:255")
  int _winStreak = 0;

  // Tunables — DEVICE-PENDING (provisional; the confidence bar floor/margin lives in
  // [QuranSearch] and is gated over the BEST-EVER peaks via [decideFindBest]). This
  // state adds two guards on top: a query MUST reach [_minQueryLen] collapsed
  // phonemes before any pick, and the same verse must win [_confirm] consecutive
  // probes — without them a single spurious high-margin snapshot could auto-open the
  // wrong verse. Quran verses vary from a few words to a page, so the window is
  // sized for a short-to-medium verse; these still need on-device tuning like every
  // ASR threshold here.
  static const int _probeTail = 48; // trailing collapsed tokens fed to the finder
  static const int _minQueryLen = 24; // ~6 words before a pick is allowed
  static const int _confirm = 3; // consecutive winning probes before we commit

  bool get listening => _listening;
  bool get starting => _starting;
  bool get heardSomething => _heardSomething;
  String? get error => _error;

  // Ranked candidates from the last probe — always available to render.
  List<QuranCandidate> get candidates => _listening ? _candidates : const [];
  QuranCandidate? get pick => _pick;

  /// The recited words matched on verse candidate [id] — bolded on its row exactly
  /// like a typed hit. Empty (plain text) until a probe has scored it.
  Set<String> matchedWords(String id) => _candidateMatched[id] ?? const {};

  // Live footer telemetry (read-only). Same device-tunable 0..1 mic level as the
  // readers; leading is the current best guess shown before a pick is committed.
  double get level =>
      _listening ? ((_lastRms - _rmsFloor) / 1600).clamp(0.0, 1.0) : 0;
  QuranCandidate? get leading =>
      _listening && _candidates.isNotEmpty ? _candidates.first : null;

  String get heard => _listening ? recentHeard(_heardTail) : '';

  bool _disposed = false;

  Future<QuranSearch> _ensureSearch() =>
      _loading ??= loadQuranSearch().then((s) => _search = s);

  /// Kick off the (cached, off-thread) index build when the Quran tab first opens,
  /// so the first mic tap doesn't pay the ~114-file decode.
  void preload() {
    if (_search != null) return;
    unawaited(_ensureSearch());
  }

  Future<void> start() async {
    if (_listening || _starting) return;
    _starting = true;
    _error = null;
    _pick = null;
    _heardSomething = false;
    _heardTail = const [];
    _candidates = const [];
    _candidateMatched = const {};
    _bestScore.clear();
    _winner = null;
    _winStreak = 0;
    _prevTokens = 0;
    notifyListeners();
    Log.d('quranfind', 'START requested (reason=user-tap, tab=Quran)');
    try {
      final granted = await _engine.mic.hasPermission();
      Log.d('quranfind', 'mic permission granted=$granted');
      if (!granted) {
        _error = 'Microphone permission denied';
        return;
      }
      await _engine.claimMic(stop, owner: 'quran-finder'); // stop a reader/du'a session still holding the shared mic
      final asr = await _engine.ready();
      final search = _search ?? await _ensureSearch();
      // The screen can be popped (dispose) while the awaits resolve — release the
      // shared mic (not started here) and bail. The engine is NOT disposed.
      if (_disposed) {
        Log.d('quranfind', 'disposed during start — releasing mic, bail');
        await _engine.mic.stop();
        return;
      }
      _search = search;
      asr.resetStream();
      await _engine.mic.start(_onPcm);
      _listening = true;
      Log.d('quranfind', 'listening started (${search.verseCount} verses, '
          'minLen=$_minQueryLen confirm=$_confirm floor=${search.floor} margin=${search.margin})');
    } catch (e, st) {
      Log.e('quranfind', e, st);
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
    Log.d('quranfind', 'listening stopped');
    Log.flushFile();
    if (!_disposed) notifyListeners();
  }

  /// Called by the list screen after it has navigated to the matched reader, so
  /// returning doesn't re-fire the open.
  void clearPick() {
    _pick = null;
    _winner = null;
    _winStreak = 0;
  }

  void _onPcm(Int16List pcm) {
    // !_listening drops buffered chunks after a pick/stop.
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
    if (tokens.length > _prevTokens) {
      Log.t('quranphon', '+${tokens.length - _prevTokens} "${tokens.sublist(_prevTokens).join()}" '
          '(total=${tokens.length} rms=${_lastRms.toStringAsFixed(0)})');
    }
    _prevTokens = tokens.length;
    if (tokens.isEmpty) return;
    if (!_heardSomething) {
      _heardSomething = true;
      Log.d('quranfind', 'first audio decoded (rms=${_lastRms.toStringAsFixed(0)})');
    }

    final tailStart = tokens.length <= _probeTail ? 0 : tokens.length - _probeTail;
    final tail = [for (var i = tailStart; i < tokens.length; i++) _collapse(tokens[i])];
    _heardTail = tail;

    final result = search.find(tail);
    _candidates = result.candidates; // live list stays the CURRENT probe — never a dead end
    // Matched words for ONLY the shown candidates (top ~5), for per-row highlight.
    _candidateMatched = {for (final c in _candidates) c.id: search.matchedWords(c.id, tail)};

    foldBestScores(_bestScore, [for (final c in _candidates) MapEntry(c.id, c.score)],
        queryLen: tail.length, minQueryLen: _minQueryLen);
    final confidentId =
        decideFindBest(_bestScore, dupKeyOf: search.dupKeyOf, floor: search.floor, margin: search.margin)
            .pick;

    final decision = decideQuranPick(
      queryLen: tail.length,
      confident: confidentId,
      minQueryLen: _minQueryLen,
      prevWinner: _winner,
      prevStreak: _winStreak,
      confirm: _confirm,
    );
    _winner = decision.winner;
    _winStreak = decision.streak;
    final picked = decision.pick;

    final top = _candidates.take(3).map((c) => '${c.id}:${c.score.toStringAsFixed(2)}').join(' ');
    final beTop = _bestEverTop();
    final String verdict;
    if (picked != null) {
      verdict = 'PICK $picked (streak ${decision.streak}/$_confirm)';
    } else if (tail.length < _minQueryLen) {
      verdict = 'no-pick: below minLen ${tail.length}/$_minQueryLen';
    } else if (confidentId == null && beTop == null) {
      verdict = 'no-pick: no candidates';
    } else if (confidentId == null) {
      verdict = 'no-pick: best-ever ${beTop!.value.toStringAsFixed(2)} ${beTop.key} '
          'below floor ${search.floor} or margin ${search.margin}';
    } else {
      verdict = 'no-pick: streak ${decision.streak}/$_confirm (${decision.winner})';
    }
    Log.d('quranfind',
        'probe len=${tail.length} rms=${_lastRms.toStringAsFixed(0)} top=[$top] '
        'be=${beTop == null ? "-" : "${beTop.key}:${beTop.value.toStringAsFixed(2)}"} | $verdict');

    if (picked != null) {
      _pick = _candidates.firstWhere((c) => c.id == picked);
      _listening = false;
      unawaited(_engine.mic.stop()); // release the mic; the reader claims it when opened
      Log.d('quranfind', 'IDENTIFIED $picked (${_pick!.surah}:${_pick!.ayah}) page ${_pick!.page} -> open reader');
      Log.flushFile();
    }
    if (!_disposed) notifyListeners();
  }

  // Highest-scoring best-ever entry, for the decision trace only (null when empty).
  MapEntry<String, double>? _bestEverTop() {
    MapEntry<String, double>? top;
    for (final e in _bestScore.entries) {
      if (top == null || e.value > top.value) top = e;
    }
    return top;
  }

  @override
  void dispose() {
    _disposed = true;
    _engine.releaseMic(stop);
    if (_listening) {
      Log.d('quranfind', 'dispose (tab away/screen popped) -> stop mic');
      _engine.mic.stop(); // release the shared mic; the engine lives on
    }
    super.dispose();
  }
}

/// Collapse runs of a repeated char to one — identical to the finder's `_collapse`
/// so probe snippets normalize the same way the indexed phonemes do.
String _collapse(String s) => s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);

/// Outcome of one probe: the verse to open (or null), plus the debounce state to
/// carry into the next probe.
class QuranPickDecision {
  final String? pick; // verse id ("2:255") to open, or null to keep listening
  final String? winner; // confident verse id this probe (null = none)
  final int streak; // consecutive probes [winner] has held
  const QuranPickDecision(this.pick, this.winner, this.streak);
}

/// PURE pick decision (host-testable — no state, no platform channels). The
/// confidence bar (floor/margin over the runner-up) is already applied by
/// [QuranSearch.find]; this layers the two guards decideFind lacks — mirrors
/// [decideHadithPick]: the query must be long enough ([queryLen] >= [minQueryLen])
/// AND the same [confident] verse must hold for [confirm] consecutive probes before
/// it is picked. Below the length gate, or with no confident verse, the streak
/// resets.
QuranPickDecision decideQuranPick({
  required int queryLen,
  required String? confident,
  required int minQueryLen,
  required String? prevWinner,
  required int prevStreak,
  required int confirm,
}) {
  if (queryLen < minQueryLen || confident == null) {
    return const QuranPickDecision(null, null, 0);
  }
  final streak = confident == prevWinner ? prevStreak + 1 : 1;
  final pick = streak >= confirm ? confident : null;
  return QuranPickDecision(pick, confident, streak);
}
