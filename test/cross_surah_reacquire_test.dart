import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/state/reading_state.dart';

/// Pins the PURE cross-surah re-acquisition decision (decideReacquire). This is
/// deliberately the only unit-testable slice: ReadingState itself builds a
/// MicSource/AudioRecorder that hits a platform channel and cannot be
/// constructed under `flutter test`, which is exactly why the switch/debounce
/// logic was extracted into a top-level pure function.
///
/// NOTE: this pins the decision MECHANISM only. It cannot prove behavior on live
/// audio — the stall detection, probing, and localizer scoring run on-device and
/// the thresholds (floor/margin/confirm) still need on-device tuning.
void main() {
  const margin = 0.3;
  const floor = 0.9;
  const confirm = 3;

  ReacquireDecision decide(
    int current,
    Map<int, double> scores, {
    int prevWinner = -1,
    int prevWinStreak = 0,
  }) =>
      decideReacquire(
        current: current,
        scores: scores,
        prevWinner: prevWinner,
        prevWinStreak: prevWinStreak,
        switchMargin: margin,
        switchFloor: floor,
        confirmProbes: confirm,
      );

  test('no switch when the current surah is the best match', () {
    final d = decide(1, {1: 2.0, 2: 1.5, 3: 0.4});
    expect(d.switchTo, isNull);
    expect(d.winner, -1);
    expect(d.winStreak, 0);
  });

  test('no switch when a challenger leads but not by the margin', () {
    // 2 beats current(1) by only 0.2 < margin(0.3).
    final d = decide(1, {1: 1.5, 2: 1.7});
    expect(d.switchTo, isNull);
    expect(d.winner, -1);
  });

  test('no switch when the challenger fails the absolute floor', () {
    // 2 beats current by the margin, but 0.85 < floor(0.9).
    final d = decide(1, {1: 0.4, 2: 0.85});
    expect(d.switchTo, isNull);
    expect(d.winner, -1);
  });

  test('a qualifying challenger builds a streak but does not switch early', () {
    var d = decide(1, {1: 0.3, 2: 1.6});
    expect(d.winner, 2);
    expect(d.winStreak, 1);
    expect(d.switchTo, isNull);

    d = decide(1, {1: 0.3, 2: 1.6}, prevWinner: d.winner, prevWinStreak: d.winStreak);
    expect(d.winner, 2);
    expect(d.winStreak, 2);
    expect(d.switchTo, isNull);
  });

  test('switch fires once a challenger clears floor+margin for confirmProbes in a row', () {
    var winner = -1, streak = 0;
    int? switchTo;
    for (var i = 0; i < confirm; i++) {
      final d = decide(1, {1: 0.3, 2: 1.6}, prevWinner: winner, prevWinStreak: streak);
      winner = d.winner;
      streak = d.winStreak;
      switchTo = d.switchTo;
    }
    expect(streak, confirm);
    expect(switchTo, 2);
  });

  test('a change of winner resets the streak', () {
    // Surah 2 has led twice; now surah 3 takes over — streak restarts at 1.
    final d = decide(1, {1: 0.3, 2: 0.95, 3: 1.8}, prevWinner: 2, prevWinStreak: 2);
    expect(d.winner, 3);
    expect(d.winStreak, 1);
    expect(d.switchTo, isNull);
  });

  test('any probe with no qualifying challenger clears an existing streak', () {
    // Was building a streak on surah 2, but this probe the current surah wins.
    final d = decide(1, {1: 2.0, 2: 1.0}, prevWinner: 2, prevWinStreak: 2);
    expect(d.winner, -1);
    expect(d.winStreak, 0);
    expect(d.switchTo, isNull);
  });

  test('an empty score map is a safe no-op', () {
    final d = decide(1, const {});
    expect(d.switchTo, isNull);
    expect(d.winner, -1);
    expect(d.winStreak, 0);
  });

  test('tie between challengers → first-scored wins (map is built ascending, so lowest surah)', () {
    final d = decide(1, {1: 0.2, 3: 1.6, 5: 1.6});
    expect(d.winner, 3);
  });

  test('current surah absent from scores → baseline 0, challenger can qualify', () {
    final d = decide(1, {2: 1.6});
    expect(d.winner, 2);
    expect(d.winStreak, 1);
  });

  group('reacqStalled', () {
    bool stalled({
      double rms = 500,
      bool anchored = true,
      int tokens = 0,
      int lastProgress = 0,
    }) =>
        reacqStalled(
          rms: rms,
          rmsFloor: 120,
          anchored: anchored,
          tokens: tokens,
          lastProgressTokens: lastProgress,
          stallTokens: 40,
          neverAnchorTokens: 80,
        );

    test('silence is never a stall', () {
      expect(stalled(rms: 10, anchored: true, tokens: 999), isFalse);
      expect(stalled(rms: 10, anchored: false, tokens: 999), isFalse);
    });

    test('anchored: stalls only after stallTokens of no progress', () {
      expect(stalled(anchored: true, tokens: 139, lastProgress: 100), isFalse);
      expect(stalled(anchored: true, tokens: 140, lastProgress: 100), isTrue);
    });

    test('never anchored: stalls only past neverAnchorTokens of audio', () {
      expect(stalled(anchored: false, tokens: 79), isFalse);
      expect(stalled(anchored: false, tokens: 80), isTrue);
    });
  });
}
