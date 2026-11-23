"""Seamless floors and grounds for the modern house (512x512 = 4 m x 4 m at 128 px/m).

Helpers label_map / seam_mask / bevel / ink_seams / crack are adapted from The
Witchening Tales (tools/art/floors.py, the user's own project). The materials
themselves are new: wide modern oak planks, pale oak, matte bathroom tiles,
patterned cement kitchen tiles, polished concrete, OSB subfloor, decking,
pavement, asphalt and an overgrown lawn.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

from core import (Canvas, INK, blur, col, dilate, fbm, mix, pnoise, rng, rrect_pts, save, smoothstep,
                  wood_tex, wobble_pts, ellipse_pts)

N = 512
SS = 2


# --------------------------------------------------------------------------
# label-map helpers (each tile/plank gets an integer id)
# --------------------------------------------------------------------------
def label_map(cv, polys, wobble=0.0):
    img = Image.new("I", (cv.W, cv.H), 0)
    d = ImageDraw.Draw(img)
    ss = cv.ss
    offs = [(ox, oy) for ox in (-cv.W, 0, cv.W) for oy in (-cv.H, 0, cv.H)]
    for i, pts in enumerate(polys):
        p = np.asarray(pts, float) * ss
        if wobble:
            p = wobble_pts(p, wobble * ss, cv.rnd, step=3 * ss)
        for ox, oy in offs:
            d.polygon([(x + ox, y + oy) for x, y in p], fill=i + 1)
    return np.asarray(img, dtype=np.int32)


def seam_mask(lab):
    e = (lab != np.roll(lab, 1, 0)) | (lab != np.roll(lab, 1, 1)) | (lab == 0)
    return e.astype(np.float32)


def bevel(cv, edges, d=3.0, sigma=2.0, dark=0.45, light=0.25, shade_color=(30, 28, 34)):
    """Shade each cell's lower-right rim, lighten its upper-left rim."""
    dd = int(d * cv.ss)
    b = blur(edges, sigma * cv.ss, True)
    b = np.clip(b * 2.2, 0, 1)
    dk = np.clip(np.roll(b, (-dd, -dd), (0, 1)) - edges, 0, 1)
    lt = np.clip(np.roll(b, (dd, dd), (0, 1)) - edges - dk, 0, 1)
    cv.mul(dk, dark, shade_color)
    cv.screen(lt, light, (235, 222, 196))
    return dk


def ink_seams(cv, edges, width=1.6, color=INK, op=0.95):
    m = dilate(edges, width * cv.ss * 0.5, True, cv.wob())
    cv.tint(m, color, op)
    return m


def crack(cv, x, y, length, rnd, width=0.7, color=INK, op=0.85):
    pts = [(x, y)]
    a = rnd.random() * 2 * math.pi
    for _ in range(int(length / 4)):
        a += rnd.normal(0, 0.5)
        x += math.cos(a) * 4
        y += math.sin(a) * 4
        pts.append((x, y))
    m = cv.mask().line(pts, width)
    cv.tint(m, color, op)
    if rnd.random() < 0.6 and len(pts) > 4:
        i = int(rnd.integers(1, len(pts) - 2))
        bx, by = pts[i]
        b = [(bx, by)]
        a2 = a + rnd.choice([-1, 1]) * 1.0
        for _ in range(int(length / 10)):
            a2 += rnd.normal(0, 0.5)
            bx += math.cos(a2) * 3
            by += math.sin(a2) * 3
            b.append((bx, by))
        cv.tint(cv.mask().line(b, width * 0.7), color, op * 0.8)


def finish_floor(cv, name, grain=0.07, size=None):
    cv.grain(grain)
    img = cv.image().convert("RGB")
    save(img, name, opaque=True)
    return img


