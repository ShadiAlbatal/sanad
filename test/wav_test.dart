import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/services/asr/wav.dart';

/// The Mistakes sheet plays a raw session PCM slice via BytesSource(mimeType:
/// 'audio/wav'), so the 44-byte header must be exactly right and the payload
/// must round-trip. Pins the canonical header offsets.
void main() {
  String ascii(Uint8List b, int off, int len) =>
      String.fromCharCodes(b.sublist(off, off + len));

  test('header magic, format, and data length', () {
    final samples = Int16List.fromList([0, 1, -1, 32767, -32768, 12345]);
    final wav = encodeWav(samples);
    final view = ByteData.view(wav.buffer);

    expect(wav.length, 44 + samples.length * 2);
    expect(ascii(wav, 0, 4), 'RIFF');
    expect(view.getUint32(4, Endian.little), 36 + samples.length * 2);
    expect(ascii(wav, 8, 4), 'WAVE');
    expect(ascii(wav, 12, 4), 'fmt ');
    expect(view.getUint32(16, Endian.little), 16); // PCM fmt chunk size
    expect(view.getUint16(20, Endian.little), 1); // audio format = PCM
    expect(view.getUint16(22, Endian.little), 1); // channels = mono
    expect(view.getUint32(24, Endian.little), 16000); // sample rate
    expect(view.getUint32(28, Endian.little), 16000 * 2); // byte rate
    expect(view.getUint16(32, Endian.little), 2); // block align
    expect(view.getUint16(34, Endian.little), 16); // bits per sample
    expect(ascii(wav, 36, 4), 'data');
    expect(view.getUint32(40, Endian.little), samples.length * 2);
  });

  test('PCM payload round-trips little-endian', () {
    final samples = Int16List.fromList([0, 1, -1, 32767, -32768, 12345, -9999]);
    final wav = encodeWav(samples);
    final view = ByteData.view(wav.buffer);
    final out = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = view.getInt16(44 + i * 2, Endian.little);
    }
    expect(out, samples);
  });
}
