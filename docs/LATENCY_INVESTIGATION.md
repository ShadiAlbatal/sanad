# Verse-boundary latency — investigation log

Live tracking of the "marker lags at verse ends" problem. Each attempt records
**what we're testing, how, and the result**. Newest attempt at the bottom.

## Problem

During live follow-along the marker flows word-to-word inside a verse, but at a
**verse boundary** it freezes on the verse-final word for several seconds, then
jumps ahead in a burst to catch up. Reported by the user as "lags at verse ends".

## Evidence from the pulled device logs (`pulls/run_20260715_005926/logs`)

Parsed all 6 real recitation sessions. Per-word marker dwell:

| Position | Marker dwell |
|---|---|
| Mid-verse words | 0.86 – 1.3 s (median) — flows, trails by ~1 word |
| **Verse-final words** | **3.2 – 7.1 s** (one outlier 10.9 s) |

Representative boundaries (session `run_20260715_010133`):

| Boundary | Verse-final word held | Then jumped to |
|---|---|---|
| 2:6 → 2:7 | 4.2 s | 2:7:4 (burst through 2:7:2,3 in ~140 ms) |
| 2:7 → 2:8 | 3.2 s | 2:8:2 |
| 2:17 → 2:18 (`run_...004606`) | 5.65 s | 2:18:3 |

The `[mic] chunk#` audio clock advances continuously through every freeze (a
chunk every ~80 ms, no gaps). **But** the mic logs a chunk whether the audio is
speech or silence, so continuous chunks do **not** prove the reciter was talking.

## Hypotheses

| # | Hypothesis | Status | Note |
|---|---|---|---|
| H1 | At the next verse it drops to a wide/global search | **FALSE** | `ANCHOR lock` fires exactly once per session, never re-fires; no wide-search event in any log. |
| H2 | The 0.8 s silence buffer causes it | **FALSE (as per-verse cause)** | `_tailPad` (0.8 s) runs only in `SherpaAsr.finish()` — once, at end of the whole recitation, not per verse. |
| H2′ | The model's *inherent* ~0.8 s right-context contributes | **TRUE but partial** | zipformer2-ctc emits a word only after ~0.8 s of following audio. Explains ~0.8 s of the freeze, not the full 3–7 s. |
| H3 | Reciter's natural waqf (breath pause) at the verse end | **UNKNOWN** | Can't be separated from engine buffering with current logs. |
| H4 | Marker is display-clamped behind the strict frontier | **UNKNOWN** | `rawCursor = min(_head, _reached+1)`; if `_head` is already in the next verse but `_reached` lags, the marker is pinned. Need `_head`/`_reached` logged to confirm. |

## Mechanism (from `phoneme_matcher.dart`, unverified split)

Freeze duration ≈ (waqf pause, H3) + (~0.8 s right-context, H2′) + (time for the
localizer to accumulate enough next-verse phonemes to cross, gated by
`crossed`/`_reached≥vEnd`) + (display clamp catch-up, H4). We do **not** yet know
the size of each term. That's what Attempt 1 measures.

---

## Attempt 1 — Instrument to split the freeze (measure before fixing)

**Goal:** decide H3 vs H4 (reciter pause vs engine/matcher clamp) and size H2′.

**How:** add two decisive signals to the per-chunk `[recite]` trace, no behavior change:
- `rms=` — RMS energy of each mic PCM chunk. Silence during a freeze ⇒ reciter
  paused (H3). Speech-level energy during a freeze ⇒ engine/matcher (H4/H2′).
- `head= reach= ay= loc=word/score toks=` — matcher internals + cumulative phoneme
  count. If `toks` keeps growing and `head` moves into the next verse while the
  displayed `cursor` stays pinned ⇒ display clamp (H4). If `toks`/`head` stay flat
  ⇒ model isn't emitting (pause or right-context).

**Files:** `phoneme_matcher.dart` (getters), `reading_state.dart` (`_onPcm` RMS +
enriched `[recite]` log).

**Status:** implemented, `flutter analyze` clean, debug APK built OK. Awaiting a
device run (`.\run_eval.ps1`, recite ~3 verses across 2 boundaries, Ctrl+C to pull).

**How to read the result** — find a boundary where `cursor`/`cur` stays pinned,
then look across the frozen chunks:

| During the freeze | Verdict |
|---|---|
| `rms` drops to near-0 | Reciter paused (waqf breath) → H3, natural, not a bug |
| `rms` stays high **and** `toks` flat, `head` flat | Model not emitting under speech → H2′ right-context |
| `toks` grows, `head` moves past `reach` into next verse, `cursor` still pinned | Display clamp → H4, fixable in the matcher |
| `loc=word/score` sits below 12 on next-verse words | Localizer score floor gating the cross |

**Result: root cause found — a forward-frontier acceptance-window deadlock.**
Device run `run_20260715_012628` (Al-Baqara 2:17→2:21). Classified every freeze
≥1.5s with the new fields. In **every** freeze:
- `rms` stays high (means ~700–1500, peaks 3000–6600) with only brief inter-word
  dips → **the reciter is actively reciting, not pausing. H3 disproven.**
