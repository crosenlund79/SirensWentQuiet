"""Generates the shared template art (assets/graphics/common/).

Run: python3 tools/art/make_common.py
Outputs are Claude-made template_ fallbacks; user overrides go in
custom/graphics/common/<name>.png (see assets/README.md).
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "graphics" / "common"


def crosshair(size=32, ss=8):
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    r = 8.5 * ss
    # dark outline ring, then light ring on top
    for width, colour in ((int(3.6 * ss), (10, 8, 8, 200)), (int(1.5 * ss), (245, 238, 226, 255))):
        d.ellipse((c - r, c - r, c + r, c + r), outline=colour, width=width)
    # cut gaps at the compass points
    g = 2.2 * ss
    for box in ((c - g, 0, c + g, s), (0, c - g, s, c + g)):
        mask = Image.new("L", (s, s), 0)
        ImageDraw.Draw(mask).rectangle(box, fill=255)
        img.paste((0, 0, 0, 0), (0, 0), mask)
    # centre dot
    d.ellipse((c - 2.6 * ss, c - 2.6 * ss, c + 2.6 * ss, c + 2.6 * ss), fill=(10, 8, 8, 200))
    d.ellipse((c - 1.4 * ss, c - 1.4 * ss, c + 1.4 * ss, c + 1.4 * ss), fill=(245, 238, 226, 255))
    img = img.resize((size, size), Image.LANCZOS)
    img.save(OUT / "template_crosshair.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    crosshair()
    print("wrote", OUT)
