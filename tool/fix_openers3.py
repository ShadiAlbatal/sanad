import json
def load(p): return json.load(open('assets/mushaf/page-%03d.json'%p,encoding='utf-8'))
def save(p,o): json.dump(o,open('assets/mushaf/page-%03d.json'%p,'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
def qc(p): return json.load(open('tool/_cache/qc/page-%03d.json'%p,encoding='utf-8'))
# authoritative page where each surah's S:1:1 sits
truePage={}
for p in range(1,605):
    for v in qc(p)['verses']:
        for w in v['words']:
            if w['char_type_name']=='word':
                s,a,ww=w['location'].split(':')
                if a=='1' and ww=='1': truePage.setdefault(int(s),p)
# remove any name line on a page where that surah does NOT start
removed=[]
for p in range(1,605):
    d=load(p); keep=[]; ch=False
    for l in d['lines']:
        if l['type'] in ('surah-header','surah-opener'):
            sid=int(l['surah'])
            if truePage.get(sid)!=p:
                removed.append((p,l['line'],sid)); ch=True; continue
        keep.append(l)
    if ch:
        # renumber remaining lines to be contiguous from their current order? NO —
        # removed lines were spurious extras at page bottom/top; keep original line numbers
        d['lines']=keep; save(p,d)
print('removed %d spurious name lines:'%len(removed))
for r in removed: print('  page %d line %d surah %d'%r)
# final invariant
namelines={}
for p in range(1,605):
    for l in load(p)['lines']:
        if l['type'] in ('surah-header','surah-opener'): namelines.setdefault(int(l['surah']),[]).append((p,l['line']))
tot=sum(len(v) for v in namelines.values())
print('total name lines now:',tot,'(should be 114)')
print('surahs without exactly one:',[s for s in range(1,115) if len(namelines.get(s,[]))!=1])
