import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Compact live "is it hearing / understanding me?" readout for the recitation
/// footers: a tiny equalizer whose bars ride the mic [level] plus a status word
/// that walks waiting → Listening → Following as the tracker locks on. The
/// footers rebuild every mic chunk (~80ms), so the bars animate off [level] with
/// no controller of its own.
///
/// - [active] false → renders nothing.
/// - [tracking] true → the pipeline knows where you are (accent).
/// - otherwise the label reflects whether the mic is hearing your voice yet.
/// - [label] overrides the derived status text (used by the du'a finder to show
///   "Matching…" / "Hearing: <title>?"); the colour still follows the state.
///
/// End-aligned and internally shrink-safe (the text ellipsizes), so it can sit
/// in an `Expanded` slot in a crowded footer without overflowing.
class HearingIndicator extends StatelessWidget {
  final bool active;
  final double level;
  final bool tracking;
  final String? label;
  const HearingIndicator({
    super.key,
    required this.active,
    required this.level,
    required this.tracking,
    this.label,
  });

  static const double _hearingThreshold = 0.05;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final hearing = level >= _hearingThreshold;

    final Color color;
    final String text;
    if (tracking) {
      color = context.accent;
      text = label ?? 'Following';
    } else if (hearing) {
      color = soft;
      text = label ?? 'Listening…';
    } else {
      color = soft.withValues(alpha: 0.55);
      text = label ?? 'waiting…';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _Equalizer(level: level, color: color, live: hearing || tracking),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Equalizer extends StatelessWidget {
  final double level;
  final Color color;
  final bool live;
  const _Equalizer({required this.level, required this.color, required this.live});

  // Per-bar sensitivity so the four bars don't move in lockstep — an equalizer,
  // not one meter.
  static const List<double> _factors = [0.55, 1.0, 0.7, 0.9];
  static const double _minH = 4;
  static const double _maxH = 15;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _factors.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 3,
            height: _minH + (_maxH - _minH) * (level * _factors[i]).clamp(0.0, 1.0),
            decoration: BoxDecoration(
              color: color.withValues(alpha: live ? 1.0 : 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}
