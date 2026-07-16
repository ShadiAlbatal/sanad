"""Validate our bundled phoneme corpus (assets/asr/quran_phonemes/*.json) against
the model author's canonical ordered_quran_phonemes.json (model-exact, 0 OOV).

For each ayah we reconstruct our per-word phoneme strings (group flat `phonemes`
by `phonemeToWord`, split by `ayahBoundaries`) and compare to the canonical
`aya_phonemes_list`. Reports word-count (segmentation) mismatches, exact per-word
phoneme mismatches, and mismatches that survive `collapse` (repeated-char fold,
which the matcher applies). Writes a UTF-8 detail report; prints ASCII stats.
"""
import json, re, sys, os

CANON = r"C:\Users\salext\prv\apps\Zikir Ai\spike\zipformer-quran-phoneme\ordered_quran_phonemes.json"
OURDIR = r"C:\Users\salext\prv\apps\TilawaAi\assets\asr\quran_phonemes"
REPORT = r"C:\Users\salext\prv\apps\TilawaAi\tool\corpus_validation_report.txt"

collapse = lambda s: re.sub(r"(.)\1+", r"\1", s)

canon = json.load(open(CANON, encoding="utf-8"))

tot_ayat = seg_mismatch = exact_ok = collapse_ok = word_mismatch = ayat_all_ok = 0
missing_ours = missing_canon = 0
examples = []

for surah in range(1, 115):
    p = os.path.join(OURDIR, f"{surah:03d}.json")
    d = json.load(open(p, encoding="utf-8"))
    ph, p2w, bounds = d["phonemes"], d["phonemeToWord"], d["ayahBoundaries"]
    n_words = len(d["words"])
    # per-word phoneme string (join units in corpus order)
    word_ph = {}
    for u, w in zip(ph, p2w):
        word_ph.setdefault(w, []).append(u)
    word_str = {w: "".join(v) for w, v in word_ph.items()}
    n_ayat = len(bounds)
    for a in range(n_ayat):
        lo = bounds[a]
        hi = bounds[a + 1] if a + 1 < n_ayat else n_words
        ours = [word_str.get(w, "") for w in range(lo, hi)]
        key = f"{surah}:{a+1}"
        c = canon.get(key)
        if c is None:
            missing_canon += 1
            continue
        tot_ayat += 1
        cw = c["aya_phonemes_list"]
        if len(ours) != len(cw):
            seg_mismatch += 1
            if len(examples) < 40:
                examples.append(f"[SEG] {key}: ours={len(ours)} words, canon={len(cw)} words\n"
                                 f"      ours : {ours}\n      canon: {cw}")
            continue
        ayah_ok = True
        for i, (o, cc) in enumerate(zip(ours, cw)):
            if o == cc:
                exact_ok += 1
            elif collapse(o) == collapse(cc):
                collapse_ok += 1
                ayah_ok = False
            else:
                word_mismatch += 1
                ayah_ok = False
                if len(examples) < 40:
                    examples.append(f"[WORD] {key} w{i}: ours='{o}' canon='{cc}'")
        if ayah_ok:
            ayat_all_ok += 1

# canonical ayat with no counterpart in ours
our_keys = set()
for surah in range(1, 115):
    d = json.load(open(os.path.join(OURDIR, f"{surah:03d}.json"), encoding="utf-8"))
    for a in range(len(d["ayahBoundaries"])):
        our_keys.add(f"{surah}:{a+1}")
missing_ours = len([k for k in canon if k not in our_keys])

tot_words = exact_ok + collapse_ok + word_mismatch
with open(REPORT, "w", encoding="utf-8") as f:
    f.write("CORPUS VALIDATION vs canonical ordered_quran_phonemes.json\n")
    f.write("=" * 60 + "\n")
    f.write(f"ayat compared            : {tot_ayat}\n")
    f.write(f"  fully identical        : {ayat_all_ok}\n")
    f.write(f"  segmentation mismatch  : {seg_mismatch} (word count per ayah differs)\n")
    f.write(f"canonical ayat missing from ours : {missing_ours}\n")
    f.write(f"our ayat missing from canonical  : {missing_canon}\n")
    f.write(f"\nword-level (over segmentation-matched ayat), {tot_words} words:\n")
    f.write(f"  exact phoneme match    : {exact_ok}\n")
    f.write(f"  match only after collapse: {collapse_ok}\n")
    f.write(f"  real mismatch          : {word_mismatch}\n")
    f.write("\nEXAMPLES\n" + "-" * 40 + "\n")
    f.write("\n".join(examples))

print("ayat_compared", tot_ayat)
print("ayat_identical", ayat_all_ok)
print("seg_mismatch_ayat", seg_mismatch)
print("missing_from_ours", missing_ours, "missing_from_canon", missing_canon)
print("words_total", tot_words, "exact", exact_ok, "collapse_only", collapse_ok, "real_mismatch", word_mismatch)
print("report ->", REPORT)
