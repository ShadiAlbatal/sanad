import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/hadith_corpus.dart';
import 'package:sanad/services/asr/hadith_search.dart';

/// End-to-end proof that the PACKAGED, gzipped combined asset
/// (assets/asr/hadith/corpus.json.gz — Bukhari + Muslim) loads, decodes its
/// int-encoded phonemes back to units, and drives the shared PhonemeFinder to
/// retrieve the true hadith. Runs against the REAL bundled asset via rootBundle
/// (hence ensureInitialized), NOT the uncompacted scratchpad corpus.
///
/// Queries are contiguous phoneme spans sliced straight from the shipped corpus,
/// ~40 phonemes ≈ a 10-word matn snippet. The scale test measured ~94% top-5 on
/// word spans at 7000 docs; we assert a conservative 0.85 floor and print the
/// measured number. (The asset now also carries words/phonemeToWord for the
/// reader's follow-along — see hadith_clip_test.dart — but the find path ignores
/// them, so this end-to-end retrieval proof is unaffected.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HadithCorpus corpus;
  late HadithSearch search;

  setUpAll(() async {
    corpus = await loadHadithCorpus();
    search = HadithSearch(corpus);
  });

  test('packaged asset loads and decodes', () {
    expect(corpus.docs.length, greaterThan(5000));
    expect(corpus.byId.length, corpus.docs.length);
    final first = corpus.docs.first;
    expect(first.phonemes, isNotEmpty);
    expect(corpus.byId[first.id]!.text, isNotEmpty);
  });

  test('top-5 retrieval on ~10-word spans clears 0.85', () {
    const window = 40;
    final eligible = [for (final d in corpus.docs) if (d.phonemes.length >= window + 20) d];
    final rng = math.Random(20260716);
    final probes = ([...eligible]..shuffle(rng)).take(200).toList();

    var top5 = 0;
    for (final d in probes) {
      final start = (d.phonemes.length - window) ~/ 2;
      final q = d.phonemes.sublist(start, start + window);
      final res = search.find(q);
      if (res.candidates.any((c) => c.id == d.id)) top5++;
    }
    final rate = top5 / probes.length;
    // ignore: avoid_print
    print('top-5 = ${(100 * rate).toStringAsFixed(1)}% over ${probes.length} probes');
    expect(rate, greaterThanOrEqualTo(0.85));
  });

  test('a strong span returns a confident, correct pick', () {
    final longest = corpus.docs.reduce((a, b) => a.phonemes.length >= b.phonemes.length ? a : b);
    final start = (longest.phonemes.length - 40) ~/ 2;
    final q = longest.phonemes.sublist(start, start + 40);

    final res = search.find(q);
    expect(res.confident, isTrue);
    expect(res.pick, isNotNull);
    expect(res.pick!.id, longest.id);
    expect(res.candidates.map((c) => c.id), contains(res.pick!.id));
  });

  test('an ambiguous short query is not confident but still lists candidates', () {
    final freq = <String, int>{};
    for (final d in corpus.docs) {
      final ph = d.phonemes;
      final seen = <String>{};
      for (var i = 0; i + 3 <= ph.length; i++) {
        seen.add('${ph[i]} ${ph[i + 1]} ${ph[i + 2]}');
      }
      for (final g in seen) {
        freq[g] = (freq[g] ?? 0) + 1;
      }
    }
    final commonest = freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key.split(' ');

    final res = search.find(commonest);
    expect(res.candidates, isNotEmpty);
    expect(res.confident, isFalse);
    expect(res.pick, isNull);
  });
}
