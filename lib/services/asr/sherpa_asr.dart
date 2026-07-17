import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import '../../util/log.dart';

/// Streaming phoneme ASR (Muno459 zipformer2-ctc) via sherpa-onnx
/// OnlineRecognizer — the engine that worked "like a clock" in the RN build.
/// One persistent stream survives the whole recitation (breath pauses included);
/// each [accept] returns the CUMULATIVE phoneme tokens decoded so far.
class SherpaAsr {
  final so.OnlineRecognizer _recognizer;
  so.OnlineStream _stream;
  bool _disposed = false;

  SherpaAsr._(this._recognizer) : _stream = _recognizer.createStream();

  static const _modelAsset = 'assets/asr/phoneme/model.int8.onnx';
  static const _tokensAsset = 'assets/asr/phoneme/tokens.txt';
  // The zipformer needs ~0.8s of trailing audio to emit the last word's phonemes.
  static final _tailPad = Float32List((0.8 * 16000).round());

  static Future<SherpaAsr> create() async {
    so.initBindings();
    final dir = await getApplicationSupportDirectory();
    final base = '${dir.path}/phoneme';
    final model = await _stage(_modelAsset, '$base/model.int8.onnx');
    final tokens = await _stage(_tokensAsset, '$base/tokens.txt');
    final config = so.OnlineRecognizerConfig(
      feat: const so.FeatureConfig(sampleRate: 16000, featureDim: 80),
      model: so.OnlineModelConfig(
        zipformer2Ctc: so.OnlineZipformer2CtcModelConfig(model: model),
        tokens: tokens,
        numThreads: 2,
        debug: false,
        modelType: 'zipformer2_ctc',
      ),
      decodingMethod: 'greedy_search',
      enableEndpoint: false,
    );
    final rec = so.OnlineRecognizer(config);
    Log.d('sherpa', 'online phoneme recognizer ready (zipformer2_ctc)');
    return SherpaAsr._(rec);
  }

  /// Feed a PCM16 mono@16kHz chunk; returns the cumulative phoneme tokens.
  List<String> accept(Int16List pcm) {
    if (_disposed) return const [];
    final f = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      f[i] = pcm[i] / 32768.0;
    }
    _stream.acceptWaveform(samples: f, sampleRate: 16000);
    while (_recognizer.isReady(_stream)) {
      _recognizer.decode(_stream);
    }
    return _recognizer.getResult(_stream).tokens;
  }

  /// Per-token START time (seconds), index-aligned with the tokens from the last
  /// [accept]/[finish]. Read right after [finish], before the next [resetStream].
  List<double> get lastTimestamps =>
      _disposed ? const [] : _recognizer.getResult(_stream).timestamps;

  /// Flush the tail (pad with silence so the last word's phonemes emit).
  List<String> finish() {
    if (_disposed) return const [];
    _stream.acceptWaveform(samples: _tailPad, sampleRate: 16000);
    _stream.inputFinished();
    while (_recognizer.isReady(_stream)) {
      _recognizer.decode(_stream);
    }
    final tokens = _recognizer.getResult(_stream).tokens;
    Log.d('sherpa', 'finish flush (tail-pad) -> ${tokens.length} tokens');
    return tokens;
  }

  /// Start a fresh stream for a new recitation.
  void resetStream() {
    if (_disposed) return;
    _stream.free();
    _stream = _recognizer.createStream();
    Log.t('sherpa', 'stream reset (fresh recitation)');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stream.free();
    _recognizer.free();
  }

  static Future<String> _stage(String asset, String dest) async {
    final f = File(dest);
    final data = await rootBundle.load(asset);
    if (!f.existsSync() || f.lengthSync() != data.lengthInBytes) {
      await f.parent.create(recursive: true);
      await f.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      Log.d('sherpa', 'staged $asset -> $dest (${data.lengthInBytes}B)');
    }
    return dest;
  }
}
