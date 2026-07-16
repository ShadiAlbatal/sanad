"""Validate the corpus->mushaf alignment (assets/asr/align/NNN.json) against the
mushaf word counts (assets/asr/verse_index.json) and the model author's canonical
text segmentation (quran_text2phoneme.json + ordered_quran_phonemes.json).

Per ayah:
  C = corpus phoneme-word count (our quran_phonemes ayahBoundaries)
  M = mushaf word count (verse_index 'n')
  T = canonical text word count (text2phoneme key, independent of our mushaf data)
  our align maps each corpus word -> [mushaf s:a:w]; the union should be EXACTLY
  {s:a:1 .. s:a:M}, in order, no gaps/extras.

Checks: (1) coverage complete & exact, (2) monotonic (in reciting order),
(3) T == M (author's text words corroborate the mushaf word count).
"""
import json, glob, os, re, sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_phoneme_align import pnorm, mnorm  # noqa: E402  (share the exact normalization)

SPIKE = r"C:\Users\salext\prv\apps\Zikir Ai\spike\zipformer-quran-phoneme"
BASE = r"C:\Users\salext\prv\apps\TilawaAi"
REPORT = os.path.join(BASE, "tool", "align_validation_report.txt")

# Defense-in-depth (added after the 2026-07-15 review): coverage/monotonic/identity
# don't catch a merge/split whose INTERNAL boundary is wrong. Flag any corpus group
# whose phonemes barely overlap the mushaf words it's mapped to. Baseline below is
# all-verified-legit (hamza elision, tāʾ marbūṭa, muqaṭṭaʿāt letter-names, + 13
# known cosmetic tail-attached particles); a rise above it signals a real regression.
SIM_FLOOR = 0.5
SIM_LOW_BASELINE = 77


def _bagsim(a, b):
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    ca, cb = Counter(a), Counter(b)
    return 2 * sum((ca & cb).values()) / (len(a) + len(b))

ordered = json.load(open(os.path.join(SPIKE, "ordered_quran_phonemes.json"), encoding="utf-8"))
t2p = json.load(open(os.path.join(SPIKE, "quran_text2phoneme.json"), encoding="utf-8"))
vindex = json.load(open(os.path.join(BASE, "assets/asr/verse_index.json"), encoding="utf-8"))
M_of = {e["k"]: e["n"] for e in vindex}

# mushaf location -> normalized letters, for the per-group similarity check
mush_letters = {}
for p in glob.glob(os.path.join(BASE, "assets/mushaf/page-*.json")):
    for line in json.load(open(p, encoding="utf-8"))["lines"]:
        for w in line.get("words", []):
            loc = w.get("location", "")
            if re.match(r"^\d+:\d+:\d+$", loc):
                mush_letters[loc] = mnorm(w.get("word", ""))

# text2phoneme is Quran-ordered; zip positionally with ordered (also Quran-ordered)
# to attach an s:a key to each text entry, verifying the phoneme strings agree.
T_of, phon_mismatch = {}, 0
for (skey, oval), (text, phon) in zip(ordered.items(), t2p.items()):
    if oval["aya_phoneme"] != phon:
        phon_mismatch += 1
    T_of[skey] = len(text.split())

tot = complete = monotonic_ok = t_eq_m = identity_ok = identity_tot = 0
groups_tot = groups_low = 0
incomplete, extras, nonmono, t_ne_m, identity_bad, low_sim = [], [], [], [], [], []

