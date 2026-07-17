import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/state/quran_finder_state.dart';

/// Pins the PURE Quran-pick decision ([decideQuranPick]) — the two gates the live
/// finder layers on top of [QuranSearch]'s floor/margin confidence bar: a minimum
/// query length and a consecutive-probe streak. The state itself builds on the
/// shared MicSource (a platform channel) and cannot run under `flutter test`, which
/// is why this logic is a top-level pure function (mirrors decideHadithPick).
///
/// NOTE: pins the decision MECHANISM only; the confidence of [confident] comes from
/// on-device phoneme scoring, and the thresholds still need device tuning.
void main() {
  const minLen = 24;
  const confirm = 3;

  QuranPickDecision decide(
    int queryLen,
    String? confident, {
    String? prevWinner,
    int prevStreak = 0,
  }) =>
      decideQuranPick(
        queryLen: queryLen,
        confident: confident,
        minQueryLen: minLen,
        prevWinner: prevWinner,
        prevStreak: prevStreak,
        confirm: confirm,
      );

  test('below the min query length never picks, even with a confident verse', () {
    final d = decide(minLen - 1, '2:255');
    expect(d.pick, isNull);
    expect(d.winner, isNull);
    expect(d.streak, 0);
  });

  test('no confident verse → no pick, streak resets', () {
    final d = decide(60, null, prevWinner: '2:255', prevStreak: 2);
    expect(d.pick, isNull);
    expect(d.winner, isNull);
    expect(d.streak, 0);
  });

  test('confident + long enough qualifies but must confirm before a pick', () {
    final d = decide(30, '2:255');
    expect(d.winner, '2:255');
    expect(d.streak, 1);
    expect(d.pick, isNull);
  });

  test('the same verse over confirm probes → returns it', () {
    String? winner;
    var streak = 0;
    String? pick;
    for (var i = 0; i < confirm; i++) {
      final d = decide(40, '2:255', prevWinner: winner, prevStreak: streak);
      winner = d.winner;
      streak = d.streak;
      pick = d.pick;
    }
    expect(streak, confirm);
    expect(pick, '2:255');
  });

  test('does not pick before confirm even while qualifying every probe', () {
    String? winner;
    var streak = 0;
    for (var i = 0; i < confirm - 1; i++) {
      final d = decide(40, '2:255', prevWinner: winner, prevStreak: streak);
      winner = d.winner;
      streak = d.streak;
      expect(d.pick, isNull);
    }
    expect(streak, confirm - 1);
  });

  test('a change of confident verse resets the streak', () {
    final d = decide(40, '1:1', prevWinner: '2:255', prevStreak: 2);
    expect(d.winner, '1:1');
    expect(d.streak, 1);
    expect(d.pick, isNull);
  });

  test('same ayah in a different surah is a different verse — streak resets', () {
    final d = decide(40, '3:1', prevWinner: '2:1', prevStreak: 2);
    expect(d.winner, '3:1');
    expect(d.streak, 1);
    expect(d.pick, isNull);
  });

  test('a probe that drops below min length clears an existing streak', () {
    final d = decide(minLen - 5, '2:255', prevWinner: '2:255', prevStreak: 2);
    expect(d.winner, isNull);
    expect(d.streak, 0);
    expect(d.pick, isNull);
  });

  test('exactly at the min length is allowed (inclusive)', () {
    final d = decide(minLen, '2:255');
    expect(d.winner, '2:255');
    expect(d.streak, 1);
  });
}
