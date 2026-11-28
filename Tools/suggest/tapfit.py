#!/usr/bin/env python3
"""Fit Vikey's English tap areas to Apple's: which key a touch types, from where it lands and how likely each letter
is next. Input: the log of iOS/Tests/TapAreaBenchTests (TAPCTXDATA: a context's keys and next-letter chances from
SuggestLM.nextLetters; TAPAREA: each point, with Apple's key and Vikey's current one).

    tapfit.py BENCH.log [--test-every 4]
Contexts c03, c07, … (every 4th) are held out: the parameters are fitted on the others and scored on these.

The model, per touch (x, y) and key k:
    score = -0.5 * (dx^2 + dy^2) + weight * log prior(k)
    dx = the distance outside the key's middle part (a wide key is a letter key stretched), in key widths / sigma_x
    dy = the distance from the row's centre, in key heights / sigma_y
    prior: letters  (1 - floor) * P(letter) + floor / 26;  space: P(the word ends) + space_floor;
           delete, shift: fixed;  other keys: never by a prior (they win only inside their own frame)
and inside the middle `sure` share of a key, that key wins outright.
"""
import argparse
import json
import math
import sys

import numpy as np

LETTERS = "abcdefghijklmnopqrstuvwxyz"

def load(path):
    ctx, pts = {}, []
    for line in open(path, encoding="utf-8"):
        if line.startswith("TAPCTXDATA\t"):
            j = json.loads(line.split("\t", 1)[1]); ctx[j["text"]] = j
        elif line.startswith("TAPAREA\t"):
            pts.append(json.loads(line.split("\t", 1)[1]))
    return ctx, pts

KEYS_USED = list(LETTERS) + [" ", "⌫", "shift"]

def features(ctx, pts):
    """Per point, per candidate key: dx (pt outside the key's middle), dy (pt from its row centre), the key's own
    frame contains the point, the key's width/height; and per point the prior inputs."""
    n, m = len(pts), len(KEYS_USED)
    DX = np.full((n, m), 1e3); DY = np.full((n, m), 1e3); INSIDE = np.zeros((n, m), bool)
    SX = np.full((n, m), 1e3); SY = np.full((n, m), 1e3); HALF = np.zeros((n, m))   # signed, in letter widths / key heights
    REL = np.full((n, m), 9.0)   # how far from the centre, as a share of the half-size (max of x, y): sure-zone test
    KW = np.ones((n, m)); KH = np.ones((n, m))
    P = np.zeros((n, 27)); OTHER = np.zeros(n, bool)
    for i, p in enumerate(pts):
        c = ctx[p["text"]]
        d = c["dist"] or [1 / 27] * 27
        P[i] = d
        letter_w = next(k["w"] for k in c["keys"] if k["k"] == "q")
        frames = {}
        for k in c["keys"]:
            name = k["k"] if k["k"] in KEYS_USED else ("shift" if k["k"] == "shift" else k["k"])
            frames[name] = k
        x, y = p["x"], p["y"]
        for j, name in enumerate(KEYS_USED):
            k = frames.get(name)
            if not k: continue
            cx, cy = k["x"] + k["w"] / 2, k["y"] + k["h"] / 2
            half_extra = max(k["w"] - letter_w, 0) / 2
            DX[i, j] = max(abs(x - cx) - half_extra, 0) / letter_w
            DY[i, j] = abs(y - cy) / k["h"]
            SX[i, j] = (x - cx) / letter_w; SY[i, j] = (y - cy) / k["h"]; HALF[i, j] = half_extra / letter_w
            KW[i, j] = k["w"]; KH[i, j] = k["h"]
            INSIDE[i, j] = k["x"] <= x <= k["x"] + k["w"] and k["y"] <= y <= k["y"] + k["h"]
            REL[i, j] = max(abs(x - cx) / (k["w"] / 2), abs(y - cy) / (k["h"] / 2))
        # a point on a key outside our set (123, return, emoji): that key, whatever the prior
        OTHER[i] = any(k["x"] <= x <= k["x"] + k["w"] and k["y"] <= y <= k["y"] + k["h"] for k in c["keys"] if k["k"] not in KEYS_USED)
    return dict(DX=DX, DY=DY, SX=SX, SY=SY, HALF=HALF, INSIDE=INSIDE, REL=REL, P=P, OTHER=OTHER)

