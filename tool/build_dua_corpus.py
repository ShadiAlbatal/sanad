"""Build the COMPREHENSIVE du'a corpus (Hisn al-Muslim / حصن المسلم) — additively
on top of the existing 5 validated du'as, using the SAME Hafs G2P + greedy-vocab
path as build_dua_phonemes.py (quran-transcript phoneme ops + longest-match over
the 250-unit tokens.txt) so every du'a tokenises identically to the on-device
hypothesis.

Two outputs, mirroring the split the app already uses for hadith:

  1. Per-du'a reader clips -> assets/asr/dua_phonemes/<id>.json (full clip shape:
     id, title, source, arabic, meaning, words, phonemes, phonemeToWord,
     ayahBoundaries). loadDuaClip(id) reads these UNCHANGED, so the reader opens
     and follows along ANY du'a. The existing 5 files are left untouched.

  2. A combined find/list corpus -> assets/asr/dua/corpus.json.gz: a keyless
     array of [id, title, source, arabic, meaning, [phoneme_int, ...], [word, ...],
     [phonemeToWord_int, ...]] over the existing 5 + every newly phonemized Hisn
     du'a. phoneme units are re-encoded as their INTEGER index into tokens.txt line
     order (exactly what loadPhonemeUnits() yields in Dart). Drives DuaSearch
     (PhonemeFinder) and the browsable list. words/phonemeToWord ride along so the
     voice finder can map a matched phoneme back to its word for candidate-row
     highlighting (piece 3b), mirroring the hadith corpus.

Fault-tolerant BATCH job like build_hadith_phonemes.py: a du'a that OOVs or is
under-diacritized is SKIPPED and counted, never aborting the run.

Source: hisnmuslim.com public API (fully-diacritized Hisn al-Muslim), assembled +
cleaned + de-duplicated against the existing 5 into tool/hisn_source.json. The
underlying supplications are Qur'an/Sunnah text (public domain); attribution:
Hisn al-Muslim by Sa'id b. 'Ali b. Wahf al-Qahtani.

Usage:
    .venv/Scripts/python tool/build_dua_corpus.py
"""
import gzip
import json
from pathlib import Path

from build_dua_phonemes import (
    ARABIC_LETTER,
    MIN_DIACRITIZATION,
    TOKENS,
    diacritization_ratio,
    greedy,
    norm_word,
    phonemes_only,
)
from pack_hadith_corpus import load_vocab_index

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SOURCE = HERE / "hisn_source.json"
DUA_INPUT = HERE / "dua_input.json"  # the existing 5 (their ids + metadata)
CLIP_DIR = ROOT / "assets" / "asr" / "dua_phonemes"
CORPUS = ROOT / "assets" / "asr" / "dua" / "corpus.json.gz"

# Pack-time phoneme index MUST be <blank>-inclusive, tokens.txt line order — the
# exact convention Dart's loadPhonemeUnits() yields (and pack_hadith_corpus uses).
# build_dua_phonemes' own UNIT_LIST drops <blank> for its greedy G2P, which is
# right for tokenization but one position off for the packer's integer encoding.
VOCAB_INDEX = load_vocab_index(TOKENS)


def build_clip(entry: dict):
    """Full reader-clip dict for one du'a, or None if any word OOVs. Tolerant
    sibling of build_dua_phonemes.build_entry (no SystemExit)."""
    raw_words = [w for w in entry["arabic"].strip().split() if ARABIC_LETTER.search(w)]
    if not raw_words:
        return None
    phonemes, p2w = [], []
    for wi, w in enumerate(raw_words):
        toks = greedy(phonemes_only(norm_word(w)))
        if any(t.startswith("?") for t in toks):
            return None
        phonemes += toks
        p2w += [wi] * len(toks)
    return {
        "id": entry["id"],
        "title": entry.get("title", ""),
        "source": entry.get("source", ""),
        "arabic": entry["arabic"],
        "meaning": entry.get("meaning", ""),
        "words": raw_words,
        "phonemes": phonemes,
        "phonemeToWord": p2w,
        "ayahBoundaries": [0],
    }


def row_from_clip(clip: dict):
    """Compact find/list row: [id, title, source, arabic, meaning, [phon_int,...],
    [word,...], [phonemeToWord_int,...]] — the word map rides along for voice
    candidate-row highlighting (piece 3b)."""
    return [
        clip["id"],
        clip.get("title", ""),
        clip.get("source", ""),
        clip.get("arabic", ""),
        clip.get("meaning", ""),
        [VOCAB_INDEX[p] for p in clip["phonemes"]],
        clip["words"],
        clip["phonemeToWord"],
    ]


def main():
    CLIP_DIR.mkdir(parents=True, exist_ok=True)
    CORPUS.parent.mkdir(parents=True, exist_ok=True)

    rows = []

    # 1. Existing 5 — read their already-validated clips (untouched on disk) so the
    #    combined corpus carries them with their current ids + metadata.
    existing_ids = [d["id"] for d in json.loads(DUA_INPUT.read_text(encoding="utf-8"))]
    for did in existing_ids:
        clip = json.loads((CLIP_DIR / f"{did}.json").read_text(encoding="utf-8"))
        rows.append(row_from_clip(clip))

    # 2. Hisn al-Muslim — phonemize additively, tolerant of OOV / under-diacritized.
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    built = skipped_oov = skipped_underdia = 0
    for entry in source:
        ratio = diacritization_ratio(entry["arabic"])
        if ratio < MIN_DIACRITIZATION:
            skipped_underdia += 1
            continue
        clip = build_clip(entry)
        if clip is None:
            skipped_oov += 1
            continue
        (CLIP_DIR / f"{clip['id']}.json").write_text(
            json.dumps(clip, ensure_ascii=False, indent=2), encoding="utf-8")
        rows.append(row_from_clip(clip))
        built += 1

    compact = json.dumps(rows, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    gz = gzip.compress(compact, 9)
    CORPUS.write_bytes(gz)

    mb = lambda b: f"{b / (1024 * 1024):.2f} MB"
    print(f"existing={len(existing_ids)} hisn-source={len(source)} "
          f"hisn-built={built} skipped-oov={skipped_oov} skipped-underdiacritized={skipped_underdia}")
    print(f"combined corpus rows={len(rows)}")
    print(f"corpus (a) compact json : {mb(len(compact))}")
    print(f"corpus (b) gzipped      : {mb(len(gz))}  -> {CORPUS}")


if __name__ == "__main__":
    main()
