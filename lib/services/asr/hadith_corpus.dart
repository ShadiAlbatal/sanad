import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'phoneme_corpus.dart' show loadPhonemeUnits;
import 'phoneme_finder.dart';
import 'phoneme_matcher.dart' show PhonemeClip;

const String hadithAsset = 'assets/asr/hadith/corpus.json.gz';

/// The bundled hadith corpus (Sahih al-Bukhari + Sahih Muslim). Ships gzipped as
/// an array of `[collection, number, text, [phoneme_int, ...], [word, ...],
/// [phonemeToWord_int, ...]]`, phonemes encoded as indices into tokens.txt line
/// order (see tool/pack_hadith_corpus.py). Drives BOTH paths from one decode:
/// the phoneme-search "Find" ([docs]/[byId]) AND the reader's word-level
/// follow-along ([HadithEntry.clip], the per-hadith [PhonemeClip] + display words).
class HadithCorpus {
  final List<FindDoc> docs;
  final Map<String, HadithEntry> byId; // FindDoc.id ("bukhari:2790") -> display + clip
  const HadithCorpus(this.docs, this.byId);

  /// Pure CPU decode (gunzip + JSON parse + FindDoc collapses), separated from the
  /// platform-channel asset read so it can run inside an `Isolate.run` off the UI
  /// thread (see loadHadithSearch). [vocab] is the tokens.txt unit list; [bytes]
  /// the gzipped asset. The phoneme int stream decodes to raw (uncollapsed) units
  /// so [HadithEntry.phonemes] stays 1:1 with [HadithEntry.phonemeToWord]; FindDoc
  /// madd-collapses its own copy for retrieval.
  factory HadithCorpus.decode(Uint8List bytes, List<String> vocab) {
    final raw = json.decode(utf8.decode(gzip.decode(bytes))) as List;
    final docs = <FindDoc>[];
    final byId = <String, HadithEntry>{};
    for (final e in raw) {
      final row = e as List;
      final collection = row[0] as String;
      final number = (row[1] as num).toInt();
      final text = row[2] as String;
      final phonemes = [for (final c in (row[3] as List)) vocab[(c as num).toInt()]];
      // words/phonemeToWord ride along for the reader (older 4-column assets omit
      // them — the find path still works, follow-along is simply unavailable).
      final words = row.length > 4 ? [for (final w in (row[4] as List)) w as String] : const <String>[];
      final phonemeToWord =
          row.length > 5 ? [for (final w in (row[5] as List)) (w as num).toInt()] : const <int>[];
      final entry = HadithEntry(collection, number, text,
          words: words, phonemes: phonemes, phonemeToWord: phonemeToWord);
      docs.add(FindDoc(entry.id, phonemes, words: words, phonemeToWord: phonemeToWord));
      byId[entry.id] = entry;
    }
    return HadithCorpus(docs, byId);
  }
}

/// Display name for a hadith collection ('bukhari' -> 'Bukhari', 'muslim' ->
/// 'Muslim'), used for the `Bukhari #n` / `Muslim #n` labels the UI shows.
String hadithCollectionName(String collection) =>
    collection.isEmpty ? collection : collection[0].toUpperCase() + collection.substring(1);

class HadithEntry {
  final String collection; // 'bukhari' | 'muslim'
  final int number;
  final String text;
  // Follow-along data (empty on older find-only assets). words[i] is display word
  // i; phonemes is the raw unit sequence; phonemeToWord maps each phoneme to its
  // word index. See [clip].
  final List<String> words;
  final List<String> phonemes;
  final List<int> phonemeToWord;
  const HadithEntry(this.collection, this.number, this.text,
      {this.words = const [], this.phonemes = const [], this.phonemeToWord = const []});

  String get id => '$collection:$number';
  String get label => '${hadithCollectionName(collection)} #$number';

  bool get hasClip => words.isNotEmpty && phonemes.isNotEmpty;

  /// The per-hadith follow-along clip (same shape as a du'a's [DuaClip]): a flat
  /// phoneme sequence + phoneme→word map + the display words. A hadith has no
  /// āyah grouping, so it is a single segment (`ayahBoundaries: [0]`). Null when
  /// the asset carries no word map (older find-only build).
  HadithClip? get clip => hasClip
      ? HadithClip(
          id,
          PhonemeClip(
            wordCount: words.length,
            phonemes: phonemes,
            phonemeToWord: phonemeToWord,
            ayahBoundaries: const [0],
          ),
          words,
        )
      : null;
}

/// A loaded hadith's follow-along clip: the phoneme clip for the matcher + the
/// display words (corpus word IS display word, 1:1, no location map). Sibling of
/// the du'a's `DuaClip` — the reader greens `words[i]` when corpus word `i` lights.
class HadithClip {
  final String id;
  final PhonemeClip clip;
  final List<String> words;
  const HadithClip(this.id, this.clip, this.words);
}

HadithCorpus? _cache;

Future<HadithCorpus> loadHadithCorpus() async {
  final cached = _cache;
  if (cached != null) return cached;

  final vocab = await loadPhonemeUnits();
  final bytes = (await rootBundle.load(hadithAsset)).buffer.asUint8List();
  return _cache = HadithCorpus.decode(bytes, vocab);
}