for f in sorted(glob.glob(os.path.join(BASE, "assets/asr/quran_phonemes/*.json"))):
    surah = int(os.path.basename(f)[:3])
    corpus = json.load(open(f, encoding="utf-8"))
    align = json.load(open(os.path.join(BASE, f"assets/asr/align/{surah:03d}.json"), encoding="utf-8"))
    bounds = corpus["ayahBoundaries"]
    nw = len(corpus["words"])
    # per-corpus-word phoneme string, for the similarity check
    gstr = {}
    for u, w in zip(corpus["phonemes"], corpus["phonemeToWord"]):
        gstr.setdefault(w, []).append(u)
    for a in range(len(bounds)):
        lo = bounds[a]
        hi = bounds[a + 1] if a + 1 < len(bounds) else nw
        key = f"{surah}:{a+1}"
        M = M_of.get(key, 0)
        tot += 1
        # collect mushaf word numbers this ayah's corpus words map to, in order
        seq = []
        for ci in range(lo, hi):
            for loc in align[ci]:
                m = re.match(r"(\d+):(\d+):(\d+)$", loc)
                if m and int(m[1]) == surah and int(m[2]) == a + 1:
                    seq.append(int(m[3]))
                else:
                    seq.append(-1)  # out-of-ayah / malformed
        # per-group phoneme <-> assigned-mushaf similarity (boundary correctness)
        for ci in range(lo, hi):
            g = pnorm("".join(gstr.get(ci, [])))
            mcat = "".join(mush_letters.get(loc, "") for loc in align[ci])
            groups_tot += 1
            if _bagsim(g, mcat) < SIM_FLOOR:
                groups_low += 1
                if len(low_sim) < 40:
                    low_sim.append((key, ci - lo, round(_bagsim(g, mcat), 2), g, mcat, align[ci]))
        covered = set(x for x in seq if x > 0)
        want = set(range(1, M + 1))
        if covered == want and -1 not in seq:
            complete += 1
        else:
            miss = sorted(want - covered)
            extra = sorted(covered - want)
            if miss or extra or -1 in seq:
                (incomplete if miss else extras).append(
                    (key, f"M={M} covered={len(covered)} missing={miss} extra={extra}"))
        # monotonic non-decreasing mushaf word numbers
        clean = [x for x in seq if x > 0]
        if clean == sorted(clean):
            monotonic_ok += 1
        else:
            nonmono.append((key, str(seq)))
        # Per-word correctness: when corpus word count == mushaf word count the
        # mapping MUST be identity (corpus word k -> only mushaf word k+1). This
        # catches misassignments that still happen to cover everything (e.g. a
        # doubled word + an empty word), which the coverage check alone misses.
        # 2:181, 27:1: C==M by coincidence but genuinely non-identity — a merge
        # (فَمَنۢ+بَدَّلَهُۥ) or muqaṭṭaʿāt split (طسٓ) with a compensating split/merge
        # elsewhere. Verified correct; whitelisted so the check flags only regressions.
        IDENTITY_OK_NONID = {"2:181", "27:1"}
        C = hi - lo
        if C == M:
            identity_tot += 1
            ok = True
            for k, ci in enumerate(range(lo, hi)):
                if align[ci] != [f"{surah}:{a+1}:{k+1}"]:
                    ok = False
                    break
            if ok or key in IDENTITY_OK_NONID:
                identity_ok += 1
            else:
                identity_bad.append((key, f"C==M=={M} but not identity: "
                                     f"{[align[ci] for ci in range(lo, hi)]}"))
        # text2phoneme corroboration (informational only — t2p is NOT ayah-indexed,
        # so T rarely equals M; kept as a weak sanity signal, not a pass/fail gate)
        T = T_of.get(key)
        if T == M:
            t_eq_m += 1
        else:
            t_ne_m.append((key, f"T(text2phoneme)={T} M(mushaf)={M} C(corpus)={hi-lo}"))

with open(REPORT, "w", encoding="utf-8") as fh:
    fh.write("CORPUS->MUSHAF ALIGNMENT VALIDATION\n" + "=" * 55 + "\n")
    fh.write(f"ayat total                 : {tot}\n")
    fh.write(f"coverage complete & exact  : {complete}\n")
    fh.write(f"monotonic (in order)       : {monotonic_ok}\n")
    fh.write(f"identity on C==M ayat      : {identity_ok}/{identity_tot}\n")
    fh.write(f"per-group sim < {SIM_FLOOR}        : {groups_low}/{groups_tot} "
             f"(baseline {SIM_LOW_BASELINE}; {'OK' if groups_low <= SIM_LOW_BASELINE else 'REGRESSION'})\n")
    fh.write(f"T(text2phoneme) == M(mushaf): {t_eq_m}\n")
    fh.write(f"ordered vs text2phoneme phoneme-string mismatches: {phon_mismatch}\n")
    fh.write(f"\nINCOMPLETE coverage ({len(incomplete)}):\n")
    for k, s in incomplete:
        fh.write(f"  {k}: {s}\n")
    fh.write(f"\nEXTRA/wrong locations ({len(extras)}):\n")
    for k, s in extras:
        fh.write(f"  {k}: {s}\n")
    fh.write(f"\nNON-MONOTONIC ({len(nonmono)}):\n")
    for k, s in nonmono[:30]:
        fh.write(f"  {k}: {s}\n")
    fh.write(f"\nIDENTITY VIOLATIONS on C==M ({len(identity_bad)}):\n")
    for k, s in identity_bad[:60]:
        fh.write(f"  {k}: {s}\n")
    fh.write(f"\nLOW per-group sim < {SIM_FLOOR} ({groups_low}) [expect legit phonetic + 13 cosmetic]:\n")
    for k, ci, sc, g, mcat, locs in low_sim:
        fh.write(f"  {k} c{ci} sim={sc} phon='{g}' mushaf='{mcat}' -> {locs}\n")
    fh.write(f"\nT != M ({len(t_ne_m)}):\n")
    for k, s in t_ne_m[:60]:
        fh.write(f"  {k}: {s}\n")

print("ayat", tot)
print("coverage_complete", complete, "(", tot - complete, "not)")
print("monotonic", monotonic_ok)
print("identity_on_C==M", f"{identity_ok}/{identity_tot}", "(", identity_tot - identity_ok, "bad)")
print("per_group_sim<%.1f" % SIM_FLOOR, f"{groups_low}/{groups_tot}",
      "baseline", SIM_LOW_BASELINE, "->", "OK" if groups_low <= SIM_LOW_BASELINE else "REGRESSION")
print("incomplete", len(incomplete), "extras", len(extras), "nonmono", len(nonmono), "identity_bad", len(identity_bad))
print("report ->", REPORT)
