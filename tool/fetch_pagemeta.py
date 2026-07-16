import urllib.request, json, concurrent.futures, time
API="https://api.quran.com/api/v4/verses/by_page/%d?fields=juz_number,hizb_number,rub_el_hizb_number,chapter_id&per_page=1"
HDRS={"User-Agent":"Mozilla/5.0 TilawaAi/1.0","Accept":"application/json"}
def get(p):
    for t in range(4):
        try:
            req=urllib.request.Request(API%p, headers=HDRS)
            with urllib.request.urlopen(req, timeout=45) as r:
                v=json.loads(r.read().decode())["verses"][0]
            return (p, {"juz":v["juz_number"],"hizb":v["hizb_number"],"rub":v["rub_el_hizb_number"],"surah":v["chapter_id"]})
        except Exception as e:
            time.sleep(1.2*(t+1)); last=e
    return (p, None)
out={}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
    for p,m in ex.map(get, range(1,605)):
        if m: out[str(p)]=m
print("pages:", len(out), "| p1:", out.get("1"), "| p604:", out.get("604"))
json.dump(out, open("assets/data/page_meta.json","w",encoding="utf-8"), ensure_ascii=False, separators=(",",":"))
