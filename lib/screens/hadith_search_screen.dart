import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/asr/hadith_search.dart';
import '../services/search/corpus_text_search.dart';
import '../services/search/text_search.dart';
import '../state/voice_search_state.dart';
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

  // See QuranListScreen._opening — same rapid-double-tap guard against stacked
  // pushes while the reader takes a beat to open.
  bool _opening = false;

  void _open(String collection, int number, String text, {bool autoStart = false}) {
    if (_opening) {
      Log.d('hadithlist', 'tap on $collection:$number ignored — already opening');
      return;
    }
    Log.d('hadithlist', 'open $collection:$number (autoStart=$autoStart)');
    _opening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        Log.d('hadithlist', 'open $collection:$number aborted — unmounted before push');
        return;
      }
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => HadithReaderScreen(
                  collection: collection, number: number, text: text, autoStart: autoStart)))
          .then((_) {
        if (mounted) setState(() => _opening = false);
      });
    });
    // A bare GestureDetector tap changes nothing visually, so Flutter schedules no
    // frame — and the post-frame callback above then never fires until the next
    // unrelated input (a stray swipe) forces one, which is why tap-to-open hung
    // for seconds. Force a frame so the push runs on the very next tick.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Voice search: record → transcribe (FastConformer) → drop the transcript into
  // the search field so the SAME BM25 path renders the results. A second tap
  // stops + transcribes; there is no live per-chunk probing.
  Future<void> _toggleMic(VoiceSearchState voice) async {
    if (voice.recording) {
      final text = await voice.stopAndTranscribe();
      if (!mounted) return;
      if (text.isNotEmpty) {
        _searchController.text = text;
        _onSearchChanged(text);
      }
      return;
    }
    await voice.start();
    if (voice.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(voice.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceSearchState>();
    final searching = _query.isNotEmpty;
    final browse = _search?.allHadith;

    final int count;
    final IndexedWidgetBuilder builder;
    if (searching) {
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
      loading: browse == null,
      itemCount: count,
      itemBuilder: builder,
      emptyState: searching ? const _NoMatches() : null,
      listening: voice.recording,
      starting: voice.busy,
      level: voice.level,
      heard: '',
      hearingLabel: voice.recording ? 'Listening… tap to search' : 'Preparing…',
      onMicTap: () => _toggleMic(voice),
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