- `toks` keeps climbing (+13 … +68 during a freeze) → **the model keeps emitting
  phonemes. H2′ is not the blocker either.**
- The localizer `loc` tracks the reciter forward at **score 40–72 (floor is 12)** —
  well ahead of the frozen frontier. On the worst freeze (2:20:7, **26.6s**), `loc`
  climbed 182→**199** (~11 words) while `head`/`reach` stayed nailed at 188/187.

So the engine *has* the reciter's position; the frontier just won't move to it.
Mechanism (`phoneme_matcher.dart`): the frontier advances ≤1 word/chunk and only
accepts a localization inside `[reachLo, reachHi]` where `reachHi ≈ reached+2`
(or `nextStart+2` near a verse end). The streaming model emits in **bursts** and
the reciter moves continuously, so `loc` routinely lands **beyond `reachHi`** →
`use.word <= reachHi` fails → **rejected** → `head`/`_wordBestFrac` never update →
frontier deadlocks. `cursor = min(head, reach+1)` is pinned to the stuck frontier.

Two sub-modes seen: (a) **loc far ahead of reachHi** (bursty jump) — the dominant,
**non-recovering** case (2:20:7=26s, 2:21:6=17s only cleared on a manual stream
restart); (b) **loc lagging at an elongated verse-final word** so tokens accrue
slowly (2:18:6=5.7s) — self-recovers once the alignment extends. The §3b
lookahead only widened `reachHi` by 2 words near boundaries — too small, and it
doesn't help mid-verse bursts at all.

**Verdict on hypotheses:** H1 false, H2 false, H2′ minor, H3 false. Real cause =
**forward acceptance window too tight for the model's bursty emission** (a stronger,
upstream form of H4 — not merely a display clamp; the frontier itself is stuck).

---

## Attempt 2 — Forward relocation probe

**Goal:** let the frontier leap forward to the localizer when it confidently sits
ahead of the window, so the marker catches up instead of deadlocking.

**How:** add a FORWARD probe symmetric to the existing backward re-anchor
(`phoneme_matcher.dart`). When `loc.word > reachHi` with `score ≥ floor`, and the
forward region is **stable for `_fwdStableNeed` chunks** (guards against a spurious
one-frame jump on a repeated phrase), re-score the landing region, mark the leapt
gap as read (optimistic in-order assumption — mistakes scoring is stubbed, so this
only affects the hidden-mode reveal), and jump `_reached`/`_head`/`_curAyah` onto
`loc.word`. Logs `FWD relocate -> wN`.

**Tradeoff:** optimistic-greens the leapt gap (assumes the reciter recited it in
order). If they actually skipped a verse it would show as read; acceptable for
follow-along and revisitable once mistake-scoring is un-stubbed.

**Design correction (caught before shipping):** first cut gated the leap on a
*stable localizer region* (copied from the backward probe). But a forward-moving
reciter changes word every chunk (device data: `loc` 190→193→195→197→199), so the
region never stabilizes and it would never fire. Changed to a **consecutive
"confidently ahead" counter** (`_fwdAheadNeed=4`) plus a **leap cap**
(`_fwdMaxLeap=30`) to reject spurious long-range/back-jump matches (the log showed
noisy `loc` back-jumps to word 150). Both constants are tunable on device.

**Test:** `test/phoneme_matcher_test.dart` → "leaps the frontier forward when the
localizer is far ahead" — drops an 8-word block mid-surah so the localizer lands
past the window; asserts the cursor leaps the gap instead of freezing. Passes
(cursor 28/29); would deadlock at ~word 10 without the probe. All 8 tests green.

**Status: ABANDONED before device test.** The user pointed out they already built
this app in React Native (`../ZikirAi`) and it followed verse boundaries fine with
the *same* ported matcher. So the freeze is a **port divergence, not a missing
feature** — a forward-relocation probe would be a band-aid over a regression I
introduced. Superseded by Attempt 3.

**Result:** withdrawn (see Attempt 3).

---

## Attempt 3 — Align the Dart matcher to the RN reference

**Trigger:** the working RN implementation (`ZikirAi/src/lib/matcher/`) is ground
truth. Compared it against the Dart port line by line.

**Findings from the comparison:**
- **Tokenization — ruled out.** RN feeds sherpa's tokens as a space-joined string
  and re-tokenizes via `createPhonemeTokenizer` (greedy longest-match). But sherpa
  already emits the 251 units space-separated, and the tokenizer skips whitespace,
  so re-tokenizing is **identity** vs the Dart path (raw tokens + `collapse`).
  Equivalent — not the cause.
