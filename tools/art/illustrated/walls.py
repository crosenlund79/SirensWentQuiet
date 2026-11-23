"""Wall kit: horizontally tileable wall-cap strips in three damage states, window
panes in four states, a corner post, a fence strip and a door leaf.

Layout of every wall strip (x runs along the wall, 128 px per meter):
    rows 0..M-1          transparent margin (splinters / chips may poke out here)
    rows M..M+T-1        the wall cap, T = thickness * 128
    rows M+T..M+T+M-1    transparent margin
The TOP of an exterior strip is the OUTSIDE face (charcoal cladding); the bottom
is the painted interior drywall. The game rotates strips so the cladding always
faces out. Strips carry no directional light: the engine adds the upper-left
rim and lower-right shadow in world space.
"""
from __future__ import annotations

import math

import numpy as np

from core import (Canvas, INK, blur, col, dilate, fbm, mix, pnoise, rng, save, smoothstep, wood_tex, catmull,
                  ellipse_pts, rrect_pts)

M = 8            # margin rows
PAD = 24         # extra transparent rows so the canvas' vertical wrap never touches the strip
L = 512          # strip length (4 m)
SS = 4

CLAD = "#33393f"       # charcoal-stained cedar cladding
CORE = "#4b3f35"       # dark-stained top plate
CORE_INT = "#463e38"   # interior wall cap (stud plate)
DRY = "#d9d2c3"        # painted drywall
RAW = "#c9a577"        # fresh raw wood (splinters, studs)
RAW_DK = "#8a6a44"
CAVITY = "#1d1714"
INSUL = "#c9a96a"      # mineral-wool insulation (muted ochre)


def strip_canvas(name, T, w=L):
    H = T + 2 * M + 2 * PAD
    cv = Canvas(w, H, SS, tile=True, name=name)
    return cv, PAD + M, PAD + M + T


def crop_save(cv, name, T):
    img = cv.image()
    img = img.crop((0, PAD, img.width, PAD + T + 2 * M))
    save(img, name)
    return img


def band(cv, y0, y1, w=L):
    return cv.mask().rect(-2, y0, w + 2, y1)


# --------------------------------------------------------------------------
# intact strips
# --------------------------------------------------------------------------
def _base_strip(cv, y0, y1, exterior, w=L):
    """Paint the intact wall cap between rows y0..y1 and return band masks."""
    r = cv.rnd
    T = y1 - y0
    whole = band(cv, y0, y1, w)
    if exterior:
        clad_h = 7.0
        dry_h = 6.0
        core_c = CORE
    else:
        clad_h = 0.0
        dry_h = 3.2
        core_c = CORE_INT
    # core: stained timber plate with grain along x
    tex = wood_tex(cv.W, cv.H, rng(cv.name + "core"), core_c, mix(core_c, "#000000", 0.55),
                   mix(core_c, "#ffffff", 0.12), rings=int(cv.H / (5 * SS)) + 3)
    cv.paint(whole, tex)
    # poche cross-hatching (fine, low contrast)
    core_m = band(cv, y0 + (clad_h if exterior else dry_h), y1 - dry_h, w).arr
    cv.hatch(core_m, 45, 2.4, 0.45, 0.35)
    cv.hatch(core_m * smoothstep(0.55, 0.9, cv.noise(6, 2, 3, seed="hz")), -45, 2.6, 0.4, 0.3)
    # butt joints in the plate + nails
    xs = []
    x = r.random() * 120
    while x < w:
        xs.append(x)
        x += 150 + r.random() * 140
    for x in xs:
        cv.stroke([(x, y0 + clad_h), (x + r.normal(0, 0.6), y1 - dry_h)], 0.8, INK, 0.85)
        for dx in (-5, 5):
            for yy in (0.35, 0.65):
                cv.paint(cv.mask().circle(x + dx, y0 + T * yy, 0.9), "#8f8a80", 0.9)
    if exterior:
        cl = band(cv, y0, y0 + clad_h, w)
        ctex = wood_tex(cv.W, cv.H, rng(cv.name + "clad"), CLAD, mix(CLAD, "#000000", 0.5),
                        mix(CLAD, "#ffffff", 0.12), rings=int(cv.H / (3 * SS)))
        cv.paint(cl, ctex)
        x = r.random() * 60
        while x < w:
            cv.stroke([(x, y0), (x, y0 + clad_h)], 0.7, INK, 0.9)
            x += 90 + r.random() * 120
        cv.stroke([(-2, y0 + clad_h), (w + 2, y0 + clad_h)], 0.9, INK, 0.9)
    # drywall faces (with a crisp skirting line)
    faces = [(y1 - dry_h, y1)] + ([] if exterior else [(y0, y0 + dry_h)])
    for (a, b) in faces:
        dm = band(cv, a, b, w)
        nz = cv.noise(40, 2, 3, seed=f"dry{a}")
        cv.paint(dm, col(DRY)[None, None, :] * (0.95 + 0.08 * nz[..., None]))
        edge = b - 1.2 if b == y1 else a + 1.2
        cv.stroke([(-2, edge), (w + 2, edge)], 0.6, "#f4efe4", 0.7)
        cv.stroke([(-2, a if b == y1 else b), (w + 2, a if b == y1 else b)], 0.9, INK, 0.9)
    # paint grime / damp near the bottom of the drywall
    cv.vary(whole, 0.08, 12, 2)
    return whole


