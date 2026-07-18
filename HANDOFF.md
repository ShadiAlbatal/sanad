# Sanad — Handoff — START HERE

## ⭐ SESSION 9 (2026-07-19) — FASTCONFORMER VOICE SEARCH BUILT + MERGED — RESUME HERE

**What shipped this session (branch `spike/fastconformer-search` → MERGED to `master`):** voice search is now **transcribe-to-text** (FastConformer word model → BM25) across all three tabs, replacing the phoneme-similarity finders. Device-proven: model loads ~1.1s, transcribes ~60× realtime, near-perfect Qur'an + hadith narrator-name transcripts. This replaced the phoneme-search approach after **Option C (phoneme→word→BM25) was measured and rejected** — clean 96-100% word recovery collapsed to 62-75% at the phoneme model's real ~12% PER (error compounding); code still parked on branch `feature/word-search-from-phonemes`.

**Architecture (the two-model split — CLOSED decision):**
- **Search = FastConformer** (`lib/services/asr/word_asr.dart`, sherpa OfflineRecognizer, NeMo CTC; 125MB int8 `assets/asr/word/fastconformer.int8.onnx`, now in LFS). `lib/state/voice_search_state.dart` = the shared driver: record on the shared mic → re-transcribe the growing buffer every 2s (live narrowing) → transcript flows into each list screen's search field → existing BM25 renders. ONE `VoiceSearchState` for all 3 tabs (provided in main.dart).
- **Follow-along stays phoneme** (`sherpa_asr.dart` OnlineRecognizer, unchanged) — highlights words in the readers.
- **The two sherpa models must NEVER run at once** (device-observed: offline recognition leaves the online one decoding 0 tokens — shared native runtime/memory). Handoff on opening a reader: `VoiceSearchState.cancel()` → `_handOffToFollowAlong()` disposes the word model (frees 125MB) + `AsrEngine.invalidateEngine()` rebuilds a fresh phoneme recognizer. This invalidate runs SYNCHRONOUSLY before the reader's `ready()` (a race fix — see below).
- **UX:** leading result card auto-expands (8 lines) + a circular "trust ring" (`lib/services/search/search_confidence.dart`, streak + ≥1.5× margin) that AUTO-OPENS when it clearly converges; conservative so ambiguous isnād-only cases (true match often #2) don't mis-open. Results lock behind you (IndexedStack) so Back shows the rest.

**Independent 2-agent review done + all 4 real bugs FIXED (commit 886e9d8):** (R1) hot mic if cancel during the ~1s model-load window → generation counter aborts a superseded start; (C1/C1b) handoff race disposing the engine the reader just grabbed → synchronous invalidate + AsrEngine generation token; (R2) one shared VoiceSearchState fired phantom searches on all 3 tabs + could auto-open the WRONG reader → `_onVoice` no-ops unless its tab is active; (F1) word model leaked resident on search→Home without opening a reader → RootScaffold cancels voice on any tab change. Confidence logic + listener lifecycle + disposal confirmed sound. 228 host tests green.

**⚠️ ENDGAME CLEANUP STILL OWED (documented, NOT done — safe to defer, none blocks use):**
- **Dead phoneme finders:** `DuaFinderState`/`QuranFinderState` (provided in `root_scaffold.dart`) + `HadithFinderState` (provided in `main.dart`) are no longer read by any live search path. `hadith_reader_screen.dart`'s `_onFinder`/`_finder` block is dead (pick never fires). `lib/widgets/hadith_mic_bar.dart` is referenced nowhere. Remove these + `lib/state/{dua,quran,hadith}_finder_state.dart` + their orphaned tests (`test/{dua_finder,hadith_finder,hadith_finder_replay,quran_finder}_test.dart`). CAUTION: removing the HadithFinderState provider requires also deleting the reader's `_onFinder` read or it crashes — do it together, then device-test a hadith reader open.
- **Stale docstrings:** the 3 list-screen class docs + `root_scaffold.dart:19-23` still describe the old finder flow.
- **Debug spike:** `debug_log_screen.dart` has two "Word ASR" buttons + its OWN `WordAsr` (a 2nd 125MB instance when tapped, dev-gated). Keep as a dev tool or strip before store.
- **Triplication:** the ~60-line voice-search shell (`_onVoice`/`_onSearchChanged`+confidence/`_toggleMic`/`_open`) is copy-pasted across the 3 list screens and has ALREADY drifted (the `loading:` guard differs per screen). Factor into a shared mixin/controller.
- **APK size:** ~200MB of models now (69MB phoneme + 125MB word). Accepted per "accuracy over size" but flag before store submission.
- **License:** FastConformer model card self-contradicts (npl-1.0 header vs CC-BY-4.0 body) — re-check current HF page before shipping; CC-BY-4.0 would be commercially OK (better than the phoneme model's non-commercial license).

**Still open from before (unchanged):** device-tune ASR thresholds; Quran backward-read false-green (piece 5); web version (spike WASM); the fawazahmed0 matn-separated dataset swap (composes as isnād/matn BM25 fields later — user rejected forced pre-classification; ONE search over everything).

## SESSION 8 (2026-07-18) — DEVICE-BUG SWEEP + SEARCH-ARCHITECTURE VERDICT

**Repo/deploy state:** GitHub repo created + pushed: `github.com/ShadiAlbatal/sanad` (public). `master` = shippable, 223 tests green. Git LFS tracks `*.onnx/*.gz` going forward (existing blobs NOT migrated — deliberate; `git lfs migrate import --everything --include="*.onnx,*.gz"` + force-push whenever worth it). Known cosmetic quirk: `git status` always shows the 3 large binaries as "M" (LFS filter display artifact, not real changes — ignore). Site deployed by user to Cloudflare (build cmd empty, output `public`, root `site`).

**Device bugs found via log-driven debugging and FIXED on `master` (all from real pulled logs, `pulls/run_*`):**
- **Tap-to-open hang (THE "app is unusably slow" bug):** tapping a surah/hadith/du'ā did nothing for seconds, then opened INSTANTLY on any stray swipe — USER found the swipe clue. Cause: `_open()` defers `Navigator.push` into `addPostFrameCallback`, but bare-GestureDetector cards paint nothing on tap → no frame scheduled → callback never fires until unrelated input forces a frame. Fix: `WidgetsBinding.instance.ensureVisualUpdate()` after registering, all 3 list screens. The readers/indexes were never slow — thread was IDLE, not busy.
- **Hadith follow-along dead:** finder→reader hand-off fired an un-awaited `mic.stop()` that killed the reader's freshly-started stream. Fix: `MicSource` serializes start/stop on a promise chain. Confirmed working in device log (28 words greened, anchored).
- **Dua finder never confident:** `_minQueryLen=12` let short generic openings fold false tied peaks (3 unrelated du'ās at 0.69) into best-ever, permanently blocking the real match's margin (1.13 < 0.69+0.5). → 20.
- **Short hadiths structurally unpickable:** hadith `_minQueryLen=40` > entire phonemization of short matns (hadith of intentions = ~29 tokens, scored 1.57/margin 0.71 but could never reach the gate). → 20.
- **All four footers clipped behind Android nav bar** (SearchListScaffold + 3 reader footers): explicit `viewPadding.bottom`/keyboard inset instead of SafeArea. Also removed idle-prompt line; footer = search field + mic in ONE row (mic right, thumb-reachable).
- **Curl-view crash on close:** `late final _anim = AnimationController(...)` initialized lazily — first ACCESS could be `dispose()` → Ticker built on deactivated element. → eager in initState.
- **Voice results vanish on mic stop:** each list tab now caches last voice candidates (`_voiceCache`) until a new recitation or typed query.
- **Continue-reading rebuild churn:** Home rebuilds on every tab switch; cards re-created their corpus-load Future each build → FutureBuilder reset each switch. → id-keyed stateful `_ResumeCard`, future built once.
- Also: per-tab Continue Reading cards (Quran/Dua/Hadith, `lastDuaId`/`lastHadithId` in prefs), Explore tiles removed (Counter kept), double-tap push-stacking guard (`_opening`), `run_eval.ps1` pkg fixed to `com.sanad.sanad`, readable collapsed-phoneme traces (`collapsed window`/`collapsed tail`) for word-by-word debugging.

**SEARCH-ARCHITECTURE VERDICT (measured, decision made):**
- **User's core complaint:** hadith voice search feels wrong vs Quran. Diagnosis from logs + corpus: NOT an algorithm bug — isnād ambiguity is real (e.g. recited chain عبد الله بن مسلمة عن مالك عن ابن شهاب عن سالم appears VERBATIM in Bukhari #582/#693/#1480/#1552; a 4-way tie is the CORRECT answer). Quran works because verse openings are near-unique; isnāds are the norm-repeated case. User WANTS Google-style cumulative word search: say عن أبي هريرة → all his hadiths, add words → narrow, highlight. Rolling-window phoneme similarity structurally cannot do that.
- **Option C prototype (phoneme→word lexicon→BM25) BUILT + MEASURED** on branch `feature/word-search-from-phonemes` (`lib/services/search/phoneme_word_lexicon.dart` + `phoneme_word_segmenter.dart` + test; 63,742 words / 65,897 seqs from the 3 corpora's own word maps; Viterbi DP segmenter). Results: **clean phonemes 96–100% word recovery — but at realistic ~12% PER (the phoneme model's real-voice error) recovery COLLAPSES to 62–75%** (compounding). Latency p50 167ms/max 352ms per accept() vs ~80ms live budget (2–4× over). Streaming-consistency test FAILING (incremental ≠ all-at-once). Three measured walls ⇒ **Option C rejected for live use; phoneme approach exhausted for search** (fine for follow-along, which stays phoneme-based EVERYWHERE — closed decision).
- **NEXT: FastConformer transcribe-to-text path** (HANDOFF line ~148's documented fallback, user's own two-model proposal): word-level ASR **4.13% WER on real voice** (vs ~64% effective word accuracy through the phoneme pipeline) → transcript → existing BM25. Search doesn't need streaming; transcribe on pause/stop. Phoneme model takes over for follow-along once a doc opens (sequential handoff, NOT parallel — load word model on search open, dispose on reader open; avoid both inferring at once). **User gate: test everything current BEFORE bundling a second model — that testing is now DONE (numbers above). Immediate next step: locate the FastConformer model from the ZikirAi evaluation, check size/quantization/on-device load time+memory, THEN decide bundling.** Caveat from old benchmark: 4.13% WER is Quran-tuned; hadith WER (narrator proper nouns) unmeasured.
- Dataset swap (fawazahmed0 matn-separated) still parked; composes later as isnād/matn BM25 fields, not needed for the model decision. User explicitly rejected forced isnād/matn pre-classification — ONE search over everything; BM25's IDF handles common-word down-weighting naturally.

## SESSION 7 (2026-07-17) — RENAME DONE: TilawaAi → Sanad
**NAME PICKED: Sanad** (سند). Rename cascade complete across app + site:
- `pubspec.yaml` name `sanad`; Android `applicationId`/`namespace` `com.sanad.sanad` (was `com.tilawa.tilawa_ai`), `MainActivity.kt` moved to `android/app/src/main/kotlin/com/sanad/sanad/`, manifest label "Sanad"; iOS `CFBundleDisplayName`/`CFBundleName` + bundle IDs in `project.pbxproj` → `com.sanad.sanad`(`.RunnerTests`), mic-usage string reworded.
- All `package:tilawa_ai/...` imports (38 test files + lib/tool) → `package:sanad/...`. Stale `build/` wiped (was baking the old package name into merged manifests).
- In-app strings (home title, settings About card + "Help improve", licenses page, debug log header, privacy screen copy, `MaterialApp.title`) → Sanad. `TilawaApp` class name and internal identifiers left as-is (cosmetic, not user-visible).
- Site (`site/public/{index.html, ar/index.html, privacy.html, delete-account.html}`, `site/README.md`, `site/wrangler.toml`): brand strings, canonical/OG/hreflang URLs (`tilawa.ylensolutions.com`→`sanad.ylensolutions.com`, app CTA `app.tilawa...`→`app.sanad...`), `tilawa_lang` localStorage key→`sanad_lang`, CF Pages project name `tilawa-site`→`sanad-site`. Arabic page: brand mentions → سند, but generic uses of "تلاوة" (the common noun "recitation") were carefully left/restored as تلاوة — do not blanket sed التلاوة/تلاوة, only brand-context occurrences.
- **NOT renamed (needs your call):** the repo/working-directory folder itself is still `TilawaAi` (didn't rename mid-session while working in it — safe to do separately, e.g. `git mv`/folder rename + update any absolute-path references, or just leave it — folder name isn't user-facing). `HANDOFF.md` body below this point is historical log and still says "TilawaAi" throughout — left alone as a record, not live config.
- **Still open:** domain `sanad.ylensolutions.com` isn't provisioned yet (DNS/Cloudflare routing) — the site config now points at it but nothing resolves until you set it up; verify `com.sanad.sanad` doesn't collide with an existing Play Console app before first upload; commit + deploy still pending your go (see PENDING DECISIONS below, now down to #2 and #3 — naming is resolved).

## ⭐ SESSION 6 (2026-07-17) — RESUME HERE (search + unified-UX build)
This session: shipped voice-driven **Hadith search**, fixed device bugs, ran a phoneme-vs-word benchmark, and **completed (HOST) a unified search/UX overhaul across all tabs** (pieces 1-4 + 3b all done + reviewed; piece 5 = device-tuning TODO). **STATUS: unified-search build is HOST-COMPLETE** (all 3 tabs = list + shared footer + global voice+typed search + matched-word highlight + follow-along everywhere; Quran nav-flipped to global). **223 tests, host-complete + polished** (highlight nwAlign windowed via localize-then-window, ~90× smaller worst-case, output byte-identical — verified). Remaining: (5) backward-read false-green = device-tuning TODO (see piece-5 diagnosis below); user device-test the whole build (`run_eval.ps1`). MARKETING WEBSITE ✅ DONE at `TilawaAi/site/` (static, deploy-ready for Cloudflare Pages, matches agenda-v2/chatnotes pattern): `wrangler.toml` (name=tilawa-site, [assets] dir=public, SPA fallback) + `public/{index.html EN, ar/index.html RTL, privacy.html, delete-account.html trilingual, favicon.svg, _headers, _redirects}` + README. Cream+emerald design, pure-CSS mushaf hero mockup, tri-collection follow-along (Qur'an+Adhkār+Hadith) messaging explicit, app CTAs→`app.tilawa.ylensolutions.com`, marketing canonical=`tilawa.ylensolutions.com`. DEPLOY: `cd site && wrangler deploy` (or CF Pages, root=`site/`). USER FILLS: support emails (`support@`/`privacy@ylensolutions.com`), real Play Store URL at launch, confirm app subdomain live. Legal URLs app hard-links: `/privacy`, `/delete-account`. **SITE REVISION DONE (2026-07-17):** bespoke theme (parchment/ivory + deep emerald-teal + GOLD + 8-point-star Islamic motifs + gold dividers; Cormorant Garamond headings, Amiri for Arabic/mushaf) — no longer a SnapNote clone; THREE animated phone mockups side-by-side (Qur'an=Fātiḥa, Duʿā=Hisn waking supplication, Hadith=hadith of intentions) with follow-along greening + reduced-motion fallback; THREE explicit per-collection cards (Qur'an/Adhkār/Hadith) + 2 shared trait cards. EN+AR done, verified clean. **NAME CANDIDATES OFFERED (2026-07-17, user considering, no pick yet):** all riff on Arabic root ت-ل-و (talā = "to recite" AND "to follow" — the app's exact function). Top 3: **Talaqqī** (تلقّي — oral-transmission recite-and-correct, most precise fit), **Sadā** (صدى — "echo/resonance," cleanest brand, fits the gold/emerald site aesthetic), **Tālī** (تالي — "the one who recites/follows," short/on-root). Also considered: Rattil/Iqra (AVOID — Tarteel-adjacent/oversaturated, competitor-confusion risk), Wird, Sanad (hadith/isnad angle). Next: user picks → quick-check domain/Play-Store/trademark availability → rename cascade (site branding, domain, repo, app) → commit → deploy.

**WEB VERSION — asked about, not started.** Flutter Web is feasible for READ+BROWSE+TYPED-SEARCH (pure Dart, ships fast) — could live at `app.tilawa...`, matches the site's existing "open web app" link. **VOICE/recite-follow on web is UNPROVEN**: the engine is native FFI (sherpa-onnx C++/ONNX), needs WASM (sherpa-onnx-wasm or onnxruntime-web) + browser mic→PCM pipeline + a ~73MB model download in-browser — real, unvalidated engineering. RECOMMENDATION (not yet executed): spike sherpa_onnx web/WASM support + browser inference feasibility FIRST before committing to full voice-on-web; ship read/browse/typed-search-only web as the safe fallback if WASM doesn't pan out. Not started — do after naming/deploy settles, or whenever user wants the spike run.

**PENDING DECISIONS (block repo+deploy):** (1) USER CHANGING THE APP NAME — cascades to site branding + domain + repo name; site is currently branded "TilawaAi"; rename everything once decided. (2) GIT: app folder is a local git repo but the ENTIRE session's work is UNCOMMITTED — commit after the rename. Can't create/push a GitHub remote (no GitHub auth) — user does that, or deploy without a remote. (3) DEPLOY: no separate CF connection; `wrangler` is likely already authed on this machine (agenda/snapnote deploy from here) → `cd site && wrangler deploy` should work; deploying PUBLISHES → only on user's explicit go, after name+repo settled. ORDER: name → rename+commit → deploy. Full details in the sections below (search "UNIFIED UX BUILD", "DEVICE RE-TEST RESULT", "BENCHMARK RESULT") + memory (`hadith-search-feature`, `hadith-quran-datasets`, `asr-matcher-cursor-contracts`, `feedback-*`).

**Shared search engine (DONE):** `lib/services/asr/phoneme_finder.dart` (IDF 3-gram prefilter K=50 → PhonemeLocalizer rerank, `decideFindBest` = best-ever peak + dup-collapse + margin-primary/floor). Powers Hadith (12,370 Bukhari+Muslim, `assets/asr/hadith/corpus.json.gz`) AND Dua (259 Hisn al-Muslim, `assets/asr/dua/corpus.json.gz`). Calibrated on real device logs: floor 0.9 / margin 0.5 / streak 3.

**Device bugs FIXED (need on-device re-confirm):** (1) dua search returned empty = `<blank>`-vocab off-by-one in the packer → FIXED; (2) Quran page-render FREEZE (title/page updated, text stuck) = `_PageContentState` stale `_future`, fixed with `didUpdateWidget` re-fetch; (3) retrieval calibration (IDF/floor/margin/best-ever/dedup). Base build the UX pass sits on.

**BENCHMARK verdict (150 real hadith voices):** phoneme vs transcribe-to-text (fastconformer, 10.6% WER) → **hybrid, not replacement.** Top-1 tied; text/BM25 wins top-5 + short/partial. → keep phoneme for voice auto-pick, ADD **typed BM25 text search** (built). On-device voice→text deferred. NW-matcher lost to BM25 for retrieval.

**UNIFIED UX BUILD — pieces (each subagent-built + reviewed):**
- (1) ✅ shared `SearchListScaffold` (list + footer: mic/status/heard/search-bar) on Dua+Hadith; hadith empty-list fixed.
- (2) ✅ typed BM25 search (`text_search.dart`) + matched-word highlight (`highlighted_arabic.dart`) + keyboard-lift + loader dedup.
- (3) ✅ DONE + REVIEW-PASSED — Hadith follow-along. Repacked `assets/asr/hadith/corpus.json.gz` (9.2MB, KEEPS words+phonemeToWord), `hadith_corpus.dart` per-hadith clip, `lib/state/hadith_reading_state.dart` (mirrors DuaReadingState), `hadith_reader_screen.dart` follow-along + voice-jump, `corpus_text_search.dart` loader-retry fix, `test/hadith_clip_test.dart`. Review: decode fidelity manually verified byte-exact vs `hadith_out/combined.json` (12,370 docs), find-path intact, mic handoff sound, non-destructive. 202 tests. NON-BLOCKING cleanup: strengthen `hadith_clip_test` fidelity assert (currently self-referential — data is correct but test can't catch a future off-by-one; needs a real fixture).
- (4) ✅ BUILT (4a+4b), host-verified (214 tests), UNDER REVIEW. **(4a)** `quran_corpus.dart` + `quran_search.dart` (`QuranSearch`: global voice+BM25-text over 6,236 verses from bundled `quran_phonemes/*.json`, NO new asset; verse phonemes are STRINGS = no `<blank>` bug risk) + `quran_search_test.dart`; verse-own-span retrieves top-1 globally. **(4b) NAV FLIP:** Quran TAB → `quran_list_screen.dart` (shared scaffold: 114-surah browse + typed BM25 + voice via new `quran_finder_state.dart`); READER (`quran_screen.dart`) → PUSHED route (from list/Home/Continue), reader internals UNTOUCHED (only added footer/back/dispose-mic-stop; freeze-fix + last-page intact); `root_scaffold` tab2→list, provides Dua+Quran finders, tab-away/bg now stops `QuranFinderState`; `home_screen` tile/Continue → reader at lastPage. ReadingState already app-wide → no provider-scope change. **REVIEW-PASSED:** suspected bg-mic gap is NOT a gap (RootScaffold stays mounted under the pushed reader; its lifecycle handler stops ReadingState app-wide AND the finders — both pop-path `dispose` + bg-path covered); provider scope fine; mic handoff clean; reader internals + freeze-fix untouched; nav correct; 214 tests. **→ Quran tab now genuinely GLOBAL + identical to Dua/Hadith = CORE REQUIREMENT MET.** Device-only note: curl-swipe vs back-swipe edge feel on Android.
- (5) 🟠 DIAGNOSED, NO SAFE HOST FIX → DEVICE-TUNING TODO (no code changed). Root cause is NOT a head-behind-frontier leak (the "head-gate" fix is a proven NO-OP — head is always AT the frontier on advance). REAL cause = **repeated-phrase / residual-audio forward-latching**: re-reading a phrase that shares phonemes with a FORWARD word (ubiquitous: الله/الرحمن الرحيم) → windowed `nwAlign` latches the audio onto the forward duplicate's ref (`phoneme_matcher.dart:157-160`), bumps `frac`, `_head`=max-matched-ref (`:175-179`), frontier advances (`:246`), greens the forward word. Every host-side matcher-only fix fails (localizer pos structurally lags reached 2-5w even in clean forward → can't threshold; clamping `_head` fixes marker not green; the clean nwAlign tie-break fix is in the device-tuned localizer file). GENUINE fix needs trajectory-aware disambiguation (prefer backward copy when recent motion is backward) — DEVICE-TUNED, validate via `run_eval.ps1` + messy-recording fixtures. Candidate directions: (a) withhold frontier advance the chunk `_head` jumps forward vs the robust `_lastReloc.word` (sweep margin on device); (b) damp `_wordBestFrac` during a backward re-read. Prototype behind tuning consts + device-sweep before merge.
- (3b) ✅ DONE — voice-word highlight on all 3 tabs. `FindDoc` now carries the word map (words+phonemeToWord); `PhonemeFinder.matchedWordIndices(id, query)` nwAligns the collapsed query vs a candidate's phonemes → matched ref phonemes → word indices; `matchedDisplayWords` (text_search.dart) normalizes those to the same `Set<String>` HighlightedArabic/typed path uses. Each finder state exposes `matchedWords(id)` for the shown candidates (top ~5 only); Hadith/Quran/Dua list screens pass it to their cards. DUA now ALSO renders the candidate list while reciting (was browse). Dua FIND corpus repacked WITH the word map: `assets/asr/dua/corpus.json.gz` 6→8 cols, 259 docs, 64→92 KB (tool/repack_dua_corpus_wordmap.py, from existing clips, phoneme-int fidelity + round-trip asserted; build_dua_corpus.py updated so future rebuilds keep it). Test: test/voice_highlight_test.dart. 222 host tests. Device-pending: live-mic highlight + nwAlign per-probe latency on long matns.
- (4) ⬜ Quran NAV FLIP: Quran tab → the list (adopt scaffold); Home Quran button → last page.
- (5) ⬜ FIX: Quran backward-read false-greens 1 word ahead (matcher GRACE); + polish.

**Target UX (user-confirmed):** all 3 tabs identical = content LIST + shared FOOTER; GLOBAL search per tab (voice OR typed); match→open-direct / else→candidate-list-with-highlighted-matched-words; once opened→FOLLOW-ALONG on everything incl. Hadith.

**Roadmap after the 5 pieces:** evaluate & swap hadith data to `fawazahmed0`/`freococo-650k` (matn-separated + narrator + CC0) as a SEPARATE step; then **isnad/narrator SEARCH** layer (metadata, not phoneme) on that data. Optional: audio-derived phonemes to raise the voice ceiling.

**Host tests green (198+ before piece 3). Device-pending:** live mic flows, on-device keyboard lift, real-voice accuracy. User builds APK + tests on device (`run_eval.ps1` → recite → press **`s`** → pulls logs to `pulls/run_*`; ignore the red adb stderr = cosmetic).

---

# TilawaAi — Handoff (2026-07-16, session 5)

## CURRENT STATE (top of session 5, 2026-07-16)
- **Repo is now git-initialized + committed** (`743dbed`, branch `master`, initial commit, 1098 files). No
  remote yet — CI (`.github/workflows/ci.yml`) is inert until a GitHub remote is added. Commit author is set
  LOCALLY (this repo only) to `shadialbatal1993@hotmail.com`; the global git config (a work email) was left
  untouched. History was rewritten once to scrub a work email that git had auto-stamped — 0 traces remain.
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

## UNIFIED SEARCH + FOLLOW-ALONG ARCHITECTURE — roadmap (2026-07-16)
All 6 features (Quran/Dua/Hadith × find + follow) are ONE operation with 3 knobs: **speak → phonemes → localize against a candidate set → act on the match.** Knobs: (1) candidate set (this page / all Quran / this dua / all duas / all hadith); (2) contract — *follow-cursor* (in a known text, marker tracks you, backward-tracking) vs *find* (identify which text, forward-only); (3) UI action (move cursor / turn page / navigate+open / show candidate list).

**CURRENT-STATE FACTS (verified in code 2026-07-17 — corrects an earlier overstatement).** The app has **NO global voice search on any surface today.** Quran reader matches ONLY the current surah (`reading_state.dart` loads one `loadSurahClip` at a time); its "cross-surah reacquire" is real but bounded to **±5 surahs** (`_reacqNeighbourhood=5`), fires only on stall (3-probe confirm) — NOT global (this is why reciting p100 content while on p343 doesn't jump: >5 surahs away, never in reach). Dua LIST finder searches all **5** duas (the only "search across a set"); dua READER follows the single open dua, no jump. All 114 Quran surah phoneme files ARE bundled (`assets/asr/quran_phonemes/`), so global Quran search is data-possible, just not wired. → The Hadith tab (global find over 7008) is the FIRST true global search = a NEW capability + the template to unify toward. UNIFY = give Quran a global `PhonemeFinder` over all 114 surahs' verses (recite anything → find verse anywhere → jump → existing follow-along resumes; the n-gram index is what makes 6000+ verses fast) and make the dua finder reachable from inside the reader. Same engine, one corpus each, differ only in post-landing (Quran/Dua follow-along; Hadith static).

**CORE REQUIREMENT (user, 2026-07-17): GLOBAL search over the FULL corpus in EVERY tab — effective, not partial, not "fake."** Each tab (Quran/Dua/Hadith) must search its ENTIRE corpus, not a window/fragment, and must RELIABLY return the right result (a global search that returns wrong results = "fake"). Status: Hadith (12,370) ✅ + Dua (259) ✅ already search full corpus on the shared `PhonemeFinder`. **QURAN is the gap** — still uses the bounded ±5-surah reacquire (partial), NOT the shared engine. FIX = put Quran on the shared engine over ALL 114 surahs' verses (phoneme data already bundled) → recite anything → locate verse ANYWHERE → jump → follow-along resumes. "Effective not fake" has 2 parts: COVERAGE (engine delivers) + ACCURACY (the benchmark/audio-phoneme work) — make it effective BEFORE wide. SEQUENCE: benchmark decides pipeline (phoneme vs transcribe-to-text) FIRST → then unify ALL tabs incl. Quran-global on the chosen pipeline (build once, don't wire Quran-global onto phoneme then rip out if transcribe-to-text wins).

**UNIFIED UX BUILD (confirmed by user 2026-07-17) — realizes "unite the UI" too.** ALL 3 tabs identical UI = content **LIST** + shared **FOOTER** (mic + status + "hearing" ticker + **text search bar**). **GLOBAL search per tab, voice OR typed.** Result: confident match → **open direct**; else → candidate **LIST with matched words HIGHLIGHTED**. Once opened → **FOLLOW-ALONG on everything incl. HADITH** (NEW — was find-only). **Nav flip:** Quran TAB → the list (adopts the scaffold); Home Quran button → last page. **Fixes:** Quran backward-read false-greens 1 word ahead (matcher GRACE fix); hadith reader now follows. **DEPENDENCY:** hadith follow-along needs the per-hadith word↔phoneme map (words+phonemeToWord) that was DROPPED from the find corpus → rebuild hadith corpus keeping it. **Benchmark-informed:** add TYPED BM25 text search (won top-5 + short/partial on 150 real voices; use FULL-fragment BM25 not 2-keyword; NW lost — see [[hadith-search-feature]]). **SEQUENCE (each subagent-built + reviewed):** (1) ✅ DONE+reviewed — shared `SearchListScaffold` list+footer on Dua+Hadith (hadith empty-list fixed); (2) ✅ DONE+reviewed — typed BM25 text search (`text_search.dart`) + matched-word highlight (`highlighted_arabic.dart`) + keyboard-lift + loader dedup; voice match→open/candidates unchanged; (3) �driving — Hadith corpus rebuild (KEEP word map, CURRENT data — NOT fawazahmed0) + follow-along reader (`HadithReadingState` mirrors DuaReadingState) + loader-retry fix; (3b) voice-word highlight (needs finder to expose word-level match, now possible w/ word map); (4) nav flip (Quran tab→list adopts scaffold, Home→last page); (5) fixes (Quran backward-read false-green + polish). **REFINED: fawazahmed0 matn/narrator swap is UN-BUNDLED from piece 3 → its own evaluated step AFTER follow-along works (don't entangle a data-source change with a new feature); isnad/narrator SEARCH = later layer on that data.** Built on the bug-fix build (dua-returns ✅ + quran-freeze-fixed ✅, device-pending final confirm). Host tests: 198 pass.

**Principle: unite the ENGINE, not the BUTTON.**
- UNITE → one background ASR worker + one localizer/n-gram-index retrieval core. (This is Plan B's real target — the shared core is the *retrieval engine*, not just "common plumbing.")
- DON'T UNITE → the two contracts. Follow-along and Find are different jobs; keep them as two thin modes over one engine (this is Plan B's own "if a step forces them to be the same when they aren't, STOP").
- BUTTON → per-domain search first; the global "speak anywhere" cascade is a cheap v2, not a prerequisite.

**Cascade (the "Quran-in-page then broaden" idea): belongs to Find mode, gated by intent.** While READING, bias hard to the current text (a shared word must not yank you into a hadith — passive follow-along is NOT a cross-corpus search). On EXPLICIT search, cascade current-context → domain → cross-domain, heavily context-weighted, disambiguation list on ties.

**3 layers:** (L1) Engine: worker → phonemes → localizer + n-gram index, one code path. (L2) Modes: FollowAlong(candidates=current text, cursor+backward) / Find(candidates=corpus/cascade, forward-only, ranked). (L3) Domains: Quran/Dua/Hadith each supply {corpus phonemes+index, reader UI}, plug into modes.

**Sequencing = GREENFIELD-FIRST (lowers risk vs extracting the core out of 3 live states):** build the shared retrieval core fresh in Hadith (nothing to break; Hadith is mostly Find anyway — no tajwīd recitation), prove it on device, THEN migrate the 3 live states onto the proven core.
- **Phase 0 (host, BUILT + under hardening):** `tool/build_hadith_phonemes.py` + domain-agnostic Dart retrieval core (`lib/services/asr/phoneme_finder.dart`: `FindDoc`, `PhonemeFinder` = 3-gram prefilter K=50 → `PhonemeLocalizer` SW rerank, `decideFind` floor=1.2/margin=0.4 from DuaFinderState) + host test (`test/phoneme_finder_test.dart`, 500-doc fixture). This IS L1's Find path. Adversarial review (2026-07-16): core sound, claims honest (96% top-1 / 100% top-5 @10-word verified; 4% misses = real shared-boilerplate near-dup matns, `decideFind` correctly declines on those ties). **Constraints for Phase 1 wiring:** (a) ENFORCE a min query length — top-5 falls 100%@10w → 94%@6w → 82%@3w, so the live mic must gate on ≥~8-10 words; (b) `decideFind` has NO streak guard (unlike DuaFinderState's `_confirm=3`) — the live caller must accumulate a STABLE query, not feed raw tail snapshots, or a single spurious high-margin frame commits a wrong pick; (c) K=50 CONFIRMED at scale. **Phase 0 ACCEPTED 2026-07-16.** Full 7008-doc Bukhari validation (`test/phoneme_finder_scale_test.dart`, `@Tags(['scale'])`, corpus in scratchpad only): top-1/top-5 by query length = 6w 66/79, **10w 84.5/94**, 15w 94/99; noisy ~11% @10w = 83/94; latency mean 56ms / p95 77 / max 88 (live-viable); index build 2.9s / ~16MB. Real numbers are BELOW the optimistic Python proof (100% top-1 @10w) — the proof used exact-token match; the real engine uses the fuzzy `PhonemeLocalizer` (sim≥0.75). **Diagnostic: prefilter recall@50 = 98.5% @10w but top-5 accuracy = 94% → the true doc is almost always IN the candidate set; the RERANK mis-ranks it. So K=50 is right (raising K won't help); the headroom is the rerank scorer, NOT the index.** DECISION: do NOT tune the reranker now — the real gate is on-device acoustic accuracy against an unknown error profile; tuning vs simulated PER risks the wrong target. Sequence: accept → Phase 1 → learn real acoustic accuracy on device → then tune rerank vs real data if needed. Min query: gate auto-open at ≥15 words (94/99); ≥10 usable; <6 unusable. Re-run the scale harness on the combined Bukhari+Muslim (~15k) before shipping Muslim; cheap lever if recall dips is K=75-100.
- **Phase 1 step 1 DONE + ACCEPTED (2026-07-17):** data layer. `assets/asr/hadith/bukhari.json.gz` (2.62MB gz / 14MB int-encoded / 21MB naive-strings; all 7008 Bukhari, `[number, text, [phoneme_ints]]`), `tool/pack_hadith_corpus.py`, `lib/services/asr/hadith_corpus.dart` (`loadHadithCorpus()` → `HadithCorpus{docs, byId}`), `lib/services/asr/hadith_search.dart` (`HadithSearch.find(queryPhonemes)` → `{pick, candidates}`), `test/hadith_search_test.dart`. Review verified the int↔unit round-trip is FAITHFUL (decoded == true ASR unit strings, no off-by-one — the on-device-breaking bug is ruled out) and the corpus is clean (0 dup numbers/empty fields). NOTE: size ≠ concern — user cares about accuracy + real functionality ([[not in repo, see memory]]). **CARRY-FORWARDS into step 2:** (i) `loadHadithCorpus`+`PhonemeFinder` build run synchronously on the calling isolate (gunzip+14MB parse+7k FindDoc collapse+index) → MUST wrap in `Isolate.run`/`compute` when wired to the tab or it janks on open; add `Log.*` coverage; (ii) TIGHTEN `HadithSearch` `margin` 0.3→≥0.4 (review: 0.3 is looser than dua's 0.4 on a MORE isnād-repetitive corpus → over-eager confident auto-open of near-tie hadith; scale is otherwise consistent with dua, floor=2.0 defensible); (iii) the 98%/94% host numbers are PLUMBING, not accuracy (queries are clean corpus slices) — real accuracy = the device test.
- **Phase 1 step 2 BUILT + REVIEW-PASSED (2026-07-17) — DEVICE-PENDING.** Hadith tab (4th tab) + live mic, mirrors Dua finder. Files: `lib/state/hadith_finder_state.dart` (claims shared mic, streams phonemes, pure `decideHadithPick` = min 40 collapsed phonemes ~10 words + `_confirm=3` streak), `lib/widgets/hadith_mic_bar.dart`, `lib/screens/hadith_search_screen.dart` (tappable candidate cards, never dead-end), `lib/screens/hadith_reader_screen.dart` (matn + "Bukhari #n", mic in footer to voice-jump), `loadHadithSearch()` (off-thread `Isolate.run` load), + `app_state.dart` `Tabs.hadith=3`, `main.dart` (app-wide provider — REQUIRED: reader is a sibling route outside the tab subtree), `root_scaffold.dart` (4th tab, stop-on-tab-away/background), `test/hadith_finder_test.dart` (8 tests). `flutter analyze` clean, 150/150 tests pass, no Quran/dua regression. Adversarial review VERIFIED safe: shared-mic claim/release correct on all exit paths (no leak/starvation of Quran/dua mic), Isolate.run boundary clean (only sendable data crosses), pick single-consume via `ModalRoute.isCurrent` guard, streak guard can't commit on one spurious probe. **Thresholds are STARTING POINTS needing on-device tuning:** `floor=2.0`, `margin=0.4`, `_minQueryLen=40`, `_confirm=3`. **LOW follow-ups (non-blocking):** (i) `_loading` caches a rejected future → mic-retry won't rebuild (near-impossible, asset is bundled); (ii) narrow tab-leave race can push reader over Home (du'a finder has the identical window — fix both or neither); (iii) `preload()` unawaited rejection logs to zone handler. Device-test = last Hadith risk + real acoustic error profile to tune reranker (recall@50 98.5% vs top-5 94% headroom).
- **FIRST DEVICE TEST DIAGNOSED (2026-07-17) — NOT fundamental, 4 fixable causes.** Logs `pulls/run_20260717_011836/logs/run_20260717_01*.log`. Hadith never auto-picked; full log analysis found the phoneme approach WORKS (same session: dua finder matched at **1.88/3.0 ~80% token align**; Quran greened words, REACQ 1.75) → text-G2P phonemes DO match the real model. **Real device per-token ceiling ≈ 1.7–1.9, NEVER ~3.0** (simulated proof was optimistic). Hadith failed for 4 hadith-specific reasons: (1) **floor=2.0 is ABOVE the ~1.9 ceiling** (`hadith_search.dart:42`) — nothing can pass; dua works only because its floor=1.2 (`dua_finder_state.dart:52`). **#1 lever.** (2) one recitation was **Sahih Muslim 54** («لا تدخلوا الجنة حتى تؤمنوا…أفشوا السلام»), corpus is **Bukhari-only** (`hadith_corpus.dart:8`) → guaranteed miss. (3) the other («من كان يؤمن بالله واليوم الآخر…» = Bukhari #5559…) truncated — mic silence-gating reset before `minLen=40`. (4) **isnad IS stored** in each doc (`build_hadith_phonemes.py` phonemizes the whole CSV col incl. «حدثنا…عن…») → 3-gram prefilter clusters on isnad boilerplate (scattered adjacent near-ties #2187/2188/2189 @0.45). NO clean in-corpus full-hadith trial yet (predicted correct-match score ~1.5–1.9). **FIX PLAN:** (a) floor 2.0→~1.3 + rely on margin/streak [cheap, primary]; (b) matn-only corpus (strip isnad before phonemize/index) [medium]; (c) add Sahih Muslim [medium]; (d) fix capture/VAD so recitation isn't chopped + render candidate LIST even below minLen (never-dead-end), gate only auto-PICK on length [cheap]. Re-test → next log's real in-corpus scores finalize the floor.
- **FIX BATCH APPLIED (2026-07-17) — host-verified + REVIEW-PASSED, ready for device re-test.** (Review confirmed: String-id nav correct, no cross-collection collision, isolate load sound, never-dead-end intact, ~20ms latency — safe.) (a) **IDF-weighted prefilter** (`phoneme_finder.dart`: raw 3-gram count → `log(N/docFreq)`) — isnad-robustness test (distinctive matn buried behind the most-common isnad prefix, the device failure mode): top-5 **58.8%→91.5%** (Bukhari), recall proven NON-regressed. (b) floor 2.0→**1.3** (`hadith_search.dart`, provisional). (c) **Sahih Muslim added** → combined `assets/asr/hadith/corpus.json.gz` (12370 docs = 7008 Bukhari + 5362 Muslim, 4.77MB gz; old `bukhari.json.gz` removed); ids collection-qualified (`bukhari:2790`/`muslim:54`), `HadithEntry`/`HadithCandidate` carry `collection` + `Bukhari #n`/`Muslim #n` label; pick/nav identity migrated int→String. (d) candidate list confirmed always-rendered (never-dead-end); capture/VAD deliberately untouched (device-pending). Combined-scale: top-5 92.5%@10w, latency mean 32ms. 153 tests pass, analyze clean. Device re-test check: recite Bukhari #2790 (الفردوس) → should now surface in the list / auto-open.
- **DEVICE RE-TEST RESULT (2026-07-17, log `pulls/run_20260717_023707/logs/run_20260717_023705.log`, 11 attempts) — IDF FIX VALIDATED, phoneme search VIABLE (no rewrite/transcribe-to-text needed).** Correct hadith ranked #1 in every in-corpus attempt (isnad-crowding GONE); الفردوس content surfaced #1/#2 (it's at `bukhari:2581`/`:6873` NOT 2790 — corpus ids ≠ sunnah.com); `muslim:81` AUTO-PICKED and was CORRECT (verified). Remaining blockers are all CALIBRATION: (1) **floor 1.3 too high** (rejected real #1s at 0.45–1.10; correct partials 0.34–0.60 overlap isnad chance-matches 0.38–0.50) → **make MARGIN the primary gate** (correct #1 leads by 0.8–1.0, noise by 0.05–0.10), drop floor to ~0.9–1.0; (2) **near-duplicate corpus docs** (same matn in multiple books: Firdaws 2581/6873, zakāt 1407/1408/1411) tie & defeat margin → **duplicate-collapse** (cluster by matn, max, margin vs first non-dup); (3) **60-phoneme rolling window DECAYS long recitations** — full hadith (matn+isnad) peaks then decays as window rolls past matn into isnad tail (att4 muslim:81 hit 1.10 then fell to 0.25) → **score on BEST-EVER peak per candidate across the recitation, not current window** (biggest lever; att4 would've picked). Capture OK (att7/9 just short recitations <minLen40). NOTE `fawazahmed0` matn-only swap directly helps (2)+(3). **PLAN: calibration pass (floor↓ + margin-primary + best-ever + dedup) applied to BOTH hadith+dua AFTER the dua-corpus build; then fawazahmed0 matn swap; then UX items.**
- **CALIBRATION APPLIED (2026-07-17) — host-verified, pending review then device re-test.** Shared engine, both finders. Gates: floor 1.3/1.2→**0.9**, margin 0.4→**0.5** (PRIMARY, measured post-dedup over best-ever peaks), minLen/streak kept. Three changes in `phoneme_finder.dart` (`dupKeyOf` FNV-1a hash of collapsed phonemes, `foldBestScores`, `decideFindBest`) reused by `hadith_finder_state`+`dua_finder_state`: (1) **best-ever peak scoring** (per-session `_bestScore` map, reset on `start()`, gated to queryLen≥minLen so short-span chance-scores can't poison it) — fixes the window-decay; (2) **duplicate-collapse** by dupKey before margin (Firdaws 2581/6873 identical matn → one) — EXACT-hash only (near-dup zakāt variants collapse only after the fawazahmed0 matn swap); (3) recalibrated gates. **Replay test** (`test/hadith_finder_replay_test.dart`) feeds the verbatim logged att1–4 scores through the new pipeline: att3+att4 now AUTO-PICK (att4 was silently missed pre-best-ever), att1 noise + att2 Firdaws-dup correctly list-only. `flutter analyze` clean, **177 tests pass**. Dua gates provisional-by-analogy (no dua device capture yet). Next device test: hadith AND dua are both live + calibrated now. **REVIEW-PASSED (2026-07-17) — safe for device re-test** (decideFindBest edge cases sound, best-ever resets per session, mic/readers untouched, shared-not-forked, 177 tests + 7 scale pass). Two non-blocking WATCH-ITEMS for the device test: (i) **DUA false-pick risk** — dua gates are borrowed-by-analogy (no dua device data), minLen=12 is low, best-ever is monotonic + duas are short/confusable → a short dua could chance-match and auto-open the WRONG one; the #1 thing to tune from dua logs (common case is safe-decline→list). (ii) the 3-probe streak is largely SUBSUMED by monotonic best-ever (once qualified it stays; streak just waits 3 probes) — intended (lets att4's decayed peak pick), but floor+margin now do all false-pick protection. Also: `decideDuaPick` mirrors the replay-tested `decideHadithPick` byte-for-byte but dua CALIBRATION has no grounding test (data gap); exact-hash dedup won't collapse near-variant adhkar until the fawazahmed0 matn swap.
- **HADITH/SEARCH UX FEEDBACK (user, from device test 2026-07-17) — do as a UX pass AFTER the dua-corpus build (keep hadith+dua consistent; don't edit the just-reviewed hadith finder mid-test):** (1) **Live-highlight the matching/filtering during recitation** — show the candidate list updating live w/ highlighting so the user SEES filter in/out; AND enhance `[hadithfind]` logging to log the FULL top-K + explicit filter-IN/OUT transitions (currently logs only top-3 per probe — you can infer filtering across lines but it's not explicit). (2) **BUG: back button clears the results** — tapping a candidate → reader → back wipes the list; PRESERVE candidates on reader-open+return, only clear on a NEW recitation start (currently `start()`/stop resets `_candidates`). (3) **Hadith list is EMPTY when idle** (search-first design, no browse) — add a browsable default list (lazy `ListView.builder` over the corpus, load-more), SAME browse pattern as the dua-list expansion → consistent across both search tabs. (4) **LATER: header TEXT search bar** (search-by-typing, complements voice) — easy once the browse list exists.
- **OPEN ARCHITECTURE DECISION — phoneme vs transcribe-to-text for SEARCH (2026-07-17).** Benchmark (ZikirAi): word models (NeMo/Muno459 FastConformer, **4.13% WER**) are ~2–3× more accurate than the phoneme model (**11.63% PER / ~64% acc**). SEARCH does NOT need streaming (that's only for live follow-along), so the word model's offline/segmented nature is fine for "recite → identify" — making **transcribe-to-text (word ASR → Arabic text → fuzzy text search) a likely-stronger foundation for search** than phoneme-vs-G2P matching (the ~1.7–1.9 device ceiling). CAVEATS: (a) 4.13% WER is QURAN-tuned — hadith WER unknown (diff vocab/proper nouns), must measure; (b) ZikirAi DISABLED phoneme+live-mic (native sherpa frame-count crash) — but TilawaAi's device test streamed phonemes live w/o crash, so the Flutter port seems to have solved it (confirm stability). **DECISION (user, 2026-07-17): try the phoneme fix batch FIRST (cheap, in-flight, keeps live-filter feel) — hope it works without a big change. Transcribe-to-text is the DOCUMENTED READY FALLBACK if the re-test disappoints** (A/B on device; possible hybrid = phoneme live-filter while speaking + word-model transcribe for the accurate final pick on stop). Do NOT build the word path yet.
- **DUA WILL EXPAND (user, 2026-07-17):** the 5-dua corpus was a test; dua will grow large. → its brute-force `DuaFinderState` (one localizer per candidate) won't scale; when it grows it must migrate onto the SAME `PhonemeFinder` engine (IDF prefilter → rerank) being hardened for Hadith. Reinforces unite-the-engine: this Hadith work is the shared search substrate for dua-at-scale too (Phase 2 migration).
- **DUA CORPUS EXPANDED + MIGRATED (2026-07-17) — DONE, additive/non-destructive.** 5 → **259 duas** (254 Hisn al-Muslim from hisnmuslim.com API, fully diacritized; sourced/deduped/committed as `tool/hisn_source.json`, phonemized by new `tool/build_dua_corpus.py`, 254 built / 1 OOV / 8 under-diacritized skipped). Assets: per-dua reader clips `assets/asr/dua_phonemes/hisn-N.json` (loadDuaClip unchanged) + combined `assets/asr/dua/corpus.json.gz` (64KB). Finder migrated off the O(N) brute-force loop onto the shared `PhonemeFinder` engine: new `lib/services/asr/dua_corpus.dart` + `dua_search.dart` (`DuaSearch`, off-thread load), `dua_finder_state.dart` now uses `DuaSearch` + pure `decideDuaPick` (public surface preserved), `dua_list_screen.dart` browses the full corpus. Existing 5 clips byte-untouched, `lib/data/duas.dart` untouched, reader intact. `flutter analyze` clean, **163 tests pass**. Device-pending: live-mic tuning (same pattern). → dua+hadith now share the engine, so the calibration pass fixes both.
- **BUG FOUND+FIXED (2026-07-17): dua search returned `top=[]` (empty) on device.** Off-by-one VOCAB bug: `build_dua_corpus.py` packed phoneme ints off a `<blank>`-LESS vocab (`build_dua_phonemes.load_vocab()` drops `<blank>`), but Dart `loadPhonemeUnits()` KEEPS `<blank>` at index 0 → every phoneme decoded one-off → garbage → empty 3-gram index → zero candidates. Fix = pack with `<blank>`-INCLUSIVE line-order indexing (mirror `pack_hadith_corpus.load_vocab_index`; hadith was immune) + regenerate `corpus.json.gz`. **CONVENTION/GOTCHA: any corpus PACKER's int↔phoneme index MUST be `<blank>`-inclusive tokens.txt-line-order to match Dart `loadPhonemeUnits`.** The dua test missed it because it queried with the corpus's OWN self-decoded (garbage) phonemes (self-consistent) → hardened to query with reader-side `assets/asr/dua_phonemes/<id>.json` strings + a decode-fidelity assert. **FIXED+VERIFIED 2026-07-17:** `build_dua_corpus.py` now uses `pack_hadith_corpus.load_vocab_index` (blank-inclusive), asset regenerated (259 rows); decoded all 259 rows == true reader phonemes (the failing check now passes); 182 tests pass. Hadith healthy (tests pass). **QURAN PAGE-RENDER FREEZE — CONFIRMED via 4 device screenshots (2026-07-17), under investigation.** Opening 4 different surahs (An-Nas/604, Al-An'am/128, Ar-Ra'd/249, Al-A'raf/151): app-bar TITLE + footer PAGE-NUMBER update correctly, but the rendered mushaf TEXT stays FROZEN on Al-Mu'minun 23:18–24 (~page 342, where recitation follow-along last auto-navigated). So page-INDEX state advances, page RENDER is stuck — a widget-rebuild / curl-captured-image desync the log can't show (log shows correct settles/captures). No Quran files in the branch diff → likely pre-existing curl bug triggered by recitation-follow, OR indirect rebuild-scope regression from `main.dart` app-wide provider / `root_scaffold` 4th IndexedStack child. Suspects: `curl_page_view.dart` `_jumpTo` early-return `if(page==_current)return` with wedged `_current`, or stale capture-image adoption; `quran_screen.dart` title/footer reading `_page` (updates) vs curl child rendering `_current` (stuck). Repro: recite→auto-follow a page→open a different surah→text frozen. **ROOT-CAUSED + FIXED 2026-07-17 (pre-existing, not this branch):** `_PageContentState` (`quran_screen.dart`) captured `late Future<MushafPage> _future = repo.page(page)` ONCE; curl view keeps leaf State alive via stable GlobalKeys, so on page change the reused State kept its stale resolved future → FutureBuilder showed the old page while title/footer (separate setState `_page`) advanced. Frozen on surah 23 = recitation-follow persisted it as `lastPage`, reader restored there, jumps reused the stale-future State. FIX = add `didUpdateWidget` re-fetching `_future` when `old.page != widget.page` (guarded so marker-tick rebuilds don't thrash). Quran-only, analyze clean, 182 tests pass. **REVIEW-PASSED — SHIP** (no marker-tick thrash: page prop stable across highlight rebuilds; no swipe flicker: cachedPage initialData + bridge bitmap; only stale-future site in lib/ — grep-confirmed; repo.page memoized so re-fetch is cheap). Minor non-blocking: cold far-surah jump shows a blank frame for ~tens of ms before paint (better than frozen wrong page; optional: pre-warm target in `jumpTo`). Device-pending final confirm — repro: recite→auto-follow→open another surah→text updates.
- **DATA UPGRADES found (HF sweep 2026-07-17, see memory [[hadith-quran-datasets]]).** (1) **`fawazahmed0/hadith-data`** — 10 collections, fully diacritized, **isnad/matn already SEPARATED**, CC0 → swap our text corpus to this AFTER the current fix re-test: it solves isnad pollution at the SOURCE (clean matn-only index, no fragile splitter, IDF becomes a bonus not a crutch) + gives multi-collection coverage + cleanest license. (2) **`siddiqiya/ar-quran-hadith14books-MSA`** — the ONLY hadith AUDIO corpus (14 books incl Bukhari/Muslim, ~119h, Apache 2.0, transcripts un-diacritized) → reserve asset: enables audio-derived reference phonemes (fix the ~1.9 text-vs-audio ceiling) + word-ASR benchmark, pull if phoneme re-test underperforms. (3) LICENSE: current phoneme model `Muno459/zipformer_p-quran` is NON-COMMERCIAL (ship-blocker if monetized; matches REVIEW.md); Apache-2.0 alt `MostafaMaroof/wav2vec2-arabic-phoneme-asr` (75-phoneme, non-streaming = re-arch).
- **Observability + device-test tooling (2026-07-17, review-verified).** Atom-level `Log.*` across the recitation/search/mic pipeline → app's EXISTING on-device file sink (`getExternalStorageDirectory()/logs/run_<stamp>.log`, opened via `Log.diagEnabled`=debug; 5000-line RAM ring + append file; NO new in-app UI). Per-probe DECISION TRACE on `Log.d('hadithfind', …)`: `probe len=.. rms=.. top=[#N:score …] | <verdict>` where verdict = WHY (`below minLen L/40` / `floor best<2.0` / `margin X<0.40 (best..#a vs ..#b)` / `streak k/3` / `PICK #N`). Raw phoneme deltas on `Log.t` (`traceOn=true` BY DEFAULT = full "what it heard"; kept ON per user's "every atom", toggleable on the existing debug screen). Mic-owner labels on claim/release (`quran`/`dua-reader`/`dua-finder`/`hadith-finder`). Quran + dua-finder were already traced; added a trace to the dua READER (was silent). `flutter analyze` clean, 150 tests pass, mic path unperturbed.
- **`run_eval.ps1`** (updated the EXISTING pull script, not a new one): builds debug APK → install → launch → recite → **press `s` to stop → deterministically SAVES + `adb pull`s** `logs/`(+`eval/`,`recordings/`) into `pulls\run_<timestamp>\`. Stop is a keypress poll loop (`[Console]::KeyAvailable`/`ReadKey`), NOT Ctrl+C/`finally` (unreliable in PowerShell — kept only as backup); verified by repro. Flags `-SkipBuild`/`-SkipInstall` preserved. Read the Hadith trace: grep the pulled `run_*.log` for `[hadithfind]`.
- **Phase 2:** Plan B — migrate ReadingState/DuaReadingState/DuaFinderState onto the now-proven core. Device-test each.
- **Phase 3:** Plan A — offload the one core to the worker isolate. Fallback flag.
- **Phase 4 (v2):** global cascade mic. Cheap once L1/L2 exist.

**Entry-point model (decided 2026-07-16).** Two capabilities; only their combination differs per domain: (A) **voice-find → jump to it** (universal, on the one `PhonemeFinder` engine); (B) **track-after-landing** (lock + window = 1 word forward / current-verse backward) — a per-domain toggle, ON only where the text is actually recited.
- Quran: A ✅ (mic from list/reader; recite off-page → jumps there, e.g. p5→p100) + B ✅ (recited).
- Dua: A ⚠️ TODAY find is list-only then dead-ends (the inconsistency to FIX in Phase 2) + B ✅ (single dua).
- Hadith (Phase 1): **A ✅ — copy Quran's entry, NOT dua's dead-end.** Mic works from the Hadith tab AND inside an open hadith (jump to another without backing out). Speak ~10+ words → engine's floor/margin decision → one confident match opens it; several → candidate list → tap. **B ❌ — no tracking window; hadith isn't recited for tajwīd, just find→display** (Arabic + reference; translation later). This makes voice-find consistent across all 3 tabs; Phase 2 then makes dua match hadith rather than a redesign. Cross-domain cascade stays Phase 4.
- **NEVER DEAD-END (UX rule, 2026-07-16).** A short query, a low-confidence result, OR many near-ties must ALWAYS render the ranked candidates as a **clickable list** — never ignore, never "no match," never silently do nothing. Only ONE clearly-confident match (`decideFind.confident`) auto-navigates; every other case falls back to the tappable list of `search()`'s top-K so the user picks. `search()` already returns ranked candidates regardless of confidence, so this is a UI-contract rule (no engine change); the UI must show them whenever not-confident.

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
