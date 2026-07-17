import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/duas.dart';
import '../data/quotes.dart';
import '../data/quran_repository.dart';
import '../models/mushaf.dart';
import '../services/asr/dua_search.dart';
import '../services/asr/hadith_corpus.dart' show hadithCollectionName;
import '../services/asr/hadith_search.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../util/day_part.dart';
import '../util/log.dart';
import 'adzkar_screen.dart';
import 'debug_log_screen.dart';
import 'dua_reader_screen.dart';
import 'hadith_reader_screen.dart';
import 'quran_screen.dart';
import 'user_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final repo = context.read<QuranRepository>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    final now = DateTime.now();
    final part = dayPartOf(now);
    final suggestion = suggestionFor(part);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greetingFor(part),
                      style: TextStyle(fontSize: 14, color: soft)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    // Debug Log screen (exports recitation traces) is dev-only.
                    onLongPress: Log.diagEnabled
                        ? () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const DebugLogScreen()))
                        : null,
                    child: const Text('Sanad',
                        style:
                            TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UserScreen())),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: context.accent.withValues(alpha: 0.30),
                        width: 1.5),
                  ),
                  child: Icon(Icons.person_rounded,
                      color: context.accent, size: 24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _QuoteCard(quote: dailyQuote(now)),
          const SizedBox(height: 20),
          _ContinueCard(page: app.lastPage, repo: repo),
          const SizedBox(height: 14),
          if (app.lastDuaId != null) ...[
            _DuaContinueCard(id: app.lastDuaId!),
            const SizedBox(height: 14),
          ],
          if (app.lastHadithId != null) ...[
            _HadithContinueCard(id: app.lastHadithId!),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 8),
          Text('Explore',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: soft,
              )),
          const SizedBox(height: 12),
          _QuickTile(
            icon: Icons.touch_app_rounded,
            label: 'Counter',
            subtitle: 'Tasbih & adhkār',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AdzkarScreen(pushed: true))),
          ),
          const SizedBox(height: 22),
          _SuggestionCard(
            suggestion: suggestion,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    AdzkarScreen(pushed: true, initialCategory: suggestion.category))),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final Quote quote;
  const _QuoteCard({required this.quote});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: dark ? AppColors.nightCard : AppColors.paperEdge,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(color: context.accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              quote.arabic,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'UthmanicHafs',
                fontSize: 26,
                height: 1.9,
                color: dark ? AppColors.nightInk : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            quote.english,
            style: TextStyle(fontSize: 14.5, height: 1.4, color: soft),
          ),
          const SizedBox(height: 10),
          Text(
            quote.source.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: context.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final int page;
  final QuranRepository repo;
  const _ContinueCard({required this.page, required this.repo});

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final accentHsl = HSLColor.fromColor(accent);
    final accentDeep =
        accentHsl.withLightness((accentHsl.lightness * 0.72).clamp(0.0, 1.0)).toColor();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => QuranScreen(initialPage: page))),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent, accentDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Continue reading',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  FutureBuilder<Chapter>(
                    future: repo.chapterForPage(page),
                    builder: (context, snap) => Text(
                      snap.hasData ? snap.data!.nameSimple : '…',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('Page $page',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 32),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared shell for the Dua/Hadith "continue reading" cards — same gradient card
/// as Quran's [_ContinueCard], just resolving its title/subtitle from an async
/// lookup (the corpus search index) instead of the always-loaded [QuranRepository].
///
/// [id]-keyed and STATEFUL so the lookup [Future] is built once (in [initState] /
/// on an actual [id] change), not on every Home rebuild — Home rebuilds on every
/// tab switch anywhere in the app (see AppState.tabIndex), and re-running
/// `loadDuaSearch().then(...)` there each time handed [FutureBuilder] a
/// freshly-identical-but-new [Future], which reset it to "waiting" and
/// re-subscribed on every switch for no reason.
class _ResumeCard extends StatefulWidget {
  final String id;
  final String eyebrow;
  final Future<(String title, String subtitle)?> Function(String id) loader;
  final void Function(BuildContext context, String id) onOpen;
  const _ResumeCard(
      {required this.id, required this.eyebrow, required this.loader, required this.onOpen});

  @override
  State<_ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<_ResumeCard> {
  late Future<(String, String)?> _future = widget.loader(widget.id);

  @override
  void didUpdateWidget(_ResumeCard old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _future = widget.loader(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final accentHsl = HSLColor.fromColor(accent);
    final accentDeep =
        accentHsl.withLightness((accentHsl.lightness * 0.72).clamp(0.0, 1.0)).toColor();
    return FutureBuilder<(String, String)?>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (snap.connectionState == ConnectionState.done && data == null) {
          return const SizedBox.shrink(); // id no longer resolves — fail quiet
        }
        return GestureDetector(
          onTap: () => widget.onOpen(context, widget.id),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accentDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.eyebrow,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(data?.$1 ?? '…',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(data?.$2 ?? '',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DuaContinueCard extends StatelessWidget {
  final String id;
  const _DuaContinueCard({required this.id});

  static Future<(String, String)?> _load(String id) async {
    final meta = (await loadDuaSearch()).metaById(id);
    return meta == null ? null : (meta.title, meta.source);
  }

  static void _open(BuildContext context, String id) async {
    final meta = (await loadDuaSearch()).metaById(id);
    if (meta == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DuaReaderScreen(
            dua: Dua(
                id: meta.id,
                title: meta.title,
                source: meta.source,
                arabic: meta.arabic,
                meaning: meta.meaning))));
  }

  @override
  Widget build(BuildContext context) => _ResumeCard(
      id: id, eyebrow: 'Continue reading', loader: _load, onOpen: _open);
}

class _HadithContinueCard extends StatelessWidget {
  final String id;
  const _HadithContinueCard({required this.id});

  static Future<(String, String)?> _load(String id) async {
    final e = (await loadHadithSearch()).entryById(id);
    return e == null ? null : (e.label, hadithCollectionName(e.collection));
  }

  static void _open(BuildContext context, String id) async {
    final e = (await loadHadithSearch()).entryById(id);
    if (e == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            HadithReaderScreen(collection: e.collection, number: e.number, text: e.text)));
  }

  @override
  Widget build(BuildContext context) => _ResumeCard(
      id: id, eyebrow: 'Continue reading', loader: _load, onOpen: _open);
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: context.accent, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: soft, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: soft),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final AdhkarSuggestion suggestion;
  final VoidCallback onTap;
  const _SuggestionCard({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: context.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: context.accent.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          children: [
            Icon(suggestion.icon, color: context.accent, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text('Open the counter',
                      style: TextStyle(color: soft, fontSize: 12.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: soft),
          ],
        ),
      ),
    );
  }
}