def _wrap_draw(cv):
    img = Image.fromarray(np.clip(cv.rgb, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    offs = [(ox, oy) for ox in (-cv.W, 0, cv.W) for oy in (-cv.H, 0, cv.H)]
    return img, d, offs


def _close_wrap(cv, img):
    cv.rgb = np.asarray(img, np.float32).copy()


# --------------------------------------------------------------------------
# modern plank floors: long boards, staggered ends, micro-bevel, no nails
# --------------------------------------------------------------------------
def planks(name, base, dark, light, rows=16, wear=0.12, knot_rate=0.12, scuff=0.4, min_len=150):
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    board = N / rows
    polys = []
    for ri in range(rows):
        while True:
            k = int(r.integers(1, 3))
            cuts = np.sort(r.integers(0, N, k))
            gaps = np.diff(np.concatenate([cuts, [cuts[0] + N]]))
            if gaps.min() >= min_len:
                break
        y0, y1 = ri * board, (ri + 1) * board
        for i, c0 in enumerate(cuts):
            c1 = c0 + gaps[i]
            polys.append([(c0, y0), (c1, y0), (c1, y1), (c0, y1)])
    lab = label_map(cv, polys)
    nvar = 6
    texs = [wood_tex(cv.W, cv.H, rng(f"{name}:v{i}"), base, dark, light, rings=int(r.integers(40, 64)), streak=1.1)
            for i in range(nvar)]
    var = r.integers(0, nvar, len(polys) + 1)
    tone = 0.88 + 0.22 * r.random(len(polys) + 1)
    out = np.zeros((cv.H, cv.W, 3), np.float32)
    for i in range(nvar):
        sel = (var[lab] == i)
        out[sel] = texs[i][sel]
    out *= tone[lab][..., None]
    cv.rgb[:] = out
    cv.a[:] = 1
    n = cv.noise(4, 4, 4, seed="wear")
    cv.mul(smoothstep(0.65, 0.95, n), 0.18)
    cv.screen(smoothstep(0.45, 0.05, n), wear, (200, 180, 150))
    edges = seam_mask(lab)
    bevel(cv, edges, 2.0, 1.3, 0.42, 0.2)
    hz = smoothstep(0.55, 0.85, cv.noise(3, 5, 3, seed="hz"))
    cv.hatch(hz, angle=-8, spacing=3.0, width=0.5, op=0.2, dash=20)
    for p in polys:
        if r.random() < knot_rate:
            (c0, y0), (c1, _), _, (_, y1) = p
            kx = (c0 + 20 + r.random() * max(10, (c1 - c0 - 40))) % N
            ky = y0 + 5 + r.random() * (board - 10)
            for i, k in enumerate((1.8, 1.3, 0.8)):
                m = cv.mask().ellipse(kx, ky, 3.2 * k, 1.4 * k, wobble=0.3)
                cv.tint(m, dark, 0.2 + 0.18 * i)
    for _ in range(int(70 * scuff)):
        x, y = r.random() * N, r.random() * N
        a = r.normal(0, 0.35)
        ln = 6 + r.random() * 24
        m = cv.mask().line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], 0.5)
        cv.tint(m, (225, 205, 170) if r.random() < 0.6 else INK, 0.22)
    ink_seams(cv, edges, 1.3, op=0.8)
    return finish_floor(cv, name)


# --------------------------------------------------------------------------
# bathroom: matte off-white square tiles with grey grout, a few hairline cracks
# --------------------------------------------------------------------------
def floor_tile():
    name = "floor_tile"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    n_t = 20
    t = N / n_t
    g = 1.1
    polys = []
    for j in range(n_t):
        for i in range(n_t):
            polys.append(rrect_pts(i * t + g, j * t + g, (i + 1) * t - g, (j + 1) * t - g, 1.2))
    lab = label_map(cv, polys, wobble=0.12)
    W, H = cv.W, cv.H
    nz = fbm(W, H, 10, 10, r, 5)
    base = col("#cfd0cb")[None, None, :] * (0.95 + 0.07 * nz[..., None])
    tone = 0.93 + 0.1 * r.random(len(polys) + 1)
    hue = r.random(len(polys) + 1)
    tint = np.stack([1.0 - 0.02 * hue, np.ones_like(hue), 1.0 + 0.02 * hue], -1)
    grout = col("#7d7c78")
    out = np.where((lab == 0)[..., None], grout[None, None, :], base * (tone[:, None] * tint)[lab])
    cv.rgb[:] = out
    cv.a[:] = 1
    edges = seam_mask(lab)
    bevel(cv, edges, 1.6, 1.0, 0.3, 0.35, (70, 76, 90))
    gr = cv.noise(5, 5, 4, seed="grime")
    cv.mul(smoothstep(0.62, 0.95, gr), 0.25, (110, 100, 80))
    cv.hatch(smoothstep(0.7, 0.95, gr), 50, 3.0, 0.45, 0.18)
    for _ in range(7):
        crack(cv, r.random() * N, r.random() * N, 10 + r.random() * 26, r, 0.5, (60, 58, 56), 0.7)
    ink_seams(cv, edges, 0.9, color=(52, 50, 48), op=0.7)
    return finish_floor(cv, name, 0.05)


