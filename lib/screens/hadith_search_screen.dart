import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/asr/hadith_search.dart';
import '../services/search/corpus_text_search.dart';
import '../services/search/text_search.dart';
import '../state/app_state.dart';
import '../state/voice_search_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/highlighted_arabic.dart';
import '../widgets/search_list_scaffold.dart';
import 'hadith_reader_screen.dart';
import 'voice_search_list_mixin.dart';

/// The Hadith tab, rendered through the shared [SearchListScaffold] (content list
/// + unified footer). Idle, it browses the WHOLE corpus (Sahih Bukhari + Muslim,
/// sorted by collection + number). Voice + typed search run through
/// [VoiceSearchListMixin] (FastConformer live-transcription → BM25); a confident
/// match opens the reader. Never a dead end. Tapping any row opens that hadith's
/// reader.
class HadithSearchScreen extends StatefulWidget {
  const HadithSearchScreen({super.key});

  @override
  State<HadithSearchScreen> createState() => _HadithSearchScreenState();
}

class _HadithSearchScreenState extends State<HadithSearchScreen>
    with VoiceSearchListMixin<HadithSearchScreen, TextSearchHit> {
  HadithSearch? _search;
  TextSearch? _textSearch;

  @override
  void initState() {
    super.initState();
    // Same cached, off-thread index the search uses (loadHadithSearch is memoized)
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

  @override
  int get voiceTab => Tabs.hadith;
  @override
  String get logTag => 'hadithlist';
  @override
  List<TextSearchHit> runSearch(String q) => _textSearch?.search(q) ?? const [];
  @override
  ({String id, double score}) scoreOf(TextSearchHit hit) =>
      (id: hit.id, score: hit.score);
  @override
  void openHit(TextSearchHit hit) {
    final e = _search?.entryById(hit.id);
    if (e != null) _open(e.collection, e.number, e.text);
  }

  void _open(String collection, int number, String text) => openRoute((_) =>
      HadithReaderScreen(
          collection: collection, number: number, text: text, autoStart: true));

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceSearchState>();
    final browse = _search?.allHadith;

    // While reciting, the leading result expands to show more of the matching text
    // and carries the trust ring that fills toward auto-open.
    final leadExpanded = voice.recording && voiceQuery;

    final int count;
    final IndexedWidgetBuilder builder;
    if (searching) {
      count = results.length;
      builder = (_, i) {
        final hit = results[i];
        final e = _search!.entryById(hit.id)!;
        return _HadithCard(
          label: e.label,
          text: e.text,
          matched: hit.matchedWords,
          onTap: () => _open(e.collection, e.number, e.text),
          expanded: leadExpanded && i == 0,
          confidence: leadExpanded && i == 0 ? conf : null,
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
      onMicTap: toggleMic,
      micIdleLabel: 'Recite to find a hadith',
      searchController: searchController,
      onSearchChanged: onSearchChanged,
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
  final bool expanded; // the live leading result: show more matching text
  final double? confidence; // 0..1 trust ring (null = no ring)
  const _HadithCard(
      {required this.label,
      required this.text,
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(16),
          border: expanded ? Border.all(color: context.accent.withValues(alpha: 0.6), width: 1.4) : null,
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
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: HighlightedArabic(
                text: text,
                matched: matched,
                highlight: context.accent,
                maxLines: expanded ? 8 : 2,
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
