import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/quran_repository.dart';
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
