import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import '../../util/log.dart';

/// SPIKE ONLY — offline word-level ASR (Muno459 FastConformer-Quran, NeMo CTC)
/// via sherpa-onnx's OfflineRecognizer. Not wired into search yet; exists to
/// measure on-device load time, memory, and real-voice transcript quality
/// before committing to bundling this second (~125 MB) model. Transcribes a
/// whole utterance at once (offline), which is exactly the transcribe-on-pause
/// shape search would use — the streaming phoneme model stays the follow-along
/// engine.
class WordAsr {
  so.OfflineRecognizer? _recognizer;

  static const _modelAsset = 'assets/asr/word/fastconformer.int8.onnx';
  static const _tokensAsset = 'assets/asr/word/tokens.txt';

  bool get loaded => _recognizer != null;

  Future<void> ensureLoaded() async {
    if (_recognizer != null) return;
    final sw = Stopwatch()..start();
    so.initBindings();
    final dir = await getApplicationSupportDirectory();
    final base = '${dir.path}/word';
    final model = await _stage(_modelAsset, '$base/fastconformer.int8.onnx');
    final tokens = await _stage(_tokensAsset, '$base/tokens.txt');
    final tStage = sw.elapsedMilliseconds;
    final config = so.OfflineRecognizerConfig(
      feat: const so.FeatureConfig(sampleRate: 16000, featureDim: 80),
      model: so.OfflineModelConfig(
        nemoCtc: so.OfflineNemoEncDecCtcModelConfig(model: model),
        tokens: tokens,
        numThreads: 2,
        debug: false,
      ),
      decodingMethod: 'greedy_search',
    );
    _recognizer = so.OfflineRecognizer(config);
    Log.d('wordasr', 'loaded FastConformer: stage=${tStage}ms '
        'create=${sw.elapsedMilliseconds - tStage}ms total=${sw.elapsedMilliseconds}ms');
  }

  /// Transcribe a whole PCM16 mono@16k clip to text. Returns the transcript and
  /// logs inference time. Caller must have loaded the model.
  String transcribe(Int16List pcm) {
    final rec = _recognizer;
    if (rec == null) return '';
    final sw = Stopwatch()..start();
    final f = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      f[i] = pcm[i] / 32768.0;
    }
    final stream = rec.createStream();
    stream.acceptWaveform(samples: f, sampleRate: 16000);
    rec.decode(stream);
    final text = rec.getResult(stream).text;
    stream.free();
    final secs = (pcm.length / 16000).toStringAsFixed(1);
    Log.d('wordasr', 'transcribe ${secs}s clip in ${sw.elapsedMilliseconds}ms -> "$text"');
    return text;
  }

  void dispose() {
    _recognizer?.free();
    _recognizer = null;
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
      Log.d('wordasr', 'staged $asset -> $dest (${data.lengthInBytes}B)');
    }
    return dest;
  }
}
