import 'dart:typed_data';

/// Wrap 16-bit mono PCM [samples] in a 44-byte canonical WAV header (little-
/// endian) so the Mistakes sheet's AudioPlayer can play a raw session slice. The
/// engine runs at 16kHz, so that is the only sample rate the app ever needs.
Uint8List encodeWav(Int16List samples, {int sampleRate = 16000}) {
  const channels = 1;
  const bitsPerSample = 16;
  const blockAlign = channels * bitsPerSample ~/ 8;
  final byteRate = sampleRate * blockAlign;
  final dataBytes = samples.length * 2;
  final bytes = Uint8List(44 + dataBytes);
  final view = ByteData.view(bytes.buffer);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes[offset + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // fmt chunk size (PCM)
  view.setUint16(20, 1, Endian.little); // audio format = PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes;
}
