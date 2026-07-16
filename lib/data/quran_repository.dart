import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/mushaf.dart';
import '../util/log.dart';

class QuranRepository {
  static const totalPages = 604;

  final Map<int, MushafPage> _pageCache = {};
  final Map<int, Future<MushafPage>> _pageFutures = {};
  List<Chapter>? _chapters;
  List<String>? _basmala;
  Map<int, PageMeta>? _pageMeta;

  /// Loads chapters, page metadata and basmala once. After this resolves the
  /// synchronous accessors below are safe to use.
  Future<void> preload() async {
    await Future.wait([chapters(), _loadMeta(), basmalaWords()]);
  }

  Future<void> _loadMeta() async {
    if (_pageMeta != null) return;
    final raw = await rootBundle.loadString('assets/data/page_meta.json');
    final m = json.decode(raw) as Map<String, dynamic>;
    _pageMeta = {
      for (final e in m.entries)
        int.parse(e.key): PageMeta.fromJson(e.value as Map<String, dynamic>)
    };
  }

  PageMeta? metaSync(int page) => _pageMeta?[page];

  Chapter? chapterForPageSync(int page) {
    final list = _chapters;
    if (list == null) return null;
    Chapter current = list.first;
    for (final c in list) {
      if (c.startPage <= page) {
        current = c;
      } else {
        break;
      }
    }
    return current;
  }

  MushafPage? cachedPage(int page) => _pageCache[page];

  Future<List<String>> basmalaWords() async {
    if (_basmala != null) return _basmala!;
    final raw = await rootBundle.loadString('assets/data/basmala.json');
    final m = json.decode(raw) as Map<String, dynamic>;
    _basmala = (m['words'] as List).cast<String>();
    return _basmala!;
  }

  List<String>? get basmalaSync => _basmala;

  Future<List<Chapter>> chapters() async {
    if (_chapters != null) return _chapters!;
    final raw = await rootBundle.loadString('assets/data/chapters.json');
    final list = json.decode(raw) as List;
    _chapters = list
        .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
        .toList();
    return _chapters!;
  }

  Future<MushafPage> page(int page) {
    return _pageFutures.putIfAbsent(page, () async {
      try {
        final name = 'assets/mushaf/page-${page.toString().padLeft(3, '0')}.json';
        final raw = await rootBundle.loadString(name);
        final p = MushafPage.fromJson(json.decode(raw) as Map<String, dynamic>);
        _pageCache[page] = p;
        Log.d('load', 'page $page: ${p.lines.length} lines');
        return p;
      } catch (e, st) {
        Log.e('load', 'page $page: $e', st);
        // Don't memoize a failed load: a transient IO/OOM hiccup would otherwise
        // poison this page for the rest of the app run with no way to retry.
        _pageFutures.remove(page);
        rethrow;
      }
    });
  }

  Future<Chapter> chapterForPage(int page) async {
    final list = await chapters();
    Chapter current = list.first;
    for (final c in list) {
      if (c.startPage <= page) {
        current = c;
      } else {
        break;
      }
    }
    return current;
  }
}
