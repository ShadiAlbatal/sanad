import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The circular record/stop mic control shared by the Quran, du'a-reader and
/// du'a-finder footers. Pure/stateless (active/starting flags + labels + a tap
/// callback) so the three footers no longer carry byte-identical private
/// copies, and it is host-testable without any provider.
class MicToggleButton extends StatelessWidget {
  final bool active;
  final bool starting;
  final VoidCallback onTap;
  final String idleLabel;
  final String activeLabel;
  final String startingLabel;
  const MicToggleButton({
    super.key,
    required this.active,
    required this.starting,
    required this.onTap,
    this.idleLabel = 'Start recitation',
    this.activeLabel = 'Stop recitation, recording',
    this.startingLabel = 'Starting recitation',
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFE23B3B) : context.accent;
    return Semantics(
      button: true,
      toggled: active,
      label: starting ? startingLabel : (active ? activeLabel : idleLabel),
      child: GestureDetector(
        onTap: starting ? null : onTap,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: ExcludeSemantics(
            child: starting
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Icon(active ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white, size: active ? 28 : 26),
          ),
        ),
      ),
    );
  }
}
