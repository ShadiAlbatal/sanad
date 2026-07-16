import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/asr/asr_engine.dart';
import '../state/app_state.dart';
import '../state/dua_finder_state.dart';
import '../state/reading_state.dart';
import '../widgets/dua_finder_footer.dart';
import '../widgets/reading_footer.dart';
import 'dua_list_screen.dart';
import 'home_screen.dart';
import 'quran_screen.dart';

class RootScaffold extends StatelessWidget {
  const RootScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    // Provided ABOVE the Scaffold so both the bottom DuaFinderFooter and the
    // DuaListScreen (inside the IndexedStack) read the ONE shared finder.
    return ChangeNotifierProvider(
      create: (ctx) => DuaFinderState(ctx.read<AsrEngine>()),
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
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tab = app.tabIndex;
    final onDua = tab == Tabs.dua;
    final onQuran = tab == Tabs.quran;

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
    // Symmetric guard for the Quran reader: leaving the Quran tab mid-recitation
    // must stop the mic (the mic control lives only on the Quran footer, and the
    // IndexedStack keeps ReadingState alive so it would otherwise run invisibly).
    if (_lastTab == Tabs.quran && tab != Tabs.quran) {
      final reading = context.read<ReadingState>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (reading.asrActive) reading.stopAsrListening();
        reading.clearRetainedPcm(); // free ~19 MB voice buffer on leaving the reader
      });
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
            QuranScreen(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quran & Azkar are immersive (tab bar hidden), so their footers are
            // the bottom-most bar and must reserve the system nav-bar inset
            // themselves; on Home the NavigationBar below owns that inset.
            if (onQuran)
              SafeArea(top: false, child: const ReadingFooter(showMic: true)),
            if (onDua)
              SafeArea(top: false, child: const DuaFinderFooter()),
            // Only Home shows the tab bar; the phone back button (PopScope above)
            // returns to Home from the immersive Duas/Quran tabs.
            if (tab == Tabs.home)
              NavigationBar(
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
                ],
              ),
          ],
        ),
      ),
    );
  }
}
