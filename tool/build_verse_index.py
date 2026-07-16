"""Build assets/asr/verse_index.json for ASR acquisition + navigation.

One compact record per verse (Hafs, 6236 total):
  {"k": "2:10", "p": <page 1..604>, "n": <word count>}

- `k` = surah:ayah key. Per-word reference tokens are looked up at runtime as
  "k:1".."k:n" against ref_tokens.json, so we don't duplicate token data here.
- `p` = the page the verse STARTS on (first word's page), for navigating the
  mushaf display to a verse that acquisition locks onto.
- `n` = word count, so the runtime can enumerate word locations.

Page is derived by scanning the bundled mushaf pages (assets/mushaf/page-*.json),
which list every word's `location`.
"""
import json
import glob
import os
import re


def main():
    # verse -> page it first appears on
    verse_page = {}
    for path in glob.glob("assets/mushaf/page-*.json"):
        page = int(re.search(r"page-(\d+)\.json", path).group(1))
        d = json.load(open(path, encoding="utf-8"))
        for ln in d.get("lines", []):
            for w in ln.get("words", []):
                loc = w.get("location")
                if not loc:
                    continue
                s, a, _ = loc.split(":")
                key = f"{s}:{a}"
                if key not in verse_page or page < verse_page[key]:
                    verse_page[key] = page

    # word counts from ref_tokens (authoritative word set used by the ASR)
    ref = json.load(open("assets/asr/ref_tokens.json", encoding="utf-8"))
    counts = {}
    for loc in ref:
        s, a, w = loc.split(":")
        key = f"{s}:{a}"
        counts[key] = max(counts.get(key, 0), int(w))

    def sort_key(k):
        s, a = k.split(":")
        return (int(s), int(a))

    index = []
    missing_page = 0
    for key in sorted(counts, key=sort_key):
        page = verse_page.get(key)
        if page is None:
            missing_page += 1
            continue
        index.append({"k": key, "p": page, "n": counts[key]})

    print("verses:", len(index), "missing page:", missing_page)
    with open("assets/asr/verse_index.json", "w", encoding="utf-8") as f:
        json.dump(index, f, separators=(",", ":"))


if __name__ == "__main__":
    main()
