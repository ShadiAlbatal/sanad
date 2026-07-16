# TilawaAi — Handoff (2026-07-16, session 5) — START HERE

## CURRENT STATE (top of session 5, 2026-07-16)
- **Repo is now git-initialized + committed** (`daaf6a9`, branch `master`, initial commit, 1098 files). No
  remote yet — CI (`.github/workflows/ci.yml`) is inert until a GitHub remote is added. `git` identity in use:
  Shadi Albatal (global config — change if you want a different author on this project).
- **`pulls/` and `tool/_cache/` are git-ignored** (pulls = sensitive recitation logs; cache = regenerable).
  `/build/`, `.dart_tool/`, keystores/`key.properties` already ignored. `audio/` + `capture/` ARE committed
  (non-sensitive reference media).
- **Health: 128 tests green, `flutter analyze lib` clean.** The full A-to-Z review (`docs/REVIEW.md`) roadmap
  is DONE except the 2 items that need a phone: (1) ONNX-on-background-isolate, (2) the RecitationSession
  3-state merge — step-by-step device-verified plans for both are the next section.
- **User still owes (external/legal, not code):** create the real release keystore (`android/key.properties`
  from the `.example`); paste the exact ASR-model + KFGQPC-font license text into `lib/util/licenses.dart` /
  `THIRD_PARTY_NOTICES.md`; add a project `LICENSE`; write a privacy policy before any Supabase upload.
- **Analytics = local + opt-in only (Phase A).** Supabase upload (Phase B) is NOT wired; `SupabaseAnalyticsSink`
  exists but is never instantiated. Plan + schema in `docs/ANALYTICS_PLAN.md`.

## DEVICE-VERIFIED PLANS for the 2 deferred items (do these WITH a phone in the loop)
Both were deferred because they touch the live on-device ASR and CANNOT be checked by `flutter test`
(the states hold platform channels; sherpa native code doesn't run host-side). The rule for both: **one
small step, then recite on device and observe — never a big-bang edit.** Keep a fallback switch so you can
ship the current (working) path until the new one is proven on hardware.

### Plan A — ONNX inference on a background isolate (perf: stop the UI-thread stutter)
Today `SherpaAsr.accept()` (sherpa_asr.dart) runs the synchronous FFI decode on the mic-stream callback,
i.e. the root/UI isolate → per-chunk jank during recitation. The recognizer is a live native FFI handle that
CANNOT cross isolates, so it must be created + fed entirely inside a worker isolate.
0. **Baseline** on device: recite a page, note smoothness/stutter + follow accuracy. Before-picture.
1. **Worker skeleton:** one long-lived isolate PER SESSION (never per chunk). SendPort handshake. The worker
   does today's `SherpaAsr.create()` work itself (stage model.int8.onnx via path_provider — CONFIRM that path
   works from an isolate on device — create OnlineRecognizer + stream).
2. **Message protocol:** main→worker `{pcm: Int16List}` / `{finish}` / `{dispose}`; worker→main
   `{ready}` / `{tokens: List<String>}` (cumulative) / `{error}`.
3. **Wire the feed:** `MicSource.onPcm` (main) currently calls `asr.accept(pcm)` inline — change to send PCM
   to the worker; worker decodes + posts cumulative tokens back; the **matcher stays on main** (pure Dart,
   cheap). Preserve chunk ORDER (in-order queue on the worker). `finish()` (0.8 s silence pad + final decode)
   also moves to the worker; main awaits its final tokens before `_buildMistakes`.
