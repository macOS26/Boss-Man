#!/usr/bin/env python3
"""Quantify boss-vs-Pete billboard scale in the 3D modes from captured frames.

Scans tests/headless/out/frames-* screenshots, color-masks boss shirts
(Bill red, Milt pink, Stan orange; teal Bobs is skipped, walls are teal-ish) inside the play region, measures
the tallest shirt blob per frame, and compares it with Pete's shirt height
(Pete renders at a fixed screen size, so his median height is the reference).
Same sprite proportions on every PixelPerson means shirt-height ratio equals
body-height ratio.

Usage: python3 measure-boss.py out/frames-ray
"""
import sys
import json
from pathlib import Path
from PIL import Image

PLAY = (30, 140, 1210, 500)          # x0, y0, x1, y1: excludes HUD strip + minimap
PETE_WIN = (520, 280, 720, 505)      # Pete's fixed over-shoulder spot


def classify(r, g, b):
    if r >= 160 and g <= 85 and b <= 85:
        return 'red'
    if r >= 210 and 115 <= g <= 190 and 150 <= b <= 215:
        return 'pink'
    if r >= 200 and 105 <= g <= 178 and b <= 80:
        return 'orange'
    return None


def is_pete_blue(r, g, b):
    return r <= 90 and 110 <= g <= 185 and b >= 215


def blob_height(coords):
    """Largest contiguous y-run height among the given pixel coords."""
    if not coords:
        return 0, None
    xs = sorted(set(x for x, _ in coords))
    best_x = max(xs, key=lambda x: sum(1 for cx, _ in coords if abs(cx - x) <= 6)) if xs else None
    col = sorted(y for x, y in coords if best_x is not None and abs(x - best_x) <= 6)
    if not col:
        return 0, None
    runs, start, prev = [], col[0], col[0]
    for y in col[1:]:
        if y - prev > 4:
            runs.append((start, prev))
            start = y
        prev = y
    runs.append((start, prev))
    y0, y1 = max(runs, key=lambda r: r[1] - r[0])
    return y1 - y0 + 1, (best_x, y0, y1)


def main(frames_dir):
    frames = sorted(Path(frames_dir).glob('f*.png'))
    pete_heights, sightings = [], []
    for f in frames:
        im = Image.open(f).convert('RGB')
        px = im.load()
        boss_px = {}
        for y in range(PLAY[1], PLAY[3], 2):
            for x in range(PLAY[0], PLAY[2], 2):
                c = classify(*px[x, y])
                if c:
                    boss_px.setdefault(c, []).append((x, y))
        pete = [(x, y) for y in range(PETE_WIN[1], PETE_WIN[3], 2)
                for x in range(PETE_WIN[0], PETE_WIN[2], 2) if is_pete_blue(*px[x, y])]
        ph, _ = blob_height(pete)
        if ph > 30:
            pete_heights.append(ph)
        for color, coords in boss_px.items():
            if len(coords) < 12:
                continue
            h, box = blob_height(coords)
            if h >= 8:
                sightings.append({'frame': f.name, 'boss': color, 'shirt_h': h, 'box': box})

    pete_med = sorted(pete_heights)[len(pete_heights) // 2] if pete_heights else 0
    sightings.sort(key=lambda s: -s['shirt_h'])
    print(f"frames: {len(frames)}  pete shirt height (median): {pete_med}px")
    print("closest boss sightings (largest first):")
    for s in sightings[:12]:
        ratio = s['shirt_h'] / pete_med if pete_med else 0
        print(f"  {s['frame']}  {s['boss']:6s} shirt={s['shirt_h']:3d}px  boss/pete={ratio:.2f}  at {s['box']}")
    out = {'pete_median_shirt_h': pete_med, 'sightings': sightings[:40]}
    Path(frames_dir, 'measure-report.json').write_text(json.dumps(out, indent=2))


if __name__ == '__main__':
    main(sys.argv[1])
