import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Sanad'**
  String get appName;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabQuran.
  ///
  /// In en, this message translates to:
  /// **'Quran'**
  String get tabQuran;

  /// No description provided for @tabDuas.
  ///
  /// In en, this message translates to:
  /// **'Duas'**
  String get tabDuas;

  /// No description provided for @tabHadith.
  ///
  /// In en, this message translates to:
  /// **'Hadith'**
  String get tabHadith;

  /// No description provided for @tabCounter.
  ///
  /// In en, this message translates to:
  /// **'Counter'**
  String get tabCounter;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @dataPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Data & Privacy'**
  String get dataPrivacy;

  /// No description provided for @surahs.
  ///
  /// In en, this message translates to:
  /// **'Surahs'**
  String get surahs;

  /// No description provided for @surahIndex.
  ///
  /// In en, this message translates to:
  /// **'Surah index'**
  String get surahIndex;

  /// No description provided for @duasAndAdhkar.
  ///
  /// In en, this message translates to:
  /// **'Duas & Adhkār'**
  String get duasAndAdhkar;

  /// No description provided for @adhkar.
  ///
  /// In en, this message translates to:
  /// **'Adhkar'**
  String get adhkar;

  /// No description provided for @searchQuran.
  ///
  /// In en, this message translates to:
  /// **'Search the Quran'**
  String get searchQuran;

  /// No description provided for @searchHadith.
  ///
  /// In en, this message translates to:
  /// **'Search hadith'**
  String get searchHadith;

  /// No description provided for @searchDuas.
  ///
  /// In en, this message translates to:
  /// **'Search duas'**
  String get searchDuas;

  /// No description provided for @reciteToFindVerse.
  ///
  /// In en, this message translates to:
  /// **'Recite to find a verse'**
  String get reciteToFindVerse;

  /// No description provided for @reciteToFindHadith.
  ///
  /// In en, this message translates to:
  /// **'Recite to find a hadith'**
  String get reciteToFindHadith;

  /// No description provided for @reciteToFindDua.
  ///
  /// In en, this message translates to:
  /// **'Recite to find a dua'**
  String get reciteToFindDua;

  /// No description provided for @noMatchesBrowseAll.
  ///
  /// In en, this message translates to:
  /// **'No matches — clear the search to browse all'**
  String get noMatchesBrowseAll;

  /// No description provided for @noMatchesBrowseSurahs.
  ///
  /// In en, this message translates to:
  /// **'No matches — clear the search to browse surahs'**
  String get noMatchesBrowseSurahs;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @historyAndBookmarks.
  ///
  /// In en, this message translates to:
  /// **'History & bookmarks'**
  String get historyAndBookmarks;

  /// No description provided for @bookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmark;

  /// No description provided for @removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get removeBookmark;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @nothingOpenedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing opened yet'**
  String get nothingOpenedYet;

  /// No description provided for @nothingBookmarkedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing bookmarked yet'**
  String get nothingBookmarkedYet;

  /// No description provided for @resultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 results} =1{1 result} other{{count} results}}'**
  String resultCount(int count);

  /// No description provided for @mistakes.
  ///
  /// In en, this message translates to:
  /// **'Mistakes'**
  String get mistakes;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get reveal;

  /// No description provided for @revealNextWord.
  ///
  /// In en, this message translates to:
  /// **'Reveal next word'**
  String get revealNextWord;

  /// No description provided for @revealNextAyah.
  ///
  /// In en, this message translates to:
  /// **'Reveal next ayah'**
  String get revealNextAyah;

  /// No description provided for @revealNextSegment.
  ///
  /// In en, this message translates to:
  /// **'Reveal next segment'**
  String get revealNextSegment;

  /// No description provided for @hidePreviousWord.
  ///
  /// In en, this message translates to:
  /// **'Hide previous word'**
  String get hidePreviousWord;

  /// No description provided for @hidePreviousAyah.
  ///
  /// In en, this message translates to:
  /// **'Hide previous ayah'**
  String get hidePreviousAyah;

  /// No description provided for @hidePreviousSegment.
  ///
  /// In en, this message translates to:
  /// **'Hide previous segment'**
  String get hidePreviousSegment;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @toggleTheme.
  ///
  /// In en, this message translates to:
  /// **'Toggle theme'**
  String get toggleTheme;

  /// No description provided for @pageNumber.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String pageNumber(int page);

  /// No description provided for @pageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'This page could not be loaded.'**
  String get pageLoadFailed;

  /// No description provided for @versesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} verses'**
  String versesCount(int count);

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @resetAllCounts.
  ///
  /// In en, this message translates to:
  /// **'Reset all counts?'**
  String get resetAllCounts;

  /// No description provided for @resetAllCountsBody.
  ///
  /// In en, this message translates to:
  /// **'This clears every tasbīḥ tally back to zero.'**
  String get resetAllCountsBody;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @countByVoice.
  ///
  /// In en, this message translates to:
  /// **'Count by voice'**
  String get countByVoice;

  /// No description provided for @listeningReciteFreely.
  ///
  /// In en, this message translates to:
  /// **'Listening — recite freely'**
  String get listeningReciteFreely;

  /// No description provided for @counterHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a card or the mic and recite — it counts as you go.'**
  String get counterHint;

  /// No description provided for @repeatTimes.
  ///
  /// In en, this message translates to:
  /// **'Repeat ×{count}'**
  String repeatTimes(int count);

  /// No description provided for @continueReading.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get continueReading;

  /// No description provided for @openTheAdhkar.
  ///
  /// In en, this message translates to:
  /// **'Open the adhkar'**
  String get openTheAdhkar;

  /// No description provided for @lastPageRead.
  ///
  /// In en, this message translates to:
  /// **'Last page read'**
  String get lastPageRead;

  /// No description provided for @morningAdhkar.
  ///
  /// In en, this message translates to:
  /// **'Morning adhkār'**
  String get morningAdhkar;

  /// No description provided for @eveningAdhkar.
  ///
  /// In en, this message translates to:
  /// **'Evening adhkār'**
  String get eveningAdhkar;

  /// No description provided for @nightIstighfar.
  ///
  /// In en, this message translates to:
  /// **'Night — istighfār'**
  String get nightIstighfar;

  /// No description provided for @rememberAllah.
  ///
  /// In en, this message translates to:
  /// **'Remember Allah'**
  String get rememberAllah;

  /// No description provided for @greeting.
  ///
  /// In en, this message translates to:
  /// **'Assalamu ʿalaykum'**
  String get greeting;

  /// No description provided for @guestSignInSoon.
  ///
  /// In en, this message translates to:
  /// **'Guest · sign-in coming soon'**
  String get guestSignInSoon;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @accent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get accent;

  /// No description provided for @accentAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get accentAuto;

  /// No description provided for @accentIris.
  ///
  /// In en, this message translates to:
  /// **'Iris'**
  String get accentIris;

  /// No description provided for @accentEmerald.
  ///
  /// In en, this message translates to:
  /// **'Emerald'**
  String get accentEmerald;

  /// No description provided for @accentCoral.
  ///
  /// In en, this message translates to:
  /// **'Coral'**
  String get accentCoral;

  /// No description provided for @accentOcean.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get accentOcean;

  /// No description provided for @accentAutoCaption.
  ///
  /// In en, this message translates to:
  /// **'Auto shifts the colour with the time of day.'**
  String get accentAutoCaption;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @helpImprove.
  ///
  /// In en, this message translates to:
  /// **'Help improve Sanad'**
  String get helpImprove;

  /// No description provided for @crashReports.
  ///
  /// In en, this message translates to:
  /// **'Crash & error reports'**
  String get crashReports;

  /// No description provided for @crashReportsBody.
  ///
  /// In en, this message translates to:
  /// **'Optional. Anonymous crash/error summaries to help fix bugs. The app works fully without this.'**
  String get crashReportsBody;

  /// No description provided for @performanceUsage.
  ///
  /// In en, this message translates to:
  /// **'Performance & usage'**
  String get performanceUsage;

  /// No description provided for @performanceUsageBody.
  ///
  /// In en, this message translates to:
  /// **'Anonymous performance and usage to improve the app.'**
  String get performanceUsageBody;

  /// No description provided for @privacyCaption.
  ///
  /// In en, this message translates to:
  /// **'Anonymous, and kept on-device for now — nothing is uploaded anywhere yet. You can use the app fully without an account or sharing. See Data & Privacy.'**
  String get privacyCaption;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'A calm Quran companion — read, listen, and remember.'**
  String get appTagline;

  /// No description provided for @licenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses & Attribution'**
  String get licenses;

  /// No description provided for @neverShared.
  ///
  /// In en, this message translates to:
  /// **'Never shared'**
  String get neverShared;

  /// No description provided for @sharedOptIn.
  ///
  /// In en, this message translates to:
  /// **'Shared — only if you opt in'**
  String get sharedOptIn;

  /// No description provided for @offTextVerse.
  ///
  /// In en, this message translates to:
  /// **'Off-text — recitation did not match the verse here'**
  String get offTextVerse;

  /// No description provided for @offTextDua.
  ///
  /// In en, this message translates to:
  /// **'Off-text — recitation did not match here'**
  String get offTextDua;

  /// No description provided for @skippedWord.
  ///
  /// In en, this message translates to:
  /// **'Skipped — jumped over this word'**
  String get skippedWord;

  /// No description provided for @makhrajExpected.
  ///
  /// In en, this message translates to:
  /// **'makhraj: expected '**
  String get makhrajExpected;

  /// No description provided for @heardArrow.
  ///
  /// In en, this message translates to:
  /// **'  →  heard '**
  String get heardArrow;

  /// No description provided for @heardLabel.
  ///
  /// In en, this message translates to:
  /// **'heard: {text}'**
  String heardLabel(String text);

  /// No description provided for @pronunciation.
  ///
  /// In en, this message translates to:
  /// **'pronunciation'**
  String get pronunciation;

  /// No description provided for @greetingDawn.
  ///
  /// In en, this message translates to:
  /// **'A blessed dawn'**
  String get greetingDawn;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'A blessed evening'**
  String get greetingEvening;

  /// No description provided for @greetingNight.
  ///
  /// In en, this message translates to:
  /// **'A peaceful night'**
  String get greetingNight;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done ✓'**
  String get done;

  /// No description provided for @surahNumber.
  ///
  /// In en, this message translates to:
  /// **'Surah {number}'**
  String surahNumber(int number);

  /// No description provided for @hadithRef.
  ///
  /// In en, this message translates to:
  /// **'{collection} · #{number}'**
  String hadithRef(String collection, int number);

  /// No description provided for @listeningTapToSearch.
  ///
  /// In en, this message translates to:
  /// **'Listening… tap to search'**
  String get listeningTapToSearch;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get preparing;

  /// No description provided for @stopListening.
  ///
  /// In en, this message translates to:
  /// **'Stop listening'**
  String get stopListening;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get starting;

  /// No description provided for @reciteToFind.
  ///
  /// In en, this message translates to:
  /// **'Recite to find'**
  String get reciteToFind;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @surahsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} surahs'**
  String surahsCount(int count);

  /// No description provided for @ayahNumber.
  ///
  /// In en, this message translates to:
  /// **'Ayah {number}'**
  String ayahNumber(int number);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
