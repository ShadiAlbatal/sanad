"""Build a phonemized hadith phoneme-corpus JSON for the offline phoneme
retrieval ("Find") engine, reusing the EXACT Hafs G2P + greedy-vocab path from
build_dua_phonemes.py (quran-transcript phoneme ops + longest-match over the
250-unit tokens.txt) so hadith references tokenize identically to the on-device
hypothesis.

Unlike the du'a tool this is a fault-tolerant BATCH job over thousands of rows:
a hadith that OOVs, throws, or is under-diacritized is SKIPPED and counted, never
aborting the run.

Input: an Open-Hadith-Data diacritized ("mushakkala") CSV. Each row is
"<number>","<matn text WITH tashkeel + U+200F markers>","<tafseel>". Column 2 is
the text; the U+200F/U+200E direction marks are stripped and whitespace collapsed.

Output: one array-of-entries JSON per collection, <out>/<collection>.json. Each
entry mirrors the du'a clip shape so the Dart loader is uniform:
  {id, ref:{book,number}, text, words, phonemes, phonemeToWord}

Usage:
    .venv/Scripts/python tool/build_hadith_phonemes.py \\
        --csv bukhari.csv --collection bukhari --out tool/out [--limit N]
"""
import argparse
import csv
import json
import re
from pathlib import Path

from build_dua_phonemes import (
    ARABIC_LETTER,
    MIN_DIACRITIZATION,
    diacritization_ratio,
    greedy,
    norm_word,
    phonemes_only,
)

csv.field_size_limit(10 ** 7)
_DIR_MARKS = "‏‎"


def clean(text: str) -> str:
    for m in _DIR_MARKS:
        text = text.replace(m, "")
    return re.sub(r"\s+", " ", text).strip()


def build_entry(collection: str, number: str, text: str):
    raw_words = [w for w in text.split() if ARABIC_LETTER.search(w)]
    phonemes, p2w = [], []
    for wi, w in enumerate(raw_words):
        toks = greedy(phonemes_only(norm_word(w)))
        if any(t.startswith("?") for t in toks):
            return None
        phonemes += toks
        p2w += [wi] * len(toks)
    return {
        "id": f"{collection}:{number}",
        "ref": {"book": collection, "number": int(number)},
        "text": text,
        "words": raw_words,
        "phonemes": phonemes,
        "phonemeToWord": p2w,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--collection", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, help="process only the first N hadith")
    args = ap.parse_args()

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    entries = []
    total = processed = skipped_oov = skipped_underdia = 0
    with open(args.csv, encoding="utf-8", newline="") as f:
        for row in csv.reader(f):
            if len(row) < 2:
                continue
            text = clean(row[1])
            if not ARABIC_LETTER.search(text):
                continue
            if args.limit is not None and total >= args.limit:
                break
            total += 1
            if diacritization_ratio(text) < MIN_DIACRITIZATION:
                skipped_underdia += 1
                continue
            try:
                entry = build_entry(args.collection, row[0].strip(), text)
            except Exception:
                entry = None
            if entry is None:
                skipped_oov += 1
                continue
            entries.append(entry)
            processed += 1

    out = outdir / f"{args.collection}.json"
    out.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")
    print(f"processed {processed} / skipped-OOV {skipped_oov} / "
          f"skipped-underdiacritized {skipped_underdia} / total {total}")
    print(f"wrote {len(entries)} entries -> {out}")


if __name__ == "__main__":
    main()
