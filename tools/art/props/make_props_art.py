"""Generates the template art for the hybrid props (assets/graphics/props/).

Run from the project root:  python3 tools/art/props/make_props_art.py

Forked from tools/art/modular/make_modular.py (Experiment 001, Version B):
fabric, wood_grain, concrete and asphalt use the same algorithms and seeds,
so they reproduce B's textures. rough_wood is new (weathered, scavenged
planks for barricades, crates, plank doors and the rain collector frame).

Every texture tiles seamlessly. RGB is the colour (light and near-neutral
where the props tint it per piece); ALPHA is a height map (white = raised)
that the props shader turns into a gentle bump. A user override without
alpha simply renders flat. Users override any of them with
custom/graphics/props/<name>.png (see docs/experiment-002/props.md).
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets" / "graphics" / "props"


# --- tileable noise (forked) -------------------------------------------------------

def value_noise(size, cells, seed, aspect=(1, 1)):
    """Periodic value noise in [0, 1]. `cells` grid cells across the tile."""
    rng = np.random.default_rng(seed)
    cx, cy = cells * aspect[0], cells * aspect[1]
    grid = rng.random((cy, cx))
    ys = np.arange(size) * cy / size
    xs = np.arange(size) * cx / size
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % cy
    x1 = (x0 + 1) % cx
    a = grid[np.ix_(y0, x0)]
    b = grid[np.ix_(y0, x1)]
    c = grid[np.ix_(y1, x0)]
    d = grid[np.ix_(y1, x1)]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(size, cells, octaves, seed, aspect=(1, 1), gain=0.5):
    out = np.zeros((size, size))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        out += amp * value_noise(size, cells * (2 ** o), seed + o * 17, aspect)
        total += amp
        amp *= gain
    return out / total


def lerp(a, b, t):
    return a + (b - a) * t


def rgb(c):
    return np.array(c, dtype=float) / 255.0


def save(name, color, height=None):
    """color: HxWx3 floats 0..1, height: HxW floats 0..1 (alpha)."""
    c = np.clip(color, 0, 1)
    if height is None:
        img = Image.fromarray((c * 255).astype(np.uint8), "RGB")
    else:
        h = np.clip(height, 0, 1)
        arr = np.dstack([c, h[..., None]])
        img = Image.fromarray((arr * 255).astype(np.uint8), "RGBA")
    img.save(OUT / f"template_{name}.png")
    print("  template_%s.png" % name)


def tint(base, amount):
    """base rgb (3,), amount HxW in about -1..1 -> brightness modulation"""
    return base[None, None, :] * (1.0 + amount[..., None])


def grain(size, seed, along="y", stretch=24):
    """Streaky wood grain, 0..1, streaks along the given axis."""
    if along == "y":
        n = fbm(size, 4, 4, seed, aspect=(stretch, 1))
    else:
        n = fbm(size, 4, 4, seed, aspect=(1, stretch))
    rings = np.sin(n * 40.0) * 0.5 + 0.5
    return 0.6 * n + 0.4 * rings


def _crack_lines(size, seed, count, steps, step_len, width, turn, along_x=False):
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(seed)
    for _ in range(count):
        p = np.array([rng.uniform(0, size), rng.uniform(0, size)])
        ang = rng.normal(0, 0.08) if along_x else rng.uniform(0, np.pi * 2)
        for _ in range(steps):
            ang += rng.normal(0, turn)
            if along_x:
                ang = float(np.clip(ang, -0.25, 0.25))
            q = p + np.array([np.cos(ang), np.sin(ang)]) * rng.uniform(*step_len)
            # draw wrapped copies so the tile stays seamless
            for ox in (-size, 0, size):
                for oy in (-size, 0, size):
                    d.line([(p[0] + ox, p[1] + oy), (q[0] + ox, q[1] + oy)], fill=255, width=width)
            p = q
    return img


# --- textures forked from Version B -----------------------------------------------------

def concrete(size=512):
    """Poured concrete, 2.5 m tile: mottled, aggregate speckle, a hairline crack."""
    m1 = fbm(size, 4, 5, 81)
    m2 = fbm(size, 24, 3, 82)
    spk = (fbm(size, 90, 1, 83) > 0.78).astype(float)
    base = rgb((150, 148, 142))
    amt = (m1 - 0.5) * 0.22 + (m2 - 0.5) * 0.08 - spk * 0.06
    col = tint(base, amt)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(84)
    for _ in range(2):
        p = np.array([rng.uniform(0, size), rng.uniform(0, size)])
        ang = rng.uniform(0, np.pi)
        for _ in range(26):
            ang += rng.normal(0, 0.35)
            q = p + np.array([np.cos(ang), np.sin(ang)]) * rng.uniform(8, 18)
            d.line([tuple(p), tuple(q)], fill=255, width=1)
            p = q
    crack = np.asarray(img.filter(ImageFilter.GaussianBlur(0.6)), float) / 255.0
    col *= (1 - 0.35 * crack)[..., None]
    height = 0.6 + (m2 - 0.5) * 0.5 - crack * 0.5 - spk * 0.2
    save("concrete", col, height)


def asphalt(size=512):
    """Old asphalt, 4 m tile: aggregate, patching, cracks."""
    m1 = fbm(size, 4, 5, 111)
    spk = fbm(size, 120, 1, 112)
    base = rgb((58, 58, 60))
    amt = (m1 - 0.5) * 0.25 + (spk - 0.5) * 0.35
    col = tint(base, amt)
    patch = np.clip((fbm(size, 3, 3, 113) - 0.62) * 6, 0, 1)
    col = lerp(col, col * 0.75, patch[..., None])
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(114)
    for _ in range(5):
        p = np.array([rng.uniform(0, size), rng.uniform(0, size)])
        ang = rng.uniform(0, np.pi * 2)
        for _ in range(20):
            ang += rng.normal(0, 0.5)
            q = p + np.array([np.cos(ang), np.sin(ang)]) * rng.uniform(6, 14)
            d.line([tuple(p), tuple(q)], fill=255, width=2)
            p = q
    crack = np.asarray(img.filter(ImageFilter.GaussianBlur(0.8)), float) / 255.0
    col *= (1 - 0.5 * crack)[..., None]
    height = 0.55 + (spk - 0.5) * 0.6 - crack * 0.5
    save("asphalt", col, height)


def fabric(size=256):
    """Woven upholstery (near-white; furniture tints it), 0.5 m tile."""
    y, x = np.mgrid[0:size, 0:size].astype(float)
    period = size / 64
    wx = np.sin(x / period * np.pi * 2) * 0.5 + 0.5
    wy = np.sin(y / period * np.pi * 2) * 0.5 + 0.5
    checker = (np.floor(x / period) + np.floor(y / period)) % 2
    weave = np.where(checker > 0, wx, wy)
    slub = fbm(size, 10, 3, 121, aspect=(1, 4))
    mott = fbm(size, 3, 3, 122)
    v = 0.86 + (weave - 0.5) * 0.12 + (slub - 0.5) * 0.1 + (mott - 0.5) * 0.08
    col = np.dstack([v, v, v])
    height = 0.3 + weave * 0.7
    save("fabric", col, height)


def wood_grain(size=256):
    """Furniture wood grain (light; tinted per piece), 1 m tile, grain along x."""
    g = grain(size, 131, "x", 20)
    mott = fbm(size, 3, 3, 132)
    v = 0.84 + (g - 0.5) * 0.22 + (mott - 0.5) * 0.06
    col = np.dstack([v * 1.02, v, v * 0.96])
    save("wood_grain", col, 0.5 + (g - 0.5) * 0.6)


# --- new for the props ----------------------------------------------------------------------

def rough_wood(size=256):
    """Weathered, scavenged board: coarse grain along x, knots, drying checks,
    saw marks and grey weathering. 1 m tile, light and near-neutral (tinted)."""
    g = grain(size, 141, "x", 14)
    coarse = fbm(size, 3, 4, 142, aspect=(1, 6))
    weather = fbm(size, 5, 4, 143)
    y, x = np.mgrid[0:size, 0:size].astype(float)
    # circular saw marks: faint arcs across the grain
    saw = np.sin((x + 0.0008 * (y - size / 2) ** 2) / size * np.pi * 2 * 22) * 0.5 + 0.5
    v = 0.8 + (g - 0.5) * 0.34 + (coarse - 0.5) * 0.12 + (saw - 0.5) * 0.04
    # knots: dark ovals with rings, wrapped
    rng = np.random.default_rng(144)
    knot = np.zeros((size, size))
    for _ in range(3):
        kx, ky = rng.uniform(0, size), rng.uniform(0, size)
        rx, ry = rng.uniform(7, 12), rng.uniform(4, 7)
        dx = np.minimum(np.abs(x - kx), size - np.abs(x - kx)) / rx
        dy = np.minimum(np.abs(y - ky), size - np.abs(y - ky)) / ry
        r = np.sqrt(dx * dx + dy * dy)
        knot = np.maximum(knot, np.clip(1.4 - r, 0, 1) * (0.6 + 0.4 * np.sin(r * 9.0)))
    v -= knot * 0.3
    # drying checks (cracks) running along the grain
    checks = _crack_lines(size, 145, 7, 9, (6, 16), 1, 0.12, along_x=True)
    crack = np.asarray(checks.filter(ImageFilter.GaussianBlur(0.5)), float) / 255.0
    v -= crack * 0.38
    col = np.dstack([v * 1.03, v * 1.0, v * 0.95])
    # silver-grey weathering in patches (keeps the tint from looking new)
    grey = np.clip((weather - 0.45) * 2.2, 0, 1)[..., None]
    col = lerp(col, np.dstack([v, v, v]) * 0.92 + 0.04, grey * 0.6)
    height = 0.55 + (g - 0.5) * 0.5 + (coarse - 0.5) * 0.2 - crack * 0.6 - knot * 0.15
    save("rough_wood", col, height)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    print("props template art ->", OUT)
    fabric()
    wood_grain()
    concrete()
    asphalt()
    rough_wood()


if __name__ == "__main__":
    main()
