import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/asr/asr_engine.dart';
import '../state/app_state.dart';
import '../state/dua_finder_state.dart';
import '../state/hadith_finder_state.dart';
import '../state/quran_finder_state.dart';
import '../state/reading_state.dart';
import 'dua_list_screen.dart';
import 'hadith_search_screen.dart';
import 'home_screen.dart';
import 'quran_list_screen.dart';

class RootScaffold extends StatelessWidget {
  const RootScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    // Provided ABOVE the Scaffold so the Dua/Quran list screens (inside the
    // IndexedStack), which own their footers via the shared SearchListScaffold,
    // read the ONE shared finder each — and the lifecycle guards below can stop
    // them on tab-away/background. (The Quran READER is a pushed route driven by
    // the app-global ReadingState, not these finders.)
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (ctx) => DuaFinderState(ctx.read<AsrEngine>())),
        ChangeNotifierProvider(create: (ctx) => QuranFinderState(ctx.read<AsrEngine>())),
      ],
      child: const _RootView(),
    );
  }
}

class _RootView extends StatefulWidget {
  const _RootView();

  @override
  State<_RootView> createState() => _RootViewState();
}

class _RootViewState extends State<_RootView> with WidgetsBindingObserver {
  int _lastTab = Tabs.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Never leave the mic hot when the app is backgrounded: stop any active
  // recitation pipeline on pause/inactive/hidden (the IndexedStack keeps these
  // states alive, so nothing else would stop them).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    if (!mounted) return;
    final reading = context.read<ReadingState>();
    if (reading.asrActive) reading.stopAsrListening();
    reading.clearRetainedPcm(); // don't hold raw voice audio while backgrounded
    final finder = context.read<DuaFinderState>();
    if (finder.listening) finder.stop();
    final quran = context.read<QuranFinderState>();
    if (quran.listening) quran.stop();
    final hadith = context.read<HadithFinderState>();
    if (hadith.listening) hadith.stop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tab = app.tabIndex;

    // The finder is provided at root and the tabs are an IndexedStack (never
    // disposed on switch), so leaving Azkar won't auto-stop it. Release the
    // shared mic explicitly when we navigate away from Azkar mid-listen (going
    // to Quran and reciting already stops it via claimMic; going Home does not).
    if (_lastTab == Tabs.dua && tab != Tabs.dua) {
      final finder = context.read<DuaFinderState>();
      if (finder.listening) {
        WidgetsBinding.instance.addPostFrameCallback((_) => finder.stop());
      }
    }
    // Symmetric guard for the Quran list's voice finder: its mic lives in the
    // screen, kept alive by the IndexedStack, so leaving the tab mid-listen must
    // stop it (the reader is a pushed route that self-stops on pop).
    if (_lastTab == Tabs.quran && tab != Tabs.quran) {
      final quran = context.read<QuranFinderState>();
      if (quran.listening) {
        WidgetsBinding.instance.addPostFrameCallback((_) => quran.stop());
      }
    }
    // Same for the Hadith finder: its mic lives in the screen, kept alive by the
    // IndexedStack, so leaving the tab mid-listen must stop it.
    if (_lastTab == Tabs.hadith && tab != Tabs.hadith) {
      final hadith = context.read<HadithFinderState>();
      if (hadith.listening) {
        WidgetsBinding.instance.addPostFrameCallback((_) => hadith.stop());
      }
    }
    _lastTab = tab;

    return PopScope(
      // Quran and Azkar aren't pushed routes (they're IndexedStack tabs), so the
      // system back button would otherwise exit the app straight from them. Treat
      // it as "go back to Home" instead — both are immersive (tab bar hidden).
      canPop: tab == Tabs.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.tabIndex = Tabs.home;
      },
      child: Scaffold(
        body: IndexedStack(
          index: tab,
          children: const [
            DuaListScreen(),
            HomeScreen(),
            QuranListScreen(),
            HadithSearchScreen(),
          ],
        ),
        // Only Home shows the tab bar; the phone back button (PopScope above)
        // returns to Home from the immersive list tabs. On those tabs this MUST
        // be null (not an empty Column): a non-null bottomNavigationBar makes the
        // Scaffold zero the bottom viewPadding it passes to its body, which then
        // starves the nested SearchListScaffold footer of its nav-bar inset and
        // hides it behind the Android nav bar. Each list tab carries its own
        // footer via SearchListScaffold.
        bottomNavigationBar: tab != Tabs.home
            ? null
            : NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) => app.tabIndex = i,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.wb_twilight_outlined),
                    selectedIcon: Icon(Icons.wb_twilight_rounded),
                    label: 'Duas',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book_rounded),
                    label: 'Quran',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.format_quote_outlined),
                    selectedIcon: Icon(Icons.format_quote_rounded),
                    label: 'Hadith',
                  ),
                ],
              ),
      ),
    );
  }
}
