"""Fetch per-word imlaei-orthography text (quran.com API) for all 604 pages.

The ASR model's BPE tokenizer was trained on canonical imlaei-orthography
text (not Uthmani rasm) -- forced alignment needs reference token sequences
built from the same orthography convention the model actually outputs.
Output: assets/asr/imlaei.json, a flat {"s:a:w": "imlaei word", ...} map
keyed by the same location format used in assets/mushaf/page-*.json.
"""
import urllib.request, json, os, concurrent.futures

BASE = "https://api.quran.com/api/v4/verses/by_page/%d?words=true&word_fields=text_imlaei,location"
OUT = "assets/asr/imlaei.json"


def fetch(page):
    req = urllib.request.Request(BASE % page, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=40) as r:
        d = json.loads(r.read().decode())
    out = {}
    for v in d["verses"]:
        for w in v["words"]:
            if w.get("char_type_name") != "word":
                continue
            out[w["location"]] = w["text_imlaei"]
    return page, out


result = {}
errs = []
done = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    futs = {ex.submit(fetch, p): p for p in range(1, 605)}
    for fut in concurrent.futures.as_completed(futs):
        p = futs[fut]
        try:
            _, words = fut.result()
            result.update(words)
        except Exception as e:
            errs.append((p, str(e)))
        done += 1
        if done % 100 == 0:
            print("...%d done" % done, flush=True)

print("TOTAL words:", len(result), "errors:", errs[:10])
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, separators=(",", ":"))
