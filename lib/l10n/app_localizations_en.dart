// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Sanad';

  @override
  String get tabHome => 'Home';

  @override
  String get tabQuran => 'Quran';

  @override
  String get tabDuas => 'Duas';

  @override
  String get tabHadith => 'Hadith';

  @override
  String get tabCounter => 'Counter';

  @override
  String get settings => 'Settings';

  @override
  String get profile => 'Profile';

  @override
  String get dataPrivacy => 'Data & Privacy';

  @override
  String get surahs => 'Surahs';

  @override
  String get surahIndex => 'Surah index';

  @override
  String get duasAndAdhkar => 'Duas & Adhkār';

  @override
  String get adhkar => 'Adhkar';

  @override
  String get searchQuran => 'Search the Quran';

  @override
  String get searchHadith => 'Search hadith';

  @override
  String get searchDuas => 'Search duas';

  @override
  String get reciteToFindVerse => 'Recite to find a verse';

  @override
  String get reciteToFindHadith => 'Recite to find a hadith';

  @override
  String get reciteToFindDua => 'Recite to find a dua';

  @override
  String get noMatchesBrowseAll =>
      'No matches — clear the search to browse all';

  @override
  String get noMatchesBrowseSurahs =>
      'No matches — clear the search to browse surahs';

  @override
  String get history => 'History';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get historyAndBookmarks => 'History & bookmarks';

  @override
  String get bookmark => 'Bookmark';

  @override
  String get removeBookmark => 'Remove bookmark';

  @override
  String get clear => 'Clear';

  @override
  String get nothingOpenedYet => 'Nothing opened yet';

  @override
  String get nothingBookmarkedYet => 'Nothing bookmarked yet';

  @override
  String resultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: '0 results',
    );
    return '$_temp0';
  }

  @override
  String get mistakes => 'Mistakes';

  @override
  String get hide => 'Hide';

  @override
  String get reveal => 'Reveal';

  @override
  String get revealNextWord => 'Reveal next word';

  @override
  String get revealNextAyah => 'Reveal next ayah';

  @override
  String get revealNextSegment => 'Reveal next segment';

  @override
  String get hidePreviousWord => 'Hide previous word';

  @override
  String get hidePreviousAyah => 'Hide previous ayah';

  @override
  String get hidePreviousSegment => 'Hide previous segment';

  @override
  String get back => 'Back';

  @override
  String get retry => 'Retry';

  @override
  String get toggleTheme => 'Toggle theme';

  @override
  String pageNumber(int page) {
    return 'Page $page';
  }

  @override
  String get pageLoadFailed => 'This page could not be loaded.';

  @override
  String versesCount(int count) {
    return '$count verses';
  }

  @override
  String get reset => 'Reset';

  @override
  String get resetAllCounts => 'Reset all counts?';

  @override
  String get resetAllCountsBody =>
      'This clears every tasbīḥ tally back to zero.';

  @override
  String get cancel => 'Cancel';

  @override
  String get countByVoice => 'Count by voice';

  @override
  String get listeningReciteFreely => 'Listening — recite freely';

  @override
  String get counterHint =>
      'Tap a card or the mic and recite — it counts as you go.';

  @override
  String repeatTimes(int count) {
    return 'Repeat ×$count';
  }

  @override
  String get continueReading => 'Continue reading';

  @override
  String get openTheAdhkar => 'Open the adhkar';

  @override
  String get lastPageRead => 'Last page read';

  @override
  String get morningAdhkar => 'Morning adhkār';

  @override
  String get eveningAdhkar => 'Evening adhkār';

  @override
  String get nightIstighfar => 'Night — istighfār';

  @override
  String get rememberAllah => 'Remember Allah';

  @override
  String get greeting => 'Assalamu ʿalaykum';

  @override
  String get guestSignInSoon => 'Guest · sign-in coming soon';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get accent => 'Accent';

  @override
  String get accentAuto => 'Auto';

  @override
  String get accentIris => 'Iris';

  @override
  String get accentEmerald => 'Emerald';

  @override
  String get accentCoral => 'Coral';

  @override
  String get accentOcean => 'Ocean';

  @override
  String get accentAutoCaption =>
      'Auto shifts the colour with the time of day.';

  @override
  String get language => 'Language';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get helpImprove => 'Help improve Sanad';

  @override
  String get crashReports => 'Crash & error reports';

  @override
  String get crashReportsBody =>
      'Optional. Anonymous crash/error summaries to help fix bugs. The app works fully without this.';

  @override
  String get performanceUsage => 'Performance & usage';

  @override
  String get performanceUsageBody =>
      'Anonymous performance and usage to improve the app.';

  @override
  String get privacyCaption =>
      'Anonymous, and kept on-device for now — nothing is uploaded anywhere yet. You can use the app fully without an account or sharing. See Data & Privacy.';

  @override
  String get about => 'About';

  @override
  String get appTagline =>
      'A calm Quran companion — read, listen, and remember.';

  @override
  String get licenses => 'Licenses & Attribution';

  @override
  String get neverShared => 'Never shared';

  @override
  String get sharedOptIn => 'Shared — only if you opt in';

  @override
  String get offTextVerse =>
      'Off-text — recitation did not match the verse here';

  @override
  String get offTextDua => 'Off-text — recitation did not match here';

  @override
  String get skippedWord => 'Skipped — jumped over this word';

  @override
  String get makhrajExpected => 'makhraj: expected ';

  @override
  String get heardArrow => '  →  heard ';

  @override
  String heardLabel(String text) {
    return 'heard: $text';
  }

  @override
  String get pronunciation => 'pronunciation';
}