def _outline(cv, y0, y1, w=L, width=1.8):
    for y in (y0, y1):
        m = cv.mask().line([(-4, y), (w + 4, y)], width)
        cv.paint(dilate(m.arr, 0.3 * cv.ss, True, cv.wob()), INK)


# --------------------------------------------------------------------------
# damage
# --------------------------------------------------------------------------
def _split(cv, x, y, length, ang, width, rnd, color=RAW, op=1.0):
    """A pale split in the timber with a dark inked edge."""
    pts = [(x, y)]
    a = ang
    for _ in range(int(length / 3)):
        a += rnd.normal(0, 0.25)
        x += math.cos(a) * 3
        y += math.sin(a) * 3
        pts.append((x, y))
    m = cv.mask().line(pts, width + 1.2)
    cv.paint(m, INK, 0.9 * op)
    cv.paint(cv.mask().line(pts, width * 0.6), color, 0.9 * op)
    return pts


def _splinter(cv, x, y, ang, length, width, rnd, color=RAW):
    """A wedge-shaped splinter sticking out, inked."""
    ca, sa = math.cos(ang), math.sin(ang)
    nx, ny = -sa, ca
    tip = (x + ca * length, y + sa * length)
    pts = [(x + nx * width, y + ny * width), tip, (x - nx * width, y - ny * width)]
    m = cv.mask().poly(pts, wobble=0.2)
    cv.paint(dilate(m.arr, 0.9 * cv.ss, True), INK)
    cv.paint(m, mix(color, "#000000", rnd.random() * 0.25))
    cv.stroke([(x, y), ((x + tip[0]) / 2, (y + tip[1]) / 2)], 0.4, RAW_DK, 0.8)


def _chip(cv, x, y, rx, ry, rnd, fill):
    m = cv.mask().ellipse(x, y, rx, ry, wobble=min(rx, ry) * 0.35, rot=rnd.random() * 180)
    cv.paint(dilate(m.arr, 0.8 * cv.ss, True), INK)
    cv.paint(m, fill)


