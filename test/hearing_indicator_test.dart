import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/theme/app_theme.dart';
import 'package:tilawa_ai/widgets/hearing_indicator.dart';

/// Pins the footer "is it hearing / tracking me?" indicator: hidden when
/// inactive, and the three live states (waiting → Listening → Following) with
/// their colours, plus that it never overflows a tight footer slot.
void main() {
  const accent = Color(0xFF9B22C3);

  Future<void> pump(
    WidgetTester tester, {
    required bool active,
    required double level,
    required bool tracking,
    String? label,
    double width = 400,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light(primary: accent)),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Row(
                children: [
                  Expanded(
                    child: HearingIndicator(
                      active: active,
                      level: level,
                      tracking: tracking,
                      label: label,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  testWidgets('inactive renders nothing', (tester) async {
    await pump(tester, active: false, level: 0.5, tracking: true);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('active + no voice → dim "waiting…"', (tester) async {
    await pump(tester, active: true, level: 0.0, tracking: false);
    expect(find.text('waiting…'), findsOneWidget);
  });

  testWidgets('active + hearing, not tracking → "Listening…" in muted ink', (tester) async {
    await pump(tester, active: true, level: 0.4, tracking: false);
    expect(find.text('Listening…'), findsOneWidget);
    expect(colorOf(tester, 'Listening…'), AppColors.inkSoft);
  });

  testWidgets('tracking → "Following" in the accent', (tester) async {
    await pump(tester, active: true, level: 0.4, tracking: true);
    expect(find.text('Following'), findsOneWidget);
    expect(colorOf(tester, 'Following'), accent);
  });

  testWidgets('a custom label overrides the derived status text', (tester) async {
    await pump(tester, active: true, level: 0.3, tracking: false, label: 'Matching…');
    expect(find.text('Matching…'), findsOneWidget);
    expect(find.text('Listening…'), findsNothing);
  });

  testWidgets('a long label in a tight slot ellipsizes without overflow', (tester) async {
    await pump(
      tester,
      active: true,
      level: 0.3,
      tracking: false,
      width: 80,
      label: 'Hearing: some absurdly long du\'ā title that could never fit?',
    );
    expect(tester.takeException(), isNull);
  });
}
