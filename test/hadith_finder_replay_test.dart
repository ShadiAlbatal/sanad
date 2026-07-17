import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/phoneme_finder.dart';
import 'package:sanad/state/hadith_finder_state.dart';

/// REPLAY of real on-device probe sequences from
/// pulls/run_20260717_023707/logs/run_20260717_023705.log through the calibrated
/// decision (foldBestScores → decideFindBest → decideHadithPick) — grounding the
/// gate choice (floor 0.9, margin 0.5, minLen 40, streak 3) in the very data it
/// was tuned on. Under the OLD floor 1.3 the whole session produced exactly ONE
/// pick (att3, which briefly hit 1.30); att4's correct match decayed below 1.3 as
/// the 60-phoneme window rolled off the matn into the isnād tail and was missed.
/// The recalibrated gates must auto-pick att3 AND att4 while still declining the
/// isnād/noise attempts. Scores are transcribed verbatim from the logged
/// `top=[id:score …]` traces.
///
/// This mirrors HadithFinderState._onPcm exactly; the state itself builds on the
/// platform MicSource and cannot run under `flutter test`, so the pipeline is
/// replayed here from its pure pieces.
typedef Probe = ({int len, List<MapEntry<String, double>> top});

const _floor = 0.9, _margin = 0.5, _minLen = 40, _confirm = 3;

String _identity(String id) => id;

/// Full attempt through the NEW (best-ever) pipeline — returns the picked id/null.
String? _replay(List<Probe> probes, {String Function(String) dupKeyOf = _identity}) {
  final best = <String, double>{};
  String? winner;
  var streak = 0;
  for (final p in probes) {
    foldBestScores(best, p.top, queryLen: p.len, minQueryLen: _minLen);
    final confident = decideFindBest(best, dupKeyOf: dupKeyOf, floor: _floor, margin: _margin).pick;
    final d = decideHadithPick(
      queryLen: p.len,
      confident: confident,
      minQueryLen: _minLen,
      prevWinner: winner,
      prevStreak: streak,
      confirm: _confirm,
    );
    winner = d.winner;
    streak = d.streak;
    if (d.pick != null) return d.pick;
  }
  return null;
}

/// Same attempt WITHOUT best-ever — the per-probe current-window decision, to show
/// window decay defeats it. Uses decideFind over each probe's own scores.
String? _replayNoBestEver(List<Probe> probes) {
  String? winner;
  var streak = 0;
  for (final p in probes) {
    final results = [for (final e in p.top) FindResult(e.key, e.value)];
    final confident = decideFind(results, floor: _floor, margin: _margin).pick;
    final d = decideHadithPick(
      queryLen: p.len,
      confident: confident,
      minQueryLen: _minLen,
      prevWinner: winner,
      prevStreak: streak,
      confirm: _confirm,
    );
    winner = d.winner;
    streak = d.streak;
    if (d.pick != null) return d.pick;
  }
  return null;
}

