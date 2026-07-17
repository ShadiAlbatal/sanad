"""One-shot repack of the du'a FIND corpus to CARRY the word map (piece 3b).

The find/list corpus `assets/asr/dua/corpus.json.gz` shipped as 6-column rows
`[id, title, source, arabic, meaning, [phoneme_int, ...]]` — words/phonemeToWord
were dropped (they were "follow-along machinery the find path never touches").
Voice-candidate word highlighting now needs them, so this appends two columns —
`[..., [word, ...], [phonemeToWord_int, ...]]` — mirroring the hadith corpus.

Rebuilt from the EXISTING per-du'a clips (`assets/asr/dua_phonemes/<id>.json`,
which already store words+phonemes+phonemeToWord) — NO G2P re-run, so membership
and order are byte-preserved: each old row keeps its id/metadata/phoneme ints and
only gains the two trailing columns. Fidelity is asserted per doc (the clip's
phonemes re-encode to the row's existing int stream; lengths align 1:1).

Usage:
    python tool/repack_dua_corpus_wordmap.py
"""
import gzip
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CORPUS = ROOT / "assets" / "asr" / "dua" / "corpus.json.gz"
CLIP_DIR = ROOT / "assets" / "asr" / "dua_phonemes"
TOKENS = ROOT / "assets" / "asr" / "phoneme" / "tokens.txt"


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
    vocab = load_vocab_index(TOKENS)
    rows = json.loads(gzip.decompress(CORPUS.read_bytes()).decode("utf-8"))
    out = []
    for row in rows:
        did = row[0]
        phon_ints = row[5]
        clip = json.loads((CLIP_DIR / f"{did}.json").read_text(encoding="utf-8"))
        words = clip["words"]
        phonemes = clip["phonemes"]
        p2w = clip["phonemeToWord"]
        # Fidelity: the clip's phonemes re-encode EXACTLY to this row's existing
        # int stream (same order, same length), and the word map aligns 1:1.
        assert len(phonemes) == len(p2w) == len(phon_ints), (
            f"{did}: len mismatch phon={len(phonemes)} p2w={len(p2w)} row={len(phon_ints)}")
        assert [vocab[p] for p in phonemes] == phon_ints, f"{did}: phoneme int stream differs"
        assert all(0 <= w < len(words) for w in p2w), f"{did}: p2w out of word range"
        out.append(row[:6] + [words, p2w])

    compact = json.dumps(out, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    gz = gzip.compress(compact, 9)
    CORPUS.write_bytes(gz)

    # Round-trip: re-decode and confirm the two new columns survive the gzip.
    back = json.loads(gzip.decompress(CORPUS.read_bytes()).decode("utf-8"))
    assert len(back) == len(rows)
    assert all(len(r) == 8 for r in back)
    assert all(len(r[6]) == max(r[7]) + 1 for r in back if r[7])

    print(f"docs={len(out)} (was {len(rows)}), cols 6 -> 8 (+words +phonemeToWord)")
    print(f"gzipped: {len(gz)} B ({len(gz) / 1024:.1f} KB) -> {CORPUS}")


if __name__ == "__main__":
    main()
