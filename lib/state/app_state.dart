import 'package:flutter/material.dart';
import '../data/prefs.dart';
import '../services/analytics.dart';
import '../theme/app_theme.dart';
import '../util/day_part.dart';

abstract class Tabs {
  static const dua = 0;
  static const home = 1;
  static const quran = 2;
  static const hadith = 3;
}

enum AccentChoice { auto, iris, emerald, coral, ocean }

class AppState extends ChangeNotifier {
  final Prefs prefs;
  AppState(this.prefs)
      : _lastPage = prefs.lastPage,
        _lastDuaId = prefs.lastDuaId,
        _lastHadithId = prefs.lastHadithId {
    _themeMode = _parse(prefs.themeMode);
    _accentChoice = _parseAccent(prefs.accent);
    _shareEssential = prefs.shareEssential;
    _sharePerformance = prefs.sharePerformance;
    Analytics.instance.essentialConsent = _shareEssential;
    Analytics.instance.usageConsent = _sharePerformance;
  }

  int _lastPage;
  int get lastPage => _lastPage;
  void setLastPage(int page) {
    if (page == _lastPage) return;
    _lastPage = page;
    prefs.setLastPage(page);
    // No notify: Home re-reads lastPage when it rebuilds on tab switch, and
    // notifying here would rebuild the whole scaffold on every page turn.
  }

  String? _lastDuaId;
  String? get lastDuaId => _lastDuaId;
  void setLastDuaId(String id) {
    if (id == _lastDuaId) return;
    _lastDuaId = id;
    prefs.setLastDuaId(id); // no notify — same rationale as setLastPage
  }

  String? _lastHadithId;
  String? get lastHadithId => _lastHadithId;
  void setLastHadithId(String id) {
    if (id == _lastHadithId) return;
    _lastHadithId = id;
    prefs.setLastHadithId(id); // no notify — same rationale as setLastPage
  }

  late ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;
  void setThemeMode(ThemeMode m) {
    _themeMode = m;
    prefs.setThemeMode(m.name);
    notifyListeners();
  }

  void cycleTheme() {
    setThemeMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  late AccentChoice _accentChoice;
  AccentChoice get accentChoice => _accentChoice;
  void setAccentChoice(AccentChoice c) {
    _accentChoice = c;
    prefs.setAccent(c.name);
    notifyListeners();
  }

  Color get accentColor => switch (_accentChoice) {
        AccentChoice.iris => AppColors.accentIris,
        AccentChoice.emerald => AppColors.accentEmerald,
        AccentChoice.coral => AppColors.accentCoral,
        AccentChoice.ocean => AppColors.accentOcean,
        AccentChoice.auto => _autoAccent(),
      };

  // Auto follows the arc of the day: dawn opens in iris, brightens to emerald
  // through the morning, cools to ocean in the afternoon, warms to coral at
  // dusk, then settles back to deep ocean-blue for the night. Re-resolves
  // whenever the theme rebuilds (launch, tab change, settings) — no timer.
  static Color _autoAccent() => switch (dayPartOf(DateTime.now())) {
        DayPart.fajr => AppColors.accentIris,
        DayPart.morning => AppColors.accentEmerald,
        DayPart.afternoon => AppColors.accentOcean,
        DayPart.evening => AppColors.accentCoral,
        DayPart.night => AppColors.accentOcean,
      };

  late bool _shareEssential;
  bool get shareEssential => _shareEssential;
  void setShareEssential(bool v) {
    _shareEssential = v;
    prefs.setShareEssential(v);
    Analytics.instance.essentialConsent = v;
    notifyListeners();
  }

  late bool _sharePerformance;
  bool get sharePerformance => _sharePerformance;
  void setSharePerformance(bool v) {
    _sharePerformance = v;
    prefs.setSharePerformance(v);
    Analytics.instance.usageConsent = v;
    notifyListeners();
  }

  // Cross-tab reader navigation. jumpTarget ticks on every request so the
  // reader can listen and jump even when asked to go to the same page twice.
  int _pendingJump = 1;
  int get pendingJump => _pendingJump;
  final ValueNotifier<int> jumpTarget = ValueNotifier(0);

  int _tabIndex = Tabs.home;
  int get tabIndex => _tabIndex;
  set tabIndex(int i) {
    _tabIndex = i;
    notifyListeners();
  }

  void openReaderAt(int page) {
    _pendingJump = page;
    _tabIndex = Tabs.quran;
    jumpTarget.value++;
    notifyListeners();
  }

  @override
  void dispose() {
    jumpTarget.dispose();
    super.dispose();
  }

  static ThemeMode _parse(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static AccentChoice _parseAccent(String s) => AccentChoice.values
      .firstWhere((c) => c.name == s, orElse: () => AccentChoice.auto);
}
