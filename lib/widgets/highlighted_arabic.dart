import 'package:flutter/material.dart';
import '../services/search/text_search.dart' show searchWords;

/// Renders Arabic display text with the search-matched words emphasised (bold +
/// accent), splitting on whitespace and normalising each token the SAME way the
/// index does ([searchWords]) so a matched word lights up regardless of its
/// diacritics. With no [matched] words it is a plain [Text] — the browse/voice
/// cards pass an empty set and get the untouched rendering.
class HighlightedArabic extends StatelessWidget {
  final String text;
  final Set<String> matched; // normalized query words that hit this doc
  final TextStyle style;
  final Color highlight;
  final int maxLines;

  const HighlightedArabic({
    super.key,
    required this.text,
    required this.matched,
    required this.style,
    required this.highlight,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (matched.isEmpty) {
      return Text(
        text,
        textAlign: TextAlign.right,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final tokens = text.split(RegExp(r'\s+'));
    final hi = style.copyWith(color: highlight, fontWeight: FontWeight.w700);
    final spans = <TextSpan>[];
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      final norm = searchWords(tokens[i]);
      final isMatch = norm.isNotEmpty && matched.contains(norm.first);
      spans.add(TextSpan(text: tokens[i], style: isMatch ? hi : null));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: TextAlign.right,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
