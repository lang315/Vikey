#!/usr/bin/env python3
"""Score Vikey's suggestion bar against Apple's.

    score.py CASES.json APPLE.jsonl VIKEY.jsonl [--show N] [--kind part|full|next]

The words a bar offers are its cells minus the word as typed (Apple quotes it: “resi”; Vikey's first cell).
For each case:
- recall = Apple's offered words that Vikey offers too (the target: >= 95%),
- top = Apple's first offered word is in Vikey's bar,
- fix = when Apple will auto-correct (a highlighted cell), Vikey highlights the same word,
- intended = the word the writer went on to type is offered (Vikey's rate, Apple's in brackets).
Words compare case-blind, ’ as '. Apple's multi-word cells ("receipt so") and emoji are counted, and shown apart.
"""
import argparse, json, sys
from collections import Counter

ap = argparse.ArgumentParser(description='Score Vikey\'s suggestion bar against Apple\'s.')
ap.add_argument('cases'); ap.add_argument('apple'); ap.add_argument('vikey')
ap.add_argument('--show', type=int, default=0, help='list this many cases where Vikey missed one of Apple\'s words')
ap.add_argument('--kind', choices=['part', 'full', 'next'])
ap.add_argument('--partial', action='store_true', help='score the cases both runs read, when one stopped early')
args = ap.parse_args()
show, only = args.show, args.kind
cases = {c[0]: c for c in json.load(open(args.cases))}
apple = {j['id']: j['cells'] for j in map(json.loads, open(args.apple))}
vikey = {j['id']: j for j in map(json.loads, open(args.vikey))}
missing = {name: len(set(cases) - set(run)) for name, run in (('apple', apple), ('vikey', vikey))}
if any(missing.values()):
    msg = ', '.join(f'{n} lacks {k} of {len(cases)} cases' for n, k in missing.items() if k)
    if not args.partial: sys.exit(f'{msg}: rerun, or --partial to score what both have')
    print(f'PARTIAL: {msg}')

def norm(s): return s.replace('’', "'").replace('‘', "'").strip('“”"').lower()
def offered_apple(cells):
    return [norm(t) for t, _ in cells if not t.startswith('“')]
def offered_vikey(j, typed):
    return [norm(t) for t, _ in j['cells'] if norm(t) != typed or not typed]
def fixes(cells): return [norm(t) for t, sel in cells if sel]

tot = Counter(); by = {}
misses = []
for cid, c in cases.items():
    if cid not in apple or cid not in vikey:
        continue
    kind = c[4]
    if only and kind != only: continue
    typed = norm(vikey[cid].get('typed', c[2]))
    A, V = offered_apple(apple[cid]), offered_vikey(vikey[cid], typed)
    k = by.setdefault(kind, Counter())
    want = norm(c[3])
    for t in (tot, k):
        t['want_apple'] += want in A
        t['want_vikey'] += want in V
        t['cases'] += 1
        t['apple_words'] += len(A)
        t['hit_words'] += sum(a in V for a in A)
        t['multi'] += sum(' ' in a for a in A)
        t['emoji'] += sum(not any(ch.isalpha() for ch in a) for a in A)
        if A: t['with_top'] += 1; t['top_hit'] += A[0] in V
        fa, fv = fixes(apple[cid]), fixes(vikey[cid]['cells'])
        if fa or fv:
            t['fix_cases'] += 1; t['fix_same'] += fa == fv
            t['apple_fix'] += bool(fa); t['vikey_fix'] += bool(fv)
    if any(a not in V for a in A): misses.append((cid, kind, c[1][-40:], c[2], c[3], A, V))

def line(name, t):
    pct = lambda a, b: f"{100 * a / b:5.1f}%" if b else "   - "
    return (f"{name:5} cases {t['cases']:5}  recall {pct(t['hit_words'], t['apple_words'])}  top {pct(t['top_hit'], t['with_top'])}"
            f"  fix-agree {pct(t['fix_same'], t['fix_cases'])} (apple {t['apple_fix']}, vikey {t['vikey_fix']})"
            f"  intended {pct(t['want_vikey'], t['cases'])} (apple {pct(t['want_apple'], t['cases'])})"
            f"  [apple multi-word {t['multi']}, emoji {t['emoji']} of {t['apple_words']}]")
for kind in ('part', 'full', 'next'):
    if kind in by: print(line(kind, by[kind]))
print(line('all', tot))
for m in misses[:show]:
    print(f"  {m[0]} {m[1]:4} …{m[2]!r} + {m[3]!r} ({m[4]})  apple {m[5]}  vikey {m[6]}")
