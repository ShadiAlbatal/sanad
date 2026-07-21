import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sanad/data/prefs.dart';
import 'package:sanad/screens/voice_search_list_mixin.dart';
import 'package:sanad/services/asr/asr_engine.dart';
import 'package:sanad/services/asr/word_asr.dart';
import 'package:sanad/state/app_state.dart';
import 'package:sanad/state/voice_search_state.dart';
import 'package:sanad/util/log.dart';
import 'package:sanad/widgets/mic_toggle_button.dart';
import 'package:sanad/widgets/search_list_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sanad/l10n/app_localizations.dart';

/// The shared voice+typed search shell ([VoiceSearchListMixin]) as the three list
/// tabs actually use it. Pins the query/results/empty-state contract around the
/// mic toggle: starting a recording must drop BOTH the results and the query, or
/// the tab renders "No matches — clear the search" over a field the user just
/// watched empty (and which therefore shows no X button to clear with).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Log's flush Timer.periodic is created lazily on the first line and never
  // cancelled. Create it here, outside any test's fake-async zone, so it isn't
  // reported as a pending timer when a test that logs tears down.
  setUpAll(() => Log.d('test', 'warm the log flush timer'));

  Future<Widget> harness() async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(Prefs(await SharedPreferences.getInstance()));
    app.tabIndex = Tabs.quran;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<VoiceSearchState>.value(value: _FakeVoice()),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
home: _Screen()),
    );
  }

  testWidgets('tapping the mic clears the query, not just the results',
      (tester) async {
    await tester.pumpWidget(await harness());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'الدعوة');
    await tester.pump(const Duration(milliseconds: 300)); // clear the debounce
    expect(find.text('hit-الدعوة'), findsOneWidget);

    await tester.tap(find.byType(MicToggleButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final state = tester.state<_ScreenState>(find.byType(_Screen));
    expect(state.query, isEmpty, reason: 'a new recording starts from a clean query');
    expect(state.searching, isFalse);
    expect(find.text('No matches'), findsNothing,
        reason: 'the empty field must not claim the recitation matched nothing');
    expect(find.text('browse'), findsOneWidget, reason: 'the browse list is reachable');
  });

  testWidgets('a recording that yields no transcript still leaves the list browsable',
      (tester) async {
    await tester.pumpWidget(await harness());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'زقاق'); // no hits
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No matches'), findsOneWidget);

    // Mic tap, then silence: the fake never notifies with a transcript, exactly
    // like a denied mic or a recording the model decodes to ''.
    await tester.tap(find.byType(MicToggleButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('No matches'), findsNothing,
        reason: 'silence must not strand the tab on a stale empty state');
    expect(find.text('browse'), findsOneWidget);
  });
}

/// A [VoiceSearchState] that never touches the mic or the 125MB word model.
class _FakeVoice extends VoiceSearchState {
  _FakeVoice() : super(AsrEngine(), WordAsr());
  @override
  bool get recording => false;
  @override
  Future<void> start() async {}
}

class _Screen extends StatefulWidget {
  const _Screen();
  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen>
    with VoiceSearchListMixin<_Screen, String> {
  @override
  int get voiceTab => Tabs.quran;
  @override
  String get logTag => 'test';
  @override
  List<String> runSearch(String q) => q == 'زقاق' ? const [] : ['hit-$q'];
  @override
  ({String id, double score}) scoreOf(String hit) => (id: hit, score: 1);
  @override
  void openHit(String hit) {}

  @override
  Widget build(BuildContext context) => SearchListScaffold(
        title: 'T',
        itemCount: searching ? results.length : 1,
        itemBuilder: (_, i) => Text(searching ? results[i] : 'browse'),
        emptyState: searching ? const Center(child: Text('No matches')) : null,
        listening: false,
        starting: false,
        level: 0,
        heard: '',
        hearingLabel: 'h',
        onMicTap: toggleMic,
        searchController: searchController,
        onSearchChanged: onSearchChanged,
      );
}
