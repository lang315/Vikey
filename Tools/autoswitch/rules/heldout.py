#!/usr/bin/env python3
"""Scores the engine on a text file kept outside this repo (e.g. the private held-out set in vikey-data).

usage: heldout.py TEXT [TEXT ...] [--sim PATH] [--words] [--json OUT]

Same runs and numbers as golden.py, on the given text instead of the public corpora:
  clean    the text typed with Telex (sim/prep.py, varied tone positions), Vietnamese mode at the start
  typos    the same with 3% of Vietnamese words slipped (prep.py --typos 0.03)
Per run:
  errors   lazy typer (never presses the switch key): words that come out different from the text
  manual   ideal typer: switch presses needed (presses only when the next word would come out wrong)
  wrong    ideal typer: words still wrong even after the switch press (golden.py's "wrong words")
--words lists every word the lazy typer got wrong (want -> got), for comparing two engines.
--sim uses another simulator binary (default: sim/sim, built by check.sh).
The text never enters the repo: this only reads it."""
import json, os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
AS = os.path.dirname(HERE)
args = sys.argv[1:]
sim = os.path.join(AS, 'sim', 'sim')
if '--sim' in args: i = args.index('--sim'); sim = args[i + 1]; del args[i:i + 2]
out_json = None
if '--json' in args: i = args.index('--json'); out_json = args[i + 1]; del args[i:i + 2]
show_words = '--words' in args
files = [a for a in args if not a.startswith('--')]
if not files: sys.exit(__doc__)
tmp = tempfile.mkdtemp(prefix='vikey_heldout_')

def lazy_diff(dump):
    """(want word, got word, line) for every word of the text the lazy typer got wrong (LCS, like sim.cpp)."""
    bad = []
    # one "got<TAB>want" record per message; got can hold a line break (a digit typed after Enter), want can't
    parts = open(dump, encoding='utf-8').read().rstrip('\n').split('\t')
    records, got = [], parts[0]
    for p in parts[1:]:
        want, _, nxt = p.partition('\n')
        records.append((got, want)); got = nxt
    for got, want in records:
        g, w = got.split(), want.split()
        L = [[0] * (len(w) + 1) for _ in range(len(g) + 1)]
        for a in range(1, len(g) + 1):
            for b in range(1, len(w) + 1):
                L[a][b] = L[a-1][b-1] + 1 if g[a-1] == w[b-1] else max(L[a-1][b], L[a][b-1])
        a, b, miss_g, miss_w = len(g), len(w), [], []
        while a > 0 and b > 0:
            if g[a-1] == w[b-1]: a -= 1; b -= 1
            elif L[a-1][b] >= L[a][b-1]: miss_g.append(g[a-1]); a -= 1
            else: miss_w.append(w[b-1]); b -= 1
        miss_g += g[:a][::-1]; miss_w += w[:b][::-1]
        miss_g.reverse(); miss_w.reverse()
        for k, ww in enumerate(miss_w): bad.append((ww, miss_g[k] if k < len(miss_g) else '', want))
    return bad

res = {}
for path in files:
    name = os.path.splitext(os.path.basename(path))[0]
    for typos in (0, 0.03):
        key = name + ('_typos' if typos else '')
        u = os.path.join(tmp, key + '.units')
        cmd = ['python3', os.path.join(AS, 'sim', 'prep.py'), path] + (['--typos', str(typos)] if typos else [])
        with open(u, 'w') as f: subprocess.run(cmd, stdout=f, check=True)
        ideal = subprocess.run([sim, u], capture_output=True, text=True).stdout
        dump = os.path.join(tmp, key + '.dump')
        lazy = subprocess.run([sim, u, '--lazy', '--dump', dump], capture_output=True, text=True).stdout
        m = re.search(r'words (\d+) .*manual switches (\d+).*wrong words (\d+)', ideal)
        lz = re.search(r'words (\d+)\s+wrong words (\d+)', lazy)
        res[key] = {'words': int(m.group(1)), 'errors': int(lz.group(2)), 'manual': int(m.group(2)), 'wrong': int(m.group(3))}
        r = res[key]
        print(f"{key}: words {r['words']}  errors (lazy) {r['errors']}  manual {r['manual']}  wrong {r['wrong']}")
        if show_words:
            for want, got, line in lazy_diff(dump): print(f'  {want!r} -> {got!r}\t| {line}')
if out_json: json.dump(res, open(out_json, 'w'), indent=1)
