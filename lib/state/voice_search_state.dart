import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/word_asr.dart';
import '../util/log.dart';

/// A poor-man's commit horizon over the offline re-decodes. The word model
/// re-transcribes the WHOLE growing buffer every interim, so the tail can wobble
/// between passes (a later pass revises an earlier guess) — which makes the
/// search ranking, and the confidence ring, flicker even while the user recites
/// correctly. Fix: commit a word only once two CONSECUTIVE decodes agree on it
/// at the same position, and never revise a committed word. Feeding only the
/// committed prefix into search gives a stable, monotonically-growing query.
///
/// Extends [committed] forward with words on which [prev] and [cur] agree,
/// starting at the current committed length (already-committed words are never
/// re-examined). Pure + host-testable. The cost is a ~1-interim lag on the last
/// word or two (they wait for confirmation) — the exact wobble we want gone.
List<String> commitStablePrefix(List<String> committed, List<String> prev, List<String> cur) {
  // A re-decode reads the WHOLE growing buffer, so CTC can revise/insert/delete an
  // EARLIER word, not just wobble the tail. If the latest decode no longer begins
  // with the committed prefix, HOLD it — appending cur[i] by index onto a stale
  // prefix would feed search a word sequence the recognizer never produced. The
  // committed prefix stays a literal prefix of the current decode; growth resumes
  // once a decode agrees with it again (never un-commits — the stability contract).
  for (var k = 0; k < committed.length; k++) {
    if (k >= cur.length || cur[k] != committed[k]) return committed;
  }
  final out = List<String>.of(committed);
  var i = out.length;
  while (i < cur.length && i < prev.length && cur[i] == prev[i]) {
    out.add(cur[i]);
    i++;
  }
  return out;
}

List<String> _words(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

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
  // Commit-horizon state: the last interim's word list, and the words committed
  // so far (agreed across two consecutive interims). See [commitStablePrefix].
  List<String> _prevWords = const [];
  List<String> _committed = const [];
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
    _prevWords = const [];
    _committed = const [];
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
        // The cancel that bumped _gen ran _handOffToFollowAlong while the model
        // was still loading (loaded==false), so it couldn't free it. Now that the
        // load finished, hand off here — UNLESS a newer start has taken over
        // (_busy/_recording set by it), which still wants the model resident.
        if (!_busy && !_recording) _handOffToFollowAlong();
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
    // Clear so a later notifyListeners (below, after the mic.stop() await —
    // which can take a second or more) doesn't hand a NEXT tab's fresh
    // _onVoice listener this session's leftover words: VoiceSearchState is
    // ONE shared instance, and the mixin only compares against its own
    // (already-cleared) searchController.text, so a stale non-empty transcript
    // reads as "new" and fires a bogus search on whatever tab is now active.
    _transcript = '';
    _prevWords = const [];
    _committed = const [];
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
      final words = _words(text);
      // Commit horizon: grow the committed prefix by the words this interim and
      // the previous one agree on, then drive search off the COMMITTED prefix so
      // the ranking/ring don't wobble on the still-settling tail. Before anything
      // has committed (the first interim), show the raw text so results still
      // appear immediately instead of waiting a full extra interim.
      _committed = commitStablePrefix(_committed, _prevWords, words);
      _prevWords = words;
      // Show the fresh decode whenever it still EXTENDS the committed floor
      // (same prefix check commitStablePrefix itself uses) — not just before
      // the first commit. Otherwise, once anything commits, `shown` is capped
      // to the committed prefix forever: on hadith/dua recitations (out of the
      // word model's Quran-heavy comfort zone) later whole-buffer re-decodes
      // often keep re-guessing an early word slightly differently (tashkeel,
      // a resegmented syllable) — a single stray mismatch permanently freezes
      // BOTH the live "heard" text and the search query mid-recitation, even
      // though the mic and model are still running fine (only recoverable by
      // tapping stop, which re-transcribes the whole buffer fresh). Falling
      // back to the committed floor only when the decode has genuinely
      // diverged keeps the original desync protection (f5f106d) intact.
      final extendsCommitted = words.length >= _committed.length &&
          Iterable.generate(_committed.length)
              .every((i) => words[i] == _committed[i]);
      final shown = extendsCommitted ? text : _committed.join(' ');
      if (shown.isNotEmpty && shown != _transcript) {
        _transcript = shown;
        Log.d('voicesearch', 'interim: ${words.length} words, '
            '${_committed.length} committed -> "$shown"');
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
