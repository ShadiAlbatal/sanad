"""Pack the phonemized hadith corpus (output of build_hadith_phonemes.py) into
the COMPACT bundled asset the on-device "Find" engine loads. Accepts MULTIPLE
collection JSONs (Bukhari + Muslim) and packs them into one combined asset.

Each hadith keeps six fields: the collection ('bukhari' / 'muslim'), the number,
the clean matn text (display), the phoneme sequence, the display words, and the
phoneme→word map. The last two are the FOLLOW-ALONG machinery the reader needs to
green words as they are recited (the find path ignores them, but they must ride
along in the one bundled asset). Each phoneme unit is re-encoded as its INTEGER
index into tokens.txt line order (the exact order loadPhonemeUnits() yields in
Dart) — a multi-byte Arabic phoneme string becomes one small int, and gzip
crushes the repetitive digit stream. The collection qualifies the id in Dart
('bukhari:2790') so Bukhari/Muslim numbers never collide.

Output shape (array of arrays, keyless to shave every repeated JSON key):
    [[collection, number, text, [phoneme_int, ...], [word, ...], [p2w_int, ...]], ...]

Usage:
    .venv/Scripts/python tool/pack_hadith_corpus.py \\
        --in tool/out/bukhari.json tool/out/muslim.json \\
        --tokens assets/asr/phoneme/tokens.txt \\
        --out assets/asr/hadith/corpus.json.gz
"""
import argparse
import gzip
import json
from pathlib import Path


def load_vocab_index(tokens_path: Path) -> dict:
    order = []
    for line in tokens_path.read_text(encoding="utf-8").splitlines():
        l = line.rstrip()
        if not l:
            continue
        sp = l.rfind(" ")
        sym = l if sp < 0 else l[:sp]
        if sym:
            order.append(sym)
    return {sym: i for i, sym in enumerate(order)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True, nargs="+")
    ap.add_argument("--tokens", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    vocab = load_vocab_index(Path(args.tokens))

    docs = []
    per_collection = {}
    for path in args.inp:
        src = json.loads(Path(path).read_text(encoding="utf-8"))
        for e in src:
            book = e["ref"]["book"]
            codes = [vocab[p] for p in e["phonemes"]]
            docs.append([book, e["ref"]["number"], e["text"], codes,
                         e["words"], e["phonemeToWord"]])
            per_collection[book] = per_collection.get(book, 0) + 1

    compact = json.dumps(docs, ensure_ascii=False, separators=(",", ":"))
    compact_bytes = compact.encode("utf-8")
    gz = gzip.compress(compact_bytes, 9)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(gz if out.suffix == ".gz" else compact_bytes)

    mb = lambda b: f"{len(b) / (1024 * 1024):.2f} MB"
    print(f"docs={len(docs)} vocab={len(vocab)} by-collection={per_collection}")
    print(f"(b) compact int-encoded JSON   : {mb(compact_bytes)}")
    print(f"(c) compact JSON gzipped       : {mb(gz)}")
    print(f"wrote {mb(out.read_bytes())} -> {out}")


if __name__ == "__main__":
    main()
