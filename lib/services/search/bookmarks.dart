import 'dart:convert';

/// Toggle a JSON-encodable [entry] in a bookmark set stored as `List<String>`
/// (same storage shape as search_history.dart's MRU list, but a SET — no MRU
/// reordering, no cap: bookmarking is a deliberate, unbounded choice, not a
/// quick-retrieve cache). [entry] must carry a `'key'` field. Already-bookmarked
/// -> removes it; not yet bookmarked -> adds it to the front.
List<String> toggleBookmark(List<String> existing, Map<String, dynamic> entry) {
  final key = entry['key'];
  if (isBookmarked(existing, key)) {
    // Drop the matched key AND any undecodable entry (same as pushHistory's
    // keep-filter) so a corrupt entry can't linger unremovable in the list.
    return existing.where((s) {
      try {
        return (jsonDecode(s) as Map)['key'] != key;
      } catch (_) {
        return false;
      }
    }).toList();
  }
  return [jsonEncode(entry), ...existing];
}

bool isBookmarked(List<String> existing, Object? key) => existing.any((s) {
      try {
        return (jsonDecode(s) as Map)['key'] == key;
      } catch (_) {
        return false;
      }
    });
