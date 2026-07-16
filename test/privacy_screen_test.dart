import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/screens/privacy_screen.dart';

/// Smoke-pins the Data & Privacy screen: it renders (all color tokens resolve),
/// shows both the shared / never-shared groups, and states plainly that nothing
/// is uploaded in this build.
void main() {
  Future<void> pump(WidgetTester tester, {Brightness b = Brightness.light}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: b,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF9B22C3),
            brightness: b,
          ),
        ),
        home: const PrivacyScreen(),
      ),
    );
  }

  testWidgets('renders both groups and the not-uploaded note', (tester) async {
    await pump(tester);
    final scrollable = find.byType(Scrollable);
    expect(find.text('Data & Privacy'), findsOneWidget);
    expect(find.text('Shared — only if you opt in'), findsOneWidget);
    // The screen scrolls; below-fold groups are lazily built, so scroll them in.
    await tester.scrollUntilVisible(find.text('Never shared'), 300,
        scrollable: scrollable);
    expect(find.text('Never shared'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('nothing is uploaded'), 300,
        scrollable: scrollable);
    expect(find.textContaining('nothing is uploaded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark theme too', (tester) async {
    await pump(tester, b: Brightness.dark);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Never shared'), 300,
        scrollable: find.byType(Scrollable));
    expect(find.text('Never shared'), findsOneWidget);
  });
}
