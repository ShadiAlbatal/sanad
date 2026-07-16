import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/quran_repository.dart';
import '../theme/app_theme.dart';

/// Opens the surah index. [onSelect] receives the tapped surah's start page.
Future<void> showSurahList(
  BuildContext context, {
  required void Function(int startPage) onSelect,
}) async {
  final repo = context.read<QuranRepository>();
  final chapters = await repo.chapters();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.92,
      builder: (_, sc) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Surahs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: chapters.length,
              itemBuilder: (ctx, i) {
                final c = chapters[i];
                return ListTile(
                  leading: _SurahBadge(number: c.id),
                  title: Text(c.nameSimple,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${c.translated} · ${c.versesCount} verses'),
                  trailing: Text(c.nameArabic,
                      style: const TextStyle(
                          fontFamily: 'UthmanicHafs', fontSize: 20)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelect(c.startPage);
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _SurahBadge extends StatelessWidget {
  final int number;
  const _SurahBadge({required this.number});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.gold, width: 1.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Text('$number',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
