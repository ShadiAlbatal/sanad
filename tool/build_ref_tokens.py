"""Build assets/asr/ref_tokens.json from tool/_cache/imlaei.json.

quran.com's text_imlaei field embeds Quranic recitation annotations (waqf/
pause marks, rub-el-hizb marker, RTL formatting marks) directly in the word
text for ~10% of words -- these are typographic, not phonetic, and the
model's BPE vocab has zero pieces containing them, so leaving them in
silently produces <unk> (id 0) tokens in the reference sequence, breaking
forced alignment for any word near one. Also strips the Quranic dagger-alif
(U+0670), which the vocab likewise has no pieces for -- the model's training
text uses plain modern-imlaei spelling (e.g. "الرحمن" not "الرحمٰن").
"""
import json
import re
import sentencepiece as spm

_ANNOTATIONS = re.compile(
    '[ۖ-ۭ۞‏]'  # small high marks, waqf signs, rub-el-hizb, RTL mark
)
_DAGGER_ALIF = 'ٰ'


def clean(text: str) -> str:
    # Annotation marks only ever sit at a word's edge with one separating
    # space (e.g. "الْأَنْهَارُ ۖ", "۞ إِنَّ") -- never mid-word -- so a
    # trailing strip() is enough and, unlike stripping all whitespace,
    # won't corrupt legitimate multi-word reference text (e.g. the
    # isti'adha phrase) by fusing words together.
    out = _ANNOTATIONS.sub('', text)
    out = out.replace(_DAGGER_ALIF, '')
    return out.strip()


def main():
    sp = spm.SentencePieceProcessor(model_file="tool/_cache/tokenizer.model")
    imlaei = json.load(open("tool/_cache/imlaei.json", encoding="utf-8"))

    ref_tokens = {}
    unk_words = []
    for loc, raw in imlaei.items():
        text = clean(raw)
        ids = sp.encode(text, out_type=int)
        if 0 in ids:
            unk_words.append((loc, raw, text))
        ref_tokens[loc] = ids

    print("words:", len(ref_tokens), "still-unk:", len(unk_words))
    for loc, raw, text in unk_words[:20]:
        print(" ", loc, repr(raw), "->", repr(text))

    with open("assets/asr/ref_tokens.json", "w", encoding="utf-8") as f:
        json.dump(ref_tokens, f, separators=(",", ":"))


if __name__ == "__main__":
    main()
