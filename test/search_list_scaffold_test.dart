import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/widgets/heard_ticker.dart';
import 'package:sanad/widgets/hearing_indicator.dart';
import 'package:sanad/widgets/mic_toggle_button.dart';
import 'package:sanad/widgets/search_list_scaffold.dart';

/// Pins the shared shell every content tab renders through: a lazy content list +
/// a footer that ALWAYS carries the mic control and the search bar, and swaps the
/// idle prompt for the hearing indicator + heard-ticker once listening. This is
/// what makes the Dua and Hadith tabs identical.
void main() {
  Widget wrap({
    required bool listening,
    required bool loading,
    int itemCount = 3,
    ValueChanged<String>? onSearchChanged,
    VoidCallback? onMicTap,
  }) {
    return MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light(primary: Color(0xFF9B22C3))),
      home: SearchListScaffold(
        title: 'Title',
        subtitle: 'Subtitle',
        loading: loading,
        itemCount: itemCount,
        itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
        listening: listening,
        starting: false,
        level: 0.5,
        heard: 'ابجد',
        idlePrompt: 'Recite to find',
        hearingLabel: 'Hearing: X?',
        onMicTap: onMicTap ?? () {},
        onSearchChanged: onSearchChanged,
        searchHint: 'Search',
      ),
    );
  }

  testWidgets('footer always shows the mic button and the search field', (tester) async {
    await tester.pumpWidget(wrap(listening: false, loading: false));
    expect(find.byType(MicToggleButton), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search'), findsOneWidget); // hint
  });

  testWidgets('idle: shows the prompt, no hearing indicator or ticker', (tester) async {
    await tester.pumpWidget(wrap(listening: false, loading: false));
    expect(find.text('Recite to find'), findsOneWidget);
    expect(find.byType(HearingIndicator), findsNothing);
    expect(find.byType(HeardTicker), findsNothing);
  });

  testWidgets('listening: swaps in the hearing indicator + heard ticker', (tester) async {
    await tester.pumpWidget(wrap(listening: true, loading: false));
    expect(find.byType(HearingIndicator), findsOneWidget);
    expect(find.byType(HeardTicker), findsOneWidget);
    expect(find.text('Recite to find'), findsNothing);
    expect(find.byType(MicToggleButton), findsOneWidget); // mic still there
    expect(find.byType(TextField), findsOneWidget); // search still there
  });

  testWidgets('loading: spinner instead of the list, footer still present',
      (tester) async {
    await tester.pumpWidget(wrap(listening: false, loading: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('row 0'), findsNothing);
    expect(find.byType(MicToggleButton), findsOneWidget);
  });

  testWidgets('list renders the caller rows when not loading', (tester) async {
    await tester.pumpWidget(wrap(listening: false, loading: false, itemCount: 2));
    expect(find.text('row 0'), findsOneWidget);
    expect(find.text('row 1'), findsOneWidget);
  });

  testWidgets('mic tap and search onChanged fire through', (tester) async {
    var taps = 0;
    String? typed;
    await tester.pumpWidget(wrap(
      listening: false,
      loading: false,
      onMicTap: () => taps++,
      onSearchChanged: (q) => typed = q,
    ));
    await tester.tap(find.byType(MicToggleButton));
    expect(taps, 1);
    await tester.enterText(find.byType(TextField), 'salam');
    expect(typed, 'salam');
  });
}