4. **Lifecycle:** `warmAsrEngine` → spawn worker + create recognizer up front; Stop → tell worker to
   finish + RESET the stream for reuse (don't respawn); app dispose/background → dispose worker. `MicOwnership`
   stays on main; only the recognizer moves.
5. **DEVICE CHECKPOINTS:** still follows correctly (same accuracy)? smoother than the Step-0 baseline? Stop
   still yields correct mistakes across the isolate? repeated open/close/tab-switch → no worker leak/crash?
   backgrounding mid-recite cleans up?
- **Fallback flag** (e.g. `useAsrIsolate`): build BOTH paths, default to the current synchronous one, flip on
  only once proven. Gotchas: FFI-across-isolate, model-staging path in an isolate, don't respawn per chunk.

### Plan B — RecitationSession merge (collapse the 3 near-duplicate states)
ReadingState(900) / DuaReadingState(466) / DuaFinderState(254) share logic but diverge hard (Quran =
cross-surah reacquire + page-follow + markerTick; du'a reader = index-based single-segment; finder =
Shazam-style multi-du'a id). Extract the COMMON core, keep each state's unique parts. INCREMENTAL only.
0. **Baseline:** confirm all three work on device today.
1. **Pure bits first (safe, host-tested, zero behavior change):** the `(rms-120)/1600` level map + `_rmsFloor`
   const; the PCM-retention cap + `mistakeWav` slice/clamp math (the review wanted this tested); ONE shared
   token-collapse (dua states still have private `_collapse` copies — point them at the matcher's / a shared
   one). Extract → repoint all 3 → host test → one device smoke. (`advanceMarker` already done this way.)
2. **Shared plumbing (medium risk — FIRST live-pipeline step):** claim/release mic, warm-up, the
   `_onPcm` boilerplate (retain → accept → tokens → RMS), start/stop scaffolding → a mixin or small
   `RecitationCore` the three EMBED; each keeps its own matcher + its own `_applyOut` (that's where they
   differ). **Device-verify all three here.**
3. **(Optional, only if Step 2 is clean):** unify the marker/apply overlap between Quran + du'a reader; keep
   the finder separate (most different).
- **Rule:** one extraction at a time, device-smoke after each, never all three at once. If a step forces the
  three to be "the same" when they aren't, STOP — that's the wrong shape. Each step is independently
  revertible.

## HADITH SEARCH — feasibility research (2026-07-16) → GO (host-proven; real-voice device test is the only open risk)
Voice-driven Hadith search ("Shazam for hadith": speak a matn snippet → retrieve the hadith). Fully de-risked host-side.
- **Reference phonemes are TEXT-derived, not audio.** `tool/build_dua_phonemes.py`'s path (quran-transcript Hafs G2P + greedy longest-match over the 250-unit `assets/asr/phoneme/tokens.txt`) works on arbitrary diacritized Arabic — the 5 bundled "duas" ARE hadith texts. No audio corpus needed.
- **G2P generalizes to hadith vocab: 0.00% OOV over 135K words** (2000 Bukhari hadith), 0 crashes, 0 under-diacritized skips. No normalizer/diacritization work needed first. ~44 min offline to phonemize all 15k.
- **Retrieval proof (all 7008 Bukhari, 11% simulated PER, SW local-align + n-gram index):** top-1 **100% at 10-word snippets** (95.7% @6, 99.4% @15). Index (3-gram, K=50): **100% recall + 25× speedup** (154→6 ms/query at 7k). Design: **≥8-10-word min snippet, 3/4-gram phoneme index (K=50), SW rerank** reusing `PhonemeLocalizer`.
- **Isnad is NOT a problem** — SW *local* alignment skips the narrator-chain boilerplate on its own; matn-only splitting added +1.2pt @6 words, 0 elsewhere. Index whole-text; the isnad/matn splitter (fires ~50%) is optional.
- **Data source:** `mhashim6/Open-Hadith-Data` (GitHub) — per-book CSV, WITH-tashkeel + WITHOUT, aligned hadith numbers, **ODbL 1.0 / DbCL 1.0** license (attribution + share-alike; cleanest to ship). Bukhari ~7008, Muslim ~5362.
- **ONLY open risk = real on-device acoustic accuracy** (proof used simulated PER, not recorded voice). Next real step needs a phone.
- **Build sequence:** (1) commit `tool/build_hadith_phonemes.py` (fault-tolerant batch) → `assets/asr/hadith_phonemes/` + index; (2) Dart `HadithFinderState` (n-gram prefilter K=50 → SW rerank, reuse `PhonemeLocalizer`); (3) Hadith tab + record UI + candidate-list + reader; (4) device-test real voice.
- Prototype scripts/results were in session scratchpad (throwaway): `build_corpus.py`, `retrieval_experiment.py`, `REPORT.txt` — reproducible from the params above.

## Session 5 pm addendum — FULL A-TO-Z REVIEW → `docs/REVIEW.md`
Ran an independent 16-lens multi-agent audit (architecture, engineering, concurrency, ASR, ML/tajwīd, security,
privacy, data-integrity, performance, testing, deps/licensing, build/release, observability, UX/a11y/i18n,
resilience, analytics), each finding adversarially verified. The run was truncated by a session token limit, so
**11 findings are adversarially verified; ~97 are single-reviewer (to-confirm)**. Full report + roadmap in
**`docs/REVIEW.md`** (1 critical, 15 high, 47 medium, 30 low, 15 info). Headline: strong core, but real
**ship-blockers** — (1) licensing: bundled non-commercial ASR model + KFGQPC font + Qur'an data all redistributed
with NO license/attribution/LICENSE file; (2) release signs with debug keystore; (3) privacy gaps: always-on
external-storage recitation logging regardless of consent, Android Auto Backup ships logs+anon_id to Drive, mic
keeps recording after leaving the Quran tab/backgrounding, PCM never wiped; (4) tajwīd reliability gate defeated by
n=1 letters → false makhraj flags on correct recitation; (5) ONNX inference on the UI isolate + per-chunk full-page
rebuilds. Also: no CI, dead hand-rolled engine (~642 LOC) still tested, ReadingState god-object (896 LOC), 3
near-duplicate pipelines. See `docs/REVIEW.md` §Roadmap for now/next/later.

**Ship-gate "now" items KNOCKED OUT (post-review, host-verified, analyze clean + 123 tests):**
- **Auto Backup off** — `android:allowBackup="false"`+`fullBackupContent="false"` (manifest) → logs/anon_id no longer egress to Google Drive.
- **Release signing wired** — `build.gradle.kts` now loads a git-ignored `android/key.properties` (template `key.properties.example`) and signs release with it; falls back to debug ONLY if the file is absent. USER MUST create the keystore (I don't generate secrets).
- **Diagnostics gated to dev** — `Log.diagEnabled` (`kDebugMode || --dart-define=DIAG=true`) now gates BOTH the external-storage file sink (`main.dart`) and the Debug Log screen entry (`home_screen`). Store builds write NO recitation traces to disk. **Workflow note: to pull device logs, build `--debug` or `--dart-define=DIAG=true`.**
- **Mic lifecycle** — `root_scaffold` now stops the Quran `ReadingState` on leaving the Quran tab (symmetric to the finder) AND registers a `WidgetsBindingObserver` that stops all active pipelines on background (paused/inactive/hidden).
- **PCM wiped** — `ReadingState.clearRetainedPcm()` called on tab-away + background; `DuaReadingState.dispose()` frees its buffer. Raw voice no longer lingers app-lifetime.
- **Consent label fixed** — "Essential app data / Basic functionality" → "Crash & error reports / Optional…" (settings).
- **Licenses & Attribution** — `lib/util/licenses.dart` registers model/font/Qur'an-data notices via `LicenseRegistry`; Settings→About→"Licenses & Attribution" opens `showLicensePage`; `THIRD_PARTY_NOTICES.md` added. **TODOs remain: paste exact model license + KFGQPC font EULA text; add a project `LICENSE`.**
- **iOS mic string** — `NSMicrophoneUsageDescription` added to Info.plist (was a guaranteed crash/rejection).
STILL OPEN from "now": create the actual release keystore (user); confirm/paste the model + font license text (user/legal).

## Session 5 pm addendum #2 — REVIEW ROADMAP: "now" finished + 6 "next" items done
Continued straight through the rest of `docs/REVIEW.md`'s roadmap (user: "keep going"). All host-verified,
**133 tests green, `flutter analyze lib` clean**. Discussed and explicitly declined: repurposing Android Auto
Backup for cross-device progress sync (wrong tool — opaque, Android-only, snapshot-not-live, no account
model); cross-device progress stays scoped to the future Supabase+accounts phase instead.

**"now" — finished:**
- **Debug/eval audio stripped from release** — `tool/release_build.ps1` (mirrors `run_eval.ps1`'s style)
  temporarily removes the `assets/debug_audio/`/`assets/eval_audio/` pubspec lines, builds
  `apk`/`appbundle --release`, then ALWAYS restores pubspec.yaml (even on failure). Dry-run verified
  (108→106 lines, byte-identical restore) without invoking an actual build — flutter builds stay yours.

**"next" — 6 items done:**
- **Async/native crash capture** — `main.dart` now wraps `runApp` in `runZonedGuarded` AND sets
  `PlatformDispatcher.instance.onError`, alongside the existing `FlutterError.onError`; all three funnel
  through one `_reportError` helper (Log.e + optional consented crash report). Previously only sync
  Flutter-framework errors were ever logged/reported.
- **Blank-page-on-error fixed** — `QuranRepository.page()` no longer memoizes a FAILED future (removes it
  from `_pageFutures` on catch, so a later call retries fresh instead of replaying the same failure forever).
  `quran_screen.dart`'s page FutureBuilder got a real `_PageContent` StatefulWidget with a visible
  error+Retry UI instead of silently showing a blank page. New `test/quran_repository_test.dart` proves the
  retry is a fresh Future (via `identical()`), not the cached failure.
- **Mic/chevron controls dedup'd + made accessible** — the mic button and reveal-chevron were three
  byte-identical private, unlabeled `GestureDetector`/`InkWell` copies (one per footer: Quran, du'a reader,
  du'a finder). Extracted into shared `lib/widgets/mic_toggle_button.dart` / `chevron_button.dart` (pure,
  no provider dependency) with `Semantics(button:true, label:..., toggled:...)` — TalkBack can now name and
  state the app's central controls. New `test/mic_toggle_button_test.dart` / `chevron_button_test.dart`
  assert the labels/toggled-state/tap-forwarding directly (these are the first widgets in the ASR-adjacent
  UI host-testable without a live `AsrEngine`, since they take no ReadingState/provider — a reusable pattern
  for future extractions).
- **Tajwīd reliability gate fixed** — the table is built from ONE Al-Baqara run, so ج/ث/ز (seen=1) and
  ظ/بڇ/قڇ (seen=2) all point-estimated to reliability=1.0 on zero real evidence and would've cleared the
  0.95 gate, flagging a CORRECT reciter. Computed the actual Wilson-lower-bound numbers first (see chat) —
  at THIS dataset's sample sizes (max n=93), a full Wilson-bound-at-0.95 would silence literally every
  letter including the flagship ط, so instead added a minimum-sample-size floor
  (`_minReliabilitySamples = 20` in `phoneme_corpus.dart`'s `loadPhonemeReliability()`): letters below it
  get reliability floored to 0 (silenced), same as a genuinely blind letter — `tajweed_review.dart`'s
  well-tested `_threshold` comparison logic is untouched. **Honest cost:** ط (seen=6) and the ظ→ز catch
  named in the module's own docstring (seen=2) are now ALSO silenced until more eval audio raises their
  sample size — updated the docstring to say so plainly, not paper over it. Updated
  `test/tajweed_review_test.dart`'s real-asset assertions (`rel['ط']` is now 0.0, was 1.0) + added a test
  for the exact n=1 case (ج/ث/ز). The `false_mistakes_diag_test.dart` regression (0 false flags) still
  passes — flooring MORE letters can only silence more, never add a flag.
- **Qur'an content-integrity test added** — the ONLY previous content check was `tool/verify_all.py`
  (manual, network-dependent, outside `flutter test`). Reused this session's already-fetched quran.com
  cache (`tool/_cache/qc/*.json`) to cross-check total+per-page word counts (77,429 words, ZERO
  mismatches — strong independent confirmation) before generating
  `assets/data/quran_content_reference.json` (a flat `{"s:a:w":"word"}` map, `tool/gen_content_reference.py`)
  from the CURRENT bundled data. New `test/quran_content_test.dart` loads all 604 pages via
  `QuranRepository` and asserts full equality against that reference — **verified it actually catches
  corruption**: injected a fake word into page 1, confirmed the test fails with an exact
  location+expected+got diagnostic, restored, confirmed green again. (Hit and resolved a `flutter test`
  build-cache staleness artifact along the way — `build/unit_test_assets/` doesn't always invalidate on a
  rapid revert; deleting it forces a fresh rebuild. Not a real bug, just a gotcha for fast edit/test loops.)
- **CI workflow added** — `.github/workflows/ci.yml` (`flutter analyze lib` + `flutter test` on push/PR).
  **Currently INERT — this directory has no `.git` yet**, so nothing runs until it becomes a real git repo
  with a GitHub remote. Ready the moment that happens.

**Session 5 pm #4 — two more "next" perf items (133 tests green, analyze clean):**
- **O(n²) matcher collapse fixed** — `phoneme_matcher.apply()` re-collapsed the ENTIRE growing cumulative
  token stream every chunk, though only the last `_tail`(24) tokens are ever consumed. Now stores the raw
  stream and collapses ONLY the tail (identical result — `_collapse` is per-token pure). Hoisted the
  `RegExp(r'(.)\1+')` in both `phoneme_matcher.dart` and `reading_state.dart` (`_collapseTok`) to
  file-level `final` so it compiles once, not per token per chunk. Matcher tests unchanged/green.
- **Mushaf rebuild-scoping fixed** — `QuranScreen` did `context.watch<ReadingState>()` at the Scaffold
  root, so the whole page tree (3 mushaf leaves, ~360 rich-text runs) rebuilt on EVERY notify (~13/s:
  RMS level, heard ticker, 1 s timer — none of which the mushaf needs). Added a `markerTick`
  `ValueNotifier<int>` on ReadingState that bumps ONLY when a cheap visible-state signature
  (`ctxSurah|readLen|skippedLen|revealedLen|currentLocation|hidden`) changes; all 21 `notifyListeners()`
  now route through one `_notify()` choke point. QuranScreen reads (not watches) and wraps the CurlPageView
  in `ValueListenableBuilder(markerTick)`, so the mushaf rebuilds only on real marker changes (~word rate).
  The FOOTER keeps its full-frequency `context.watch` (level/heard/timer stay smooth — zero regression).
  Safety: signature can't under-bump within a surah (sets rebuilt from states each chunk → any change alters
  a length) or across surahs (ctxSurah changes); a theoretical same-length swap self-corrects next chunk
  (~80 ms), so the mushaf can never go persistently stale. **DEVICE-PENDING eyeball** (host tests green,
  but the rebuild-frequency win is only observable on-device).

**Session 5 pm #5 — "Later" architecture items (safe subset; full refactor deferred):**
- **Dead hand-rolled engine DELETED** (726 LOC) — removed `recitation_tracker.dart`(364), `token_match.dart`(94),
  `verse_index.dart`(90, the CLASS — the `verse_index.json` ASSET stays, loaded by `phoneme_corpus`),
  `bpe_decoder.dart`(25, orphan), and `test/recitation_tracker_test.dart`. Verified via import-graph +
  symbol grep that 0 live code referenced them (only the test did — the review's "false coverage" finding).
  Kept `arabic_match`/`pronunciation_head`/`eval_runner`/`file_source` (still live). analyze clean.
- **Dead `deviations` path REMOVED** — `ReadingState.wordDeviations` was hardcoded `const {}` (a stubbed
  live-tajweed feed) yet threaded through 6 widget layers (quran_screen `_PageLeaf`→`_PageContent`,
  `MushafPageView`→`_AyahLine`→`_revealWord`) with a dead devColor/underline branch. Stripped the param
  from the whole chain, simplified the word border to just marker/skip, and dropped the now-unused
  `pronunciation_head` import from both `mushaf_page_view.dart` and `quran_screen.dart`.
- **Marker anti-teleport extracted** — the byte-identical catch-up block (`gap>8?gap:gap>2?(gap/2).ceil():1`)
  duplicated in both reading states is now one pure `advanceMarker(marker, cursor)` (top-level in
  reading_state.dart, imported by dua_reading_state — same convention as the other shared pure helpers).
  Pinned by `test/advance_marker_test.dart` (6 cases) so this device-tunable curve can't drift across the
  two readers. Behavior-identical.

**Full `RecitationSession` service extraction — DEFERRED (same risk class as the ONNX isolate).** The three
states (ReadingState 900 / DuaReadingState 466 / DuaFinderState 254) share small pure bits (marker advance
[now shared], `_collapse`, the `(rms-120)/1600` level map, `_maxRetainSeconds`, PCM-slice math) but diverge
hard where it matters: ReadingState has cross-surah re-acquisition + page-follow + the new markerTick;
DuaReadingState is index-based single-segment; DuaFinderState is a Shazam-style multi-du'a identifier. A
shared base/service that all three delegate to is a MAJOR core-pipeline refactor that CANNOT be host-verified
(the states hold platform channels) — getting it subtly wrong breaks live follow-along, found only on device.
Recommend doing it incrementally + device-verified, not blind. The safe pure-helper extractions above chip at
the drift hazard without touching the live pipeline.

**Still open from "next" — ONNX inference on a background isolate: DEFERRED, do NOT do blind.** sherpa_onnx's
recognizer is a live native FFI handle that can't cross isolates, so it must be created + fed entirely on a
worker isolate (PCM in via SendPort, token strings out) — a delicate refactor of SherpaAsr/AsrEngine + the
mic feeding, and it CANNOT be host-verified (native code doesn't run under `flutter test`). Getting isolate
message-passing or model-staging wrong silently breaks the CORE feature, discovered only on device. Recommend
doing it as a focused, device-verified task (user testing each step), not blind. The two perf fixes above
already cut UI-isolate load meaningfully in the meantime.
**"Later" (architecture) untouched**, as scoped: the 3-pipeline duplication, the dead hand-rolled engine,
the dead `deviations` path.

## Session 5 pm addendum — MUSHAF SURAH-NAME FIX (data-verified vs quran.com)
User reported surah names/headers looked wrong and the line layout didn't match Tarteel. Investigated
against the authoritative KFGQPC v2 layout (quran.com API v4, same data family Tarteel/QUL render from;
cached in `tool/_cache/qc/`). Findings + fix (`tool/fix_openers*.py`, `tool/verify_all.py`):
- **Verse TEXT and line-breaks were already correct** — our page data (`assets/mushaf/page-NNN.json`, from
  the `zonetecde/mushaf-layout` dataset) matches quran.com's per-line word grouping on all 604 pages
  (only p177/p443 differ, and only in how verses 8:6 / 36:52 are split into word-*tokens* — same text,
  same visible breaks). So no Qur'ān words were mistyped.
- **Real defect = surah-name openers.** The source (a) dropped the visible name on 17 surahs that the
  KFGQPC layout draws as a COMBINED opener (name + basmala on one top line; first ayah on line 2), and
  (b) MISPLACED 13 duplicate name banners at line 15 (bottom) of surahs' LAST pages (e.g. "سورة الحج"
  showed at the end of Al-Ḥajj, not its start). Net: some surahs showed no name, others showed a name in
  the wrong place — matching the user's report.
- **Fix applied to the data:** added the combined opener (new `LineType.opener` = `surah-opener`, renders
  name+basmala in one slot via `_SurahOpener` in `mushaf_page_view.dart`) for the 15 combined cases;
  inserted header+basmala for the 2 that were shifted (81 At-Takwīr p586, 85 Al-Burūj p590 — they also
  render correctly now that they exceed the 14-line `full`-grid threshold); removed all 13 spurious
  bottom/duplicate banners. **Verified: all 114 surahs now have EXACTLY ONE correct name line on their
  true start page; no page > 15 lines; ayah groupings still match quran.com.** Pinned by
  `test/mushaf_headers_test.dart` (loads all 604 pages). No word text touched — only opener lines.
- Model change: `LineType` gained `opener`. Renderer: added `_SurahOpener`. Device-pending: eyeball the
  combined-opener rows (name+basmala scaled into one line) + the 17 fixed pages.

Session 5 continued the subagent-implement → adversarial-review loop, now DEVICE-LOG-DRIVEN
(the user recites, pulls `pulls/run_*/logs`, I diagnose). 92 tests green, `flutter analyze lib`
clean. **I no longer build the APK — the user does** (see memory `feedback-user-builds-apk`);
I finish code + analyze/test and say "ready to build".

## Session 5: what shipped (device-confirmed where noted)
- **False tajwīd mistakes — FIXED & device-confirmed.** Reproduced 3 false Al-Baqara flags from a
  real device `TOKENSTREAM` (`test/false_mistakes_diag_test.dart`) and fixed in `tajweed_review.dart`:
  `_makhraj` now folds noon-ghunna `ں→ن` (permanent); a narrow `_modelConfusable={بم,مب,شف,فش}` mask
  for pairs THIS model swaps on correct audio (INTERIM — excludes ت/د/ط so ط→ت still flags). User
  confirmed real ك/ق, س/ص swaps now catch. Deeper fix = confusion-matrix reliability (needs eval audio).
- **Dua reader degradation — FIXED & device-confirmed.** Root cause was per-screen engine/mic churn;
  fix = one shared `lib/services/asr/asr_engine.dart` (`AsrEngine`) used by BOTH `ReadingState` and
  `DuaReadingState` (+ `DuaFinderState`), with `claimMic/releaseMic` single-owner mic. Quran path
  behaviorally identical (reviewed). Device logs now show one engine + full token counts across many opens.
  **(post-handoff 2026-07-16 pm)** the single-owner mechanism was extracted from `AsrEngine` into a pure
  `MicOwnership` class (same file) and pinned by `test/asr_engine_mic_test.dart` (7 cases: preempt-once,
  same-owner-idempotent, stale-release-can't-clear-owner, await-slow-release) — it was the one session-5
  change that had shipped with no test. Behavior-preserving delegation; 110 tests green, analyze clean.
- **Log-sink bug — FIXED (was MINE).** A "hardening" I'd added nulled the file sink on the first
  transient `StreamSink is bound` and killed logging ~0.3s into every run. `log.dart` now guards writes
  behind an in-flight-flush flag and never nulls the sink. (This had made earlier device logs look empty.)
- **Reveal button direction** swapped for RTL (`<`/`<<` = forward, `>`/`>>` = back) in both footers.
- **Recite-to-open dua finder** (`dua_finder_state.dart` + `DuaFinderFooter`): on the Azkar tab the bottom
  is now the recite-control FOOTER (nav bar hidden, like Quran) — tap mic → identifies which dua via
  per-dua localizers + pure `identifyDua` (floor/margin/confirm, DEVICE-PENDING tuning; logs `[duafind]`)
  → opens that dua's reader (`autoStart`) and follows along. Mic hands off finder→reader via `claimMic`.
- **Nav reorder** → Adhkar, Home, Quran (via `Tabs{dua=0,home=1,quran=2}` constants). Home is the hub
  (only tab with the nav bar); Duas & Quran immersive, back→Home.
- **Home light/dark toggle removed** (lives in Settings only; avatar → Profile → Settings kept).
- **Settings**: accent picker (Auto/Iris/Emerald/Coral/Ocean, persisted) + "Help improve" 2 consent
  toggles (`shareEssential`/`sharePerformance`, default OFF, LOCAL-ONLY — no backend/telemetry exists).
  **ANALYTICS IS NOT REAL / NOTHING IS SENT.** Three disconnected pieces: (1) the 2 toggles store a local
  bool, wired to NOTHING; (2) `lib/services/analytics.dart` (`AnalyticsSink`/`LogAnalyticsSink`/
  `SupabaseAnalyticsSink` + `AnonId`) is dead scaffolding — `sendSession` is NEVER called anywhere;
  (3) the Supabase sink is inert anyway (`SUPABASE_URL`/`SUPABASE_ANON_KEY` unset). `supabase/sessions.sql`
  is a future table schema. To make real: build a session report from the CURRENT pipeline (the old
  `SessionRecorder` was tied to the deleted per-token engine), GATE it on the opt-in toggle, then send via
  a sink (Log sink = local; Supabase = needs creds via --dart-define + provisioned table). DECISION PENDING
  — must stay opt-in + anonymous + never raw audio; a Quran app sending which verses were recited needs a
  privacy policy. Do NOT flip on external upload without explicit user direction. **PLAN written:
  `docs/ANALYTICS_PLAN.md`** (offline-first queue + Supabase upload + accounts magic-link/Google/guest;
  updated schema; user WILL set up Supabase + apply schema when ready). User confirmed: NOT building now — planning only.
  **(post-handoff 2026-07-16 pm — Phase A BUILT, still local-only, still NOTHING UPLOADED)** the analytics
  bullet above is now partly superseded. Implemented Phase A from the plan: a PURE `buildSessionReport(...)`
  in `analytics.dart` (built from the CURRENT pipeline at Stop — surah/duaId, reached, tokens, anchored,
  skipped, slimmed mistakes {kind,loc,expected,heard} ONLY, durationMs, app, platform; NO audio range / NO
  phoneme scores / NO PII by construction), an `Analytics` singleton gate (`usageConsent`, default OFF,
  mirrored from `AppState.sharePerformance` on load + toggle), wired at Stop in BOTH `reading_state.dart`
  and `dua_reading_state.dart` (`if (usageConsent) recordSession(...)`), default sink = `LogAnalyticsSink`
  (writes the report to the Debug Log you pull — no network). New `lib/screens/privacy_screen.dart`
  ("Data & Privacy", linked from Settings) lists SENT-if-opted-in vs NEVER-sent. Tests: `analytics_report_test`
  (shape + a GUARANTEE test that no audio/PII field can reach the wire), `analytics_gate_test` (off→silent,
  on→sent once), `privacy_screen_test`. **Still NOT built: Phase B** (offline queue + Supabase
  upload — user provisions project/schema/creds) **and Phase C** (accounts). Do NOT wire external upload
  without explicit user direction + a privacy policy.
  **Adversarial-reviewed (subagent):** privacy + consent guarantees verified sound (no path reaches a sink
  with consent off; report can only emit whitelisted fields; dead `SessionRecorder.report()` confirmed
  never called). Fixed ONE real bug it found: the Stop path cleared `_asrActive`/`_active` only at the END,
  after `await mic.stop()`, so a re-entrant Stop (double mic-tap, or a cross-pipeline `claimMic` preempting
  an in-flight Stop) fired a SECOND `recordSession` for one session — now the flag is cleared synchronously
  before the first await in both `reading_state.stopAsrListening` and `dua_reading_state.stopListening`
  (also stops double review/TOKENSTREAM). Can't host-test (states hold a MicSource platform channel); the
  `MicOwnership` test pins the cross-pipeline trigger. 119 tests green, analyze clean.
  **`shareEssential` — now WIRED (was the dead toggle the review flagged).** Added a pure `buildCrashReport`
  (anonymous: clipped error message + library + fatal + app + platform; NO stack, NO PII, NO audio) + a
  second gate `Analytics.essentialConsent` (mirrors `shareEssential`, default OFF) + `recordCrash`. Hooked
  into the EXISTING `main.dart` `FlutterError.onError` (which already logs locally) so an opted-in crash
  emits `[analytics] CRASH {...}` to the local Log sink — nothing uploaded. The two gates are independent
  (tested). Data & Privacy screen + Settings caption updated to describe BOTH categories honestly. 122 tests
  green, analyze clean. (`FlutterError.onError` is a sync closure so no `unawaited` lint; `exceptionAsString()`
  is the message only — `details.stack` is deliberately never passed.)
- **Quote Arabic — REVIEWED (2026-07-16 pm), no textual errors found.** Checked all 14 entries in
  `lib/data/quotes.dart` against canonical Hafs text: all match (simple/imlaei diacritized orthography;
  #13 Tirmidhī is an intentional clause; 65:2/65:3 are consecutive āyāt split into two). Not edited — I
  won't alter Qur'ān text I can't 100% improve. The "human-verify before release" comment stays; recommend a
  final native/scholar glance (esp. the orthography differs from the app's UthmanicHafs mushaf font).
- **Dynamic accent theming**: accent now = `colorScheme.primary` via `context.accent`; `AppState.accentColor`
  resolves presets or **Auto** (shifts by `dayPart`: fajr→iris, morning→emerald, afternoon→ocean,
  evening→coral, night→ocean). Dark theme brightens the accent to a lightness floor (0.6) for legibility.
  All 45 old `AppColors.emerald` accent uses migrated; tajweed/rec-red/gold left fixed.
- **Recite-to-open CONFIRMED working on device** (log `run_20260716_055229`: `[duafind] IDENTIFIED
  dua-aslamtu-nafsi`, scored 1.71 vs 1.29 others — margin 0.42 was TIGHT past the 0.4 threshold; consider
  lowering `identifyDua` margin a touch). After open, the dua reader still anchored weakly on some duas.
- **Hearing/tracking footer indicator** (`lib/widgets/hearing_indicator.dart`): a live 4-bar equalizer +
  label (waiting… / Listening… / **Following** in accent) so the user can SEE if the app is hearing +
  tracking. Read-only getters added: `ReadingState.asrLevel`/`asrAnchored`, `DuaReadingState.level`/`anchored`,
  `DuaFinderState.level`/`leadingDuaId` (rms→0..1 mapping is DEVICE-TUNABLE: `(rms-120)/1600`). Wired into
  the Quran, dua-reader, and finder footers. No ASR behavior change (pure telemetry).
- **"Heard" phoneme ticker** (`lib/widgets/heard_ticker.dart`): a thin RTL line above each recite footer's
  buttons showing the last ~12 decoded phonemes live (UthmanicHafs) — so the user sees WHAT the model
  heard (e.g. said قال → heard قول), demystifying false flags. Getters `asrHeard`/`heard` (pure top-level
  `recentHeard(tail)`; `join('')` so harakāt-carrying tokens read word-like). Raw model output — verified
  no tatweel artifact in real device logs, so shown as-is. Read-only; matcher/token flow untouched.

## Session 5 — DEVICE-PENDING / open
- Recite-to-open match thresholds (`identifyDua` floor/margin/confirm) need on-device tuning (`[duafind]` log).
- Some duas anchor weakly in follow-along (e.g. after-adhan) — follow-along quirk, user said LEAVE for now.
- Dynamic-accent look (esp. Auto shifts + dark brightening) is unrendered here — user to eyeball.
- Quote Arabic still needs proofing (`lib/data/quotes.dart`).
- **Accounts** — user is "thinking" (use with/without); app is Guest-capable today; full auth = future (needs backend).
- **Confusion-matrix reliability** (replace ش↔ف interim mask) — needs eval audio.
- Debug Log screen exists (long-press "Tilawa" on Home) — not surfaced as a tab, kept hidden.

---

# TilawaAi — Handoff (2026-07-15, session 4)

Session 4 = a large feature batch, each SUBAGENT-implemented then adversarial-review-fixed.
All HOST-verified (80 tests green, `flutter analyze lib` clean, debug APK builds).
**ALL device-pending** — nothing below is confirmed on a phone yet.

## Session 4: what shipped
**Phase 1 — recitation UX fixes** (`reading_state.dart`): haptic buzz (`HapticFeedback.mediumImpact`)
on a newly-skipped word during LIVE mic only (gated by `_liveMic`, silent on Stop); forward-reveal
`>`/`>>` now ANCHORS to the furthest-reached position (mid-page start reveals the NEXT word, not
the page top — `revealForwardLocs` gained `anchorIndex`); backward `<`/`<<` confirmed working mic-off.

**Phase 2 — Home + nav redesign**: time-of-day util (`lib/util/day_part.dart`, pure); daily rotating
Quran/hadith QUOTE hero (`lib/data/quotes.dart` — ⚠️ ARABIC NEEDS HUMAN PROOF, 14 entries, several
are partial clauses); Continue + new Counter widget-buttons; time-based adhkār suggestion; avatar →
`UserScreen` → `SettingsScreen` (System/Light/Dark selector, language STUB, about). Counter (the old
`AdzkarScreen` tasbih) moved OFF the tab bar → reachable from the Home "Counter" button only.

**Phase 3 — Dua reader (TWO-PIPELINE design; Quran path UNTOUCHED)**: a user recites Quran OR reads a
dua, never both, so the dua reader is a SEPARATE pipeline sharing only the model + engine CLASSES.
- Spike proved feasibility: `tool/build_dua_phonemes.py` phonemizes duas via `quran_transcript`
  (diacritized text → the same 250-unit vocab, 0 OOV); on-device fixtures show the model follows duas.
- `assets/asr/dua_phonemes/*.json` (5 duas), `lib/data/duas.dart`, `loadDuaClip`/`DuaClip` in
  `phoneme_corpus.dart` (1:1 corpus-word→display-word, no mushaf map).
- `lib/state/dua_reading_state.dart` — `DuaReadingState`: OWN `SherpaAsr` (lazy, disposed with the
  screen; `_disposed` guard so a back-out during warm-up doesn't leak the engine/mic), own matcher,
  hide/reveal (reuses the pure `revealForwardLocs`/`revealBackLocs` via `"0:0:i"` word-index strings),
  live follow, PCM retention + tap-to-hear, tajwīd mistakes — all carried over from the Quran path's
  fixed versions. Tab 1 (`root_scaffold.dart`) is now `DuaListScreen`→`DuaReaderScreen` +
  `DuaReadingFooter`/`showDuaMistakesSheet`; the Quran `ReadingFooter` shows on the Quran tab only.
- Memory: peak 2× phoneme models only WHILE a dua reader is open (Quran engine stays warm globally).
  Could share one engine later if low-end RAM is tight; kept separate for isolation.

**PENDING device check (session 4):** haptics feel; mid-page reveal; the whole Home redesign; theme
selector persistence; **dua mic follow-along on real dua recitation** (the key unknown — host spike
only); tap-to-hear on duas; quote rendering. Plus the STILL-OPEN false-mistakes bug (needs a device
`[mistakes] review:` + `TOKENSTREAM` log to fix). Quote Arabic needs proofing.

**False-mistakes FIXED (device-log-driven):** the user's Al-Baqara run falsely flagged 3 makhraj
mistakes. Reproduced host-side from the device `TOKENSTREAM` (`test/false_mistakes_diag_test.dart`,
surah 2, min1497/max1563) and fixed in `tajweed_review.dart`: (a) PERMANENT — `_makhraj` now folds
the noon-ghunna glyph `ں→ن` (corpus writes assimilating noon as ں = same makhraj as ن; 469× in surah 2);
(b) INTERIM — a narrow `_modelConfusable={بم,مب,شف,فش}` mask for the two consonant pairs THIS model
swaps on correct audio. Excludes ت/د/ط so the flagship ط→ت catch still fires. The real fix is
regenerating `phoneme-reliability.json` from a heard-given-said CONFUSION MATRIX (esp. for ش↔ف, which
rests on thin evidence) — tracked as a follow-up; needs eval audio.

**Dua reader DEGRADATION fixed (device-log-driven).** Device logs showed the dua reader mic-follow
WORKED on the first open (217 tokens, tracked) but degraded on repeated opens (31/6/15 tokens, never
anchored) + `StreamSink is bound` mic/log errors. Root cause: each `DuaReaderScreen` created+disposed
its OWN ~70MB sherpa engine + mic (on top of the always-warm Quran engine) → native resource churn
starved the model. FIX (user-approved, touches the protected Quran path): extracted one shared
`lib/services/asr/asr_engine.dart` (`AsrEngine`: single `SherpaAsr` lazy via `ready()`, single
`MicSource`, `units`/`reliability`, `warm()`); BOTH `ReadingState` and `DuaReadingState` now delegate to
it (constructor-injected; app-global `Provider<AsrEngine>` above them in `main.dart`). Neither state
disposes the engine/mic — only `AsrEngine.dispose()` at app teardown. Added single-owner mic:
`AsrEngine.claimMic/releaseMic` so starting one pipeline stops the other (tabs are an IndexedStack, so
a Quran session stays alive on tab-switch — this prevents a zombie session on the shared mic). Also
hardened `Log._write` to swallow sink errors. Review verified the Quran path is behaviorally identical.
**DEVICE-PENDING:** confirm dua follow-along no longer degrades across many opens.

**Remaining:** Phase 4 (curl — INTENTIONALLY DROPPED, current curl kept); confusion-matrix reliability;
full i18n (language is a stub); quote Arabic proof.

---

# TilawaAi — Handoff (2026-07-15, session 3)

Session 3 shipped the three remaining §3 features (below), each SUBAGENT-implemented
then adversarial-review-fixed. All host-side; **PENDING on-device tuning/verify**.
Full suite green (52 tests, `flutter analyze lib` clean). The matcher/localizer
(`phoneme_matcher.dart`, `phoneme_align.dart`) were NOT modified except one additive
read-only getter (`int get anchor`).

## Session 3: what shipped (host-verified, device-pending)
1. **Reveal buttons `< << > >>`** (hidden mode, `reading_footer.dart` `_RevealRow`).
   Location-based, page-scoped (diverges from ZikirAi's matcher-index model). Pure
   logic in `reading_state.dart` (`revealForwardLocs`/`revealBackLocs`), page words
   pushed from `quran_screen._registerPage` (async-refreshed on cache miss).
   Test: `test/reading_state_reveal_test.dart`.
2. **Cross-surah re-acquisition** (net-new; NO ZikirAi ref — ZikirAi is per-surah).
   Orchestration-only in `reading_state.dart`: on a sustained stall the mic tail is
   probed against a ±5 surah neighbourhood via `PhonemeLocalizer.localizeScored`; a
   debounced winner (`decideReacquire`, pure) triggers a clip/matcher switch + nav.
   Anti-thrash: `_switchCount` cap (4) reset on real progress; self-triggered turns
   don't rewrite `_ctxSurah` (juz-30 shared-page fix); lands on the localized verse's
   page, not `c:1`. Tunables are named consts — CALIBRATE ON DEVICE via the
   `REACQ probe … scores=…` log. Test: `test/cross_surah_reacquire_test.dart`.
3. **Mistake detection** (post-recitation tajwīd). Port of ZikirAi `tajweedReview.ts`
   → `lib/services/asr/tajweed_review.dart` (makhraj-substitution, SUB_COST=1.5,
   reliability≥0.95 gate, junction + madd-bleed masks). Reliability table copied to
   `assets/asr/phoneme-reliability.json`. `reviewTajweed` runs at Stop over
   `tokens.join(' ')` (space-join is LOSSLESS — empty-join re-merges units), bounded
   by `matcher.anchor..matcher.reached`. Flags → `RecitationMistake` (mispronounced +
   skipped) in the existing Mistakes sheet. Audio playback OUT OF SCOPE (no PCM
   retained → `canPlayMistake`/`mistakeWav` still stubbed). Test: `test/tajweed_review_test.dart`.

### Session 3 follow-ups (same session, after on-device feedback)
4. **Mistake audio playback (tap-to-hear) — DONE.** Session PCM retained
   (`_sessionPcm`, capped 600s), sherpa per-token `timestamps` exposed
   (`SherpaAsr.lastTimestamps`), ZikirAi `wordSpan` ported into `tajweed_review.dart`
   (contiguous-cluster around the flagged token), `RecitationMistake.start/endSample`
   populated, `mistakeWav`/`canPlayMistake` slice + WAV-encode (`lib/services/asr/wav.dart`).
   The alignment chain (timestamps=seconds, `join(' ')`→1:1 tokens, PCM==fed audio) was
   review-verified. Tests: `wav_test.dart` + span tests in `tajweed_review_test.dart`.
5. **Marker fixes (display-only):** (a) the live marker now CLEARS on Stop (was left lit
   on the last word); (b) verse-end catch-up closes HALF the gap per chunk instead of a
   1-word/chunk crawl (`_applyOut`). The inter-verse PAUSE itself is inherent streaming
   latency (see §4 below) — not fixed, can't be without model changes.
6. **Surah header** redesigned (`_SurahHeader`) — frameless centered band (was an ugly
   double-ruled gradient box). **Mic** `start()` now `stop()`s a still-recording recorder
   before `startStream` to pre-empt "StreamSink is bound to a stream".

**PENDING device check (session 3):** reveal-button feel; cross-surah probe/switch
tuning (6 best-guess thresholds); tajwīd flags vs real audio; tap-to-hear plays the
right slice; marker catch-up feel; new surah header. Reinstall APK, recite across a
surah boundary + a wrong-letter word, pull logs.

**Remaining after session 3:** cross-surah probes a ±5 window only (won't catch
reciting a far surah from an unrelated page); mid-start back-fill reveal (old deferred
item); the inter-verse marker pause is inherent (§4). See the older TODO list far below.

---

# TilawaAi — Handoff (2026-07-15, session 2)

This session **debugged and fixed the live follow-along** end-to-end.
The older 2026-07-14 section is background.

## 0. Ground rules learned this session (don't relearn the hard way)
- **ZikirAi (`../ZikirAi`) is the reference — check it FIRST.** It's the RN app that
  worked "like a clock"; TilawaAi's matcher is a port of it. Matcher logic:
  `src/lib/matcher/phonemeMatchSession.ts`. DISPLAY/marker: `src/screens/QuranReadScreen.tsx`.
  Two of this session's fixes came straight from re-reading it. See memory
  `feedback-rn-reference-is-ground-truth`.
- **The model is `Muno459/zipformer_p-quran`** (gated HF), streaming zipformer2-ctc
  phoneme. Non-commercial license. Full detail: `docs/ASR_MODEL.md`. NOT the
  fastconformer repo (that's the old, deleted engine).
- **DON'T re-add the "§3b verse-boundary lookahead / crossed-early / forward-rescue"**
  to the matcher. It diverged from RN and caused 26s non-recovering deadlocks. It was
  reverted this session. History: `docs/LATENCY_INVESTIGATION.md`.

## 1. What changed this session (all in the current debug APK)
- **Matcher reverted to RN parity** (`phoneme_matcher.dart`) — removed the §3b machinery.
  26s deadlocks gone; independently review-verified faithful to `phonemeMatchSession.ts`.
- **Corpus validated model-exact** (`tool/validate_corpus.py`, 6236/6236 identical).
- **Corpus→mushaf alignment REBUILT** (`tool/build_phoneme_align.py`, monotonic block DP
  on phonemes) — the old aligner used the lossy `words` field and dropped mushaf glyphs
  on 49 āyāt (2:263, 6:98, 66:5, …). Now 6236/6236 complete/in-order (`tool/validate_align.py`).
- **Host audio eval** (`tool/eval_audio.py`) — runs the REAL model on the host via Python
  `sherpa_onnx` (+ bundled ffmpeg). Al-Baqara 1–22 = 97% word coverage. No device needed.
- **Verbose logging**: `[phon]` (each new phoneme + rms), `[word]` (GREEN/SKIP + glyph),
  `TOKENSTREAM` dump on stop. Toggle trace on the Debug Log screen.
- **Merge highlight (RN-style range)**: a corpus word covers ≤5 mushaf glyphs (13% of
  Al-Baqara merge); the WHOLE current corpus word now highlights together
  (`SurahClip.glyphsOf` → `asrHighlightedLocations` set → `mushaf_page_view` set-membership)
  instead of a point marker hanging on the first glyph.
- **Marker fixes** (`reading_state.dart`): (a) marker only shows once matcher `anchored`
  (no false marker on the last page's first word); (b) verse-end **jump smoothed** — a
  display `_markerCursor` steps forward ≤1 word/chunk so the catch-up burst walks through
  glyphs instead of teleporting to ~word 3 of the next verse; (c) **auto-follow across
  pages** — `asrNavigate` is now TRIGGERED (was only received): the reader turns to the
  marker's page (guarded so an auto-turn never re-anchors the live matcher).
- **UI**: surah-name cartouche enlarged (`_SurahHeader` in `mushaf_page_view.dart`).

## 2. Verified vs PENDING device check
- **Verified** (host/tests): matcher RN-parity (review agent), corpus + alignment
  (validators + `flutter test test/phoneme_matcher_test.dart`, 10 tests), host eval.
- **PENDING on-device (behavioral/visual — I tuned by reasoning):** verse-jump smoothing
  feel, auto-follow page turns, idle-marker gating, merge-highlight, surah box size.
  → Reinstall APK, recite across verse boundaries + a page break, pull logs (`run_eval.ps1`).

## 3. Remaining plan (user wants: SUBAGENT implements each, REVIEW agent after each)
1. **Reveal buttons `> >> << <`** (word/āyah forward+back, hidden/memorization mode).
   Port ZikirAi `QuranReadScreen.tsx` (`revealForward`/`revealBack`, `firstHidden`/
   `lastManual`). TilawaAi has `reading_state`: `hidden`, `revealed`, `revealLocations`,
   `toggleWord`, `toggleHidden` (+ a hide/removeAll). The ORDERED word list must come from
   the current page (`QuranRepository.cachedPage(page).lines[].words[].location`), like
   ZikirAi does it in the screen. Footer is `lib/widgets/reading_footer.dart`.
2. **Cross-surah follow** — today the matcher is locked to the VISIBLE page's surah
   (`_ctxSurah`), so "open Al-Fātiḥa, recite Al-Baqara" won't track. Add re-acquisition:
   when the current surah stops matching for a while, try neighbouring/other surahs and
   switch+navigate. (Auto-follow across PAGES within a surah already works.)
3. **Mistake detection** — currently STUBBED (`mistakes`→[], `wordDeviations`→{}). Port
   ZikirAi `src/lib/matcher/tajweedReview.ts` + per-phoneme scoring; wire `mistakes_sheet`.

## 4. The verse-end "hang" (understand before touching)
User report: "at the verse end it hangs, then jumps to ~word 3 of the next verse."
- The **jump** is fixed (marker smoothing, §1 above).
- The **hang** is largely INHERENT: during the waqf (verse-end pause) the reciter is
  silent AND the streaming model needs ~0.8s of trailing audio before it emits a word's
  phonemes — so there is genuinely nothing to advance to yet. Measured: `rms`→~18 during
  the pause, `head`/`toks` flat, then a burst. The range-highlight keeps the finished
  phrase lit so it reads as "you're here", not "stuck". A real reduction would need a
  careful next-verse lookahead that does NOT mutate `curAyah`/`reachLo` (that's what the
  reverted §3b did wrong). Do the host eval + a Dart test FIRST if you attempt it.

## 5. Tooling (host-side, no device)
- `python tool/validate_corpus.py` — corpus vs canonical.
- `python tool/validate_align.py` — alignment completeness/monotonic/identity/sim-floor.
- `python tool/eval_audio.py` — run the real model on `audio/*` recordings.
- `flutter test test/phoneme_matcher_test.dart` — matcher + mapping (10 tests).
- `.\run_eval.ps1` — build+install+launch; Ctrl+C pulls logs to `pulls/run_*`.
- Canonical model data (corpus, text2phoneme) lives in `../Zikir Ai/spike/zipformer-quran-phoneme/`.

## 6. Memory (loaded each session)
`asr-model-source`, `asr-sherpa-phoneme-pipeline`, `feedback-rn-reference-is-ground-truth`,
`feedback-user-tests-on-device`, `feedback-evaluate-dont-agree`. Docs:
`docs/ASR_MODEL.md`, `docs/LATENCY_INVESTIGATION.md` (Attempts 1–5 log).

---

# TilawaAi — Handoff (2026-07-14)

Flutter Quran app: tajweed mushaf, single-page paper-curl reader, live recitation
follow-along (mic → highlight the word being recited). This session **replaced the
broken ASR engine** and fixed reader/UI issues. Below is the current state, what's
verified vs not, and how to test.

---

## 1. Headline: ASR was rebuilt on sherpa-onnx (the ZikirAi pipeline)

### Why
The Flutter app's original ASR **never worked** (no marker, no follow-along). Root
cause: it **hand-rolled** the audio frontend in Dart (`mel_frontend.dart` +
`asr_engine.dart` on `onnxruntime`) around the Muno459 **fastconformer** streaming
model. The hand-rolled mel/CMVN/CTC didn't match the model → garbage tokens
(match scores `0.00` in logs) → tracker returned `currentLocation = null` → no marker.

The RN app **`../ZikirAi`** worked "like a clock" because it used **sherpa-onnx**
(native C++ ASR runtime) + a **streaming phoneme model** + a **phoneme matcher**.
Flutter can use the same runtime via the `sherpa_onnx` pub package. So we ported
ZikirAi's exact pipeline.

### The pipeline now
```
mic (PCM16 16k) ──► SherpaAsr.accept()  ──► cumulative phoneme tokens
   (mic_source)      (sherpa OnlineRecognizer,          │
                      zipformer2-ctc, ONE persistent     ▼
                      stream, 0.8s tail pad)     PhonemeMatchSession.apply()
                                                  (ported matcher: NW align +
                                                   Smith-Waterman localizer +
                                                   follow-anywhere session)
                                                          │  cursor = corpus word idx
                                                          ▼
                                                  SurahClip.wordLocations
                                                  (corpus word → mushaf s:a:w)
                                                          │
                                                          ▼
                                             ReadingState.asrHighlightedLocation
                                                  → mushaf_page_view marker
```

- **Model:** `assets/asr/phoneme/model.int8.onnx` (72 MB, Muno459 zipformer2-ctc
  PHONEME, streaming) + `tokens.txt` (251 Arabic-script phoneme units). Copied from
  `ZikirAi/models-src/sherpa-onnx-zipformer-quran-phoneme/`.
- **Corpus:** `assets/asr/quran_phonemes/001..114.json` (per-surah `words`,
  `phonemes`, `phonemeToWord`, `ayahBoundaries`). Copied from `ZikirAi/src/data/quran`.
- **Runtime:** `sherpa_onnx: ^1.13.4` (bundles native libs). `onnxruntime` REMOVED.

### Files (all under `lib/services/asr/`)
| File | Role |
|---|---|
| `sherpa_asr.dart` | Streaming `OnlineRecognizer` wrapper (`accept`/`finish`/`resetStream`) |
| `phoneme_align.dart` | NW aligner + greedy tokenizer + Smith-Waterman localizer (ports of `phonemeAlign/Tokenizer/Localize.ts`) |
| `phoneme_matcher.dart` | `PhonemeMatchSession` — the ~350-line follow-anywhere engine (port of `phonemeMatchSession.ts`) |
| `phoneme_corpus.dart` | Loads a surah clip + corpus-word→mushaf-location map |
| `arabic_match.dart` | `similarity`/`levenshtein` (used by the aligner) |
| `eval_runner.dart` | Batch eval over bundled clips → timestamped JSON + deep log |
| `mic_source.dart`, `file_source.dart` | mic PCM / WAV-asset loading (unchanged) |

`lib/state/reading_state.dart` was rewritten to drive this; the public getters
(`asrHighlightedLocation`, `asrReadLocations`, `asrActive`, …) are unchanged so the
UI compiles as-is.

### DELETED
`asr_engine.dart`, `mel_frontend.dart`, `recitation_session.dart`, the 131 MB
`model_streaming_with_encoder.q8.onnx`, `pronunciation_head.bin`, and the
`onnxruntime` dependency. Kept but UNUSED by the live path (still pinned by the old
tracker test / used for types): `recitation_tracker.dart`, `token_match.dart`,
`verse_index.dart`, `asr_assets.dart`, `bpe_decoder.dart`, `pronunciation_head.dart`
(Deviation enum), `session.dart` (RecitationMistake type).

---

## 2. Critical bug an adversarial review caught (now fixed)

An independent review agent audited the port. It confirmed the matcher/aligner/
sherpa layers are **faithful** (all constants + logic match ZikirAi), but found:

- **The phoneme corpus segments words differently from the mushaf** (merges
  `2:5:2 = "عَلَىٰ هُدًۭى"` = two mushaf words; splits muqaṭṭaʿāt). The first mapping
  (corpus word index → `s:a:w` via ayahBoundaries) lit the **wrong glyph on 107 of
  114 surahs**. Only 7 (1,94,95,102,103,108,110) happened to line up.
- **The "29/29 verified" test was a tautology** — it fed the corpus's own phonemes
  back into itself, never checked mushaf locations, and even passed on broken surahs.

**Fix:** `tool/build_phoneme_align.py` letter-aligns corpus words ↔ mushaf words per
āyah (difflib on normalized letters) → `assets/asr/align/NNN.json` = corpus-word-index
→ LIST of mushaf locations. `SurahClip.wordLocations` uses it; a green corpus word
lights ALL the mushaf glyphs it covers. Coverage: **only 49/6236 āyāt incomplete**
(muqaṭṭaʿāt, fallback-handled). Re-run the tool if either dataset changes.

---

## 3. Verified vs NOT (be honest about this)

**CONFIRMED WORKING ON DEVICE (2026-07-15 log, live recitation of Al-Baqara):**
- ✅ The whole chain runs: `[mic] 1094 + [recite] 965` lines (old engine produced zero).
- ✅ The marker **follows real recitation in order**: cursor advanced
  `2:1:1 → 2:2:5 → 2:3:4 → 2:4:10 → 2:5:8`, `read` climbing monotonically, on **correct**
  mushaf glyphs (the corpus→mushaf alignment holds on real audio).

**Verified on the dev machine (pure Dart, no model/device):**
- ✅ Matcher logic + verse-boundary slide (`test/phoneme_matcher_test.dart`, 7 tests).
- ✅ Corpus→mushaf mapping complete on known-misaligned surahs (2,112,114).

**Still to confirm / open:**
- ⬜ **Landscape vertical overflow** (~249 px) on the mushaf page — short surahs use a
  fixed-height `Column` that doesn't fit the short landscape height. Portrait is fine.
  NOT yet fixed (user prioritized ASR). See TODO.
- ⬜ Accuracy % per clip — run the batch eval (below) for the number.
- ⬜ Streaming decode runs on the mic-callback isolate; watch for jank (move to a
  background isolate if needed).
- ⬜ `[capture] !debugNeedsPaint` — curl grabs its bitmap a frame early; cosmetic.

---

## 3b. Follow-along tuning (2026-07-15, after on-device confirmation)

User feedback that reading *flowed* but lagged at verse ends. Fixes in
`phoneme_matcher.dart` / `reading_state.dart` / `mushaf_page_view.dart`:

- **A — verse-boundary lookahead.** The matcher's forward window was capped at the
  current verse's last word, so if the model **dropped a verse-final word** it couldn't
  slide → dropped to a wide search → lag (looked like "re-searching / new session").
  Now: near the verse end (by the confirmed frontier **or** the live localized `head`,
  so dropped trailing words don't block it) the window reaches into the **next verse's
  first words** (`_versePeek=2`, score-gated), plus a **forward rescue** that prefers
  recent next-verse audio over the just-finished verse's leftover phonemes. On crossing,
  it slides `curAyah` immediately and the finished verse's unheard trailing words fall to
  **skipped/red**. Pinned by `test/phoneme_matcher_test.dart` ("slides across a verse
  boundary when the verse-final word drops").
- **B — skipped word → red in hidden mode.** `asrSkippedLocations` is now wired (was
  stubbed `{}`); skipped words are revealed in **red** instead of staying blank (fixed the
  "one word stayed hidden" report). Red also shows in normal mode.
- **C — removed** the emerald underline under the current word in hidden mode (user: "just
  reveal the word").
- **Diagnostic logging** (so we can tell model-miss from matcher-reject):
  - `ANCHOR lock @wN` — should fire **once per session**; multiple = a real re-search bug.
  - `verse CROSS early -> ayah N` / `verse slide -> ayah N` — verse transitions.
  - `SKIP w# frac=X need=Y phonemes=Z` — `frac≈0` = model didn't emit it; `frac<need` =
    threshold too strict (loosenable).

NOTE: the streaming model emits a word's phonemes only after ~0.8 s of right-context;
`SherpaAsr.finish()` pads 0.8 s of silence so the last word flushes. Mid-recitation breath
pauses are covered by the continuous silence in the stream.

Deferred (user said not important now): on a mid-verse start, back-fill-reveal the earlier
words of the chapter as already-read.

---

## 4. How to test (on device)

```powershell
.\run_eval.ps1               # build + install + launch, Ctrl+C pulls logs+eval
.\run_eval.ps1 -SkipBuild    # reuse installed APK
```
Then on the phone:
- **Live:** Quran tab → tap mic → recite. Marker should follow.
- **Batch eval:** Home → Debug Log → **"Run eval (all clips)"**. Runs 8 bundled clips
  (6 correct + 2 "wrong" controls) through the real pipeline, writes
  `eval_<timestamp>.json`.

Ctrl+C in the ps1 pulls this run's `logs/run_*.log` + `eval/eval_*.json` into
`pulls\run_<timestamp>\` (every run timestamped — nothing overwrites). Read the eval:
correct clips should light most words; the two wrong clips should score low (that
contrast is the signal).

Host-side tests: `flutter test test/phoneme_matcher_test.dart` (matcher + mapping),
`flutter test test/page_render_scan_test.dart` (0 mushaf overflow).

---

## 5. Other work this session (reader / UI)

- **Reader:** SINGLE page (a two-page spread was built then rejected by the user).
  Curl direction corrected: forward peels from LEFT edge, back from RIGHT, every swipe
  curls (`curl_page_view.dart`).
- **Footer:** now clears the Android nav bar (SafeArea in `root_scaffold.dart`).
- **Page layout:** shared math extracted to `widgets/mushaf_layout.dart` (single source
  for renderer + a "Scan pages" render diagnostic). Verified 0 overflow across 604 pages.
- **Debug Log screen:** file-diagnostic buttons, "Sherpa: hear Kursi" (logs phonemes),
  "Run eval", "Scan pages".

---

## 6. TODO / next (v1 scope left open)

1. ✅ **Landscape vertical overflow — FIXED (session 4, host-verified).** The `!full`
   branch of `mushaf_page_view._body` centered a fixed-gap `Column` with no height escape;
   short surahs overflowed the short landscape viewport (reproduced: Al-Fātiḥa +91px at
   800×360). Wrapped in `SingleChildScrollView` + `ConstrainedBox(minHeight: maxHeight)` so
   it stays centered when it fits (portrait unchanged) and scrolls when the height is tight.
   Pinned by `test/landscape_overflow_test.dart` (pumps every <14-line page at landscape
   geometry, asserts no RenderFlex overflow). PENDING device: confirm feel in landscape.
2. **Auto-navigate** the page to follow the reciter across pages (marker only shows while
   its `s:a:w` is on the visible page; use `verse_index.dart` for loc→page). Also enables
   cross-surah continuation.
3. **Run the batch eval** for accuracy numbers per clip (Debug Log → "Run eval").
4. **Move sherpa decode off the mic isolate** if it janks the UI.
5. **Re-add mistakes/tajweed scoring** (stubbed — was tied to the deleted per-token
   engine; `mistakes`→[], `wordDeviations`→{}).
6. Curl `!debugNeedsPaint` capture warning — add a guard.
7. Mid-verse-start back-fill reveal (deferred user request, §3b).
8. The 49 muqaṭṭaʿāt-edge āyāt use a fallback mapping — verify they highlight sanely.

Project memory: `~/.claude/.../memory/asr-sherpa-phoneme-pipeline.md` (supersedes the
ASR section of `tilawa-ai-conventions.md`).
