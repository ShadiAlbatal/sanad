# -*- coding: utf-8 -*-
"""Generate assets/data/quran_content_reference.json: a flat {"s:a:w": "word"}
map of every word's Uthmani text across all 604 mushaf pages, used by
test/quran_content_test.dart to catch scripture corruption offline and
deterministically (no network, no manual script).

Before writing, cross-checks total + per-page word counts against the cached
quran.com API v4 data (tool/_cache/qc/*.json, fetched during the 2026-07-16
surah-opener verification) as an independent sanity check -- refuses to write
if anything doesn't line up.
"""
import json
import os

QC_DIR = 'tool/_cache/qc'
MUSHAF_DIR = 'assets/mushaf'
OUT = 'assets/data/quran_content_reference.json'

ref = {}
mismatches = []
total_ours = 0
total_qc = 0

for pg in range(1, 605):
    mushaf_path = '%s/page-%03d.json' % (MUSHAF_DIR, pg)
    page = json.load(open(mushaf_path, encoding='utf-8'))
    our_words = [
        (w['location'], w['word'])
        for line in page['lines'] if line['type'] == 'text'
        for w in line.get('words', [])
    ]
    total_ours += len(our_words)
    for loc, word in our_words:
        ref[loc] = word

    qc_path = '%s/page-%03d.json' % (QC_DIR, pg)
    if os.path.exists(qc_path):
        qc = json.load(open(qc_path, encoding='utf-8'))
        qc_count = sum(1 for v in qc['verses'] for w in v['words'] if w['char_type_name'] == 'word')
        total_qc += qc_count
        if qc_count != len(our_words):
            mismatches.append((pg, len(our_words), qc_count))

if mismatches:
    raise SystemExit('word-count mismatch vs quran.com, refusing to write: %r' % mismatches)

print('total words:', total_ours, '(quran.com cross-check:', total_qc, ')')
print('unique locations:', len(ref))

with open(OUT, 'w', encoding='utf-8') as f:
    json.dump(ref, f, ensure_ascii=False, separators=(',', ':'))
print('wrote', OUT)
