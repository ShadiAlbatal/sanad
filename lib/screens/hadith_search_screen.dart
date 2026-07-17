import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/asr/hadith_search.dart';
import '../services/search/corpus_text_search.dart';
import '../services/search/text_search.dart';
import '../state/hadith_finder_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/highlighted_arabic.dart';
import '../widgets/search_list_scaffold.dart';
import 'hadith_reader_screen.dart';

/// The Hadith tab, rendered through the shared [SearchListScaffold] (content list
/// + unified footer). Idle, it browses the WHOLE corpus (Sahih Bukhari + Muslim,
/// sorted by collection + number) — no longer an empty screen. While reciting,
/// the footer mic runs the live phoneme finder ([HadithFinderState]) and the
/// content flips to its ranked candidates; a confident match opens the reader.
/// Never a dead end. Tapping any row opens that hadith's reader.
class HadithSearchScreen extends StatefulWidget {
  const HadithSearchScreen({super.key});

  @override
  State<HadithSearchScreen> createState() => _HadithSearchScreenState();
}

class _HadithSearchScreenState extends State<HadithSearchScreen> {
  HadithFinderState? _finder;
  HadithSearch? _search;
  TextSearch? _textSearch;
  final _searchController = TextEditingController();

  Timer? _debounce;
  String _query = '';
  List<TextSearchHit> _results = const [];

  @override
  void initState() {
    super.initState();
    // Same cached, off-thread index the finder uses (loadHadithSearch is memoized)
    // — rendered here as the idle browsable list. No double-load.
    loadHadithSearch().then((s) {
      if (mounted) setState(() => _search = s);
    }).catchError((Object e) {
      Log.e('hadithlist', 'corpus load failed: $e');
    });
    // The typed-search BM25 index (built off-thread from the same corpus).
    loadHadithTextSearch().then((t) {
      if (mounted) setState(() => _textSearch = t);
    }).catchError((Object e) {
      Log.e('hadithlist', 'text index load failed: $e');
    });
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final query = q.trim();
      setState(() {
        _query = query;
        _results = query.isEmpty ? const [] : (_textSearch?.search(query) ?? const []);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final finder = context.read<HadithFinderState>();
    if (!identical(finder, _finder)) {
      _finder?.removeListener(_onFinder);
      _finder = finder;
      _finder!.addListener(_onFinder);
      finder.preload(); // build the corpus off-thread on first tab open
    }
  }

  void _onFinder() {
    final finder = _finder;
    final pick = finder?.pick;
    if (finder == null || pick == null) return;
    // A pushed reader (on top) owns the pick; don't double-navigate from under it.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    finder.clearPick();
    // Opened from the live finder — the user is already reciting, so the reader
    // grabs the mic and follows along immediately (mirrors the du'a finder pick).
    _open(pick.collection, pick.number, pick.text, autoStart: true);
  }

  // See QuranListScreen._opening — same rapid-double-tap guard against stacked
  // pushes while the reader takes a beat to open.
  bool _opening = false;

  void _open(String collection, int number, String text, {bool autoStart = false}) {
    if (_opening) return;
    _opening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => HadithReaderScreen(
                  collection: collection, number: number, text: text, autoStart: autoStart)))
          .then((_) {
        if (mounted) setState(() => _opening = false);
      });
    });
  }

  @override
  void dispose() {
    _finder?.removeListener(_onFinder);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleMic(HadithFinderState finder) async {
    if (finder.listening) {
      await finder.stop();
      return;
    }
    await finder.start();
    if (finder.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(finder.error!)));
    }
  }

  String _finderLabel(HadithFinderState finder) {
    if (!finder.heardSomething) return 'Listening…';
    final lead = finder.leading;
    return lead == null ? 'Matching…' : 'Hearing: ${lead.label}?';
  }

  @override
  Widget build(BuildContext context) {
    final finder = context.watch<HadithFinderState>();
    // Three renderings through the same card + scaffold, in priority order:
    //  1. reciting → the finder's live ranked candidates (voice), each row bolding
    //     the words the recitation matched (finder.matchedWords, via the corpus
    //     word map) — the same highlight the typed path gives;
    //  2. a typed query → ranked BM25 results with the matched words highlighted;
    //  3. idle → browse the whole corpus. Never a dead end.
    final candidates = finder.candidates;
    final showCandidates = finder.listening && candidates.isNotEmpty;
    final searching = !showCandidates && _query.isNotEmpty;
    final browse = _search?.allHadith;

    final int count;
    final IndexedWidgetBuilder builder;
    if (showCandidates) {
      count = candidates.length;
      builder = (_, i) => _HadithCard(
            label: candidates[i].label,
            text: candidates[i].text,
            matched: finder.matchedWords(candidates[i].id),
            onTap: () =>
                _open(candidates[i].collection, candidates[i].number, candidates[i].text),
          );
    } else if (searching) {
      count = _results.length;
      builder = (_, i) {
        final hit = _results[i];
        final e = _search!.entryById(hit.id)!;
        return _HadithCard(
          label: e.label,
          text: e.text,
          matched: hit.matchedWords,
          onTap: () => _open(e.collection, e.number, e.text),
        );
      };
    } else {
      count = browse?.length ?? 0;
      builder = (_, i) => _HadithCard(
            label: browse![i].label,
            text: browse[i].text,
            onTap: () => _open(browse[i].collection, browse[i].number, browse[i].text),
          );
    }

    return SearchListScaffold(
      title: 'Hadith',
      subtitle: 'Recite a hadith to find it, or tap one to read',
      loading: !showCandidates && browse == null,
      itemCount: count,
      itemBuilder: builder,
      emptyState: searching ? const _NoMatches() : null,
      listening: finder.listening,
      starting: finder.starting,
      level: finder.level,
      heard: finder.heard,
      idlePrompt: 'Recite a hadith to find it',
      hearingLabel: _finderLabel(finder),
      onMicTap: () => _toggleMic(finder),
      micIdleLabel: 'Recite to find a hadith',
      searchController: _searchController,
      onSearchChanged: _onSearchChanged,
      searchHint: 'Search hadith',
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

class _HadithCard extends StatelessWidget {
  final String label;
  final String text;
  final Set<String> matched; // typed-search matched words to highlight ('' otherwise)
  final VoidCallback onTap;
  const _HadithCard(
      {required this.label, required this.text, required this.onTap, this.matched = const {}});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: context.accent,
                      )),
                ),
                Icon(Icons.chevron_right_rounded, color: soft),
              ],
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: HighlightedArabic(
                text: text,
                matched: matched,
                highlight: context.accent,
                style: const TextStyle(
                  fontFamily: 'UthmanicHafs',
                  fontSize: 21,
                  height: 1.9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
