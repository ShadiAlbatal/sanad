import 'dart:math' as math;
import '../../util/log.dart';
import 'phoneme_align.dart';

/// Ported from the RN build's phonemeMatchSession.ts — the FOLLOW-ANYWHERE,
/// verse-windowed phoneme matcher that lit words smoothly ("like a clock").
/// Works on a per-surah phoneme clip; the caller maps word index → s:a:w.

enum WordState { pending, correct, skipped }

enum PhonemeEventType { correct, skipped, skipAttempt }

class PhonemeEvent {
  final PhonemeEventType type;
  final int wordIndex;
  const PhonemeEvent(this.type, this.wordIndex);
}

/// One surah phonetized: flat phoneme sequence + phoneme→word map + āyah starts.
class PhonemeClip {
  final int wordCount;
  final List<String> phonemes;
  final List<int> phonemeToWord;
  final List<int> ayahBoundaries; // first word index of each āyah
  const PhonemeClip({
    required this.wordCount,
    required this.phonemes,
    required this.phonemeToWord,
    required this.ayahBoundaries,
  });
}

class MatchOutput {
  final List<WordState> states;
  final int cursor;
  final List<PhonemeEvent> events;
  const MatchOutput(this.states, this.cursor, this.events);
}

// Hoisted so it is compiled ONCE, not rebuilt on every _collapse call (which
// runs per token, per chunk, ~10-25x/sec during recitation).
final RegExp _collapseRe = RegExp(r'(.)\1+');
String _collapse(String s) => s.replaceAllMapped(_collapseRe, (m) => m[1]!);

class PhonemeMatchSession {
  final int _n;
  final List<int> _phonemeToWord;
  final List<String> _ref;
  final List<int> _boundaries;
  final List<List<int>> _wordPhonemes;
  final PhonemeLocalizer _localizer;
  final double _threshold;
  final double _adv;

  // Tuning (verbatim from the RN engine).
  static const _tail = 24;
  static const _shortTail = 10;
  static const _green = 0.5;
  static const _grace = 1;
  static const _scoreFloor = 12.0;
  static const _freezeChunks = 8;
  static const _backStableNeed = 3;
  static const _backRegionSize = 2;
  static const _backJumpBig = 5;
  static const _backConfirmChunks = 6;

  List<String> _allTokens = [];
  late List<double> _wordBestFrac;
  int _head = -1;
  int _reached = -1;
  int _anchor = -1;
  int _curAyah = 0;
  int _stuckChunks = 0;
  int _lastSkipAttempt = -1;
  int _backRegion = -1;
  int _backStable = 0;
  int _displayCursor = 0;
  int _pendingBackCursor = -1;
  int _pendingBackCount = 0;
  LocResult? _lastReloc;
  final Set<int> _greenedEmitted = {};
  final Set<int> _skippedEmitted = {};
  late List<WordState> _current;

  PhonemeMatchSession(PhonemeClip clip, List<String> units, {double? threshold, double? advanceNeed})
      : _n = clip.wordCount,
        _phonemeToWord = clip.phonemeToWord,
        _ref = clip.phonemes.map(_collapse).toList(),
        _boundaries = clip.ayahBoundaries.isNotEmpty ? clip.ayahBoundaries : const [0],
        _wordPhonemes = List.generate(clip.wordCount, (_) => <int>[]),
        _threshold = threshold ?? kPhonemeThreshold,
        _adv = advanceNeed ?? 0.65,
        _localizer = PhonemeLocalizer(clip.phonemes.map(_collapse).toList(),
            (r) => clip.phonemeToWord[r], threshold: threshold ?? kPhonemeThreshold) {
    for (var i = 0; i < _phonemeToWord.length; i++) {
      _wordPhonemes[_phonemeToWord[i]].add(i);
    }
    _wordBestFrac = List<double>.filled(_n, 0);
    _current = List<WordState>.filled(_n, WordState.pending);
  }

  bool _maj(int wi) => _wordBestFrac[wi] >= _green;
  double _greenNeed(int wi) {
    final len = _wordPhonemes[wi].length;
    if (len == 0) return 1;
    return math.max(_green, math.min(len, 2) / len);
  }

