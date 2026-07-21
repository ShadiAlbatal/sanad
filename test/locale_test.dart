import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/data/prefs.dart';
import 'package:sanad/l10n/app_localizations.dart';
import 'package:sanad/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

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

  test('the two ARB files carry exactly the same keys', () {
    Map<String, dynamic> arb(String p) =>
        jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
    Set<String> keys(Map<String, dynamic> m) =>
        m.keys.where((k) => !k.startsWith('@')).toSet();

    final en = keys(arb('lib/l10n/app_en.arb'));
    final ar = keys(arb('lib/l10n/app_ar.arb'));
    // gen_l10n silently falls back to the template for a missing key, so an
    // untranslated string ships as English with no warning anywhere.
    expect(ar.difference(en), isEmpty, reason: 'keys in ar with no en template');
    expect(en.difference(ar), isEmpty, reason: 'UNTRANSLATED: keys missing from ar');
  });

  test('no Arabic value was left as its English source', () {
    final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final ar = jsonDecode(File('lib/l10n/app_ar.arb').readAsStringSync())
        as Map<String, dynamic>;
    // Deliberately identical in both: proper nouns and the self-labelled
    // language names, which stay in their own script by design.
    const sameByDesign = {'languageArabic', 'languageEnglish', 'hadithRef'};
    final copied = <String>[];
    for (final k in en.keys) {
      if (k.startsWith('@') || sameByDesign.contains(k)) continue;
      if (ar[k] == en[k]) copied.add(k);
    }
    expect(copied, isEmpty, reason: 'Arabic still holds the English text');
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
