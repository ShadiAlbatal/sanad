import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/widgets/mic_toggle_button.dart';

/// Pins the screen-reader label + button/toggle semantics for the shared mic
/// control (previously three icon-only, unlabeled GestureDetector copies —
/// the app's most central control was silent to TalkBack).
void main() {
  Future<void> pump(WidgetTester tester,
      {required bool active, required bool starting, VoidCallback? onTap}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light(primary: Color(0xFF9B22C3))),
      home: Scaffold(
        body: MicToggleButton(active: active, starting: starting, onTap: onTap ?? () {}),
      ),
    ));
  }

  testWidgets('idle: labeled "Start recitation", a button, not toggled', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, active: false, starting: false);
    final node = tester.getSemantics(find.byType(MicToggleButton));
    expect(node.label, 'Start recitation');
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.isToggled), isFalse);
    handle.dispose();
  });

  testWidgets('active: labeled "Stop recitation, recording" and toggled on',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, active: true, starting: false);
    final node = tester.getSemantics(find.byType(MicToggleButton));
    expect(node.label, 'Stop recitation, recording');
    expect(node.hasFlag(SemanticsFlag.isToggled), isTrue);
    handle.dispose();
  });

  testWidgets('starting: labeled and taps are disabled', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(tester, active: false, starting: true, onTap: () => taps++);
    final node = tester.getSemantics(find.byType(MicToggleButton));
    expect(node.label, 'Starting recitation');
    await tester.tap(find.byType(MicToggleButton));
    expect(taps, 0);
    handle.dispose();
  });

  testWidgets('tapping while idle invokes onTap', (tester) async {
    var taps = 0;
    await pump(tester, active: false, starting: false, onTap: () => taps++);
    await tester.tap(find.byType(MicToggleButton));
    expect(taps, 1);
  });

  testWidgets('custom labels (du\'a finder wording) override the defaults',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MicToggleButton(
          active: false,
          starting: false,
          onTap: () {},
          idleLabel: 'Recite to find a du\'ā',
        ),
      ),
    ));
    final node = tester.getSemantics(find.byType(MicToggleButton));
    expect(node.label, 'Recite to find a du\'ā');
    handle.dispose();
  });
}
