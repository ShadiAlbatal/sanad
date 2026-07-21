import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/search/bookmarks.dart';

/// The per-tab bookmark set (toggle/isBookmarked over a `List<String>` of JSON
/// entries). Unlike search_history's MRU list this is a SET keyed on 'key':
/// no cap, no reordering, add/remove by identity. Pins the identity matching
/// across the three tabs' entry shapes and the corrupt-entry tolerance.
void main() {
  String entry(String key, [Map<String, dynamic>? extra]) =>
      jsonEncode({'key': key, ...?extra});

  test('adds a not-yet-bookmarked entry to the front', () {
    final out = toggleBookmark(const [], {'key': 'surah:112', 'label': 'Al-Ikhlas'});
    expect(out.length, 1);
    expect(jsonDecode(out.first)['key'], 'surah:112');
  });

  test('toggling an already-bookmarked key removes exactly that entry', () {
    final start = [entry('surah:112'), entry('ayah:2:255'), entry('bukhari:1')];
    final out = toggleBookmark(start, {'key': 'ayah:2:255'});
    expect(out.map((s) => jsonDecode(s)['key']), ['surah:112', 'bukhari:1']);
  });

  test('page-sharing surahs are DISTINCT bookmarks (the collision regression)', () {
    // 112/113/114 all start on mushaf page 604 — identity keys must keep them
    // separate where a page key would have collapsed them into one.
    var bm = <String>[];
    bm = toggleBookmark(bm, {'key': 'surah:112', 'page': 604, 'label': 'Al-Ikhlas'});
    bm = toggleBookmark(bm, {'key': 'surah:114', 'page': 604, 'label': 'An-Nas'});
    expect(bm.length, 2);
    expect(isBookmarked(bm, 'surah:112'), isTrue);
    expect(isBookmarked(bm, 'surah:114'), isTrue);
    // Removing one leaves the other intact.
    bm = toggleBookmark(bm, {'key': 'surah:112', 'page': 604, 'label': 'Al-Ikhlas'});
    expect(isBookmarked(bm, 'surah:112'), isFalse);
    expect(isBookmarked(bm, 'surah:114'), isTrue);
  });

  test('isBookmarked matches by key across the three tabs\' entry shapes', () {
    final bm = [
      entry('surah:3', {'page': 50, 'label': 'Al-Imran'}),
      entry('dua-after-adhan', {'label': 'Dua after Adhan'}),
      entry('bukhari:6109', {'label': 'Bukhari #6109', 'number': 6109}),
    ];
    expect(isBookmarked(bm, 'surah:3'), isTrue);
    expect(isBookmarked(bm, 'dua-after-adhan'), isTrue);
    expect(isBookmarked(bm, 'bukhari:6109'), isTrue);
    expect(isBookmarked(bm, 'surah:4'), isFalse);
  });

  test('a corrupt (undecodable) entry never matches and is dropped on the next toggle', () {
    final bm = ['not json at all', entry('surah:1')];
    expect(isBookmarked(bm, 'surah:1'), isTrue);
    // Toggling off surah:1 removes it AND sheds the corrupt entry (no leak).
    final out = toggleBookmark(bm, {'key': 'surah:1'});
    expect(out, isEmpty);
  });

  test('re-adding a removed key puts it back at the front', () {
    var bm = [entry('a'), entry('b')];
    bm = toggleBookmark(bm, {'key': 'a'});
    expect(bm.map((s) => jsonDecode(s)['key']), ['b']);
    bm = toggleBookmark(bm, {'key': 'a', 'label': 'A'});
    expect(bm.map((s) => jsonDecode(s)['key']), ['a', 'b']);
  });
}
