import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/widgets/chevron_button.dart';

/// Pins the screen-reader label for the shared reveal-chevron control
/// (previously three icon-only, unlabeled InkWell copies -- the memorization
/// step-reveal row was entirely silent to TalkBack).
void main() {
  testWidgets('exposes its semantic label as a button and forwards taps',
      (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChevronButton(
          icon: Icons.chevron_left_rounded,
          fg: Colors.black,
          dark: false,
          semanticLabel: 'Reveal next word',
          onTap: () => taps++,
        ),
      ),
    ));
    final node = tester.getSemantics(find.byType(ChevronButton));
    expect(node.label, 'Reveal next word');
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);

    await tester.tap(find.byType(ChevronButton));
    expect(taps, 1);
    handle.dispose();
  });
}