# --------------------------------------------------------------------------
# kitchen: patterned cement tiles (muted slate + chalk + charcoal)
# --------------------------------------------------------------------------
def floor_kitchen_tile():
    name = "floor_kitchen_tile"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    n_t = 16
    t = N / n_t
    g = 0.9
    polys = []
    for j in range(n_t):
        for i in range(n_t):
            polys.append(rrect_pts(i * t + g, j * t + g, (i + 1) * t - g, (j + 1) * t - g, 0.8))
    lab = label_map(cv, polys, wobble=0.1)
    W, H = cv.W, cv.H
    S = int(t * SS)
    # one tile motif: quarter circles in each corner + a centre diamond, rotated per tile so 4 tiles form rosettes
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    quarter = (np.hypot(xx, yy) < 0.5).astype(np.float32)
    ring = ((np.hypot(xx, yy) < 0.62) & (np.hypot(xx, yy) > 0.55)).astype(np.float32)
    far = (np.hypot(1 - xx, 1 - yy) < 0.3).astype(np.float32)
    diamond = ((np.abs(xx - 0.5) + np.abs(yy - 0.5)) < 0.16).astype(np.float32)
    motif_a = np.clip(quarter + far, 0, 1)     # slate
    motif_b = np.clip(ring + diamond, 0, 1)    # charcoal
    A = np.zeros((H, W), np.float32)
    B = np.zeros((H, W), np.float32)
    for j in range(n_t):
        for i in range(n_t):
            k = (i % 2) + 2 * (j % 2)
            rot = [0, 1, 3, 2][k]
            a = np.rot90(motif_a, -rot)
            b = np.rot90(motif_b, -rot)
            y0, x0 = int(round(j * t * SS)), int(round(i * t * SS))
            hh = min(S, H - y0)
            ww = min(S, W - x0)
            A[y0:y0 + hh, x0:x0 + ww] = a[:hh, :ww]
            B[y0:y0 + hh, x0:x0 + ww] = b[:hh, :ww]
    A = blur(A, 0.8 * SS, True)
    B = blur(B, 0.6 * SS, True)
    nz = fbm(W, H, 12, 12, r, 5)
    chalk = col("#c9c3b4")[None, None, :] * (0.93 + 0.1 * nz[..., None])
    slate = col("#56687a")[None, None, :] * (0.9 + 0.16 * nz[..., None])
    char = col("#2c2f33")[None, None, :] * (0.9 + 0.2 * nz[..., None])
    out = chalk * (1 - A[..., None]) + slate * A[..., None]
    out = out * (1 - B[..., None]) + char * B[..., None]
    tone = 0.92 + 0.12 * r.random(len(polys) + 1)
    out = out * tone[lab][..., None]
    grout = col("#6b675f")
    out = np.where((lab == 0)[..., None], grout[None, None, :], out)
    cv.rgb[:] = out
    cv.a[:] = 1
    edges = seam_mask(lab)
    bevel(cv, edges, 1.6, 1.0, 0.35, 0.3)
    # cement tiles wear: faded patches, scuffs
    w = cv.noise(4, 4, 4, seed="wear")
    cv.screen(smoothstep(0.7, 0.98, w), 0.25, (210, 205, 190))
    cv.mul(smoothstep(0.35, 0.05, w), 0.25, (60, 50, 40))
    cv.hatch(smoothstep(0.4, 0.1, w), 35, 3.0, 0.5, 0.2)
    for _ in range(6):
        crack(cv, r.random() * N, r.random() * N, 10 + r.random() * 20, r, 0.5, (40, 38, 36), 0.6)
    ink_seams(cv, edges, 1.0, color=(40, 38, 36), op=0.75)
    return finish_floor(cv, name, 0.06)


