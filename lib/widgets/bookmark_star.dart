import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The star toggle shown on every list card (Quran surah/verse, du'ā, hadith)
/// so the affordance is pinned identical across tabs instead of copy-pasted.
/// The icon is 20px but the tap target is padded to a comfortable ~40px so a
/// near-miss doesn't fall through to the card's own onTap (open-the-reader).
class BookmarkStar extends StatelessWidget {
  final bool bookmarked;
  final VoidCallback onToggle;
  const BookmarkStar({super.key, required this.bookmarked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    return Semantics(
      button: true,
      label: bookmarked ? 'Remove bookmark' : 'Bookmark',
      child: InkResponse(
        onTap: onToggle,
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            bookmarked ? Icons.star_rounded : Icons.star_border_rounded,
            size: 20,
            color: bookmarked ? context.accent : soft,
          ),
        ),
      ),
    );
  }
}
