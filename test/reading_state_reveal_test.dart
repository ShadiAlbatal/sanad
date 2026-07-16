import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/state/reading_state.dart';

/// Pins the hidden-mode footer step-reveal (`< << > >>`): forward/back by word
/// and by āyah walk the visible page's words in reading order, stay within one
/// āyah, and never re-reveal or hide a word the reciter already got. Pure
/// logic — no ASR, no device.
void main() {
  // Two āyāt on the page: 1:1 (two words), 1:2 (three words).
  const page = ['1:1:1', '1:1:2', '1:2:1', '1:2:2', '1:2:3'];

  test('forward by word walks one word at a time in reading order', () {
    final revealed = <String>{};
    revealed.addAll(revealForwardLocs(page, revealed, const {}, ayah: false));
    expect(revealed, {'1:1:1'});
    revealed.addAll(revealForwardLocs(page, revealed, const {}, ayah: false));
    expect(revealed, {'1:1:1', '1:1:2'});
    revealed.addAll(revealForwardLocs(page, revealed, const {}, ayah: false));
    expect(revealed, {'1:1:1', '1:1:2', '1:2:1'});
  });

  test('forward by āyah reveals the whole āyah, then the next', () {
    final revealed = <String>{};
    revealed.addAll(revealForwardLocs(page, revealed, const {}, ayah: true));
    expect(revealed, {'1:1:1', '1:1:2'});
    revealed.addAll(revealForwardLocs(page, revealed, const {}, ayah: true));
    expect(revealed, {'1:1:1', '1:1:2', '1:2:1', '1:2:2', '1:2:3'});
  });

  test('back by word hides the last manually revealed word', () {
    final revealed = {'1:1:1', '1:1:2', '1:2:1'};
    revealed.removeAll(revealBackLocs(page, revealed, const {}, ayah: false));
    expect(revealed, {'1:1:1', '1:1:2'});
  });

  test('back by āyah hides the whole āyah', () {
    final revealed = {'1:1:1', '1:1:2', '1:2:1', '1:2:2', '1:2:3'};
    revealed.removeAll(revealBackLocs(page, revealed, const {}, ayah: true));
    expect(revealed, {'1:1:1', '1:1:2'});
  });

  test('forward skips words the reciter already got; back never hides them', () {
    const read = {'1:1:1'};
    final revealed = <String>{...read};
    final fwd = revealForwardLocs(page, revealed, read, ayah: false);
    expect(fwd, {'1:1:2'}); // not 1:1:1 — already read
    revealed.addAll(fwd);
    // A recited word sits in `revealed` too; back must not remove it.
    expect(revealBackLocs(page, revealed, read, ayah: false), {'1:1:2'});
    expect(revealBackLocs(page, {'1:1:1'}, read, ayah: false), isEmpty);
    expect(revealBackLocs(page, {'1:1:1'}, read, ayah: true), isEmpty);
  });

  test('forward at end and back with nothing manual are no-ops', () {
    final full = page.toSet();
    expect(revealForwardLocs(page, full, const {}, ayah: false), isEmpty);
    expect(revealForwardLocs(page, full, const {}, ayah: true), isEmpty);
    expect(revealBackLocs(page, const {}, const {}, ayah: false), isEmpty);
  });

  test('anchored forward reveals the first hidden word AFTER the anchor', () {
    // Reciter started mid-page and reached 1:2:1 (index 2); nothing revealed.
    // `>` should reveal 1:2:2 (index 3), not the page's first word.
    expect(
      revealForwardLocs(page, const {}, const {}, ayah: false, anchorIndex: 2),
      {'1:2:2'},
    );
  });

  test('anchored forward by āyah reveals the still-hidden rest of the anchor word\'s next āyah', () {
    // Reciter read āyah 1:1 (both words) and reached 1:2:1 (index 2); nothing
    // manually revealed. `>>` reveals the still-hidden rest of āyah 1:2.
    const read = {'1:1:1', '1:1:2', '1:2:1'};
    expect(
      revealForwardLocs(page, const {}, read, ayah: true, anchorIndex: 2),
      {'1:2:2', '1:2:3'},
    );
  });

  test('anchored forward falls back to first-hidden-overall when nothing is hidden after the anchor', () {
    // Everything from the anchor onward is already read; only earlier words are
    // hidden — reveal the first of those so the tap still does something.
    const read = {'1:2:1', '1:2:2', '1:2:3'};
    expect(
      revealForwardLocs(page, const {}, read, ayah: false, anchorIndex: 4),
      {'1:1:1'},
    );
  });

  test('anchorIndex: -1 reveals from the page top (unchanged behavior)', () {
    expect(
      revealForwardLocs(page, const {}, const {}, ayah: false, anchorIndex: -1),
      {'1:1:1'},
    );
  });
}
