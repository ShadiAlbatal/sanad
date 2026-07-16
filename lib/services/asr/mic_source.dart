import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import '../../util/log.dart';

/// Wraps `record`'s raw PCM stream (16kHz mono, 16-bit) for feeding straight
/// into the ASR engine via the `onPcm` callback passed to [start].
class MicSource {
  AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final List<int> _byteTail = []; // odd trailing byte between chunks

  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
  );

  Future<bool> hasPermission() async {
    final ok = await _recorder.hasPermission();
    Log.d('mic', 'hasPermission=$ok');
    return ok;
  }

  int _pcmChunks = 0;
  int _pcmSamples = 0;

  Future<void> start(void Function(Int16List pcm) onPcm) async {
    // Drop any leftover subscription, then open the stream. A recorder still
    // bound to a previous stream (a session that didn't stop cleanly, or a hot
    // restart) makes startStream throw "StreamSink is bound to a stream" —
    // pre-empt it by stopping first, and if it still throws, dispose+recreate
    // the recorder and retry once.
    await _sub?.cancel();
    _sub = null;
    Stream<Uint8List> stream;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
      stream = await _recorder.startStream(_config);
    } catch (e, st) {
      Log.e('mic', 'startStream failed ($e) — recreating recorder', st);
      try {
        await _recorder.dispose();
      } catch (_) {}
      _recorder = AudioRecorder();
      stream = await _recorder.startStream(_config);
    }
    _byteTail.clear();
    _pcmChunks = 0;
    _pcmSamples = 0;
    Log.d('mic', 'stream started (pcm16/16k/mono)');
    _sub = stream.listen((bytes) {
      final all = _byteTail.isEmpty ? bytes : Uint8List.fromList([..._byteTail, ...bytes]);
      final sampleCount = all.length ~/ 2;
      final pcm = Int16List(sampleCount);
      final byteData = ByteData.sublistView(all, 0, sampleCount * 2);
      for (var i = 0; i < sampleCount; i++) {
        pcm[i] = byteData.getInt16(i * 2, Endian.little);
      }
      _byteTail
        ..clear()
        ..addAll(all.sublist(sampleCount * 2));
      _pcmChunks++;
      _pcmSamples += sampleCount;
      Log.t('mic', 'chunk#$_pcmChunks bytes=${bytes.length} samples=$sampleCount '
          'tail=${_byteTail.length} totalSamples=$_pcmSamples (${(_pcmSamples / 16000).toStringAsFixed(2)}s)');
      if (pcm.isNotEmpty) onPcm(pcm);
    }, onError: (e, st) => Log.e('mic', e, st));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _recorder.stop();
    Log.d('mic', 'stream stopped ($_pcmChunks chunks, $_pcmSamples samples)');
  }

  void dispose() {
    _sub?.cancel();
    _recorder.dispose();
  }
}
