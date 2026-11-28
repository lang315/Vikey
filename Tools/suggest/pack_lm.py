#!/usr/bin/env python3
"""Packs vikey-data's English n-gram counts (lm_en/: vocab.tsv, bi.tsv.gz, tri.tsv.gz, made by lm_en/fetch_lm.py from
FineWeb and Reddit, see ACKNOWLEDGEMENTS.md) into iOS/Keyboard/SuggestEN.bin, which SuggestLM.swift memory-maps.

    pack_lm.py [--src SUBDIR] [--minc 20]                                  English: SuggestEN.bin
    pack_lm.py --data ~/Work/vikey-data/lm_vi --out SuggestVI --minc 20    Vietnamese: SuggestVI.bin

The model: Katz back-off, trigram -> bigram -> unigram. A pair or triple is kept when seen >= minc times; the rest of
its context's mass (beta) goes to the order below, so dropping an entry costs little. Discount D = 0.75.

Layout, little-endian, every section 4-byte aligned:
  "VKLM0002", then u32: nWords, nTri, nBiEntries, nTriEntries, blobBytes, uniTotal
  keyOffsets u32[nWords+1]    words byte-sorted (lowercase, ' kept), so a prefix is a range of ids;
  blob                        each word's key, then "\\t" + its display form when that differs ("i\\tI", "youtube\\tYouTube")
  uni u32[nWords]             counts
  biStart u32[nCtx+1], biTotal u32[nCtx], biBeta f32[nCtx]     one context per word id, then <s> and <,>
  biIds u16[nBiEntries], biCounts u16[nBiEntries]              per context, sorted by id; a count c is kept as
                                                               round(ln(c) * 2000), within 0.03% of it
  triKeys u32[nTri] (id1 << 16 | id2, sorted), triStart u32[nTri+1], triTotal u32[nTri], triBeta f32[nTri]
  triIds u16[nTriEntries], triCounts u16[nTriEntries]
  top u16[64]                 the most common words, next-word candidates in any context
"""
import collections, gzip, math, os, struct, sys
SRC = os.path.expanduser(sys.argv[sys.argv.index('--data') + 1] if '--data' in sys.argv else
                         '~/Work/vikey-data/lm_en/' + (sys.argv[sys.argv.index('--src') + 1] if '--src' in sys.argv else ''))
NAME = sys.argv[sys.argv.index('--out') + 1] if '--out' in sys.argv else 'SuggestEN'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'iOS', 'Keyboard', NAME + '.bin')
MINC = int(sys.argv[sys.argv.index('--minc') + 1]) if '--minc' in sys.argv else 20
MAXW = 60000   # word ids are u16
D = 0.75

vocab = []
for l in open(f'{SRC}/vocab.tsv', encoding='utf-8'):
    w, c, form = l.rstrip('\n').split('\t')
    if len(w) == 1 and w.isascii() and w not in ('a', 'i'): continue   # letters on their own aren't words (ở, à are)
    vocab.append((w, int(c), form))
vocab = sorted(vocab, key=lambda x: -x[1])[:MAXW]
vocab.sort(key=lambda x: x[0].encode())
ids = {w: i for i, (w, _, _) in enumerate(vocab)}
N = len(vocab)
assert N + 2 < 65536, N
ids['<s>'], ids['<,>'] = N, N + 1
uni = [c for _, c, _ in vocab]
total = sum(uni)
p1 = [c / total for c in uni]

bi_all = collections.defaultdict(dict); bi_tot = collections.Counter()
for l in gzip.open(f'{SRC}/bi.tsv.gz', 'rt', encoding='utf-8'):
    k, c = l.rstrip('\n').split('\t'); a, b = k.split(' '); c = int(c)
    if a not in ids: continue
    bi_tot[a] += c
    if b in ids and b not in ('<s>', '<,>') and c >= MINC: bi_all[a][ids[b]] = c
bi_ctx = {}   # context id -> (total, beta, sorted entries)
for a, d in bi_all.items():
    n = bi_tot[a]
    kept = sum((c - D) / n for c in d.values()); low = sum(p1[w] for w in d)
    bi_ctx[ids[a]] = (n, (1 - kept) / max(1e-9, 1 - low), sorted(d.items()))
