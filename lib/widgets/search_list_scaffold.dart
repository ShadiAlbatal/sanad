import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'heard_ticker.dart';
import 'hearing_indicator.dart';
import 'mic_toggle_button.dart';

/// The unified "content list + footer" shell every content tab (Dua, Hadith, and
/// eventually Quran) renders through, so they look and behave identically. It is
/// two parts:
///
///  - a scrollable content area: a header (title + subtitle) over a lazy
///    [ListView.builder] the caller drives via [itemCount] / [itemBuilder]
///    (or a spinner while [loading], or [emptyState] when there is nothing);
///  - a fixed bottom FOOTER composed of the shared recitation controls
///    ([MicToggleButton] + [HearingIndicator] + [HeardTicker]) and a text search
///    [TextField]. The footer is byte-identical between tabs; only the data and
///    which finder state drives the mic differ.
///
/// The mic side is wired live (same proven pattern as the old per-tab footers).
/// The search [TextField] is a wired SHELL only: [onSearchChanged] fires but
/// typed-search behavior (match → open / candidates-with-highlight) is a LATER
/// piece — callers pass a stub for now.
class SearchListScaffold extends StatelessWidget {
  final String title;

  // Content
  final bool loading; // show a centered spinner instead of the list
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? emptyState; // shown when !loading && itemCount == 0
  final ScrollController? scrollController; // caller resets this on a new recording
  final String? countLabel; // e.g. "14 results" / "259 duas" — shown beside the title

  // The header's overflow menu (History / Bookmarks) — identical shape on
  // every tab, only the entries + what a tap does differ. Null hides the menu
  // (e.g. while a screen's history/bookmarks haven't loaded yet).
  final List<Map<String, dynamic>>? history;
  final List<Map<String, dynamic>>? bookmarks;
  final String Function(Map<String, dynamic> entry)? labelOf;
  final void Function(Map<String, dynamic> entry)? onOpenEntry;
  final void Function(Map<String, dynamic> entry)? onRemoveBookmark;

  // Footer — mic (live)
  final bool listening;
  final bool starting;
  final double level;
  final String heard; // decoded-phoneme ticker text; '' when idle
  final String hearingLabel; // status text while listening ("Hearing: X?")
  final VoidCallback onMicTap;
  final String micIdleLabel; // mic-button semantics
  final String micActiveLabel;
  final String micStartingLabel;

  // Footer — search (shell; behavior deferred to piece 2)
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchHint;
  final VoidCallback? onClear; // the field's X button — clears text AND results

