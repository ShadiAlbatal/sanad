# TilawaAi — Independent A-to-Z Code Review

_Generated 2026-07-16 · multi-agent review across 16 IT lenses (architecture, engineering, concurrency, ASR pipeline, ML/tajwīd, security, privacy, data integrity, performance, testing, dependencies/licensing, build/release, observability, UX/a11y/i18n, resilience, analytics)._

## How to read this
Each lens was reviewed by an independent agent that read the actual source; findings were then **adversarially verified** against the code by a second agent. The run hit a session token limit partway through, so:

- **11 findings are ✅ adversarially verified** (a second agent confirmed them against the source).
- **97 findings are • single-reviewer** (the finder produced them but its verifier was cut off) — high-signal, but treat as *to-confirm* rather than gospel.
- Severity mix: **1 critical · 15 high · 47 medium · 30 low · 15 info/strength** (108 findings total).
- One lens (data-integrity) had its finder cut off; the mushaf data was separately verified against quran.com earlier this session.

## Update (2026-07-16, later same day) — roadmap items fixed
All 5 "Ship-blockers → Privacy: disclosure & data handling" items are done (Auto Backup off, diagnostics
dev-gated, mic lifecycle, PCM wiped, consent label fixed), plus signing wired (needs your keystore), the
iOS mic string, and a Licenses & Attribution page. From **Next**, also fixed: async/native crash capture
(`runZonedGuarded` + `PlatformDispatcher.onError`), the blank-page-on-error bug (+ dedup'd the mic/chevron
buttons into shared, Semantics-labeled, tested widgets), the tajwīd reliability gate (min-sample-size floor —
see caveat below), a Qur'an content-integrity test (604 pages pinned + verified vs quran.com), CI
(`.github/workflows/ci.yml`, inert until this becomes a real git repo with a remote), and a release-build
script that strips the ~16 MB debug/eval audio from release builds. 133 tests green, analyze clean.
**Caveat on the tajwīd fix:** letters below 20 observations (including the flagship ط and the documented ظ
catch) are now silenced too, honestly reflecting thin evidence — not a new regression, the correct fix. See
`HANDOFF.md` for full detail. Still open: create the actual keystore, paste the exact model/font license
text, ONNX-on-background-isolate, rebuild-scope narrowing, and the remaining "Later" architecture items.

## Executive summary
TilawaAi is a genuinely impressive on-device Qur'an + Adhkar recitation app with a hard technical core (streaming phoneme ASR, tajwīd feedback, a faithful 15-line mushaf). The **engineering craft in the pure, testable core is strong** — extracted pure functions with real tests, mushaf data now verified against quran.com, analytics that is private by construction. The problem is not the core logic; it's **almost everything around actually shipping it**.

Three clusters dominate, and each blocks a real release:

1. **Licensing / distribution — the #1 risk.** The bundled ~72 MB ASR model is **non-commercial and access-gated**, the UthmanicHafs font and the Qur'an text/layout are redistributed with **no license, no attribution, and no LICENSE/NOTICE file anywhere**, and the release build is **signed with the public debug keystore**. None of this is a code bug — it's a legal/compliance wall in front of any store listing or monetized release.

2. **Privacy posture vs. reality.** The app *tells* users "nothing is uploaded / works fully offline," but in practice a verbose **recitation history (which verses, decoded phonemes, timestamps) is written to external storage every session regardless of consent**, Android **Auto Backup silently ships those logs plus the anonymous install-id to Google Drive**, the **mic keeps recording after you leave the Quran tab or background the app**, and raw voice PCM is **never wiped** after a session. For a religious-practice app, this is the most important cluster to close.

3. **Architecture debt that will slow everything down.** `ReadingState` is an 896-LOC god-object; three recitation pipelines are near-duplicated and will drift; ~642 LOC of the superseded hand-rolled engine still sits (and is still *tested*) beside the live one. On top: **ONNX inference runs on the UI isolate**, every mic chunk rebuilds all three mushaf pages, and the matcher re-collapses the whole cumulative token stream each chunk.

One ML-correctness finding deserves special billing because it hits the app's core promise: the **tajwīd reliability gate is defeated by n=1 letters**, so a *correct* reciter can be told they made a makhraj mistake — the exact "crying wolf" the design tries hard to avoid.

**Overall health: ~5.5/10.** The core logic is ~8/10; ship-readiness is ~3/10. Nothing here is fatal — all of it is addressable — but several items are true release gates, not polish.

## Ship-blockers (resolve before ANY public or monetized release)
1. **ASR model license** — confirm redistribution is allowed with the model author; keep the app free or relicense/swap the model; ship the model's license + a visible attribution.
2. **Font + Qur'an-data license/attribution** — bundle the KFGQPC font EULA and quran.com/QUL attribution; pin the exact upstream data version.
3. **Release signing** — a real upload keystore + Play App Signing (debug-signed builds cannot be published or updated).
4. **Privacy: disclosure & data handling** — gate the external-storage recitation log behind debug, set `allowBackup=false` (or exclude logs + anon_id), stop the mic on tab-away/background, wipe PCM on Stop, and make the privacy copy accurate.
5. **LICENSE/NOTICE + in-app license page** — Apache-2.0 (sherpa-onnx/onnxruntime), the MIT/BSD packages, the font, the model, and the Qur'an data all carry attribution obligations.

## Findings
_✅ = adversarially verified · • = single-reviewer (confirm before acting). Each: file:line · category, one-line impact, one-line fix._


### CRITICAL

**• single-reviewer — Release build is signed with the debug keystore — cannot be published or updated**  
`android/app/build.gradle.kts:37` · release-signing  
↳ _Impact:_ Any `flutter build apk/appbundle --release` is signed with the auto-generated debug keystore. Google Play rejects debug-signed uploads outright, so the app literally cannot be published. Worse, the debug keystore is per-machine and disposable — even if sideloaded, the next build from another machine has a different signing cert, so no up…  
↳ _Fix:_ Create a release keystore, add android/key.properties (gitignored), load it in build.gradle.kts, and define signingConfigs.release. Store the keystore + passwords securely; losing them means never being able to update the app on Play.


### HIGH

**✅ verified (confirmed) — Non-commercial, access-gated ASR model (72.7 MB model.int8.onnx) is bundled and redistributed inside the APK**  
`lib/services/asr/sherpa_asr.dart:19` · licensing  
↳ _Impact:_ Two compounding, ship-blocking problems. (1) Monetization ban: the moment TilawaAi carries ads, IAP, a paid tier, or is sold, distributing this bundled model violates its license. (2) Redistribution of a GATED model: HF gating requires each downloader to request access and accept terms; baking the weights into a public Play Store APK han…  
↳ _Fix:_ Before any store release: (a) confirm in writing with the model author (Muno459) that bundling the int8 weights in a redistributed app is permitted, and get explicit redistribution wording; (b) keep the app strictly free (no ads/IAP/subscriptions) or negotiat…

**• single-reviewer — No CI: the entire quality gate depends on a human remembering to run `flutter test`/`flutter analyze` before each manual APK build**  
`analysis_options.yaml:11` · ci-automation  
↳ _Impact:_ A failing test, an analyzer error, or a regression in the pure ASR/matcher logic can be built into an APK and shipped to the user's device with no signal. On a solo project the discipline of manually running two commands before every build is exactly what erodes over time; the well-written test suite provides zero protection on the build…  
↳ _Fix:_ Add a minimal GitHub Actions workflow (`flutter pub get` → `flutter analyze lib` → `flutter test`) triggered on push/PR, and/or a `pre-build.ps1` / git pre-commit hook that runs the same two commands and refuses on failure so the gate can't be silently skippe…

**• single-reviewer — Default Android Auto Backup uploads recitation logs and the 'per-install' anonymous id to the user's Google Drive — directly contradicting the in-app 'nothing is uploaded anywhere' promise**  
`android/app/src/main/AndroidManifest.xml:5` · undisclosed-egress  
↳ _Impact:_ The recitation-history logs and the anonymous install id egress to Google's cloud with no disclosure, breaking the app's central privacy claim and any Play Data-safety declaration built on it. Because anon_id is backed up, it survives reinstall/restore and can follow the user to a new device, undermining the 'a code for this app copy, no…  
↳ _Fix:_ Set `android:allowBackup="false"`, or add dataExtractionRules/fullBackupContent that exclude the `logs/` directory and the anon_id preference. Decide explicitly whether anon_id should be excluded from backup so it stays truly per-install.

**• single-reviewer — Crash capture only hooks FlutterError.onError — async/platform crashes escape both the pulled log file AND the crash report**  
`lib/main.dart:17` · crash-capture  
↳ _Impact:_ The file-sink's stated purpose is 'so a whole run can be adb-pulled to a PC after testing'. But an async crash — the exact failure you most want to diagnose — terminates the app leaving no entry in the pulled log, and (with essentialConsent on) no crash report either. With no CI, no remote reporting, and manual device testing, this is th…  
↳ _Fix:_ Add `WidgetsBinding.instance.platformDispatcher.onError = (e, st) { Log.e('zone', e, st); ... return true; };` and/or wrap `runApp` in `runZonedGuarded(..., (e, st) => Log.e('zone', e, st))`. Route both into the same Log.e + recordCrash path so async/platform…

