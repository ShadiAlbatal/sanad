import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import '../../util/log.dart';

/// A decoded PCM16 mono clip, ready to feed into [AsrEngine.pushAudio] exactly
/// like the mic. Used by the on-device ASR diagnostic (feed a known recording
/// through the real engine and watch the byte/token/tracker trace in the log).
class PcmClip {
  final Int16List pcm;
  final int sampleRate;
  const PcmClip(this.pcm, this.sampleRate);
  double get seconds => sampleRate == 0 ? 0 : pcm.length / sampleRate;
}

/// Load a bundled WAV asset as PCM16 samples. The debug assets are already
/// 16kHz mono 16-bit (converted with ffmpeg), so no resample/downmix is done —
/// only a RIFF chunk walk to find `fmt `/`data`. Throws on a non-16-bit clip.
Future<PcmClip> loadWavAsset(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final bd = ByteData.sublistView(bytes);

  if (bytes.length < 12 ||
      String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
      String.fromCharCodes(bytes, 8, 12) != 'WAVE') {
    throw FormatException('not a WAV asset: $assetPath');
  }

  var sampleRate = 16000, bits = 16, channels = 1;
  var dataOff = -1, dataLen = 0;
  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, pos, pos + 4);
    final sz = bd.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      channels = bd.getUint16(body + 2, Endian.little);
      sampleRate = bd.getUint32(body + 4, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOff = body;
      dataLen = sz.clamp(0, bytes.length - body);
      break;
    }
    pos = body + sz + (sz & 1); // chunks are word-aligned
  }
  if (dataOff < 0 || bits != 16) {
    throw FormatException('unsupported WAV (bits=$bits data@$dataOff) $assetPath');
  }

  final total = dataLen ~/ 2;
  // Downmix to mono if needed so the diagnostic tolerates a stereo clip.
  final frames = channels > 1 ? total ~/ channels : total;
  final pcm = Int16List(frames);
  if (channels <= 1) {
    for (var i = 0; i < frames; i++) {
      pcm[i] = bd.getInt16(dataOff + i * 2, Endian.little);
    }
  } else {
    for (var f = 0; f < frames; f++) {
      var acc = 0;
      for (var c = 0; c < channels; c++) {
        acc += bd.getInt16(dataOff + (f * channels + c) * 2, Endian.little);
      }
      pcm[f] = (acc ~/ channels);
    }
  }
  Log.d('diag',
      'loaded $assetPath: ${pcm.length} samples @${sampleRate}Hz ${channels}ch/${bits}bit (${(pcm.length / sampleRate).toStringAsFixed(1)}s)');
  return PcmClip(pcm, sampleRate);
}
