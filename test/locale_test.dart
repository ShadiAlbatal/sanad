import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/data/prefs.dart';
import 'package:sanad/l10n/app_localizations.dart';
import 'package:sanad/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app is Arabic-first: every collection it carries is Arabic and the user
/// recites in Arabic, so the UI defaults to Arabic regardless of the device
/// locale, with English available in Settings. Picking a locale also picks a
/// text direction, which is the part that can silently regress.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Prefs> freshPrefs([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    return Prefs(await SharedPreferences.getInstance());
  }

  test('defaults to Arabic on a device that has never set a language', () async {
    final app = AppState(await freshPrefs());
    expect(app.locale.languageCode, 'ar');
  });

  test('a stored choice wins over the default', () async {
    final app = AppState(await freshPrefs({'language': 'en'}));
    expect(app.locale.languageCode, 'en');
  });

  test('switching language persists it', () async {
    final prefs = await freshPrefs();
    final app = AppState(prefs);
    app.setLocale(const Locale('en'));
    expect(prefs.languageCode, 'en');
    expect(app.locale.languageCode, 'en');
  });

  testWidgets('Arabic renders RTL and English LTR', (tester) async {
    for (final (code, want) in [
      ('ar', TextDirection.rtl),
      ('en', TextDirection.ltr),
    ]) {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(code),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context)!.settings),
        ),
      ));
      await tester.pump();
      expect(Directionality.of(tester.element(find.byType(Text))), want,
          reason: '$code must lay out $want');
    }
  });

  testWidgets('both languages resolve every key used on the settings screen',
      (tester) async {
    for (final code in ['ar', 'en']) {
      late AppLocalizations t;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(code),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          t = AppLocalizations.of(context)!;
          return const SizedBox();
        }),
      ));
      await tester.pump();
      for (final s in [
        t.settings, t.appearance, t.accent, t.language, t.helpImprove,
        t.about, t.tabHome, t.tabQuran, t.tabDuas, t.tabHadith, t.tabCounter,
        t.appTagline, t.privacyCaption, t.crashReportsBody,
      ]) {
        expect(s, isNotEmpty, reason: 'empty string in "$code"');
      }
      // The language labels stay in their own script in BOTH locales, so a user
      // stranded in a language they can't read can still find their way back.
      expect(t.languageArabic, 'العربية');
      expect(t.languageEnglish, 'English');
    }
  });
}
