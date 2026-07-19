import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/search/search_confidence.dart';

List<({String id, double score})> _r(List<(String, double)> pairs) =>
    [for (final p in pairs) (id: p.$1, score: p.$2)];

void main() {
  test('a stable clear leader fills the ring and auto-opens', () {
    final c = SearchConfidence();
    var out = c.update(_r([('a', 90), ('b', 40)])); // 2.25× lead
    expect(out.confidence, 0.5);
    expect(out.openId, isNull);
    out = c.update(_r([('a', 95), ('b', 42)]));
    expect(out.confidence, 1.0);
    expect(out.openId, 'a');
  });

  test('an ambiguous close field never reaches full (right answer may be #2)', () {
    final c = SearchConfidence();
    for (var i = 0; i < 5; i++) {
      final out = c.update(_r([('a', 40), ('b', 39)])); // 1.03× — not clear
      expect(out.confidence, 0);
      expect(out.openId, isNull);
    }
  });

  test('a changing leader resets the streak', () {
    final c = SearchConfidence();
    c.update(_r([('a', 90), ('b', 40)])); // a: streak 1
    final out = c.update(_r([('b', 90), ('a', 40)])); // leader flips to b
    expect(out.confidence, 0.5); // b streak 1, not full
    expect(out.openId, isNull);
  });

  test('a same-id wobble decays confidence instead of hard-resetting it', () {
    final c = SearchConfidence();
    c.update(_r([('a', 90), ('b', 40)])); // clear, streak 1
    final out = c.update(_r([('a', 50), ('b', 48)])); // same id, one noisy probe
    expect(out.confidence, 0); // (streak-1).clamp(0,1) == 0 from streak 1
    expect(out.openId, isNull);
  });

  test('a single wobble does not erase a longer streak — recovers next probe', () {
    final c = SearchConfidence();
    c.update(_r([('a', 90), ('b', 40)])); // streak 1
    c.update(_r([('a', 95), ('b', 42)])); // streak 2 -> full, would open
    final wobble = c.update(_r([('a', 50), ('b', 48)])); // same id, noisy probe
    expect(wobble.confidence, 0.5); // decays by 1 (2->1), not to 0
    expect(wobble.openId, isNull);
    final recovered = c.update(_r([('a', 95), ('b', 42)])); // clears again
    expect(recovered.confidence, 1.0); // streak 1->2, back to full immediately
    expect(recovered.openId, 'a');
  });

  test('a leader-identity change still resets fully — no partial credit', () {
    final c = SearchConfidence();
    c.update(_r([('a', 90), ('b', 40)])); // a: streak 1
    c.update(_r([('a', 95), ('b', 42)])); // a: streak 2 -> full
    final flipped = c.update(_r([('b', 90), ('a', 40)])); // leader flips to b
    expect(flipped.confidence, 0.5); // b starts fresh at streak 1
    expect(flipped.openId, isNull);
  });

  test('empty results reset', () {
    final c = SearchConfidence();
    c.update(_r([('a', 90), ('b', 40)]));
    final out = c.update(_r([]));
    expect(out.confidence, 0);
    expect(out.openId, isNull);
  });
}