def _cracked(cv, y0, y1, exterior, w=L):
    r = rng(cv.name + "cracks")
    T = y1 - y0
    clad_h = 7.0 if exterior else 0.0
    dry_h = 6.0 if exterior else 3.2
    inside = band(cv, y0, y1, w).arr
    # chipped drywall faces: bites INTO the face that expose the brown plate behind
    faces = [(y1 - dry_h, y1)] + ([] if exterior else [(y0, y0 + dry_h)])
    for (a, b) in faces:
        x = r.random() * 30
        while x < w:
            rx = 4 + r.random() * 7
            yc = b if b == y1 else a
            m = cv.mask().ellipse(x, yc, rx, dry_h * (0.6 + 0.4 * r.random()), wobble=1.0, rot=r.random() * 20).arr * inside
            cv.paint(dilate(m, 0.7 * cv.ss, True) * inside, INK, 0.9)
            cv.paint(m, mix(RAW_DK, CORE, 0.5))
            cv.paint(erode_safe(m, 1.2 * cv.ss) , mix(CAVITY, CORE, 0.3))
            x += 16 + r.random() * 30
    if exterior:
        x = r.random() * 40
        while x < w:
            m = cv.mask().ellipse(x, y0, 2.5 + r.random() * 5, 4.0, wobble=0.8).arr * inside
            cv.paint(dilate(m, 0.7 * cv.ss, True) * inside, INK, 0.9)
            cv.paint(m, mix(RAW_DK, CAVITY, 0.3))
            x += 40 + r.random() * 60
    # splits along the plate grain, fresh raw wood showing
    for _ in range(int(w / 11)):
        x = r.random() * w
        y = y0 + clad_h + 3 + r.random() * (T - clad_h - dry_h - 6)
        _split(cv, x, y, 14 + r.random() * 30, r.normal(0, 0.08) + (math.pi if r.random() < 0.5 else 0),
               1.0 + r.random() * 0.8, r)
    # hairline cross cracks (ink only)
    for _ in range(int(w / 20)):
        x = r.random() * w
        pts = [(x, y0 + 1)]
        yy = y0 + 1
        while yy < y1 - 1:
            yy += 2.5
            pts.append((pts[-1][0] + r.normal(0, 1.2), yy))
        cv.paint(cv.mask().line(pts, 0.7), INK, 0.9)
    # a few splinters poking into the margins
    for _ in range(int(w / 30)):
        x = r.random() * w
        if r.random() < 0.5:
            _splinter(cv, x, y1 - 0.5, math.pi / 2 + r.normal(0, 0.5), 3 + r.random() * 3, 0.9, r)
        else:
            _splinter(cv, x, y0 + 0.5, -math.pi / 2 + r.normal(0, 0.5), 3 + r.random() * 3, 0.9, r)
    # plaster specks
    for _ in range(int(w / 6)):
        cv.paint(cv.mask().circle(r.random() * w, y0 + r.random() * T, 0.5 + r.random() * 0.6), DRY, 0.7)


def erode_safe(m, rpx):
    from core import erode
    return np.clip(erode(m, rpx, True), 0, 1)


