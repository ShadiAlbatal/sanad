import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'phoneme_corpus.dart' show loadVersePages;
import 'phoneme_finder.dart';

/// Display + navigation metadata for one Quran verse in the global search corpus —
/// everything a result row and the reader jump need: the "surah:ayah" [id], its
/// [surah]/[ayah] numbers, the joined display [text], and the mushaf [page]
/// (1..604, 0 when the verse index has no entry) to flip the reader to.
class QuranVerseMeta {
  final String id; // "surah:ayah"
  final int surah;
  final int ayah;
  final String text;
  final int page;
  const QuranVerseMeta(this.id, this.surah, this.ayah, this.text, this.page);
}

/// The GLOBAL Quran verse corpus, built at load from the already-bundled
/// per-surah phoneme files (`assets/asr/quran_phonemes/NNN.json`) — no new asset.
/// Each surah is split into its ~verses using `ayahBoundaries` (word-index starts),
/// yielding one [FindDoc] per verse (id "surah:ayah", the verse's own phoneme
/// slice) plus per-verse display text + mushaf page. ~6,236 verses across 114
/// surahs. Sibling of [DuaCorpus]/[HadithCorpus]; unlike them the surah phoneme
/// JSONs store phoneme unit STRINGS directly, so there is no int→vocab decode.
class QuranCorpus {
  final List<FindDoc> docs;
  final List<QuranVerseMeta> verses; // surah/ayah order, drives the browsable list
  final Map<String, QuranVerseMeta> byId;
  const QuranCorpus(this.docs, this.verses, this.byId);

  /// Pure CPU decode (JSON parse + per-verse phoneme slicing + FindDoc collapses),
  /// separated from the platform-channel asset reads so it can run inside an
  /// `Isolate.run` off the UI thread (see loadQuranSearch). [surahJson] is the raw
  /// text of the 114 `quran_phonemes/NNN.json` files (any order); [versePages] the
  /// "surah:ayah" → mushaf page map from [loadVersePages].
  factory QuranCorpus.decode(List<String> surahJson, Map<String, int> versePages) {
    final docs = <FindDoc>[];
    final verses = <QuranVerseMeta>[];
    final byId = <String, QuranVerseMeta>{};
    for (final s in surahJson) {
      final j = json.decode(s) as Map<String, dynamic>;
      final surah = (j['surah'] as num).toInt();
      final words = [for (final w in (j['words'] as List)) w as String];
      final phonemes = [for (final p in (j['phonemes'] as List)) p as String];
      final phonemeToWord = [for (final w in (j['phonemeToWord'] as List)) (w as num).toInt()];
      final boundaries = [for (final b in (j['ayahBoundaries'] as List)) (b as num).toInt()];

      final wordToAyah = List<int>.filled(words.length, 0);
      for (var a = 0; a < boundaries.length; a++) {
        final end = a + 1 < boundaries.length ? boundaries[a + 1] : words.length;
        for (var w = boundaries[a]; w < end; w++) {
          wordToAyah[w] = a;
        }
      }
      // Per-verse phoneme slice + a VERSE-LOCAL word map (word index re-based to
      // the verse's first word) so a matched phoneme maps into that verse's own
      // display words for voice candidate-row highlighting.
      final versePhonemes = List.generate(boundaries.length, (_) => <String>[]);
      final versePhonemeToWord = List.generate(boundaries.length, (_) => <int>[]);
      for (var p = 0; p < phonemes.length; p++) {
        final a = wordToAyah[phonemeToWord[p]];
        versePhonemes[a].add(phonemes[p]);
        versePhonemeToWord[a].add(phonemeToWord[p] - boundaries[a]);
      }

      for (var a = 0; a < boundaries.length; a++) {
        final ayah = a + 1;
        final id = '$surah:$ayah';
        final end = a + 1 < boundaries.length ? boundaries[a + 1] : words.length;
        final verseWords = words.sublist(boundaries[a], end);
        final meta = QuranVerseMeta(id, surah, ayah, verseWords.join(' '), versePages[id] ?? 0);
        docs.add(FindDoc(id, versePhonemes[a],
            words: verseWords, phonemeToWord: versePhonemeToWord[a]));
        verses.add(meta);
        byId[id] = meta;
      }
    }
    verses.sort((a, b) {
      final c = a.surah.compareTo(b.surah);
      return c != 0 ? c : a.ayah.compareTo(b.ayah);
    });
    return QuranCorpus(docs, verses, byId);
  }
}

QuranCorpus? _cache;

/// Read all 114 surah phoneme files + the verse index on the main isolate, then
/// decode. For host tests / synchronous callers; the app uses the off-thread
/// loadQuranSearch. Cached so a second call is free.
Future<QuranCorpus> loadQuranCorpus() async {
  final cached = _cache;
  if (cached != null) return cached;
  final versePages = await loadVersePages();
  final surahJson = <String>[];
  for (var s = 1; s <= 114; s++) {
    final tag = s.toString().padLeft(3, '0');
    surahJson.add(await rootBundle.loadString('assets/asr/quran_phonemes/$tag.json'));
  }
  return _cache = QuranCorpus.decode(surahJson, versePages);
}
