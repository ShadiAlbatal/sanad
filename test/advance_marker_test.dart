import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/state/reading_state.dart';

/// Pins the shared anti-teleport marker catch-up ([advanceMarker]) — previously
/// duplicated byte-for-byte in ReadingState and DuaReadingState (a tuning-drift
/// hazard). The curve: forward small gaps step 1, medium gaps close half (ceil),
/// a big gap (>8) jumps at once, and any backward move follows immediately.
void main() {
  test('no gap: marker stays', () {
    expect(advanceMarker(5, 5), 5);
  });

  test('backward: follows immediately to the cursor', () {
    expect(advanceMarker(10, 4), 4);
    expect(advanceMarker(10, 0), 0);
  });

  test('small forward gap (<=2): steps exactly one', () {
    expect(advanceMarker(5, 6), 6); // gap 1
    expect(advanceMarker(5, 7), 6); // gap 2 -> +1
  });

  test('medium forward gap (3..8): closes half, rounded up', () {
    expect(advanceMarker(0, 3), 2); // gap 3 -> ceil(1.5)=2
    expect(advanceMarker(0, 4), 2); // gap 4 -> 2
    expect(advanceMarker(0, 7), 4); // gap 7 -> ceil(3.5)=4
    expect(advanceMarker(0, 8), 4); // gap 8 -> 4
  });

  test('big forward gap (>8): jumps straight to the cursor (real relocation)', () {
    expect(advanceMarker(0, 9), 9);
    expect(advanceMarker(2, 40), 40);
  });

  test('repeated application converges upward without overshooting', () {
    var m = 0;
    const target = 20;
    for (var i = 0; i < 20 && m < target; i++) {
      final next = advanceMarker(m, target);
      expect(next, greaterThan(m)); // always makes progress
      expect(next, lessThanOrEqualTo(target)); // never overshoots
      m = next;
    }
    expect(m, target);
  });
}
