import 'dart:convert';

/// Push a JSON-encodable [entry] onto a most-recently-used history list stored
/// as `List<String>` (SharedPreferences' native list type — no extra codec
/// needed at the storage layer). [entry] must carry a `'key'` field used to
/// de-dup: re-opening an already-recent item moves it to the front instead of
/// creating a second row. Malformed stored entries (a future format change,
/// corrupt prefs) are dropped rather than crashing the caller.
List<String> pushHistory(List<String> existing, Map<String, dynamic> entry, {int cap = 8}) {
  final key = entry['key'];
  final kept = existing.where((s) {
    try {
      return (jsonDecode(s) as Map)['key'] != key;
    } catch (_) {
      return false;
    }
  });
  final list = [jsonEncode(entry), ...kept];
  return list.length > cap ? list.sublist(0, cap) : list;
}

/// Decode a history list back to maps, silently dropping any entry that fails
/// to parse (same tolerance as [pushHistory]).
List<Map<String, dynamic>> decodeHistory(List<String> stored) => [
      for (final s in stored) ?_tryDecode(s),
    ];

Map<String, dynamic>? _tryDecode(String s) {
  try {
    return (jsonDecode(s) as Map).cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}
