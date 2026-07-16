import urllib.request, json, os, concurrent.futures
BASE="https://raw.githubusercontent.com/zonetecde/mushaf-layout/main/mushaf/page-%03d.json"
OUT="assets/mushaf"
os.makedirs(OUT, exist_ok=True)
def strip(d):
    for ln in d.get("lines",[]):
        ln.pop("qpcV1", None)
        for w in ln.get("words",[]):
            w.pop("qpcV1", None)
    return d
def fetch(p):
    dst=os.path.join(OUT,"page-%03d.json"%p)
    if os.path.exists(dst) and os.path.getsize(dst)>50: return (p,"skip")
    try:
        with urllib.request.urlopen(BASE%p, timeout=40) as r:
            d=json.loads(r.read().decode())
        with open(dst,"w",encoding="utf-8") as f:
            json.dump(strip(d),f,ensure_ascii=False,separators=(",",":"))
        return (p,"ok")
    except Exception as e:
        return (p,"ERR %s"%e)
done=0; errs=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as ex:
    for p,st in ex.map(fetch, range(1,605)):
        done+=1
        if st.startswith("ERR"): errs.append((p,st))
        if done%100==0: print("...%d done"%done, flush=True)
print("TOTAL files:", len(os.listdir(OUT)), "errors:", errs[:10])
