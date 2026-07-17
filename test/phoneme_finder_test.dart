import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/phoneme_finder.dart';

/// Retrieval proof for [PhonemeFinder] over REAL phonemized Bukhari data
/// (test/fixtures/hadith_sample.json, 500 hadith built by
/// tool/build_hadith_phonemes.py). Pure Dart — the fixture is read via dart:io,
/// no Flutter bindings or on-device model needed.
///
/// A "query" is a contiguous ~10-word phoneme sub-span of a real hadith; we
/// assert the finder retrieves that same hadith as top-1/top-5. One test injects
/// ~10% phoneme noise (the model's rough PER) to prove robustness.

const _fixture = 'test/fixtures/hadith_sample.json';
const _queryWords = 10;
const _floor = 1.2;
const _margin = 0.4;

class _Doc {
  final String id;
  final List<String> phonemes;
  final List<int> p2w;
  final int words;
  _Doc(this.id, this.phonemes, this.p2w) : words = p2w.isEmpty ? 0 : p2w.last + 1;
}

List<_Doc> _load() {
  final raw = json.decode(File(_fixture).readAsStringSync()) as List;
  return [
    for (final e in raw)
      _Doc(
        (e as Map<String, dynamic>)['id'] as String,
        [for (final p in (e['phonemes'] as List)) p as String],
        [for (final w in (e['phonemeToWord'] as List)) (w as num).toInt()],
      )
  ];
}

List<String> _wordSpan(_Doc d, int wStart, int wCount) {
  final out = <String>[];
  for (var i = 0; i < d.phonemes.length; i++) {
    final w = d.p2w[i];
    if (w >= wStart && w < wStart + wCount) out.add(d.phonemes[i]);
  }
  return out;
}

List<String> _noisy(List<String> q, List<String> vocab, math.Random rng, double per) {
  final out = <String>[];
  for (final t in q) {
    if (rng.nextDouble() < per) {
      final op = rng.nextDouble();
      if (op < 0.5) {
        out.add(vocab[rng.nextInt(vocab.length)]);
      } else if (op < 0.75) {
        continue;
      } else {
        out.add(t);
        out.add(vocab[rng.nextInt(vocab.length)]);
      }
    } else {
      out.add(t);
    }
  }
  return out;
}