**• single-reviewer — Every mic chunk rebuilds all 3 on-screen mushaf pages, even when only the mic level/timer changed**  
`lib/screens/quran_screen.dart:142` · rebuild-churn  
↳ _Impact:_ ~360 rich-text runs across 3 pages are rebuilt and re-laid-out 10-25x/sec throughout recitation, most of which change nothing visible (the marker only advances a word occasionally; RMS level and the seconds timer change constantly but only need the footer). This is wasted CPU/battery and a direct contributor to page-turn and follow-along…  
↳ _Fix:_ Separate high-frequency telemetry (asrLevel, asrHeard, timer) from marker state so the mushaf only rebuilds when highlighted/read/skipped/verse actually change: expose them via a distinct ValueNotifier/ChangeNotifier or wrap the mushaf in a `Selector<ReadingS…

**• single-reviewer — A page whose JSON fails to load renders as a permanently blank white page — the errored Future is cached, so there is no recovery for the session**  
`lib/screens/quran_screen.dart:255` · graceful-degradation  
↳ _Impact:_ A corrupt/missing page JSON, or a merely transient failure (e.g. an OOM/IO hiccup while json.decode'ing a page during memory pressure), leaves that mushaf page blank for the entire app run with no message, no spinner, and no retry — even after the underlying cause clears. For a Quran reader a silently blank page is a trust/UX failure and…  
↳ _Fix:_ Add a `snap.hasError` branch in the FutureBuilder that shows a visible error+retry affordance (and logs), and stop caching failed futures in QuranRepository.page — on catch, remove the entry from `_pageFutures` before rethrow (`_pageFutures.remove(page)`) so …

**• single-reviewer — Live recitation mic keeps recording after leaving the Quran tab and when the app is backgrounded**  
`lib/screens/root_scaffold.dart:47` · lifecycle-privacy  
↳ _Impact:_ After starting a Quran follow-along and pressing back to Home (or backgrounding the app), the microphone continues capturing audio, the session timer keeps ticking, and PCM is retained (up to 600s, reading_state.dart:178-180) with no way to stop it without navigating back to the Quran tab. This is a privacy concern (unexpected continued …  
↳ _Fix:_ Stop the Quran ReadingState when leaving the Quran tab (mirror the DuaFinder handling in root_scaffold.dart), and register a WidgetsBindingObserver at the app/root level that stops any active pipeline (ReadingState / DuaReadingState / DuaFinderState) on AppLi…

**• single-reviewer — Streaming ONNX phoneme inference runs synchronously on the UI isolate (no compute/isolate offload)**  
`lib/services/asr/sherpa_asr.dart:54` · main-thread-blocking  
↳ _Impact:_ During continuous recitation (the app's core feature) the zipformer2-ctc decode blocks the UI isolate on every mic chunk (~10-25x/sec). numThreads:2 only parallelizes the native C++ math; the Dart isolate still blocks in the FFI call and cannot produce frames, so the mushaf drops frames / stutters while the mic is live, and the effect co…  
↳ _Fix:_ Run the OnlineRecognizer on a long-lived background isolate: create the recognizer there, stream PCM chunks in via a SendPort, and return cumulative tokens back to the UI isolate. Keep one worker for the whole session (don't Isolate.run per chunk). This remov…

**• single-reviewer — Tajwīd reliability gate is defeated by n=1 letters (ج/ث/ز rated 1.0) → false makhraj-error flags on correct recitation**  
`lib/services/asr/tajweed_review.dart:239` · tajweed-logic  
↳ _Impact:_ For any substitution against a rare-but-trusted letter (e.g. model hears ذ where ref is ز, or ت↔ث) that survives the makhraj/confusable/junction/madd masks, the app confidently tells a CORRECT reciter they made a tajwīd mistake — exactly the 'crying wolf' the whole design claims to avoid, on the app's core value (trustworthy recitation f…  
↳ _Fix:_ Gate on a Wilson/Jeffreys lower confidence bound instead of the raw point estimate, and/or require a minimum sample size (e.g. seen ≥ 20) before a letter is eligible to flag; letters below the min stay silent. Regenerate the table from far more eval audio tha…

**• single-reviewer — Three near-duplicate recitation pipelines (ReadingState / DuaReadingState / DuaFinderState) with no shared base — verbatim-copied logic that will drift**  
`lib/state/dua_reading_state.dart:333` · duplication  
↳ _Impact:_ Any tuning or bug fix (rms floor, level curve, the gap heuristic, retention cap) must be made in 2-3 places and WILL diverge silently — the classic drift hazard. Device tuning of `/1600` (flagged DEVICE-PENDING in comments) has to be repeated per file.  
↳ _Fix:_ Extract a shared RecitationSession mixin/base (or the service from finding #1) owning _onPcm/_retain/_applyOut/level/_collapse and the tuning constants; have all three states delegate to it. DuaFinderState shares the probe/collapse half.

**• single-reviewer — ReadingState (896 LOC) is a god-object mixing ~8 concerns and ships the debug/eval harness inside the production state**  
`lib/state/reading_state.dart:23` · god-object  
↳ _Impact:_ The app's single most-central file couples unrelated concerns: editing reveal logic risks the ASR path; the 17-field re-acquisition machine cannot be unit-tested in isolation (only the extracted pure fns are); debug/eval code and its imports ship in production. This is the dominant barrier to the extensibility goals (iOS, more languages)…  
↳ _Fix:_ Split into: a ReadingState (UI/reveal + exposes getters), a RecitationSession service (mic->matcher->marker, reused by Quran+Dua), a ReacquisitionController (the probe machine), and move runFileDiagnostic/runSherpaTest/runEval behind a dev-only DiagnosticsCon…

**• single-reviewer — Always-on diagnostic log persists a verse-by-verse recitation history (surah, full decoded phoneme/token stream, timestamps) to external storage in release builds — undisclosed, unbounded, un-erasable**  
`lib/util/log.dart:35` · data-minimization  
↳ _Impact:_ A behavioral profile of the user's religious practice — which surahs/verses were recited, when, how often, and the decoded phonemes reconstructing what was said — sits unencrypted in app-scoped external storage (reachable over USB/MTP, by file managers, and by other apps with broad storage access), accumulating with no cap and no user-fa…  
↳ _Fix:_ Gate `Log.initFileSink()` and the Debug Log screen behind kDebugMode (or a hidden dev setting, default off). If a file log is kept for support, write to internal storage (getApplicationDocumentsDirectory, not external), cap/rotate it, redact verse content and…

**• single-reviewer — Core recite mic and reveal chevrons are icon-only GestureDetectors with zero screen-reader labels — TalkBack cannot name or describe the app's central control**  
`lib/widgets/reading_footer.dart:227` · accessibility  
↳ _Impact:_ A blind or low-vision reciter using TalkBack lands on the record button and hears an empty/unnamed node with no indication it starts recitation or that it is currently recording vs stopped. The four reveal chevrons announce nothing at all, so step-reveal memorization is unusable non-visually. Blind and low-vision reciters are a real and …  
↳ _Fix:_ Wrap each icon-only control in `Semantics(button: true, label: ..., hint: ...)`. For the mic use a stateful label ('Start recitation' / 'Stop recitation, recording') and mark it a toggle; for chevrons label direction+granularity ('Reveal next word', 'Reveal p…

**• single-reviewer — Non-commercial-licensed ASR model bundled with no LICENSE/attribution in the distributable**  
`pubspec.yaml:71` · licensing-release-blocker  
↳ _Impact:_ Shipping this APK on any commercial storefront (Play Store distribution, or any paid/ad-supported form) redistributes a model whose license forbids commercial use, and does so without the required attribution/license text. That is a legal distribution blocker independent of code quality, and it will only surface after release.  
↳ _Fix:_ Confirm the exact model license; if non-commercial, either obtain a commercial license, swap to a permissively-licensed model, or restrict distribution accordingly. Bundle the model's LICENSE/NOTICE in-app (e.g. a licenses screen) and in the repo.

**• single-reviewer — No dart test validates the actual Quran verse/glyph content of the 604 mushaf pages; the real content verifier is an ungated network Python script**  
`tool/verify_all.py:6` · content-integrity  
↳ _Impact:_ For a Quran app, wrong scripture is the worst-case defect. A corrupted glyph, dropped āyah, or wrong word introduced by a future page-editing script would pass every automated test and ship. The one real integrity check requires internet + a manual Python run, so in practice it is rarely re-run after edits.  
↳ _Fix:_ Bundle a canonical per-page reference (word `location` sequence + a glyph/text checksum) as a test asset and add a dart test that loads all 604 `QuranRepository.page(p)` and asserts full equality, so content corruption fails `flutter test` offline and determi…


### MEDIUM

**✅ verified (confirmed) — No LICENSE / NOTICE / attribution surface anywhere — OSS attribution obligations unmet**  
`README.md:3` · license-compliance  
↳ _Impact:_ Google Play's policies expect open-source license attribution to be surfaced, and Apache-2.0 (sherpa-onnx/onnxruntime) plus the font EULA and the model's 'pass the terms on' clause each require the notices to travel with the distributed app. With no LICENSE, no NOTICE, and no license page, the release is non-compliant across every bundle…  
↳ _Fix:_ Add a project LICENSE, wire a `showLicensePage()`/About screen (Flutter auto-aggregates package LICENSE files; add the font, model, and Quran-data notices manually via `LicenseRegistry.addLicense`), and include the ASR model's non-commercial terms and font EU…

**✅ verified (confirmed) — Release build is signed with the shared, publicly-known Android debug keystore**  
`android/app/build.gradle.kts:37` · build-signing  
↳ _Impact:_ The Android debug keystore ships with the SDK and its password/alias are public, so any `flutter run --release` / built APK carries no real developer identity. Google Play rejects debug-signed uploads outright, and for sideloaded APKs anyone can compile a modified build that signs with the identical well-known key, so the OS treats a tam…  
↳ _Fix:_ Create a dedicated upload/release keystore, load it via a git-ignored `key.properties`, and point `signingConfigs.release` at it before any distribution. Enable Play App Signing. Keep the debug config only for `debug`/local runs.

**✅ verified (confirmed) — UthmanicHafs (KFGQPC) Quran font is redistributed with no license text or attribution**  
`pubspec.yaml:80` · licensing  
↳ _Impact:_ KFGQPC / quran.com (QUL) UthmanicHafs fonts are NOT open-licensed (OFL); they ship under a custom KFGQPC EULA that restricts modification and commercial redistribution and generally requires attribution and use limited to Quranic content. Redistributing the .ttf in a store app without carrying its license/attribution is a compliance gap …  
↳ _Fix:_ Identify the exact provenance/version of uthmanic_hafs.ttf (e.g. QUL 'UthmanicHafs1 Ver18'), obtain and bundle its license/EULA, add an in-app attribution, and confirm the redistribution + (non-)commercial terms match the app's business model before publishin…

**✅ verified (confirmed) — Bundled Quran text, tajweed markup and page layout are redistributed with no attribution or verified license**  
`tool/fetch_pages.py:2` · data-licensing  
↳ _Impact:_ This third-party Quranic text/layout dataset is redistributed inside the APK. quran.com/QUL and the KFGQPC layout data carry their own usage/attribution terms; shipping them with zero attribution or license verification is a compliance gap and, for a Quran app, also a data-integrity/provenance concern (no pinned commit/version of the ups…  
↳ _Fix:_ Record the exact upstream commit/version of zonetecde/mushaf-layout and the quran.com API terms, confirm redistribution is permitted, and add a data-source attribution (in-app credits screen or About). Pin the fetch scripts to immutable revisions so the shipp…

**• single-reviewer — No code/resource shrinking or app-bundle config — universal fat APK carrying all ABIs + 108 MB assets**  
`android/app/build.gradle.kts:33` · build-optimization  
↳ _Impact:_ A `flutter build apk --release` produces a single universal APK bundling arm64-v8a, armeabi-v7a and x86_64 copies of the ONNX runtime plus all 108 MB of assets — easily well over 100 MB, hurting install conversion and bumping into per-APK size limits. Resource shrinking is off so unused Android resources ship too.  
↳ _Fix:_ Ship an Android App Bundle (`flutter build appbundle`) so Play delivers per-device ABIs, or use `--split-per-abi` for APKs. Enable minifyEnabled/shrinkResources for the release type (add R8 keep rules only if a plugin needs them).

**• single-reviewer — Reliability table and confusable mask are un-versioned, un-reproducible single-run artifacts with no linkage to the ASR model**  
`assets/asr/phoneme-reliability.json:1` · reproducibility  
↳ _Impact:_ If the sherpa model.int8.onnx is ever swapped/retrained, the reliability numbers and the ب↔م/ش↔ف mask silently become invalid but nothing forces regeneration or even flags the drift, so the tajwīd verdicts quietly degrade. The table also cannot be independently regenerated or audited.  
↳ _Fix:_ Commit a deterministic generator (heard-vs-said confusion matrix over the eval corpus) that stamps the model version/SHA into the output JSON; have verify_all.py assert the stamp matches the shipped model, and regenerate on any model change.

**• single-reviewer — iOS build has no microphone usage description — guaranteed crash on first record + App Store rejection**  
`ios/Runner/Info.plist:4` · ios-not-shippable  
↳ _Impact:_ On iOS, requesting the microphone without NSMicrophoneUsageDescription triggers an immediate hard crash (SIGABRT) the first time recitation starts, and App Store review auto-rejects the binary. Confirms iOS is unbuilt/unshippable as-is; anyone attempting the 'iOS later' path hits this on day one.  
↳ _Fix:_ Add NSMicrophoneUsageDescription (a user-facing reason string) to ios/Runner/Info.plist before any iOS build, and tidy CFBundleName. Add an iOS smoke build to whatever gate exists once iOS work starts.

**• single-reviewer — Async/native errors are unhandled — most likely crash class bypasses logging and crash-consent sink**  
`lib/main.dart:17` · crash-reporting  
↳ _Impact:_ For a native-heavy on-device ASR app, uncaught async and platform-channel errors are the most probable crash source, yet they skip the local Log.e capture and the essential-consent crash report entirely — you get a silent crash with no diagnostic and no report, undermining the whole crash-safety opt-in.  
↳ _Fix:_ Set PlatformDispatcher.instance.onError (return true after logging/reporting) and/or wrap runApp in runZonedGuarded so async and native errors flow through the same Log.e + Analytics.recordCrash path.

**• single-reviewer — Recitation state is fragmented across three provider lifetimes driving one shared mic; app-global ReadingState is never disposed and pins ~18 MB PCM + clip caches for app lifetime**  
`lib/main.dart:40` · lifecycle-coupling  
↳ _Impact:_ Reasoning about 'who owns the mic / who is listening' requires tracing claimMic across three files and three lifetimes; the global ReadingState holds ~18 MB session PCM + caches resident after any Quran session until app exit. The scattered ownership is the root cause of the invisible-session workaround.  
↳ _Fix:_ Unify the recitation states under one lifecycle (e.g. a single RecitationController with a mode enum, or provide all three at the same scope) and free the PCM/caches on stop/tab-away rather than app teardown.

**• single-reviewer — Unguarded bootstrap and no PlatformDispatcher.onError: a cold-start failure shows a blank screen, and async/isolate crashes bypass the opt-in crash report**  
`lib/main.dart:14` · error-reporting  
↳ _Impact:_ Two gaps: (1) if Prefs.load()/initFileSink throw during a cold start, runApp is never reached and the user gets a white screen / ANR with no fallback UI. (2) The whole point of the 'Essential app data' (crash-safety) opt-in is undercut — the most common real-world crash class (uncaught async errors) never reaches buildCrashReport/recordC…  
↳ _Fix:_ Wrap bootstrap in try/catch (run the app with defaults on Prefs failure) and add `PlatformDispatcher.instance.onError` (and/or runZonedGuarded) that forwards to Log.e + Analytics.recordCrash, mirroring the existing FlutterError.onError handler, so async/platf…

**• single-reviewer — Crash emission has no throttle/dedup and fires on every FlutterError frame; fatal is hardcoded false**  
`lib/main.dart:17` · robustness  
↳ _Impact:_ Today (LogAnalyticsSink) a broken frame spams the Debug Log ring buffer. Once SupabaseAnalyticsSink is enabled (Phase B), the SAME recurring error becomes an HTTP POST storm to /rest/v1/sessions — one request per frame — flooding the anon-insert endpoint (RLS policy is 'with check (true)', analytics.dart + sessions.sql:30-32, so no serve…  
↳ _Fix:_ Dedup identical (error,library) within a window and cap crash emissions per session (e.g. keep a seen-set + max N). Pass a real fatal flag (FlutterErrorDetails.silent / stack presence) instead of a constant. Consider only emitting a crash summary once per (er…

**• single-reviewer — No localization infrastructure at all despite a user-facing Language setting — UI is hardcoded English and stays LTR on Arabic/Urdu devices**  
`lib/main.dart:48` · i18n  
↳ _Impact:_ On a device set to Arabic/Urdu/etc, the app chrome remains English and left-to-right (Material widgets also won't localize date/number/direction defaults). The target audience is heavily non-English-first, yet there is no path to translate without touching every screen. Retrofitting l10n after all strings are inlined is far more expensiv…  
↳ _Fix:_ Add `flutter_localizations` + an ARB/gen-l10n (or equivalent) setup now, wire `localizationsDelegates`/`supportedLocales` into MaterialApp, and route strings through a lookup even if only English exists initially. This also unlocks correct app-level `Directio…

