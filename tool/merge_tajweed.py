import urllib.request, json, os, time, concurrent.futures
API="https://api.quran.com/api/v4/verses/by_page/%d?words=true&word_fields=text_uthmani_tajweed&per_page=300"
MUSHAF="assets/mushaf"
HDRS={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) TilawaAi/1.0","Accept":"application/json"}

def get_json(url, tries=4):
    last=None
    for t in range(tries):
        try:
            req=urllib.request.Request(url, headers=HDRS)
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            last=e; time.sleep(1.5*(t+1))
    raise last

def loc_map(page):
    d=get_json(API%page)
    m={}
    for v in d["verses"]:
        vk=v["verse_key"]
        for w in v["words"]:
            if w.get("char_type_name")=="word":
                m["%s:%d"%(vk,w["position"])]=w.get("text_uthmani_tajweed","")
    return m

def process(page):
    try:
        m=loc_map(page)
        path=os.path.join(MUSHAF,"page-%03d.json"%page)
        d=json.load(open(path,encoding="utf-8"))
        n=0
        for ln in d.get("lines",[]):
            for w in ln.get("words",[]):
                tj=m.get(w.get("location"))
                if tj: w["tj"]=tj; n+=1
        json.dump(d, open(path,"w",encoding="utf-8"), ensure_ascii=False, separators=(",",":"))
        return (page, n, None)
    except Exception as e:
        return (page, 0, str(e))

try:
    d1=get_json(API%1)
    bwords=[w.get("text_uthmani_tajweed","") for w in d1["verses"][0]["words"] if w.get("char_type_name")=="word"]
    json.dump({"words":bwords}, open("assets/data/basmala.json","w",encoding="utf-8"), ensure_ascii=False)
    print("basmala words:", len(bwords))
except Exception as e:
    print("basmala ERR", e)

done=0; errs=[]; total=0
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
    for page,n,err in ex.map(process, range(1,605)):
        done+=1; total+=n
        if err: errs.append((page,err))
        if done%100==0: print("...%d (words tagged so far %d)"%(done,total), flush=True)
print("done. total words tagged:", total, "errors:", errs[:8])
