import 'dart:async';

import 'mic_source.dart';
import 'phoneme_corpus.dart';
import 'sherpa_asr.dart';
import '../../util/log.dart';

/// The single app-global holder for the ONE phoneme ASR engine + ONE mic, shared
/// by every recitation pipeline (Quran follow-along in [ReadingState] and the
/// du'a reader in [DuaReadingState]). The two are never active at once — a user
/// recites Quran OR reads a du'a — so one warm ~70 MB ONNX model serves both.
/// Creating/disposing a second engine per du'a open was starving the model and
/// churning native mic/log resources. This holder has app lifetime; [dispose]
/// runs only at app teardown.
class AsrEngine {
  SherpaAsr? _asr;
  Future<SherpaAsr>? _creating;
  List<String> _units = const [];
  Map<String, double> _reliability = const {};

  final MicSource mic = MicSource();

  SherpaAsr? get asrOrNull => _asr;
  List<String> get units => _units;
  Map<String, double> get reliability => _reliability;

  final MicOwnership _owner = MicOwnership();

  Future<void> claimMic(Future<void> Function() releaseSelf, {String owner = '?'}) =>
      _owner.claim(releaseSelf, owner);

  void releaseMic(Future<void> Function() releaseSelf) => _owner.release(releaseSelf);

  /// Load the phoneme unit + reliability tables once (idempotent).
  Future<void> ensureData() async {
    if (_units.isEmpty) _units = await loadPhonemeUnits();
    if (_reliability.isEmpty) _reliability = await loadPhonemeReliability();
  }

  /// Create the engine once (guarding a stored [Future] against concurrent
  /// double-create) and ensure the phoneme data is loaded, then return the ready
  /// engine. A failed create nulls the guard so a later call can retry.
  Future<SherpaAsr> ready() async {
    await ensureData();
    final existing = _asr;
    if (existing != null) return existing;
    final future = _creating ??= SherpaAsr.create();
    try {
      final created = await future;
      _asr = created;
      return created;
    } catch (_) {
      if (identical(_creating, future)) _creating = null;
      rethrow;
    }
  }

  /// Dispose the phoneme recognizer so the next [ready] rebuilds a fresh one.
  /// Needed after the FastConformer word model has run: sharing the sherpa native
  /// runtime, a heavy offline recognition can leave the streaming recognizer
  /// decoding 0 tokens (device-observed). Rebuilding guarantees a clean session.
  void invalidateEngine() {
    if (_asr == null && _creating == null) return;
    Log.d('asr', 'phoneme engine invalidated — will rebuild on next use');
    _asr?.dispose();
    _asr = null;
    _creating = null;
  }

  /// Fire-and-forget warm-up so the first mic tap doesn't pay the model's
  /// cold-start cost (mirrors the old ReadingState.warmAsrEngine/_warmWatch).
  void warm() {
    if (_asr != null || _creating != null) return;
    Log.d('read', 'warming sherpa phoneme engine…');
    final sw = Stopwatch()..start();
    ready().then((_) {
      Log.d('read', 'sherpa engine ready (${sw.elapsedMilliseconds}ms, ${_units.length} units)');
    }).catchError((Object e, StackTrace st) {
      Log.e('asr', e, st);
    });
  }

  void dispose() {
    mic.dispose();
    _asr?.dispose();
  }
}

/// Single-owner registry for the shared mic's "stop me" callback. A recitation
/// session registers its release via [claim] when it starts; because the tabs
/// are an IndexedStack, a Quran session stays alive when you switch to the du'a
/// reader, so a new claimant must stop the previous one — otherwise the old
/// session runs invisibly on the shared mic (timer + reset stream underneath it).
///
/// Pure logic (holds no MicSource/platform channel) so the preempt / same-owner-
/// idempotent / stale-release contract is unit-testable — mirrors why
/// [identifyDua] was extracted from DuaFinderState.
class MicOwnership {
  Future<void> Function()? _releaseActive;
  String _activeOwner = 'none'; // label of the current owner, for the handoff trace

  Future<void> claim(Future<void> Function() releaseSelf, [String owner = '?']) async {
    final prev = _releaseActive;
    if (prev != null && !identical(prev, releaseSelf)) {
      Log.d('mic', 'owner: "$owner" claims mic, preempting "$_activeOwner"');
      _releaseActive = null;
      await prev();
    } else {
      Log.d('mic', 'owner: "$owner" claims mic (prev="$_activeOwner")');
    }
    _releaseActive = releaseSelf;
    _activeOwner = owner;
  }

  void release(Future<void> Function() releaseSelf) {
    if (identical(_releaseActive, releaseSelf)) {
      Log.d('mic', 'owner: "$_activeOwner" released mic');
      _releaseActive = null;
      _activeOwner = 'none';
    }
  }
}
