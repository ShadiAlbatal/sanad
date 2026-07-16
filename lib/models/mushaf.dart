import '../theme/tajweed.dart';

enum LineType { surahHeader, basmala, opener, text }

LineType _lineType(String raw) {
  switch (raw) {
    case 'surah-header':
      return LineType.surahHeader;
    case 'basmala':
      return LineType.basmala;
    // A combined surah opener: the KFGQPC layout gives some surahs a single
    // top line holding BOTH the name and the basmala (first ayah lands on the
    // next line), vs the two-line header+basmala form.
    case 'surah-opener':
      return LineType.opener;
    default:
      return LineType.text;
  }
}

class MushafWord {
  final String location; // "2:255:3"
  final String glyph; // qpcV2 glyph (kept for future exact-glyph mode)
  final String uthmani; // plain uthmani text
  final String tajweed; // uthmani text with <rule class=..> tajweed markup
  final int surah;
  final int ayah;
  final int index;

  MushafWord({
    required this.location,
    required this.glyph,
    required this.uthmani,
    required this.tajweed,
  })  : surah = int.parse(location.split(':')[0]),
        ayah = int.parse(location.split(':')[1]),
        index = int.parse(location.split(':')[2]);

  factory MushafWord.fromJson(Map<String, dynamic> j) {
    final uthmani = (j['word'] ?? '') as String;
    return MushafWord(
      location: j['location'] as String,
      glyph: (j['qpcV2'] ?? '') as String,
      uthmani: uthmani,
      tajweed: (j['tj'] ?? uthmani) as String,
    );
  }

  List<TajweedSpan>? _spans;
  List<TajweedSpan> get spans => _spans ??= Tajweed.parse(tajweed);

  String? _plain;
  String get plain => _plain ??= spans.map((s) => s.text).join();

  double? measuredBaseWidth; // cached by the renderer at the base font size
}

class MushafLine {
  final int line;
  final LineType type;
  final String text; // header text or plain ayah text
  final String glyph; // basmala glyph
  final int? surah; // for surah header
  final List<MushafWord> words;

  MushafLine({
    required this.line,
    required this.type,
    required this.text,
    required this.glyph,
    required this.surah,
    required this.words,
  });

  factory MushafLine.fromJson(Map<String, dynamic> j) {
    final ws = (j['words'] as List?) ?? const [];
    return MushafLine(
      line: j['line'] as int,
      type: _lineType(j['type'] as String),
      text: (j['text'] ?? '') as String,
      glyph: (j['qpcV2'] ?? '') as String,
      surah: j['surah'] == null ? null : int.parse(j['surah'].toString()),
      words: ws
          .map((w) => MushafWord.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MushafPage {
  final int page;
  final List<MushafLine> lines;

  MushafPage({required this.page, required this.lines});

  factory MushafPage.fromJson(Map<String, dynamic> j) => MushafPage(
        page: j['page'] as int,
        lines: (j['lines'] as List)
            .map((l) => MushafLine.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

class PageMeta {
  final int juz;
  final int hizb;
  final int rub; // rub' al-hizb 1..240
  final int surah;
  PageMeta({required this.juz, required this.hizb, required this.rub, required this.surah});

  factory PageMeta.fromJson(Map<String, dynamic> j) => PageMeta(
        juz: j['juz'] as int,
        hizb: j['hizb'] as int,
        rub: j['rub'] as int,
        surah: j['surah'] as int,
      );

  // 0 = start of hizb, 1 = ¼, 2 = ½, 3 = ¾
  int get quarter => (rub - 1) % 4;
  static const _fracs = ['', '¼', '½', '¾'];
  String get quarterLabel => _fracs[quarter];
}

class Chapter {
  final int id;
  final String nameArabic;
  final String nameSimple;
  final String translated;
  final int versesCount;
  final String revelationPlace;
  final int startPage;

  Chapter({
    required this.id,
    required this.nameArabic,
    required this.nameSimple,
    required this.translated,
    required this.versesCount,
    required this.revelationPlace,
    required this.startPage,
  });

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        id: j['id'] as int,
        nameArabic: j['nameArabic'] as String,
        nameSimple: j['nameSimple'] as String,
        translated: j['translated'] as String,
        versesCount: j['versesCount'] as int,
        revelationPlace: j['revelationPlace'] as String,
        startPage: j['startPage'] as int,
      );
}
