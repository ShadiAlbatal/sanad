// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'سَنَد';

  @override
  String get tabHome => 'الرئيسية';

  @override
  String get tabQuran => 'القرآن';

  @override
  String get tabDuas => 'الأدعية';

  @override
  String get tabHadith => 'الحديث';

  @override
  String get tabCounter => 'التسبيح';

  @override
  String get settings => 'الإعدادات';

  @override
  String get profile => 'الملف الشخصي';

  @override
  String get dataPrivacy => 'البيانات والخصوصية';

  @override
  String get surahs => 'السور';

  @override
  String get surahIndex => 'فهرس السور';

  @override
  String get duasAndAdhkar => 'الأدعية والأذكار';

  @override
  String get adhkar => 'الأذكار';

  @override
  String get searchQuran => 'ابحث في القرآن';

  @override
  String get searchHadith => 'ابحث في الحديث';

  @override
  String get searchDuas => 'ابحث في الأدعية';

  @override
  String get reciteToFindVerse => 'اتلُ لتجد آية';

  @override
  String get reciteToFindHadith => 'اتلُ لتجد حديثًا';

  @override
  String get reciteToFindDua => 'اتلُ لتجد دعاءً';

  @override
  String get noMatchesBrowseAll => 'لا توجد نتائج — امسح البحث لتصفّح الكل';

  @override
  String get noMatchesBrowseSurahs => 'لا توجد نتائج — امسح البحث لتصفّح السور';

  @override
  String get history => 'السجل';

  @override
  String get bookmarks => 'المحفوظات';

  @override
  String get historyAndBookmarks => 'السجل والمحفوظات';

  @override
  String get bookmark => 'حفظ';

  @override
  String get removeBookmark => 'إزالة من المحفوظات';

  @override
  String get clear => 'مسح';

  @override
  String get nothingOpenedYet => 'لم تفتح شيئًا بعد';

  @override
  String get nothingBookmarkedYet => 'لا توجد محفوظات بعد';

  @override
  String resultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نتيجة',
      many: '$count نتيجة',
      few: '$count نتائج',
      two: 'نتيجتان',
      one: 'نتيجة واحدة',
      zero: 'لا نتائج',
    );
    return '$_temp0';
  }

  @override
  String get mistakes => 'الأخطاء';

  @override
  String get hide => 'إخفاء';

  @override
  String get reveal => 'إظهار';

  @override
  String get revealNextWord => 'أظهر الكلمة التالية';

  @override
  String get revealNextAyah => 'أظهر الآية التالية';

  @override
  String get revealNextSegment => 'أظهر المقطع التالي';

  @override
  String get hidePreviousWord => 'أخفِ الكلمة السابقة';

  @override
  String get hidePreviousAyah => 'أخفِ الآية السابقة';

  @override
  String get hidePreviousSegment => 'أخفِ المقطع السابق';

  @override
  String get back => 'رجوع';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get toggleTheme => 'تبديل المظهر';

  @override
  String pageNumber(int page) {
    return 'صفحة $page';
  }

  @override
  String get pageLoadFailed => 'تعذّر تحميل هذه الصفحة.';

  @override
  String versesCount(int count) {
    return '$count آية';
  }

  @override
  String get reset => 'تصفير';

  @override
  String get resetAllCounts => 'تصفير جميع العدادات؟';

  @override
  String get resetAllCountsBody => 'سيعيد هذا كل تسبيحة إلى الصفر.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get countByVoice => 'العدّ بالصوت';

  @override
  String get listeningReciteFreely => 'يستمع — سبّح كما تشاء';

  @override
  String get counterHint =>
      'المس بطاقة أو الميكروفون وسبّح — يُحتسب أولًا بأول.';

  @override
  String repeatTimes(int count) {
    return 'التكرار ×$count';
  }

  @override
  String get continueReading => 'متابعة القراءة';

  @override
  String get openTheAdhkar => 'افتح الأذكار';

  @override
  String get lastPageRead => 'آخر صفحة قُرئت';

  @override
  String get morningAdhkar => 'أذكار الصباح';

  @override
  String get eveningAdhkar => 'أذكار المساء';

  @override
  String get nightIstighfar => 'الليل — الاستغفار';

  @override
  String get rememberAllah => 'اذكر الله';

  @override
  String get greeting => 'السلام عليكم';

  @override
  String get guestSignInSoon => 'زائر · تسجيل الدخول قريبًا';

  @override
  String get appearance => 'المظهر';

  @override
  String get themeSystem => 'حسب النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get accent => 'اللون المميّز';

  @override
  String get accentAuto => 'تلقائي';

  @override
  String get accentIris => 'بنفسجي';

  @override
  String get accentEmerald => 'زمرّدي';

  @override
  String get accentCoral => 'مرجاني';

  @override
  String get accentOcean => 'محيطي';

  @override
  String get accentAutoCaption => '«تلقائي» يغيّر اللون حسب وقت اليوم.';

  @override
  String get language => 'اللغة';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get helpImprove => 'ساعد في تحسين سَنَد';

  @override
  String get crashReports => 'تقارير الأعطال والأخطاء';

  @override
  String get crashReportsBody =>
      'اختياري. ملخّصات مجهولة للأعطال تساعد على إصلاح الخلل. يعمل التطبيق كاملًا بدونها.';

  @override
  String get performanceUsage => 'الأداء والاستخدام';

  @override
  String get performanceUsageBody =>
      'بيانات أداء واستخدام مجهولة لتحسين التطبيق.';

  @override
  String get privacyCaption =>
      'بيانات مجهولة، وتُحفظ على الجهاز حاليًا — لا يُرفع شيء إلى أي مكان بعد. يمكنك استخدام التطبيق كاملًا دون حساب أو مشاركة. انظر البيانات والخصوصية.';

  @override
  String get about => 'عن التطبيق';

  @override
  String get appTagline => 'رفيق هادئ للقرآن — اقرأ واستمع واحفظ.';

  @override
  String get licenses => 'التراخيص والإسناد';

  @override
  String get neverShared => 'لا تُشارَك أبدًا';

  @override
  String get sharedOptIn => 'تُشارَك — فقط إن وافقت';

  @override
  String get offTextVerse => 'خارج النص — لم تطابق التلاوة الآية هنا';

  @override
  String get offTextDua => 'خارج النص — لم تطابق التلاوة هنا';

  @override
  String get skippedWord => 'تخطٍّ — تم تجاوز هذه الكلمة';

  @override
  String get makhrajExpected => 'المخرج: المتوقَّع ';

  @override
  String get heardArrow => '  ←  سُمِع ';

  @override
  String heardLabel(String text) {
    return 'سُمِع: $text';
  }

  @override
  String get pronunciation => 'النطق';

  @override
  String get greetingDawn => 'فجرٌ مبارك';

  @override
  String get greetingMorning => 'صباح الخير';

  @override
  String get greetingAfternoon => 'طاب نهارك';

  @override
  String get greetingEvening => 'مساءٌ مبارك';

  @override
  String get greetingNight => 'ليلةٌ هانئة';

  @override
  String get done => 'تمّ ✓';

  @override
  String surahNumber(int number) {
    return 'سورة $number';
  }

  @override
  String hadithRef(String collection, int number) {
    return '$collection · #$number';
  }

  @override
  String get listeningTapToSearch => 'يستمع… المس للبحث';

  @override
  String get preparing => 'جارٍ التحضير…';

  @override
  String get stopListening => 'أوقف الاستماع';

  @override
  String get starting => 'جارٍ البدء';

  @override
  String get reciteToFind => 'اتلُ للبحث';

  @override
  String get search => 'بحث';

  @override
  String surahsCount(int count) {
    return '$count سورة';
  }

  @override
  String ayahNumber(int number) {
    return 'آية $number';
  }
}
