import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sanad/services/asr/asr_engine.dart';
import 'package:sanad/state/dua_reading_state.dart';
import 'package:sanad/state/reading_state.dart';
import 'package:sanad/util/log.dart';
import 'package:sanad/widgets/chevron_button.dart';
import 'package:sanad/widgets/dua_reading_footer.dart';
import 'package:sanad/widgets/reading_footer.dart';
import 'package:sanad/l10n/app_localizations.dart';

/// The hidden-mode reveal chevrons live INLINE in the footer row (not a row of
/// their own), inside a FittedBox that scales them down to fit. That makes their
/// rendered size a function of how the row divides its free width — so pin it:
/// a stray flex sibling once halved their share and shrank all four to ~19x14,
/// well under a usable tap target, with a 90px empty Spacer sitting beside them.
void main() {
  // Log's flush Timer.periodic is created lazily and never cancelled; create it
  // outside a test's fake-async zone so it isn't seen as a pending timer.
  setUpAll(() => Log.d('test', 'warm the log flush timer'));

  // A phone-sized viewport at 1.0 DPR — the case that actually squeezes.
  const view = Size(360, 800);

  Future<Size> chevronSize(WidgetTester tester, Widget footer) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,

      home: Scaffold(body: Column(children: [const Spacer(), footer])),
    ));
    await tester.pump();
    final finder = find.byType(ChevronButton);
    expect(finder, findsNWidgets(4), reason: 'all four reveal chevrons must render');
    // The FittedBox scales by PAINT TRANSFORM, so the RenderBox size stays 46x34
    // however hard it is squeezed — only the on-screen rect shrinks. Measure that.
    // Sub-pixel rounding makes the four rects differ in the last decimal, so
    // report the smallest — that is the one a thumb has to hit.
    var w = double.infinity, h = double.infinity;
    for (var i = 0; i < 4; i++) {
      final r = tester.getRect(finder.at(i));
      if (r.width < w) w = r.width;
      if (r.height < h) h = r.height;
    }
    return Size(w, h);
  }

  testWidgets('Quran footer: hidden-mode chevrons keep a usable size',
      (tester) async {
    final state = ReadingState(AsrEngine())..toggleHidden();
    addTearDown(state.dispose);
    final size = await chevronSize(
      tester,
      ChangeNotifierProvider<ReadingState>.value(
        value: state,
        child: const ReadingFooter(showMic: true),
      ),
    );
    // Natural size is 46x34; at 360dp the row genuinely cannot fit all four at
    // full size, so some scale-down is expected — but not to a third of it.
    expect(size.width, greaterThan(34), reason: 'chevrons rendered $size');
    expect(size.height, greaterThan(25), reason: 'chevrons rendered $size');
  });

  testWidgets("Du'a footer: hidden-mode chevrons keep a usable size",
      (tester) async {
    final state = DuaReadingState(AsrEngine())..toggleHidden();
    addTearDown(state.dispose);
    final size = await chevronSize(
      tester,
      ChangeNotifierProvider<DuaReadingState>.value(
        value: state,
        child: const DuaReadingFooter(),
      ),
    );
    expect(size.width, greaterThan(34), reason: 'chevrons rendered $size');
    expect(size.height, greaterThan(25), reason: 'chevrons rendered $size');
  });
}
