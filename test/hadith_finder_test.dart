import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/state/hadith_finder_state.dart';

/// Pins the PURE hadith-pick decision ([decideHadithPick]) — the two gates the
/// live finder layers on top of [HadithSearch]'s floor/margin confidence bar:
/// a minimum query length and a consecutive-probe streak. The state itself builds
/// on the shared MicSource (a platform channel) and cannot run under
/// `flutter test`, which is why this logic is a top-level pure function.
///
/// NOTE: pins the decision MECHANISM only; the confidence of [confident] comes
/// from on-device localizer scoring, and the thresholds still need device tuning.
void main() {
  const minLen = 40;
  const confirm = 3;

  HadithPickDecision decide(
    int queryLen,
    String? confident, {
    String? prevWinner,
    int prevStreak = 0,
  }) =>
      decideHadithPick(
        queryLen: queryLen,
        confident: confident,
        minQueryLen: minLen,
        prevWinner: prevWinner,
        prevStreak: prevStreak,
        confirm: confirm,
      );

  test('below the min query length never picks, even with a confident hadith', () {
    final d = decide(minLen - 1, 'bukhari:6011');
    expect(d.pick, isNull);
    expect(d.winner, isNull);
    expect(d.streak, 0);
  });

  test('no confident hadith → no pick, streak resets', () {
    final d = decide(60, null, prevWinner: 'bukhari:6011', prevStreak: 2);
    expect(d.pick, isNull);
    expect(d.winner, isNull);
    expect(d.streak, 0);
  });

  test('confident + long enough qualifies but must confirm before a pick', () {
    final d = decide(45, 'bukhari:6011');
    expect(d.winner, 'bukhari:6011');
    expect(d.streak, 1);
    expect(d.pick, isNull);
  });

  test('the same hadith over confirm probes → returns it', () {
    String? winner;
    var streak = 0;
    String? pick;
    for (var i = 0; i < confirm; i++) {
      final d = decide(50, 'bukhari:6011', prevWinner: winner, prevStreak: streak);
      winner = d.winner;
      streak = d.streak;
      pick = d.pick;
    }
    expect(streak, confirm);
    expect(pick, 'bukhari:6011');
  });

  test('does not pick before confirm even while qualifying every probe', () {
    String? winner;
    var streak = 0;
    for (var i = 0; i < confirm - 1; i++) {
      final d = decide(50, 'bukhari:6011', prevWinner: winner, prevStreak: streak);
      winner = d.winner;
      streak = d.streak;
      expect(d.pick, isNull);
    }
    expect(streak, confirm - 1);
  });

  test('a change of confident hadith resets the streak', () {
    final d = decide(50, 'bukhari:342', prevWinner: 'bukhari:6011', prevStreak: 2);
    expect(d.winner, 'bukhari:342');
    expect(d.streak, 1);
    expect(d.pick, isNull);
  });

  test('same number in a different collection is a different hadith — streak resets', () {
    final d = decide(50, 'muslim:6011', prevWinner: 'bukhari:6011', prevStreak: 2);
    expect(d.winner, 'muslim:6011');
    expect(d.streak, 1);
    expect(d.pick, isNull);
  });

  test('a probe that drops below min length clears an existing streak', () {
    final d = decide(minLen - 5, 'bukhari:6011', prevWinner: 'bukhari:6011', prevStreak: 2);
    expect(d.winner, isNull);
    expect(d.streak, 0);
    expect(d.pick, isNull);
  });

  test('exactly at the min length is allowed (inclusive)', () {
    final d = decide(minLen, 'bukhari:6011');
    expect(d.winner, 'bukhari:6011');
    expect(d.streak, 1);
  });
}
