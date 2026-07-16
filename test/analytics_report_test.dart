import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/services/analytics.dart';
import 'package:tilawa_ai/services/asr/pronunciation_head.dart' show Deviation;
import 'package:tilawa_ai/services/asr/session.dart';

/// Pins the pure end-of-session report builder — its shape for both pipelines and,
/// most importantly, the "never audio / never PII" guarantee: the report can only
/// ever contain the whitelisted fields, so a mistake's audio sample range and its
/// per-phoneme scores can never leak into what would be uploaded.
void main() {
  RecitationMistake mispron(String loc) => RecitationMistake(
        kind: MistakeKind.mispronounced,
        location: loc,
        expectedText: 'قَالَ',
        heardText: 'قول',
        prob: 0.42,
        // audio range + phoneme scores that MUST NOT reach the report
        phonemes: const [PhonemeScore('ق', 12, 0.11, Deviation.major)],
        startSample: 16000,
        endSample: 32000,
      );
  RecitationMistake skip(String loc) => RecitationMistake(
        kind: MistakeKind.skipped,
        location: loc,
        expectedText: 'وَ',
        heardText: '',
        prob: null,
        phonemes: const [],
        startSample: -1,
        endSample: -1,
      );

  test('quran report has the expected shape', () {
    final r = buildSessionReport(
      kind: 'quran',
      ref: '2',
      reached: 40,
      tokens: 217,
      anchored: true,
      skipped: 1,
      mistakes: [mispron('2:2:1'), skip('2:3:1')],
      durationMs: 45000,
      platform: 'android',
    );
    expect(r['schema'], 1);
    expect(r['kind'], 'quran');
    expect(r['surah'], 2);
    expect(r.containsKey('duaId'), isFalse);
    expect(r['reached'], 40);
    expect(r['tokens'], 217);
    expect(r['anchored'], true);
    expect(r['skipped'], 1);
    expect(r['mistakeCount'], 2);
    expect(r['durationMs'], 45000);
    expect(r['platform'], 'android');
    expect(r['app'], appBuildId);
  });

  test('dua report uses duaId, not surah', () {
    final r = buildSessionReport(
      kind: 'dua',
      ref: 'dua-aslamtu-nafsi',
      reached: 8,
      tokens: 60,
      anchored: false,
      skipped: 0,
      mistakes: const [],
      durationMs: 12000,
      platform: 'android',
    );
    expect(r['kind'], 'dua');
    expect(r['duaId'], 'dua-aslamtu-nafsi');
    expect(r.containsKey('surah'), isFalse);
    expect(r['mistakeCount'], 0);
    expect(r['mistakes'], isEmpty);
  });

  test('each mistake is slimmed to kind/loc/expected/heard only', () {
    final r = buildSessionReport(
      kind: 'quran',
      ref: '2',
      reached: 5,
      tokens: 30,
      anchored: true,
      skipped: 0,
      mistakes: [mispron('2:2:1')],
      durationMs: 5000,
      platform: 'ios',
    );
    final m = (r['mistakes'] as List).single as Map<String, dynamic>;
    expect(m.keys.toSet(), {'kind', 'loc', 'expected', 'heard'});
    expect(m['kind'], 'mispronounced');
    expect(m['loc'], '2:2:1');
    expect(m['heard'], 'قول');
  });

  test('crash report is anonymous, kind=crash, clipped, no stack/PII', () {
    final longErr = 'X' * 500;
    final r = buildCrashReport(
      error: '  $longErr  ',
      library: 'widgets library',
      fatal: false,
      platform: 'android',
    );
    expect(r['kind'], 'crash');
    expect(r['library'], 'widgets library');
    expect(r['fatal'], false);
    expect(r['app'], appBuildId);
    expect((r['error'] as String).length, lessThanOrEqualTo(301)); // 300 + ellipsis
    expect((r['error'] as String).startsWith('X'), isTrue);
    final wire = jsonEncode(r).toLowerCase();
    for (final banned in ['stack', 'pcm', 'wav', 'audio', 'name', 'email', 'anon']) {
      expect(wire.contains(banned), isFalse, reason: 'crash report leaked "$banned"');
    }
  });

  test('GUARANTEE: no audio-range / phoneme-score / PII field can reach the wire', () {
    final r = buildSessionReport(
      kind: 'quran',
      ref: '2',
      reached: 40,
      tokens: 217,
      anchored: true,
      skipped: 1,
      mistakes: [mispron('2:2:1'), skip('2:3:1')],
      durationMs: 45000,
      platform: 'android',
    );
    final wire = jsonEncode(r).toLowerCase();
    for (final banned in [
      'startsample',
      'endsample',
      'phonemes',
      'prob',
      'pcm',
      'wav',
      'audio',
      'sample',
      'name',
      'email',
    ]) {
      expect(wire.contains(banned), isFalse, reason: 'report leaked "$banned"');
    }
  });
}
