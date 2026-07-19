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
  final String subtitle;

  // Content
  final bool loading; // show a centered spinner instead of the list
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? emptyState; // shown when !loading && itemCount == 0
  final ScrollController? scrollController; // caller resets this on a new recording
  final String? countLabel; // e.g. "14 results" / "259 duas" — shown under the subtitle
  final Widget? aboveList; // e.g. a "Recent" history row — shown only while idle/browsing

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
    required this.subtitle,
    this.loading = false,
    required this.itemCount,
    required this.itemBuilder,
    this.emptyState,
    this.scrollController,
    this.countLabel,
    this.aboveList,
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
              child: Text(title,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(subtitle,
                          style: TextStyle(color: soft, fontSize: 13.5))),
                  if (countLabel != null)
                    Text(countLabel!,
                        style: TextStyle(
                            color: soft, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            ?aboveList,
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

/// A horizontal "Recent" row of quick-retrieve chips shown above the list
/// while idle/browsing — tap one to reopen it without re-reciting or
/// re-typing. Shared across the three list tabs; only the entry shape and
/// what a tap does differ, supplied by the caller.
class HistoryRow extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final String Function(Map<String, dynamic> entry) labelOf;
  final void Function(Map<String, dynamic> entry) onTap;
  const HistoryRow({super.key, required this.entries, required this.labelOf, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chipColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = entries[i];
          return GestureDetector(
            onTap: () => onTap(e),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(labelOf(e),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 13, color: soft, fontWeight: FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }
}