for a, n in bi_tot.items():
    if ids[a] not in bi_ctx: bi_ctx[ids[a]] = (n, 1.0, [])

def p2(w, b):
    e = bi_ctx.get(b)
    if not e: return p1[w]
    n, beta, entries = e
    c = dict(entries).get(w) if len(entries) < 64 else None
    if c is None:
        import bisect
        i = bisect.bisect_left(entries, (w, 0))
        c = entries[i][1] if i < len(entries) and entries[i][0] == w else None
    return (c - D) / n if c else beta * p1[w]

tri_all = collections.defaultdict(dict); tri_tot = collections.Counter()
for l in gzip.open(f'{SRC}/tri.tsv.gz', 'rt', encoding='utf-8'):
    k, c = l.rstrip('\n').split('\t'); a, b, w = k.split(' '); c = int(c)
    if a not in ids or b not in ids: continue
    key = ids[a] << 16 | ids[b]
    tri_tot[key] += c
    if w in ids and w not in ('<s>', '<,>') and c >= MINC: tri_all[key][ids[w]] = c
tri = []
for key, d in tri_all.items():
    n = tri_tot[key]; b = key & 0xFFFF
    kept = sum((c - D) / n for c in d.values()); low = sum(p2(w, b) for w in d)
    tri.append((key, n, (1 - kept) / max(1e-9, 1 - low), sorted(d.items())))
tri.sort()

blob = bytearray(); offs = []
for w, _, form in vocab:
    offs.append(len(blob)); blob += w.encode() + (b'\t' + form.encode() if form != w else b'')
offs.append(len(blob))
def pad(b): return b + b'\0' * (-len(b) % 4)

nctx = N + 2
bi_start, bi_total, bi_beta, bi_ids, bi_counts = [0], [], [], [], []
for i in range(nctx):
    n, beta, entries = bi_ctx.get(i, (0, 1.0, []))
    bi_total.append(min(n, 2**32 - 1)); bi_beta.append(beta)
    for w, c in entries: bi_ids.append(w); bi_counts.append(c)
    bi_start.append(len(bi_ids))
tri_keys, tri_start, tri_total, tri_beta, tri_ids, tri_counts = [], [0], [], [], [], []
for key, n, beta, entries in tri:
    tri_keys.append(key); tri_total.append(n); tri_beta.append(beta)
    for w, c in entries: tri_ids.append(w); tri_counts.append(c)
    tri_start.append(len(tri_ids))

def q(c): return round(math.log(c) * 2000)   # fits u16 for counts up to e^32
out = bytearray(b'VKLM0002')
out += struct.pack('<6I', N, len(tri), len(bi_ids), len(tri_ids), len(blob), total)
out += struct.pack(f'<{N + 1}I', *offs)
out += pad(bytes(blob))
out += struct.pack(f'<{N}I', *uni)
out += struct.pack(f'<{nctx + 1}I', *bi_start) + struct.pack(f'<{nctx}I', *bi_total) + struct.pack(f'<{nctx}f', *bi_beta)
out += pad(struct.pack(f'<{len(bi_ids)}H', *bi_ids) + struct.pack(f'<{len(bi_counts)}H', *map(q, bi_counts)))
out += struct.pack(f'<{len(tri)}I', *tri_keys) + struct.pack(f'<{len(tri) + 1}I', *tri_start)
out += struct.pack(f'<{len(tri)}I', *tri_total) + struct.pack(f'<{len(tri)}f', *tri_beta)
out += pad(struct.pack(f'<{len(tri_ids)}H', *tri_ids) + struct.pack(f'<{len(tri_counts)}H', *map(q, tri_counts)))
top = sorted(range(N), key=lambda i: -uni[i])[:64]
out += struct.pack('<64H', *top)
open(OUT, 'wb').write(out)
print(f'{N} words, {len(bi_ids)} pairs, {len(tri)} two-word contexts with {len(tri_ids)} triples (minc {MINC})'
      f' -> {os.path.relpath(OUT)} {len(out) / 1e6:.1f} MB')