def predict(F, prm):
    sx, sy, w, floor, sfloor, pdel, pshift, sure = (prm[k] for k in ("sx", "sy", "w", "floor", "sfloor", "pdel", "pshift", "sure"))
    P = F["P"]
    prior = np.empty((P.shape[0], len(KEYS_USED)))
    prior[:, :26] = (1 - floor) * P[:, :26] + floor / 26
    prior[:, 26] = P[:, 26] + sfloor
    prior[:, 27] = pdel
    prior[:, 28] = pshift
    ox, oy = prm.get("ox", 0), prm.get("oy", 0)
    dx = np.maximum(np.abs(F["SX"] + ox) - F["HALF"], 0); dy = F["SY"] + oy
    score = -0.5 * ((dx / sx) ** 2 + (dy / sy) ** 2) + w * np.log(prior)
    pick = score.argmax(1)
    if sure > 0:   # inside the middle of a key: that key
        inner = F["REL"] <= sure
        has = inner.any(1)
        pick = np.where(has, inner.argmax(1), pick)
    names = np.array(KEYS_USED + ["?"])
    out = names[pick].astype(object)
    out[F["OTHER"]] = "?"
    return out

def label(a):
    return a if a in KEYS_USED else ("shift" if a == "" else "?")

def agreement(pred, gold, mask):
    return float((pred[mask] == gold[mask]).mean()) if mask.any() else float("nan")

GRID = {
    "sx": [0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.6],
    "sy": [0.2, 0.25, 0.3, 0.35, 0.4, 0.5],
    "w": [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0],
    "floor": [0.001, 0.003, 0.01, 0.03, 0.1, 0.3],
    "sfloor": [0.001, 0.01, 0.03, 0.1, 0.3, 1.0],
    "pdel": [0.001, 0.003, 0.01, 0.03, 0.1, 0.3],
    "pshift": [0.001, 0.003, 0.01, 0.03, 0.1, 0.3],
    "sure": [0, 0.3, 0.5, 0.6, 0.7, 0.8],
    "ox": [-0.2, -0.15, -0.1, -0.05, 0, 0.05, 0.1, 0.15, 0.2],
    "oy": [-0.2, -0.15, -0.1, -0.05, 0, 0.05, 0.1, 0.15, 0.2],
}

def fit(F, gold, mask, start):
    prm = dict(start)
    best = agreement(predict(F, prm), gold, mask)
    for _ in range(4):
        changed = False
        for k, vals in GRID.items():
            for v in vals:
                t = dict(prm); t[k] = v
                a = agreement(predict(F, t), gold, mask)
                if a > best + 1e-9: best, prm, changed = a, t, True
        if not changed: break
    return prm, best

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log"); ap.add_argument("--test-every", type=int, default=4)
    a = ap.parse_args()
    ctx, pts = load(a.log)
    F = features(ctx, pts)
    gold = np.array([label(p["apple"]) for p in pts], dtype=object)
    now = np.array([label(p["vikey"]) for p in pts], dtype=object)
    texts = list(dict.fromkeys(p["text"] for p in pts))   # the contexts in their order
    cid = np.array([texts.index(p["text"]) for p in pts])
    test = cid % a.test_every == a.test_every - 1
    train = ~test
    print(f"{len(pts)} points, {len(ctx)} contexts; train {train.sum()}, test {test.sum()}")
    print(f"Vikey now:      train {100 * agreement(now, gold, train):.1f}%  test {100 * agreement(now, gold, test):.1f}%")
    start = dict(sx=0.35, sy=0.25, w=0.5, floor=0.03, sfloor=0.03, pdel=0.01, pshift=0.01, sure=0, ox=0, oy=0)
    geo = dict(start, w=0)
    print(f"keys only:      train {100 * agreement(predict(F, geo), gold, train):.1f}%  test {100 * agreement(predict(F, geo), gold, test):.1f}%")
    prm, tr = fit(F, gold, train, start)
    te = agreement(predict(F, prm), gold, test)
    print(f"fitted:         train {100 * tr:.1f}%  test {100 * te:.1f}%   {json.dumps(prm)}")
    pred = predict(F, prm)
    from collections import Counter
    print("test disagreements (apple, model):", Counter((g, p) for g, p, m in zip(gold, pred, test) if m and g != p).most_common(12))
    json.dump(prm, open(a.log + ".fit.json", "w"))



