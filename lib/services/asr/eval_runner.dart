import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../../util/log.dart';
import 'file_source.dart';
import 'phoneme_corpus.dart';
import 'phoneme_matcher.dart';
import 'sherpa_asr.dart';

/// Batch evaluation: runs every bundled recording (assets/eval_audio/manifest
/// .json) through the real streaming pipeline (sherpa phoneme engine → phoneme
/// matcher), logs a deep per-clip trace, and writes a timestamped JSON eval
/// file to external storage for `adb pull`. Correct clips should light most
/// words; "wrong" clips should light few — that contrast is the eval signal.
class EvalRunner {
  final SherpaAsr asr;
  final List<String> units;
  EvalRunner(this.asr, this.units);

  Future<String?> runAll() async {
    final manifest = json.decode(await rootBundle.loadString('assets/eval_audio/manifest.json')) as List;
    Log.d('eval', '================ EVAL START (${manifest.length} clips) ================');
    final results = <Map<String, dynamic>>[];

    for (final m in manifest) {
      final file = m['file'] as String;
      final surah = (m['surah'] as num).toInt();
      final label = m['label'] as String;
      final kind = m['kind'] as String;
      try {
        final res = await _runClip(file: file, surah: surah, label: label, kind: kind);
        results.add(res);
      } catch (e, st) {
        Log.e('eval', 'clip $file failed: $e', st);
        results.add({'file': file, 'label': label, 'error': '$e'});
      }
    }

    // Summary table.
    Log.d('eval', '---------------- EVAL SUMMARY ----------------');
    for (final r in results) {
      if (r['error'] != null) {
        Log.d('eval', '${(r['label'] as String).padRight(24)} ERROR ${r['error']}');
        continue;
      }
      Log.d('eval',
          '${(r['label'] as String).padRight(24)} ${r['kind'].toString().padRight(8)} '
          'green ${r['green']}/${r['words']} (${((r['greenFrac'] as num) * 100).toStringAsFixed(0)}%) '
          'phonemes=${r['phonemeCount']} final=${r['finalLocation']}');
    }

    final path = await _write(results);
    Log.d('eval', '================ EVAL DONE -> $path ================');
    await Log.flushFile();
    return path;
  }

  Future<Map<String, dynamic>> _runClip({
    required String file,
    required int surah,
    required String label,
    required String kind,
  }) async {
    Log.d('eval', '=== CLIP $label ($file, surah $surah, $kind) ===');
    final clip = await loadWavAsset('assets/eval_audio/$file');
    final sc = await loadSurahClip(surah);
    final matcher = PhonemeMatchSession(sc.clip, units);
    asr.resetStream();

    const chunkSize = 1600; // 100ms
    final cursorPath = <int>[];
    var lastPhonemeCount = 0;
    MatchOutput? out;
    var chunkNo = 0;
    for (var off = 0; off < clip.pcm.length; off += chunkSize) {
      final end = off + chunkSize < clip.pcm.length ? off + chunkSize : clip.pcm.length;
      final tokens = asr.accept(Int16List.sublistView(clip.pcm, off, end));
      chunkNo++;
      if (tokens.isNotEmpty) {
        out = matcher.apply(tokens);
        cursorPath.add(out.cursor);
        // Deep per-second trace: cursor + phoneme growth.
        if (chunkNo % 10 == 0) {
          final loc = sc.primary(out.cursor) ?? '-';
          Log.d('eval', '  ${(off / 16000).toStringAsFixed(1)}s cursor=${out.cursor} @$loc '
              'phonemes=${tokens.length}(+${tokens.length - lastPhonemeCount})');
        }
        lastPhonemeCount = tokens.length;
      }
    }
    final tail = asr.finish();
    if (tail.isNotEmpty) {
      out = matcher.apply(tail);
      cursorPath.add(out.cursor);
    }

    final n = sc.clip.wordCount;
    final green = out?.states.where((s) => s == WordState.correct).length ?? 0;
    final skipped = out?.states.where((s) => s == WordState.skipped).length ?? 0;
    final finalCursor = out?.cursor ?? -1;
    final finalLoc = sc.primary(finalCursor) ?? '-';
    final heardStr = tail.join();

    Log.d('eval', 'RESULT $label: green $green/$n skipped=$skipped phonemes=${tail.length} '
        'final=$finalLoc  heard="${heardStr.length > 120 ? "${heardStr.substring(0, 120)}…" : heardStr}"');

    return {
      'file': file,
      'label': label,
      'surah': surah,
      'kind': kind,
      'durationS': double.parse((clip.pcm.length / 16000).toStringAsFixed(1)),
      'words': n,
      'green': green,
      'skipped': skipped,
      'greenFrac': n == 0 ? 0.0 : green / n,
      'phonemeCount': tail.length,
      'finalCursor': finalCursor,
      'finalLocation': finalLoc,
      'heard': heardStr,
      'cursorPath': cursorPath,
    };
  }

  Future<String?> _write(List<Map<String, dynamic>> results) async {
    try {
      Directory? base = await getExternalStorageDirectory();
      base ??= await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/eval');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/eval_${_stamp()}.json');
      const enc = JsonEncoder.withIndent('  ');
      f.writeAsStringSync(enc.convert({'clips': results.length, 'results': results}));
      return f.path;
    } catch (e) {
      Log.e('eval', 'write failed: $e');
      return null;
    }
  }

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