  bool _majAdv(int wi) => _wordBestFrac[wi] >= math.max(_greenNeed(wi), _adv);

  int _ayahStart(int a) => _boundaries[a.clamp(0, _boundaries.length - 1)];
  int _ayahEnd(int a) => a + 1 < _boundaries.length ? _boundaries[a + 1] - 1 : _n - 1;

  /// Feed the CUMULATIVE phoneme token stream; recompute states + cursor.
  MatchOutput apply(List<String> cumulativeTokens) {
    // Store the RAW cumulative stream. Only the last [_tail] tokens are ever
    // consumed (below), and _collapse is a per-token pure function, so
    // collapsing just that tail is identical to collapsing the whole list and
    // slicing — but O(tail) per chunk instead of O(session length), avoiding the
    // quadratic re-collapse of the entire stream on every mic chunk.
    _allTokens = cumulativeTokens;
    final events = _recompute();
    return MatchOutput(List.of(_current), _displayCursor, events);
  }

  List<PhonemeEvent> _recompute() {
    final events = <PhonemeEvent>[];
    final rawTail = _allTokens.length <= _tail
        ? _allTokens
        : _allTokens.sublist(_allTokens.length - _tail);
    final tail = [for (final t in rawTail) _collapse(t)];
    _lastReloc = null;

    final vStart = _ayahStart(_curAyah);
    final vEnd = _ayahEnd(_curAyah);
    final fwdEdge = math.min(vEnd, _reached + 1 + _grace);
    final reachLo = _anchor < 0 ? 0 : math.max(_ayahStart(_curAyah), _anchor);
    final reachHi = _anchor < 0 ? _n - 1 : fwdEdge;
    var accepted = false;

    if (tail.length >= 6) {
      final loc = _localizer.localizeScored(tail);
      _lastReloc = loc;
      var use = loc;
      // Repeated-phrase rescue: the long tail can be "won" by a longer, older,
      // now-out-of-window match while newer in-window audio is also present. A
      // short recency-biased snippet, gated by the same window+score check, only
      // rescues a chunk the primary was about to reject.
      if (!(loc.word >= reachLo && loc.word <= reachHi && loc.score >= _scoreFloor) && tail.length >= _shortTail) {
        final shortLoc = _localizer.localizeScored(tail.sublist(tail.length - _shortTail));
        if (shortLoc.word >= reachLo && shortLoc.word <= reachHi && shortLoc.score >= _scoreFloor) {
          use = shortLoc;
        }
      }
      if (use.word >= reachLo && use.word <= reachHi && use.score >= _scoreFloor) {
        accepted = true;
        final wLo = math.max(reachLo, use.word - 3);
        final wHi = math.min(reachHi, use.word + 6);
        final refLo = _wordPhonemes[wLo][0];
        final refHi = _wordPhonemes[wHi][_wordPhonemes[wHi].length - 1];
        final pairs = nwAlign(tail, _ref.sublist(refLo, refHi + 1), 0, _threshold)
            .map((p) => [p[0], p[1] + refLo])
            .toList();
        final matchedRef = {for (final p in pairs) p[1]};
        for (var wi = wLo; wi <= wHi; wi++) {
          final ph = _wordPhonemes[wi];
          if (ph.isEmpty) continue;
          var hit = 0;
          for (final i in ph) {
            if (matchedRef.contains(i)) hit++;
          }
          final fr = hit / ph.length;
          if (fr > _wordBestFrac[wi]) _wordBestFrac[wi] = fr;
        }
        var lastRef = -1;
        for (final p in pairs) {
          if (p[1] > lastRef) lastRef = p[1];
        }
        if (lastRef >= 0) _head = _phonemeToWord[lastRef];
      }
    }

    // Backward re-anchor probe.
    final lr = _lastReloc;
    if (_anchor >= 0 && lr != null && lr.word >= 0 && lr.word < reachLo && lr.score >= _scoreFloor) {
      final region = (lr.word / _backRegionSize).floor();
      if (region == _backRegion) {
        _backStable++;
      } else {
        _backRegion = region;
        _backStable = 1;
      }
      if (_backStable >= _backStableNeed) {
        final pLo = math.max(vStart, lr.word - 3);
        final pHi = math.min(reachLo - 1, lr.word + 4);
        if (pLo < pHi) {
          final refLo = _wordPhonemes[pLo][0];
          final refHi = _wordPhonemes[pHi][_wordPhonemes[pHi].length - 1];
          final pairs = nwAlign(tail, _ref.sublist(refLo, refHi + 1), 0, _threshold)
              .map((p) => [p[0], p[1] + refLo])
              .toList();
          final matchedRef = {for (final p in pairs) p[1]};
          for (var wi = pLo; wi <= pHi; wi++) {
            final ph = _wordPhonemes[wi];
            if (ph.isEmpty) continue;
            var hit = 0;
            for (final i in ph) {
              if (matchedRef.contains(i)) hit++;
            }
            final fr = hit / ph.length;
            if (fr > _wordBestFrac[wi]) _wordBestFrac[wi] = fr;
          }
          for (var wi = pLo; wi < pHi; wi++) {
            if (_majAdv(wi) && _majAdv(wi + 1)) {
              _anchor = wi;
              _backRegion = -1;
              _backStable = 0;
              Log.d('recite', 'ANCHOR back -> w$wi (re-read earlier)');
              break;
            }
          }
        }
      }
    } else {
      _backRegion = -1;
      _backStable = 0;
    }

    // Lock the mid-verse anchor at the first two consecutive green words.
    if (_anchor < 0) {
      for (var i = 0; i < _n - 1; i++) {
        if (_majAdv(i) && _majAdv(i + 1)) {
          _anchor = i;
          _reached = i - 1;
          Log.d('recite', 'ANCHOR lock @w$i (ayah $_curAyah)');
          break;
        }
      }
    }

    // Advance the strict frontier one step per chunk (grace tolerance = 1).
    final prevReached = _reached;
    if (_anchor >= 0) {
      final edge = math.min(vEnd, _reached + 1 + _grace);
      final i = _reached + 1;
      if (i <= edge && _majAdv(i)) {
        _reached = i;
      } else if (i <= edge) {
        var k = 1;
        while (k <= _grace && i + k <= edge && !_majAdv(i + k)) {
          k++;
        }
        if (k <= _grace && i + k <= edge && _majAdv(i + k)) _reached = i + k;
      }
    }
    if (_reached >= vEnd && _curAyah + 1 < _boundaries.length) {
      _curAyah = _curAyah + 1;
      Log.d('recite', 'verse slide -> ayah $_curAyah (frontier complete)');
    }

    // Marker position (smoothed).
    final rawCursor = _anchor < 0
        ? math.max(0, _head)
        : _head >= 0
            ? math.min(_head, _reached + 1)
            : math.max(0, _reached + 1);
    if (rawCursor >= _displayCursor || _displayCursor - rawCursor >= _backJumpBig) {
      _displayCursor = rawCursor;
      _pendingBackCursor = -1;
      _pendingBackCount = 0;
    } else if (rawCursor == _pendingBackCursor) {
      _pendingBackCount++;
      if (_pendingBackCount >= _backConfirmChunks) _displayCursor = rawCursor;
    } else {
      _pendingBackCursor = rawCursor;
      _pendingBackCount = 1;
    }

    // Freeze → one skip-attempt.
    final advanced = _reached > prevReached;
    final speaking = tail.length >= 6;
    if (_anchor < 0) {
      _stuckChunks = 0;
    } else if (advanced) {
      _stuckChunks = 0;
      _lastSkipAttempt = -1;
    } else if (speaking && !accepted) {
      _stuckChunks++;
    } else {
      _stuckChunks = 0;
    }
    if (_stuckChunks >= _freezeChunks && _reached + 1 != _lastSkipAttempt) {
      _lastSkipAttempt = _reached + 1;
      events.add(PhonemeEvent(PhonemeEventType.skipAttempt, _reached + 1));
      // Recovery from a hard stall. A word the model can't confidently align — a
      // rare/elongated word, a mispronunciation, or a matn/reference divergence —
      // otherwise walls the frontier for the REST of the recitation: the "stuck,
      // won't move whatever I do" freeze (device-confirmed on long hadith clips,
      // 100-189 words, which are ONE flat span with no ayah window to reset on).
      // After ~0.64s stuck WHILE speaking, step the frontier one word past the
      // wall; it renders as skipped (not green). Self-healing: if that word is in
      // fact being recited, its monotonic _wordBestFrac keeps rising and _maj
      // flips it back to green retroactively — so a false skip corrects itself,
      // while a genuine gap just lets follow-along move on. Bounded by the span
      // end and re-armed only after another _freezeChunks of stall, so it steps
      // ~1 word / 0.64s of stuck speech, never a runaway skip.
      //
      // Gated to FLAT clips (one span — hadith & du'ā). Qur'an clips carry real
      // āyah boundaries and their own device-tuned window/rescue machinery for
      // repeated-phrase stalls (the RN-parity path); stepping the frontier there
      // fights that logic, so leave Qur'an untouched.
      if (_boundaries.length <= 1 && _reached < vEnd) {
        _reached++;
        _stuckChunks = 0;
        Log.d('recite', 'SKIP-ADVANCE past w$_reached (stuck $_freezeChunks+ chunks, speaking)');
      }
    }

    // Word states.
    for (var wi = 0; wi < _n; wi++) {
      final WordState st;
      if (_maj(wi) && wi <= _reached && (_anchor < 0 || wi >= _anchor)) {
        st = WordState.correct;
      } else if (_anchor >= 0 && wi >= _anchor && wi <= _reached) {
        st = WordState.skipped;
      } else {
        st = WordState.pending;
      }
      _current[wi] = st;
      if (st == WordState.correct && !_greenedEmitted.contains(wi)) {
        _greenedEmitted.add(wi);
        events.add(PhonemeEvent(PhonemeEventType.correct, wi));
      } else if (st == WordState.skipped && !_skippedEmitted.contains(wi) && !_greenedEmitted.contains(wi)) {
        _skippedEmitted.add(wi);
        events.add(PhonemeEvent(PhonemeEventType.skipped, wi));
        // Diagnostic: was it the model (frac~0 → no phonemes emitted for this
        // word) or the matcher/threshold (frac decent but under the green bar)?
        Log.d('recite', 'SKIP w$wi frac=${_wordBestFrac[wi].toStringAsFixed(2)} '
            'need=${math.max(_greenNeed(wi), _adv).toStringAsFixed(2)} phonemes=${_wordPhonemes[wi].length}');
      }
    }
    return events;
  }

