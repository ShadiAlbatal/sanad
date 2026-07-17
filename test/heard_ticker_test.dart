import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/state/reading_state.dart' show recentHeard;
import 'package:sanad/widgets/heard_ticker.dart';

/// Pins the footer "what the model heard" ticker: the pure recent-phoneme
/// window and the widget's RTL / placeholder rendering.
void main() {
  group('recentHeard', () {
    test('empty tail → empty string', () {
      expect(recentHeard(const []), '');
    });

    test('short tail joins every token in order', () {
      expect(recentHeard(['قَ', 'ا', 'لَ']), 'قَالَ');
    });

    test('long tail keeps only the last 12 tokens', () {
      final tail = [for (var i = 0; i < 20; i++) 'ب'];
      expect(recentHeard(tail).length, 12);
    });
  });

  Future<void> pump(WidgetTester tester, String heard) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 300, child: HeardTicker(heard: heard)),
          ),
        ),
      );

  testWidgets('empty heard shows the faint placeholder', (tester) async {
    await pump(tester, '');
    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('heard phonemes render in the Uthmanic font, RTL, one line', (tester) async {
    await pump(tester, 'قَالَ');
    final text = tester.widget<Text>(find.text('قَالَ'));
    expect(text.style!.fontFamily, 'UthmanicHafs');
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.textAlign, TextAlign.right);
    final dir = tester.widget<Directionality>(
      find.ancestor(of: find.text('قَالَ'), matching: find.byType(Directionality)).first,
    );
    expect(dir.textDirection, TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
