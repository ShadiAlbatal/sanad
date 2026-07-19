import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/search/search_history.dart';

void main() {
  test('pushes new entries to the front', () {
    var list = pushHistory(const [], {'key': 'a', 'label': 'A'});
    list = pushHistory(list, {'key': 'b', 'label': 'B'});
    final decoded = decodeHistory(list);
    expect(decoded.map((e) => e['key']), ['b', 'a']);
  });

  test('re-opening an existing entry moves it to the front instead of duplicating', () {
    var list = pushHistory(const [], {'key': 'a', 'label': 'A'});
    list = pushHistory(list, {'key': 'b', 'label': 'B'});
    list = pushHistory(list, {'key': 'a', 'label': 'A'});
    final decoded = decodeHistory(list);
    expect(decoded.length, 2);
    expect(decoded.map((e) => e['key']), ['a', 'b']);
  });

  test('caps at the given size, dropping the oldest', () {
    var list = const <String>[];
    for (var i = 0; i < 10; i++) {
      list = pushHistory(list, {'key': 'item$i'}, cap: 8);
    }
    expect(list.length, 8);
    final decoded = decodeHistory(list);
    expect(decoded.first['key'], 'item9'); // most recent first
    expect(decoded.last['key'], 'item2'); // item0/item1 fell off
  });

  test('decodeHistory drops malformed entries instead of throwing', () {
    final decoded = decodeHistory(['not json', '{"key":"ok"}', '']);
    expect(decoded.length, 1);
    expect(decoded.first['key'], 'ok');
  });
}
