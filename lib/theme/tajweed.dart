import 'package:flutter/material.dart';

/// One coloured run of letters produced from the tajweed HTML of a word.
class TajweedSpan {
  final String text;
  final String? rule; // null = default ink colour
  const TajweedSpan(this.text, this.rule);
}

/// Canonical quran.com / KFGQPC tajweed rule → colour map.
/// Keys match the `class=` names actually emitted in assets/mushaf/*.json's
/// "tj" field (verified against 50 pages) — NOT the older
/// qalqalah/idgham_with_ghunnah/madda_obligatory spellings, which never
/// matched anything and silently rendered as plain ink. Colour values for
/// madda_normal, madda_obligatory_*, qalaqah, ghunnah, idgham_ghunnah,
/// idgham_shafawi and iqlab were sampled directly from Tarteel screenshots
/// (page 232 Hud 11:89, page 582/585/588 Juz 30) — laam_shamsiyah/ham_wasl/
/// slnt confirmed as plain/unhighlighted, matching the existing muted grey.
/// ikhafa, idgham_wo_ghunnah, madda_necessary remain best-effort: sampled
/// examples were either ambiguous (ikhafa showed no colour on the one clean
/// example checked) or the crop missed the target word.
class Tajweed {
  static const _base = <String, Color>{
    'ham_wasl': Color(0xFFAAAAAA),
    'laam_shamsiyah': Color(0xFFAAAAAA),
    'slnt': Color(0xFFAAAAAA),
    'madda_normal': Color(0xFF1C8FC0),
    'madda_permissible': Color(0xFF1E9ED1),
    'madda_necessary': Color(0xFF000EAD),
    'madda_obligatory_mottasel': Color(0xFF0F86C0),
    'madda_obligatory_monfasel': Color(0xFF0F86C0),
    'qalaqah': Color(0xFF29B6E8),
    'ikhafa': Color(0xFFB01E96),
    'ikhafa_shafawi': Color(0xFFE91E8C),
    'idgham_shafawi': Color(0xFF1C8FC0),
    'iqlab': Color(0xFF1C8FC0),
    'idgham_ghunnah': Color(0xFFE91E8C),
    'idgham_wo_ghunnah': Color(0xFF169200),
    'idgham_mutajanisayn': Color(0xFFA1A1A1),
    'idgham_mutaqaribayn': Color(0xFFA1A1A1),
    'ghunnah': Color(0xFF12BD71),
  };

  // On light paper the pale greys/blues need to sit a little darker.
  static const _lightOverrides = <String, Color>{
    'ham_wasl': Color(0xFF8A8A8A),
    'laam_shamsiyah': Color(0xFF8A8A8A),
    'slnt': Color(0xFF8A8A8A),
    'idgham_mutajanisayn': Color(0xFF8A8A8A),
    'idgham_mutaqaribayn': Color(0xFF8A8A8A),
    'madda_normal': Color(0xFF106D96),
    'madda_obligatory_mottasel': Color(0xFF0A5E8A),
    'madda_obligatory_monfasel': Color(0xFF0A5E8A),
    'idgham_shafawi': Color(0xFF106D96),
    'iqlab': Color(0xFF106D96),
    'ghunnah': Color(0xFF0D9A5B),
  };

  static Color? colorFor(String? rule, bool dark) {
    if (rule == null) return null;
    if (!dark) {
      final o = _lightOverrides[rule];
      if (o != null) return o;
    }
    return _base[rule];
  }

  static final _tagRe =
      RegExp(r'<\s*(rule|tajweed|span)\s+class=([a-zA-Z0-9_\-]+)\s*>|<\s*/\s*(rule|tajweed|span)\s*>');

  /// Parse quran.com tajweed HTML (`ذ<rule class=madda_normal>ٰ</rule>لِكَ`)
  /// into coloured runs. Non-colour wrapper classes (custom-*, end) inherit the
  /// nearest colouring ancestor.
  static List<TajweedSpan> parse(String html) {
    if (!html.contains('<')) return [TajweedSpan(html, null)];
    final spans = <TajweedSpan>[];
    final stack = <String?>[]; // colour rule at each open tag (null if none)
    var i = 0;
    for (final m in _tagRe.allMatches(html)) {
      if (m.start > i) {
        final text = html.substring(i, m.start);
        if (text.isNotEmpty) {
          spans.add(TajweedSpan(text, _topColour(stack)));
        }
      }
      if (m.group(1) != null) {
        final cls = m.group(2)!;
        stack.add(_base.containsKey(cls) ? cls : null);
      } else if (stack.isNotEmpty) {
        stack.removeLast();
      }
      i = m.end;
    }
    if (i < html.length) {
      final text = html.substring(i);
      if (text.isNotEmpty) spans.add(TajweedSpan(text, _topColour(stack)));
    }
    return spans.isEmpty ? [TajweedSpan(html, null)] : spans;
  }

  static String? _topColour(List<String?> stack) {
    for (var k = stack.length - 1; k >= 0; k--) {
      if (stack[k] != null) return stack[k];
    }
    return null;
  }
}
