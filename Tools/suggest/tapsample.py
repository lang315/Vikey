#!/usr/bin/env python3
"""Touch points for AppleRefUITests.testTapMap across many contexts: where each keyboard puts a tap, beyond one
context ("I said "). Points scatter around a key's centre like real touches (a little wider, so borders get many),
on the iOS 26 iPhone layout 402 pt wide, in the AppleRef window's coordinates (rows at y 611, 665, 719; space row 773).

    tapsample.py OUT.json [--per 200] [--seed 7]
Rows: [id "cNN-i", text before the cursor, x, y]. Contexts: word starts after a word, and words half typed.
"""
import argparse
import json
import random

CONTEXTS = [
    "I said ", "Thank ", "I want to ", "Can you ", "See you ", "It was a ", "Let me ", "How are ", "We need to ",
    "I don't ", "What do you ", "Please ", "in the ", "This is ", "I think ", "Do you ", "", "Hello. ", "I love ",
    "Have a ", "Are you ", "My name is ", "I will ", "That's ",
    "th", "I want to th", "wh", "Thank yo", "It's goo", "pl", "I'm so ex", "qu", "Let me kn", "Can you he", "I lo",
    "The meet", "sch", "I'm go", "som", "abo", "Have a gre", "See you tom", "I need to ch", "We should pr", "tha",
    "becau", "Whe", "dif",
]

KW, KH, GAP, PITCH = 33.47, 43.0, 6.0, 54.0
ROW_Y = [611.0, 665.0, 719.0]
def row_keys():
    keys = {}
    for i, c in enumerate("qwertyuiop"): keys[c] = (6.67 + KW / 2 + i * (KW + GAP), ROW_Y[0], KW)
    for i, c in enumerate("asdfghjkl"): keys[c] = (26.385 + KW / 2 + i * (KW + GAP), ROW_Y[1], KW)
    for i, c in enumerate("zxcvbnm"): keys[c] = (65.86 + KW / 2 + i * (KW + GAP), ROW_Y[2], KW)
    keys["shift"] = (6.67 + 45.3 / 2, ROW_Y[2], 45.3)
    keys["delete"] = (402 - 6.67 - 45.3 / 2, ROW_Y[2], 45.3)
    keys["space"] = ((105.27 + 296.73) / 2, ROW_Y[2] + PITCH, 191.46)
    return keys

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("--per", type=int, default=200); ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    rnd = random.Random(a.seed)
    keys = row_keys()
    letters = [k for k in keys if len(k) == 1]
    rows = []
    for n, text in enumerate(CONTEXTS):
        for i in range(a.per):
            k = rnd.choice(["shift", "delete", "space"]) if rnd.random() < 0.1 else rnd.choice(letters)
            cx, cy, w = keys[k]
            x = min(max(cx + rnd.gauss(0, 0.4 * (KW if k == "space" else w)), 2), 400)
            y = min(max(cy + rnd.gauss(0, 0.35 * KH), 592), 790)
            rows.append([f"c{n:02d}-{i}", text, round(x, 1), round(y, 1)])
    json.dump(rows, open(a.out, "w"))
    print(len(rows), "points,", len(CONTEXTS), "contexts ->", a.out)

if __name__ == "__main__":
    main()