# ---- a learned model: per-key biases + the language model, fitted by maximum likelihood (softmax over keys) ----

def learn(F, gold, train, floor=0.01, sfloor=0.03, epochs=400, use_lm=True):
    import torch
    keys = KEYS_USED
    idx = {k: i for i, k in enumerate(keys)}
    ok = np.array([g in idx for g in gold]) & train & ~F["OTHER"]
    y = torch.tensor([idx[g] for g in gold[ok]])
    P = F["P"][ok]
    lp = np.zeros((ok.sum(), len(keys)))
    lp[:, :26] = np.log((1 - floor) * P[:, :26] + floor / 26)
    lp[:, 26] = np.log(P[:, 26] + sfloor)
    DX2 = torch.tensor(F["DX"][ok] ** 2); DY2 = torch.tensor(F["DY"][ok] ** 2); LP = torch.tensor(lp)
    lm_mask = torch.tensor([1.0] * 27 + [0.0, 0.0], dtype=torch.float64)
    a = torch.tensor(4.0, dtype=torch.float64, requires_grad=True)     # 1 / sigma_x^2
    b = torch.tensor(8.0, dtype=torch.float64, requires_grad=True)     # 1 / sigma_y^2
    w = torch.tensor(0.3 if use_lm else 0.0, dtype=torch.float64, requires_grad=use_lm)   # the language model's weight
    bias = torch.zeros(len(keys), dtype=torch.float64, requires_grad=True)
    opt = torch.optim.Adam([a, b, bias] + ([w] if use_lm else []), lr=0.05)
    for _ in range(epochs):
        opt.zero_grad()
        s = -0.5 * (a * DX2 + b * DY2) + w * LP * lm_mask + bias
        loss = torch.nn.functional.cross_entropy(s, y) + 1e-3 * (bias ** 2).sum()
        loss.backward()
        opt.step()
    return dict(a=a.item(), b=b.item(), w=w.item(), bias=bias.detach().numpy().tolist(), floor=floor, sfloor=sfloor)

def predict_learned(F, m):
    P = F["P"]
    lp = np.zeros((P.shape[0], len(KEYS_USED)))
    lp[:, :26] = np.log((1 - m["floor"]) * P[:, :26] + m["floor"] / 26)
    lp[:, 26] = np.log(P[:, 26] + m["sfloor"])
    s = -0.5 * (m["a"] * F["DX"] ** 2 + m["b"] * F["DY"] ** 2) + m["w"] * lp + np.array(m["bias"])
    out = np.array(KEYS_USED, dtype=object)[s.argmax(1)]
    out[F["OTHER"]] = "?"
    return out

def main_learned():
    ap = argparse.ArgumentParser()
    ap.add_argument("log"); ap.add_argument("--test-every", type=int, default=4)
    a = ap.parse_args(sys.argv[2:])
    ctx, pts = load(a.log)
    F = features(ctx, pts)
    gold = np.array([label(p["apple"]) for p in pts], dtype=object)
    texts = list(dict.fromkeys(p["text"] for p in pts))
    cid = np.array([texts.index(p["text"]) for p in pts])
    test = cid % a.test_every == a.test_every - 1
    for floor in (0.001, 0.01, 0.05):
        for use_lm in (True, False):
            m = learn(F, gold, ~test, floor=floor)
            if not use_lm:
                m = learn_no_lm(F, gold, ~test)
            pr = predict_learned(F, m)
            print(f"learned floor={floor} lm={use_lm}: train {100 * agreement(pr, gold, ~test):.1f}%  test {100 * agreement(pr, gold, test):.1f}%  "
                  f"sx={1 / math.sqrt(max(m['a'], 1e-6)):.2f} sy={1 / math.sqrt(max(m['b'], 1e-6)):.2f} w={m['w']:.2f}")
            if not use_lm: break

def learn_no_lm(F, gold, train):
    return learn(F, gold, train, use_lm=False)   # w stays 0 while fitting: the biases carry the rest


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "learn": main_learned()
    else: main()
