import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/state/dua_finder_state.dart';

/// Pins the PURE du'a-identify decision ([identifyDua]) — the "Shazam for du'ās"
/// picker. This is the only unit-testable slice: DuaFinderState itself builds on
/// the shared MicSource/AudioRecorder (a platform channel) and cannot be
/// constructed under `flutter test`, which is why the qualify/debounce logic was
/// extracted into a top-level pure function.
///
/// NOTE: this pins the decision MECHANISM only. It cannot prove behavior on live
/// audio — the localizer scoring runs on-device and the thresholds
/// (floor/margin/confirm) still need on-device tuning.
void main() {
  const floor = 1.2;
  const margin = 0.4;
  const confirm = 3;

  DuaIdentifyDecision decide(
    Map<String, double> scores, {
    String prevWinner = '',
    int prevStreak = 0,
  }) =>
      identifyDua(
        scores: scores,
        prevWinner: prevWinner,
        prevStreak: prevStreak,
        floor: floor,
        margin: margin,
        confirm: confirm,
      );

  test('empty scores → no pick', () {
    final d = decide(const {});
    expect(d.pick, isNull);
    expect(d.winner, '');
    expect(d.streak, 0);
  });

  test('all below floor → no pick even with a clear leader', () {
    final d = decide({'a': 1.0, 'b': 0.2, 'c': 0.1});
    expect(d.pick, isNull);
    expect(d.winner, '');
  });

  test('above floor but margin over 2nd-best too small → no pick', () {
    // a clears floor(1.2) but only leads b by 0.3 < margin(0.4).
    final d = decide({'a': 1.6, 'b': 1.3});
    expect(d.pick, isNull);
    expect(d.winner, '');
  });

  test('qualifies (over floor + margin) but must confirm before a pick', () {
    final d = decide({'a': 2.0, 'b': 1.2, 'c': 0.3});
    expect(d.winner, 'a');
    expect(d.streak, 1);
    expect(d.pick, isNull);
  });

  test('a clear winner over confirm probes → returns it', () {
    var winner = '';
    var streak = 0;
    String? pick;
    for (var i = 0; i < confirm; i++) {
      final d = decide({'a': 2.2, 'b': 1.1, 'c': 0.4}, prevWinner: winner, prevStreak: streak);
      winner = d.winner;
      streak = d.streak;
      pick = d.pick;
    }
    expect(streak, confirm);
    expect(pick, 'a');
  });

  test('does not pick before confirm even while qualifying every probe', () {
    var winner = '';
    var streak = 0;
    for (var i = 0; i < confirm - 1; i++) {
      final d = decide({'a': 2.2, 'b': 1.1}, prevWinner: winner, prevStreak: streak);
      winner = d.winner;
      streak = d.streak;
      expect(d.pick, isNull);
    }
    expect(streak, confirm - 1);
  });

  test('a change of winner resets the streak', () {
    // 'a' has led twice; now 'b' clearly wins — streak restarts at 1, no pick.
    final d = decide({'a': 1.0, 'b': 2.4, 'c': 0.2}, prevWinner: 'a', prevStreak: 2);
    expect(d.winner, 'b');
    expect(d.streak, 1);
    expect(d.pick, isNull);
  });

  test('a probe with no qualifier clears an existing streak', () {
    // Was building a streak on 'a', but this probe nobody clears floor+margin.
    final d = decide({'a': 1.0, 'b': 0.9}, prevWinner: 'a', prevStreak: 2);
    expect(d.winner, '');
    expect(d.streak, 0);
    expect(d.pick, isNull);
  });

  test('a single candidate has no runner-up to beat and qualifies on floor alone', () {
    final d = decide({'a': 1.5});
    expect(d.winner, 'a');
    expect(d.streak, 1);
  });

  test('a lone candidate under the floor still does not qualify', () {
    final d = decide({'a': 0.9});
    expect(d.pick, isNull);
    expect(d.winner, '');
  });

  test('exactly on the floor qualifies (inclusive lower bound)', () {
    final d = decide({'a': 1.2, 'b': 0.5}); // best==floor, comfortably past margin
    expect(d.winner, 'a');
    expect(d.streak, 1);
  });
}
