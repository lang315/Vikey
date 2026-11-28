#!/usr/bin/env python3
"""Score Vikey's Vietnamese bar (no Apple side: Tony, "Apple word suggestion for vn is also bad"):

    score_vi.py CASES_VI.json VIKEY.jsonl
Cases from vikey-data lm_vi/make_cases_vi.py, Vikey's bar from vikey_run.sh with TEST_RUNNER_MODE=vi.
For each kind (part: a syllable's keys cut short; next: after a space), how often the syllable typed next is in
the bar (offered) and is its first word (first). Compared NFC, case-blind.
"""
import json, collections, unicodedata, sys
cases={c[0]:c for c in json.load(open(sys.argv[1]))}
v={j['id']:j for j in map(json.loads, open(sys.argv[2]))}
st=collections.Counter()
for i,c in cases.items():
    cells=[unicodedata.normalize('NFC',t).lower() for t,_ in v[i]['cells']]
    typed=unicodedata.normalize('NFC',v[i].get('typed','')).lower()
    offered=[x for x in cells if x!=typed or not typed]
    want=unicodedata.normalize('NFC',c[3]).lower()
    st[c[4],'n']+=1; st[c[4],'hit']+=want in offered
    st[c[4],'top']+= bool(offered) and offered[0]==want
for k in ('part','next'):
    print(k, st[k,'n'], 'intended offered %.1f%%'%(100*st[k,'hit']/st[k,'n']), 'first %.1f%%'%(100*st[k,'top']/st[k,'n']))
