import 'package:flutter/material.dart';

/// One coloured run of letters produced from the tajweed HTML of a word.
class TajweedSpan {
  final String text;
  final String? rule; // null = default ink colour
  const TajweedSpan(this.text, this.rule);
}

/// Canonical quran.com / KFGQPC tajweed rule → colour map.
/// Same hues the printed tajweed mushaf uses; a few greys are lightened for
/// the dark theme and darkened for the light (paper) theme.
class Tajweed {
  static const _base = <String, Color>{
    'ham_wasl': Color(0xFFAAAAAA),
    'laam_shamsiyah': Color(0xFFAAAAAA),
    'slnt': Color(0xFFAAAAAA),
    'madda_normal': Color(0xFF537FFF),
    'madda_permissible': Color(0xFF4050FF),
    'madda_necessary': Color(0xFF000EAD),
    'madda_obligatory': Color(0xFF2144C1),
    'qalqalah': Color(0xFFDD0008),
    'ikhafa': Color(0xFF9400A8),
    'ikhafa_shafawi': Color(0xFFD500B7),
    'idgham_shafawi': Color(0xFF58B800),
    'iqlab': Color(0xFF26BFFD),
    'idgham_with_ghunnah': Color(0xFF169777),
    'idgham_wo_ghunnah': Color(0xFF169200),
    'idgham_mutajanisayn': Color(0xFFA1A1A1),
    'idgham_mutaqaribayn': Color(0xFFA1A1A1),
    'ghunnah': Color(0xFFFF7E1E),
  };

  // On light paper the pale greys/blues need to sit a little darker.
  static const _lightOverrides = <String, Color>{
    'ham_wasl': Color(0xFF8A8A8A),
    'laam_shamsiyah': Color(0xFF8A8A8A),
    'slnt': Color(0xFF8A8A8A),
    'idgham_mutajanisayn': Color(0xFF8A8A8A),
    'idgham_mutaqaribayn': Color(0xFF8A8A8A),
    'madda_normal': Color(0xFF2D5BFF),
    'iqlab': Color(0xFF109FDB),
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