# --------------------------------------------------------------------------
# utility room: polished concrete with saw-cut joints and stains
# --------------------------------------------------------------------------
def floor_concrete():
    name = "floor_concrete"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    n = fbm(W, H, 6, 6, r, 6)
    n2 = fbm(W, H, 40, 40, r, 3)
    c0, c1 = col("#6a6966"), col("#8c8a84")
    cv.rgb[:] = c0 + (c1 - c0) * (0.65 * n + 0.35 * n2)[..., None]
    cv.a[:] = 1
    # aggregate speckle
    sp = smoothstep(0.86, 0.93, pnoise(W, H, W // 3, H // 3, r))
    cv.mul(sp, 0.35, (30, 30, 30))
    sp2 = smoothstep(0.88, 0.95, pnoise(W, H, W // 4, H // 4, rng(name + "b")))
    cv.screen(sp2, 0.25, (220, 215, 205))
    # oil / damp stains
    st = smoothstep(0.7, 0.9, cv.noise(3, 3, 4, seed="stain"))
    cv.mul(st, 0.35, (50, 45, 40))
    cv.hatch(smoothstep(0.75, 0.95, cv.noise(3, 3, 4, seed="stain")), 45, 3.2, 0.5, 0.22)
    # trowel swirls (faint)
    for _ in range(18):
        x, y = r.random() * N, r.random() * N
        rr = 18 + r.random() * 30
        pts = ellipse_pts(x, y, rr, rr * 0.6, 40, r.random() * 180, 0, 110 + r.random() * 90)
        cv.tint(cv.mask().line(pts, 0.6), (190, 186, 178), 0.12)
    # saw-cut control joints every 2 m (256 px)
    joints = np.zeros((H, W), np.float32)
    for k in range(2):
        p = int(k * 256 * SS)
        joints[:, p:p + int(1.2 * SS)] = 1
        joints[p:p + int(1.2 * SS), :] = 1
    joints = blur(joints, 0.4 * SS, True)
    bevel(cv, joints, 1.5, 1.0, 0.4, 0.25)
    cv.tint(np.clip(joints * 1.5, 0, 1), (35, 33, 32), 0.85)
    for _ in range(9):
        crack(cv, r.random() * N, r.random() * N, 20 + r.random() * 50, r, 0.55, (38, 36, 34), 0.7)
    return finish_floor(cv, name, 0.06)


# --------------------------------------------------------------------------
# OSB subfloor (revealed under destroyed wall sections), 256x256
# --------------------------------------------------------------------------
def floor_subfloor():
    name = "floor_subfloor"
    S = 256
    cv = Canvas(S, S, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    n = fbm(W, H, 8, 8, r, 4)
    cv.rgb[:] = col("#9c7a50")[None, None, :] * (0.85 + 0.25 * n[..., None])
    cv.a[:] = 1
    img, d, offs = _wrap_draw(cv)
    for _ in range(900):
        x, y = r.random() * W, r.random() * H
        a = r.random() * 180
        ln = (8 + r.random() * 22) * SS
        wd = (2 + r.random() * 5) * SS
        pts = [(x + math.cos(math.radians(a)) * ln / 2 * sx - math.sin(math.radians(a)) * wd / 2 * sy,
                y + math.sin(math.radians(a)) * ln / 2 * sx + math.cos(math.radians(a)) * wd / 2 * sy)
               for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        t = r.random()
        fill = tuple(int(v) for v in mix("#7a5a36", "#c49a64", t))
        for ox, oy in offs:
            d.polygon([(px + ox, py + oy) for px, py in pts], fill=fill)
    _close_wrap(cv, img)
    cv.mul(smoothstep(0.55, 0.95, cv.noise(5, 5, 3, seed="dk")), 0.3)
    cv.hatch(np.ones((H, W), np.float32), 45, 3.0, 0.4, 0.12)
    # stamped nail line
    for k in range(8):
        y = (k + 0.5) * S / 8
        m = cv.mask().circle(S * 0.5, y, 1.3)
        cv.tint(m, INK, 0.8)
    return finish_floor(cv, name, 0.06)


# --------------------------------------------------------------------------
# outdoor: deck boards, pavement, asphalt, overgrown lawn
# --------------------------------------------------------------------------
def floor_deck():
    name = "floor_deck"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    rows = 28
    board = N / rows
    polys = []
    for ri in range(rows):
        cut = r.integers(0, N)
        y0, y1 = ri * board + 1.4, (ri + 1) * board - 1.4
        polys.append([(cut, y0), (cut + N - 3, y0), (cut + N - 3, y1), (cut, y1)])
    lab = label_map(cv, polys)
    texs = [wood_tex(cv.W, cv.H, rng(f"{name}:v{i}"), "#7d7468", "#3f3a33", "#9b9283", rings=12) for i in range(4)]
    var = r.integers(0, 4, len(polys) + 1)
    tone = 0.85 + 0.25 * r.random(len(polys) + 1)
    out = np.zeros((cv.H, cv.W, 3), np.float32)
    for i in range(4):
        sel = var[lab] == i
        out[sel] = texs[i][sel]
    out *= tone[lab][..., None]
    out = np.where((lab == 0)[..., None], col("#1a1714")[None, None, :], out)
    cv.rgb[:] = out
    cv.a[:] = 1
    edges = seam_mask(lab)
    bevel(cv, edges, 2.0, 1.4, 0.5, 0.22)
    w = cv.noise(4, 4, 4, seed="weather")
    cv.mul(smoothstep(0.55, 0.95, w), 0.35, (40, 45, 40))
    cv.tint(smoothstep(0.75, 0.95, w), "#4a5040", 0.25)
    for ri in range(rows):
        y = (ri + 0.5) * board
        for x in (64, 192, 320, 448):
            for dy in (-board * 0.25, board * 0.25):
                cv.tint(cv.mask().circle(x, y + dy, 1.1), (40, 38, 36), 0.9)
    ink_seams(cv, edges, 1.0, op=0.8)
    return finish_floor(cv, name, 0.07)


def ground_concrete():
    name = "ground_concrete"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    t = 128
    polys = []
    for j in range(N // t):
        for i in range(N // t):
            polys.append(rrect_pts(i * t + 1.5, j * t + 1.5, (i + 1) * t - 1.5, (j + 1) * t - 1.5, 2))
    lab = label_map(cv, polys, wobble=0.5)
    n = fbm(W, H, 10, 10, r, 5)
    base = col("#8a8781")[None, None, :] * (0.85 + 0.25 * n[..., None])
    tone = 0.88 + 0.16 * r.random(len(polys) + 1)
    out = np.where((lab == 0)[..., None], col("#2b2a27")[None, None, :], base * tone[lab][..., None])
    cv.rgb[:] = out
    cv.a[:] = 1
    edges = seam_mask(lab)
    bevel(cv, edges, 2.5, 1.6, 0.45, 0.25)
    sp = smoothstep(0.86, 0.93, pnoise(W, H, W // 3, H // 3, r))
    cv.mul(sp, 0.3, (30, 30, 30))
    st = cv.noise(4, 4, 4, seed="stain")
    cv.mul(smoothstep(0.65, 0.95, st), 0.35, (40, 40, 30))
    # moss / weeds in the joints
    moss = blur(edges, 2.5 * SS, True) * smoothstep(0.45, 0.8, cv.noise(6, 6, 3, seed="moss"))
    cv.tint(np.clip(moss * 2.2, 0, 1), "#46512f", 0.65)
    for _ in range(14):
        crack(cv, r.random() * N, r.random() * N, 20 + r.random() * 50, r, 0.7, (30, 28, 26), 0.8)
    ink_seams(cv, edges, 1.4, op=0.85)
    return finish_floor(cv, name, 0.07)


def ground_asphalt():
    name = "ground_asphalt"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    n = fbm(W, H, 6, 6, r, 5)
    cv.rgb[:] = col("#36373a")[None, None, :] * (0.8 + 0.35 * n[..., None])
    cv.a[:] = 1
    for s, op, c in ((W // 2, 0.4, (15, 15, 16)), (W // 3, 0.35, (120, 118, 112))):
        sp = smoothstep(0.82, 0.9, pnoise(W, H, s, s, rng(f"{name}{s}")))
        if c[0] > 50:
            cv.screen(sp, op, c)
        else:
            cv.mul(sp, op, c)
    # patched repairs and tar-sealed cracks
    pat = smoothstep(0.72, 0.76, cv.noise(3, 3, 3, seed="patch"))
    cv.mul(pat, 0.25, (20, 20, 22))
    for _ in range(20):
        crack(cv, r.random() * N, r.random() * N, 30 + r.random() * 80, r, 1.2, (12, 12, 13), 0.85)
    cv.hatch(smoothstep(0.6, 0.9, cv.noise(4, 4, 3, seed="h")), 45, 3.2, 0.5, 0.2)
    return finish_floor(cv, name, 0.06)


def ground_grass():
    """Overgrown, half-dead suburban lawn (cool olive with straw patches)."""
    name = "ground_grass"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    n = fbm(W, H, 5, 5, r, 5)
    dead = fbm(W, H, 3, 3, rng(name + "dead"), 4)
    c0, c1 = col("#323b27"), col("#4a5532")
    straw0, straw1 = col("#4f4630"), col("#7a6c48")
    green = c0 + (c1 - c0) * n[..., None]
    straw = straw0 + (straw1 - straw0) * n[..., None]
    dm = smoothstep(0.55, 0.8, dead)[..., None]
    cv.rgb[:] = green * (1 - dm) + straw * dm
    cv.a[:] = 1
    cv.hatch(np.ones((H, W), np.float32), 60, 2.6, 0.5, 0.2)
    img, d, offs = _wrap_draw(cv)
    clump = fbm(W, H, 6, 6, rng("grass:clump"), 3)
    pal_g = [("#161c12", "#232b1a"), ("#2c3620", "#3f4a2a"), ("#47532f", "#66703e"), ("#6a7444", "#8a8a55")]
    pal_s = [("#2a2419", "#3a3222"), ("#4f4530", "#665a3c"), ("#7a6a44", "#968458"), ("#9c8c5e", "#b8a674")]
    for li in range(4):
        count = [2400, 3200, 2400, 900][li]
        for _ in range(count):
            x, y = r.random() * W, r.random() * H
            cl = clump[int(y) % H, int(x) % W]
            if li >= 2 and cl < 0.25 + 0.1 * li:
                continue
            isdead = dead[int(y) % H, int(x) % W] > 0.62
            pal = pal_s if isdead else pal_g
            nb = int(r.integers(5, 11))
            for _b in range(nb):
                a = r.random() * 2 * math.pi
                ln = (2 + r.random() * (3 + 1.8 * li)) * SS
                bend = r.normal(0, 0.4)
                pts = [(x + math.cos(a + bend * t) * ln * t, y + math.sin(a + bend * t) * ln * t)
                       for t in np.linspace(0, 1, 4)]
                fill = tuple(int(v) for v in mix(pal[li][0], pal[li][1], r.random()))
                w = max(1, int((0.5 + r.random() * 0.7) * SS))
                for ox, oy in offs:
                    q = [(px + ox, py + oy) for px, py in pts]
                    if li >= 2 and _b % 3 == 0:
                        d.line([(px + 0.9 * SS, py + 0.9 * SS) for px, py in q], fill=(8, 10, 7), width=w + 1)
                    d.line(q, fill=fill, width=w)
    # dandelion rosettes / clover and a few fallen leaves
    for _ in range(40):
        x, y = r.random() * W, r.random() * H
        for k in range(4):
            a = k * 1.57 + r.random()
            px, py = x + math.cos(a) * 3 * SS, y + math.sin(a) * 3 * SS
            pts = ellipse_pts(px, py, 3.2 * SS, 1.3 * SS, 10, math.degrees(a))
            for ox, oy in offs:
                d.polygon([(qx + ox, qy + oy) for qx, qy in pts], fill=(52, 66, 38), outline=(12, 15, 10))
    for _ in range(30):
        x, y = r.random() * W, r.random() * H
        rr = (3 + r.random() * 3) * SS
        a = r.random() * 360
        fill = tuple(int(v) for v in mix("#5a3a22", "#8a6232", r.random()))
        pts = ellipse_pts(x, y, rr, rr * 0.45, 16, a)
        for ox, oy in offs:
            d.polygon([(px + ox, py + oy) for px, py in pts], fill=fill, outline=INK)
    _close_wrap(cv, img)
    cv.mul(smoothstep(0.35, 0.05, n), 0.15, (5, 8, 10))
    return finish_floor(cv, name, 0.07)


def build_all():
    print("floors")
    planks("floor_wood", "#7a5a3e", "#3a2617", "#9c7a56", rows=16, wear=0.12)
    planks("floor_wood_light", "#a88c6a", "#6a5038", "#c4aa84", rows=20, wear=0.18, scuff=0.6)
    floor_tile()
    floor_kitchen_tile()
    floor_concrete()
    floor_subfloor()
    floor_deck()
    ground_concrete()
    ground_asphalt()
    ground_grass()


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        for f in sys.argv[1:]:
            globals()[f]()
    else:
        build_all()
