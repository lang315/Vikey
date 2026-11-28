#!/usr/bin/env python3
"""Cases for the suggestion benchmark: a place in a real sentence where the bar is read.

    make_cases.py OUT_DIR TEXT_FILE... [--per-split N] [--seed S]

Each case is [id, text before the cursor, letters to type]:
- "part": a word cut after 1..len-1 of its letters (every keystroke equally likely),
- "full": the whole word typed, before the space,
- "next": nothing typed after a space (next-word predictions).
Texts are split in two by line (dev to tune on, test to report), so no sentence is in both (repeated lines are
kept once).
Writes cases_<split>.json (lists of [id, context, letters, word, kind]) and apple_in_<split>.json ([id, context,
letters]: what apple_run.sh and vikey_run.sh read).
"""
import json, random, re, sys

args = sys.argv[1:]
per_split = int(args[args.index('--per-split') + 1]) if '--per-split' in args else 1000
seed = int(args[args.index('--seed') + 1]) if '--seed' in args else 7
files = [a for i, a in enumerate(args[1:], 1) if not a.startswith('--') and args[i - 1] not in ('--per-split', '--seed')]
out = args[0]
rnd = random.Random(seed)
KINDS = [('part', 0.7), ('full', 0.15), ('next', 0.15)]

def places(line):
    """Words that can be typed at a word start: letters only, after a space or at the start."""
    for m in re.finditer(r'[A-Za-z]+', line):
        s, e = m.span()
        if (s == 0 or line[s - 1] == ' ') and (e == len(line) or not line[e].isalnum()):
            yield s, m.group()

lines, seen = [], set()
for f in files:
    for l in open(f, encoding='utf-8'):
        l = ' '.join(l.split())
        key = l.lower()
        if len(l.split()) < 4 or key in seen or next(places(l), None) is None: continue
        seen.add(key); lines.append((f.split('/')[-1].split('.')[0], l))
rnd.shuffle(lines)
halves = {'dev': lines[0::2], 'test': lines[1::2]}
if not halves['test']: sys.exit('not enough lines with a word to type for two splits')

for split, ls in halves.items():
    cases, n = [], 0
    while len(cases) < per_split:
        src, line = ls[n % len(ls)]; n += 1
        p = list(places(line))
        if not p: continue
        s, word = rnd.choice(p)
        ctx = line[:s]
        if len(ctx) > 200:   # the last 200 characters, from a word start
            ctx = ctx[-200:]; ctx = ctx[ctx.find(' ') + 1:]
        r = rnd.random()
        kind = 'part' if r < KINDS[0][1] else 'full' if r < KINDS[0][1] + KINDS[1][1] else 'next'
        if kind == 'part':
            if len(word) < 2: continue
            letters = word[:rnd.randint(1, len(word) - 1)].lower()
        elif kind == 'full':
            letters = word.lower()
        else:
            if not ctx: continue
            letters = ''
        cases.append([f'{split}-{len(cases):04d}', ctx, letters, word, kind])
    json.dump(cases, open(f'{out}/cases_{split}.json', 'w'), ensure_ascii=False, indent=0)
    json.dump([c[:3] for c in cases], open(f'{out}/apple_in_{split}.json', 'w'), ensure_ascii=False)
    print(split, len(cases), {k: sum(c[4] == k for c in cases) for k, _ in KINDS})
