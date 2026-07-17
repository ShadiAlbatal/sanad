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

  // Footer — mic (live)
  final bool listening;
  final bool starting;
  final double level;
  final String heard; // decoded-phoneme ticker text; '' when idle
  final String idlePrompt; // centered status text when not listening
  final String hearingLabel; // status text while listening ("Hearing: X?")
  final VoidCallback onMicTap;
  final String micIdleLabel; // mic-button semantics
  final String micActiveLabel;
  final String micStartingLabel;

  // Footer — search (shell; behavior deferred to piece 2)
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchHint;

  const SearchListScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    this.loading = false,
    required this.itemCount,
    required this.itemBuilder,
    this.emptyState,
    required this.listening,
    required this.starting,
    required this.level,
    required this.heard,
    required this.idlePrompt,
    required this.hearingLabel,
    required this.onMicTap,
    this.micIdleLabel = 'Recite to find',
    this.micActiveLabel = 'Stop listening',
    this.micStartingLabel = 'Starting',
    this.searchController,
    this.onSearchChanged,
    this.searchHint = 'Search',
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
              child: Text(subtitle,
                  style: TextStyle(color: soft, fontSize: 13.5)),
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
        idlePrompt: idlePrompt,
        hearingLabel: hearingLabel,
        onMicTap: onMicTap,
        micIdleLabel: micIdleLabel,
        micActiveLabel: micActiveLabel,
        micStartingLabel: micStartingLabel,
        searchController: searchController,
        onSearchChanged: onSearchChanged,
        searchHint: searchHint,
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
  final String idlePrompt;
  final String hearingLabel;
  final VoidCallback onMicTap;
  final String micIdleLabel;
  final String micActiveLabel;
  final String micStartingLabel;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchHint;

  const _Footer({
    required this.listening,
    required this.starting,
    required this.level,
    required this.heard,
    required this.idlePrompt,
    required this.hearingLabel,
    required this.onMicTap,
    required this.micIdleLabel,
    required this.micActiveLabel,
    required this.micStartingLabel,
    required this.searchController,
    required this.onSearchChanged,
    required this.searchHint,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.nightCard : AppColors.paperEdge;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    // The footer lives in [Scaffold.bottomNavigationBar], which resizeToAvoidBottom-
    // Inset does NOT lift, so pad by the keyboard inset to keep the search field
    // ABOVE the soft keyboard (the bar stays visually in the footer per the design).
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Container(
        color: barColor,
        padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + keyboard),
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
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(idlePrompt,
                    style:
                        TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w500)),
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
      ),
    );
  }
}

/// The footer's text search bar. Wired shell only: [onChanged] fires but nothing
/// consumes it yet (typed search is piece 2).
class _SearchField extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hint;
  const _SearchField({required this.controller, required this.onChanged, required this.hint});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? AppColors.night : AppColors.paper;
    final soft = dark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final ink = dark ? AppColors.nightInk : AppColors.ink;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: ink, fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: fill,
        hintText: hint,
        hintStyle: TextStyle(color: soft, fontSize: 15),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: soft),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
