/// Tracks how confidently a live voice search has converged on ONE result, so the
/// UI can fill a "trust" ring and auto-open when it's sure. Fed the ranked top
/// results after each interim transcription (every ~2s). Confidence rises only
/// while the SAME id stays #1 AND clearly leads the runner-up; it drops to 0 the
/// moment the leader changes or the lead collapses — a wrong-but-close #1 (the
/// isnād-ambiguity case, where the true hadith is often #2) never reaches full,
/// so it won't auto-open the wrong one. Pure logic — no UI, host-testable.
class SearchConfidence {
  // The #1 must beat #2 by this ratio to count as a "clear" lead. Deliberately
  // high: on a real device an unambiguous match leads ~1.5–2.3×, while close/
  // ambiguous fields sit ~1.0–1.2× — we only auto-open the former.
  static const double _clearRatio = 1.5;
  // Consecutive clear-lead probes before the ring is full (auto-open).
  static const int _needStreak = 2;

  String? _leaderId;
  int _streak = 0;

  String? get leaderId => _leaderId;

  /// Feed the ranked (id, score) list from the latest search. Returns the ring
  /// fill 0..1 and, when full, the id to auto-open (else null).
  ({double confidence, String? openId}) update(List<({String id, double score})> ranked) {
    if (ranked.isEmpty) {
      _leaderId = null;
      _streak = 0;
      return (confidence: 0, openId: null);
    }
    final top = ranked.first;
    final clear = ranked.length < 2 || top.score >= ranked[1].score * _clearRatio;
    if (clear && top.id == _leaderId) {
      _streak++;
    } else if (clear) {
      _leaderId = top.id;
      _streak = 1;
    } else {
      _streak = 0; // no clear leader — the field is still ambiguous
    }
    final confidence = (_streak / _needStreak).clamp(0.0, 1.0);
    final openId = _streak >= _needStreak ? _leaderId : null;
    return (confidence: confidence, openId: openId);
  }

  void reset() {
    _leaderId = null;
    _streak = 0;
  }
}
