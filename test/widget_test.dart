import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/models/mushaf.dart';

void main() {
  test('MushafWord parses location into surah:ayah:index', () {
    final w = MushafWord(location: '2:255:3', glyph: 'x', uthmani: 'y', tajweed: 'y');
    expect(w.surah, 2);
    expect(w.ayah, 255);
    expect(w.index, 3);
  });
}
