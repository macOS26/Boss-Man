#!/usr/bin/env python3
"""
Extract the Marker Felt faces the title screen uses into standalone .ttf files.

macOS ships Marker Felt as a TrueType *collection* (MarkerFelt.ttc) containing two
faces — "Marker Felt Thin" and "Marker Felt Wide". SFML's sf::Font::loadFromFile
only ever loads face 0 of a .ttc, so it can't reach the Wide face. We split the
collection into individual .ttf files the game can load directly:

    assets/fonts/MarkerFelt-Thin.ttf   (prompts, leaderboard, high score)
    assets/fonts/MarkerFelt-Wide.ttf   (the big "BOSS-MAN" title)

Requirements:  pip3 install fonttools
Usage:         python3 scripts/extract_fonts.py
Output:        assets/fonts/MarkerFelt-{Thin,Wide}.ttf

Note: Marker Felt is an Apple-bundled font; only extract what your usage/licensing
permits.
"""
import os
import sys
from fontTools.ttLib import TTCollection

FONT_PATH = "/System/Library/Fonts/MarkerFelt.ttc"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts")


def main():
    if not os.path.exists(FONT_PATH):
        sys.exit(f"Marker Felt not found at {FONT_PATH} (macOS only).")
    os.makedirs(OUT_DIR, exist_ok=True)

    collection = TTCollection(FONT_PATH)
    for face in collection.fonts:
        full = face["name"].getDebugName(4) or face["name"].getDebugName(1) or ""
        variant = "Wide" if "Wide" in full else "Thin"
        out = os.path.join(OUT_DIR, f"MarkerFelt-{variant}.ttf")
        face.save(out)
        print(f"  {full!r:30} -> {out}")
    print(f"Wrote Marker Felt faces into {OUT_DIR}")


if __name__ == "__main__":
    main()