- **The real divergence.** RN's `recompute` is *simpler*: `reachHi = fwdEdge`
  (reached+2), and its **entire** boundary handling is the `SHORT_TAIL` recency
  rescue + the natural `reached≥vEnd → curAyah++` slide. It has **no** verse-peek
  lookahead, **no** "crossed-early", **no** forward-rescue. All of that was added to
  the Dart port in the §3b "tuning" (and Attempt 2 added a forward-relocation on
  top). That extra machinery is what diverged from the version that worked — and
  it's what produced the 26s non-recovering deadlocks (`crossed`/verse-peek move
  `curAyah`/`reachLo` around and strand the frontier).

**How:** reverted `phoneme_matcher.dart` `_recompute` to match RN exactly — removed
verse-peek lookahead, crossed-early, forward-rescue, and the Attempt-2 forward
probe (and their constants/fields). Kept the Attempt-1 instrumentation. Added a
`TOKENSTREAM` dump on stop so a real freeze can be replayed host-side through both
matchers.

**Host-side validation (no device needed):** ported RN's own regression test
`ayahBoundaryFreeze.test.ts` to Dart — it replays a **real captured** Al-Fatiha
token stream (ayah 2→3, the "ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ" repeated-phrase freeze) through
the matcher. **Passes: `maxCursor=9` (≥8 required)** → the reverted port tracks the
boundary exactly like RN; the localizer/aligner port is faithful (not the divergence).
All tests pass, `flutter analyze` clean.

**Status:** implemented; tests green; debug APK to build. Awaiting a device run of
the same Al-Baqara passage: does the reverted (RN-parity) matcher still freeze? If
not, §3b was the cause — done. If it does, grab the `TOKENSTREAM` line and replay it
through the RN matcher (`ZikirAi`, jest) to localize the remaining divergence.

**Result:** device run `run_20260715_045609` (Al-Baqara from ~ayah 16). The revert
worked — the 26s non-recovering deadlocks are GONE (max freeze now 13.6s and it
recovers). But two DISTINCT residual sticks were found, neither a matcher bug:

1. **Mid-verse "hang on words" = corpus word → multi-glyph MERGES.** 13% of
   Al-Baqara corpus words cover 2–5 mushaf glyphs (word 173 = ظُلُمَـٰتٌۭ وَرَعْدٌۭ
   وَبَرْقٌۭ يَجْعَلُونَ, 4 glyphs). The matcher tracks per corpus word; the marker
   showed only `primary()` (first glyph), so it sat on glyph 1 while the whole
   phrase was recited, then jumped. RN never showed this (it displayed corpus
   words, not the finer mushaf). **FIXED (Attempt 4 below).**
2. **Verse-end "stuck between verses" = waqf pause + re-acquisition.** At 2:19:18,
   13.6s: reciter hit the verse end, `rms`→18 (~3s silent waqf), then the marker
   waited for next-verse phonemes. Inherent to the strict frontier (RN has it too).
   NOT fixed — the §3b machinery that tried to was what caused the deadlocks.

---

## Attempt 4 — Highlight the whole current corpus word (fixes issue 1, the RN way)

Checked how ZikirAi (`QuranReadScreen.tsx`) handled this — it does NOT step a point
marker. Each printed mushaf word carries a matcher-word RANGE `[wordIndex,
wordIndexEnd]` and is "current" when `cursor` is anywhere in it, so a merged phrase's
glyphs all light together and a split glyph stays lit across its letter-words. The
marker is a RANGE, not a point. (My first cut here was a `frac`-based point-stepper —
a worse reinvention; reverted.)

**How:** `SurahClip.glyphsOf(cursor)` = all mushaf glyphs of the current corpus word;
`reading_state` exposes `asrHighlightedLocations` (set); `mushaf_page_view`'s
`isCurrent` is now set-membership (`currentLocations.contains(word.location)`) instead
of a single-glyph `==`; the whole set also joins the reveal set. So on a merged word
the entire phrase highlights as current instead of the marker hanging on glyph 1.
Pinned by `current highlight covers every glyph of a merged corpus word`.

**Status:** implemented; analyze clean; 10/10 tests pass; APK built. Awaiting a device
run to confirm the mid-verse hang is gone.

**Result:** device run confirmed the merge highlight helped. Remaining verse-end
report (user): "at the verse end it hangs, then JUMPS to ~word 3 of the next verse."

## Attempt 5 — Smooth the verse-end catch-up (fixes the JUMP)

Confirmed in logs: cursor `2:18:6 → 2:19:2 → 2:19:4` — teleports, skipping glyphs.
The **hang** is real model latency (waqf silence + right-context — nothing to show
during it, inherent). The **jump** is the fixable part: when the model bursts the
next verse's phonemes in, `reached` advances several words at once and the marker
teleported (RN shows forward moves immediately too). Fix: a display-layer
`_markerCursor` that steps forward ≤1 corpus word per chunk (backward + very large
relocations still immediate), so the catch-up WALKS through the glyphs. Matcher
untouched (RN parity kept). Analyze clean, tests pass, APK built.

Note: this smooths the jump; the hang length ≈ your waqf pause + ~0.8s model
right-context and is largely inherent (the model hasn't emitted the next words yet).

**Result:** _pending device run._
