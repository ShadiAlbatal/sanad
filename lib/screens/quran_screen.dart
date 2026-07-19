import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/quran_repository.dart';
import '../models/mushaf.dart';
import '../state/app_state.dart';
import '../state/reading_state.dart';
import '../theme/app_theme.dart';
import '../util/log.dart';
import '../widgets/curl_page_view.dart';
import '../widgets/mushaf_page_view.dart';
import '../widgets/reading_footer.dart';
import '../widgets/surah_list_sheet.dart';

class QuranScreen extends StatefulWidget {
  final int? initialPage;

  /// When opened from voice search the user is already reciting, so begin the
  /// follow-along the moment the page is ready (mirrors the Dua/Hadith readers)
  /// — claims the shared mic from the search and re-anchors on the live audio
  /// without a second tap.
  final bool autoStart;
  const QuranScreen({super.key, this.initialPage, this.autoStart = false});

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  final CurlController _controller = CurlController();
  late int _page;
  late final AppState _app;
  late final ReadingState _reading;
  final Set<String> _highlighted = {};
  List<String> _basmala = const [];

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _page = widget.initialPage ?? _app.lastPage;
    _app.jumpTarget.addListener(_handleJump);
    _reading = context.read<ReadingState>();
    _reading.asrNavigate.addListener(_handleAsrNavigate);
    _preload();
    // Load the ONNX session ahead of time so the footer mic button doesn't
    // pay the model's cold-start cost on first tap.
    _reading.warmAsrEngine();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSettle(_page));
  }

  // The ASR tracker asks the display to follow the recitation to a settled/slid
  // verse's page.
  void _handleAsrNavigate() {
    final page = _reading.asrNavigate.value;
    if (page == null || !mounted) return;
    _reading.asrNavigate.value = null;
    if (page != _page) {
      Log.d('reader', 'ASR follow: navigate $_page -> $page');
      jumpTo(page);
    }
  }

  Future<void> _preload() async {
    final repo = context.read<QuranRepository>();
    await repo.preload();
    await repo.page(_page);
    Log.d('reader', 'preload done, open page $_page');
    if (mounted) {
      setState(() => _basmala = repo.basmalaSync ?? const []);
      _registerPage(_page); // sets the surah context startAsrListening reads below
      if (widget.autoStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reading.startAsrListening();
        });
      }
    }
  }

  void _handleJump() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => jumpTo(_app.pendingJump));
  }

  @override
  void dispose() {
    _app.jumpTarget.removeListener(_handleJump);
    _reading.asrNavigate.removeListener(_handleAsrNavigate);
    // The reader is now a PUSHED route (was an always-alive IndexedStack tab whose
    // mic the root scaffold stopped on tab-away). Popping it must release the shared
    // mic itself — otherwise a live follow-along would run invisibly on the engine.
    if (_reading.asrActive) _reading.stopAsrListening();
    _reading.clearRetainedPcm(); // free the ~19 MB voice buffer on leaving the reader
    super.dispose();
  }

  void jumpTo(int page) {
    Log.d('reader', 'jumpTo page $page');
    _controller.jumpTo(page - 1);
  }

  void _onSettle(int page) {
    _app.setLastPage(page);
    final repo = context.read<QuranRepository>();
    _registerPage(page);
    // Warm neighbours so turning to them (and capturing them) doesn't stutter.
    for (final p in [page - 2, page - 1, page + 1, page + 2]) {
      if (p >= 1 && p <= QuranRepository.totalPages) repo.page(p);
    }
  }

  // In hidden (memorization) mode a tap reveals just that word.
  void _tapWord(MushafWord w) {
    final reading = context.read<ReadingState>();
    if (reading.hidden) reading.toggleWord(w.location);
  }

  // Long-press reveals the whole ayah the word belongs to.
  void _revealAyah(MushafWord w) {
    final reading = context.read<ReadingState>();
    if (!reading.hidden) return;
    final page = context.read<QuranRepository>().cachedPage(_page);
    if (page == null) return;
    final locs = <String>[
      for (final line in page.lines)
        for (final word in line.words)
          if (word.surah == w.surah && word.ayah == w.ayah) word.location,
    ];
    reading.revealLocations(locs);
  }

  /// Tells ReadingState which page/surah is on screen — context for tiered
  /// acquisition, and (if a session is live) a manual page turn re-acquires
  /// from here.
  void _registerPage(int page) {
    final repo = context.read<QuranRepository>();
    final surah = repo.chapterForPageSync(page)?.id ?? 1;
    final reading = context.read<ReadingState>();
    reading.setCurrentPage(page: page, surah: surah);
    final cached = repo.cachedPage(page);
    if (cached != null) {
      reading.setPageWords(_pageLocs(cached));
    } else {
      repo.page(page).then((p) {
        if (mounted && _page == page) reading.setPageWords(_pageLocs(p));
      });
    }
  }

  List<String> _pageLocs(MushafPage p) => [
        for (final line in p.lines)
          for (final word in line.words) word.location,
      ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final repo = context.read<QuranRepository>();
    // Read (not watch): the expensive mushaf tree rebuilds on ReadingState's
    // markerTick (fires only when the visible markers/reveal/hidden/surah
    // change), NOT on every high-frequency notify (RMS level, heard, timer)
    // which only the footer consumes. Manual taps rebuild via setState below.
    final reading = context.read<ReadingState>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              page: _page,
              repo: repo,
              onIndex: () => showSurahList(context, onSelect: jumpTo),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: reading.markerTick,
                builder: (context, _, child) {
                  final highlighted = <String>{
                    ..._highlighted,
                    ...reading.asrHighlightedLocations, // whole current corpus word (may be several glyphs)
                  };
                  return CurlPageView(
                    controller: _controller,
                    initialPage: _page - 1,
                    itemCount: QuranRepository.totalPages,
                    onPageChanged: (i) {
                      setState(() => _page = i + 1);
                      _onSettle(i + 1);
                    },
                    itemBuilder: (context, i) => _PageLeaf(
                      page: i + 1,
                      repo: repo,
                      dark: dark,
                      basmala: _basmala,
                      highlighted: highlighted,
                      hidden: reading.hidden,
                      revealed: reading.revealed,
                      currentVerseKey: reading.asrCurrentVerseKey,
                      currentLocations: reading.asrHighlightedLocations,
                      skipped: reading.asrSkippedLocations,
                      onWordTap: _tapWord,
                      onWordLongPress: _revealAyah,
                    ),
                  );
                },
              ),
            ),
            _BottomBar(page: _page, repo: repo),
          ],
        ),
      ),
      // As a pushed route the reader owns its recitation footer (it used to be
      // rendered by the root scaffold while the reader was the Quran tab). SafeArea
      // reserves the system nav-bar inset since this is the bottom-most bar.
      bottomNavigationBar:
          SafeArea(top: false, child: const ReadingFooter(showMic: true)),
    );
  }
}

