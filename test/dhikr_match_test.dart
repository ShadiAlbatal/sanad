import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/dhikr/dhikr_match.dart';

void main() {
  test('normalizes tashkil and alif/hamza variants', () {
    expect(normalizeArabic('سُبْحَانَ اللَّهِ'), 'سبحان الله');
    expect(normalizeArabic('أَسْتَغْفِرُ اللّٰهَ').contains('استغفر'), isTrue);
  });

  test('counts a single phrase', () {
    expect(countDhikr('سبحان الله'), {'subhanallah': 1});
  });

  test('counts repeats of one phrase in a segment', () {
    expect(countDhikr('سبحان الله سبحان الله سبحان الله'), {'subhanallah': 3});
  });

  test('counts mixed phrases, non-overlapping', () {
    final c = countDhikr('سبحان الله والحمد لله والله أكبر');
    expect(c['subhanallah'], 1);
    expect(c['alhamdulillah'], 1);
    expect(c['allahuakbar'], 1);
  });

  test('tahlil (4 words) wins over the الله inside it — not double-counted', () {
    // "لا إله إلا الله" must count tahlil once and NOT also credit a الله-phrase.
    final c = countDhikr('لا إله إلا الله');
    expect(c, {'tahlil': 1});
  });

  test('works on diacritized input straight from the data', () {
    expect(countDhikr('الْحَمْدُ لِلَّهِ')['alhamdulillah'], 1);
    expect(countDhikr('اللَّهُ أَكْبَرُ')['allahuakbar'], 1);
    expect(countDhikr('أَسْتَغْفِرُ اللَّهَ')['istighfar'], 1);
  });

  test('ignores non-dhikr speech', () {
    expect(countDhikr('مرحبا كيف حالك اليوم'), <String, int>{});
    expect(countDhikr(''), <String, int>{});
  });
}
