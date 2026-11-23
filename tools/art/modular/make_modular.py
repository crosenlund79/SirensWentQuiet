"""Generates the template art for Version B (assets/graphics/modular/).

Run from the project root:  python3 tools/art/modular/make_modular.py

Every texture tiles seamlessly. RGB is the painted colour; the ALPHA channel
of the surface textures is a height map (white = raised) that the kit shader
turns into a gentle bump, so grooves, grout and plank seams catch the light.
A user override without alpha simply renders flat.

Outputs are Claude-made template_ fallbacks. Users override them with
custom/graphics/modular/<name>.png (see assets/README.md and
docs/experiment-001/modular.md for the logical names).
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets" / "graphics" / "modular"
RNG = np.random.default_rng(1979)


# --- tileable noise -------------------------------------------------------------

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


# --- wood helpers ------------------------------------------------------------------

def grain(size, seed, along="y", stretch=24):
    """Streaky wood grain, 0..1, streaks along the given axis."""
    aspect = (1, stretch) if along == "x" else (stretch, 1)
    # value_noise aspect multiplies cells per axis; streaks = many cells across, few along
    if along == "y":
        n = fbm(size, 4, 4, seed, aspect=(stretch, 1))
    else:
        n = fbm(size, 4, 4, seed, aspect=(1, stretch))
    rings = np.sin(n * 40.0) * 0.5 + 0.5
    return 0.6 * n + 0.4 * rings


# --- textures ------------------------------------------------------------------------

def siding(size=512):
    """Exterior: vertical tongue-and-groove boards, 2 m tile, 14 boards.
    Pale blue-grey paint over wood, brushed, slightly weathered."""
    x = np.arange(size)
    boards = 14
    bw = size / boards
    board_id = np.floor(x / bw).astype(int)
    local = (x % bw) / bw
    rng = np.random.default_rng(11)
    tone = rng.normal(0, 0.035, boards)[board_id]
    g = grain(size, 21, "y", 30)
    brush = fbm(size, 6, 4, 33, aspect=(10, 1))
    mott = fbm(size, 3, 4, 44)
    base = rgb((156, 166, 170))
    amt = tone[None, :] + (g - 0.5) * 0.07 + (brush - 0.5) * 0.06 + (mott - 0.5) * 0.08
    col = tint(base, amt)
    # groove shadow + bevel highlight
    groove = np.exp(-((local - 0.0) / 0.035) ** 2) + np.exp(-((local - 1.0) / 0.035) ** 2)
    edge_hi = np.exp(-((local - 0.07) / 0.03) ** 2)
    col *= (1.0 - 0.55 * groove)[None, :, None]
    col += (0.05 * edge_hi)[None, :, None]
    # faint paint chipping showing grey wood
    chips = fbm(size, 28, 3, 55) > 0.8
    wood = rgb((120, 112, 100))
    col[chips] = lerp(col[chips], wood, 0.55)
    height = np.tile(1.0 - np.clip(groove * 1.4, 0, 1), (size, 1)) * 0.85 + 0.15 * g
    save("siding", col, height)


def plaster(size=512):
    """Interior paint over drywall, near-white (tinted per room in the shader). 2 m tile."""
    roll = fbm(size, 5, 5, 61)
    fine = fbm(size, 48, 2, 62)
    streak = fbm(size, 3, 3, 63, aspect=(1, 6))
    base = rgb((236, 232, 224))
    amt = (roll - 0.5) * 0.06 + (fine - 0.5) * 0.04 + (streak - 0.5) * 0.04
    col = tint(base, amt)
    height = 0.5 + (fine - 0.5) * 0.6 + (roll - 0.5) * 0.3
    save("plaster", col, height)


def planks(name, size, plank_count, base_rgb, seed, row_len=(0.35, 0.8), contrast=1.0):
    """Floor boards running along x, 2 m tile with `plank_count` rows."""
    rng = np.random.default_rng(seed)
    y = np.arange(size)
    x = np.arange(size)
    ph = size / plank_count
    row = np.floor(y / ph).astype(int)
    ly = (y % ph) / ph
    col = np.zeros((size, size, 3))
    height = np.ones((size, size))
    base = rgb(base_rgb)
    g = grain(size, seed + 1, "x", 30)
    mott = fbm(size, 4, 4, seed + 2)
    for r in range(plank_count):
        rows = row == r
        # staggered joints, wrapping across the tile
        cuts = []
        pos = rng.random() * size
        while len(cuts) < 6:
            cuts.append(pos % size)
            pos += size * rng.uniform(*row_len)
            if pos - cuts[0] >= size:
                break
        cuts = sorted(cuts)
        seg_id = np.searchsorted(cuts, x, side="right") % len(cuts)
        seg_tone = rng.normal(0, 0.08 * contrast, len(cuts))[seg_id]
        seg_hue = rng.normal(0, 0.025, len(cuts))[seg_id]
        tone = seg_tone[None, :] + (g[rows] - 0.5) * 0.16 * contrast + (mott[rows] - 0.5) * 0.08
        c = tint(base, tone)
        c[..., 0] *= 1 + seg_hue[None, :]
        c[..., 2] *= 1 - seg_hue[None, :]
        col[rows] = c
        # end joints
        for cpos in cuts:
            d = np.minimum(np.abs(x - cpos), size - np.abs(x - cpos))
            j = np.exp(-(d / 1.6) ** 2)
            col[rows] *= (1 - 0.45 * j)[None, :, None]
            height[rows] = np.minimum(height[rows], 1 - j[None, :] * np.ones((rows.sum(), 1)))
    seam = np.exp(-((ly - 0.0) / 0.03) ** 2) + np.exp(-((ly - 1.0) / 0.03) ** 2)
    col *= (1 - 0.5 * seam)[:, None, None]
    height = np.minimum(height, (1 - np.clip(seam * 1.3, 0, 1))[:, None])
    height = height * 0.85 + 0.15 * g
    save(name, col, height)


def tile_grid(name, size, count, colors, grout_rgb, seed, grout=0.06, jitter=0.05, glaze=True):
    """Square tiles, `count` per tile edge, colours chosen per tile."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:size, 0:size]
    tsz = size / count
    ix = np.floor(x / tsz).astype(int)
    iy = np.floor(y / tsz).astype(int)
    lx = (x % tsz) / tsz
    ly = (y % tsz) / tsz
    pick = rng.integers(0, len(colors), (count, count))
    tone = rng.normal(0, jitter, (count, count))
    base = np.array([rgb(c) for c in colors])[pick[iy, ix]]
    col = base * (1 + tone[iy, ix])[..., None]
    mott = fbm(size, 6, 4, seed + 3)
    col *= (1 + (mott - 0.5) * 0.1)[..., None]
    if glaze:
        # soft glaze highlight toward the upper-left of each tile
        hl = np.clip(1 - np.hypot(lx - 0.3, ly - 0.3) * 1.6, 0, 1) ** 2
        col += hl[..., None] * 0.05
    d = np.minimum(np.minimum(lx, 1 - lx), np.minimum(ly, 1 - ly))
    gm = np.clip(1 - d / grout, 0, 1)
    gm = gm ** 1.5
    gcol = rgb(grout_rgb) * (1 + (fbm(size, 30, 2, seed + 4) - 0.5) * 0.2)[..., None]
    col = lerp(col, gcol, gm[..., None])
    height = 1 - gm * 0.9
    save(name, col, height)


