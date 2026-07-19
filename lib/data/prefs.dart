import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  static const _kLastPage = 'last_page';
  static const _kLastDuaId = 'last_dua_id';
  static const _kLastHadithId = 'last_hadith_id';
  static const _kThemeMode = 'theme_mode'; // 'light' | 'dark' | 'system'
  static const _kAccent = 'accent'; // AccentChoice name
  static const _kShareEssential = 'share_essential';
  static const _kSharePerformance = 'share_performance';
  static const _kDuaHistory = 'dua_history';
  static const _kHadithHistory = 'hadith_history';
  static const _kQuranHistory = 'quran_history';

  final SharedPreferences _sp;
  Prefs(this._sp);

  static Future<Prefs> load() async => Prefs(await SharedPreferences.getInstance());

  int get lastPage => _sp.getInt(_kLastPage) ?? 1;
  Future<void> setLastPage(int p) => _sp.setInt(_kLastPage, p);

  String? get lastDuaId => _sp.getString(_kLastDuaId);
  Future<void> setLastDuaId(String id) => _sp.setString(_kLastDuaId, id);

  String? get lastHadithId => _sp.getString(_kLastHadithId);
  Future<void> setLastHadithId(String id) => _sp.setString(_kLastHadithId, id);

  String get themeMode => _sp.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String m) => _sp.setString(_kThemeMode, m);

  String get accent => _sp.getString(_kAccent) ?? 'auto';
  Future<void> setAccent(String a) => _sp.setString(_kAccent, a);

  bool get shareEssential => _sp.getBool(_kShareEssential) ?? false;
  Future<void> setShareEssential(bool v) => _sp.setBool(_kShareEssential, v);

  bool get sharePerformance => _sp.getBool(_kSharePerformance) ?? false;
  Future<void> setSharePerformance(bool v) => _sp.setBool(_kSharePerformance, v);

  // Recently-opened items per tab (quick-retrieve), each a JSON-encoded map —
  // see services/search/search_history.dart for the push/decode helpers.
  List<String> get duaHistory => _sp.getStringList(_kDuaHistory) ?? const [];
  Future<void> setDuaHistory(List<String> v) => _sp.setStringList(_kDuaHistory, v);

  List<String> get hadithHistory => _sp.getStringList(_kHadithHistory) ?? const [];
  Future<void> setHadithHistory(List<String> v) => _sp.setStringList(_kHadithHistory, v);

  List<String> get quranHistory => _sp.getStringList(_kQuranHistory) ?? const [];
  Future<void> setQuranHistory(List<String> v) => _sp.setStringList(_kQuranHistory, v);
}