void main() {
  final all = _load();
  final finder = PhonemeFinder([for (final d in all) FindDoc(d.id, d.phonemes)]);
  final vocab = {for (final d in all) ...d.phonemes}.toList();

  // Deterministic sample of hadith long enough for an interior 10-word span.
  final eligible = [for (final d in all) if (d.words >= 15) d];
  final rng = math.Random(20260716);
  final sample = [...eligible]..shuffle(rng);
  final probes = sample.take(150).toList();

  test('fixture loaded (500 real Bukhari hadith)', () {
    expect(all.length, greaterThanOrEqualTo(300));
    expect(eligible.length, greaterThan(100));
  });

  test('clean 10-word span retrieves its hadith (top-1 / top-5)', () {
    var top1 = 0, top5 = 0, n = 0;
    for (final d in probes) {
      final wStart = (d.words - _queryWords) ~/ 2;
      final q = _wordSpan(d, wStart, _queryWords);
      if (q.length < 3) continue;
      n++;
      final res = finder.search(q);
      if (res.isNotEmpty && res.first.id == d.id) top1++;
      if (res.any((r) => r.id == d.id)) top5++;
    }
    final t1 = top1 / n, t5 = top5 / n;
    // ignore: avoid_print
    print('clean: n=$n top1=${(t1 * 100).toStringAsFixed(1)}% top5=${(t5 * 100).toStringAsFixed(1)}%');
    expect(t1, greaterThanOrEqualTo(0.95));
    expect(t5, greaterThanOrEqualTo(0.98));
  });

  test('~10% phoneme noise still retrieves in top-5 for most queries', () {
    final nrng = math.Random(99);
    var top5 = 0, n = 0;
    for (final d in probes) {
      final wStart = (d.words - _queryWords) ~/ 2;
      final clean = _wordSpan(d, wStart, _queryWords);
      if (clean.length < 3) continue;
      final q = _noisy(clean, vocab, nrng, 0.10);
      if (q.length < 3) continue;
      n++;
      final res = finder.search(q);
      if (res.any((r) => r.id == d.id)) top5++;
    }
    final t5 = top5 / n;
    // ignore: avoid_print
    print('noisy(10%): n=$n top5=${(t5 * 100).toStringAsFixed(1)}%');
    expect(t5, greaterThanOrEqualTo(0.90));
  });

  test('a clear match yields a confident, correct decision', () {
    final d = probes.first;
    final wStart = (d.words - _queryWords) ~/ 2;
    final res = finder.search(_wordSpan(d, wStart, _queryWords));
    final decision = decideFind(res, floor: _floor, margin: _margin);
    expect(decision.confident, isTrue);
    expect(decision.pick, d.id);
  });

  test('a too-short query is not confident', () {
    final d = probes.first;
    final res = finder.search(d.phonemes.take(2).toList());
    expect(res, isEmpty);
    expect(decideFind(res, floor: _floor, margin: _margin).confident, isFalse);
  });

  group('duplicate-collapse key', () {
    test('identical collapsed phoneme sequences share a dupKey; different ones differ', () {
      final f = PhonemeFinder([
        FindDoc('a', ['ba', 'ba', 'ta', 'sa', 'la', 'ma']),
        FindDoc('b', ['ba', 'ba', 'ta', 'sa', 'la', 'ma']), // same matn, different id
        FindDoc('c', ['qa', 'la', 'ha', 'wa', 'da', 'na']),
      ]);
      expect(f.dupKeyOf('a'), f.dupKeyOf('b'));
      expect(f.dupKeyOf('a'), isNot(f.dupKeyOf('c')));
      expect(f.dupKeyOf('unknown-id'), 'unknown-id'); // unknown → its own unique key
    });

    test('madd-collapse (elongation within a token) means the two copies still match', () {
      // FindDoc collapses repeated chars WITHIN each phoneme unit, so an elongated
      // vowel ('baa') normalizes to the same token as its plain form ('ba').
      final f = PhonemeFinder([
        FindDoc('plain', ['ba', 'ta', 'sa', 'la']),
        FindDoc('madd', ['baa', 'ta', 'saaa', 'la']), // elongations collapse away
      ]);
      expect(f.dupKeyOf('plain'), f.dupKeyOf('madd'));
    });
  });

  group('foldBestScores (best-ever peak accumulation)', () {
    test('keeps the max each id reaches across probes', () {
      final best = <String, double>{};
      foldBestScores(best, [const MapEntry('x', 0.4), const MapEntry('y', 0.2)],
          queryLen: 40, minQueryLen: 40);
      foldBestScores(best, [const MapEntry('x', 0.3), const MapEntry('y', 0.9)],
          queryLen: 40, minQueryLen: 40);
      expect(best['x'], 0.4); // x decayed but its peak is retained
      expect(best['y'], 0.9);
    });

    test('probes below minLen do NOT accumulate (short-query chance matches ignored)', () {
      final best = <String, double>{};
      foldBestScores(best, [const MapEntry('noise', 2.4)], queryLen: 7, minQueryLen: 40);
      expect(best, isEmpty);
      foldBestScores(best, [const MapEntry('noise', 0.3)], queryLen: 40, minQueryLen: 40);
      expect(best['noise'], 0.3); // only the real, long-span score survives
    });
  });

  group('decideFindBest (best-ever + dup-collapse margin)', () {
    String noDup(String id) => id; // every id distinct

    test('duplicate runner-up is collapsed so the margin is measured vs a DIFFERENT doc', () {
      // Firdaws case: the same matn under two ids leads; a genuinely different
      // hadith trails far behind. Without collapse the margin is ~0 (dup as its own
      // runner-up) and the pick is wrongly declined; with collapse it clears.
      final best = {'dupA': 1.30, 'dupB': 1.28, 'other': 0.40};
      String dup(String id) => id == 'dupA' || id == 'dupB' ? 'same-matn' : id;
      expect(decideFindBest(best, dupKeyOf: dup, floor: 0.9, margin: 0.5).pick, 'dupA');
      // Same scores but treating the duplicate as distinct → margin 0.02 → declines.
      expect(decideFindBest(best, dupKeyOf: noDup, floor: 0.9, margin: 0.5).confident, isFalse);
    });

    test('below the floor is never confident even with a huge margin', () {
      final best = {'a': 0.60, 'b': 0.10};
      expect(decideFindBest(best, dupKeyOf: noDup, floor: 0.9, margin: 0.5).confident, isFalse);
    });

    test('a lone distinct candidate qualifies on floor alone', () {
      final best = {'a': 1.0};
      expect(decideFindBest(best, dupKeyOf: noDup, floor: 0.9, margin: 0.5).pick, 'a');
    });

    test('near-tie between two DIFFERENT hadith declines (noise regime)', () {
      final best = {'a': 0.95, 'b': 0.90};
      expect(decideFindBest(best, dupKeyOf: noDup, floor: 0.9, margin: 0.5).confident, isFalse);
    });
  });
}
