#!/usr/bin/env python3
"""Compare which key a tap lands on, Apple's keyboard vs Vikey's (AppleRefUITests.testTapMap run on each):

    tapmap.py TAPS.json APPLE.log VIKEY.log OUT_PREFIX
Prints the share of points where both keyboards type the same letter, per context, and draws OUT_PREFIX-<context>.png:
each point coloured by its letter (Apple on the left, Vikey on the right), points where they differ ringed.
"""
import json, sys, collections
from PIL import Image, ImageDraw, ImageFont

taps = {t[0]: t for t in json.load(open(sys.argv[1]))}
def read(p):
    out = {}
    for l in open(p, encoding='utf-8'):
        if l.startswith('TAP\t'):
            j = json.loads(l.split('\t', 1)[1])
            # the first character: Apple's field also takes its inline prediction ("j" shows as "just")
            out[j['id']] = j['got'][:1].lower()
    return out
apple, vikey = read(sys.argv[2]), read(sys.argv[3])
prefix = sys.argv[4]
ctxs = sorted({i.split('-')[0] for i in taps})
pal = {}
def color(ch):
    if ch not in pal:
        h = (len(pal) * 0.618) % 1
        import colorsys; r, g, b = colorsys.hsv_to_rgb(h, 0.55, 0.95); pal[ch] = (int(r * 255), int(g * 255), int(b * 255))
    return pal[ch]
for ctx in ctxs:
    ids = [i for i in taps if i.startswith(ctx + '-') and i in apple and i in vikey]
    if not ids: continue
    same = sum(apple[i] == vikey[i] for i in ids)
    diff = collections.Counter((apple[i], vikey[i]) for i in ids if apple[i] != vikey[i])
    print(f'{ctx}: {len(ids)} points, same letter {100 * same / len(ids):.1f}%; most common differences (apple, vikey):', diff.most_common(8))
    # one cell per tap point (10 x 6 pt), its letter written in it; Apple above, Vikey below; red: they differ
    xs = sorted({taps[i][2] for i in ids}); ys = sorted({taps[i][3] for i in ids})
    cw, ch_ = 26, 16                                  # a cell is 10 pt wide: 2.6 px per pt across
    W, H = int((max(xs) - min(xs) + 10) * 2.6), len(ys) * ch_
    img = Image.new('RGB', (W + 20, 2 * H + 70), 'white'); d = ImageDraw.Draw(img)
    try: font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 11)
    except Exception: font = ImageFont.load_default()
    at = {(taps[i][2], taps[i][3]): i for i in ids}
    for side, (name, res) in enumerate((('Apple', apple), ('Vikey', vikey))):
        top = 25 + side * (H + 35)
        d.text((10, top - 18), f'{name}: where a tap lands ({ctx}: after "{taps[ids[0]][1]}")', fill='black', font=font)
        for x in xs:
            for r, y in enumerate(ys):
                i = at.get((x, y))
                if i is None: continue
                letter = res[i] or ' '
                left = 10 + int((x - min(xs)) * 2.6)
                box = [left, top + r * ch_, left + cw - 1, top + (r + 1) * ch_ - 1]
                d.rectangle(box, fill=color(letter), outline='red' if apple[i] != vikey[i] else None, width=2)
                d.text((box[0] + 9, box[1] + 1), letter if letter.isalpha() else ('⌫' if letter == '⌫' else '·'), fill='black', font=font)
    img.save(f'{prefix}-{ctx}.png')