/// One full-screen mushaf page, styled as a leaf in an open book: a binding
/// gutter shadow down one side and stacked page-edges on the fore-edge.
class _PageLeaf extends StatelessWidget {
  final int page; // 1-based
  final QuranRepository repo;
  final bool dark;
  final List<String> basmala;
  final Set<String> highlighted;
  final bool hidden;
  final Set<String> revealed;
  final String? currentVerseKey;
  final Set<String> currentLocations;
  final Set<String> skipped;
  final void Function(MushafWord) onWordTap;
  final void Function(MushafWord) onWordLongPress;
  const _PageLeaf({
    required this.page,
    required this.repo,
    required this.dark,
    required this.basmala,
    required this.highlighted,
    required this.hidden,
    required this.revealed,
    required this.currentVerseKey,
    required this.currentLocations,
    required this.skipped,
    required this.onWordTap,
    required this.onWordLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Odd pages sit on the right (binding/gutter on the left); even mirror it.
    final bindingLeft = page.isOdd;
    return RepaintBoundary(
      child: Container(
        margin: EdgeInsets.only(
          top: 6,
          bottom: 6,
          left: bindingLeft ? 6 : 2,
          right: bindingLeft ? 2 : 6,
        ),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paper,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
              blurRadius: 9,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: _PageContent(
                  page: page,
                  repo: repo,
                  dark: dark,
                  basmala: basmala,
                  highlighted: highlighted,
                  hidden: hidden,
                  revealed: revealed,
                  currentVerseKey: currentVerseKey,
                  currentLocations: currentLocations,
                  skipped: skipped,
                  onWordTap: onWordTap,
                  onWordLongPress: onWordLongPress,
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: bindingLeft ? 0 : null,
                right: bindingLeft ? null : 0,
                child: _GutterShadow(fromLeft: bindingLeft, dark: dark),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: bindingLeft ? null : 0,
                right: bindingLeft ? 0 : null,
                width: 16,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BookEdgesPainter(onRight: bindingLeft, dark: dark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loads and renders one page's content, with a visible error + retry
/// affordance instead of a silent blank page if the page JSON fails to load
/// (a corrupt asset, or a transient IO/OOM hiccup during a scan).
class _PageContent extends StatefulWidget {
  final int page;
  final QuranRepository repo;
  final bool dark;
  final List<String> basmala;
  final Set<String> highlighted;
  final bool hidden;
  final Set<String> revealed;
  final String? currentVerseKey;
  final Set<String> currentLocations;
  final Set<String> skipped;
  final void Function(MushafWord) onWordTap;
  final void Function(MushafWord) onWordLongPress;
  const _PageContent({
    required this.page,
    required this.repo,
    required this.dark,
    required this.basmala,
    required this.highlighted,
    required this.hidden,
    required this.revealed,
    required this.currentVerseKey,
    required this.currentLocations,
    required this.skipped,
    required this.onWordTap,
    required this.onWordLongPress,
  });

  @override
  State<_PageContent> createState() => _PageContentState();
}

class _PageContentState extends State<_PageContent> {
  late Future<MushafPage> _future = widget.repo.page(widget.page);

  // The curl view holds the current/neighbour leaves under stable GlobalKeys, so
  // this State object is reused when its slot is asked to render a different page
  // (e.g. a surah-index jump or an ASR follow). Re-fetch the future when the page
  // number changes, otherwise the FutureBuilder keeps resolving the old page and
  // the render stays frozen while the title/footer advance.
  @override
  void didUpdateWidget(_PageContent old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) {
      _future = widget.repo.page(widget.page);
    }
  }

  void _retry() => setState(() => _future = widget.repo.page(widget.page));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MushafPage>(
      future: _future,
      initialData: widget.repo.cachedPage(widget.page),
      builder: (context, snap) {
        if (snap.hasError) {
          final soft = widget.dark ? AppColors.nightInkSoft : AppColors.inkSoft;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: soft, size: 28),
                const SizedBox(height: 10),
                Text('This page could not be loaded.',
                    style: TextStyle(color: soft, fontSize: 13.5)),
                const SizedBox(height: 10),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snap.hasData) return const SizedBox.expand();
        return MushafPageView(
          page: snap.data!,
          basmalaWords: widget.basmala,
          highlighted: widget.highlighted,
          hidden: widget.hidden,
          revealed: widget.revealed,
          currentVerseKey: widget.currentVerseKey,
          currentLocations: widget.currentLocations,
          skipped: widget.skipped,
          onWordTap: widget.onWordTap,
          onWordLongPress: widget.onWordLongPress,
        );
      },
    );
  }
}

class _GutterShadow extends StatelessWidget {
  final bool fromLeft;
  final bool dark;
  const _GutterShadow({required this.fromLeft, required this.dark});

  @override
  Widget build(BuildContext context) {
    final deep = Colors.black.withValues(alpha: dark ? 0.42 : 0.20);
    final mid = Colors.black.withValues(alpha: dark ? 0.14 : 0.06);
    return IgnorePointer(
      child: Container(
        width: 30,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: fromLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [deep, mid, Colors.transparent],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Thin stacked page-edge lines along the fore-edge (paper block of a book).
class _BookEdgesPainter extends CustomPainter {
  final bool onRight;
  final bool dark;
  const _BookEdgesPainter({required this.onRight, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    const n = 7;
    const gap = 2.0;
    final color = dark ? Colors.white : const Color(0xFF6B5A2E);
    for (var i = 0; i < n; i++) {
      final x = onRight ? size.width - 1 - i * gap : 1 + i * gap;
      final a = (dark ? 0.22 : 0.16) * (1 - i / n);
      canvas.drawLine(
        Offset(x, 2),
        Offset(x, size.height - 2),
        Paint()
          ..color = color.withValues(alpha: a)
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(_BookEdgesPainter old) =>
      old.onRight != onRight || old.dark != dark;
}

class _TopBar extends StatelessWidget {
  final int page;
  final QuranRepository repo;
  final VoidCallback onIndex;
  const _TopBar({
    required this.page,
    required this.repo,
    required this.onIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Row(
        children: [
          // The reader is a pushed route now, so it needs its own way back to the
          // list/home it was opened from.
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: onIndex,
            tooltip: 'Surah index',
          ),
          Expanded(
            child: Text(
              repo.chapterForPageSync(page)?.nameSimple ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: Icon(Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded),
            onPressed: () => context.read<AppState>().cycleTheme(),
            tooltip: 'Toggle theme',
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int page;
  final QuranRepository repo;
  const _BottomBar({required this.page, required this.repo});

  @override
  Widget build(BuildContext context) {
    final soft = Theme.of(context).brightness == Brightness.dark
        ? AppColors.nightInkSoft
        : AppColors.inkSoft;
    final style = TextStyle(color: soft, fontSize: 12.5);
    final strong =
        TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w600);
    final m = repo.metaSync(page);
    final left = m == null
        ? ''
        : 'Juz ${m.juz}  ·  Ḥizb ${m.hizb}${m.quarterLabel.isEmpty ? '' : ' ${m.quarterLabel}'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(left, style: style),
          Text('Page $page', style: strong),
        ],
      ),
    );
  }
}
