import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/search/text_search.dart';
import 'package:sanad/widgets/highlighted_arabic.dart';
import 'package:sanad/widgets/search_list_scaffold.dart';

/// The typed-search UX end to end, without the heavy corpus/provider stack: a
/// [TextSearch] index drives the shared [SearchListScaffold] so typing filters
/// the list to ranked hits, each rendering the matched words highlighted; clearing
/// the query returns the full browse list. Also pins that [HighlightedArabic] bolds
/// exactly the matched words and leaves the rest plain.
void main() {
  const docs = [
    TextSearchDoc('a', 'اللهم رب هذه الدعوة التامة والصلاة القائمة'),
    TextSearchDoc('b', 'سبحان الله وبحمده سبحان الله العظيم'),
    TextSearchDoc('c', 'اللهم أنت ربي لا إله إلا أنت خلقتني'),
  ];

  Set<String> boldTexts(WidgetTester tester, Finder card) {
    final rich = tester.widget<RichText>(
        find.descendant(of: card, matching: find.byType(RichText)));
    final out = <String>{};
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text != null &&
          span.text!.trim().isNotEmpty &&
          span.style?.fontWeight == FontWeight.w700) {
        out.add(span.text!);
      }
      return true;
    });
    return out;
  }

  testWidgets('HighlightedArabic bolds only the matched words', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: HighlightedArabic(
            text: 'اللهم رب هذه الدعوة',
            matched: searchWords('الدعوة').toSet(),
            highlight: const Color(0xFF9B22C3),
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ),
    ));
    expect(boldTexts(tester, find.byType(HighlightedArabic)), {'الدعوة'});
  });

  testWidgets('no matched words → plain Text, nothing bold', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HighlightedArabic(
          text: 'اللهم رب هذه الدعوة',
          matched: const {},
          highlight: const Color(0xFF9B22C3),
          style: const TextStyle(fontSize: 20),
        ),
      ),
    ));
    expect(find.text('اللهم رب هذه الدعوة'), findsOneWidget); // plain Text, not Text.rich
    expect(boldTexts(tester, find.byType(HighlightedArabic)), isEmpty);
  });

  testWidgets('typing filters the list to ranked hits + highlights the query',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Harness(docs)));
    // Idle: the whole corpus browses.
    expect(find.byType(HighlightedArabic), findsNWidgets(3));

    await tester.enterText(find.byType(TextField), 'الدعوة القائمة');
    await tester.pump(const Duration(milliseconds: 300)); // clear the debounce

    // Only doc 'a' survives, with its two query words bolded.
    final cards = find.byType(HighlightedArabic);
    expect(cards, findsOneWidget);
    // Bold spans carry the ORIGINAL display tokens (highlighted in place).
    expect(boldTexts(tester, cards), {'الدعوة', 'القائمة'});

    // Clearing the query restores the full browse list.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HighlightedArabic), findsNWidgets(3));
  });

  testWidgets('a query with no matches shows the empty state, list stays reachable',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Harness(docs)));
    await tester.enterText(find.byType(TextField), 'زقاق');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HighlightedArabic), findsNothing);
    expect(find.text('No matches'), findsOneWidget);
  });
}

/// A minimal stand-in for the Dua/Hadith screens: the same TextSearch → filtered
/// list → highlighted rows wiring, over an in-memory corpus (no assets/providers).
class _Harness extends StatefulWidget {
  final List<TextSearchDoc> docs;
  const _Harness(this.docs);
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final TextSearch _search = TextSearch(widget.docs);
  final _controller = TextEditingController();
  String _query = '';
  List<TextSearchHit> _results = const [];

  void _onChanged(String q) {
    setState(() {
      _query = q.trim();
      _results = _query.isEmpty ? const [] : _search.search(_query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    final byId = {for (final d in widget.docs) d.id: d.text};

    final int count;
    final IndexedWidgetBuilder builder;
    if (searching) {
      count = _results.length;
      builder = (_, i) => HighlightedArabic(
            text: byId[_results[i].id]!,
            matched: _results[i].matchedWords,
            highlight: const Color(0xFF9B22C3),
            style: const TextStyle(fontSize: 20),
          );
    } else {
      count = widget.docs.length;
      builder = (_, i) => HighlightedArabic(
            text: widget.docs[i].text,
            matched: const {},
            highlight: const Color(0xFF9B22C3),
            style: const TextStyle(fontSize: 20),
          );
    }

    return SearchListScaffold(
      title: 'T',
      subtitle: 'S',
      itemCount: count,
      itemBuilder: builder,
      emptyState: searching ? const Center(child: Text('No matches')) : null,
      listening: false,
      starting: false,
      level: 0,
      heard: '',
      idlePrompt: 'idle',
      hearingLabel: 'h',
      onMicTap: () {},
      searchController: _controller,
      onSearchChanged: _onChanged,
    );
  }
}
