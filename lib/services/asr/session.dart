import 'pronunciation_head.dart';

/// One BPE piece = the finest unit the model scores. For Arabic these are
/// letters and diacritic clusters (e.g. 'ك', the shadda 'ّ', 'الر'), which is
/// what "phoneme-level" means here — there is no separate IPA phonemizer; the
/// tokenizer pieces + the pronunciation head's per-token feature table are the
/// phonology the model exposes.
class PhonemeScore {
  final String piece; // human-readable unit (▁ word-boundary marker stripped)
  final int tokenId;
  final double prob; // P(pronounced correctly)
  final Deviation deviation;
  const PhonemeScore(this.piece, this.tokenId, this.prob, this.deviation);

  Map<String, dynamic> toJson() => {
        'piece': piece,
        'id': tokenId,
        'p': double.parse(prob.toStringAsFixed(3)),
        'dev': deviation.name,
      };
}

/// Emitted by the engine for each word the tracker commits — carries both the
/// per-phoneme scores and the audio sample range for playback.
class WordScore {
  final String location; // s:a:w
  final String expectedText; // decoded reference (imlaei) word
  final String heardText; // decoded from what the model actually heard
  final double prob; // word-level average P(correct)
  final Deviation deviation;
  final List<PhonemeScore> phonemes;
  final int startSample; // into the retained session PCM (16kHz)
  final int endSample;
  const WordScore({
    required this.location,
    required this.expectedText,
    required this.heardText,
    required this.prob,
    required this.deviation,
    required this.phonemes,
    required this.startSample,
    required this.endSample,
  });
}

enum MistakeKind {
  mispronounced, // word read but pronunciation head flagged it (minor/major)
  skipped, // word jumped over (1-word forward skip)
  offText, // sustained off-text recitation (warning)
}

/// A single reviewable mistake in the Mistakes sheet.
class RecitationMistake {
  final MistakeKind kind;
  final String location; // s:a:w ('' for offText)
  final String expectedText;
  final String heardText;
  final double? prob;
  final List<PhonemeScore> phonemes; // the offending units first
  final int startSample; // audio range (−1/−1 when no audio, e.g. skipped)
  final int endSample;

  const RecitationMistake({
    required this.kind,
    required this.location,
    required this.expectedText,
    required this.heardText,
    required this.prob,
    required this.phonemes,
    required this.startSample,
    required this.endSample,
  });

  bool get hasAudio => startSample >= 0 && endSample > startSample;
  Duration get at => Duration(milliseconds: (startSample / 16.0).round());

  /// The specific units that were wrong (for "what is the mistake").
  List<PhonemeScore> get badPhonemes =>
      phonemes.where((p) => p.deviation != Deviation.ok).toList();

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'loc': location,
        'expected': expectedText,
        'heard': heardText,
        'p': prob == null ? null : double.parse(prob!.toStringAsFixed(3)),
        'phonemes': [for (final p in phonemes) p.toJson()],
        'startSample': startSample,
        'endSample': endSample,
      };
}

/// Accumulates everything heard in one recitation session, both for the live
/// Mistakes list and the end-of-session analytics report.
class SessionRecorder {
  final String sessionId;
  final DateTime startedAt;

  final List<WordScore> words = []; // every scored word, in order
  final List<RecitationMistake> mistakes = [];
  int offTextCount = 0;

  SessionRecorder(this.sessionId, this.startedAt);

  void addWord(WordScore w) {
    words.add(w);
    if (w.deviation != Deviation.ok) {
      final bad = w.phonemes.where((p) => p.deviation != Deviation.ok).toList()
        ..sort((a, b) => a.prob.compareTo(b.prob));
      final rest = w.phonemes.where((p) => p.deviation == Deviation.ok);
      mistakes.add(RecitationMistake(
        kind: MistakeKind.mispronounced,
        location: w.location,
        expectedText: w.expectedText,
        heardText: w.heardText,
        prob: w.prob,
        phonemes: [...bad, ...rest],
        startSample: w.startSample,
        endSample: w.endSample,
      ));
    }
  }

  void addSkip(String location, String expectedText) {
    mistakes.add(RecitationMistake(
      kind: MistakeKind.skipped,
      location: location,
      expectedText: expectedText,
      heardText: '',
      prob: null,
      phonemes: const [],
      startSample: -1,
      endSample: -1,
    ));
  }

  void addOffText(int startSample, int endSample) {
    offTextCount++;
    mistakes.add(RecitationMistake(
      kind: MistakeKind.offText,
      location: '',
      expectedText: '',
      heardText: '',
      prob: null,
      phonemes: const [],
      startSample: startSample,
      endSample: endSample,
    ));
  }

  /// Aggregate stats + full per-word detail for analytics (see AnalyticsSink).
  Map<String, dynamic> report({required int endedAtMs}) {
    final scored = words.length;
    final ok = words.where((w) => w.deviation == Deviation.ok).length;
    final minor = words.where((w) => w.deviation == Deviation.minor).length;
    final major = words.where((w) => w.deviation == Deviation.major).length;
    final skipped = mistakes.where((m) => m.kind == MistakeKind.skipped).length;
    final avg = scored == 0 ? 0.0 : words.map((w) => w.prob).reduce((a, b) => a + b) / scored;
    final verses = words.map((w) {
      final p = w.location.split(':');
      return '${p[0]}:${p[1]}';
    }).toSet().toList();
    return {
      'sessionId': sessionId,
      'startedAtMs': startedAt.millisecondsSinceEpoch,
      'endedAtMs': endedAtMs,
      'wordsScored': scored,
      'wordAccuracy': double.parse((scored == 0 ? 0.0 : ok / scored).toStringAsFixed(3)),
      'avgPronProb': double.parse(avg.toStringAsFixed(3)),
      'ok': ok,
      'minor': minor,
      'major': major,
      'skipped': skipped,
      'offText': offTextCount,
      'verses': verses,
      'words': [
        for (final w in words)
          {
            'loc': w.location,
            'expected': w.expectedText,
            'heard': w.heardText,
            'p': double.parse(w.prob.toStringAsFixed(3)),
            'dev': w.deviation.name,
            'phonemes': [for (final ph in w.phonemes) ph.toJson()],
          }
      ],
    };
  }
}
