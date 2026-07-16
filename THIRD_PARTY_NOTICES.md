# Third-party notices — TilawaAi

TilawaAi bundles and redistributes the components below. Their terms apply in
addition to this app's own license. The same notices are surfaced in-app under
**Settings → About → Licenses & Attribution** (via `showLicensePage`).

> **Release gate:** several entries below have `[TODO]` markers. Resolve every one
> — with the exact upstream license text and, where noted, written confirmation
> from the author — **before** any public store listing or monetized release.

## ASR model — `Muno459/zipformer_p-quran`
- Streaming zipformer2-ctc phoneme model (`assets/asr/phoneme/model.int8.onnx`, ~72 MB) used for recitation follow-along.
- Source: Hugging Face (gated repo). License: **free for NON-COMMERCIAL use** ("for the sake of Allah") — no selling, subscriptions, paywalls, ads, or revenue — and the terms must be **passed on** to recipients.
- **[TODO]** Paste the model's exact license text here and in `lib/util/licenses.dart`. Confirm in writing with the author that bundling/redistributing the weights inside a distributed APK is permitted. If the app ever monetizes, this must be relicensed or the model swapped.

## Qur'an font — KFGQPC "UthmanicHafs"
- `assets/fonts/uthmanic_hafs.ttf` (~242 KB), via QUL / quran.com. Renders the mushaf.
- Redistributed under the KFGQPC font EULA (generally: Qur'anic-content use, attribution required, restrictions on modification/commercial use).
- **[TODO]** Bundle the exact KFGQPC/QUL font EULA text and record the exact font version (e.g. "UthmanicHafs1 VerNN"). Confirm the redistribution + (non-)commercial terms match the app's business model.

## Qur'an text, tajwīd markup & page layout
- `assets/mushaf/*.json` (604 pages), per-word Uthmani text, tajwīd HTML, juz/hizb metadata.
- Sources: quran.com API v4 / QUL, and the `zonetecde/mushaf-layout` dataset (see `tool/fetch_*.py`, `tool/merge_tajweed.py`). Layout openers were locally corrected (`tool/fix_openers*.py`); Qur'anic word text is unmodified and was verified line-for-line against quran.com.
- **[TODO]** Record the exact upstream commit/version of `zonetecde/mushaf-layout` and the quran.com/QUL data terms; confirm redistribution-with-attribution is permitted and pin the fetch scripts to immutable revisions.

## ONNX Runtime
- Bundled natively by the `sherpa_onnx` package. **Apache License 2.0**, © Microsoft.

## Dart / Flutter packages
- `flutter`, `sherpa_onnx` (Apache-2.0), `provider`, `shared_preferences`, `http`, `record`, `audioplayers`, `fftea`, `uuid`, `path_provider`, `cupertino_icons`. Their license texts are auto-aggregated into the in-app license page by Flutter.

## This app
- **[TODO]** Add a top-level `LICENSE` for TilawaAi's own source (your choice — e.g. a permissive or a source-available license) so the project's terms are explicit.
