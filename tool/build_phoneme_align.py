"""Build assets/asr/align/NNN.json — a per-surah map from phoneme-corpus word
index to the mushaf "surah:ayah:word" glyph(s) it covers.

The phoneme corpus (assets/asr/quran_phonemes) segments words differently from
the mushaf (assets/mushaf): it MERGES adjacent words (connected recitation) and
SPLITS others (muqaṭṭaʿāt). We align the two per āyah by their normalized letters
and assign every corpus word the mushaf glyph(s) its letters fall in.

We align on the corpus PHONEMES, not the corpus `words` field: `words` is a lossy
per-group label (for a merged group it shows only ONE of the words it covers — e.g.
2:263's 5 groups spell all 11 mushaf words in phonemes but `words` lists just 5),
so aligning `words` silently dropped mushaf glyphs on ~49 āyāt. The phoneme string
is complete, so aligning it recovers full coverage. Every mushaf word is then
guaranteed an owner (uncovered ones attach to their nearest neighbour's group).

    python tool/build_phoneme_align.py
"""
import json, glob, re, os
from collections import Counter

HARAKAT = re.compile('[ً-ْٰٓ-ٕـ]')


def _base(s: str) -> str:
    s = HARAKAT.sub('', s)
    for a in 'آأإٱ':
        s = s.replace(a, 'ا')
    s = s.replace('ء', '').replace('ى', 'ي').replace('ة', 'ه').replace('ؤ', 'و').replace('ئ', 'ي')
    s = re.sub(r'(.)\1+', r'\1', s)  # collapse elongation (madd) so both sides compare
    return re.sub(r'[^ء-ي]', '', s)


def mnorm(s: str) -> str:
    return _base(s)


def pnorm(s: str) -> str:
    # Phoneme units carry madd/ghunna marks; fold them to their base letter so the
    # phoneme skeleton matches the mushaf consonantal skeleton.
    s = s.replace('ۥ', 'و').replace('ۦ', 'ي').replace('ں', 'ن')
    return _base(s)


def _sim(a, b):
    # Cheap character-bag overlap (order-insensitive); enough to place segment
    # boundaries. O(len), so the full DP stays fast even on long āyāt.
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    ca, cb = Counter(a), Counter(b)
    inter = sum((ca & cb).values())
    return 2 * inter / (len(a) + len(b))


def _blocks(gp, mletters, maxa, maxb):
    """Monotonic BLOCK alignment: tile the C×M grid with contiguous blocks, each
    a≥1 corpus groups × b≥1 mushaf words, covering everything exactly once, to
    maximize total bag-similarity of the (concatenated corpus phonemes) vs
    (concatenated mushaf letters) in each block. A block handles all shapes at
    once — 1:1 (a=b=1), merge (a=1,b>1), muqaṭṭaʿāt split (a>1,b=1) — so merges
    and splits can coexist in one āyah. A tiny size penalty breaks ties toward
    1:1. Returns the list of chosen (i,j,a,b) blocks, or None if infeasible
    within the caps."""
    C, M = len(gp), len(mletters)
    NEG = float('-inf')
    dp = [[NEG] * (M + 1) for _ in range(C + 1)]
    bk = [[None] * (M + 1) for _ in range(C + 1)]
    dp[0][0] = 0.0
    # Only merge-blocks (1 corpus × b mushaf) or split-blocks (a corpus × 1
    # mushaf) — never both at once. A Quran region is a merge OR a split, not a
    # tangled many-to-many; excluding a>1&b>1 blocks removes spurious mappings
    # and cuts the inner loop from maxa*maxb to maxa+maxb.
    for i in range(C + 1):
        for j in range(M + 1):
            if dp[i][j] == NEG:
                continue
            for b in range(1, min(maxb, M - j) + 1):  # merge: gp[i] over b mushaf
                val = dp[i][j] + _sim(gp[i] if i < C else '', ''.join(mletters[j:j + b])) - 0.001 * (b - 1)
                if i < C and val > dp[i + 1][j + b]:
                    dp[i + 1][j + b] = val
                    bk[i + 1][j + b] = (i, j, 1, b)
            for a in range(2, min(maxa, C - i) + 1):  # split: a corpus over mletters[j]
                val = dp[i][j] + _sim(''.join(gp[i:i + a]), mletters[j] if j < M else '') - 0.001 * (a - 1)
                if j < M and val > dp[i + a][j + 1]:
                    dp[i + a][j + 1] = val
                    bk[i + a][j + 1] = (i, j, a, 1)
    if dp[C][M] == NEG:
        return None
    blocks = []
    i, j = C, M
    while (i, j) != (0, 0):
        pi, pj, a, b = bk[i][j]
        blocks.append((pi, pj, a, b))
        i, j = pi, pj
    return blocks


