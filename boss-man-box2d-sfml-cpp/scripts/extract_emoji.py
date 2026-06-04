#!/usr/bin/env python3
"""
Extract the specific emoji glyphs the game uses from Apple Color Emoji into PNGs.

Bundling the whole 183 MB Apple Color Emoji font is impractical (exceeds GitHub's
100 MB file limit) and SFML/FreeType can't render its `sbix` color glyphs anyway.
Instead we pull just the ~20 glyphs we use, as PNGs, which the game loads as plain
textures (sf::Texture) — small, and works on every platform with no CoreText.

Each PNG is named by the lowercase hex of the emoji's UTF-8 bytes (e.g. fish 🐟 =>
f09f909f.png), exactly matching the byte strings used in the C++ source, so
EmojiText.cpp can find a glyph by hashing the UTF-8 string it's asked to draw.

Requirements:  pip3 install fonttools
Usage:         python3 scripts/extract_emoji.py
Output:        assets/emoji/<utf8-hex>.png

Note: Apple Color Emoji artwork is Apple's; only extract what your usage/licensing
permits.
"""
import os
import sys
from fontTools.ttLib import TTCollection

FONT_PATH = "/System/Library/Fonts/Apple Color Emoji.ttc"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "emoji")

# Exact UTF-8 byte sequences as used in the C++ source
# (Constants.hpp travelers, MazeRenderer machines, HUDRenderer checklist).
EMOJIS = [
    b"\xf0\x9f\x90\x9f",              # 🐟 fish
    b"\xf0\x9f\x8d\xa9",              # 🍩 donut
    b"\xe2\x98\x95",                  # ☕ coffee
    b"\xf0\x9f\xa5\xa4",              # 🥤 soda
    b"\xf0\x9f\x8d\x8e",              # 🍎 apple
    # NOTE: ✂️ (e29c82efb88f.png) is intentionally NOT extracted — the level-6
    # traveler uses the shiny red stapler image dropped in at that filename instead.
    b"\xf0\x9f\x8d\x89",              # 🍉 melon
    b"\xf0\x9f\xa7\x87",              # 🧇 waffle
    b"\xf0\x9f\x8d\xa6",              # 🍦 ice cream
    b"\xf0\x9f\x8e\x82",              # 🎂 cake
    b"\xf0\x9f\x91\x80",              # 👀 eyes
    b"\xf0\x9f\x91\x81\xef\xb8\x8f",  # 👁️ big eye
    b"\xf0\x9f\x96\xa8\xef\xb8\x8f",  # 🖨️ printer
    b"\xf0\x9f\x93\xa0",              # 📠 fax
    b"\xf0\x9f\x93\x84",              # 📄 cover sheet
    b"\xf0\x9f\x93\x9a",              # 📚 book binder
    b"\xf0\x9f\x93\xa6",              # 📦 delivery box
    b"\xf0\x9f\x94\xab",              # 🔫 water gun
    b"\xe2\x9c\x85",                  # ✅ checked
    b"\xe2\x9d\x8c",                  # ❌ unchecked
    b"\xf0\x9f\x93\x95",              # 📕 red book   (book binder variants)
    b"\xf0\x9f\x93\x97",              # 📗 green book
    b"\xf0\x9f\x93\x98",              # 📘 blue book
    b"\xf0\x9f\x93\x99",              # 📙 orange book
    b"\xf0\x9f\x95\xb9\xef\xb8\x8f",  # 🕹️ joystick  (title PLAY button)
    b"\xe2\x9c\x8f\xef\xb8\x8f",      # ✏️ pencil     (title EDITOR button)
    b"\xf0\x9f\x93\xba",              # 📺 television (Fullscreen toggle)
    b"\xf0\x9f\xaa\x9f",              # 🪟 window     (Window toggle)
    b"\xe2\x8f\xb3",                  # ⏳ hourglass  (era/Time toggle)
    b"\xf0\x9f\x91\xbb",              # 👻 ghost      (Boss-Tracks toggle)
]


def png_for(strike, gname, depth=0):
    """Return PNG bytes for a glyph, following 'dupe' references."""
    g = strike.glyphs.get(gname)
    if g is None:
        return None
    if g.graphicType == "dupe" and depth < 4:
        ref = g.imageData.decode("utf-8", "ignore") if g.imageData else None
        return png_for(strike, ref, depth + 1) if ref else None
    if g.graphicType == "png " and g.imageData:
        return g.imageData
    return None


def main():
    if not os.path.exists(FONT_PATH):
        sys.exit(f"Apple Color Emoji not found at {FONT_PATH} (macOS only).")
    os.makedirs(OUT_DIR, exist_ok=True)

    font = TTCollection(FONT_PATH).fonts[0]  # "Apple Color Emoji"
    cmap = font.getBestCmap()
    sbix = font["sbix"]
    strike = max(sbix.strikes.values(), key=lambda s: s.ppem)  # highest resolution

    ok = 0
    for raw in EMOJIS:
        s = raw.decode("utf-8")
        cp = ord(s[0])  # base codepoint (ignores trailing variation selector)
        gname = cmap.get(cp)
        data = png_for(strike, gname) if gname else None
        fn = raw.hex() + ".png"
        if data:
            with open(os.path.join(OUT_DIR, fn), "wb") as f:
                f.write(data)
            ok += 1
            print(f"  {s}  U+{cp:04X}  -> {fn} ({len(data)} bytes)")
        else:
            print(f"  MISSING {s}  U+{cp:04X}  glyph={gname}")
    print(f"Extracted {ok}/{len(EMOJIS)} emoji at {strike.ppem}px into {OUT_DIR}")


if __name__ == "__main__":
    main()
