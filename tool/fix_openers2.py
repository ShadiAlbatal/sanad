import json
ch=json.load(open('assets/data/chapters.json',encoding='utf-8'))
starts={c['id']:c['startPage'] for c in ch}; names={c['id']:c['nameArabic'] for c in ch}
def load(p): return json.load(open('assets/mushaf/page-%03d.json'%p,encoding='utf-8'))
def save(p,o): json.dump(o,open('assets/mushaf/page-%03d.json'%p,'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))
def qc(p): return json.load(open('tool/_cache/qc/page-%03d.json'%p,encoding='utf-8'))
def first_ayah_line(p,sid):
    d=qc(p); ws=[w for v in d['verses'] for w in v['words'] if w['char_type_name']=='word']
    return min(w['line_number'] for w in ws if int(w['location'].split(':')[0])==sid)

for sid in [22,23,26,32,37,64]:
    sp=starts[sid]; snum='%03d'%sid; name='سورة '+names[sid]
    assert first_ayah_line(sp,sid)==2, sid
    # 1) start page: basmala L1 -> combined opener
    pg=load(sp)
    assert pg['lines'][0]['line']==1 and pg['lines'][0]['type']=='basmala', (sp,pg['lines'][0])
    pg['lines'][0]={'line':1,'type':'surah-opener','surah':snum,'text':name}
    save(sp,pg)
    # 2) remove the spurious header sitting at the bottom of a later page
    for p in range(1,605):
        d=load(p); before=len(d['lines'])
        keep=[l for l in d['lines'] if not (p!=sp and l['type'] in ('surah-header','surah-opener') and str(l.get('surah',''))==snum)]
        if len(keep)<before:
            # it must have been the last line, page otherwise full of text
            removed=[l for l in d['lines'] if l not in keep][0]
            assert removed['line']==before, (p,'stray header not last line',removed)
            d['lines']=keep; save(p,d)
            print('surah %2d: opener added p%d, removed stray header at p%d L%d'%(sid,sp,p,removed['line']))