  int get cursor => _displayCursor;

  // Diagnostics (latency investigation) — expose the internals that decide
  // whether a verse-end freeze is the model not emitting vs the display clamp.
  int get head => _head;
  int get reached => _reached;
  int get curAyah => _curAyah;
  int get lastLocWord => _lastReloc?.word ?? -1;
  double get lastLocScore => _lastReloc?.score ?? -1;

  /// True once the matcher has locked onto the recitation. Before this the cursor
  /// sits at word 0 (a placeholder) — the marker must NOT show yet, or it looks
  /// pinned to the first word of the loaded surah.
  bool get anchored => _anchor >= 0;

  /// The word the session anchored on (−1 before lock-on). The post-recitation
  /// tajwīd review bounds its alignment to [anchor]..[reached] so un-recited
  /// earlier reference phonemes don't corrupt the path on a mid-start recitation.
  int get anchor => _anchor;

  void reset() {
    _allTokens = [];
    for (var i = 0; i < _wordBestFrac.length; i++) {
      _wordBestFrac[i] = 0;
    }
    _current = List<WordState>.filled(_n, WordState.pending);
    _head = -1;
    _reached = -1;
    _anchor = -1;
    _curAyah = 0;
    _stuckChunks = 0;
    _lastSkipAttempt = -1;
    _lastReloc = null;
    _backRegion = -1;
    _backStable = 0;
    _displayCursor = 0;
    _pendingBackCursor = -1;
    _pendingBackCount = 0;
    _greenedEmitted.clear();
    _skippedEmitted.clear();
  }
}
