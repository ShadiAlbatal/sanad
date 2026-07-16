import json
ch=json.load(open('assets/data/chapters.json',encoding='utf-8'))
starts={c['id']:c['startPage'] for c in ch}
names={c['id']:c['nameArabic'] for c in ch}
def qc(p): return json.load(open('tool/_cache/qc/page-%03d.json'%p,encoding='utf-8'))
def first_ayah_line(p,sid):
    d=qc(p); ws=[w for v in d['verses'] for w in v['words'] if w['char_type_name']=='word']
    return min(w['line_number'] for w in ws if int(w['location'].split(':')[0])==sid)
def load(p): return json.load(open('assets/mushaf/page-%03d.json'%p,encoding='utf-8'))
def save(p,obj): json.dump(obj,open('assets/mushaf/page-%03d.json'%p,'w',encoding='utf-8'),ensure_ascii=False,separators=(',',':'))

missing=[4,10,24,27,33,38,45,47,53,60,65,80,81,82,85,86,91]
changed=[]
for sid in missing:
    sp=starts[sid]; fl=first_ayah_line(sp,sid); name='سورة '+names[sid]; snum='%03d'%sid
    pg=load(sp); lines=pg['lines']
    if fl==2:
        # combined opener: line 1 must currently be the basmala
        assert lines[0]['line']==1 and lines[0]['type']=='basmala', (sp,'expected basmala L1',lines[0])
        lines[0]={'line':1,'type':'surah-opener','surah':snum,'text':name}
        changed.append((sp,sid,'combined-opener'))
    elif fl==3:
        # two openers dropped + ayahs shifted up: prepend header+basmala, shift +2
        assert lines[0]['type']=='text', (sp,'expected text L1 (shifted)',lines[0])
        for l in lines: l['line']+=2
        pg['lines']=[{'line':1,'type':'surah-header','surah':snum,'text':name},
                     {'line':2,'type':'basmala'}]+lines
        changed.append((sp,sid,'inserted header+basmala'))
    else:
        raise SystemExit('unexpected fl=%d for surah %d p%d'%(fl,sid,sp))
    save(sp,pg)
    assert len(load(sp)['lines'])<=15, (sp,'>15 lines')
print('patched %d pages:'%len(changed))
for c in changed: print('  page %d surah %d : %s'%c)
