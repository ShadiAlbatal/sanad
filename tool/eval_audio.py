"""Host-side ASR eval: run the REAL streaming phoneme model (sherpa-onnx, same
model.int8.onnx the app ships) over the recordings in audio/, and score what it
heard against the bundled phoneme corpus. Lets us iterate on ASR accuracy WITHOUT
the device.

Decode: ffmpeg (bundled via imageio-ffmpeg) -> 16k mono f32, one persistent
streaming decode + 0.8s tail pad (mirrors SherpaAsr.finish). Score: greedy-tokenize
the heard phoneme string with the 251-unit vocab, then align (difflib) to the
expected āyah/surah's corpus phonemes -> coverage (% words the audio produced, in
order) + phoneme match ratio. Correct recitations should score high; the *-wrong
and off-text (azan/thabat) controls should score low -- that contrast is the signal.

    python tool/eval_audio.py
"""
import json, glob, os, re, subprocess, sys
import numpy as np
import soundfile as sf  # noqa: F401  (kept: proves libsndfile present)
import imageio_ffmpeg
import sherpa_onnx
from difflib import SequenceMatcher

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
collapse = lambda s: re.sub(r"(.)\1+", r"\1", s)

# audio file -> expected (surah, ayah or None for whole surah, is_control)
TARGETS = [
    ("audio/alfatiha.mp4", 1, None, False),
    ("assets/debug_audio/alfatiha_16k.wav", 1, None, False),
    ("audio/alikhlas.mp4", 112, None, False),
    ("audio/alfalaq.mp4", 113, None, False),
    ("audio/alnas.mp4", 114, None, False),
    ("audio/alkursi.mp4", 2, 255, False),
    ("assets/debug_audio/alkursi_16k.wav", 2, 255, False),
    ("audio/albaqarah.mp4", 2, (1, 25), False),
    ("audio/albaqarah_1-22.mp4", 2, (1, 22), False),
    ("audio/fatira.mpeg", 35, (1, 5), False),
    # controls: should score LOW
    ("audio/alkursi-wrong.ogg", 2, 255, True),
    ("assets/debug_audio/alkursi_wrong_16k.wav", 2, 255, True),
    ("audio/ikhlas-worng.ogg", 112, None, True),
    ("audio/azan.mpeg", 1, None, True),       # adhan, not Qur'an
    ("audio/althabat.mpeg", 1, None, True),   # du'a, not Qur'an
]


def decode16k(path):
    out = subprocess.run(
        [FFMPEG, "-nostdin", "-v", "error", "-i", path, "-ac", "1", "-ar", "16000",
         "-f", "f32le", "-"], capture_output=True)
    return np.frombuffer(out.stdout, dtype=np.float32)


def load_units():
    units = []
    for line in open(os.path.join(BASE, "assets/asr/phoneme/tokens.txt"), encoding="utf-8"):
        tok = line.split()
        if tok:
            units.append(tok[0])
    return [u for u in units if re.search(r"[؀-ۿ]", u)]  # arabic-script units only


def tokenize(text, units):
    vocab = set(units)
    maxlen = max(len(u) for u in units)
    toks, i, n = [], 0, len(text)
    while i < n:
        if text[i].isspace():
            i += 1
            continue
        m = ""
        for L in range(min(maxlen, n - i), 0, -1):
            if text[i:i + L] in vocab:
                m = text[i:i + L]
                break
        if m:
            toks.append(m)
            i += len(m)
        else:
            i += 1
    return toks


def expected_phonemes(surah, ayah):
    """ayah: None = whole surah; int = that āyah; (a_lo, a_hi) = āyah range."""
    d = json.load(open(os.path.join(BASE, f"assets/asr/quran_phonemes/{surah:03d}.json"), encoding="utf-8"))
    ph = [collapse(p) for p in d["phonemes"]]
    p2w = d["phonemeToWord"]
    if ayah is None:
        return ph, p2w, len(d["words"])
    b = d["ayahBoundaries"]
    a_lo, a_hi = (ayah, ayah) if isinstance(ayah, int) else ayah
    lo = b[a_lo - 1]
    hi = b[a_hi] if a_hi < len(b) else len(d["words"])
    idx = [i for i, w in enumerate(p2w) if lo <= w < hi]
    return [ph[i] for i in idx], [p2w[i] - lo for i in idx], hi - lo


def main():
    units = load_units()
    rec = sherpa_onnx.OnlineRecognizer.from_zipformer2_ctc(
        tokens=os.path.join(BASE, "assets/asr/phoneme/tokens.txt"),
        model=os.path.join(BASE, "assets/asr/phoneme/model.int8.onnx"),
        num_threads=2)
    report = open(os.path.join(BASE, "tool", "eval_audio_report.txt"), "w", encoding="utf-8")
    hdr = (f"{'file':30} {'expect':>8} {'dur':>5} {'#ph':>5} {'span(words)':>12} "
           f"{'in-span':>8} {'PER':>5}  verdict")
    print(hdr)
    print("-" * 98)
    report.write(hdr + "\n" + "-" * 98 + "\n")
    for path, surah, ayah, control in TARGETS:
        full = os.path.join(BASE, path)
        if not os.path.exists(full):
            print(f"{os.path.basename(path):30} MISSING")
            continue
        audio = decode16k(full)
        st = rec.create_stream()
        st.accept_waveform(16000, audio)
        st.accept_waveform(16000, np.zeros(int(0.8 * 16000), dtype=np.float32))
        st.input_finished()
        while rec.is_ready(st):
            rec.decode_stream(st)
        heard_str = rec.get_result(st)
        heard = tokenize(heard_str, units)
        exp_ph, exp_p2w, nwords = expected_phonemes(surah, ayah)
        sm = SequenceMatcher(None, heard, exp_ph, autojunk=False)
        matched = sum(size for _, _, size in sm.get_matching_blocks())
        # PER-ish: fraction of the ALIGNED span that mismatched (lower is better)
        per = 1 - matched / max(len(exp_ph), 1)
        covered = set()
        for a, b, size in sm.get_matching_blocks():
            for k in range(size):
                covered.add(exp_p2w[b + k])
        # Score relative to the SPAN actually recited (so a partial recitation of a
        # long surah isn't unfairly penalized against the whole surah's word count).
        if covered:
            w0, w1 = min(covered), max(covered)
            span = w1 - w0 + 1
            inspan = len(covered) / span
        else:
            w0 = w1 = -1
            span = 0
            inspan = 0.0
        if ayah is None:
            exp_lbl = f"s{surah}"
        elif isinstance(ayah, int):
            exp_lbl = f"{surah}:{ayah}"
        else:
            exp_lbl = f"{surah}:{ayah[0]}-{ayah[1]}"
        if control:
            verdict = f"CONTROL {'ok-low' if inspan < 0.5 else 'still-matches (recitation w/ localized errors — global coverage is not a per-word mistake detector)'}"
        else:
            verdict = "GOOD" if inspan > 0.7 else ("PARTIAL" if inspan > 0.4 else "LOW")
        line = (f"{os.path.basename(path):30} {exp_lbl:>8} {len(audio)/16000:4.0f}s "
                f"{len(heard):5}  w{w0+1}-{w1+1}/{nwords:<5} {inspan:7.0%} {per:5.0%}  {verdict}")
        print(line)
        report.write(line + "\n    HEARD: " + heard_str + "\n")
    report.close()
    print("\nphoneme dumps -> tool/eval_audio_report.txt")


if __name__ == "__main__":
    main()
