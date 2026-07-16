"""Build TilawaAi phoneme-corpus JSON for hadith du'as, using the SAME 250-unit
Hafs phoneme scheme the streaming zipformer2-ctc model was trained on
(Muno459/zipformer_p-quran). Adapted from the ZikirAi tool of the same name.

Why this exists: the Quran corpus (assets/asr/quran_phonemes/NNN.json) was
phonetized through the quran-transcript Quran-database pipeline (real ayat,
proper wasl/waqf). That pipeline does not cover hadith du'as. Feeding raw du'a
text to the public quran_phonetizer fails two ways: (1) du'as are in plain
(imlaey) script but the phonetizer needs Uthmani (hamzat-wasl, alef-madda,
alef-maqsura), and (2) its process_sifat step throws IndexError on common words.

We sidestep both: a light imlaey->Uthmani normalizer per word, and a
phonemes_only wrapper that runs the library's own phoneme operations and skips
the buggy sifat layer (we only need the phoneme string). Greedy longest-match
tokenization over the vocab matches the runtime phonemeTokenizer, so reference
and on-device hypothesis tokenize identically.

Under-diacritized du'a texts are skipped (their phoneme reference would drop the
vowels the reciter actually says); add full tashkeel to the du'a text in
dua_input.json and re-run.

Output shape matches loadSurahClip's reader: {id, words, phonemes,
phonemeToWord, ayahBoundaries, arabic, meaning}. ayahBoundaries is [0] (whole
du'a is one span) — set per-sentence later if sentence-level follow is wanted.

Usage:
    python -m venv .venv && .venv/Scripts/pip install quran-transcript
    .venv/Scripts/python tool/build_dua_phonemes.py            # -> tool/out/<id>.json
    .venv/Scripts/python tool/build_dua_phonemes.py --out DIR   # custom output dir
"""
import argparse
import json
import re
from pathlib import Path

from quran_transcript.phonetics.conv_base_operation import sub_with_mapping
from quran_transcript.phonetics.operations import OPERATION_ORDER
from quran_transcript import alphabet as alph
from quran_transcript import MoshafAttributes

HERE = Path(__file__).resolve().parent
TOKENS = HERE.parent / "assets" / "asr" / "phoneme" / "tokens.txt"
INPUT = HERE / "dua_input.json"

MIN_DIACRITIZATION = 0.6  # separates the good du'as (0.82-0.94) from under-vocalized (~0.25)

SPACE = alph.uthmani.space
MOSHAF = MoshafAttributes(rewaya="hafs", madd_monfasel_len=4, madd_mottasel_len=4,
                          madd_mottasel_waqf=4, madd_aared_len=4)


def load_vocab():
    """250 phoneme units from tokens.txt (drop the <blank> row and its id)."""
    units = []
    for line in TOKENS.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        unit = line.rsplit(" ", 1)[0]
        if unit == "<blank>":
            continue
        units.append(unit)
    return units


UNIT_LIST = load_vocab()
VOCAB = set(UNIT_LIST)
MAXLEN = max(len(u) for u in UNIT_LIST)

HARAKA = "ً-ْٰ"  # tanwin, harakat, shadda, sukun, superscript alef
ARABIC_LETTER = re.compile(r"[ء-ي]")


def phonemes_only(text: str) -> str:
    """The phoneme string the library produces, without the crashing sifat step
    (quran_transcript phonetizer.py, verbatim minus process_sifat)."""
    text, mp = sub_with_mapping(r"\s+", f"{SPACE}", text)
    text, mp = sub_with_mapping(r"(\s$|^\s)", r"", text, mappings=mp)
    for op in OPERATION_ORDER:
        text, mp = op.apply(text, MOSHAF, mp)
    return text


def greedy(s: str):
    """Greedy longest-match over the vocab — identical to the runtime
    phonemeTokenizer.ts so reference and hypothesis tokenize the same way."""
    out, i = [], 0
    while i < len(s):
        if s[i].isspace():
            i += 1
            continue
        matched = ""
        for length in range(min(MAXLEN, len(s) - i), 0, -1):
            if s[i:i + length] in VOCAB:
                matched = s[i:i + length]
                break
        if matched:
            out.append(matched)
            i += len(matched)
        else:
            out.append("?" + s[i])  # OOV marker -> caught by build_entry
            i += 1
    return out


def norm_word(w: str) -> str:
    """imlaey -> Uthmani, only the transforms these du'as need. The definite
    article's alif becomes hamzat-wasl so it elides; the lam is kept (the model
    emits it even before sun letters)."""
    if w.startswith("ال"):
        w = "ٱ" + w[1:]
    else:
        m = re.match(rf"^([وفبكل][{HARAKA}]?)ال", w)  # prefix + article
        if m:
            w = m.group(1) + "ٱل" + w[len(m.group(0)):]
        elif w[0] == "ا" and len(w) > 1:              # other word-initial wasl alif
            w = "ٱ" + w[1:]
    w = w.replace("آ", "ءَا")                         # alef-madda -> hamza + alif
    w = re.sub(r"ى$", "ا", w)                         # word-final alef-maqsura -> alif
    return w


def diacritization_ratio(text: str) -> float:
    letters = [c for c in text if ARABIC_LETTER.match(c)]
    marks = len(re.findall(rf"[{HARAKA}]", text))
    return marks / max(1, len(letters))


def build_entry(dua: dict) -> dict:
    raw_words = [w for w in dua["arabic"].strip().split() if ARABIC_LETTER.search(w)]
    phonemes, p2w = [], []
    for wi, w in enumerate(raw_words):
        toks = greedy(phonemes_only(norm_word(w)))
        oov = [t for t in toks if t.startswith("?")]
        if oov:
            raise SystemExit(f"{dua['id']}: word {wi} {w!r} -> OOV {oov}")
        phonemes += toks
        p2w += [wi] * len(toks)
    assert len(phonemes) == len(p2w)
    assert max(p2w) == len(raw_words) - 1
    return {
        "id": dua["id"],
        "title": dua.get("title", ""),
        "source": dua.get("source", ""),
        "arabic": dua["arabic"],
        "meaning": dua.get("meaning", ""),
        "words": raw_words,
        "phonemes": phonemes,
        "phonemeToWord": p2w,
        "ayahBoundaries": [0],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(HERE / "out"), help="output directory")
    args = ap.parse_args()
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    duas = json.loads(INPUT.read_text(encoding="utf-8"))
    built = 0
    for dua in duas:
        ratio = diacritization_ratio(dua["arabic"])
        if ratio < MIN_DIACRITIZATION:
            print(f"{dua['id']}: SKIPPED — under-diacritized ({ratio:.0%} of letters "
                  f"marked); add full tashkeel to dua_input.json, then re-run")
            continue
        entry = build_entry(dua)
        (outdir / f"{entry['id']}.json").write_text(
            json.dumps(entry, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"{dua['id']}: {len(entry['words'])} words, {len(entry['phonemes'])} "
              f"phonemes (diacritization {ratio:.0%}) -> {entry['id']}.json")
        built += 1
    print(f"\nwrote {built} du'a corpus files to {outdir}")


if __name__ == "__main__":
    main()