void main() {
  // att3 (02:43:30) — muslim:81 recited matn-first; the distinctive span fills the
  // window and the score stays high. The two leading below-minLen probes include a
  // chance-match (bukhari:788 at 2.14 for a 7-phoneme span) that must NOT poison
  // the peaks.
  const att3 = <Probe>[
    (len: 7, top: [MapEntry('bukhari:788', 2.14), MapEntry('muslim:1559', 2.14), MapEntry('muslim:81', 1.71)]),
    (len: 29, top: [MapEntry('muslim:81', 1.34), MapEntry('bukhari:1182', 0.52), MapEntry('bukhari:3239', 0.52)]),
    (len: 42, top: [MapEntry('muslim:81', 1.07), MapEntry('bukhari:1182', 0.36), MapEntry('bukhari:3239', 0.36)]),
    (len: 45, top: [MapEntry('muslim:81', 1.07), MapEntry('bukhari:1182', 0.33), MapEntry('bukhari:3239', 0.33)]),
    (len: 57, top: [MapEntry('muslim:81', 1.05), MapEntry('muslim:5327', 0.32), MapEntry('bukhari:1182', 0.26)]),
    (len: 60, top: [MapEntry('muslim:81', 1.00), MapEntry('muslim:5327', 0.30), MapEntry('bukhari:1182', 0.25)]),
  ];

  // att4 (02:43:53) — muslim:81 recited WITH the isnād; the score peaks mid-matn
  // then decays as the window rolls into the (shared, low-idf) isnād tail. All
  // real len-60 values; ordered to show the rolling-window bounce past the peak.
  const att4 = <Probe>[
    (len: 60, top: [MapEntry('muslim:81', 0.55), MapEntry('bukhari:3616', 0.25), MapEntry('bukhari:4066', 0.25)]),
    (len: 60, top: [MapEntry('muslim:81', 0.70), MapEntry('bukhari:3782', 0.25), MapEntry('bukhari:4066', 0.25)]),
    (len: 60, top: [MapEntry('muslim:81', 0.95), MapEntry('bukhari:4063', 0.30), MapEntry('muslim:3110', 0.30)]),
    (len: 60, top: [MapEntry('muslim:81', 0.70), MapEntry('bukhari:3782', 0.25), MapEntry('bukhari:4066', 0.25)]),
    (len: 60, top: [MapEntry('muslim:81', 0.55), MapEntry('bukhari:3616', 0.25), MapEntry('bukhari:4066', 0.25)]),
  ];

  // att1 (02:38:50) — isnād/noise: a short-span chance leader (bukhari:788, and a
  // 3-way 2.40 tie at len 5) that collapses to ~0.3–0.4 once the query is long
  // enough to matter. Nothing at len≥40 clears the floor.
  const att1 = <Probe>[
    (len: 5, top: [MapEntry('bukhari:1018', 2.40), MapEntry('bukhari:1057', 2.40), MapEntry('bukhari:1064', 2.40)]),
    (len: 7, top: [MapEntry('bukhari:788', 2.14), MapEntry('muslim:1559', 2.14), MapEntry('muslim:81', 1.71)]),
    (len: 40, top: [MapEntry('bukhari:788', 0.38), MapEntry('bukhari:233', 0.30), MapEntry('bukhari:244', 0.30)]),
    (len: 44, top: [MapEntry('bukhari:788', 0.34), MapEntry('bukhari:244', 0.27), MapEntry('bukhari:2751', 0.27)]),
    (len: 53, top: [MapEntry('bukhari:6873', 0.34), MapEntry('bukhari:2581', 0.28), MapEntry('bukhari:3923', 0.28)]),
    (len: 60, top: [MapEntry('bukhari:2581', 0.25), MapEntry('bukhari:3923', 0.25), MapEntry('bukhari:6873', 0.25)]),
  ];

  // att2 (02:41:54) — Firdaws: the SAME matn stored under bukhari:6873 and
  // bukhari:2581 leads. dupKeyOf collapses them; the pick is declined on the FLOOR
  // (0.60 < 0.9), so it stays list-only — a correct, safe outcome.
  String firdawsDup(String id) =>
      (id == 'bukhari:6873' || id == 'bukhari:2581') ? 'firdaws' : id;
  const att2 = <Probe>[
    (len: 40, top: [MapEntry('bukhari:6873', 0.60), MapEntry('bukhari:2581', 0.45), MapEntry('bukhari:3645', 0.38)]),
    (len: 43, top: [MapEntry('bukhari:6873', 0.56), MapEntry('bukhari:2581', 0.42), MapEntry('bukhari:3645', 0.35)]),
    (len: 46, top: [MapEntry('bukhari:6873', 0.52), MapEntry('bukhari:2581', 0.39), MapEntry('bukhari:5270', 0.33)]),
  ];

  test('att3 (matn-first) auto-picks muslim:81', () {
    expect(_replay(att3), 'muslim:81');
  });

  test('att4 (isnād + window decay) auto-picks muslim:81 via best-ever peaks', () {
    expect(_replay(att4), 'muslim:81');
  });

  test('att4 is MISSED without best-ever — the window decay is the reason it was lost', () {
    // The single 0.95 peak cannot hold 3 consecutive probes because the window
    // rolls off it; the per-probe streak resets on the sub-floor probes. Best-ever
    // is precisely the lever that fixes this.
    expect(_replayNoBestEver(att4), isNull);
  });

  test('att1 (isnād/noise) is correctly DECLINED — list-only, no auto-pick', () {
    expect(_replay(att1), isNull);
  });

  test('att1 short-span chance matches never poison the best-ever peaks', () {
    // Replay accumulation directly: the 2.40/2.14 leaders live only at len<40 and
    // must be absent; the peak map holds only the ~0.3–0.4 long-span scores.
    final best = <String, double>{};
    for (final p in att1) {
      foldBestScores(best, p.top, queryLen: p.len, minQueryLen: _minLen);
    }
    expect(best.containsKey('bukhari:1018'), isFalse); // len-5 tie, never accumulated
    expect(best['bukhari:788'], 0.38); // its long-span score, not the 2.14 chance peak
    expect(best.values.reduce((a, b) => a > b ? a : b), lessThan(_floor));
  });

  test('att2 (Firdaws duplicate) collapses to one doc and stays list-only on the floor', () {
    expect(_replay(att2, dupKeyOf: firdawsDup), isNull);
  });
}
