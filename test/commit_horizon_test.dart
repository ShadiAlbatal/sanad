import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/state/voice_search_state.dart';

List<String> w(String s) => s.split(' ').where((x) => x.isNotEmpty).toList();

void main() {
  test('commits words two consecutive decodes agree on, front to back', () {
    // prev/cur agree on "a b c"; the tail differs (still settling).
    final out = commitStablePrefix(const [], w('a b c x'), w('a b c y'));
    expect(out, w('a b c'));
  });

  test('never revises an already-committed word even if a later decode changes it', () {
    var committed = commitStablePrefix(const [], w('a b c'), w('a b c'));
    expect(committed, w('a b c'));
    // A later pass revises word 2 — the committed prefix must NOT shrink or change.
    committed = commitStablePrefix(committed, w('a b c'), w('a b Z d'));
    expect(committed, w('a b c'));
  });

  test('extends the committed prefix as more of the tail stabilizes', () {
    var committed = commitStablePrefix(const [], w('a b'), w('a b c')); // agree on a b
    expect(committed, w('a b'));
    committed = commitStablePrefix(committed, w('a b c'), w('a b c d')); // now agree on c
    expect(committed, w('a b c'));
  });

  test('a wobbling tail commits nothing new until it settles', () {
    var committed = commitStablePrefix(const [], w('a b'), w('a b')); // a b committed
    expect(committed, w('a b'));
    // Word 2 flip-flops across passes — never two-in-a-row agreement.
    committed = commitStablePrefix(committed, w('a b'), w('a b x'));
    expect(committed, w('a b'));
    committed = commitStablePrefix(committed, w('a b x'), w('a b y'));
    expect(committed, w('a b')); // still stuck at 2 — x != y
  });

  test('empty / shorter decodes never un-commit', () {
    var committed = commitStablePrefix(const [], w('a b c'), w('a b c'));
    expect(committed, w('a b c'));
    committed = commitStablePrefix(committed, w('a b c'), w('a')); // model produced fewer
    expect(committed, w('a b c'));
  });
}
