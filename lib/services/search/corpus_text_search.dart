import 'dart:isolate';
import '../asr/dua_search.dart';
import '../asr/hadith_search.dart';
import '../../util/log.dart';
import 'text_search.dart';

/// Cached, off-thread BM25 text indexes for the typed-search bar — one per corpus,
/// built once from the SAME loaded corpus the voice finder uses (no second asset
/// decode). The BM25 build (tokenize + postings) runs in an `Isolate.run` so
/// opening a tab and typing never janks a frame; concurrent callers share one
/// in-flight build (mirrors the loader dedup in dua_search/hadith_search).

TextSearch? _duaCache;
Future<TextSearch>? _duaLoading;

Future<TextSearch> loadDuaTextSearch() async {
  final cached = _duaCache;
  if (cached != null) return cached;
  return _duaLoading ??= _buildDuaTextSearch();
}

Future<TextSearch> _buildDuaTextSearch() async {
  final sw = Stopwatch()..start();
  try {
    final corpus = await loadDuaSearch();
    final docs = [for (final m in corpus.allDuas) TextSearchDoc(m.id, m.arabic)];
    final index = await Isolate.run(() => TextSearch(docs));
    Log.d('duasearch', 'text index ready: ${index.docCount} duas, build ${sw.elapsedMilliseconds}ms');
    return _duaCache = index;
  } catch (e, st) {
    _duaLoading = null; // let a later caller retry the build
    Log.e('duasearch', 'text index build FAILED after ${sw.elapsedMilliseconds}ms: $e', st);
    rethrow;
  }
}

TextSearch? _hadithCache;
Future<TextSearch>? _hadithLoading;

Future<TextSearch> loadHadithTextSearch() async {
  final cached = _hadithCache;
  if (cached != null) return cached;
  return _hadithLoading ??= _buildHadithTextSearch();
}

Future<TextSearch> _buildHadithTextSearch() async {
  final sw = Stopwatch()..start();
  try {
    final corpus = await loadHadithSearch();
    final docs = [for (final e in corpus.allHadith) TextSearchDoc(e.id, e.text)];
    final index = await Isolate.run(() => TextSearch(docs));
    Log.d('hadithsearch', 'text index ready: ${index.docCount} hadith, build ${sw.elapsedMilliseconds}ms');
    return _hadithCache = index;
  } catch (e, st) {
    _hadithLoading = null; // let a later caller retry the build
    Log.e('hadithsearch', 'text index build FAILED after ${sw.elapsedMilliseconds}ms: $e', st);
    rethrow;
  }
}