def _broken(cv, y0, y1, exterior, w=L):
    """Torn-open wall: cavity with raw studs and insulation, splintered plate."""
    r = rng(cv.name + "broken")
    T = y1 - y0
    # ragged outline of what's left: rebuild the cap as a jagged band
    def ragged(y, amp, step=5):
        pts = []
        x = -6
        while x < w + 6:
            pts.append((x, y + r.normal(0, amp)))
            x += step + r.random() * step
        return pts
    top = ragged(y0 + 1.5, 1.6)
    bot = ragged(y1 - 1.5, 1.6)
    cav = cv.mask().poly(top + bot[::-1])
    # everything inside the wall becomes a dark cavity first
    cv.paint(band(cv, y0 - 1, y1 + 1, w), CAVITY)
    cv.hatch(band(cv, y0, y1, w).arr, 45, 2.0, 0.5, 0.45, color=(0, 0, 0))
    # insulation tufts
    for _ in range(int(w / 7)):
        x = r.random() * w
        y = y0 + 3 + r.random() * (T - 6)
        m = cv.mask()
        for k in range(4):
            m.ellipse(x + r.normal(0, 2.5), y + r.normal(0, 1.2), 1.6 + r.random() * 2.2, 1.2 + r.random() * 1.4, wobble=0.6)
        cv.paint(blur(m.arr, 0.8 * cv.ss), mix(INSUL, "#ffffff", r.random() * 0.25), 0.75)
        cv.hatch(m.arr, 30, 1.6, 0.35, 0.35, color=(90, 70, 40))
    # studs (raw pale timber across the wall) every ~0.4 m
    x = r.random() * 20
    while x < w:
        sw = 4.5 + r.random()
        m = cv.mask().rect(x - sw / 2, y0 - 0.5 + r.random(), x + sw / 2, y1 + 0.5 - r.random(), 0.5, wobble=0.25)
        tex = wood_tex(cv.W, cv.H, rng(f"stud{x:.0f}"), RAW, RAW_DK, "#e0c08e", vertical=True, rings=60)
        cv.paint(dilate(m.arr, 1.0 * cv.ss, True), INK)
        cv.paint(m, tex)
        cv.stroke([(x + sw / 2 - 0.8, y0 + 1), (x + sw / 2 - 0.8, y1 - 1)], 0.5, RAW_DK, 0.8)
        x += 46 + r.random() * 12
    # remains of the plate: splintered dark boards hanging on at random
    x = r.random() * 30
    while x < w:
        ln = 18 + r.random() * 40
        yy = y0 + (T * (0.2 + 0.6 * r.random()))
        ang = r.normal(0, 0.12)
        hw = 2.2 + r.random() * 2.5
        ca, sa = math.cos(ang), math.sin(ang)
        jag = [(x + ca * ln + sa * hw * 0.3, yy + sa * ln - ca * hw * 0.3)]
        pts = [(x - sa * hw, yy + ca * hw), (x + sa * hw, yy - ca * hw),
               (x + ca * ln * 0.8 + sa * hw, yy + sa * ln * 0.8 - ca * hw)] + jag + [
            (x + ca * ln * 0.85 - sa * hw, yy + sa * ln * 0.85 + ca * hw)]
        m = cv.mask().poly(pts, wobble=0.3)
        cv.paint(dilate(m.arr, 1.0 * cv.ss, True), INK)
        cv.paint(m, wood_tex(cv.W, cv.H, rng(f"plank{x:.0f}"), CORE, "#1a120c", RAW_DK, rings=40))
        # raw end grain at the broken end
        cv.paint(cv.mask().circle(jag[0][0], jag[0][1], hw * 0.6), RAW, 0.9)
        x += ln + 14 + r.random() * 30
    # drywall shards still hanging on the faces
    faces = [y1] + ([] if exterior else [y0])
    for yb in faces:
        x = r.random() * 20
        while x < w:
            ln = 6 + r.random() * 14
            sgn = -1 if yb == y1 else 1
            pts = [(x, yb), (x + ln, yb + r.normal(0, 0.6)), (x + ln * 0.6, yb + sgn * (2 + r.random() * 3))]
            m = cv.mask().poly(pts, wobble=0.2)
            cv.paint(dilate(m.arr, 0.8 * cv.ss, True), INK)
            cv.paint(m, DRY)
            x += ln + 6 + r.random() * 16
    if exterior:
        x = r.random() * 20
        while x < w:
            ln = 10 + r.random() * 22
            pts = [(x, y0 - 0.5), (x + ln, y0 - 0.5 + r.normal(0, 0.8)), (x + ln * 0.7, y0 + 4 + r.random() * 2), (x + 2, y0 + 5)]
            m = cv.mask().poly(pts, wobble=0.3)
            cv.paint(dilate(m.arr, 0.9 * cv.ss, True), INK)
            cv.paint(m, wood_tex(cv.W, cv.H, rng(f"clad{x:.0f}"), CLAD, "#101214", "#4a5056", rings=50))
            x += ln + 8 + r.random() * 20
    # splinters out into the margins on both sides
    for _ in range(int(w / 16)):
        x = r.random() * w
        if r.random() < 0.5:
            _splinter(cv, x, y1 - 1, math.pi / 2 + r.normal(0, 0.6), 5 + r.random() * 6, 1.3, r)
        else:
            _splinter(cv, x, y0 + 1, -math.pi / 2 + r.normal(0, 0.6), 5 + r.random() * 6, 1.3, r)
    # plaster dust
    d = smoothstep(0.5, 0.9, cv.noise(30, 3, 3, seed="dust")) * band(cv, y0, y1, w).arr
    cv.screen(d, 0.3, (200, 190, 175))


def wall_set(prefix, T, exterior):
    for state in ("", "_cracked", "_broken"):
        name = prefix + state
        cv, y0, y1 = strip_canvas(name, T)
        if state == "_broken":
            _broken(cv, y0, y1, exterior)
            cv.grain(0.06)
        else:
            _base_strip(cv, y0, y1, exterior)
            _outline(cv, y0, y1)
            if state == "_cracked":
                _cracked(cv, y0, y1, exterior)
            cv.grain(0.06)
        crop_save(cv, name, T)


# --------------------------------------------------------------------------
# windows: one 1 m pane (128 px) in an exterior wall, 4 states
# --------------------------------------------------------------------------
FRAME = "#26292d"
GLASS = "#8fa6b2"


def _window_base(cv, y0, y1, w):
    T = y1 - y0
    # jambs at both ends (cap continues 6 px each side)
    whole = cv.mask().rect(0, y0, w, y1)
    cv.paint(whole, FRAME)
    tex = wood_tex(cv.W, cv.H, rng(cv.name + "frame"), FRAME, "#0d0e10", "#3d4248", rings=60)
    cv.paint(whole, tex)
    # interior sill board (pale painted) on the inside face
    sill = cv.mask().rect(3, y1 - 7, w - 3, y1)
    cv.paint(sill, "#dcd6c8")
    cv.stroke([(3, y1 - 7), (w - 3, y1 - 7)], 0.8, INK, 0.9)
    cv.stroke([(3, y1 - 1.5), (w - 3, y1 - 1.5)], 0.5, "#f6f1e6", 0.8)
    # glass band
    g0, g1 = y0 + 9, y0 + 17
    return g0, g1


