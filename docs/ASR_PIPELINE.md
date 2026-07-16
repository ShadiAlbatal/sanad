# TilawaAi — On-Device Quran ASR Pipeline (A→Z)

Live "read-along the mushaf" with per-word position tracking and per-word
pronunciation/tajweed scoring. 100% on-device, no network at runtime.

This describes the Flutter implementation so it can be mirrored in React Native.
Every number here is the real value used in production.

---

## 0. The model

- **Repo:** `Muno459/fastconformer-quran-streaming` (HuggingFace, gated).
- **Architecture:** cache-aware streaming FastConformer-Hybrid encoder,
  17 layers, d_model 512. CTC head over a **1025**-symbol vocabulary
  (1024 SentencePiece BPE pieces + 1 CTC blank = id **1024**).
- **File we ship:** `model_streaming_with_encoder.q8.onnx` (~132 MB, int8).
  IMPORTANT: use the `..._with_encoder` variant — it exposes `encoder_output`
  in addition to `logprobs`. The plain `model.q8.onnx` does **not** emit
  encoder features and cannot drive pronunciation scoring.
- **Trained on:** canonical **imlaei**-orthography Quran text (NOT Uthmani
  rasm). This matters — see §6.

### ONNX I/O contract (per streaming step)

Inputs:
| name | shape | dtype | notes |
|---|---|---|---|
| `audio_signal` | `[1, 80, T]` | float32 | 80-dim log-mel, T = frames this chunk |
| `length` | `[1]` | int64 | = T |
| `cache_last_channel` | `[1, 17, 70, 512]` | float32 | carried between steps |
| `cache_last_time` | `[1, 17, 512, 8]` | float32 | carried between steps |
| `cache_last_channel_len` | `[1]` | int64 | carried between steps |

Outputs:
| name | shape | notes |
|---|---|---|
| `logprobs` | `[1, T', 1025]` | per-frame CTC log-probs; T' ≈ T/8 |
| `encoder_output` | `[1, T', 512]` | per-frame hidden features |
| `cache_last_channel_next` | `[1, 17, 70, 512]` | feed as next `cache_last_channel` |
| `cache_last_time_next` | `[1, 17, 512, 8]` | feed as next `cache_last_time` |
| `cache_last_channel_next_len` | `[1]` | feed as next `cache_last_channel_len` |

- Caches start **all zeros** (len = 0) at session start; each step's `*_next`
  outputs become the next step's cache inputs. Do not reset mid-utterance.
- **Encoder output hop ≈ 80 ms** (8× subsampling of the 10 ms mel hop). Used to
  convert alignment frame indices ↔ time.

---

## 1. Prebaked assets (generated offline, bundled in the app)

None of these are fetched at runtime. Generation scripts are in `tool/`.

| asset | shape / form | purpose |
|---|---|---|
| `mel_filters.json` | (80, 257) | slaney mel filterbank matrix |
| `cmvn.json` | `{tlog_mean, tlog_std, clean_mean, clean_std}`, each len 80 | fixed global CMVN |
| `vocab.json` | 1024 strings, index = token id | BPE piece for each id (decode/debug) |
| `ref_tokens.json` | `{ "s:a:w": [int,…] }` | every mushaf word pre-tokenized (see §6) |
| `preamble.json` | `{ istiadha:[…], basmala:[…] }` | optional spoken-prefix token ids |
| `pronunciation_head.bin` + `_manifest.json` | packed float32 | the scoring head's weights (§7) |

`tokenizer.model` (SentencePiece) is **not** shipped in the app — it's only
used offline to build `ref_tokens.json` / `preamble.json`, because we never
need to tokenize free text on-device (we tokenize the *known* mushaf text ahead
of time).

---

## 2. Microphone → PCM  (`mic_source.dart`)

- Package: `record`. Config: **PCM 16-bit, 16 kHz, mono**, streamed.
- The stream delivers `Uint8List`. Reassemble little-endian int16 samples;
  carry any odd trailing byte between chunks (`_byteTail`) so samples never
  split across delivery boundaries.
- Output: `Int16List` PCM handed to the mel frontend.

---

## 3. PCM → log-mel frames  (`mel_frontend.dart`)

Matches torchaudio `MelSpectrogram` used in the model's reference script.
Constants (exact):

