import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/search/search_confidence.dart';
import '../state/app_state.dart';
import '../state/voice_search_state.dart';
import '../util/log.dart';

/// The shared voice + typed search shell for the three list tabs (Quran, Duas,
/// Hadith). Each tab renders a different corpus through the same
/// [SearchListScaffold], and the plumbing between the shared [VoiceSearchState]
/// (FastConformer, live-transcribing every ~2s) and the tab's BM25 index is
/// identical — this mixin holds that plumbing so it lives in ONE place: the
/// voice listener, the debounced search, the trust-ring confidence, auto-open,
/// the mic toggle, and the guarded reader push.
///
/// A screen mixes this in over its result/hit type [H] and supplies the five
/// things that genuinely differ: [voiceTab] (which tab reacts to the shared
/// voice), [logTag], [runSearch] (its BM25 call), [scoreOf] (hit → id+score for
/// the confidence ring), and [openHit] (auto-open the confident pick). The
/// screen keeps its own `initState` loads and its own `build`/cards.
mixin VoiceSearchListMixin<W extends StatefulWidget, H> on State<W> {
  VoiceSearchState? _voice;
  final searchController = TextEditingController();
  final _confidence = SearchConfidence();
  Timer? _debounce;
  bool _opening = false;

  /// Current trimmed query (typed or the live transcript); empty = browsing.
  String query = '';
  List<H> results = const [];

  /// Trust-ring fill 0..1 on the leading result while reciting (0 when typed).
  double conf = 0;

  /// The current query arrived from voice — drives the ring + leading-card expand.
  bool voiceQuery = false;

  // ---- the screen supplies these ----

  /// Which [Tabs] value this screen is, so only the visible tab reacts to the
  /// ONE shared [VoiceSearchState] (else off-screen tabs run phantom searches
  /// and could auto-open the wrong reader).
  int get voiceTab;

  /// Log channel for this screen (e.g. 'quranlist').
  String get logTag;

  /// The tab's BM25 search over [query]; empty list until its index has loaded.
  List<H> runSearch(String query);

  /// A hit's stable id + score, fed to the confidence ring.
  ({String id, double score}) scoreOf(H hit);

  /// Open the reader for the confident auto-pick (the hit whose id the ring
  /// chose). Called only when the ring fills.
  void openHit(H hit);

  VoiceSearchState? get voice => _voice;
  bool get searching => query.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = context.read<VoiceSearchState>();
    if (!identical(v, _voice)) {
      _voice?.removeListener(_onVoice);
      _voice = v;
      v.addListener(_onVoice);
    }
  }

  // Mirror the live transcript into the search field as it grows, so the BM25
  // results narrow AS the user recites (not only on stop).
  void _onVoice() {
    if (!mounted || context.read<AppState>().tabIndex != voiceTab) return;
    final t = _voice?.transcript ?? '';
    if (t.isEmpty || t == searchController.text) return;
    searchController.text = t;
    onSearchChanged(t, fromVoice: true);
  }

  void onSearchChanged(String q, {bool fromVoice = false}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final trimmed = q.trim();
      results = trimmed.isEmpty ? const [] : runSearch(trimmed);
      // Live voice: track how confidently the field has converged on one result,
      // fill the ring, and auto-open when it's clearly sure. Typed search never
      // auto-opens — the user is deciding.
      String? openId;
      if (fromVoice && trimmed.isNotEmpty) {
        final out = _confidence
            .update([for (final h in results.take(5)) scoreOf(h)]);
        conf = out.confidence;
        openId = out.openId;
        voiceQuery = true;
      } else {
        _confidence.reset();
        conf = 0;
        voiceQuery = false;
      }
      setState(() => query = trimmed);
      if (trimmed.isNotEmpty) {
        final top = results
            .take(3)
            .map((h) => scoreOf(h))
            .map((s) => '${s.id}:${s.score.toStringAsFixed(2)}')
            .join(' ');
        Log.d(logTag,
            'search "$trimmed" -> ${results.length} hits conf=${conf.toStringAsFixed(2)} top=[$top]');
      }
      if (openId != null && results.isNotEmpty) {
        final id = openId;
        final hit = results.firstWhere((h) => scoreOf(h).id == id,
            orElse: () => results.first);
        Log.d(logTag, 'auto-open ${scoreOf(hit).id} (trust ring full)');
        openHit(hit);
      }
    });
  }

  Future<void> toggleMic() async {
    final v = _voice;
    if (v == null) return;
    if (v.recording) {
      await v.stop();
      return;
    }
    _confidence.reset();
    conf = 0;
    await v.start();
    if (v.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v.error!)));
    }
  }

  /// The guarded reader push shared by every tap-to-open and auto-open: one
  /// in-flight navigation at a time, free the shared mic for the reader's
  /// phoneme follow-along, then push on the very next frame.
  void openRoute(WidgetBuilder builder) {
    if (_opening) {
      Log.d(logTag, 'open ignored — already opening');
      return;
    }
    _opening = true;
    // Lock the results + free the word model / rebuild the phoneme engine so the
    // reader's follow-along runs clean (see VoiceSearchState.cancel).
    _voice?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: builder))
          .then((_) {
        if (mounted) setState(() => _opening = false);
      });
    });
    // A bare GestureDetector tap changes nothing visually, so Flutter schedules
    // no frame — and the post-frame callback above then never fires until the
    // next unrelated input (a stray swipe) forces one, which is why tap-to-open
    // hung for seconds. Force a frame so the push runs on the very next tick.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _voice?.removeListener(_onVoice);
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }
}