def hex_tiles(name, size, across, seed):
    """Terracotta hexagon tiles (pointy-top), tileable. `across` hexes per row;
    the row count is the nearest even number, with a ~1 % vertical squash."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:size, 0:size].astype(float)
    ri = size / across / 2.0                    # inradius (flat sides left/right)
    big_r = ri * 2.0 / np.sqrt(3.0)             # circumradius
    rows = int(round(size / (1.5 * big_r) / 2.0)) * 2
    sy = (rows * 1.5 * big_r) / size            # squash so rows tile exactly
    yy = y * sy
    span_y = size * sy
    best = np.full((size, size), 1e9)
    cell_id = np.zeros((size, size), int)
    for r in range(rows):
        for c in range(across):
            cx = c * 2 * ri + (ri if r % 2 else 0.0)
            cy = r * 1.5 * big_r
            dx = np.abs(((x - cx + size / 2) % size) - size / 2)
            dy = np.abs(((yy - cy + span_y / 2) % span_y) - span_y / 2)
            hd = np.maximum(dx, 0.5 * dx + 0.8660254 * dy) / ri
            m = hd < best
            best[m] = hd[m]
            cell_id[m] = r * across + c
    tones = rng.normal(0, 0.07, rows * across)
    hues = rng.normal(0, 0.03, rows * across)
    base = rgb((178, 98, 66))
    col = base[None, None, :] * (1 + tones[cell_id])[..., None]
    col[..., 0] *= 1 + hues[cell_id]
    col[..., 1] *= 1 - hues[cell_id] * 0.5
    mott = fbm(size, 8, 4, seed + 9)
    col *= (1 + (mott - 0.5) * 0.18)[..., None]
    gm = np.clip((best - 0.88) / 0.1, 0, 1)
    grout = rgb((196, 186, 170))
    col = lerp(col, grout[None, None, :], gm[..., None])
    height = 1 - gm * 0.9
    save(name, col, height)


def concrete(size=512):
    """Poured concrete, 2 m tile: mottled, aggregate speckle, a hairline crack."""
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


def roof(size=512):
    """Standing-seam metal roof, 2 m tile, seams every 0.5 m (along y = slope)."""
    x = np.arange(size)
    period = size / 4
    local = (x % period) / period
    seam = np.exp(-((local - 0.5) / 0.018) ** 2)
    seam_sh = np.exp(-((local - 0.53) / 0.03) ** 2)
    streak = fbm(size, 5, 4, 91, aspect=(8, 1))
    mott = fbm(size, 3, 3, 92)
    base = rgb((64, 68, 72))
    amt = (streak - 0.5) * 0.2 + (mott - 0.5) * 0.12
    col = tint(base, amt)
    col += (seam * 0.18)[None, :, None]
    col *= (1 - 0.3 * seam_sh)[None, :, None]
    # rust bloom in a few places
    rust = np.clip((fbm(size, 7, 4, 93) - 0.68) * 5, 0, 1)
    col = lerp(col, rgb((112, 70, 46))[None, None, :] * (0.8 + 0.4 * streak[..., None]), (rust * 0.5)[..., None])
    height = np.tile(0.4 + seam * 0.6, (size, 1))
    save("roof", col, height)


def grass(size=512):
    """Dead suburban lawn, 4 m tile: straw, olive and bare patches."""
    m1 = fbm(size, 5, 5, 101)
    m2 = fbm(size, 10, 4, 102)
    blades = fbm(size, 80, 2, 103)
    dry = rgb((138, 128, 94))
    olive = rgb((96, 98, 74))
    dirt = rgb((94, 82, 68))
    t = np.clip((m1 - 0.35) * 1.6 + (m2 - 0.5) * 0.8, 0, 1)
    col = lerp(olive[None, None, :], dry[None, None, :], t[..., None])
    bare = np.clip((m2 - 0.66) * 4, 0, 1)
    col = lerp(col, dirt[None, None, :], (bare * 0.7)[..., None])
    col *= (1 + (blades - 0.5) * 0.35)[..., None]
    height = 0.5 + (blades - 0.5) * 0.8
    save("grass", col, height)


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


def marks(size=512):
    """Damage marks atlas, 2x2 cells, RGBA with real transparency:
    0 bullet hole, 1 splintered gash, 2 crack web, 3 glass impact web."""
    cell = size // 2
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ss = 4
    rng = np.random.default_rng(141)

    def cell_canvas():
        return Image.new("RGBA", (cell * ss, cell * ss), (0, 0, 0, 0))

    # 0: bullet hole - torn rim (light raw material), dark core, soot ring
    c = cell_canvas()
    d = ImageDraw.Draw(c)
    cc = cell * ss / 2
    pts = []
    for k in range(18):
        a = k / 18 * np.pi * 2
        r = cell * ss * (0.26 + rng.uniform(-0.06, 0.07))
        pts.append((cc + np.cos(a) * r, cc + np.sin(a) * r))
    # soft soot / dirt halo (radial gradient)
    yy, xx = np.mgrid[0:cell * ss, 0:cell * ss].astype(float)
    rr = np.hypot(xx - cc, yy - cc) / (cell * ss * 0.48)
    halo = np.clip(1.0 - rr, 0, 1) ** 1.3 * 0.62
    halo_img = np.zeros((cell * ss, cell * ss, 4), np.uint8)
    halo_img[..., 0] = 34
    halo_img[..., 1] = 30
    halo_img[..., 2] = 27
    halo_img[..., 3] = (halo * 255).astype(np.uint8)
    c = Image.alpha_composite(c, Image.fromarray(halo_img, "RGBA"))
    d = ImageDraw.Draw(c)
    d.polygon(pts, fill=(226, 214, 192, 255))
    pts2 = []
    for k in range(14):
        a = k / 14 * np.pi * 2
        r = cell * ss * (0.13 + rng.uniform(-0.03, 0.03))
        pts2.append((cc + np.cos(a) * r, cc + np.sin(a) * r))
    d.polygon(pts2, fill=(18, 14, 12, 255))
    for k in range(7):
        a = rng.uniform(0, np.pi * 2)
        r0 = cell * ss * 0.24
        r1 = cell * ss * rng.uniform(0.34, 0.46)
        d.line([(cc + np.cos(a) * r0, cc + np.sin(a) * r0), (cc + np.cos(a) * r1, cc + np.sin(a) * r1)], fill=(40, 34, 28, 220), width=ss * 2)
    img.paste(c.resize((cell, cell), Image.LANCZOS), (0, 0))

    # 1: splintered gash (enemy blows / heavy hits)
    c = cell_canvas()
    d = ImageDraw.Draw(c)
    for k in range(5):
        x0 = cc + rng.uniform(-0.3, 0.3) * cell * ss
        y0 = cc + rng.uniform(-0.25, 0.25) * cell * ss
        ang = rng.uniform(-0.5, 0.5) + np.pi / 2 * (k % 2)
        ln = cell * ss * rng.uniform(0.25, 0.42)
        w = ss * rng.uniform(4, 9)
        dx, dy = np.cos(ang) * ln / 2, np.sin(ang) * ln / 2
        d.line([(x0 - dx, y0 - dy), (x0 + dx, y0 + dy)], fill=(214, 196, 160, 255), width=int(w * 1.8))
        d.line([(x0 - dx * 0.8, y0 - dy * 0.8), (x0 + dx * 0.8, y0 + dy * 0.8)], fill=(34, 26, 20, 255), width=int(w * 0.6))
    img.paste(c.resize((cell, cell), Image.LANCZOS), (cell, 0))

    # 2: crack web (plaster / siding cracks)
    c = cell_canvas()
    d = ImageDraw.Draw(c)
    for k in range(6):
        p = np.array([cc, cc]) + rng.normal(0, cell * ss * 0.04, 2)
        ang = k / 6 * np.pi * 2 + rng.uniform(-0.3, 0.3)
        width = ss * 3
        for s in range(9):
            ang += rng.normal(0, 0.35)
            q = p + np.array([np.cos(ang), np.sin(ang)]) * cell * ss * 0.055
            d.line([tuple(p), tuple(q)], fill=(24, 20, 18, 235), width=max(ss, int(width)))
            if rng.random() < 0.3:
                b = ang + rng.choice([-1, 1]) * 0.9
                q2 = p + np.array([np.cos(b), np.sin(b)]) * cell * ss * 0.07
                d.line([tuple(p), tuple(q2)], fill=(24, 20, 18, 200), width=ss * 2)
            p = q
            width *= 0.85
    img.paste(c.resize((cell, cell), Image.LANCZOS), (0, cell))

    # 3: glass impact web (white, for the glass pane)
    c = cell_canvas()
    d = ImageDraw.Draw(c)
    rays = 11
    for k in range(rays):
        ang = k / rays * np.pi * 2 + rng.uniform(-0.15, 0.15)
        p = np.array([cc, cc])
        for s in range(7):
            ang += rng.normal(0, 0.12)
            q = p + np.array([np.cos(ang), np.sin(ang)]) * cell * ss * 0.07
            d.line([tuple(p), tuple(q)], fill=(235, 245, 250, 230), width=ss * 2)
            p = q
    for ring in (0.09, 0.18, 0.3):
        pts = []
        for k in range(rays + 1):
            a = k / rays * np.pi * 2
            r = cell * ss * ring * rng.uniform(0.85, 1.15)
            pts.append((cc + np.cos(a) * r, cc + np.sin(a) * r))
        d.line(pts, fill=(235, 245, 250, 170), width=ss * 2)
    d.ellipse((cc - ss * 10, cc - ss * 10, cc + ss * 10, cc + ss * 10), fill=(250, 252, 255, 255))
    img.paste(c.resize((cell, cell), Image.LANCZOS), (cell, cell))
    img.save(OUT / "template_marks.png")
    print("  template_marks.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    print("writing", OUT)
    siding()
    plaster()
    planks("floor_wood", 512, 11, (150, 104, 66), 151)
    planks("floor_wood_light", 512, 9, (196, 170, 132), 161, row_len=(0.5, 1.0), contrast=0.7)
    tile_grid("floor_tile", 512, 10, [(206, 214, 214), (196, 206, 208), (214, 220, 218)], (150, 156, 156), 171, grout=0.07)
    hex_tiles("floor_kitchen_tile", 512, 7, 181)
    concrete()
    roof()
    grass()
    asphalt()
    fabric()
    wood_grain()
    marks()