def _glass(cv, x0, x1, g0, g1, state, r):
    gm = cv.mask().rect(x0, g0, x1, g1)
    if state in ("intact", "cracked"):
        grad = np.linspace(0, 1, cv.W)[None, :] * np.ones((cv.H, 1))
        gl = col(GLASS)[None, None, :] * (0.85 + 0.25 * grad[..., None])
        cv.paint(gm, gl)
        # gloss streaks
        for gx in (x0 + 10, x0 + 16, (x0 + x1) / 2 + 12):
            cv.stroke([(gx, g1 - 1), (gx + 5, g0 + 1)], 1.0, "#f2fbff", 0.7)
        if state == "cracked":
            for cx in (x0 + (x1 - x0) * 0.35, x0 + (x1 - x0) * 0.72):
                cy = (g0 + g1) / 2
                for k in range(9):
                    a = k * 2 * math.pi / 9 + r.normal(0, 0.2)
                    ln = 4 + r.random() * 12
                    cv.stroke([(cx, cy), (cx + math.cos(a) * ln, cy + math.sin(a) * ln * 0.5)], 0.45, "#f8fdff", 0.95)
                cv.stroke(ellipse_pts(cx, cy, 4, 2.4, 14) + [ellipse_pts(cx, cy, 4, 2.4, 14)[0]], 0.4, "#f8fdff", 0.8)
                cv.paint(cv.mask().circle(cx, cy, 1.0), INK)
    else:
        cv.paint(gm, "#0f1214")
        # shard teeth on both frame edges
        x = x0
        while x < x1:
            ln = 3 + r.random() * 5
            for (yy, sg) in ((g0, 1), (g1, -1)):
                if r.random() < 0.7:
                    pts = [(x, yy), (x + ln, yy), (x + ln * (0.3 + 0.4 * r.random()), yy + sg * (1.5 + r.random() * 3))]
                    cv.paint(cv.mask().poly(pts), "#a9c0cb", 0.85)
                    cv.stroke([pts[0], pts[2]], 0.3, "#eef8ff", 0.8)
            x += ln + r.random() * 3
    cv.stroke([(x0, g0), (x1, g0)], 0.7, INK, 0.9)
    cv.stroke([(x0, g1), (x1, g1)], 0.7, INK, 0.9)


def window_set():
    w = 128
    T = 40
    for state in ("intact", "cracked", "shattered", "broken"):
        name = "window" if state == "intact" else f"window_{state}"
        cv, y0, y1 = strip_canvas(name, T, w)
        cv.tile = True
        r = rng(name)
        g0, g1 = _window_base(cv, y0, y1, w)
        _glass(cv, 7, w - 7, g0, g1, state, r)
        # mullion (centre post of the frame)
        cv.paint(cv.mask().rect(w / 2 - 2, y0, w / 2 + 2, y1 - 7), FRAME)
        cv.stroke([(w / 2 - 2, y0), (w / 2 - 2, y1 - 7)], 0.6, INK, 0.9)
        cv.stroke([(w / 2 + 2, y0), (w / 2 + 2, y1 - 7)], 0.6, INK, 0.9)
        # jamb lines
        for x in (7, w - 7):
            cv.stroke([(x, y0), (x, y1 - 7)], 0.7, INK, 0.9)
        if state == "broken":
            _cracked(cv, y0, y1, True, w)
            for _ in range(5):
                x = 6 + r.random() * (w - 12)
                yy = y0 + 2 + r.random() * (T - 4)
                _split(cv, x, yy, 10 + r.random() * 16, r.normal(0, 0.3), 1.0, r)
            # bent frame chunks
            for x in (20 + r.random() * 20, 80 + r.random() * 20):
                _chip(cv, x, (g0 + g1) / 2, 7, 5, r, CAVITY)
        _outline(cv, y0, y1, w, 1.6)
        cv.grain(0.05)
        img = cv.image()
        # windows are not tileable: the canvas wrap only helped the margins
        img = img.crop((0, PAD, img.width, PAD + T + 2 * M))
        save(img, name)


