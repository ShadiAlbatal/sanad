import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/duas.dart';
import '../services/asr/dua_corpus.dart';
import '../services/asr/dua_search.dart';
import '../services/search/corpus_text_search.dart';
import '../services/search/search_confidence.dart';
import '../services/search/text_search.dart';
import '../state/app_state.dart';
import '../state/voice_search_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/highlighted_arabic.dart';
import '../widgets/search_list_scaffold.dart';
import 'dua_reader_screen.dart';

/// The Azkar tab's root: the browsable list of du'ās & adhkār (existing 5 + Hisn
/// al-Muslim, ~260), sourced from the bundled du'a corpus, rendered through the
/// shared [SearchListScaffold] (content list + unified footer). Tapping a card
/// opens its reader. The footer's mic runs the "recite to open" finder
/// ([DuaFinderState]); this screen also listens for the finder's pick and opens
/// that du'a's reader, already following along.
class DuaListScreen extends StatefulWidget {
  const DuaListScreen({super.key});

  @override
  State<DuaListScreen> createState() => _DuaListScreenState();
}

class _DuaListScreenState extends State<DuaListScreen> {
  VoiceSearchState? _voice;
  DuaSearch? _search;
  TextSearch? _textSearch;
  final _searchController = TextEditingController();

  Timer? _debounce;
  String _query = '';
  List<TextSearchHit> _results = const [];
  final _confidence = SearchConfidence();
  double _conf = 0;
  bool _voiceQuery = false;

  @override
  void initState() {
    super.initState();
    // Same cached, off-thread corpus the finder uses — rendered here for browsing.
    loadDuaSearch().then((s) {
      if (mounted) setState(() => _search = s);
    }).catchError((Object e) {
      Log.e('dualist', 'corpus load failed: $e');
    });
    // The typed-search BM25 index (built off-thread from the same corpus).
    loadDuaTextSearch().then((t) {
      if (mounted) setState(() => _textSearch = t);
    }).catchError((Object e) {
      Log.e('dualist', 'text index load failed: $e');
    });
  }

  Dua _duaFromMeta(DuaMeta m) => Dua(
        id: m.id,
        title: m.title,
        source: m.source,
        arabic: m.arabic,
        meaning: m.meaning,
      );

  void _onSearchChanged(String q, {bool fromVoice = false}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final query = q.trim();
      _results = query.isEmpty ? const [] : (_textSearch?.search(query) ?? const []);
      String? openId;
      if (fromVoice && query.isNotEmpty) {
        final out = _confidence
            .update([for (final h in _results.take(5)) (id: h.id, score: h.score)]);
        _conf = out.confidence;
        openId = out.openId;
        _voiceQuery = true;
      } else {
        _confidence.reset();
        _conf = 0;
        _voiceQuery = false;
      }
      setState(() => _query = query);
      if (query.isNotEmpty) {
        Log.d('dualist',
            'search "$query" -> ${_results.length} hits conf=${_conf.toStringAsFixed(2)}');
      }
      if (openId != null) {
        final meta = _search?.metaById(openId);
        if (meta != null) {
          Log.d('dualist', 'auto-open $openId (trust ring full)');
          _open(_duaFromMeta(meta));
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final voice = context.read<VoiceSearchState>();
    if (!identical(voice, _voice)) {
      _voice?.removeListener(_onVoice);
      _voice = voice;
      voice.addListener(_onVoice);
    }
  }

  void _onVoice() {
    // Only the visible tab reacts to the shared voice state (see hadith screen).
    if (!mounted || context.read<AppState>().tabIndex != Tabs.dua) return;
    final t = _voice?.transcript ?? '';
    if (t.isEmpty || t == _searchController.text) return;
    _searchController.text = t;
    _onSearchChanged(t, fromVoice: true);
  }

  // See QuranListScreen._opening — same rapid-double-tap guard against stacked
  // pushes while the reader takes a beat to open.
  bool _opening = false;

  void _open(Dua dua) {
    if (_opening) return;
    _opening = true;
    // Lock the results + free the mic for the reader's phoneme follow-along, then
    // open with autoStart so highlighting begins as the user recites (see hadith).
    _voice?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => DuaReaderScreen(dua: dua, autoStart: true)))
          .then((_) {
        if (mounted) setState(() => _opening = false);
      });
    });
    // A bare GestureDetector tap changes nothing visually, so Flutter schedules no
    // frame — and the post-frame callback above then never fires until the next
    // unrelated input (a stray swipe) forces one. Force a frame so the push runs
    // on the very next tick.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _voice?.removeListener(_onVoice);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleMic(VoiceSearchState voice) async {
    if (voice.recording) {
      await voice.stop();
      return;
    }
    _confidence.reset();
    _conf = 0;
    await voice.start();
    if (voice.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(voice.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceSearchState>();
    final searching = _query.isNotEmpty;
    final metas = _search?.allDuas;
    final leadExpanded = voice.recording && _voiceQuery;

    final int count;
    final IndexedWidgetBuilder builder;
    if (searching) {
      count = _results.length;
      builder = (_, i) {
        final hit = _results[i];
        final meta = _search!.metaById(hit.id)!;
        return _DuaCard(
          dua: _duaFromMeta(meta),
          matched: hit.matchedWords,
          onTap: () => _open(_duaFromMeta(meta)),
          expanded: leadExpanded && i == 0,
          confidence: leadExpanded && i == 0 ? _conf : null,
        );
      };
    } else {
      count = metas?.length ?? 0;
      builder = (_, i) => _DuaCard(
          dua: _duaFromMeta(metas![i]), onTap: () => _open(_duaFromMeta(metas[i])));
    }

    return SearchListScaffold(
      title: 'Duas & Adhkār',
      subtitle: 'Recite to open, or tap a du\'ā — words light up as you read',
      loading: metas == null,
      itemCount: count,
      itemBuilder: builder,
      emptyState: searching ? const _NoMatches() : null,
      listening: voice.recording,
      starting: voice.busy,
      level: voice.level,
      heard: '',
      hearingLabel: voice.recording ? 'Listening… tap to search' : 'Preparing…',
      onMicTap: () => _toggleMic(voice),
      micIdleLabel: 'Recite to find a du\'ā',
      searchController: _searchController,
      onSearchChanged: _onSearchChanged,
      searchHint: 'Search du\'ās',
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text('No matches — clear the search to browse all',
            textAlign: TextAlign.center, style: TextStyle(color: soft, fontSize: 14)),
      ),
    );
  }
}

class _DuaCard extends StatelessWidget {
  final Dua dua;
  final Set<String> matched; // typed-search matched words to highlight ('' when browsing)
  final VoidCallback onTap;
  final bool expanded; // the live leading result: show more matching text
  final double? confidence; // 0..1 trust ring (null = no ring)
  const _DuaCard(
      {required this.dua,
      required this.onTap,
      this.matched = const {},
      this.expanded = false,
      this.confidence});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(18),
          border: expanded ? Border.all(color: context.accent.withValues(alpha: 0.6), width: 1.4) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(dua.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (confidence != null)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      value: confidence!.clamp(0.0, 1.0),
                      strokeWidth: 2.5,
                      backgroundColor: soft.withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation(context.accent),
                    ),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: soft),
              ],
            ),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.rtl,
              child: HighlightedArabic(
                text: dua.arabic,
                matched: matched,
                highlight: context.accent,
                maxLines: expanded ? 8 : 2,
                style: const TextStyle(
                  fontFamily: 'UthmanicHafs',
                  fontSize: 22,
                  height: 1.9,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(dua.source.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: context.accent,
                )),
          ],
        ),
      ),
    );
  }
}
