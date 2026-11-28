#!/usr/bin/env python3
"""Score whole words typed by scattered taps (iOS/Tests/TypingAccuracyTests, TYPED lines):

    score_typed.py CASES.json LOG [--show N]
right = the word that ended up in the text is the one meant (case-blind, an apostrophe the keyboard added is fine);
taps alone = the keys the taps picked spell it (before auto-correct; Vietnamese cases: its Telex keys). Of the words whose taps were wrong, how many
were fixed; of those typed right, how many were broken.
"""
import collections
import json
import sys
import unicodedata
cases = {c[0]: c for c in json.load(open(sys.argv[1]))}
show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 0
st = collections.Counter(); miss = []
for l in open(sys.argv[2], encoding='utf-8'):
    if not l.startswith('TYPED\t'): continue
    j = json.loads(l.split('\t', 1)[1]); c = cases[j['id']]
    want = unicodedata.normalize('NFC', c[2].lower())
    want_keys = c[3].lower() if len(c) > 3 else want   # Vietnamese cases: the word's Telex keys
    got = unicodedata.normalize('NFC', j['got'].strip().lower().replace('’', "'"))
    keys = j['keys']
    ok = got == want or got.replace("'", '') == want
    st['n'] += 1; st['right'] += ok
    if keys != want_keys:
        st['typo'] += 1; st['fixed'] += ok
        if not ok: miss.append((want, keys, got))
    else:
        st['clean'] += 1; st['broken'] += not ok
        if not ok: miss.append((want, keys, got))
n = st['n']
print(f"{n} words: right {100 * st['right'] / n:.2f}%; taps alone right {100 * st['clean'] / n:.1f}%; "
      f"mistyped {st['typo']}, fixed {st['fixed']} ({100 * st['fixed'] / max(1, st['typo']):.1f}%); typed right {st['clean']}, broken {st['broken']}")
for m in miss[:show]: print('  want', m[0], '| taps', m[1], '| got', m[2])