```
sample_rate  = 16000
n_fft        = 512      → 257 real FFT bins
win_length   = 400      (25 ms), Hann window, centered in the 512 frame
                        (left pad = (512-400)/2 = 56)
hop_length   = 160      (10 ms)
n_mels       = 80
preemphasis  = 0.97     s[i] - 0.97*s[i-1]
log          = ln(x + 2^-24)   (2^-24 = 5.9604644775390625e-08)
mel norm     = slaney (baked into mel_filters.json)
```

Per chunk:
1. Scale int16 → float (`/32768`), apply pre-emphasis (carry `_prevRaw`).
2. **Once at stream start**, reflect-pad the front by `n_fft/2 = 256` samples
   (torchaudio centers frames; live audio has no "end" yet so only the start is
   padded — mid-stream framing is identical).
3. Slide the 400-sample Hann window by hop 160; for each window: zero-pad to
   512, FFT, power spectrum (257 bins), matmul with the (80×257) mel filterbank,
   `ln(x + 2^-24)` → one 80-dim frame.
4. Emit frames incrementally (buffer holds leftover < win_length samples).

Output: a stream of 80-dim `float64` log-mel frames.

---

## 4. Chunking + CMVN + inference  (`asr_engine.dart`)

- Buffer mel frames until **112** accumulate (`chunkMel = 112` ≈ **1.12 s**),
  then run one ONNX step on that chunk. Leftover frames wait for the next chunk.
  On stop, `flush()` runs the partial remainder.
- **CMVN normalize** each frame before inference, per mel bin m:
  `x[m] = (mel[m] - mean[m]) / (std[m] + 1e-5)`.
  Use the **`tlog`** profile for phone-mic audio (default); `clean` is for
  studio recordings. Then lay out as `audio_signal` `[1, 80, T]` (mel-major:
  `audio[m*T + f]`).
- Run the session with the 5 inputs (chunk + the 3 carried caches). Read back
  `logprobs`, `encoder_output`, and the 3 `*_next` caches; store the caches for
  the next chunk.
- Keep a running list of all `encoder_output` frames for the session (needed
  for pooling in §7). Frame index is global across chunks.

Each output frame f then does two things: feeds the aligner (§5) and, when a
token's span closes, feeds the scorer (§7).

---

## 5. Streaming CTC forced alignment  (`forced_aligner.dart`)

**Why alignment instead of free decode:** the feature is "follow a *known*
page + score each word", not open transcription. Free CTC decode gives a
guessed string you'd then have to fuzzy-match to mushaf words — which breaks on
imlaei-vs-Uthmani spelling. Forced alignment instead tracks *how far into the
known reference token sequence* the reciter has gotten, and gives each token its
exact frame span (required for §7). No text is ever compared.

Setup per page:
- Flatten the page's reference tokens in reading order:
  `refIds = concat(ref_tokens[loc] for each word loc on the page)`, remembering
  which word index each token came from.
- Optionally prepend **isti'adha** and **basmala** tokens (`preamble.json`) as
  an *optional* prefix (basmala only when the page renders a basmala line).
  These are wired with **bypass arcs** so alignment can skip either/both — the
  reciter may or may not say them, and it must not stall either way.
- Build the standard CTC "extended" label sequence
  `z = [blank, t0, blank, t1, blank, …]` (length `2N+1`).

Per output frame (streaming Viterbi over `z`):
- Standard CTC forced-alignment recursion: `alpha[s] = logp[z[s]] + max(alpha[s],
  alpha[s-1], alpha[s-2] if z[s]≠blank and z[s]≠z[s-2])`, plus the preamble
  bypass predecessors.
- The best-scoring state gives the current reference-token index → the current
  **word location** (emit when it changes → live word highlight).
- When the head advances past a token, that token's frame span
  `[startFrame, endFrame)` is final → hand it to §7.
- `flush()` closes any tokens still open at end of stream.

Output: (a) a stream of "current word location" (`s:a:w`) for the position
marker, and (b) closed `TokenSpan`s for scoring.

---

## 6. The imlaei ↔ Uthmani bridge (critical, and invisible)

- **Display** uses your existing Uthmani mushaf (`assets/mushaf/page-NNN.json`,
  UthmanicHafs font). **Unchanged. The imlaei text is never rendered.**
- **Alignment** uses `ref_tokens.json`: each mushaf word's imlaei text,
  tokenized offline with the model's own SentencePiece tokenizer.
- The two are joined **only by the `location` id** (`"surah:ayah:word"`). Both
  files key every word by the same id, so token sequence for `2:2:2` →
  highlight the displayed word whose `location == "2:2:2"`. Letters are never
  compared → spelling differences are structurally irrelevant.

