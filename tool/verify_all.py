import urllib.request,json,os,time,sys
os.makedirs('tool/_cache/qc',exist_ok=True)
def fetch(p):
    fn='tool/_cache/qc/page-%03d.json'%p
    if os.path.exists(fn): return json.load(open(fn,encoding='utf-8'))
    url='https://api.quran.com/api/v4/verses/by_page/%d?words=true&per_page=all&word_fields=line_number,location,char_type_name'%p
    req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0','Accept':'application/json'})
    for attempt in range(4):
        try:
            d=json.loads(urllib.request.urlopen(req,timeout=60).read().decode())
            json.dump(d,open(fn,'w',encoding='utf-8'),ensure_ascii=False); time.sleep(0.12); return d
        except Exception as e:
            time.sleep(1.0+attempt)
    raise RuntimeError('fail page %d'%p)

def qc_line_groups(d):
    words=[w for v in d['verses'] for w in v['words'] if w['char_type_name']=='word']
    byline={}
    for w in words: byline.setdefault(w['line_number'],[]).append(w['location'])
    return [byline[ln] for ln in sorted(byline)]

def our_line_groups(pg):
    p=json.load(open('assets/mushaf/page-%03d.json'%pg,encoding='utf-8'))
    return [[w['location'] for w in l.get('words',[])] for l in p['lines'] if l['type']=='text']

seq_mismatch=[]; done=0
for pg in range(1,605):
    d=fetch(pg)
    qc=qc_line_groups(d)
    our=our_line_groups(pg)
    if qc!=our: seq_mismatch.append(pg)
    done+=1
    if done%100==0: print('...%d fetched'%done,flush=True)
print('PAGES where our per-line word grouping != quran.com:',len(seq_mismatch))
print(seq_mismatch)