# --------------------------------------------------------------------------
# post (end grain), fence, door leaf
# --------------------------------------------------------------------------
def wall_post():
    S = 40
    cv = Canvas(S + 2 * M, S + 2 * M, SS, name="wall_post")
    m = cv.mask().rect(M, M, M + S, M + S, 1.0, wobble=0.3)
    tex = wood_tex(cv.W, cv.H, rng("post"), "#3d322b", "#1a1310", "#4f4238", rings=20)
    cv.part(m, tex, ow=1.8, shade=0.35, light=0.0, hatch=0.4, depth=3)
    c = M + S / 2
    for k, rr in enumerate((15, 11, 7, 3.5)):
        pts = ellipse_pts(c + 3, c + 2, rr, rr * 0.9, 40)
        cv.stroke(pts + [pts[0]], 0.5, "#2a201a", 0.8)
    for _ in range(3):
        a = cv.rnd.random() * 2 * math.pi
        cv.stroke([(c, c), (c + math.cos(a) * 16, c + math.sin(a) * 16)], 0.5, INK, 0.7)
    cv.grain(0.06)
    save(cv.image(), "wall_post")


def fence():
    """Weathered timber privacy fence seen from above, tileable in x: 512 x 32
    (fence body 0.125 m = 16 px between 8 px margins). Posts every 2 m."""
    T = 16
    cv, y0, y1 = strip_canvas("fence", T)
    r = cv.rnd
    x = 0.0
    while x < L:
        bw = 11 + r.random() * 3
        m = cv.mask().rect(x + 0.6, y0 + 3 + r.normal(0, 0.3), x + bw - 0.6, y1 - 3 + r.normal(0, 0.3), 0.6, wobble=0.15)
        tex = wood_tex(cv.W, cv.H, rng(f"fence{x:.0f}"), "#6b645a", "#2e2a25", "#857e72", vertical=True, rings=30)
        cv.paint(dilate(m.arr, 0.9 * cv.ss, True), INK)
        cv.paint(m, mix(tex, np.array([60, 66, 58], np.float32), 0.1 * r.random()))
        x += bw
    rail = cv.mask().rect(-2, y0 + 1.5, L + 2, y0 + 4)
    cv.paint(dilate(rail.arr, 0.6 * cv.ss, True), INK)
    cv.paint(rail, "#4e4840")
    for px in (0, 256):
        m = cv.mask().rect(px - 9, y0, px + 9, y1, 1.0, wobble=0.3)
        cv.part(m, wood_tex(cv.W, cv.H, rng(f"fp{px}"), "#564e45", "#221e1a", "#6e655a", rings=12),
                ow=1.6, shade=0.0, light=0.0, hatch=0.3, depth=2)
        cv.paint(cv.mask().circle(px, (y0 + y1) / 2, 2.0), "#2a2520")
    cv.grain(0.07)
    crop_save(cv, "fence", T)


def door_leaf():
    """Flush modern door, 0.9 m x 0.05 m, hinge at the LEFT end (x=0 of the leaf)."""
    w, h = 116, 7
    cv = Canvas(w + 2 * M, h + 2 * M, SS, name="door_leaf")
    m = cv.mask().rect(M, M, M + w, M + h, 1.0, wobble=0.2)
    cv.part(m, "#d7d1c4", ow=1.6, shade=0.25, light=0.2, hatch=0.25, depth=1.5)
    # lever handle near the free end, both faces
    for yy, sg in ((M - 0.5, -1), (M + h + 0.5, 1)):
        hm = cv.mask().rect(M + w - 14, yy + sg * 0.2 - 1.2, M + w - 5, yy + sg * 0.2 + 1.2, 1.0)
        cv.part(hm, "#2a2a2c", ow=0.8, shade=0.0, light=0.3, hatch=0, depth=0.8)
    # hinge knuckles
    for xx in (M + 1.5,):
        cv.paint(cv.mask().circle(xx, M + h / 2, 2.2), "#55524c")
    cv.grain(0.05)
    save(cv.image(), "door_leaf")


def build_all():
    print("walls")
    wall_set("wall_ext", 40, True)
    wall_set("wall_int", 26, False)
    window_set()
    wall_post()
    fence()
    door_leaf()


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        for f in sys.argv[1:]:
            globals()[f]()
    else:
        build_all()
