import 'package:flutter/material.dart';

/// Small pill-shaped icon button used for the hide/reveal step chevrons in
/// both the Quran and du'a reader footers. Pure/stateless (icon, colors, a
/// screen-reader label and a tap callback) so it is shared instead of
/// duplicated per footer, and is host-testable without any provider.
class ChevronButton extends StatelessWidget {
  final IconData icon;
  final Color fg;
  final bool dark;
  final String semanticLabel;
  final VoidCallback onTap;
  const ChevronButton({
    super.key,
    required this.icon,
    required this.fg,
    required this.dark,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = (dark ? Colors.white : Colors.black).withValues(alpha: 0.06);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ExcludeSemantics(child: Icon(icon, size: 22, color: fg)),
          ),
        ),
      ),
    );
  }
}
