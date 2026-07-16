import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../util/log.dart';
import 'phoneme_matcher.dart';

/// A loaded surah: the phoneme clip for the matcher + a corpus-word-index →
/// mushaf-location map. The phoneme corpus segments words differently from the
/// mushaf (it merges/splits some), so each corpus word maps to the ONE-OR-MORE
/// mushaf "surah:ayah:word" glyphs it actually covers (precomputed offline by
/// tool/build_phoneme_align.py via letter alignment — see assets/asr/align/).
class SurahClip {
  final int surah;
  final PhonemeClip clip;
  final List<List<String>> wordLocations; // corpus word index -> mushaf locations
  final List<String> words; // corpus word index -> reference word string (a
  // whitespace-merged junction unit contains a space); drives the tajwīd review.
  const SurahClip(this.surah, this.clip, this.wordLocations, this.words);

  /// Primary mushaf glyph for a corpus word (for the moving marker).
  String? primary(int wordIndex) {
    if (wordIndex < 0 || wordIndex >= wordLocations.length) return null;
    final l = wordLocations[wordIndex];
    return l.isEmpty ? null : l.first;
  }

  /// ALL mushaf glyphs a corpus word covers. A corpus word can absorb several
  /// mushaf words (13% of Al-Baqara merges 2–5, e.g. word 173 = ظُلُمَـٰتٌۭ وَرَعْدٌۭ
  /// وَبَرْقٌۭ يَجْعَلُونَ). Highlighting the whole set as "current" (the RN app's
  /// approach) keeps the marker from hanging on the first glyph of a merged phrase.
  Set<String> glyphsOf(int wordIndex) {
    if (wordIndex < 0 || wordIndex >= wordLocations.length) return const {};
    return wordLocations[wordIndex].toSet();
  }
}

/// verse "surah:ayah" → the mushaf page (1..604) it starts on, for auto-following
/// the reader to the reciter's page. Loaded once from the ASR verse index.
Future<Map<String, int>> loadVersePages() async {
  final raw = json.decode(await rootBundle.loadString('assets/asr/verse_index.json')) as List;
  return {for (final e in raw) (e as Map<String, dynamic>)['k'] as String: (e['p'] as num).toInt()};
}

Future<List<String>> loadPhonemeUnits() async {
  final raw = await rootBundle.loadString('assets/asr/phoneme/tokens.txt');
  final units = <String>[];
  for (final line in raw.split('\n')) {
    final l = line.trimRight();
    if (l.isEmpty) continue;
    final sp = l.lastIndexOf(' ');
    final sym = sp < 0 ? l : l.substring(0, sp);
    if (sym.isNotEmpty) units.add(sym);
  }
  return units;
}

final _clipCache = <int, SurahClip>{};

/// Load (and cache) the phoneme clip + mushaf-location map for a surah (1..114).
Future<SurahClip> loadSurahClip(int surah) async {
  final cached = _clipCache[surah];
  if (cached != null) return cached;
  final tag = surah.toString().padLeft(3, '0');
  final j = json.decode(await rootBundle.loadString('assets/asr/quran_phonemes/$tag.json'))
      as Map<String, dynamic>;
  final wordStrings = [for (final w in (j['words'] as List)) w as String];
  final words = wordStrings.length;
  final phonemes = [for (final p in (j['phonemes'] as List)) p as String];
  final phonemeToWord = [for (final w in (j['phonemeToWord'] as List)) (w as num).toInt()];
  final boundaries = [for (final b in ((j['ayahBoundaries'] as List?) ?? const [0])) (b as num).toInt()];

  // Precomputed corpus-word → mushaf-location(s) alignment.
  List<List<String>> wordLocations;
  try {
    final a = json.decode(await rootBundle.loadString('assets/asr/align/$tag.json')) as List;
    wordLocations = [for (final e in a) [for (final l in (e as List)) l as String]];
  } catch (e) {
    // Fallback: derive from āyah boundaries — WRONG on any surah where the corpus
    // merges/splits words vs the mushaf (most of them). Should never happen: all
    // 114 align files ship as assets. Loud (error) so a packaging drop is obvious.
    Log.e('recite', 'align $tag MISSING ($e) — degraded boundary fallback (wrong on merges)');
    wordLocations = List.generate(words, (_) => <String>[]);
    var ayah = 0;
    for (var w = 0; w < words; w++) {
      while (ayah + 1 < boundaries.length && w >= boundaries[ayah + 1]) {
        ayah++;
      }
      wordLocations[w] = ['$surah:${ayah + 1}:${w - boundaries[ayah] + 1}'];
    }
  }

  final clip = SurahClip(
    surah,
    PhonemeClip(
      wordCount: words,
      phonemes: phonemes,
      phonemeToWord: phonemeToWord,
      ayahBoundaries: boundaries,
    ),
    wordLocations,
    wordStrings,
  );
  _clipCache[surah] = clip;
  return clip;
}