**• single-reviewer — Errors on the du'a autoStart / clip-load path are silently swallowed — the reader looks frozen with no message**  
`lib/screens/dua_reader_screen.dart:30` · silent-failure  
↳ _Impact:_ On the flagship 'recite to open' flow, an asset/model/mic failure produces a blank or inert du'a reader that silently does nothing — the user sees the screen open but no words light up and no recitation begins, with no error and no way to know what went wrong.  
↳ _Fix:_ Surface load/start errors on the autoStart path (e.g. have _DuaReaderView show an error state when `state.error != null` / words are empty after load, or push a SnackBar from the autoStart callback), and add a catchError to the loadDua future in the provider …

**• single-reviewer — Debug Log screen and eval harness are reachable in release builds**  
`lib/screens/home_screen.dart:42` · debug-surface-in-prod  
↳ _Impact:_ Any shipped user who long-presses the home title gets the internal diagnostics screen, can export raw decode logs, and can kick off the eval suite. This is a debug/data-exposure surface present in production, and it is the reason the test-audio assets must ship.  
↳ _Fix:_ Gate the long-press entry point (and ideally the whole DebugLogScreen route) behind kDebugMode or a build-time --dart-define flag so it compiles out of release.

**• single-reviewer — Coral accent (and Auto's dusk color) used as small text fails WCAG AA contrast on the light paper background**  
`lib/screens/home_screen.dart:167` · color-contrast  
↳ _Impact:_ With the Coral accent selected, or Auto accent in the evening, small accent-colored labels across Home, the du'a reader, the surah list, and Settings drop to ~3.1:1 and become hard to read for low-vision users and in bright/outdoor conditions. Emerald (~4.7:1) barely passes; Coral clearly fails.  
↳ _Fix:_ Apply a light-theme lightness ceiling for accent-as-text (mirror the existing `_accentForDark` floor with a light-side cap), or reserve the raw accent for fills/large text and darken it for text runs under ~18px. Verify each preset against 4.5:1 on `AppColors…

**• single-reviewer — QuranScreen watches ReadingState at the Scaffold root, rebuilding the whole page + CurlPageView ~13x/s during live recitation**  
`lib/screens/quran_screen.dart:142` · rebuild-scope  
↳ _Impact:_ Sustained high-frequency rebuild of the app's core screen during its core feature (follow-along), on Android-first low-end targets; extra allocation of the highlighted set each frame.  
↳ _Fix:_ Narrow the reactive surface: wrap only the mushaf/footer in Selector/Consumer keyed to the highlight/marker sets, or expose asrHighlightedLocations/skipped as ValueListenables so the page turns react without rebuilding the Scaffold.

**• single-reviewer — ~70 MB ONNX model is warmed at every cold start regardless of whether recitation is ever used**  
`lib/screens/quran_screen.dart:42` · startup-memory  
↳ _Impact:_ Baseline resident memory is raised by ~70 MB and native ASR threads + disk-staging I/O run at every cold start even when the ASR feature is never touched. On low-RAM Android this increases the chance of the app being evicted in the background and adds needless launch-time I/O.  
↳ _Fix:_ Warm lazily: trigger warmAsrEngine only when the Quran tab is first selected (or on first ReadingFooter paint / first mic-button focus), not from QuranScreen.initState under an eager IndexedStack. Keep the shared-engine design; just defer creation until the r…

**• single-reviewer — QuranScreen watches all of ReadingState, rebuilding 3 full mushaf page trees on every mic chunk (~12/s) including telemetry-only notifies**  
`lib/screens/quran_screen.dart:142` · rebuild-scope  
↳ _Impact:_ Sustained rebuild churn of ~1000+ widgets ~12x/second across three page trees during live recitation on Android (the target platform), causing avoidable jank and battery use for changes that don't affect the page.  
↳ _Fix:_ Scope the reader's dependency to only page-relevant fields with a Selector<ReadingState, ...> over (asrHighlightedLocations, asrReadLocations, asrSkippedLocations, asrCurrentVerseKey, hidden, revealed), so telemetry-only notifies (asrLevel/asrHeard/asrSeconds…

**• single-reviewer — 'Essential app data' consent is bundled with 'Basic functionality', a misleading label that pressures users into enabling crash-data collection**  
`lib/screens/settings_screen.dart:92` · consent-clarity  
↳ _Impact:_ Consent-validity / dark-pattern concern: users may enable diagnostic data collection believing the app needs it to function. Under GDPR-style consent standards and Play policy, an optional data-collection switch must not be framed as essential.  
↳ _Fix:_ Rename to make clear it is optional crash/error diagnostics only (e.g. 'Crash & error reports'), and drop 'Essential'/'Basic functionality' framing.

**• single-reviewer — AnalyticsSink has only sendSession; crash reports are routed through it into the sessions table**  
`lib/services/analytics.dart:106` · design  
↳ _Impact:_ Crashes and recitation sessions are conflated in one table under one code path. Phase B queries over 'sessions' must special-case kind='crash' everywhere or crash rows pollute usage metrics. There is also no route for a crash-specific endpoint/consent-scoped sink.  
↳ _Fix:_ Add a distinct sendCrash to AnalyticsSink (or a separate crashes table / endpoint), and have recordCrash call it. Keep the two report families in separate tables so session dashboards aren't polluted by crash rows.

**• single-reviewer — Entire pronunciation-head ML pipeline is dead code that references a missing asset and would crash if invoked**  
`lib/services/asr/asr_assets.dart:92` · dead-code  
↳ _Impact:_ Misleading model provenance for a religious tajwīd app (feedback is actually deterministic makhraj-substitution matching, not an ML pronunciation model); ~2.2 MB of dead assets ship in the APK (ref_tokens.json 2.0 MB, mel_filters.json 112 KB, vocab.json, cmvn.json, pronunciation_head_manifest.json — all only referenced by the dead AsrAss…  
↳ _Fix:_ Either delete the abandoned BPE/head pipeline (pronunciation_head.dart, asr_assets.dart, recitation_tracker.dart, verse_index.dart, token_match.dart, session.dart's WordScore/SessionRecorder, and the dead assets) plus the stale comments, or wire the head in a…

**• single-reviewer — Single-owner mic preempt is a no-op against a session still inside its async start window**  
`lib/services/asr/asr_engine.dart:88` · race-condition  
↳ _Impact:_ The shared-mic single-owner invariant — the core of this whole design — is defeated. End state: the mic delivers to ReadingState while DuaFinderState still reports `_listening=true` with frozen telemetry; `_owner._releaseActive` points at the wrong stop callback so a later preempt targets the dead session and the live one keeps recording…  
↳ _Fix:_ Track an in-flight 'starting' owner in AsrEngine, or make claim() await the previous owner's FULL relinquish including the starting phase. Simplest: give each pipeline a `_stopRequested`/generation token checked after every await in start (like DuaReadingStat…

**• single-reviewer — align-file load failure silently falls back to a word→glyph mapping the code itself calls 'WRONG', mis-highlighting Quran words**  
`lib/services/asr/phoneme_corpus.dart:76` · data-integrity  
↳ _Impact:_ If an align file is ever dropped in packaging OR fails to decode transiently (e.g. memory pressure parsing a large surah's align data), recitation follow-along silently maps corpus words to the wrong mushaf glyphs for that whole session — the moving marker, read/skip washes, and post-recitation mistake locations point at the wrong Quran …  
↳ _Fix:_ Narrow the catch to a genuinely-missing asset, and treat a decode failure as fatal-for-that-surah (surface it / disable tracking for that surah) rather than degrading to a knowingly-wrong mapping; consider a build-time assert (tool/) that all 114 align files …

**• single-reviewer — Matcher re-collapses the entire cumulative token stream (and recompiles a RegExp per token) every chunk — O(n²) over a session**  
`lib/services/asr/phoneme_matcher.dart:113` · algorithmic-cost  
↳ _Impact:_ On long recitations the per-chunk Dart-side bookkeeping grows with session length and surah size, adding steady CPU/GC pressure (regex churn + list/set reallocation) on top of the UI-isolate inference — extra battery drain and micro-stutter that worsens the longer the user recites.  
↳ _Fix:_ Hoist the collapse pattern to a `static final RegExp`. Collapse only the tail window actually consumed rather than the whole cumulative list. Reuse/diff the word-state list instead of copying the full-surah List each chunk, and only rebuild read/skipped sets …

**• single-reviewer — Words the phoneme model cannot voice (frac<0.5, e.g. ص/ض/ق/غ/ك) are grace-skipped and reported as 'you skipped this word' — false recitation-error feedback**  
`lib/services/asr/phoneme_matcher.dart:238` · asr-correctness-false-feedback  
↳ _Impact:_ A user who recites a word correctly, but whose word contains letters the model can't emit, gets buzzed mid-recitation and told in the Mistakes sheet that they SKIPPED a word of the Qur'an. For a tajwid-feedback app this is a correctness/trust failure — the feedback contradicts a correct recitation.  
↳ _Fix:_ Distinguish 'model emitted ~no phonemes for this word' (frac≈0 → unreliable, suppress the skip verdict, like reviewTajweed already suppresses low-reliability makhraj flags) from a genuine jump (neighbouring words greened but this one truly absent). Gate the s…

**• single-reviewer — ~642 LOC of the superseded hand-rolled ASR engine remains in lib/services/asr/ intermingled with the live sherpa pipeline, reachable only from tests**  
`lib/services/asr/recitation_tracker.dart:78` · dead-code  
↳ _Impact:_ A newcomer/reviewer cannot tell the live pipeline from the dead one (recitation_tracker.dart vs phoneme_matcher.dart both look load-bearing). The test suite still pins behavior of code no product path uses, giving false coverage confidence. Obscures the module boundary the lens asks about.  
↳ _Fix:_ Delete the orphaned cluster and its tests, or if kept as reference, move under lib/services/asr/_legacy/ (or tool/) so the live sherpa surface is unambiguous.

**• single-reviewer — Entire token-based ASR pipeline (RecitationTracker/VerseIndex/AsrAssets/PronunciationHead) is dead code shipped alongside the live phoneme matcher; a referenced asset is even missing**  
`lib/services/asr/recitation_tracker.dart:78` · dead-code-maintainability  
↳ _Impact:_ ~730+ LOC of unused ASR logic plus a missing-asset landmine. Any engineer (or reviewer) fixing an acquisition/skip/lock bug may edit RecitationTracker believing it drives the app — it does not. The green test suite gives false confidence that the token-based acquisition/skip/back logic is validated when the shipping matcher is PhonemeMat…  
↳ _Fix:_ Delete the token-based pipeline (recitation_tracker.dart, verse_index.dart, token_match.dart, asr_assets.dart, pronunciation_head.dart, bpe_decoder.dart, SessionRecorder in session.dart) and their tests, OR wire the missing pronunciation_head.bin and actually…

**• single-reviewer — _modelConfusable blanket mask permanently suppresses genuine ب↔م and ش↔ف makhraj errors (false negatives)**  
`lib/services/asr/tajweed_review.dart:67` · tajweed-logic  
↳ _Impact:_ Whole classes of real mispronunciations can never be reported, regardless of how clearly the reciter erred — a silent correctness gap in the mistake detector. The trade-off (avoiding model-driven false positives) is reasonable as a stopgap but is unbounded and undocumented to the end user.  
↳ _Fix:_ Replace the hard-coded pair mask with per-pair suppression derived from an actual heard-given-said confusion matrix (the TODO in the same comment and HANDOFF.md:127), so pairs are down-weighted proportionally rather than fully blinded.

**• single-reviewer — DuaReadingState fabricates fake Quran 's:a:w' location strings to reuse the reveal helpers — leaky cross-module coupling**  
`lib/state/dua_reading_state.dart:161` · leaky-abstraction  
↳ _Impact:_ The du'a memorization reveal is coupled to the Quran location-string format purely to reuse two pure functions. Any change to that format (likely under the i18n/iOS extensibility work) silently breaks du'a reveal, and the round-trip string parse is fragile and hard to follow.  
↳ _Fix:_ Refactor revealForwardLocs/revealBackLocs to operate on generic indices (or a small typed key), then both Quran and Dua call them without string fabrication.

**• single-reviewer — Dead 'deviations' live-tajweed path threaded through 4 widget layers while the source getter is hardcoded to const {}**  
`lib/state/reading_state.dart:147` · dead-path  
↳ _Impact:_ Four widget layers carry a dead parameter and QuranScreen+MushafPageView are coupled to pronunciation_head.dart's Deviation enum for a disabled feature, enlarging the rebuild payload and misrepresenting behavior to the next maintainer.  
↳ _Fix:_ Either wire the per-word deviation feed or remove the deviations parameter from the whole chain (getter, screen, _PageLeaf, MushafPageView, _AyahLine) until it exists.

**• single-reviewer — Retained session voice PCM (up to ~19 MB) is never wiped after Stop — held in an app-lifetime provider until the next session or app kill**  
`lib/state/reading_state.dart:608` · data-minimization  
↳ _Impact:_ The very data the privacy screen lists under 'Never shared: Your voice or any audio recording' (privacy_screen.dart:23) persists in RAM far beyond its tap-to-hear-mistake purpose, with no zeroization on stop or teardown. This widens the exposure window to heap/memory inspection and violates data-minimization. Bounded to in-memory (not pe…  
↳ _Fix:_ Clear `_sessionPcm`, `_finalizedPcm`, and `_retainedSamples` in stopAsrListening once the Mistakes sheet is dismissed (or after a short TTL) and in dispose(). Consider retaining only the flagged-word audio spans rather than the whole session buffer.

**• single-reviewer — Analytics emission call-sites (privacy-critical) are untested — only the pure report builder and gate are covered**  
`lib/state/reading_state.dart:623` · test-coverage  
↳ _Impact:_ The two hand-duplicated Stop paths are where a session's consent respect and 'never audio/PII' promise actually take effect at runtime, yet they are verified only manually on-device. A future edit that drops the call-site `usageConsent` check, mislabels `kind`, or passes the wrong `ref` would not be caught host-side.  
↳ _Fix:_ Extract an injectable pure emit helper (takes an `Analytics` + the Stop primitives, returns/sends the report) so a host test can drive the Quran and dua Stop-emit decisions with a fake sink, mirroring the existing decideReacquire/MicOwnership extraction patte…

**• single-reviewer — Non-extracted orchestration in reading_state (896) / dua_reading_state (466) is structurally untestable and uncovered, including PCM slice math**  
`lib/state/reading_state.dart:187` · test-coverage  
↳ _Impact:_ Real, privacy-relevant slice/clamp arithmetic (tap-to-hear audio bounds) and the marker-catch-up UX run only on-device. An off-by-one in the clamp or memoization could crash playback or slice the wrong audio, undetected by the suite.  
↳ _Fix:_ Lift the marker-advance step and the mistake-WAV slice math into top-level pure functions taking plain `Int16List`/ints (as decideReacquire/reacqStalled already are) and unit-test their boundaries (empty PCM, start==end, cap-truncated session).

**• single-reviewer — Fire-and-forget re-acquisition probe and page re-anchor have no error handling and can re-fire every chunk**  
`lib/state/reading_state.dart:328` · unawaited-future  
↳ _Impact:_ A single unshippable/missing surah asset near the reciter's position turns into a repeating storm of unhandled async exceptions plus repeated full clip-load attempts on the UI isolate during live recitation. Even absent a bad asset, a transient rootBundle/IO failure is unhandled rather than logged-and-recovered.  
↳ _Fix:_ Wrap _probeAndMaybeSwitch's body in try/catch (log via Log.e and advance `_lastProbeTokens` in a finally so a persistent failure backs off instead of re-firing), and add `.catchError` plus an `_asrActive` guard to the setCurrentPage re-anchor `.then`.

**• single-reviewer — All ASR inference and cumulative-token reprocessing runs synchronously on the UI isolate, growing with session length**  
`lib/state/reading_state.dart:301` · ui-isolate-blocking  
↳ _Impact:_ Every mic chunk blocks the UI isolate on native inference plus O(session-length) token reprocessing, so on longer sessions (the retention cap is 600s) and slower Android devices the frame budget is repeatedly consumed on the main thread — jank, delayed marker updates, and a mic callback that can fall behind real time. The PCM retention i…  
↳ _Fix:_ Move sherpa decode + matcher.apply off the UI isolate (a long-lived Isolate fed the PCM chunks, returning states/cursor), or at minimum make apply incremental (collapse only the newly-appended tokens and keep a running collapsed buffer) so per-chunk cost is O…

**• single-reviewer — No app-lifecycle handling: mic + ASR session keep 'running' when the app is backgrounded mid-recitation**  
`lib/state/reading_state.dart:599` · lifecycle  
↳ _Impact:_ When the user backgrounds the app mid-recitation the session stays `active`: the second-timer keeps counting while Android (no foreground-service config) stops delivering mic audio, so on return the elapsed clock is inflated relative to captured PCM, and the sample-index math used to slice tap-to-hear mistake audio (startSample = startSe…  
↳ _Fix:_ Register a WidgetsBindingObserver (in RootScaffold or an app-level widget) and call the active pipeline's stop/pause on AppLifecycleState.paused/inactive so recitation ends cleanly, the mic is released, and the timer reflects real captured audio.

**• single-reviewer — Cross-surah re-acquisition ranks candidates by raw Smith-Waterman score normalized only by tail length, not by reference length — biased toward longer neighbouring surahs**  
`lib/state/reading_state.dart:378` · asr-reacquire-correctness  
↳ _Impact:_ When a reciter is correctly on a short surah adjacent to a long one (e.g. juz-30 short surahs near a longer one, or any ±5 neighbourhood spanning a long surah), the longer surah can win the probe on length alone and trigger a spurious switch, yanking the follow-along marker and landing page to the wrong surah.  
↳ _Fix:_ Normalize the localizer score by the matched span length (or the number of matched reference phonemes), not by tail length, before cross-surah comparison — so candidates compete on match density, not reference size. Alternatively cap the SW search to a window…

**• single-reviewer — Log file has no rotation, no size cap, and old runs are never deleted**  
`lib/util/log.dart:41` · log-rotation  
↳ _Impact:_ Trace is on by default and the recitation path is a firehose (phon/word/recite/mic per ~80ms chunk, plus a full TOKENSTREAM dump at session end), so a single 10-minute session writes tens of thousands of lines into one uncapped file. Every launch spawns another file that lives forever on external storage. Over normal use this accumulates…  
↳ _Fix:_ Cap each run file (rotate/stop at a byte budget) and prune old run_*.log on startup (keep the last N or last M days). Close the sink on lifecycle detach. Consider only opening the file sink under kDebugMode or a debug toggle.

**• single-reviewer — Verbose recitation logging ships enabled in release — no kReleaseMode gate on traceOn or the file sink; always-on TOKENSTREAM dumps the full phoneme stream**  
`lib/util/log.dart:20` · production-log-hygiene  
↳ _Impact:_ A release APK the user distributes writes a detailed behavioral record of a user's Quran/adhkar recitation (which verses, mistakes, timing, audio RMS) to logcat and to an external-storage file on every run, with trace on by default. This is a privacy-sensitive religious-practice trail persisted unencrypted, plus needless CPU/IO from the …  
↳ _Fix:_ Default traceOn to `kDebugMode`, gate initFileSink() and the debugPrint call on kDebugMode (or a user-visible diagnostics toggle), and demote/redact the TOKENSTREAM and per-verse dumps so full token streams and recited-verse identifiers never write in release…

**• single-reviewer — 'Clear' clears only the in-memory buffer, not the on-disk log — the recited-verse history persists after the user thinks it is gone**  
`lib/util/log.dart:122` · log-hygiene  
↳ _Impact:_ A user (or tester) who taps the Clear (delete) action reasonably believes the logs are gone. The on-disk run_*.log — containing the full trace, TOKENSTREAM dumps, and the verses/mistakes recited — remains fully intact and keeps appending. There is no in-app way to delete the persisted log, so the sensitive recitation trail cannot actuall…  
↳ _Fix:_ Make Log.clear() (or a distinct 'Delete log file' action) also truncate/delete the current sink file, or add an explicit purge that removes the logs/ directory. At minimum, relabel the button so it does not imply on-disk deletion.

**• single-reviewer — Fixed-font mushaf disables OS text scaling with no in-app zoom or font-size control, and can shrink Quran text to 12pt**  
`lib/widgets/mushaf_page_view.dart:51` · accessibility  
↳ _Impact:_ A low-vision user who raises their system font to read comfortably gets no enlargement of the Arabic script — precisely the content the app exists to display — and on dense pages the script may render as small as 12pt with full diacritics. This is the exact scenario OS text-scaling is meant to solve, disabled for the users who most need …  
↳ _Fix:_ Keep the fixed-layout page as the default but add an accessible reading path: either an in-app font-scale/zoom control, or a reflowing single-column verse mode that honors `MediaQuery.textScaler`. At minimum, apply a user-configurable multiplier to `kMushafBa…

**• single-reviewer — Footer reveal chevrons, pills, and accent swatches are below the 48dp minimum touch-target size**  
`lib/widgets/reading_footer.dart:165` · tap-target  
↳ _Impact:_ The height-34 chevrons packed close together are error-prone to hit, especially during hands-busy recitation/memorization and for users with motor impairments; mis-taps step the wrong direction (word vs ayah) or fire the adjacent control.  
↳ _Fix:_ Ensure every interactive control reserves at least 48x48dp of hit area (increase padding or wrap in a fixed-size `SizedBox`/`ConstrainedBox`; `IconButton` already enforces this). Increase inter-chevron spacing so adjacent forward/back targets don't overlap th…

**• single-reviewer — ~16 MB of debug/eval test WAV fixtures ship inside the production APK**  
`pubspec.yaml:76` · apk-bloat-test-data  
↳ _Impact:_ Every end user downloads ~16 MB of internal recitation test corpus (including 'alkursi_wrong', 'ikhlas_wrong' negative samples) that has no runtime purpose in a shipped build — pure download/storage waste and leakage of internal test fixtures.  
↳ _Fix:_ Move debug_audio/eval_audio out of the release asset set — e.g. exclude them from pubspec assets and load only in dev, or gate them behind a debug-only flavor. Keep them in-repo for the host eval harness, just not in the shipped bundle.

**• single-reviewer — ~16 MB of developer debug/eval recitation recordings (plus ~2.3 MB dead-pipeline assets) are bundled into the release APK unconditionally**  
`pubspec.yaml:76` · packaging-privacy-bloat  
↳ _Impact:_ Every user downloads ~18 MB of developer test material — private/sample recitation audio recordings and reference tables — that the app never uses at runtime. Bloats the APK and ships internal test audio (potentially of identifiable reciters) to all end users.  
↳ _Fix:_ Move debug_audio/eval_audio behind a debug-only asset variant or strip them from release builds; remove the dead-pipeline JSON assets when the dead code is deleted. Confirm the release APK no longer contains assets/debug_audio and assets/eval_audio.

**• single-reviewer — Supabase sessions schema's generated columns reference fields buildSessionReport never emits — Phase B dashboards will be all-NULL, and the file tells you to run it**  
`supabase/sessions.sql:15` · data-integrity  
↳ _Impact:_ When Phase B is flipped on by a developer following sessions.sql's own instructions, every inserted row gets NULL for words_scored, word_accuracy, avg_pron_prob, major, off_text. Every dashboard/index built on those denormalised columns is silently empty; only the raw JSONB 'report' has real data. Two conflicting sources of truth (sessio…  
↳ _Fix:_ Replace supabase/sessions.sql with the corrected schema from ANALYTICS_PLAN.md:77-98 (kind/surah/reached/tokens/anchored/mistake_count/skipped/app_version), or delete sessions.sql and point the SupabaseAnalyticsSink comment at the plan. Add a test that assert…

**• single-reviewer — `page_render_scan_test.dart` is a print-only test that asserts nothing yet sits in the gate, giving false coverage for portrait-width overflow**  
`test/page_render_scan_test.dart:13` · test-quality  
↳ _Impact:_ A layout regression that overflows or ragged-fills normal portrait pages at common phone widths ships green — the reader's core surface is unguarded in portrait. The file looks like real coverage in the suite listing, masking the gap.  
↳ _Fix:_ Convert the scan to an assertion (e.g. `expect(worst, lessThan(0.5px))` and a ragged-fill floor) so portrait overflow fails the gate, or move it under `tool/` as an explicitly diagnostic script so it isn't counted as a test.

**• single-reviewer — `recitation_tracker_test.dart` pins a superseded/dead engine — the largest tracking-logic test protects code the live app never runs**  
`test/recitation_tracker_test.dart:2` · dead-code-coverage  
↳ _Impact:_ Misallocated coverage and false confidence: green tests suggest the tracker is validated while the live `ReadingState._applyOut`/`_onPcm` orchestration that actually drives follow-along has none. The dead source also inflates the 56-file count and invites confusion about which matcher is authoritative.  
↳ _Fix:_ Delete `recitation_tracker.dart`, `token_match.dart`, `verse_index.dart` (the `VerseIndex` class; the `verse_index.json` asset is loaded separately by `phoneme_corpus.dart`) and this test, OR document why they are retained and redirect the equivalent test eff…


### LOW

**✅ verified (confirmed) — Android Auto Backup is left enabled (no allowBackup=false), so anon_id and recitation logs are backed up to the cloud and adb-extractable**  
`android/app/src/main/AndroidManifest.xml:5` · insecure-backup  
↳ _Impact:_ The stable per-install id and the plaintext recitation logs are copied into the user's Google Drive backup and can be pulled off the device via `adb backup` on non-rooted phones. This undermines the privacy_screen.dart promise that reports are 'written only to this device's diagnostic log' and 'nothing is uploaded anywhere' — the OS uplo…  
↳ _Fix:_ Set `android:allowBackup="false"` (or provide `dataExtractionRules`/`fullBackupContent` that exclude the logs dir and `anon_id`). If backup is desired, explicitly exclude sensitive files.

**✅ verified (confirmed) — INTERNET permission is granted although the app advertises fully-offline operation, enabling silent upload once the Supabase sink is compiled in**  
`android/app/src/main/AndroidManifest.xml:4` · least-privilege  
↳ _Impact:_ The capability to exfiltrate is pre-granted ahead of need. Whoever later builds with `--dart-define=SUPABASE_URL/SUPABASE_ANON_KEY` turns on network upload with only the in-app 'Performance & usage' toggle as a gate and no OS-level signal to the user, despite the current offline messaging. It is a latent least-privilege / expectations ga…  
↳ _Fix:_ Keep INTERNET out of the shipped manifest until the upload feature actually goes live with a published privacy policy (the dev-only `debug`/`profile` manifests already declare it for tooling). When enabled, ensure the consent copy matches that data now leaves…

**✅ verified (confirmed) — Hidden Debug Log screen ships in release builds and exports sensitive logs to the clipboard**  
`lib/screens/debug_log_screen.dart:39` · debug-surface-exposure  
↳ _Impact:_ Anyone with brief physical access to an unlocked device can long-press the home title, read the full recitation history and decoded token streams, and one-tap copy them to the clipboard (from where other apps / keyboards can read them). It also lets a bystander flip the trace firehose on. A hidden gesture is not a security control.  
↳ _Fix:_ Compile the debug entry point and screen out of release builds: wrap the GestureDetector/route in `if (kDebugMode)`, or move it behind a build flag. At minimum, do not expose 'Copy all'/log export in release.

**✅ verified (confirmed) — Full recitation content (surah + verse trace + decoded token stream) is written to a persistent plaintext log on external storage every session, regardless of consent**  
`lib/state/reading_state.dart:640` · sensitive-data-logging  
↳ _Impact:_ The device accumulates an unbounded, plaintext record of which surahs/verses a user recited and where they stumbled — sensitive religious-behavior data — with no rotation or lifecycle. `minSdk = flutter.minSdkVersion` keeps Android <=10 in scope, where `Android/data/<pkg>/files` is readable by any app holding READ_EXTERNAL_STORAGE; on al…  
↳ _Fix:_ Gate all file-sink logging (and the TOKENSTREAM/verse traces) behind `kDebugMode`, or drop the external-storage sink for release builds and log only to the in-memory ring buffer. If a file sink is kept for testing, cap total size, prune old `run_*.log` files …

**✅ verified (confirmed) — `fftea` is a declared-but-unused dependency (dead supply-chain surface)**  
`pubspec.yaml:39` · unused-dependency  
↳ _Impact:_ An unused dependency is pure supply-chain surface with no benefit: it (and any transitive code) is resolved and can end up in the build, must be tracked for CVEs, and misleads readers into thinking on-device FFT still runs. Low severity because it is not currently exploitable, but it should not ship.  
↳ _Fix:_ Remove `fftea` from pubspec.yaml and run `flutter pub get`. While there, note `http` is now pulled in only for the inert `SupabaseAnalyticsSink` (lib/services/analytics.dart) — keep it only if the analytics upload path is intended to be enabled.

**• single-reviewer — Launcher name is the snake_case machine name 'tilawa_ai'**  
`android/app/src/main/AndroidManifest.xml:6` · release-polish  
↳ _Impact:_ Users see 'tilawa_ai' under the home-screen icon and in app settings — an unpolished, developer-facing name for a shipping consumer app.  
↳ _Fix:_ Set android:label to the product name (e.g. 'Tilawa') in the main AndroidManifest.

**• single-reviewer — No app-lifecycle handling: mic, 1s timer, and PCM retention keep running when the app is backgrounded**  
`lib/main.dart:34` · lifecycle  
↳ _Impact:_ Backgrounding mid-recitation leaves the mic capturing with no visible in-app UI; without a foreground service Android may kill the process, silently discarding the in-progress session and its end-of-session review. Battery/CPU also keep being spent on decode while backgrounded.  
↳ _Fix:_ Register a WidgetsBindingObserver at the app root and stop (or explicitly pause) any active ReadingState/DuaReadingState/DuaFinderState session on AppLifecycleState.paused; decide deliberately whether background recitation should continue (and if so, add a fo…

**• single-reviewer — Startup consent race: crashes before AppState's constructor use default-OFF consent, so early-startup crashes are dropped even when the user opted in**  
`lib/main.dart:19` · correctness  
↳ _Impact:_ The crash-safety opt-in silently misses exactly the earliest-startup crashes it is most valuable for, even for a user who enabled it on a prior launch. Errs on the safe side (drops rather than leaks), so no privacy harm — but the feature under-delivers on its stated purpose. Nothing is lost locally (Log.e still records it unconditionally…  
↳ _Fix:_ Read the two consent bools from SharedPreferences (or a lightweight synchronous cache) and set Analytics.instance consent BEFORE installing FlutterError.onError, or buffer early crash reports until consent is resolved and flush/drop based on the resolved valu…

**• single-reviewer — recordCrash is fire-and-forget from inside the error handler with an unguarded await in the default sink**  
`lib/main.dart:20` · robustness  
↳ _Impact:_ If sendSession throws asynchronously (e.g. a plugin/platform-channel failure while the app is already in an error state), it surfaces as an unhandled async error raised from within the crash handler — added instability precisely during a crash. Bounded in practice (when essential consent is on, prefs is already initialised and AnonId is …  
↳ _Fix:_ Wrap the recordCrash call in unawaited(...) with an attached error handler, and guard LogAnalyticsSink.sendSession's AnonId.get()/log in try/catch so the crash reporter can never itself throw.

**• single-reviewer — Tasbih / dhikr counter gives no haptic feedback on tap, though haptics are used elsewhere**  
`lib/screens/adzkar_screen.dart:28` · haptics  
↳ _Impact:_ A tasbih counter is the one control users operate repeatedly without looking; the absence of a per-tap buzz (and any distinct cue on reaching the target count) removes the tactile confirmation users expect from a counter, making it easy to lose count.  
↳ _Fix:_ Fire `HapticFeedback.selectionClick()` on each increment and a stronger `mediumImpact()` when the count completes a set (`v >= d.repeat`).

**• single-reviewer — Debug Log screen and trace toggle ship in release with no build-mode guard**  
`lib/screens/home_screen.dart:42` · debug-surface  
↳ _Impact:_ Anyone with the device can long-press to reveal, copy, and export the full recitation trace and file path, and can turn the verbose firehose on. Bounded (on-device, physical access) but it is a shipped diagnostic/privacy surface that a release build should not carry.  
↳ _Fix:_ Gate the long-press entry point (and ideally the screen route) behind kDebugMode or a hidden developer-mode preference so it is absent from release builds.

**• single-reviewer — _ContinueCard builds a fresh Future on every rebuild, causing a '…' flash**  
`lib/screens/home_screen.dart:219` · future-builder-antipattern  
↳ _Impact:_ The surah name on the Home 'Continue reading' card briefly flashes to '…' on unrelated AppState changes (e.g. toggling theme). Cosmetic but avoidable.  
↳ _Fix:_ Use the synchronous `repo.chapterForPageSync(page)` (already available and used elsewhere) since preload() has run, or cache the future / pass initialData so rebuilds don't reset it.

**• single-reviewer — Dead `_highlighted` set in QuranScreen: never mutated, but merged into a freshly-allocated Set every build**  
`lib/screens/quran_screen.dart:27` · dead-code  
↳ _Impact:_ Confusing dead state that implies a manual-highlight feature that doesn't exist; the per-build Set allocation also defeats any `==`-based child skip. Minor.  
↳ _Fix:_ Delete `_highlighted` and pass `reading.asrHighlightedLocations` directly (it is already the same value passed as currentLocations), or keep the merge only if a manual-highlight path is actually planned.

**• single-reviewer — Cold-loading mushaf page shows a blank page with no loading indicator**  
`lib/screens/quran_screen.dart:255` · loading-state  
↳ _Impact:_ On first open of the reader, or when jumping to an uncached page, the user briefly sees a blank paper page with no signal that content is loading, which can read as a broken/empty page rather than a pending fetch.  
↳ _Fix:_ Show a lightweight loading affordance (centered `CircularProgressIndicator` or a paper-toned skeleton) in the `!snap.hasData` branch instead of `SizedBox.expand()`.

**• single-reviewer — App version is hardcoded a second time in analytics and will drift on the next bump**  
`lib/services/analytics.dart:17` · version-management  
↳ _Impact:_ The moment pubspec is bumped, all analytics/crash reports keep reporting the stale '1.0.0+1' unless someone remembers to hand-edit this constant — making version-correlated crash/usage analysis silently wrong.  
↳ _Fix:_ Derive the build id at runtime (e.g. package_info_plus) or inject it via a build-time --dart-define, rather than duplicating the literal.

**• single-reviewer — Crash report carries the raw exception message verbatim (300 chars) — not scrubbed, despite the 'NO user data' guarantee — before it can feed a network sink**  
`lib/services/analytics.dart:67` · data-minimization  
↳ _Impact:_ Exception strings can embed interpolated values (file paths, asset/verse identifiers, arbitrary state). When the network sink is enabled, these incidental strings would be transmitted under an 'anonymous' promise. Currently gated by essentialConsent and only reaching the local log sink, so low today.  
↳ _Fix:_ Before any network sink is wired, reduce `error` to an exception type + normalized code, or run a scrub (strip file paths / long literals) rather than shipping the raw message.

**• single-reviewer — Crash reports carry no stack or line info — future remote crash telemetry will be near-undiagnosable**  
`lib/services/analytics.dart:74` · crash-capture  
↳ _Impact:_ When the essential/crash opt-in is eventually wired to a network sink (Phase B), the remote reports (a truncated message + library name, no stack, no line, no build ordinal beyond '1.0.0+1') will rarely be enough to locate a crash. The privacy motive is sound, but the feature as designed will not deliver actionable crash diagnostics.  
↳ _Fix:_ Include a path-sanitized/symbol-only top frames summary or a stable error fingerprint (hash of normalized stack) in buildCrashReport, and give crashes their own endpoint/table rather than sharing the sessions sink.

**• single-reviewer — No offline durability: SupabaseAnalyticsSink drops consented reports on any failure — no queue/retry despite the plan requiring one**  
`lib/services/analytics.dart:173` · data-integrity  
↳ _Impact:_ For an offline-first Quran app, recitations done with no connectivity (the common case) are the exact ones that fail the POST and are silently lost the moment Phase B creds are injected — with the user having consented and expecting their data to count. Also every network blip drops a session with no retry.  
↳ _Fix:_ Build the persisted drop-oldest queue (JSON file/prefs) before or together with flipping Supabase creds; SupabaseAnalyticsSink should enqueue on failure and flush on connectivity. Until then, document that Supabase mode is lossy so it isn't enabled prematurel…

**• single-reviewer — anon_id links crash reports to the same install identity as recitation history, added at the sink layer where the PII test can't see it**  
`lib/services/analytics.dart:137` · privacy  
↳ _Impact:_ Anyone with access to the (future) sessions table can join a crash row to a specific install's recitation history (which surah/verses were read, mistakes, timing) via anon_id, since both share the id. Still anonymous per-install (no account/PII), so bounded — but it undercuts the 'distinct, anonymous crash summary' framing in buildCrashR…  
↳ _Fix:_ Decide deliberately whether crash reports should carry the same anon_id as sessions. If not, use a separate crash id or none. Either way, add a sink-level test (not just a report-level one) that pins what is actually put on the wire, since the id is attached …

**• single-reviewer — Live green/red follow-along is phoneme-COVERAGE only, but is documented as pronunciation-quality feedback**  
`lib/services/asr/phoneme_matcher.dart:99` · correctness  
↳ _Impact:_ A maintainer (or a future UI change) may treat the live green as a tajwīd-correctness signal and surface it as such, over-claiming accuracy; users could infer their pronunciation was validated in real time when only word position was tracked.  
↳ _Fix:_ Correct the comment to state green = positional coverage, and keep pronunciation verdicts confined to the post-Stop reviewTajweed path.

**• single-reviewer — Live per-word tajweed feedback is dead: wordDeviations always returns const {}, so the whole deviations render path never fires**  
`lib/state/reading_state.dart:147` · dead-code  
↳ _Impact:_ Misleading dead plumbing across four widgets/state that reads like a working feature; a reviewer/maintainer can't tell the live per-word tajweed underline was intentionally stubbed vs. broken. (Post-recitation mistakes in the sheet are unaffected.)  
↳ _Fix:_ Either wire wordDeviations to real per-word deviations, or delete the dead parameter chain (wordDeviations getter, the deviations field on MushafPageView/_AyahLine/_PageLeaf, and the devColor/underline branch) and drop the stale comment. Leave a TODO if it is…

**• single-reviewer — ReadingState/DuaReadingState _onPcm lack the active/disposed guard that DuaFinderState has, so late chunks mutate post-session state**  
`lib/state/reading_state.dart:301` · race-condition  
↳ _Impact:_ Bounded and mostly cosmetic — a stray chunk during the cancel window can re-mutate `_asrRead`/marker and notify listeners after Stop, and adds a little extra audio to the stream just before finish(). No crash or data loss, but the inconsistency with the finder's guarded callback is a latent footgun (e.g. if the flags/active model changes…  
↳ _Fix:_ Add `if (!_asrActive) return;` / `if (!_active) return;` at the top of both _onPcm methods to match DuaFinderState, so the callback is inert the instant the session flips inactive.

**• single-reviewer — Permanently-denied microphone permission is a dead-end: the same snackbar with no path to settings**  
`lib/state/reading_state.dart:273` · graceful-degradation  
↳ _Impact:_ A user who permanently denied the mic (or denied once on a stricter OEM) can never recover in-app — the core recitation feature is silently unusable with only a transient toast and no guidance, and they have no way to know they must fix it in system settings.  
↳ _Fix:_ When permission is denied, offer an action (e.g. SnackBar action or dialog) that calls openAppSettings() (permission_handler) and explains the mic is required for follow-along.

**• single-reviewer — Re-acquisition self-disables for the rest of a session after 4 fruitless switches, with no in-session re-arm except a manual page turn**  
`lib/state/reading_state.dart:324` · asr-reacquire-robustness  
↳ _Impact:_ A reciter who hits a hard-to-track passage (poor mic, heavy tajwid the model garbles) loses cross-surah follow-along for the rest of the session and must stop/restart or manually turn a page to recover — with no visible indication why tracking died.  
↳ _Fix:_ Re-arm after a cooldown (e.g. reset `_switchCount` after N tokens of no probing, or after a sustained silence gap) rather than latching it off until a manual page turn.

**• single-reviewer — Stop path runs the matcher/haptic/navigation with no _active guard; a queued mic chunk during `await mic.stop()` can buzz a skip or fire a page-turn after the session ended**  
`lib/state/reading_state.dart:301` · asr-lifecycle  
↳ _Impact:_ Rare stray haptic buzz or a page navigation firing just as the user taps Stop; cosmetic/UX only, not data loss.  
↳ _Fix:_ Add `if (!_asrActive) return;` at the top of `_onPcm` (both ReadingState and DuaReadingState), and set `_liveMic=false` before awaiting mic.stop().

**• single-reviewer — No regression test for log.dart despite the known past StreamSink concurrency bug**  
`lib/util/log.dart:76` · test-coverage  
↳ _Impact:_ The _flushing interlock, ring-buffer trim (removeRange at line 70), and file-sink init/flush semantics can silently regress (re-introducing the StreamSink throw into the logging hot path, or losing the trim bound) with the host `flutter test` gate passing.  
↳ _Fix:_ Add a log_test.dart pinning: buffer trims at _max, _write never throws while a flush is in flight (drops to memory only), and flushFile is a no-op when the sink is null — the behaviors the comments say were hard-won.

**• single-reviewer — Page-turn captures 3 full-screen bitmaps per settle and re-captures them again 500ms later**  
`lib/widgets/curl_page_view.dart:85` · redundant-work  
↳ _Impact:_ Each page turn does the 3-page GPU->CPU bitmap readback up to twice; the second pass is redundant whenever the first succeeded. During recitation-driven auto page turns this stacks a capture hitch onto the already-loaded UI isolate.  
↳ _Fix:_ Skip the 500ms fallback when the post-frame capture already produced non-null images (only retry if _curImg is still null), and consider capturing at a lower pixelRatio for the curl bitmap since it is a transient turn effect.

**• single-reviewer — Quran pager offers only swipe/curl for sequential navigation and mounts three pages at once with no Semantics boundaries**  
`lib/widgets/curl_page_view.dart:263` · accessibility  
↳ _Impact:_ Users who cannot perform a horizontal drag (motor impairment, switch access) have no next/previous affordance for turning one page at a time. For screen-reader users, prev + current + next pages of Quran text are all in the accessibility tree at once with no focus management, so traversal reads three pages of ayat with no page boundary.  
↳ _Fix:_ Add explicit previous/next page controls (or make the top bar page label a stepper), and wrap the off-screen neighbour boundaries in `ExcludeSemantics`/`Offstage` so only the current page is exposed to assistive tech.

**• single-reviewer — No golden/render tests for the custom-painted reader UI (page curl, glyph layout)**  
`lib/widgets/curl_painter.dart:1` · test-coverage  
↳ _Impact:_ A visual regression in the core page-curl animation or in Uthmanic glyph placement — the app's central reading experience — would not be caught by any automated test; only the crash case (RenderFlex overflow) is guarded.  
↳ _Fix:_ Add a small set of golden tests for a representative rendered mushaf page and a mid-curl animation frame at a fixed size/font, so pixel regressions in the painter and layout surface in `flutter test`.

**• single-reviewer — Mic/pill/chevron footer controls are copy-pasted across three footer files**  
`lib/widgets/dua_reading_footer.dart:210` · duplication  
↳ _Impact:_ A visual/behavioral change to the mic button or reveal row must be made in 2-3 places and will silently diverge; contradicts the project's 'shared helpers go in lib/, no one-off utility files' rule.  
↳ _Fix:_ Extract shared `RecitationMicButton`, `FooterPillButton`, and `StepRevealRow` widgets (parameterized by callbacks) into a shared widgets file and reuse them from all three footers.


### INFO

**✅ verified (confirmed) — Strength: analytics is privacy-preserving by construction and genuinely inert**  
`lib/services/analytics.dart:99` · privacy-by-design  
↳ _Impact:_ No PII or raw audio can reach a report by construction, consent is off by default, and nothing leaves the device in the shipped configuration. This is a solid privacy foundation worth preserving as the backend is wired up.  
↳ _Fix:_ Keep the allow-list report builder and the default-off consent gates. When the Supabase sink is activated, add TLS-only enforcement and re-verify the analytics_report_test invariant still holds.

**• single-reviewer — Strength: the analytics report is privacy-preserving by construction — opt-in default-off, anonymous, data-minimized, and inert offline**  
`lib/services/analytics.dart:34` · privacy-strength  
↳ _Impact:_ The end-of-session analytics pathway is well-designed for privacy: minimized, anonymous, consent-gated, and non-transmitting in this build. This is the correct baseline; the findings above concern the log/backup/retention paths that sit outside this guarantee.  
↳ _Fix:_ Preserve these properties. Extend the same discipline (minimization, consent, non-egress) to the diagnostic log file and backup posture so the guarantee holds end-to-end, not just for the analytics report object.

**• single-reviewer — Strength: analytics is privacy-by-construction with double-gated consent, and it is well pinned by tests**  
`lib/services/analytics.dart:22` · analytics-privacy  
↳ _Impact:_ Positive: the one path that could exfiltrate recitation data is minimal, opt-in, off by default, currently inert, and regression-tested — a genuinely solid observability/privacy design that the verbose file-logging path (findings above) should be brought in line with.  
↳ _Fix:_ Keep this model; extend the same 'off by default / whitelist / tested' discipline to the file sink and debug logging so the two halves of the observability story match.

**• single-reviewer — Strength: end-of-session report is privacy-safe by construction and well pinned**  
`lib/services/analytics.dart:34` · strength  
↳ _Impact:_ The 'no audio / no PII' guarantee is enforced by data-flow construction rather than by review vigilance, and the gate semantics are regression-tested. This is the right design for a consent-sensitive religious-practice app.  
↳ _Fix:_ Keep it. When adding a network sink, extend the same whitelist-by-construction discipline to the sink layer (test what is actually POSTed, including anon_id).

**• single-reviewer — Strength: clean AsrEngine seam, pure host-testable decision functions, and privacy-by-construction analytics**  
`lib/services/asr/asr_engine.dart:15` · strength  
↳ _Impact:_ These seams are the right ones to build on for iOS/i18n: the engine boundary and the pure functions are reusable, and the analytics whitelist prevents audio/PII leakage even as the sink changes.  
↳ _Fix:_ Preserve and extend this pattern — route the recitation-session refactor (findings #1/#2) through the same AsrEngine seam and keep new tuning logic in pure functions.

**• single-reviewer — Strength: deliberate, well-reasoned resilience in the mic/engine layer and session teardown**  
`lib/services/asr/mic_source.dart:28` · resilience-strength  
↳ _Impact:_ These patterns materially reduce crash surface around the highest-risk native resources (mic, ONNX model, IO logging) and around double-tap / preemption races on the single shared engine.  
↳ _Fix:_ Keep these; extend the same intent to the gaps above (page-load error UI, lifecycle stop, autoStart error surfacing).

**• single-reviewer — Strengths: disciplined RepaintBoundary/curl-capture isolation and well-guarded per-reader async lifecycle**  
`lib/state/dua_reading_state.dart:403` · strength  
↳ _Impact:_ These patterns are sound and worth preserving. Note one asymmetry: the app-global ReadingState (Quran) has no `_disposed` guard like DuaReadingState, which is currently safe only because it is a top-level provider that is never disposed during the app's life (main.dart:44).  
↳ _Fix:_ Keep the per-reader guard pattern; if ReadingState ever becomes screen-scoped, add the same `_disposed` guard to its timer and post-await notifies.

**• single-reviewer — Good bounded-memory and caching discipline in the hot paths**  
`lib/state/reading_state.dart:178` · strength  
↳ _Impact:_ These choices keep worst-case memory bounded and prevent the most expensive per-word work (regex tajweed parse, TextPainter measurement) from recomputing on every rebuild — they meaningfully limit the blast radius of the rebuild-churn issue above.  
↳ _Fix:_ Preserve these patterns. When fixing the rebuild churn (finding above), keep the memoized spans/widths and shared-engine design intact.

**• single-reviewer — Solid re-entrant-stop idempotency and pure, host-testable concurrency helpers**  
`lib/state/reading_state.dart:608` · strength  
↳ _Impact:_ The hardest re-entrancy cases (double Stop, engine-disposed-during-start, matcher/stream freeing) are handled deliberately and are testable off-device, which is why the pipeline is mostly robust despite the shared mutable engine.  
↳ _Fix:_ Keep this pattern; extend the same synchronous-flag-before-await and post-await re-check discipline to close the start-window preempt gap in finding 1.

**• single-reviewer — STRENGTH: live matcher decision logic is cleanly extracted as pure, host-testable functions with dedicated tests**  
`lib/state/reading_state.dart:777` · strength  
↳ _Impact:_ The genuinely-live re-acquisition debounce, stall detection, and tajwid review are unit-testable in isolation and are actually covered, which materially lowers regression risk on the parts that ship.  
↳ _Fix:_ Preserve this pattern; when the dead token-based pipeline is removed, keep these pure extractions and their tests as the canonical spec for the live pipeline.

**• single-reviewer — Strength: RTL Arabic handling and dark-accent contrast floor are handled deliberately and consistently**  
`lib/widgets/mushaf_page_view.dart:363` · rtl  
↳ _Impact:_ RTL correctness and dark-mode accent legibility — common failure points in Arabic apps — are addressed thoughtfully; this is a solid base to build the a11y/i18n gaps above onto.  
↳ _Fix:_ Keep this discipline; extend the same accent-legibility reasoning to the light theme (see the contrast finding) and the same RTL awareness to a future app-level Directionality when locales are added.

**• single-reviewer — Solid supply-chain hygiene: fully pinned lockfile, all deps from pub.dev, coherent recent versions**  
`pubspec.lock:1` · supply-chain-strength  
↳ _Impact:_ Reproducible, verifiable dependency resolution with a small, mainstream transitive set — a genuine strength that materially lowers supply-chain risk relative to the licensing gaps above.  
↳ _Fix:_ Keep the lockfile committed. Add a periodic `flutter pub outdated` / advisory check (there is no CI today, .github is absent) so version drift and future CVEs are caught, and pin the direct-dependency `^` constraints if you want the lock to be the sole source…

**• single-reviewer — No CI/CD — the test + analyze gate is entirely manual with no enforcement**  
`pubspec.yaml:45` · ci-cd  
↳ _Impact:_ Nothing automatically enforces the 21-test suite or the analyzer before an APK is cut on a ~10k-LOC app, so a regression or analyzer error can ship if the manual step is skipped. Acceptable for a solo project but a real gap as it grows.  
↳ _Fix:_ Add a minimal CI workflow (flutter analyze + flutter test on push/PR); optionally a release job that builds the signed AAB once signing is fixed.

**• single-reviewer — Strength: risky logic is deliberately extracted into pure functions and pinned with focused, real-capture regression tests**  
`test/analytics_report_test.dart:119` · strength  
↳ _Impact:_ This is the correct architecture for an on-device-ASR app where the stateful shell can't run host-side: the highest-risk correctness and privacy logic IS host-testable and is tested, including with captured real-audio fixtures rather than only synthetic data.  
↳ _Fix:_ Keep applying this extraction discipline to the currently-untestable emission/marker/slice glue (findings above) so the on-device gap keeps shrinking.

**• single-reviewer — Reference phoneme corpus is byte-for-byte validated against canonical data — strong data integrity**  
`tool/corpus_validation_report.txt:1` · strength  
↳ _Impact:_ The reference side of the pipeline (what the reciter is scored against) is trustworthy Qur'an content, which is the most safety-critical asset in the app; false positives/negatives therefore stem from the model/heuristics side, not corrupt reference text.  
↳ _Fix:_ Keep validate_corpus.py / validate_align.py in the ship gate (add to CI once it exists) so any future corpus regeneration re-proves this invariant.


## Cross-cutting themes
- **"Offline & private" is aspirational, not enforced.** Logging, Auto Backup, mic lifecycle, and PCM retention all leak past the stated posture.
- **Debug/eval tooling ships in production.** The hidden Debug Log screen, ~16 MB of test WAVs, and the eval entry points are all in the release build.
- **Dead vs. live code is ambiguous.** The superseded hand-rolled engine (~642 LOC) still sits beside — and is still *tested* alongside — the live sherpa pipeline.
- **Duplication invites drift.** The three recitation states re-implement the same tuning constants and heuristics; a fix must be made in 2–3 places.
- **The test suite is strong where it can reach and blind where it can't.** Excellent pure-function tests; the platform-channel-bound orchestration and the actual Qur'an *content* have no host gate; and there is no CI.

## Roadmap
**Now — release gates (days):** real signing keystore; `allowBackup=false`; gate file-logging + the Debug Log screen + eval assets behind `kDebugMode`; stop the mic on tab-away/background; wipe PCM on Stop; add LICENSE + an in-app license/attribution page; rename the "Essential app data" consent toggle; add `NSMicrophoneUsageDescription` before any iOS build.

**Next — quality (weeks):** move ONNX inference to a background isolate; scope `context.watch` so the mushaf doesn't rebuild on every mic chunk; add `PlatformDispatcher.onError` / `runZonedGuarded` crash capture; add a `snap.hasError`/retry branch and stop caching failed page futures; fix the tajwīd reliability gate (Wilson lower bound / minimum sample size); add a Dart Qur'an-content-integrity test; add CI (`analyze` + `test`); add `Semantics` to the mic/chevron controls; ship an App Bundle + enable minify/shrink.

**Later — architecture (sustained):** extract a shared `RecitationSession` service and collapse the three near-duplicate states; delete or quarantine the dead hand-rolled engine and its test; hoist the matcher's per-chunk O(n²) collapse; remove or wire the dead `deviations` path.

## Strengths (credit where due)
- Analytics is privacy-preserving *by construction* — pure builders, consent-gated, no audio/PII by design (verified).
- The pure-function extraction pattern (`identifyDua`, `MicOwnership`, `decideReacquire`) with focused tests is genuinely good discipline.
- The mushaf data is now verified line-for-line against quran.com; content correctness is taken seriously.
- The single-owner mic + shared engine fixed a real resource-churn bug; adversarial review is baked into the workflow.

---
_Method note: findings were produced by independent per-lens agents reading the source, then adversarially verified. This run was truncated by a session token limit, so verification is complete for security and dependencies/licensing and partial elsewhere; single-reviewer findings are high-signal but should be confirmed against the code before acting. Full per-finding evidence (exact snippets + verifier notes) is preserved in the session's review digest._
