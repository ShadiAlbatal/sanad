import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A thin single-line strip in the recitation footers showing the most-recent
/// decoded phonemes — the raw Arabic-script units the model just "heard". Lets
/// the reciter compare what they said against what the tracker perceived (and
/// demystifies false mistakes). Shown only while a session is active; the footer
/// rebuilds each mic chunk, so it updates live. Display-only telemetry — it
/// never drives matching.
class HeardTicker extends StatelessWidget {
  final String heard;
  const HeardTicker({super.key, required this.heard});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final ink = dark ? AppColors.nightInk : AppColors.ink;
    final empty = heard.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.hearing_rounded, size: 15, color: soft),
          const SizedBox(width: 7),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                empty ? '…' : heard,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'UthmanicHafs',
                  fontSize: 17,
                  color: empty ? soft.withValues(alpha: 0.55) : ink.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
