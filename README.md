# Sanad

Recite the Qur'an, Adhkār, and Hadith aloud and be followed word by word — all
on-device, no network.

A streaming phoneme ASR model listens as you recite and lights each word as you
reach it, across three collections: the mushaf (15-line, tajwīd-coloured), Hisn
al-Muslim, and Bukhārī + Muslim. There is also voice and typed search over all
three, post-recitation tajwīd review, and a voice-driven tasbīḥ counter.

## Layout

| Path | What |
|---|---|
| `lib/services/asr/` | the matcher, localizer and phoneme corpora — the core |
| `lib/state/` | one reading state per collection, plus voice search |
| `lib/screens/`, `lib/widgets/` | UI; the three list tabs share `SearchListScaffold` |
| `assets/asr/` | phoneme model + per-collection corpora (git-lfs) |
| `site/` | the marketing site (`sanad.ylensolutions.com`), deployed separately |
| `docs/` | pipeline, model and review notes |

`HANDOFF.md` is the live state of the project — start there. Its top section is
always the current resume point; everything below it is a dated log.

## Working on it

```
flutter test        # host suite
flutter analyze
./run_eval.ps1      # on-device recitation eval (adb)
```

Device testing is not optional here: the host suite feeds the matcher its own
reference phonemes, which proves the plumbing runs but says nothing about real
audio. Anything touching the ASR path needs a real recitation before it counts.
