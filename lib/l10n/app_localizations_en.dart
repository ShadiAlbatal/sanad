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

  @override
  String get greetingDawn => 'A blessed dawn';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'A blessed evening';

  @override
  String get greetingNight => 'A peaceful night';

  @override
  String get done => 'Done ✓';

  @override
  String surahNumber(int number) {
    return 'Surah $number';
  }

  @override
  String hadithRef(String collection, int number) {
    return '$collection · #$number';
  }

  @override
  String get listeningTapToSearch => 'Listening… tap to search';

  @override
  String get preparing => 'Preparing…';

  @override
  String get stopListening => 'Stop listening';

  @override
  String get starting => 'Starting';

  @override
  String get reciteToFind => 'Recite to find';

  @override
  String get search => 'Search';

  @override
  String surahsCount(int count) {
    return '$count surahs';
  }

  @override
  String ayahNumber(int number) {
    return 'Ayah $number';
  }

  @override
  String get countingWhatYouRecite => 'Counting what you recite…';

  @override
  String get tapMicAndRecite => 'Tap the mic and recite';

  @override
  String get hearIt => 'Hear it';

  @override
  String get audioUnavailable => 'Audio unavailable';

  @override
  String get noMistakesQuran =>
      'No mistakes yet. Tap the mic and recite — mispronounced,\nskipped, and off-text words show up here to review.';

  @override
  String get noMistakesDua =>
      'No mistakes yet. Tap the mic and recite — mispronounced\nand skipped words show up here to review.';

  @override
  String juzLabel(int number) {
    return 'Juz $number';
  }

  @override
  String hizbLabel(int number) {
    return 'Ḥizb $number';
  }

  @override
  String get privacyIntro =>
      'Sanad works fully offline and needs no account. The two “Help improve” switches are optional and independent: “Performance & usage” records an anonymous summary of each recitation, and “Essential app data” records anonymous crash/error summaries. Both are off by default.';

  @override
  String get privacyLocalNote =>
      'In this version nothing is uploaded anywhere — reports are written only to this device’s diagnostic log. Sending to a server stays off until a future update, and will always require this opt-in and a published privacy policy.';

  @override
  String get privacyShared1 =>
      'A random install id — a code for this app copy, not linked to you.';

  @override
  String get privacyShared2 =>
      'Which surah or du’a you read, and how far you reached.';

  @override
  String get privacyShared3 =>
      'How many sounds the app decoded, and whether it locked on.';

  @override
  String get privacyShared4 =>
      'Tajwīd notes it raised (the reference letter vs the one it heard).';

  @override
  String get privacyShared5 => 'Words skipped and how long the session was.';

  @override
  String get privacyShared6 =>
      'App version and your phone’s system (Android / iOS).';

  @override
  String get privacyShared7 =>
      'With “Essential app data” on: anonymous crash/error summaries (what failed and roughly where — never a full stack or your data).';

  @override
  String get privacyNever1 => 'Your voice or any audio recording.';

  @override
  String get privacyNever2 => 'Your name, email, or any account.';

  @override
  String get privacyNever3 => 'Your contacts or location.';

  @override
  String get privacyNever4 => 'Anything that identifies you personally.';
}