def align_ayah(groups, mlocs, mletters):
    """Map each corpus phoneme-group to the mushaf word(s) it covers, via a
    monotonic block alignment (complete + in-order by construction; merges and
    muqaṭṭaʿāt splits handled together). Caps bound the DP; widen if a rare long
    merge/split doesn't fit."""
    gp = [pnorm(g) for g in groups]
    C, M = len(gp), len(mlocs)
    blocks = (_blocks(gp, mletters, min(C, 8), min(M, 12))
              or _blocks(gp, mletters, min(C, 20), min(M, 40)))
    cover = [[] for _ in range(C)]
    for (i, j, a, b) in blocks:
        for gi in range(i, i + a):
            for mj in range(j, j + b):
                cover[gi].append(mlocs[mj])
    for gi in range(C):
        cover[gi] = sorted(set(cover[gi]), key=lambda L: int(L.split(':')[2]))
    return cover


def main():
    mushaf = {}
    for p in glob.glob('assets/mushaf/page-*.json'):
        d = json.load(open(p, encoding='utf-8'))
        for line in d['lines']:
            for w in line.get('words', []):
                m = re.match(r'^(\d+):(\d+):(\d+)$', w.get('location', ''))
                if not m:
                    continue
                s, a, wi = int(m[1]), int(m[2]), int(m[3])
                mushaf.setdefault((s, a), {})[wi] = (w['location'], mnorm(w.get('word', '')))

    incomplete = 0
    for f in sorted(glob.glob('assets/asr/quran_phonemes/*.json')):
        d = json.load(open(f, encoding='utf-8'))
        s = int(d['surah'])
        bnd = d['ayahBoundaries']
        p2w = d['phonemeToWord']
        ph = d['phonemes']
        N = len(d['words'])
        # per-corpus-word phoneme string
        wph = {}
        for u, w in zip(ph, p2w):
            wph.setdefault(w, []).append(u)
        word_str = {w: ''.join(v) for w, v in wph.items()}
        out = [[] for _ in range(N)]
        for ai in range(len(bnd)):
            lo = bnd[ai]
            hi = bnd[ai + 1] if ai + 1 < len(bnd) else N
            groups = [word_str.get(i, '') for i in range(lo, hi)]
            mw = mushaf.get((s, ai + 1))
            if not mw:
                for i in range(lo, hi):
                    out[i] = [f'{s}:{ai + 1}:{i - lo + 1}']
                continue
            keys = sorted(mw)
            mlocs = [mw[k][0] for k in keys]
            mletters = [mw[k][1] for k in keys]
            cover = align_ayah(groups, mlocs, mletters)
            for j, i in enumerate(range(lo, hi)):
                out[i] = cover[j]
            covered = set(l for c in cover for l in c)
            if covered != set(mlocs):
                incomplete += 1
        json.dump(out, open(f'assets/asr/align/{s:03d}.json', 'w', encoding='utf-8'), ensure_ascii=False)
    print(f'wrote 114 align files; ayat with incomplete coverage: {incomplete}')


if __name__ == '__main__':
    main()
