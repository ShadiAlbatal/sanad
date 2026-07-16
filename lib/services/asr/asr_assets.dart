import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

/// Loads the small pre-baked assets the ASR pipeline needs. All of these are
/// derived offline (Python, see tool/_cache and the conversion notes in
/// project memory) from the HF model repo, since Dart has no SentencePiece
/// encoder, no mel-filter construction, and no PyTorch checkpoint loader:
///  - mel_filters.json: (80, 257) slaney mel filterbank matrix
///  - cmvn.json: fixed-global CMVN mean/std (clean_*/tlog_*)
///  - vocab.json: 1024 BPE pieces, index = token id (for decode/embedding)
///  - ref_tokens.json: {"s:a:w": [token ids]} — every mushaf word pre-tokenized
///    with the model's own tokenizer, for forced alignment reference sequences
///  - pronunciation_head.bin (+ manifest): the 1.33M-param pronunciation head
///    checkpoint, as flat float32 arrays
class AsrAssets {
  final List<List<double>> melFilters; // (80, 257)
  final Map<String, List<double>> cmvn; // clean_mean/std, tlog_mean/std
  final List<String> vocab; // 1024 BPE pieces, index = token id
  final Map<String, List<int>> refTokens; // word location -> token ids
  final List<int> istiadhaTokens; // "أعوذ بالله..." reference tokens
  final List<int> basmalaTokens; // "بسم الله الرحمن الرحيم" reference tokens
  final PronunciationHeadWeights headWeights;

  AsrAssets({
    required this.melFilters,
    required this.cmvn,
    required this.vocab,
    required this.refTokens,
    required this.istiadhaTokens,
    required this.basmalaTokens,
    required this.headWeights,
  });

  static AsrAssets? _cached;

  static Future<AsrAssets> load() async {
    if (_cached != null) return _cached!;
    final melRaw = jsonDecode(await rootBundle.loadString('assets/asr/mel_filters.json')) as List;
    final mel = melRaw.map((row) => (row as List).map((v) => (v as num).toDouble()).toList()).toList();

    final cmvnRaw = jsonDecode(await rootBundle.loadString('assets/asr/cmvn.json')) as Map<String, dynamic>;
    final cmvn = cmvnRaw.map((k, v) => MapEntry(k, (v as List).map((e) => (e as num).toDouble()).toList()));

    final vocabRaw = jsonDecode(await rootBundle.loadString('assets/asr/vocab.json')) as List;
    final vocab = vocabRaw.cast<String>();

    final refRaw = jsonDecode(await rootBundle.loadString('assets/asr/ref_tokens.json')) as Map<String, dynamic>;
    final refTokens = refRaw.map((k, v) => MapEntry(k, (v as List).map((e) => (e as num).toInt()).toList()));

    final preambleRaw = jsonDecode(await rootBundle.loadString('assets/asr/preamble.json')) as Map<String, dynamic>;
    final istiadhaTokens = (preambleRaw['istiadha'] as List).map((e) => (e as num).toInt()).toList();
    final basmalaTokens = (preambleRaw['basmala'] as List).map((e) => (e as num).toInt()).toList();

    final headWeights = await PronunciationHeadWeights.load();

    return _cached = AsrAssets(
      melFilters: mel,
      cmvn: cmvn,
      vocab: vocab,
      refTokens: refTokens,
      istiadhaTokens: istiadhaTokens,
      basmalaTokens: basmalaTokens,
      headWeights: headWeights,
    );
  }
}

/// Flat float32 weight arrays for the pronunciation head, sliced out of the
/// packed binary asset using the offsets recorded in the manifest.
class PronunciationHeadWeights {
  final Float32List tokEmb; // (1025, 64)
  final Float32List w0; final Float32List b0; // 592 -> 1024
  final Float32List w1; final Float32List b1; // 1024 -> 512
  final Float32List w2; final Float32List b2; // 512 -> 256
  final Float32List w3; final Float32List b3; // 256 -> 1
  final Float32List featureTable; // (1025, 16)

  PronunciationHeadWeights({
    required this.tokEmb,
    required this.w0, required this.b0,
    required this.w1, required this.b1,
    required this.w2, required this.b2,
    required this.w3, required this.b3,
    required this.featureTable,
  });

  static Future<PronunciationHeadWeights> load() async {
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/asr/pronunciation_head_manifest.json'),
    ) as Map<String, dynamic>;
    final bytes = await rootBundle.load('assets/asr/pronunciation_head.bin');

    Float32List slice(String name) {
      final m = manifest[name] as Map<String, dynamic>;
      final offset = m['offset'] as int;
      final count = m['count'] as int;
      return bytes.buffer.asFloat32List(bytes.offsetInBytes + offset, count);
    }

    return PronunciationHeadWeights(
      tokEmb: slice('tok_emb'),
      w0: slice('w0'), b0: slice('b0'),
      w1: slice('w1'), b1: slice('b1'),
      w2: slice('w2'), b2: slice('b2'),
      w3: slice('w3'), b3: slice('b3'),
      featureTable: slice('feature_table'),
    );
  }
}
