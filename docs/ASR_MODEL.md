# ASR model — the one we use (and want)

**This is the correct model. Do not swap it for a fastconformer or NeMo variant.**

## Source
- **Hugging Face (gated):** `Muno459/zipformer_p-quran` →
  https://huggingface.co/Muno459/zipformer_p-quran (request access / `hf auth login`).
- "Quran Phoneme Zipformer · streaming · tajwīd-aware", **65.5M params**, streaming
  `zipformer2_ctc`, **phoneme** output. **#1 streaming** on the Quran-Lab leaderboard
  (**5.83 WER**; the fastconformer *streaming* variant is 11.96 — ~2× worse).
- Fine-tuned from `Muno459/zipformer_p-arabic` on Qur'an (Ḥafṣ, madd 4/4/4/4).
  Deterministic phoneme targets (not LLM) — that's why it's sharp.

## What we bundle (pulled straight from that page)
- `assets/asr/phoneme/model.int8.onnx` — **72,705,392 B** = repo's
  `quran_phoneme_zipformer.int8.onnx` (73 MB INT8 streaming ONNX). Verified byte count.
- `assets/asr/phoneme/tokens.txt` — **251** lines (250 phoneme units + blank).

## Config the model expects (from the model card) vs ours (`sherpa_asr.dart`)
| Param | Model card | Ours | Match |
|---|---|---|---|
| Front end | 80-bin kaldi fbank (povey, 25/10 ms, 16 kHz) | `FeatureConfig(sampleRate:16000, featureDim:80)` | ✅ |
| Head / decoding | single CTC, **no LM**, greedy | `decodingMethod: 'greedy_search'` | ✅ |
| Model type | streaming zipformer2-CTC | `modelType: 'zipformer2_ctc'` | ✅ |
| Units | 250 + blank | tokens.txt = 251 | ✅ |
| Streaming params (chunk/context) | **embedded as ONNX metadata — sherpa auto-configures** | not set (correct) | ✅ |

No external CMVN file needed (unlike the old fastconformer's `streaming_global_cmvn.npz`).

## License — IMPORTANT
Free / **non-commercial** ("for the sake of Allah"), NOT Apache-2.0. Use only in apps
that are **FREE to end users** — no selling, subscriptions, paywalls, ads, or revenue —
and pass the terms on. Relevant if TilawaAi is ever monetized.

## Useful upstream files still on the repo (not yet pulled)
| File | Why we'd want it |
|---|---|
| `config.json` (182 B) | Byte-exact confirm of the above (informational; streaming params are in the ONNX metadata). |
| **`ordered_quran_phonemes.json`** (5.11 MB) | Authoritative per-āyah phoneme corpus — 6236 āyāt, connected-recitation, **model-exact 0 OOV**. Could validate/replace our second-hand `assets/asr/quran_phonemes/*.json` and clean up the corpus↔mushaf alignment (the 49 muqaṭṭaʿāt edge āyāt). |
| **`quran_text2phoneme.json`** (3.88 MB) | Canonical text→phoneme table — a cleaner basis for corpus-word→mushaf-location mapping than `tool/build_phoneme_align.py`'s difflib heuristic. |
| `quran_per_eval.py`, `quran_wer_retrieval.py` | Author's PER/WER scripts — align `eval_runner.dart` metrics to the published 5.83 WER. |
| `phoneme_units.json` | JSON form of the 251 units (validation cross-check). |

Skip: `.onnx`/`.pt` (263 MB fp32 / PyTorch) — only for re-quantize/fine-tune; we ship int8.

## Validation results (2026-07-15)
**Corpus (`tool/validate_corpus.py`):** our `assets/asr/quran_phonemes/*.json` is
**byte-identical** to canonical `ordered_quran_phonemes.json` — 6236/6236 āyāt,
67,264/67,264 words, 0 diffs. Model-exact; not a source of error.

**Corpus→mushaf alignment — FIXED 2026-07-15.** Root cause: `build_phoneme_align.py`
aligned on the corpus `words` field, which is a **lossy per-group label** (for a merged
group it lists only ONE of the words it covers — e.g. 2:263's 5 groups spell all 11
mushaf words in phonemes but `words` shows just 5), so it silently dropped mushaf glyphs
on 49 āyāt (mostly REGULAR verses — 2:263, 6:98, 66:5… — not muqaṭṭaʿāt as old notes
claimed). Rewrote the aligner to align on the **phonemes** (complete) via a **monotonic
block DP** (merge-blocks 1×b, split-blocks a×1) that guarantees complete, in-order
coverage and identity when counts match, handling muqaṭṭaʿāt splits + merges together.
- **Now 6236/6236 āyāt: complete, in-order, 0 extras, identity on all equal-count āyāt**
  (`tool/validate_align.py`, which also has a per-group phoneme↔mushaf sim floor as a
  boundary-regression guard). 11:1 muqaṭṭaʿāt correct (الٓر → glyph 1). Pinned by Dart
  tests (surahs 1,2,11,66,112,114).
- **Known cosmetic residue (2026-07-15 review):** on **13 āyāt** (66:5, 2:230, 9:109,
  11:48, 12:21, 12:100, 14:11, 21:87, 21:109, 22:26, 34:9, 36:18, 37:11, 53:26) an
  assimilated particle (أَن/إِن/مِن…) is attached to the **tail** of the preceding merge
  group instead of leading the next (bag-similarity + assimilation makes the boundary
  genuinely ambiguous). Impact is cosmetic: the particle is always the group's LAST word,
  so `primary()` (=first loc) and the marker are unaffected — the word just greens ~1
  group (~a few hundred ms) early, and it WAS recited. Not fixed (primary marker correct;
  the "right" boundary is ill-defined under connected-recitation assimilation).
- `quran_text2phoneme.json` was NOT the right tool (9112-entry retrieval table, not
  āyah-indexed); `verse_index.json` (mushaf word counts) was the independent check.
- Aligner runtime ~1.5 min (build-time only).

## Host-side audio eval (`tool/eval_audio.py`) — no device needed
The Python `sherpa_onnx` 1.13.4 package runs the SAME `model.int8.onnx` on the host, so
we can eval real recordings without the phone (audio decoded via bundled ffmpeg from
`imageio-ffmpeg`). It runs the streaming model over `audio/*` + `assets/debug_audio/*`,
greedy-tokenizes the heard phonemes, and aligns them to the expected āyah/surah corpus.
Results (2026-07-15): correct short recitations 95–100% word coverage (Fātiḥa 29/29,
Ikhlāṣ 14/14, Kursī 44/46); **Al-Baqara āyāt 1–22 (7 min): 97% of 233 words, PER 35%** —
the full pipeline (model+corpus+alignment) tracks real audio. Off-text controls low (azan
28%, thabat 46%). Caveats: global alignment isn't localized, so score a partial recitation
against its actual āyah RANGE (see `TARGETS`), not the whole surah; and global coverage is
NOT a per-word mistake detector (the `*-wrong` controls are mostly-correct audio with
localized errors, so they still cover ~98% — catching those needs the stubbed per-phoneme
scoring). Full heard-phoneme dumps in `tool/eval_audio_report.txt`.

## Why this model (not the other two in ZikirAi)
ZikirAi has 3 selectable models: two **offline** word-CTC (`nemo_ctc`: NeMo + Muno459
fastconformer, decode 5 s segments) and this one — the **only streaming** model. Live
follow-along needs a continuous stream (marker moves as you recite, survives breath
pauses) → requires the online recognizer. Phoneme output also sidesteps the
imlaei-vs-Uthmani spelling problem that broke word matching.