/// A loaded du'a: the phoneme clip for the matcher + the display words. Unlike a
/// surah there is no separate mushaf glyph — a du'a's corpus word IS its display
/// word, so `words[i]` is highlighted directly when corpus word `i` greens (1:1,
/// no location map, no align file).
class DuaClip {
  final String id;
  final PhonemeClip clip;
  final List<String> words; // corpus word index -> display Arabic
  const DuaClip(this.id, this.clip, this.words);
}

final _duaClipCache = <String, DuaClip>{};

/// Load (and cache) the phoneme clip + display words for a du'a by its id
/// (the corpus filename, e.g. 'dua-after-adhan').
Future<DuaClip> loadDuaClip(String id) async {
  final cached = _duaClipCache[id];
  if (cached != null) return cached;
  final j = json.decode(await rootBundle.loadString('assets/asr/dua_phonemes/$id.json'))
      as Map<String, dynamic>;
  final words = [for (final w in (j['words'] as List)) w as String];
  final phonemes = [for (final p in (j['phonemes'] as List)) p as String];
  final phonemeToWord = [for (final w in (j['phonemeToWord'] as List)) (w as num).toInt()];
  final boundaries = [for (final b in ((j['ayahBoundaries'] as List?) ?? const [0])) (b as num).toInt()];

  final clip = DuaClip(
    id,
    PhonemeClip(
      wordCount: words.length,
      phonemes: phonemes,
      phonemeToWord: phonemeToWord,
      ayahBoundaries: boundaries,
    ),
    words,
  );
  _duaClipCache[id] = clip;
  return clip;
}

Map<String, double>? _reliabilityCache;

// The reliability table is built from a single Al-Baqara device run, so a
// letter observed only once or twice reads reliability=1.0 (100% "correct") on
// pure luck, not evidence — e.g. ج/ث/ز (seen=1) and ظ/بڇ/قڇ (seen=2) all
// point-estimate to 1.0 and would clear the tajwīd review's gate with zero
// statistical grounding, flagging a CORRECT reciter as wrong. Below this many
// observations, treat the letter as reliability-UNKNOWN (0) rather than trust
// the raw ok/seen ratio, so tajweed_review.dart's existing `rel >= _threshold`
// gate silences it exactly like a genuinely blind letter. This also silences
// a few previously "reliable" thin-evidence letters (e.g. ط at seen=6) that
// aren't actually backed by enough samples yet — the honest cost of the fix,
// not a regression. Needs far more eval audio to raise back with real evidence.
const int _minReliabilitySamples = 20;

/// Per-letter reliability (letter → measured reliability, floored to 0 for
/// letters without enough samples) for the tajwīd review, loaded once from the
/// bundled phoneme-reliability asset.
Future<Map<String, double>> loadPhonemeReliability() async {
  final cached = _reliabilityCache;
  if (cached != null) return cached;
  final raw =
      json.decode(await rootBundle.loadString('assets/asr/phoneme-reliability.json')) as Map<String, dynamic>;
  return _reliabilityCache = {
    for (final e in raw.entries)
      e.key: ((e.value as Map)['seen'] as num).toInt() >= _minReliabilitySamples
          ? ((e.value as Map)['reliability'] as num).toDouble()
          : 0.0
  };
}
