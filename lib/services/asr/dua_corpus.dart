import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'phoneme_corpus.dart' show loadPhonemeUnits;
import 'phoneme_finder.dart';

const String duaAsset = 'assets/asr/dua/corpus.json.gz';

/// Display metadata for one du'a in the combined corpus — everything the list
/// screen and finder header need WITHOUT loading the per-du'a reader clip. The
/// reader still loads words/phonemeToWord on demand via loadDuaClip(id).
class DuaMeta {
  final String id;
  final String title;
  final String source;
  final String arabic;
  final String meaning;
  const DuaMeta(this.id, this.title, this.source, this.arabic, this.meaning);
}

/// The bundled du'a find/list corpus (existing 5 + Hisn al-Muslim). Ships gzipped
/// as an array of `[id, title, source, arabic, meaning, [phoneme_int, ...],
/// [word, ...], [phonemeToWord_int, ...]]`, phonemes encoded as indices into
/// tokens.txt line order (see tool/build_dua_corpus.py). The word map rides along
/// for voice candidate-row highlighting (older 6-column assets omit it — find +
/// browse still work, highlight is simply unavailable); the reader still loads its
/// own per-du'a clip via loadDuaClip.
class DuaCorpus {
  final List<FindDoc> docs;
  final List<DuaMeta> metas; // corpus order, drives the browsable list
  final Map<String, DuaMeta> byId;
  const DuaCorpus(this.docs, this.metas, this.byId);

  /// Pure CPU decode (gunzip + JSON parse + FindDoc collapses), separated from the
  /// platform-channel asset read so it can run inside an `Isolate.run` off the UI
  /// thread (see loadDuaSearch). [vocab] is the tokens.txt unit list; [bytes] the
  /// gzipped asset.
  factory DuaCorpus.decode(Uint8List bytes, List<String> vocab) {
    final raw = json.decode(utf8.decode(gzip.decode(bytes))) as List;
    final docs = <FindDoc>[];
    final metas = <DuaMeta>[];
    final byId = <String, DuaMeta>{};
    for (final e in raw) {
      final row = e as List;
      final meta = DuaMeta(row[0] as String, row[1] as String, row[2] as String,
          row[3] as String, row[4] as String);
      final phonemes = [for (final c in (row[5] as List)) vocab[(c as num).toInt()]];
      // words/phonemeToWord ride along for voice-row highlighting (older 6-column
      // assets omit them — find still works, highlight is simply unavailable).
      final words = row.length > 6 ? [for (final w in (row[6] as List)) w as String] : const <String>[];
      final phonemeToWord =
          row.length > 7 ? [for (final w in (row[7] as List)) (w as num).toInt()] : const <int>[];
      docs.add(FindDoc(meta.id, phonemes, words: words, phonemeToWord: phonemeToWord));
      metas.add(meta);
      byId[meta.id] = meta;
    }
    return DuaCorpus(docs, metas, byId);
  }
}

DuaCorpus? _cache;

Future<DuaCorpus> loadDuaCorpus() async {
  final cached = _cache;
  if (cached != null) return cached;
  final vocab = await loadPhonemeUnits();
  final bytes = (await rootBundle.load(duaAsset)).buffer.asUint8List();
  return _cache = DuaCorpus.decode(bytes, vocab);
}
