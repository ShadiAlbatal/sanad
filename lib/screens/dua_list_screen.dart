import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/duas.dart';
import '../state/dua_finder_state.dart';
import '../theme/app_theme.dart';
import 'dua_reader_screen.dart';

/// The Azkar tab's root: the list of du'ās & adhkār. Tapping a card opens its
/// reader. The "recite to open" control lives in the bottom footer
/// (DuaFinderFooter, provided at root); this screen only listens for the finder's
/// pick and opens that du'a's reader, already following along.
class DuaListScreen extends StatefulWidget {
  const DuaListScreen({super.key});

  @override
  State<DuaListScreen> createState() => _DuaListScreenState();
}

class _DuaListScreenState extends State<DuaListScreen> {
  DuaFinderState? _finder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final finder = context.read<DuaFinderState>();
    if (!identical(finder, _finder)) {
      _finder?.removeListener(_onFinder);
      _finder = finder;
      _finder!.addListener(_onFinder);
    }
  }

  void _onFinder() {
    final finder = _finder;
    final id = finder?.identifiedDuaId;
    if (finder == null || id == null) return;
    final dua = duas.firstWhere((d) => d.id == id);
    finder.clearIdentified(); // consume the pick so we open exactly once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DuaReaderScreen(dua: dua, autoStart: true)),
      );
    });
  }

  @override
  void dispose() {
    _finder?.removeListener(_onFinder);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
            child: Text('Duas & Adhkār',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Recite to open, or tap a du\'ā — words light up as you read',
                style: TextStyle(color: soft, fontSize: 13.5)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
              itemCount: duas.length,
              itemBuilder: (_, i) => _DuaCard(dua: duas[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DuaCard extends StatelessWidget {
  final Dua dua;
  const _DuaCard({required this.dua});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DuaReaderScreen(dua: dua))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dark ? AppColors.nightCard : AppColors.paperEdge,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(dua.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.chevron_right_rounded, color: soft),
              ],
            ),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                dua.arabic,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'UthmanicHafs',
                  fontSize: 22,
                  height: 1.9,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(dua.source.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: context.accent,
                )),
          ],
        ),
      ),
    );
  }
}
