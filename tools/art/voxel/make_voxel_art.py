"""Generates Version A (voxel) template art: assets/graphics/voxel/template_*.png

Run: python3 tools/art/voxel/make_voxel_art.py

Most images are *voxel swatches*: one pixel = the colour of one 0.1 m voxel
face. Floors and wall boards are tiled across the house; rugs are stretched to
their rug. A creator overrides any of them with custom/graphics/voxel/<name>.png
(any size; pixel art works best). The palette is a grid of 8x8 swatches; the
game samples the centre of each swatch (layout in docs/experiment-001/voxel.md).
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets" / "graphics" / "voxel"
RNG = np.random.default_rng(1979)


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def save(name, arr):
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    mode = "RGBA" if arr.shape[2] == 4 else "RGB"
    Image.fromarray(arr, mode).save(OUT / f"template_{name}.png")


def value_noise(h, w, cell, rng):
    """Smooth tileable value noise in [0, 1]."""
    gh, gw = max(1, h // cell), max(1, w // cell)
    g = rng.random((gh, gw))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = np.floor(ys).astype(int) % gh
    x0 = np.floor(xs).astype(int) % gw
    y1 = (y0 + 1) % gh
    x1 = (x0 + 1) % gw
    fy = ys - np.floor(ys)
    fx = xs - np.floor(xs)
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]
    b = g[y0][:, x1]
    c = g[y1][:, x0]
    d = g[y1][:, x1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(h, w, cell, rng, octaves=3):
    v = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        v += amp * value_noise(h, w, max(1, cell >> o), rng)
        tot += amp
        amp *= 0.5
    return v / tot


def planks(h, w, base, plank_w=2, min_len=8, max_len=18, tone=0.09, grain=0.05, rng=RNG):
    """Floor boards running along x (image columns), plank_w pixels wide."""
    img = np.zeros((h, w, 3))
    base = hexrgb(base)
    for row0 in range(0, h, plank_w):
        x = -int(rng.integers(0, max_len))
        while x < w:
            ln = int(rng.integers(min_len, max_len + 1))
            t = 1.0 + rng.normal(0, tone)
            warm = rng.normal(0, 0.03)
            col = base * t * np.array([1 + warm, 1.0, 1 - warm])
            for xx in range(max(0, x), min(w, x + ln)):
                for yy in range(row0, min(h, row0 + plank_w)):
                    g = 1.0 + rng.normal(0, grain)
                    # darker plank ends read as joints
                    if xx == x + ln - 1:
                        g *= 0.86
                    img[yy, xx] = col * g
            x += ln
    return img


def tiles(h, w, a, b, size=3, tone=0.03, rng=RNG):
    img = np.zeros((h, w, 3))
    a, b = hexrgb(a), hexrgb(b)
    for ty in range(0, h, size):
        for tx in range(0, w, size):
            c = a if ((tx // size + ty // size) % 2 == 0) else b
            c = c * (1 + rng.normal(0, tone))
            img[ty:ty + size, tx:tx + size] = c
            # tiny bevel: lighter top-left voxel, darker bottom-right voxel
            img[ty, tx] = c * 1.04
            img[min(h - 1, ty + size - 1), min(w - 1, tx + size - 1)] = c * 0.94
    return img


def floor_concrete(h=64, w=64):
    base = hexrgb("#8a8780")
    n = fbm(h, w, 16, RNG, 4)
    fine = RNG.normal(0, 0.035, (h, w))
    img = base[None, None, :] * (0.86 + 0.26 * n + fine)[:, :, None]
    # a couple of dark oil stains
    yy, xx = np.mgrid[0:h, 0:w]
    for cx, cy, r in ((18, 40, 7), (47, 15, 5)):
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
        img *= (1 - 0.22 * np.clip(1 - d, 0, 1))[:, :, None]
    # saw-cut joint lines every 32 voxels
    img[::32, :] *= 0.85
    img[:, ::32] *= 0.85
    return img


def siding(h=26, w=96):
    """Painted lap boards, 2 voxels tall: upper voxel = board face, lower = shadow lip."""
    base = hexrgb("#55646b")
    img = np.zeros((h, w, 3))
    for b in range(0, h, 2):
        x = -int(RNG.integers(0, 40))
        while x < w:
            ln = int(RNG.integers(30, 64))
            t = 1.0 + RNG.normal(0, 0.035)
            for xx in range(max(0, x), min(w, x + ln)):
                weather = 1.0 + RNG.normal(0, 0.018)
                face = base * t * weather
                # image row 0 = top of the wall
                r_face = h - 1 - (b + 1)
                r_lip = h - 1 - b
                if 0 <= r_face < h:
                    img[r_face, xx] = face * 1.03
                img[r_lip, xx] = face * 0.8
                if xx == x + ln - 1:
                    img[max(0, r_face):r_lip + 1, xx] *= 0.9
            x += ln
    # faint grime streaks running down from the top
    streak = fbm(1, w, 6, RNG, 2)[0]
    fade = np.linspace(0.0, 1.0, h)[:, None]
    img *= (1 - 0.08 * (streak[None, :] > 0.6) * (1 - fade))[:, :, None]
    return img


def insulation(h=32, w=32):
    a, b = hexrgb("#e3897a"), hexrgb("#ebb56f")
    n = fbm(h, w, 8, RNG, 3)
    fine = RNG.random((h, w))
    t = np.clip(n * 1.3 - 0.15, 0, 1)
    img = a[None, None, :] * (1 - t[:, :, None]) + b[None, None, :] * t[:, :, None]
    return img * (0.88 + 0.2 * fine)[:, :, None]


def rug(h, w, field, border, accent, pattern):
    img = np.zeros((h, w, 3))
    f, bo, ac = hexrgb(field), hexrgb(border), hexrgb(accent)
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    img[:] = f
    if pattern == "diamond":
        cx, cy = (w - 1) / 2, (h - 1) / 2
        d = np.abs(xx - cx) / (w * 0.5) + np.abs(yy - cy) / (h * 0.5)
        img[(d > 0.45) & (d < 0.58)] = ac
        img[d < 0.18] = ac
        img[(d > 0.72) & (d < 0.78)] = bo
    elif pattern == "stripes":
        img[(xx // 2) % 4 == 0] = ac
    elif pattern == "bands":
        img[(yy % 4) == 1] = ac
    img[edge < 2] = bo
    img[edge == 0] = bo * 0.85
    wear = fbm(h, w, 6, RNG, 2)
    img *= (0.9 + 0.16 * wear + RNG.normal(0, 0.025, (h, w)))[:, :, None]
    return img


def ground(h=128, w=128):
    """Dead autumn lawn: straw, faded green, bare dirt patches."""
    straw, green, dirt = hexrgb("#7f7651"), hexrgb("#5a6241"), hexrgb("#5d4d3c")
    n1 = fbm(h, w, 32, RNG, 4)
    n2 = fbm(h, w, 16, RNG, 3)
    t = np.clip((n1 - 0.35) * 2.2, 0, 1)
    img = green[None, None, :] * (1 - t[:, :, None]) + straw[None, None, :] * t[:, :, None]
    bare = np.clip((n2 - 0.62) * 5, 0, 1)
    img = img * (1 - bare[:, :, None]) + dirt[None, None, :] * bare[:, :, None]
    img *= (0.84 + 0.3 * RNG.random((h, w)))[:, :, None]
    return img


def paving(h=40, w=40):
    """Concrete slabs, 10 x 10 voxels, with dark joints."""
    base = hexrgb("#7d7a74")
    img = np.zeros((h, w, 3))
    for ty in range(0, h, 10):
        for tx in range(0, w, 10):
            img[ty:ty + 10, tx:tx + 10] = base * (1 + RNG.normal(0, 0.04))
    img *= (0.92 + 0.14 * RNG.random((h, w)))[:, :, None]
    img[::10, :] *= 0.72
    img[:, ::10] *= 0.72
    return img


def asphalt(h=64, w=64):
    base = hexrgb("#3b3b3d")
    n = fbm(h, w, 16, RNG, 3)
    img = base[None, None, :] * (0.85 + 0.25 * n + RNG.normal(0, 0.05, (h, w)))[:, :, None]
    return img


def roof(h=64, w=64):
    """Ballast gravel on a flat roof."""
    a, b = hexrgb("#55534f"), hexrgb("#6c6964")
    n = fbm(h, w, 8, RNG, 3)
    t = np.clip(n, 0, 1)
    img = a[None, None, :] * (1 - t[:, :, None]) + b[None, None, :] * t[:, :, None]
    img *= (0.8 + 0.35 * RNG.random((h, w)))[:, :, None]
    return img


PALETTE = [
    # row 0: exterior
    "#b89f7c", "#2b2d30", "#222427", "#6d6a66", "#1e1c1b", "#6b4a33", "#3a3b3d", "#2a2b2d",
    # row 1: room paints, gypsum, interior trim
    "#8e9a86", "#b9c4c4", "#cfc7b8", "#a89f92", "#8d9091", "#d9d4c8", "#e3ddd2", "#d8d1c4",
    # row 2: structure, glass, tiles
    "#b48f5e", "#8a857c", "#6a6660", "#8fb0b8", "#dfe3e0", "#7f9690", "#b9a690", "#2e3033",
    # row 3: furniture accents
    "#4e5b63", "#8a4b34", "#b89a96", "#6f7f6d", "#c2a274", "#5b3f2c", "#c9ab80", "#2c2e31",
]


def palette():
    img = np.zeros((32, 64, 3))
    for i, h in enumerate(PALETTE):
        r, c = divmod(i, 8)
        img[r * 8:(r + 1) * 8, c * 8:(c + 1) * 8] = hexrgb(h)
    return img


def dust(size=64):
    yy, xx = np.mgrid[0:size, 0:size]
    c = (size - 1) / 2
    d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / c
    n = fbm(size, size, 8, RNG, 3)
    a = np.clip(1 - d, 0, 1) ** 1.6 * (0.55 + 0.6 * n)
    a = np.clip(a * 1.25, 0, 1)
    img = np.zeros((size, size, 4))
    img[:, :, :3] = 255
    img[:, :, 3] = a * 255
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    save("palette", palette())
    save("floor_wood", planks(48, 64, "#8b6748"))
    save("floor_wood_light", planks(48, 64, "#b59a76", tone=0.07))
    save("floor_tile", tiles(36, 36, "#c9cfcc", "#b7c0bf"))
    save("floor_kitchen", tiles(36, 36, "#c4b59c", "#8c5a43", tone=0.04))
    save("floor_concrete", floor_concrete())
    save("siding", siding())
    save("insulation", insulation())
    save("rug_living", rug(29, 34, "#7d4f3d", "#2f3438", "#c2a06a", "diamond"))
    save("rug_bed", rug(11, 22, "#a7a294", "#5d6a70", "#6f7d82", "stripes"))
    save("rug_bath", rug(8, 5, "#6d8a8c", "#4f6668", "#8fa9aa", "bands"))
    save("ground", ground())
    save("paving", paving())
    save("asphalt", asphalt())
    save("roof", roof())
    save("dust", dust())
    print("wrote", OUT)


if __name__ == "__main__":
    main()