Building `ref_tokens.json` (`tool/build_ref_tokens.py`), gotchas that bit us:
- Source text is quran.com `text_imlaei` per word (keyed by the same `s:a:w`).
- **Strip embedded recitation annotations** before tokenizing — quran.com bakes
  waqf/pause marks and the rub-el-hizb symbol into the word string
  (`ۖ ۗ ۘ ۙ ۚ ۛ ۜ ۝ ۞ ‏` U+06D6–U+06ED, U+200F). The BPE vocab has **no** pieces
  containing them → they silently become `<unk>` (id 0) and poison alignment for
  that word. This affected ~10% of all words until fixed.
- **Normalize the dagger-alif** U+0670 (`ٰ`) away (plain imlaei spelling, e.g.
  `الرحمن` not `الرحمٰن`) — the vocab has no piece for it either.
- Only `.strip()` (edge) whitespace; do **not** collapse internal spaces (would
  fuse the multi-word isti'adha phrase).
- Verify **zero** `<unk>` (id 0) across all ~77k words after building.

---

## 7. Per-word pronunciation / tajweed scoring  (`pronunciation_head.dart`)

A tiny MLP head (1.33 M params) the model author trained on top of the encoder.
Ported from the PyTorch checkpoint to a plain Dart forward pass.

For each closed `TokenSpan` from §5:
1. **Pool**: mean of the `encoder_output` frames over `[startFrame, endFrame)`
   → a 512-dim vector.
2. **Assemble input (592-dim)** = concat:
   - pooled encoder feature (512),
   - token embedding `tok_emb[token_id]` (64), from the head's own embedding table,
   - fixed per-token phonology feature `feature_table[token_id]` (16).
3. **MLP**: `592 → 1024 → 512 → 256 → 1`, **GELU** (exact/erf) between layers,
   then **sigmoid** → `p = P(pronounced correctly)`.
4. **Bucket**: `p ≥ 0.40 → ok`, `0.30 ≤ p < 0.40 → minor`, `p < 0.30 → major`.
   (Thresholds copied from the author's reference scorer; tune on device.)

Weights live in `pronunciation_head.bin` (flat float32, sliced via
`_manifest.json` offsets): `tok_emb (1025,64)`, `w0(1024,592) b0`,
`w1(512,1024) b1`, `w2(256,512) b2`, `w3(1,256) b3`, `feature_table (1025,16)`.

Output: `(location, deviation, p)` per word → UI colors the word
(green/amber/red underline) and the current word/verse markers.

---

## 8. End-to-end data flow

```
mic (PCM16 16k mono)
  → reassemble int16                         (mic_source)
  → pre-emph + Hann/FFT + mel + ln           (mel_frontend)   80-dim frames
  → buffer 112 frames (~1.12s) + CMVN(tlog)  (asr_engine)
  → ONNX step (+carry caches)                → logprobs[T',1025], encoder_output[T',512]
        │                                        │
        │ per frame: logprobs                     │ per frame: append to encoder buffer
        ▼                                        │
  streaming CTC forced align vs ref_tokens     │
  (forced_aligner)                             │
        │  emits current word location ────────┼──► UI: position marker (word + verse)
        │  emits closed TokenSpan ─────────────┘
        ▼
  pool encoder_output over span → head MLP → sigmoid → ok/minor/major
  (pronunciation_head)  ─────────────────────────────► UI: per-word tajweed color
```

---

## 9. Notes / gotchas for the RN port

- **Latency is inherent**: ~1.12 s chunking + on-device 17-layer inference means
  the marker trails speech by roughly 0.5–1.5 s. Chunk size comes from the
  model's streaming export (cache tensor shapes assume it) — don't shrink it
  without a matching re-export.
- **It's a follow-along tracker, not an open transcriber.** Forced alignment
  assumes the reciter is reading the on-screen page; reciting an unrelated verse
  will still march through the page words. Detecting whole-verse skips/subs is a
  separate mode.
- **Streaming WER is higher than the offline model** (model card: ~14% phone
  vs ~4% offline) — expect occasional wrong/missed words from the ASR itself,
  independent of the alignment.
- **License:** NPL-1.0 (non-commercial / cost-recovery only). Relevant if the
  app is ever monetized.
- **ORT runtime**: Flutter uses `onnxruntime`. RN equivalent: `onnxruntime-react-native`.
  Same I/O contract applies.
```
