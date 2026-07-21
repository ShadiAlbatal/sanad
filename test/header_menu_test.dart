import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/widgets/bookmark_star.dart';
import 'package:sanad/widgets/search_list_scaffold.dart';

/// The header overflow menu is the ONLY route to history and bookmarks now that
/// the inline HistoryRow is gone, and it is gated behind a four-way non-null
/// guard — so nothing rendered it in any test. Pin the whole path here: the gate,
/// both sheets, their empty copy, the tap-to-open pop-then-open ordering, and the
/// remove button. Plus [BookmarkStar], the per-card affordance feeding it.
void main() {
  List<Map<String, dynamic>> entries(List<String> keys) =>
      [for (final k in keys) {'key': k, 'label': 'label-$k'}];

  Widget scaffold({
    List<Map<String, dynamic>> history = const [],
    List<Map<String, dynamic>> bookmarks = const [],
    void Function(Map<String, dynamic>)? onOpenEntry,
    void Function(Map<String, dynamic>)? onRemoveBookmark,
    bool withMenu = true,
  }) =>
      MaterialApp(
        home: SearchListScaffold(
          title: 'T',
          itemCount: 1,
          itemBuilder: (_, _) => const Text('row'),
          listening: false,
          starting: false,
          level: 0,
          heard: '',
          hearingLabel: 'h',
          onMicTap: () {},
          history: withMenu ? history : null,
          bookmarks: withMenu ? bookmarks : null,
          labelOf: withMenu ? (e) => e['label'] as String : null,
          onOpenEntry: withMenu ? (onOpenEntry ?? (_) {}) : null,
          onRemoveBookmark: onRemoveBookmark,
        ),
      );

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('the menu only renders once all four of its inputs are supplied',
      (tester) async {
    await tester.pumpWidget(scaffold(withMenu: false));
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);

    await tester.pumpWidget(scaffold());
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });

  testWidgets('a screen supplying only SOME menu inputs gets no menu, not a crash',
      (tester) async {
    // The guard is an AND for a reason: with history wired but labelOf left off,
    // rendering the menu would dereference a null labelOf the moment a sheet
    // opens. Hiding it is the intended (if silent) degradation.
    await tester.pumpWidget(MaterialApp(
      home: SearchListScaffold(
        title: 'T',
        itemCount: 1,
        itemBuilder: (_, _) => const Text('row'),
        listening: false,
        starting: false,
        level: 0,
        heard: '',
        hearingLabel: 'h',
        onMicTap: () {},
        history: entries(['surah:112']),
        bookmarks: entries(['bukhari:1']),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
  });

  testWidgets('bookmarks sheet lists entries through labelOf', (tester) async {
    await tester.pumpWidget(scaffold(bookmarks: entries(['surah:112', 'ayah:2:255'])));
    await openMenu(tester, 'Bookmarks');
    expect(find.text('label-surah:112'), findsOneWidget);
    expect(find.text('label-ayah:2:255'), findsOneWidget);
  });

  testWidgets('history and bookmarks have their own empty copy', (tester) async {
    await tester.pumpWidget(scaffold());
    await openMenu(tester, 'History');
    expect(find.text('Nothing opened yet'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await tester.pumpAndSettle();

    await openMenu(tester, 'Bookmarks');
    expect(find.text('Nothing bookmarked yet'), findsOneWidget);
  });

  testWidgets('tapping an entry closes the sheet, then opens it', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(scaffold(
      bookmarks: entries(['surah:112']),
      onOpenEntry: (e) => opened.add(e['key'] as String),
    ));
    await openMenu(tester, 'Bookmarks');
    await tester.tap(find.text('label-surah:112'));
    await tester.pumpAndSettle();

    expect(opened, ['surah:112']);
    // The sheet must be gone — it once stayed up over the pushed reader.
    expect(find.text('label-surah:112'), findsNothing);
  });

  testWidgets('the remove button removes that entry and closes the sheet',
      (tester) async {
    final removed = <String>[];
    final opened = <String>[];
    await tester.pumpWidget(scaffold(
      bookmarks: entries(['surah:112', 'bukhari:1']),
      onOpenEntry: (e) => opened.add(e['key'] as String),
      onRemoveBookmark: (e) => removed.add(e['key'] as String),
    ));
    await openMenu(tester, 'Bookmarks');
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    expect(removed, ['surah:112']);
    expect(opened, isEmpty, reason: 'removing must not also open the reader');
    expect(find.text('label-bukhari:1'), findsNothing, reason: 'sheet closed');
  });

  testWidgets('history entries have no remove button', (tester) async {
    await tester.pumpWidget(scaffold(history: entries(['surah:112'])));
    await openMenu(tester, 'History');
    expect(find.text('label-surah:112'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('BookmarkStar shows its state and reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          BookmarkStar(bookmarked: false, onToggle: () => taps++),
          BookmarkStar(bookmarked: true, onToggle: () => taps++),
        ]),
      ),
    ));
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.star_border_rounded));
    await tester.pump();
    expect(taps, 1);
  });
}
