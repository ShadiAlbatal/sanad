import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/data/quotes.dart';
import 'package:sanad/util/day_part.dart';

void main() {
  group('dayPartOf', () {
    DateTime at(int hour) => DateTime(2026, 7, 15, hour);

    test('buckets boundary hours', () {
      expect(dayPartOf(at(5)), DayPart.fajr);
      expect(dayPartOf(at(8)), DayPart.morning);
      expect(dayPartOf(at(13)), DayPart.afternoon);
      expect(dayPartOf(at(18)), DayPart.evening);
      expect(dayPartOf(at(22)), DayPart.night);
      expect(dayPartOf(at(2)), DayPart.night);
    });

    test('exact range edges', () {
      expect(dayPartOf(at(4)), DayPart.fajr);
      expect(dayPartOf(at(7)), DayPart.morning);
      expect(dayPartOf(at(12)), DayPart.afternoon);
      expect(dayPartOf(at(16)), DayPart.evening);
      expect(dayPartOf(at(20)), DayPart.night);
      expect(dayPartOf(at(0)), DayPart.night);
    });
  });

  group('dailyQuote', () {
    test('is deterministic for a given date, ignoring time of day', () {
      final morning = DateTime(2026, 7, 15, 6);
      final evening = DateTime(2026, 7, 15, 23);
      expect(dailyQuote(morning), same(dailyQuote(evening)));
    });

    test('rotates across consecutive days', () {
      final a = dailyQuote(DateTime(2026, 7, 15));
      final b = dailyQuote(DateTime(2026, 7, 16));
      expect(identical(a, b), isFalse);
    });

    test('always returns an in-range quote across a full year', () {
      final start = DateTime(2026, 1, 1);
      for (var i = 0; i < 366; i++) {
        final q = dailyQuote(start.add(Duration(days: i)));
        expect(quotes.contains(q), isTrue);
      }
    });
  });
}
