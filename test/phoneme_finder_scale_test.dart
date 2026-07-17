@Tags(['scale'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/phoneme_finder.dart';

/// Real-scale validation of [PhonemeFinder] over the FULL phonemized Sahih
/// Bukhari corpus (~7008 hadith) built by tool/build_hadith_phonemes.py. The big
/// corpus lives in the session scratchpad (NOT committed, NOT a pubspec asset);
/// point [_corpus] at it or override via the CORPUS env var. Gated behind the
/// `scale` tag so ordinary `flutter test` skips it:
///     flutter test --tags scale test/phoneme_finder_scale_test.dart
///
/// This maps the short-query cliff, prefilter recall@K, and per-query latency at
/// 7000 docs — the K=50 question the 500-doc fixture could not answer.

const _corpusDefault =
    r'C:\Users\salext\AppData\Local\Temp\claude\C--Users-salext-prv-apps-TilawaAi\508e46a4-883f-49e7-a8fc-57a68eea1ce0\scratchpad\hadith_out\bukhari.json';

String get _corpus => Platform.environment['CORPUS'] ?? _corpusDefault;

final RegExp _collapseRe = RegExp(r'(.)\1+');
String _collapse(String s) => s.replaceAllMapped(_collapseRe, (m) => m[1]!);

class _Doc {
  final String id;
  final List<String> phonemes;
  final List<int> p2w;
  final int words;
  _Doc(this.id, this.phonemes, this.p2w) : words = p2w.isEmpty ? 0 : p2w.last + 1;
}

List<_Doc> _load() {
  final raw = json.decode(File(_corpus).readAsStringSync()) as List;
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

/// Mirrors PhonemeFinder's 3-gram prefilter (madd-collapse + space separator +
/// tally desc, id asc tie-break) so we can measure how deep the true doc sits in
/// the candidate ranking BEFORE the localizer rerank. Exposes BOTH the old plain
/// shared-gram COUNT ([rank], the pre-IDF baseline) and the new IDF-weighted score
/// ([rankIdf], what PhonemeFinder ships) so one run proves IDF doesn't regress.
class _Prefilter {
  final List<String> ids;
  final Map<String, List<int>> index = {};
  final Map<String, double> idf = {};
  _Prefilter(List<_Doc> docs) : ids = [for (final d in docs) d.id] {
    for (var d = 0; d < docs.length; d++) {
      final ph = docs[d].phonemes.map(_collapse).toList();
      final seen = <String>{};
      for (var i = 0; i + 3 <= ph.length; i++) {
        seen.add('${ph[i]} ${ph[i + 1]} ${ph[i + 2]}');
      }
      for (final g in seen) {
        (index[g] ??= []).add(d);
      }
    }
    final n = docs.length;
    index.forEach((g, list) => idf[g] = math.log(n / list.length));
  }

  List<int> rank(List<String> query) {
    final q = query.map(_collapse).toList();
    final tally = <int, int>{};
    for (var i = 0; i + 3 <= q.length; i++) {
      final ds = index['${q[i]} ${q[i + 1]} ${q[i + 2]}'];
      if (ds == null) continue;
      for (final d in ds) {
        tally[d] = (tally[d] ?? 0) + 1;
      }
    }
    return tally.keys.toList()
      ..sort((a, b) {
        final c = tally[b]!.compareTo(tally[a]!);
        return c != 0 ? c : ids[a].compareTo(ids[b]);
      });
  }

  List<int> rankIdf(List<String> query) {
    final q = query.map(_collapse).toList();
    final tally = <int, double>{};
    for (var i = 0; i + 3 <= q.length; i++) {
      final g = '${q[i]} ${q[i + 1]} ${q[i + 2]}';
      final ds = index[g];
      if (ds == null) continue;
      final w = idf[g]!;
      for (final d in ds) {
        tally[d] = (tally[d] ?? 0) + w;
      }
    }
    return tally.keys.toList()
      ..sort((a, b) {
        final c = tally[b]!.compareTo(tally[a]!);
        return c != 0 ? c : ids[a].compareTo(ids[b]);
      });
  }
}

void main() {
  final all = _load();

  final buildSw = Stopwatch()..start();
  final finder = PhonemeFinder([for (final d in all) FindDoc(d.id, d.phonemes)]);
  buildSw.stop();

  final prefilter = _Prefilter(all);
  final vocab = {for (final d in all) ...d.phonemes}.toList();
  final idToIndex = {for (var i = 0; i < all.length; i++) all[i].id: i};

  final queryLens = [3, 4, 6, 10, 15];
  final maxLen = queryLens.reduce(math.max);
  final eligible = [for (final d in all) if (d.words >= maxLen) d];
  final rng = math.Random(20260716);
  final probes = ([...eligible]..shuffle(rng)).take(200).toList();

  double indexBytes() {
    var b = 0;
    prefilter.index.forEach((k, v) {
      b += k.length * 2 + 48 + v.length * 8;
    });
    return b / (1024 * 1024);
  }

  void row(String label, List<Object> cols) {
    // ignore: avoid_print
    print('$label\t${cols.join('\t')}');
  }

  test('scale corpus loaded', () {
    // ignore: avoid_print
    print('corpus=$_corpus');
    // ignore: avoid_print
    print('docs=${all.length} eligible(>=$maxLen w)=${eligible.length} '
        'probes=${probes.length} vocab=${vocab.length}');
    // ignore: avoid_print
    print('index: keys=${prefilter.index.length} '
        'build=${buildSw.elapsedMilliseconds}ms footprint=${indexBytes().toStringAsFixed(1)}MB');
    expect(all.length, greaterThan(5000));
  });

  test('accuracy across query lengths (top-1 / top-5)', () {
    row('len', ['n', 'top1%', 'top5%']);
    for (final L in queryLens) {
      var top1 = 0, top5 = 0, n = 0;
      for (final d in probes) {
        final wStart = (d.words - L) ~/ 2;
        final q = _wordSpan(d, wStart, L);
        if (q.length < 3) continue;
        n++;
        final res = finder.search(q);
        if (res.isNotEmpty && res.first.id == d.id) top1++;
        if (res.any((r) => r.id == d.id)) top5++;
      }
      row('$L', [
        n,
        (100 * top1 / n).toStringAsFixed(1),
        (100 * top5 / n).toStringAsFixed(1),
      ]);
    }
  });

  test('prefilter recall@K at len 6 and 10 (plain COUNT vs IDF)', () {
    final ks = [5, 20, 50, 100];
    row('recall@K', ['len', ...ks]);
    for (final mode in ['plain', 'idf']) {
      for (final L in [6, 10]) {
        final hits = {for (final k in ks) k: 0};
        var n = 0;
        for (final d in probes) {
          final wStart = (d.words - L) ~/ 2;
          final q = _wordSpan(d, wStart, L);
          if (q.length < 3) continue;
          n++;
          final ranked = mode == 'plain' ? prefilter.rank(q) : prefilter.rankIdf(q);
          final pos = ranked.indexOf(idToIndex[d.id]!);
          for (final k in ks) {
            if (pos >= 0 && pos < k) hits[k] = hits[k]! + 1;
          }
        }
        row('$mode len$L (n=$n)', [
          for (final k in ks) (100 * hits[k]! / n).toStringAsFixed(1),
        ]);
      }
    }
  });

  test('prefilter recall@50 does not regress under IDF (assert plain<=idf)', () {
    for (final L in [6, 10]) {
      var plainHit = 0, idfHit = 0, n = 0;
      for (final d in probes) {
        final wStart = (d.words - L) ~/ 2;
        final q = _wordSpan(d, wStart, L);
        if (q.length < 3) continue;
        n++;
        final target = idToIndex[d.id]!;
        final pp = prefilter.rank(q).indexOf(target);
        final pi = prefilter.rankIdf(q).indexOf(target);
        if (pp >= 0 && pp < 50) plainHit++;
        if (pi >= 0 && pi < 50) idfHit++;
      }
      row('recall@50 len$L', ['plain=$plainHit', 'idf=$idfHit', 'n=$n']);
      expect(idfHit, greaterThanOrEqualTo(plainHit),
          reason: 'IDF prefilter regressed recall@50 vs plain count at len $L');
    }
  });

  // The isnād-crowding fix, isolated. A CLEAN in-corpus substring always sits at
  // plain-count rank 1 (the doc contains every query gram), so plain vs IDF are
  // identical on the recall table above — the crowding only bites when the query
  // shares heavy isnād boilerplate the true doc does NOT itself contain. We
  // reproduce exactly that: prepend the corpus's single most widely-shared 12-word
  // isnād prefix to each target's DISTINCTIVE matn tail, over targets that do not
  // already carry that boilerplate. Under a plain COUNT the boilerplate's isnād
  // siblings pile up and bury the true doc past top-5; under IDF the boilerplate
  // grams weigh ~0 so the rare matn grams pull the true doc back to the top.
  test('isnād-robustness: boilerplate-prefixed matn — plain COUNT buries the true doc, IDF recovers it', () {
    int df(String g) => prefilter.index[g]?.length ?? 0;
    Set<String> gramsOf(List<String> words) {
      final w = words.map(_collapse).toList();
      return {for (var i = 0; i + 3 <= w.length; i++) '${w[i]} ${w[i + 1]} ${w[i + 2]}'};
    }

    _Doc? bDoc;
    var bScore = -1;
    for (final d in all) {
      if (d.words < 12) continue;
      final s = gramsOf(_wordSpan(d, 0, 12)).fold<int>(0, (a, g) => a + df(g));
      if (s > bScore) {
        bScore = s;
        bDoc = d;
      }
    }
    final boiler = _wordSpan(bDoc!, 0, 12);

    var plainTop5 = 0, idfTop5 = 0, recovered = 0, n = 0;
    for (final d in probes) {
      if (identical(d, bDoc) || d.words < 20) continue;
      final matn = _wordSpan(d, d.words - 6, 6);
      if (matn.length < 4) continue;
      final q = [...boiler, ...matn];
      n++;
      final target = idToIndex[d.id]!;
      final pp = prefilter.rank(q).indexOf(target);
      final pi = prefilter.rankIdf(q).indexOf(target);
      final pIn5 = pp >= 0 && pp < 5;
      final iIn5 = pi >= 0 && pi < 5;
      if (pIn5) plainTop5++;
      if (iIn5) idfTop5++;
      if (!pIn5 && iIn5) recovered++;
    }
    row('isnad boilerplate(12w)+matn(6w)', [
      'n=$n',
      'boilerDF=$bScore',
      'plain-top5=${(100 * plainTop5 / n).toStringAsFixed(1)}',
      'idf-top5=${(100 * idfTop5 / n).toStringAsFixed(1)}',
      'recovered=$recovered',
    ]);
    final plainBuried = n - plainTop5;
    expect(idfTop5, greaterThan(plainTop5),
        reason: 'IDF must rank more boilerplate-crowded matn queries in top-5 than plain count');
    expect(recovered, greaterThanOrEqualTo(plainBuried ~/ 2),
        reason: 'IDF should recover at least half the true docs the plain count buried under isnād boilerplate');
  });

  test('per-query latency at 7000 (len 10)', () {
    final times = <int>[];
    for (final d in probes) {
      final wStart = (d.words - 10) ~/ 2;
      final q = _wordSpan(d, wStart, 10);
      if (q.length < 3) continue;
      final sw = Stopwatch()..start();
      finder.search(q);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    final mean = times.reduce((a, b) => a + b) / times.length / 1000;
    final p95 = times[(times.length * 0.95).floor()] / 1000;
    final max = times.last / 1000;
    row('latency ms', [
      'mean=${mean.toStringAsFixed(2)}',
      'p95=${p95.toStringAsFixed(2)}',
      'max=${max.toStringAsFixed(2)}',
    ]);
  });

  test('noisy ~11% at len 10 (top-1 / top-5)', () {
    final nrng = math.Random(99);
    var top1 = 0, top5 = 0, n = 0;
    for (final d in probes) {
      final wStart = (d.words - 10) ~/ 2;
      final clean = _wordSpan(d, wStart, 10);
      if (clean.length < 3) continue;
      final q = _noisy(clean, vocab, nrng, 0.11);
      if (q.length < 3) continue;
      n++;
      final res = finder.search(q);
      if (res.isNotEmpty && res.first.id == d.id) top1++;
      if (res.any((r) => r.id == d.id)) top5++;
    }
    row('noisy11% len10', [
      'n=$n',
      'top1=${(100 * top1 / n).toStringAsFixed(1)}',
      'top5=${(100 * top5 / n).toStringAsFixed(1)}',
    ]);
  });
}