  const SearchListScaffold({
    super.key,
    required this.title,
    this.loading = false,
    required this.itemCount,
    required this.itemBuilder,
    this.emptyState,
    this.scrollController,
    this.countLabel,
    this.history,
    this.bookmarks,
    this.labelOf,
    this.onOpenEntry,
    this.onRemoveBookmark,
    required this.listening,
    required this.starting,
    required this.level,
    required this.heard,
    required this.hearingLabel,
    required this.onMicTap,
    this.micIdleLabel = 'Recite to find',
    this.micActiveLabel = 'Stop listening',
    this.micStartingLabel = 'Starting',
    this.searchController,
    this.onSearchChanged,
    this.searchHint = 'Search',
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    final Widget content;
    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (itemCount == 0 && emptyState != null) {
      content = emptyState!;
    } else {
      content = ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  ),
                  if (countLabel != null) ...[
                    Text(countLabel!,
                        style: TextStyle(
                            color: soft, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                  ],
                  if (history != null && bookmarks != null && labelOf != null && onOpenEntry != null)
                    _HeaderMenu(
                      history: history!,
                      bookmarks: bookmarks!,
                      labelOf: labelOf!,
                      onOpenEntry: onOpenEntry!,
                      onRemoveBookmark: onRemoveBookmark,
                    ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: _Footer(
        listening: listening,
        starting: starting,
        level: level,
        heard: heard,
        hearingLabel: hearingLabel,
        onMicTap: onMicTap,
        micIdleLabel: micIdleLabel,
        micActiveLabel: micActiveLabel,
        micStartingLabel: micStartingLabel,
        searchController: searchController,
        onSearchChanged: onSearchChanged,
        searchHint: searchHint,
        onClear: onClear,
      ),
    );
  }
}

/// The shared footer bar: mic controls (identical to the old per-tab footers) plus
/// the search field. Kept private so the layout can never drift between tabs.
class _Footer extends StatelessWidget {
  final bool listening;
  final bool starting;
  final double level;
  final String heard;
  final String hearingLabel;
  final VoidCallback onMicTap;
  final String micIdleLabel;
  final String micActiveLabel;
  final String micStartingLabel;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchHint;
  final VoidCallback? onClear;

  const _Footer({
    required this.listening,
    required this.starting,
    required this.level,
    required this.heard,
    required this.hearingLabel,
    required this.onMicTap,
    required this.micIdleLabel,
    required this.micActiveLabel,
    required this.micStartingLabel,
    required this.searchController,
    required this.onSearchChanged,
    required this.searchHint,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final mq = MediaQuery.of(context);
    // The footer lives in [Scaffold.bottomNavigationBar], which resizeToAvoidBottom-
    // Inset does NOT lift. Pad the content above whatever is at the screen bottom:
    // the soft keyboard when it's up (viewInsets, which already covers the system
    // nav bar), otherwise the Android system nav bar itself (viewPadding). Under
    // Android edge-to-edge the bar draws behind the system nav bar, so the COLOR
    // must fill down to the physical edge while the CONTENT stays inset — hence the
    // padding lives inside the colored Container, not an outer SafeArea (which
    // would leave the nav-bar strip uncolored and could clip the controls).
    final keyboard = mq.viewInsets.bottom;
    final bottomInset = keyboard > 0 ? keyboard : mq.viewPadding.bottom;

    return Container(
      color: barColor,
      padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (listening) ...[
            HeardTicker(heard: heard),
            const SizedBox(height: 4),
            HearingIndicator(
              active: true,
              level: level,
              tracking: false,
              label: hearingLabel,
            ),
            const SizedBox(height: 8),
          ],
          // Search field on the left (thumb rests on the mic to its right — the
          // one-handed reach every tab shares).
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _SearchField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  hint: searchHint,
                  onClear: onClear,
                ),
              ),
              const SizedBox(width: 10),
              MicToggleButton(
                active: listening,
                starting: starting,
                onTap: onMicTap,
                idleLabel: micIdleLabel,
                activeLabel: micActiveLabel,
                startingLabel: micStartingLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The footer's text search bar. RTL (queries — typed or from voice — are
/// Arabic), with an X that appears once there's text to clear (typed or voice).
class _SearchField extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hint;
  final VoidCallback? onClear;
  const _SearchField(
      {required this.controller, required this.onChanged, required this.hint, this.onClear});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(_SearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onTextChanged);
      widget.controller?.addListener(_onTextChanged);
    }
  }

  // Rebuild just to show/hide the clear button as text is typed or cleared
  // programmatically (e.g. a new recording clearing the field).
  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller?.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? AppColors.night : AppColors.paper;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final ink = dark ? AppColors.nightInk : AppColors.ink;
    final hasText = widget.controller?.text.isNotEmpty ?? false;

    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      textDirection: TextDirection.rtl,
      style: TextStyle(color: ink, fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: fill,
        hintText: widget.hint,
        hintStyle: TextStyle(color: soft, fontSize: 15),
        suffixIcon: hasText
            ? IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: soft),
                tooltip: 'Clear',
                onPressed: widget.onClear,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// The header's overflow menu — identical on every list tab: a 3-dot button
/// that opens "History" and "Bookmarks", each showing that tab's own entries
/// in a bottom sheet. Replaces the old always-visible inline "Recent" row —
/// same underlying per-tab prefs, just tucked behind a tap instead of always
/// taking header space.
class _HeaderMenu extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> bookmarks;
  final String Function(Map<String, dynamic> entry) labelOf;
  final void Function(Map<String, dynamic> entry) onOpenEntry;
  final void Function(Map<String, dynamic> entry)? onRemoveBookmark;
  const _HeaderMenu({
    required this.history,
    required this.bookmarks,
    required this.labelOf,
    required this.onOpenEntry,
    required this.onRemoveBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_HeaderMenuAction>(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'History & bookmarks',
      onSelected: (a) {
        switch (a) {
          case _HeaderMenuAction.history:
            _showEntrySheet(context,
                title: 'History', entries: history, labelOf: labelOf, onTap: onOpenEntry);
          case _HeaderMenuAction.bookmarks:
            _showEntrySheet(context,
                title: 'Bookmarks',
                entries: bookmarks,
                labelOf: labelOf,
                onTap: onOpenEntry,
                onRemove: onRemoveBookmark);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _HeaderMenuAction.history,
          child: Row(children: [
            Icon(Icons.history_rounded, size: 20),
            SizedBox(width: 12),
            Text('History'),
          ]),
        ),
        PopupMenuItem(
          value: _HeaderMenuAction.bookmarks,
          child: Row(children: [
            Icon(Icons.bookmark_rounded, size: 20),
            SizedBox(width: 12),
            Text('Bookmarks'),
          ]),
        ),
      ],
    );
  }
}

enum _HeaderMenuAction { history, bookmarks }

void _showEntrySheet(
  BuildContext context, {
  required String title,
  required List<Map<String, dynamic>> entries,
  required String Function(Map<String, dynamic> entry) labelOf,
  required void Function(Map<String, dynamic> entry) onTap,
  void Function(Map<String, dynamic> entry)? onRemove,
}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final dark = Theme.of(sheetContext).brightness == Brightness.dark;
      final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Text(
                    title == 'History' ? 'Nothing opened yet' : 'Nothing bookmarked yet',
                    style: TextStyle(color: soft, fontSize: 14)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return ListTile(
                      title: Text(labelOf(e),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: onRemove == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: 'Remove bookmark',
                              // Closes the sheet rather than trying to patch it in
                              // place — re-open the menu to see the updated list.
                              onPressed: () {
                                onRemove(e);
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onTap(e);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}
