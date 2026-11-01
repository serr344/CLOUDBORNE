"""Turns the intro source pictures (art_src/intro/panel_01..09.png) into the game's panels
(assets/images/intro/panel_01..09.png).

The sources are AI-made "pixel art": each art pixel is a soft block a few real pixels wide that
does not sit on a clean grid, so plain resizing blurs it. Instead every panel is cropped a little
(the sources have a thin dark edge) and reduced to 256x142, about twice its art-pixel grid, so
faces and hands survive: colours are first snapped to a small palette, then each output pixel
takes the most common colour of its block. The game shows the result 1:1.
Run from the repo root:  python tools/art/cut_intro.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art_src" / "intro"
OUT = ROOT / "assets" / "images" / "intro"
SIZE = (256, 142)
COLOURS = 32
EDGE = 4  # pixels trimmed from every side of a source picture


def snap(src, size):
    """Most common palette index inside each output pixel's block (middle 80% of it)."""
    sw, sh = src.size
    w, h = size
    px = src.load()
    out = []
    for y in range(h):
        for x in range(w):
            x0, x1 = sw * x / w, sw * (x + 1) / w
            y0, y1 = sh * y / h, sh * (y + 1) / h
            mx, my = (x1 - x0) * 0.1, (y1 - y0) * 0.1
            counts = {}
            for yy in range(int(y0 + my), max(int(y0 + my) + 1, int(y1 - my))):
                for xx in range(int(x0 + mx), max(int(x0 + mx) + 1, int(x1 - mx))):
                    i = px[min(xx, sw - 1), min(yy, sh - 1)]
                    counts[i] = counts.get(i, 0) + 1
            out.append(max(counts, key=counts.get))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for path in sorted(SRC.glob("panel_*.png")):
        img = Image.open(path).convert("RGB")
        w, h = img.size
        src = img.crop((EDGE, EDGE, w - EDGE, h - EDGE))
        src = src.quantize(COLOURS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        panel = Image.new("P", SIZE)
        panel.putpalette(src.getpalette())
        panel.putdata(snap(src, SIZE))
        panel.convert("RGB").save(OUT / path.name)
        print(path.name, img.size, "->", SIZE)


if __name__ == "__main__":
    main()
