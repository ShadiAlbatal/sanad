import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/quran_repository.dart';
import '../services/asr/asr_engine.dart';
import '../services/asr/file_source.dart';
import '../services/asr/word_asr.dart';
import '../services/page_render_diagnostic.dart';
import '../state/reading_state.dart';
import '../util/log.dart';

// Bundled recordings fed through the real ASR engine for tracing (see
// ReadingState.runFileDiagnostic). Ayat al-Kursi = verse 2:255.
const _diagClips = [
  ('Al-Fatiha', 'assets/debug_audio/alfatiha_16k.wav'),
  ('Ayat al-Kursi', 'assets/debug_audio/alkursi_16k.wav'),
  ('Kursi (wrong)', 'assets/debug_audio/alkursi_wrong_16k.wav'),
];

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  // SPIKE: FastConformer word-ASR evaluation (branch spike/fastconformer-search).
  final WordAsr _word = WordAsr();
  bool _wordBusy = false;
  bool _recording = false;

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _wordTranscribeBundled() async {
    if (_wordBusy) return;
    setState(() => _wordBusy = true);
    try {
      await _word.ensureLoaded();
      final clip = await loadWavAsset('assets/debug_audio/alkursi_16k.wav');
      _word.transcribe(clip.pcm);
    } catch (e, st) {
      Log.e('wordasr', e, st);
    } finally {
      if (mounted) setState(() => _wordBusy = false);
    }
  }

  Future<void> _wordRecordAndTranscribe(AsrEngine engine) async {
    if (_wordBusy) return;
    setState(() => _wordBusy = true);
    final buf = <int>[];
    try {
      await _word.ensureLoaded();
      if (!await engine.mic.hasPermission()) {
        Log.d('wordasr', 'mic permission denied');
        return;
      }
      Log.d('wordasr', '=== recording 8s for FastConformer (recite now) ===');
      setState(() => _recording = true);
      await engine.mic.start((pcm) => buf.addAll(pcm));
      await Future.delayed(const Duration(seconds: 8));
      await engine.mic.stop();
      if (mounted) setState(() => _recording = false);
      Log.d('wordasr', 'captured ${(buf.length / 16000).toStringAsFixed(1)}s (${buf.length} samples)');
      _word.transcribe(Int16List.fromList(buf));
      await Log.flushFile();
    } catch (e, st) {
      Log.e('wordasr', e, st);
    } finally {
      if (mounted) setState(() { _wordBusy = false; _recording = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Log'),
        actions: [
          IconButton(
            icon: Icon(Log.traceOn ? Icons.blur_on_rounded : Icons.blur_off_rounded),
            tooltip: Log.traceOn ? 'Trace ON (tap to silence firehose)' : 'Trace OFF',
            onPressed: () => setState(() => Log.traceOn = !Log.traceOn),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: 'Copy all',
            onPressed: () => Clipboard.setData(
                ClipboardData(text: Log.lines.value.join('\n'))),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear',
            onPressed: Log.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Consumer<ReadingState>(
            builder: (context, reading, _) {
              final busy = reading.asrActive || reading.asrStarting;
              return Container(
                width: double.infinity,
                color: Colors.black.withValues(alpha: 0.04),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Feed a recording through the ASR (trace in log):',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final (name, asset) in _diagClips)
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => context
                                    .read<ReadingState>()
                                    .runFileDiagnostic(asset, label: name),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: Text(name, style: const TextStyle(fontSize: 12)),
                          ),
                        if (busy)
                          FilledButton.icon(
                            onPressed: reading.stopFileDiagnostic,
                            icon: const Icon(Icons.stop_rounded, size: 16),
                            label: Text(reading.asrStarting ? 'loading…' : 'Stop ${reading.asrTimeLabel}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        OutlinedButton.icon(
                          onPressed: () {
                            // Available text width mirrors _PageLeaf: full width
                            // minus its 8px margins, 32px padding, and the
                            // LayoutBuilder's -4 inset.
                            final w = MediaQuery.sizeOf(context).width - 44;
                            runPageRenderScan(context.read<QuranRepository>(), w);
                          },
                          icon: const Icon(Icons.grid_on_rounded, size: 16),
                          label: const Text('Scan pages', style: TextStyle(fontSize: 12)),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: reading.sherpaBusy
                              ? null
                              : () => context.read<ReadingState>().runSherpaTest(
                                  'assets/debug_audio/alkursi_16k.wav',
                                  label: 'Ayat al-Kursi'),
                          icon: reading.sherpaBusy
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.hearing_rounded, size: 16),
                          label: const Text('Sherpa: hear Kursi', style: TextStyle(fontSize: 12)),
                        ),
                        FilledButton.icon(
                          onPressed: reading.evalBusy
                              ? null
                              : () => context.read<ReadingState>().runEval(),
                          icon: reading.evalBusy
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.fact_check_rounded, size: 16),
                          label: Text(reading.evalBusy ? 'Evaluating…' : 'Run eval (all clips)',
                              style: const TextStyle(fontSize: 12)),
                        ),
                        // SPIKE: FastConformer word-ASR — measures load time + transcript.
                        FilledButton.tonalIcon(
                          onPressed: _wordBusy ? null : _wordTranscribeBundled,
                          icon: _wordBusy
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.text_fields_rounded, size: 16),
                          label: const Text('Word ASR: Kursi', style: TextStyle(fontSize: 12)),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _wordBusy
                              ? null
                              : () => _wordRecordAndTranscribe(context.read<AsrEngine>()),
                          icon: _recording
                              ? const Icon(Icons.mic_rounded, size: 16, color: Colors.red)
                              : const Icon(Icons.fiber_manual_record_rounded, size: 16),
                          label: Text(_recording ? 'Recording 8s…' : 'Word ASR: record 8s',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          if (Log.logFilePath != null)
            Container(
              width: double.infinity,
              color: Colors.black.withValues(alpha: 0.05),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.save_alt_rounded, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      'Saved to: ${Log.logFilePath}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: 'Copy path',
                    onPressed: () => Clipboard.setData(ClipboardData(text: Log.logFilePath!)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: Log.lines,
              builder: (context, lines, _) {
                if (lines.isEmpty) {
                  return const Center(child: Text('No log entries yet.'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                    final line = lines[lines.length - 1 - i];
                    final isErr = line.contains('ERROR');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.35,
                          color: isErr ? Colors.red : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
