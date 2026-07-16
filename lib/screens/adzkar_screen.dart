import 'package:flutter/material.dart';
import '../data/adhkar_data.dart';
import '../theme/app_theme.dart';

class AdzkarScreen extends StatefulWidget {
  // pushed: rendered as its own route (Scaffold + back button) vs. inline in the
  // tab's IndexedStack. Explicit, not inferred from canPop() — the tab instance
  // must never flip to pushed if the shell is ever mounted behind a route.
  final bool pushed;
  final String? initialCategory;
  const AdzkarScreen({super.key, this.pushed = false, this.initialCategory});

  @override
  State<AdzkarScreen> createState() => _AdzkarScreenState();
}

class _AdzkarScreenState extends State<AdzkarScreen> {
  late int _cat = _initialCat();
  final Map<String, int> _counts = {};

  int _initialCat() {
    final c = widget.initialCategory;
    if (c == null) return 0;
    final i = adhkarCategories.indexWhere((cat) => cat.title == c);
    return i < 0 ? 0 : i;
  }

  void _tap(Dhikr d) {
    setState(() {
      final v = (_counts[d.id] ?? 0) + 1;
      _counts[d.id] = v > d.repeat ? 1 : v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final cat = adhkarCategories[_cat];
    final pushed = widget.pushed;

    final body = SafeArea(
      top: !pushed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!pushed)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('Adhkar',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: adhkarCategories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final selected = i == _cat;
                return ChoiceChip(
                  label: Text(adhkarCategories[i].title),
                  selected: selected,
                  onSelected: (_) => setState(() => _cat = i),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(cat.subtitle, style: TextStyle(color: soft)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: cat.items.length,
              itemBuilder: (_, i) => _DhikrCard(
                dhikr: cat.items[i],
                count: _counts[cat.items[i].id] ?? 0,
                onTap: () => _tap(cat.items[i]),
              ),
            ),
          ),
        ],
      ),
    );

    if (!pushed) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Adhkar')),
      body: body,
    );
  }
}

class _DhikrCard extends StatelessWidget {
  final Dhikr dhikr;
  final int count;
  final VoidCallback onTap;
  const _DhikrCard(
      {required this.dhikr, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final done = count >= dhikr.repeat;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: done
                ? context.accent.withValues(alpha: 0.7)
                : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                dhikr.arabic,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFamily: 'UthmanicHafs',
                  fontSize: 24,
                  height: 1.9,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(dhikr.translit,
                style: TextStyle(
                    fontStyle: FontStyle.italic, color: soft, fontSize: 13)),
            const SizedBox(height: 4),
            Text(dhikr.translation,
                style: TextStyle(color: soft, fontSize: 13.5)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Repeat ×${dhikr.repeat}',
                    style: TextStyle(
                        color: soft,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: done
                        ? context.accent
                        : context.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    done ? 'Done ✓' : '$count / ${dhikr.repeat}',
                    style: TextStyle(
                      color: done ? Colors.white : context.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
