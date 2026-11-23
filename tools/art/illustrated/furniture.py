"""Contemporary furniture, yard props, eerie details, debris and light fixtures.

Every sprite is authored at 128 px per meter, front facing +Y (down), with an
8 px transparent margin around the footprint; the game rotates it in 90 degree
steps and adds the soft drop shadow at runtime (none is baked here).
Helpers (cushion, groove, knob, book, paper) are adapted from The Witchening
Tales tools/art/furniture.py (the user's own project); the pieces are new and
modern: no Gothic furniture, no period details.
"""
from __future__ import annotations

import math

import numpy as np

from core import (Canvas, INK, blur, catmull, col, dilate, ellipse_pts, fabric_tex, fbm, gradient, mix, noise_tex,
                  radial, rng, rrect_pts, save, smoothstep, wood_tex, edge_band, PPM)

MG = 8

WOODS = {
    "oak": ("#a07a52", "#5a4029", "#bf9a6e"),
    "walnut": ("#5e4130", "#2a1b12", "#7c5a43"),
    "ash": ("#c2a983", "#7d6648", "#d8c4a0"),
    "pine": ("#b08a5c", "#6a4e30", "#caa77a"),
    "grey": ("#7b7670", "#3c3936", "#97918a"),
}
WHITE = "#d9d6ce"
BLACK = "#2a2c30"
STEEL0, STEEL1 = "#d2d5d8", "#7d8389"
ACCENT = "#b0602c"      # rust / burnt orange (one warm accent per room)


def F(name, w_m, h_m, ss=2):
    return Canvas(int(round(w_m * PPM + 2 * MG)), int(round(h_m * PPM + 2 * MG)), ss, name=name)


def box(cv, inset=0.0):
    return MG + inset, MG + inset, cv.w - MG - inset, cv.h - MG - inset


def finish(cv, name, grain=0.06):
    cv.grain(grain)
    save(cv.image(), name)


def wtex(cv, kind="oak", vertical=False, seed="", rings=None):
    base, dark, light = WOODS[kind]
    span = cv.w if vertical else cv.h
    rings = rings or max(4, int(span / 6))
    return wood_tex(cv.W, cv.H, rng(f"{cv.name}:wood:{kind}:{vertical}:{seed}"), base, dark, light,
                    vertical=vertical, rings=rings)


def wood(cv, m, kind="oak", vertical=False, seed="", **kw):
    kw.setdefault("hatch", 0.4)
    kw.setdefault("ow", 3.6)
    kw.setdefault("depth", 4.0)
    return cv.part(m, wtex(cv, kind, vertical, seed), **kw)


def fab(cv, color, amount=0.12, weave=2.0):
    return fabric_tex(cv.W, cv.H, rng(f"{cv.name}:fab:{color}"), color, amount, weave, cv.ss)


def solid(cv, m, fill, ow=3.4, depth=4.0, shade=0.42, light=0.25, hatch=0.4, soft=0.0):
    return cv.part(m, fill, ow=ow, shade=shade, light=light, hatch=hatch, depth=depth, soft=soft)


def steel(cv, ang=45):
    return gradient(cv.W, cv.H, STEEL0, STEEL1, ang)


def groove(cv, pts, w=1.0, op=0.85, light=0.35, closed=False):
    if closed:
        pts = list(pts) + [pts[0]]
    cv.stroke(pts, w, INK, op)
    m = cv.mask().line([(x + w * 0.9, y + w * 0.9) for x, y in pts], w * 0.8)
    cv.screen(m, light)


def groove_rect(cv, x0, y0, x1, y1, w=1.0, op=0.8, r=0):
    groove(cv, rrect_pts(x0, y0, x1, y1, r, 4), w, op, closed=True)


def knob(cv, x, y, r=2.4, color=BLACK):
    cv.part(cv.mask().circle(x, y, r), color, ow=1.2, shade=0.5, light=0.5, hatch=0, depth=1.0)


def cushion(cv, x0, y0, x1, y1, color, r=9, ow=3.0, soft=0.55, seam=True, wobble=0.6, depth=6):
    m = cv.mask().rect(x0, y0, x1, y1, r, wobble=wobble)
    cv.part(m, fab(cv, color), ow=ow, shade=0.38, light=0.28, hatch=0.35, soft=soft, depth=depth)
    if seam:
        g = 4.0
        pts = rrect_pts(x0 + g, y0 + g, x1 - g, y1 - g, max(1, r - 3), 4)
        cv.stroke(pts + [pts[0]], 0.7, mix(color, INK, 0.55), 0.55)
    return m


def book(cv, x, y, w, h, color, rot=0):
    pts = rrect_pts(-w / 2, -h / 2, w / 2, h / 2, 1.0, 3)
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    P = lambda q: [(x + px * c - py * s, y + px * s + py * c) for px, py in q]
    cv.part(cv.mask().poly(P(pts)), fab(cv, color, 0.08), ow=1.6, shade=0.4, light=0.25, hatch=0.3, depth=2.5)
    cv.stroke(P([(-w / 2 + 2.5, -h / 2 + 2), (-w / 2 + 2.5, h / 2 - 2)]), 1.0, "#e6dcc4", 0.9)


def paper(cv, x, y, w, h, rot=0, writing=True, tone="#dedad0"):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    P = lambda q: [(x + px * c - py * s, y + px * s + py * c) for px, py in q]
    cv.part(cv.mask().poly(P([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)])), tone, ow=1.2,
            shade=0.22, light=0.0, hatch=0, depth=1.5)
    if writing:
        rr = rng(f"{cv.name}:paper:{x:.0f}:{y:.0f}")
        yy = -h / 2 + 4
        while yy < h / 2 - 3:
            ln = (w - 8) * (0.45 + 0.55 * rr.random())
            cv.stroke(P([(-w / 2 + 4, yy), (-w / 2 + 4 + ln, yy)]), 0.6, "#4a4640", 0.6)
            yy += 3.4


def mug(cv, x, y, r=5.5, color="#d8d2c4", coffee=True):
    cv.part(cv.mask().circle(x, y, r), color, ow=1.6, shade=0.35, light=0.35, hatch=0, depth=1.5)
    if coffee:
        cv.paint(cv.mask().circle(x, y, r * 0.62), "#3a2618")
    cv.part(cv.mask().rect(x + r - 0.5, y - 1.6, x + r + 3.5, y + 1.6, 1.2), color, ow=1.0, shade=0.2, light=0, hatch=0,
            depth=0.5)


def phone(cv, x, y, rot=0, cracked=False):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    P = lambda q: [(x + px * c - py * s, y + px * s + py * c) for px, py in q]
    cv.part(cv.mask().poly(P(rrect_pts(-5, -9.5, 5, 9.5, 2, 3))), "#16171a", ow=1.4, shade=0.2, light=0.4, hatch=0,
            depth=1)
    cv.paint(cv.mask().poly(P(rrect_pts(-4, -8, 4, 8, 1, 2))), "#2c3540")
    if cracked:
        for a in (20, 140, 260):
            cv.stroke(P([(0.5, -2), (math.cos(math.radians(a)) * 6, -2 + math.sin(math.radians(a)) * 7)]), 0.4,
                      "#c8d4dc", 0.9)


# --------------------------------------------------------------------------
# living room
# --------------------------------------------------------------------------
def sofa():
    cv = F("sofa", 2.4, 0.95)
    x0, y0, x1, y1 = box(cv)
    c = "#5b6470"
    body = cv.mask().rect(x0 + 2, y0 + 4, x1 - 2, y1, 10, wobble=0.5)
    cv.part(body, fab(cv, c), ow=4.0, shade=0.4, light=0.2, hatch=0.4, soft=0.35, depth=7)
    cushion(cv, x0, y0, x1, y0 + 30, mix(c, "#000000", 0.08), r=12, soft=0.6)          # back
    for (ax0, ax1) in ((x0, x0 + 22), (x1 - 22, x1)):                                    # slim arms
        cushion(cv, ax0, y0 + 8, ax1, y1 - 2, mix(c, "#000000", 0.05), r=9, soft=0.6)
    seat_w = (x1 - x0 - 46) / 3
    for i in range(3):
        sx = x0 + 23 + i * seat_w
        cushion(cv, sx + 1, y0 + 30, sx + seat_w - 1, y1 - 4, mix(c, "#ffffff", 0.05), r=7, soft=0.5)
    # back cushions slumped, one mustard pillow (accent) and a crumpled grey throw
    p = cv.mask().rect(x0 + 34, y0 + 20, x0 + 66, y0 + 50, 8, wobble=1.2)
    cv.part(p, fab(cv, "#b88a3a"), ow=2.4, shade=0.4, light=0.3, hatch=0.3, soft=0.5, depth=4)
    th = cv.mask().poly(catmull([(x1 - 120, y0 + 40), (x1 - 80, y0 + 34), (x1 - 40, y0 + 48), (x1 - 30, y1 - 10),
                                 (x1 - 70, y1 - 6), (x1 - 112, y1 - 14)], 8), wobble=1.4)
    cv.part(th, fab(cv, "#8d8a84", 0.18, 1.4), ow=2.2, shade=0.42, light=0.25, hatch=0.45, soft=0.4, depth=5)
    for k in range(4):
        xx = x1 - 108 + k * 20
        cv.stroke(catmull([(xx, y0 + 42), (xx + 6, y0 + 70), (xx + 2, y1 - 12)], 6), 0.8, INK, 0.45)
    phone(cv, x0 + 120, y0 + 72, rot=-20, cracked=True)
    return finish(cv, "sofa")


def armchair():
    cv = F("armchair", 0.9, 0.9)
    x0, y0, x1, y1 = box(cv)
    # walnut shell, rust upholstered seat (the room's accent)
    shell = cv.mask().rect(x0 + 2, y0, x1 - 2, y1 - 6, 30, wobble=0.5)
    wood(cv, shell, "walnut", False, ow=4.0, depth=5)
    cushion(cv, x0 + 12, y0 + 10, x1 - 12, y0 + 40, ACCENT, r=14, soft=0.55)
    cushion(cv, x0 + 16, y0 + 36, x1 - 16, y1 - 12, mix(ACCENT, "#ffffff", 0.06), r=12, soft=0.55)
    for (ax0, ax1) in ((x0 + 2, x0 + 14), (x1 - 14, x1 - 2)):
        cv.stroke([((ax0 + ax1) / 2, y0 + 30), ((ax0 + ax1) / 2, y1 - 14)], 1.0, "#1a120c", 0.6)
    return finish(cv, "armchair")


def coffee_table():
    cv = F("coffee_table", 1.1, 0.6)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 26, wobble=0.3)
    wood(cv, m, "oak", False, ow=3.8)
    groove_rect(cv, x0 + 5, y0 + 5, x1 - 5, y1 - 5, 0.8, 0.5, 22)
    mug(cv, x0 + 30, y0 + 24)
    mug(cv, x0 + 48, y1 - 22, 5.0, "#5f6d74", coffee=False)
    book(cv, x1 - 38, (y0 + y1) / 2 - 2, 30, 40, "#7a3b2e", rot=12)
    book(cv, x1 - 42, (y0 + y1) / 2 + 2, 28, 36, "#2e4048", rot=-8)
    cv.part(cv.mask().rect(x0 + 62, y0 + 30, x0 + 72, y0 + 52, 3), "#1d1e21", ow=1.2, shade=0.2, light=0.4, hatch=0,
            depth=1)   # remote
    return finish(cv, "coffee_table")


def tv_stand():
    cv = F("tv_stand", 2.0, 0.45)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0 + 4, x1, y1, 4, wobble=0.25)
    wood(cv, m, "walnut", False, ow=3.6)
    for k in range(1, 4):
        x = x0 + (x1 - x0) * k / 4
        groove(cv, [(x, y0 + 8), (x, y1 - 4)], 0.8, 0.7)
    # flat TV seen from above: a thin black slab on a foot, tilted off its stand
    tv = cv.mask().poly([(x0 + 40, y0 + 12), (x1 - 46, y0 + 6), (x1 - 46, y0 + 14), (x0 + 40, y0 + 20)])
    cv.part(tv, "#141518", ow=2.4, shade=0.2, light=0.4, hatch=0, depth=1.5)
    cv.part(cv.mask().rect((x0 + x1) / 2 - 22, y0 + 18, (x0 + x1) / 2 + 22, y0 + 30, 3), "#2a2b2f", ow=1.6, shade=0.3,
            light=0.3, hatch=0, depth=1.2)
    # console, cables, a small speaker
    cv.part(cv.mask().rect(x0 + 16, y0 + 24, x0 + 52, y0 + 44, 4), WHITE, ow=1.8, shade=0.35, light=0.3, hatch=0.2,
            depth=2)
    cv.part(cv.mask().circle(x1 - 24, y0 + 30, 10), "#33363b", ow=1.8, shade=0.4, light=0.3, hatch=0.3, depth=2)
    cv.paint(cv.mask().circle(x1 - 24, y0 + 30, 5), "#1a1b1e")
    cv.stroke(catmull([(x0 + 52, y0 + 36), (x0 + 90, y1 + 4), (x0 + 120, y0 + 30)], 10), 1.0, INK, 0.8)
    return finish(cv, "tv_stand")


def floor_lamp():
    cv = F("floor_lamp", 0.4, 0.4)
    x0, y0, x1, y1 = box(cv)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    # linen drum shade from above (the base hides under it), bulb glimpsed inside
    shade = cv.mask().circle(cx, cy, 23)
    cv.part(shade, fab(cv, "#d9cfb8", 0.08), ow=3.2, shade=0.35, light=0.3, hatch=0.3, depth=4)
    cv.paint(cv.mask().circle(cx, cy, 15), "#4a4236")
    cv.part(cv.mask().circle(cx, cy, 6), "#efe6cf", ow=1.2, shade=0.2, light=0.3, hatch=0, depth=1)
    for a in range(0, 360, 90):
        cv.stroke([(cx, cy), (cx + math.cos(math.radians(a + 45)) * 15, cy + math.sin(math.radians(a + 45)) * 15)], 0.8,
                  "#2a2622", 0.8)
    return finish(cv, "floor_lamp")


def bookshelf():
    cv = F("bookshelf", 1.4, 0.4)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 3)
    wood(cv, m, "oak", False, ow=3.8)
    inner = cv.mask().rect(x0 + 6, y0 + 5, x1 - 6, y1 - 3, 1)
    cv.paint(inner, "#2a2119")
    r = cv.rnd
    x = x0 + 8
    pal = ["#6a3b2c", "#2f4650", "#8a7a52", "#3b3b3e", "#a59d8a", "#4d5a3a", "#7d4f5a", "#c4b9a2"]
    while x < x1 - 14:
        bw = 4 + r.random() * 6
        if r.random() < 0.08:
            x += bw * 2   # gap where books were taken
            continue
        depth = 30 + r.random() * 14
        c_ = pal[int(r.integers(0, len(pal)))]
        bm = cv.mask().rect(x, y1 - 4 - depth, x + bw, y1 - 4, 0.8)
        cv.part(bm, fab(cv, c_, 0.06), ow=1.0, shade=0.35, light=0.2, hatch=0.2, depth=1.5)
        x += bw + 0.4
    # a toppled book lying across the others
    book(cv, x0 + 110, y0 + 24, 40, 22, "#a24a2c", rot=-6)
    for k in range(1, 3):
        xx = x0 + (x1 - x0) * k / 3
        cv.paint(cv.mask().rect(xx - 2, y0 + 5, xx + 2, y1 - 3), WOODS["oak"][0])
        cv.stroke([(xx - 2, y0 + 5), (xx - 2, y1 - 3)], 0.8, INK, 0.8)
        cv.stroke([(xx + 2, y0 + 5), (xx + 2, y1 - 3)], 0.8, INK, 0.8)
    return finish(cv, "bookshelf")


def dining_table():
    cv = F("dining_table", 1.6, 0.9)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 8, wobble=0.25)
    wood(cv, m, "ash", False, ow=3.8, depth=4.5)
    for yy in (y0 + (y1 - y0) / 3, y0 + 2 * (y1 - y0) / 3):
        groove(cv, [(x0 + 3, yy), (x1 - 3, yy)], 0.7, 0.45)
    # two place settings, one pushed away, a spilled glass and a vase of dead flowers
    for (px, py) in ((x0 + 50, y0 + 26), (x1 - 56, y1 - 30)):
        cv.part(cv.mask().circle(px, py, 15), "#e2ddd2", ow=1.6, shade=0.3, light=0.35, hatch=0, depth=1.5)
        cv.stroke(ellipse_pts(px, py, 10, 10, 30) + [ellipse_pts(px, py, 10, 10, 30)[0]], 0.6, "#a8a296", 0.8)
    gl = cv.mask().rect(x0 + 82, y1 - 40, x0 + 102, y1 - 32, 3)
    cv.part(gl, "#c9d8de", ow=1.2, shade=0.2, light=0.4, hatch=0, depth=0.8)
    spill = cv.mask().ellipse(x0 + 116, y1 - 30, 18, 9, wobble=2.0)
    cv.paint(spill, "#7e8f96", 0.35)
    vx, vy = (x0 + x1) / 2 + 8, (y0 + y1) / 2 - 6
    cv.part(cv.mask().circle(vx, vy, 9), "#3d4a4c", ow=1.6, shade=0.4, light=0.4, hatch=0.2, depth=1.5)
    for k in range(6):
        a = k * 1.1
        ex, ey = vx + math.cos(a) * 18, vy + math.sin(a) * 14
        cv.stroke(catmull([(vx, vy), ((vx + ex) / 2 + 2, (vy + ey) / 2 - 2), (ex, ey)], 6), 1.0, "#4a4630", 0.9)
        cv.part(cv.mask().ellipse(ex, ey, 3.2, 2.4, rot=a * 57), "#6a4a3a", ow=0.8, shade=0.2, light=0, hatch=0,
                depth=0.5)
    paper(cv, x1 - 30, y0 + 22, 26, 34, rot=14)
    return finish(cv, "dining_table")


def chair():
    cv = F("chair", 0.45, 0.42)
    x0, y0, x1, y1 = box(cv)
    # moulded shell seat (sage) on oak legs; backrest at the top (-Y)
    for (lx, ly) in ((x0 + 6, y0 + 8), (x1 - 6, y0 + 8), (x0 + 6, y1 - 4), (x1 - 6, y1 - 4)):
        cv.part(cv.mask().circle(lx, ly, 3), WOODS["oak"][0], ow=1.4, shade=0.3, light=0.2, hatch=0, depth=1)
    seat = cv.mask().rect(x0 + 3, y0 + 8, x1 - 3, y1 - 1, 16, wobble=0.4)
    cv.part(seat, gradient(cv.W, cv.H, "#7f8c7c", "#5c675a", 45), ow=3.2, shade=0.4, light=0.35, hatch=0.3,
            soft=0.35, depth=4)
    back = cv.mask().poly(catmull([(x0 + 2, y0 + 16), (x0 + 6, y0 + 2), ((x0 + x1) / 2, y0 - 2), (x1 - 6, y0 + 2),
                                   (x1 - 2, y0 + 16)], 8) + [(x1 - 9, y0 + 14), ((x0 + x1) / 2, y0 + 7),
                                                              (x0 + 9, y0 + 14)])
    cv.part(back, "#6a7768", ow=2.8, shade=0.4, light=0.35, hatch=0.3, depth=3)
    return finish(cv, "chair")


def plant():
    cv = F("plant", 0.5, 0.5)
    x0, y0, x1, y1 = box(cv)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    r = cv.rnd
    cv.part(cv.mask().circle(cx, cy, 24), "#c9c3b6", ow=3.0, shade=0.4, light=0.3, hatch=0.3, depth=3)   # white pot
    cv.paint(cv.mask().circle(cx, cy, 19), "#3a2a1e")
    # fiddle-leaf fig, half of it wilted brown
    for k in range(11):
        a = k * 2 * math.pi / 11 + r.normal(0, 0.15)
        d = 16 + r.random() * 10
        lx, ly = cx + math.cos(a) * d, cy + math.sin(a) * d
        dead = k % 3 == 0
        colr = "#7a6a3c" if dead else ("#3f5a34" if k % 2 else "#4d6b3c")
        leaf = cv.mask().ellipse(lx, ly, 13, 8, rot=math.degrees(a), wobble=0.8)
        cv.part(leaf, colr, ow=1.8, shade=0.4, light=0.3, hatch=0.35, depth=2)
        cv.stroke([(cx + math.cos(a) * (d - 10), cy + math.sin(a) * (d - 10)), (cx + math.cos(a) * (d + 9),
                                                                                cy + math.sin(a) * (d + 9))], 0.6,
                  mix(colr, "#000000", 0.5), 0.8)
    for k in range(4):
        a = r.random() * 6.28
        cv.part(cv.mask().ellipse(cx + 30 * math.cos(a), cy + 30 * math.sin(a), 6, 3.5, rot=r.random() * 180), "#806a3a",
                ow=1.0, shade=0.2, light=0, hatch=0, depth=0.5)
    return finish(cv, "plant")


def _rug(name, w_m, h_m, field, line, accent, kind):
    cv = F(name, w_m, h_m)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 4, wobble=0.6)
    if kind == "shag":
        t = fabric_tex(cv.W, cv.H, rng(name), field, 0.2, 1.0, cv.ss)
        cv.part(m, t, ow=2.0, shade=0.25, light=0.2, hatch=0.15, soft=0.4, depth=6)
        r = cv.rnd
        for _ in range(int((x1 - x0) * (y1 - y0) / 30)):
            x, y = x0 + r.random() * (x1 - x0), y0 + r.random() * (y1 - y0)
            a = r.random() * 6.28
            cv.stroke([(x, y), (x + math.cos(a) * 3, y + math.sin(a) * 3)], 0.7,
                      mix(field, "#000000", 0.2 + 0.2 * r.random()), 0.5)
    else:
        t = fabric_tex(cv.W, cv.H, rng(name), field, 0.1, 1.6, cv.ss)
        cv.part(m, t, ow=2.2, shade=0.2, light=0.15, hatch=0.15, soft=0.25, depth=5)
        # flat-weave geometric pattern: border bands, a lattice of thin lines, a few rust blocks
        b = 14
        for k, (o, w_) in enumerate(((b, 3), (b + 7, 1.4))):
            pts = rrect_pts(x0 + o, y0 + o, x1 - o, y1 - o, 2, 2)
            cv.stroke(pts + [pts[0]], w_, line, 0.85)
        step = 46
        xx = x0 + b + 20
        while xx < x1 - b - 10:
            cv.stroke([(xx, y0 + b + 10), (xx, y1 - b - 10)], 1.0, line, 0.5)
            xx += step
        yy = y0 + b + 20
        while yy < y1 - b - 10:
            cv.stroke([(x0 + b + 10, yy), (x1 - b - 10, yy)], 1.0, line, 0.5)
            yy += step
        r = cv.rnd
        for _ in range(int((x1 - x0) * (y1 - y0) / 9000)):
            i = int(r.integers(0, max(1, (x1 - x0 - 2 * b - 40) // step)))
            j = int(r.integers(0, max(1, (y1 - y0 - 2 * b - 40) // step)))
            bx, by = x0 + b + 20 + i * step, y0 + b + 20 + j * step
            cv.paint(cv.mask().rect(bx + 6, by + 6, bx + step - 6, by + step - 6, 1), accent, 0.75)
        # wear and a muddy footprint smear
        n = cv.noise(5, 5, 3, seed="wear")
        cv.mul(smoothstep(0.65, 0.95, n) * m.arr, 0.25, (60, 50, 40))
    return finish(cv, name)


def rug_living():
    return _rug("rug_living", 3.4, 2.9, "#c9c0ae", "#2e2c2b", "#9c5a32", "flat")


def rug_bed():
    return _rug("rug_bed", 2.2, 1.1, "#d6d0c4", "#000000", "#000000", "shag")


def bath_mat():
    return _rug("bath_mat", 0.5, 0.8, "#8f9a9c", "#000000", "#000000", "shag")


# --------------------------------------------------------------------------
# kitchen
# --------------------------------------------------------------------------
def _stone_top(cv, x0, y0, x1, y1, r=3):
    m = cv.mask().rect(x0, y0, x1, y1, r)
    base = noise_tex(cv.W, cv.H, rng(cv.name + "stone"), "#cfccc4", 0.05, 30, 8, 4)
    cv.part(m, base, ow=3.6, shade=0.35, light=0.3, hatch=0.3, depth=4)
    rr = cv.rnd
    for _ in range(int((x1 - x0) / 30)):   # faint veining
        x, y = x0 + rr.random() * (x1 - x0), y0 + rr.random() * (y1 - y0)
        pts = [(x, y)]
        for k in range(6):
            x += 6 + rr.random() * 6
            y += rr.normal(0, 2.5)
            pts.append((x, y))
        cv.tint(cv.mask().line(pts, 0.8).arr * m.arr, "#9a978f", 0.4)
    # backsplash edge at the back (-Y)
    cv.paint(cv.mask().rect(x0, y0, x1, y0 + 5), "#b8b4aa")
    cv.stroke([(x0, y0 + 5), (x1, y0 + 5)], 0.9, INK, 0.8)
    return m


def counter():
    """Authored 1.0 m long; the game draws caps + a tiled middle for any length."""
    cv = F("counter", 1.0, 0.62)
    x0, y0, x1, y1 = box(cv)
    _stone_top(cv, x0, y0, x1, y1)
    # crumbs, a ring stain
    rr = cv.rnd
    for _ in range(14):
        cv.paint(cv.mask().circle(x0 + rr.random() * (x1 - x0), y0 + 10 + rr.random() * (y1 - y0 - 14), 0.8), "#7a6a54", 0.8)
    pts = ellipse_pts(x0 + 70, y0 + 40, 8, 8, 30)
    cv.stroke(pts + [pts[0]], 1.0, "#8a6a4a", 0.35)
    return finish(cv, "counter")


def sink_counter():
    cv = F("sink_counter", 1.0, 0.62)
    x0, y0, x1, y1 = box(cv)
    _stone_top(cv, x0, y0, x1, y1)
    sk = cv.mask().rect(x0 + 18, y0 + 16, x1 - 18, y1 - 10, 8)
    cv.paint(dilate(sk.arr, 1.2 * cv.ss), INK)
    cv.paint(sk, steel(cv, 120))
    cv.mul(edge_band(sk.arr, -4 * cv.ss, -4 * cv.ss, 3 * cv.ss), 0.45)
    cv.paint(cv.mask().circle((x0 + x1) / 2 + 10, (y0 + y1) / 2 + 6, 3.5), "#3a3d40")
    # dirty dishes left in the sink
    for (px, py, rr_) in ((x0 + 40, y0 + 40, 13), (x0 + 50, y0 + 46, 12)):
        cv.part(cv.mask().circle(px, py, rr_), "#e0dbd0", ow=1.4, shade=0.3, light=0.3, hatch=0, depth=1.2)
        cv.paint(cv.mask().ellipse(px + 3, py + 2, 5, 3, wobble=1.0), "#7a5a3a", 0.5)
    mug(cv, x1 - 44, y0 + 46, 5.5, "#b0603a", coffee=False)
    # gooseneck tap from the back
    cv.stroke(catmull([((x0 + x1) / 2, y0 + 3), ((x0 + x1) / 2 + 2, y0 + 14), ((x0 + x1) / 2, y0 + 24)], 8), 3.4, INK, 1)
    cv.stroke(catmull([((x0 + x1) / 2, y0 + 3), ((x0 + x1) / 2 + 2, y0 + 14), ((x0 + x1) / 2, y0 + 24)], 8), 2.0,
              "#c9ccd0", 1)
    return finish(cv, "sink_counter")


def stove():
    cv = F("stove", 0.75, 0.62)
    x0, y0, x1, y1 = box(cv)
    _stone_top(cv, x0, y0, x1, y1)
    g = cv.mask().rect(x0 + 6, y0 + 8, x1 - 6, y1 - 6, 4)
    cv.paint(dilate(g.arr, 1.0 * cv.ss), INK)
    cv.paint(g, gradient(cv.W, cv.H, "#2c2e33", "#141518", 30))
    cv.stroke([(x0 + 12, y0 + 14), (x0 + 40, y0 + 12)], 1.0, "#5a5e66", 0.6)
    for (bx, by, br) in ((x0 + 26, y0 + 28, 14), (x1 - 26, y0 + 28, 11), (x0 + 26, y1 - 22, 11), (x1 - 26, y1 - 22, 14)):
        for k in (1.0, 0.7):
            pts = ellipse_pts(bx, by, br * k, br * k, 36)
            cv.stroke(pts + [pts[0]], 0.8, "#6e727a", 0.8)
    # a pot left on, lid askew
    px, py = x1 - 26, y1 - 22
    cv.part(cv.mask().circle(px, py, 16), steel(cv, 30), ow=2.0, shade=0.35, light=0.4, hatch=0.2, depth=2)
    cv.part(cv.mask().circle(px - 4, py - 3, 13), "#a9adb2", ow=1.4, shade=0.3, light=0.4, hatch=0.1, depth=1.5)
    cv.part(cv.mask().rect(px - 4 - 5, py - 3 - 2, px - 4 + 5, py - 3 + 2, 2), BLACK, ow=1.0, shade=0, light=0.3,
            hatch=0, depth=0.5)
    cv.part(cv.mask().rect(px + 14, py - 2.5, px + 30, py + 2.5, 2), BLACK, ow=1.0, shade=0, light=0.3, hatch=0, depth=0.5)
    return finish(cv, "stove")


def fridge():
    cv = F("fridge", 0.75, 0.7)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 6)
    cv.part(m, steel(cv, 60), ow=3.8, shade=0.4, light=0.4, hatch=0.25, depth=4)
    for k in range(6):   # brushed lines
        y = y0 + 10 + k * (y1 - y0 - 20) / 5
        cv.stroke([(x0 + 6, y), (x1 - 6, y + 1)], 0.5, "#f2f4f5", 0.35)
    cv.paint(cv.mask().rect(x0, y1 - 8, x1, y1), "#8f959b")
    cv.stroke([(x0, y1 - 8), (x1, y1 - 8)], 0.9, INK, 0.8)
    # a cereal box and a paper bag on top
    cv.part(cv.mask().rect(x0 + 14, y0 + 14, x0 + 44, y0 + 26, 1.5), "#b3502e", ow=1.6, shade=0.35, light=0.3,
            hatch=0.2, depth=1.5)
    cv.part(cv.mask().rect(x1 - 40, y0 + 36, x1 - 14, y0 + 62, 2, wobble=0.8), "#a58a62", ow=1.6, shade=0.4,
            light=0.25, hatch=0.3, depth=2)
    return finish(cv, "fridge")


def island():
    cv = F("island", 1.9, 0.85)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 6)
    wood(cv, m, "oak", False, ow=3.8, depth=4.5)
    # butcher-block strips
    for k in range(1, 7):
        y = y0 + (y1 - y0) * k / 7
        cv.stroke([(x0 + 3, y), (x1 - 3, y + cv.rnd.normal(0, 0.4))], 0.6, INK, 0.45)
    # fruit bowl gone bad, a newspaper, scattered keys
    bx, by = x0 + 70, (y0 + y1) / 2
    cv.part(cv.mask().circle(bx, by, 22), "#d0ccc2", ow=2.0, shade=0.35, light=0.35, hatch=0.2, depth=2)
    rr = cv.rnd
    for k in range(6):
        a = k * 1.05
        fx, fy = bx + math.cos(a) * 9, by + math.sin(a) * 9
        colr = ["#6a5a2a", "#8a3a22", "#5a4a26"][k % 3]
        cv.part(cv.mask().circle(fx, fy, 6.5 + rr.random()), colr, ow=1.2, shade=0.4, light=0.25, hatch=0.2, depth=1)
        cv.paint(cv.mask().circle(fx + 1, fy + 1, 2.0), "#3a3220", 0.6)
    paper(cv, x1 - 70, y0 + 46, 62, 44, rot=-9)
    for k in range(3):
        cv.stroke([(x1 - 90 + k * 4, y0 + 30), (x1 - 82 + k * 6, y0 + 22)], 0.6, "#4a4640", 0.7)
    for (kx, ky) in ((x0 + 120, y1 - 30), (x0 + 128, y1 - 26)):
        cv.part(cv.mask().ellipse(kx, ky, 5, 2.5, rot=30), "#b8b2a2", ow=1.0, shade=0.2, light=0.4, hatch=0, depth=0.6)
    cv.stroke(ellipse_pts(x0 + 122, y1 - 34, 5, 5, 20), 1.0, "#8a8a88", 0.9)
    return finish(cv, "island")


def stool():
    cv = F("stool", 0.4, 0.4)
    x0, y0, x1, y1 = box(cv)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for a in (45, 135, 225, 315):
        cv.part(cv.mask().circle(cx + math.cos(math.radians(a)) * 20, cy + math.sin(math.radians(a)) * 20, 2.6), BLACK,
                ow=1.0, shade=0.2, light=0.2, hatch=0, depth=0.6)
    seat = cv.mask().circle(cx, cy, 18)
    wood(cv, seat, "oak", False, ow=3.0, depth=3)
    pts = ellipse_pts(cx, cy, 13, 13, 30)
    cv.stroke(pts + [pts[0]], 0.6, INK, 0.4)
    return finish(cv, "stool")


# --------------------------------------------------------------------------
# bedroom
# --------------------------------------------------------------------------
def bed():
    cv = F("bed", 1.6, 2.1)
    x0, y0, x1, y1 = box(cv)
    frame = cv.mask().rect(x0, y0, x1, y1, 6)
    wood(cv, frame, "ash", True, ow=4.0)
    head = cv.mask().rect(x0 - 1, y0, x1 + 1, y0 + 16, 4)
    cv.part(head, fab(cv, "#6d7480"), ow=3.2, shade=0.4, light=0.3, hatch=0.3, soft=0.4, depth=3)
    mat = cv.mask().rect(x0 + 6, y0 + 16, x1 - 6, y1 - 6, 6)
    cv.part(mat, fab(cv, "#dcd8cf", 0.06), ow=2.2, shade=0.3, light=0.25, hatch=0.2, soft=0.3, depth=3)
    for px in (x0 + 18, (x0 + x1) / 2 + 6):
        cushion(cv, px, y0 + 22, px + (x1 - x0) / 2 - 30, y0 + 58, "#e6e2da", r=12, soft=0.5, ow=2.4)
    # unmade duvet thrown back, a dented pillow, a grey throw slipping off
    duv = cv.mask().poly(catmull([(x0 + 4, y0 + 96), (x0 + 60, y0 + 86), (x1 - 30, y0 + 100), (x1 + 4, y0 + 120),
                                  (x1 + 6, y1 - 20), (x1 - 40, y1 - 4), (x0 + 30, y1 - 8), (x0 + 2, y1 - 30)], 10),
                         wobble=1.6)
    cv.part(duv, fab(cv, "#cfd3d6", 0.1, 1.6), ow=2.8, shade=0.4, light=0.3, hatch=0.4, soft=0.45, depth=7)
    rr = cv.rnd
    for k in range(7):
        x = x0 + 20 + k * 26
        cv.stroke(catmull([(x, y0 + 100 + rr.normal(0, 4)), (x + 8, y0 + 160), (x - 4, y1 - 20)], 8), 0.9, INK, 0.35)
    th = cv.mask().poly(catmull([(x0 - 2, y1 - 90), (x0 + 50, y1 - 70), (x0 + 60, y1 - 4), (x0 - 4, y1 + 2)], 8),
                        wobble=1.2)
    cv.part(th, fab(cv, "#555b63", 0.18), ow=2.4, shade=0.4, light=0.25, hatch=0.45, soft=0.4, depth=4)
    phone(cv, x1 - 60, y0 + 74, rot=30)
    return finish(cv, "bed")


def nightstand():
    cv = F("nightstand", 0.45, 0.42)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 4)
    wood(cv, m, "ash", False, ow=3.4)
    groove(cv, [(x0 + 4, y1 - 8), (x1 - 4, y1 - 8)], 0.8, 0.6)
    cv.part(cv.mask().rect(x0 + 8, y0 + 8, x0 + 30, y0 + 22, 2), "#3a3c40", ow=1.2, shade=0.2, light=0.3, hatch=0,
            depth=0.8)   # glasses case
    cv.stroke(catmull([(x1 - 10, y0 + 30), (x1 - 22, y0 + 34), (x1 - 30, y0 + 28)], 6), 0.8, "#2a2a2a", 0.8)
    return finish(cv, "nightstand")


def wardrobe():
    cv = F("wardrobe", 1.5, 0.62)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 3)
    cv.part(m, noise_tex(cv.W, cv.H, rng("wardrobe"), WHITE, 0.04, 20, 6, 3), ow=3.8, shade=0.38, light=0.3,
            hatch=0.35, depth=4.5)
    cv.paint(cv.mask().rect(x0, y1 - 8, x1, y1), mix(WHITE, "#000000", 0.12))
    cv.stroke([(x0, y1 - 8), (x1, y1 - 8)], 0.9, INK, 0.8)
    # storage box and a rolled duvet on top
    cv.part(cv.mask().rect(x0 + 16, y0 + 10, x0 + 70, y0 + 52, 2), "#a68c66", ow=2.0, shade=0.4, light=0.25,
            hatch=0.3, depth=2)
    cv.stroke([(x0 + 16, y0 + 31), (x0 + 70, y0 + 31)], 1.6, "#c9bfa4", 0.9)
    cushion(cv, x1 - 92, y0 + 14, x1 - 20, y0 + 56, "#8a9096", r=18, soft=0.6, ow=2.2)
    return finish(cv, "wardrobe")


def dresser():
    cv = F("dresser", 1.2, 0.5)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 4)
    wood(cv, m, "walnut", False, ow=3.8)
    # jewelry dish, a framed photo lying face down, a hairbrush
    cv.part(cv.mask().circle(x0 + 26, y0 + 26, 11), "#cbc6bb", ow=1.6, shade=0.3, light=0.35, hatch=0, depth=1.2)
    cv.stroke(ellipse_pts(x0 + 26, y0 + 26, 5, 4, 20, 0, 0, 300), 0.9, "#c8a860", 0.9)
    cv.part(cv.mask().rect(x0 + 60, y0 + 14, x0 + 98, y0 + 44, 1.5), BLACK, ow=1.8, shade=0.3, light=0.3, hatch=0.2,
            depth=1.5)
    cv.paint(cv.mask().rect(x0 + 64, y0 + 18, x0 + 94, y0 + 40), "#3c3a38")
    cv.part(cv.mask().rect(x1 - 50, y0 + 22, x1 - 18, y0 + 32, 4), "#7a5a42", ow=1.4, shade=0.3, light=0.3, hatch=0.2,
            depth=1)
    return finish(cv, "dresser")


# --------------------------------------------------------------------------
# bathroom
# --------------------------------------------------------------------------
def bathtub():
    cv = F("bathtub", 1.7, 0.8)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 18)
    cv.part(m, gradient(cv.W, cv.H, "#eceae4", "#bdbab2", 60), ow=4.0, shade=0.38, light=0.3, hatch=0.3, depth=4)
    inner = cv.mask().rect(x0 + 12, y0 + 12, x1 - 12, y1 - 12, 34)
    cv.paint(dilate(inner.arr, 1.0 * cv.ss), INK)
    cv.paint(inner, gradient(cv.W, cv.H, "#cfd3d2", "#e8e8e2", 45))
    cv.mul(edge_band(inner.arr, -6 * cv.ss, -6 * cv.ss, 4 * cv.ss), 0.5)
    # a grey ring of dried water and the drain
    pts = rrect_pts(x0 + 26, y0 + 24, x1 - 26, y1 - 24, 26, 8)
    cv.stroke(pts + [pts[0]], 1.4, "#8a8a80", 0.35)
    cv.paint(cv.mask().circle(x1 - 34, (y0 + y1) / 2, 4), "#5a5e60")
    cv.stroke(catmull([(x1 - 6, (y0 + y1) / 2), (x1 - 14, (y0 + y1) / 2 - 2), (x1 - 20, (y0 + y1) / 2)], 6), 4.0, INK, 1)
    cv.stroke(catmull([(x1 - 6, (y0 + y1) / 2), (x1 - 14, (y0 + y1) / 2 - 2), (x1 - 20, (y0 + y1) / 2)], 6), 2.4,
              "#d2d5d8", 1)
    return finish(cv, "bathtub")


def toilet():
    cv = F("toilet", 0.7, 0.55)
    x0, y0, x1, y1 = box(cv)
    cx = (x0 + x1) / 2
    tank = cv.mask().rect(cx - 25, y0 + 1, cx + 25, y0 + 22, 4)
    cv.part(tank, gradient(cv.W, cv.H, "#f0eee8", "#c6c3bb", 60), ow=3.2, shade=0.35, light=0.3, hatch=0.25, depth=3)
    cv.part(cv.mask().rect(cx - 6, y0 + 8, cx + 6, y0 + 14, 3), "#b9bcc0", ow=1.0, shade=0, light=0.3, hatch=0,
            depth=0.5)
    bowl = cv.mask().ellipse(cx, y0 + 44, 22, 26)
    cv.part(bowl, gradient(cv.W, cv.H, "#f0eee8", "#c6c3bb", 60), ow=3.2, shade=0.35, light=0.3, hatch=0.25, depth=3)
    seat_open = cv.mask().ellipse(cx, y0 + 46, 14, 18)
    cv.paint(dilate(seat_open.arr, 0.8 * cv.ss), INK)
    cv.paint(seat_open, "#9fb0b4")
    return finish(cv, "toilet")


def vanity():
    cv = F("vanity", 0.9, 0.52)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 4)
    wood(cv, m, "oak", False, ow=3.6)
    basin = cv.mask().ellipse((x0 + x1) / 2, (y0 + y1) / 2 + 4, 30, 20)
    cv.part(basin, "#ecebe6", ow=2.6, shade=0.35, light=0.35, hatch=0.2, depth=3)
    cv.paint(cv.mask().ellipse((x0 + x1) / 2, (y0 + y1) / 2 + 6, 22, 13), "#d0d3d2")
    cv.paint(cv.mask().circle((x0 + x1) / 2, (y0 + y1) / 2 + 8, 2.6), "#5a5e60")
    cv.stroke([((x0 + x1) / 2, y0 + 2), ((x0 + x1) / 2, y0 + 14)], 3.6, INK, 1)
    cv.stroke([((x0 + x1) / 2, y0 + 2), ((x0 + x1) / 2, y0 + 14)], 2.0, "#cdd0d3", 1)
    cv.part(cv.mask().circle(x0 + 16, y0 + 16, 6), "#6f8e98", ow=1.2, shade=0.3, light=0.3, hatch=0, depth=1)
    cv.stroke([(x0 + 14, y0 + 16), (x0 + 22, y0 + 6)], 1.2, "#d6dade", 0.9)
    return finish(cv, "vanity")


# --------------------------------------------------------------------------
# utility room
# --------------------------------------------------------------------------
def water_heater():
    cv = F("water_heater", 0.6, 0.6)
    x0, y0, x1, y1 = box(cv)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    cv.part(cv.mask().circle(cx, cy, 36), gradient(cv.W, cv.H, "#e6e4dd", "#a7a59f", 50), ow=3.6, shade=0.4,
            light=0.35, hatch=0.3, depth=4)
    pts = ellipse_pts(cx, cy, 28, 28, 40)
    cv.stroke(pts + [pts[0]], 0.8, "#8a8882", 0.7)
    for (dx, colr) in ((-12, "#3a5f8a"), (12, "#a03a2a")):     # cold / hot pipes
        cv.stroke([(cx + dx, cy - 6), (cx + dx, y0 - 2)], 5.0, INK, 1)
        cv.stroke([(cx + dx, cy - 6), (cx + dx, y0 - 2)], 3.0, "#b87a4a", 1)
        cv.part(cv.mask().circle(cx + dx, cy - 12, 4.0), colr, ow=1.0, shade=0.2, light=0.3, hatch=0, depth=0.6)
    cv.part(cv.mask().circle(cx, cy + 10, 6), "#5c5e62", ow=1.2, shade=0.3, light=0.3, hatch=0, depth=1)
    return finish(cv, "water_heater")


def workbench():
    cv = F("workbench", 1.8, 0.65)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 3)
    wood(cv, m, "pine", False, ow=3.8)
    rr = cv.rnd
    for _ in range(10):
        x, y = x0 + rr.random() * (x1 - x0), y0 + rr.random() * (y1 - y0)
        cv.paint(cv.mask().ellipse(x, y, 4 + rr.random() * 8, 2 + rr.random() * 4, wobble=1.5), "#3a2c20", 0.25)
    # cordless drill, hammer, a toolbox and a coil of extension cable
    dx, dy = x0 + 40, y0 + 34
    cv.part(cv.mask().rect(dx, dy - 6, dx + 30, dy + 6, 4), "#c06a28", ow=1.8, shade=0.35, light=0.3, hatch=0.2,
            depth=1.5)
    cv.part(cv.mask().rect(dx + 8, dy + 4, dx + 16, dy + 26, 3), BLACK, ow=1.6, shade=0.3, light=0.3, hatch=0, depth=1.2)
    cv.stroke([(dx + 30, dy), (dx + 42, dy)], 1.6, "#8a8d92", 1)
    hx, hy = x0 + 100, y1 - 26
    cv.part(cv.mask().rect(hx, hy - 3, hx + 40, hy + 3, 2), WOODS["oak"][0], ow=1.4, shade=0.3, light=0.2, hatch=0,
            depth=1)
    cv.part(cv.mask().rect(hx + 36, hy - 9, hx + 44, hy + 9, 1.5), "#4a4c50", ow=1.4, shade=0.3, light=0.4, hatch=0,
            depth=1)
    tb = cv.mask().rect(x1 - 90, y0 + 12, x1 - 20, y0 + 50, 4)
    cv.part(tb, "#8d2d24", ow=2.4, shade=0.4, light=0.3, hatch=0.3, depth=2.5)
    cv.stroke([(x1 - 86, y0 + 31), (x1 - 24, y0 + 31)], 1.4, INK, 0.8)
    cv.part(cv.mask().rect(x1 - 66, y0 + 26, x1 - 44, y0 + 36, 3), BLACK, ow=1.0, shade=0, light=0.3, hatch=0, depth=0.5)
    for k, rr_ in enumerate((16, 12, 8)):
        pts = ellipse_pts(x0 + 170, y1 - 28, rr_, rr_ * 0.9, 30)
        cv.stroke(pts + [pts[0]], 2.6, INK, 1)
        cv.stroke(pts + [pts[0]], 1.4, "#e0b23a", 1)
    return finish(cv, "workbench")


def washer():
    cv = F("washer", 0.62, 0.62)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 5)
    cv.part(m, gradient(cv.W, cv.H, "#eeece6", "#c2bfb8", 60), ow=3.6, shade=0.38, light=0.3, hatch=0.3, depth=4)
    cv.paint(cv.mask().rect(x0, y0, x1, y0 + 14), "#d6d3cc")
    cv.stroke([(x0, y0 + 14), (x1, y0 + 14)], 0.9, INK, 0.8)
    cv.part(cv.mask().circle(x1 - 18, y0 + 7, 4.5), "#8a8d92", ow=1.0, shade=0.2, light=0.4, hatch=0, depth=0.5)
    cv.paint(cv.mask().rect(x0 + 10, y0 + 4, x0 + 30, y0 + 10, 1), "#2a3a44")
    # detergent bottle and a sock
    cv.part(cv.mask().rect(x0 + 14, y0 + 30, x0 + 34, y0 + 56, 4), "#3c7a8a", ow=1.6, shade=0.35, light=0.35,
            hatch=0.2, depth=1.5)
    cv.part(cv.mask().poly(catmull([(x1 - 40, y1 - 20), (x1 - 22, y1 - 26), (x1 - 14, y1 - 16), (x1 - 26, y1 - 12)], 6),
                           wobble=0.8), "#6b6f78", ow=1.4, shade=0.3, light=0.2, hatch=0.2, depth=1)
    return finish(cv, "washer")


def shelves():
    cv = F("shelves", 1.6, 0.45)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 2)
    cv.part(m, "#5a5d61", ow=3.4, shade=0.35, light=0.3, hatch=0.3, depth=3)
    wire = cv.mask().rect(x0 + 4, y0 + 4, x1 - 4, y1 - 4)
    cv.paint(wire, "#2b2c2e")
    x = x0 + 6
    while x < x1 - 6:
        cv.stroke([(x, y0 + 4), (x, y1 - 4)], 0.6, "#8a8e92", 0.8)
        x += 6
    # paint cans, a storage tub, a box of jars
    rr = cv.rnd
    for k in range(3):
        cx = x0 + 22 + k * 26
        cv.part(cv.mask().circle(cx, (y0 + y1) / 2, 12), steel(cv, 40), ow=1.8, shade=0.35, light=0.4, hatch=0.2,
                depth=1.5)
        pts = ellipse_pts(cx, (y0 + y1) / 2, 9, 9, 24)
        cv.stroke(pts + [pts[0]], 0.7, "#5a5e64", 0.8)
        cv.paint(cv.mask().ellipse(cx + 3, (y0 + y1) / 2 + 3, 4, 2.6, wobble=0.8), ["#a33a2a", "#3a6a8a", "#c8b060"][k], 0.8)
    cv.part(cv.mask().rect(x0 + 100, y0 + 6, x0 + 150, y1 - 6, 4), "#7d8f9a", ow=2.0, shade=0.35, light=0.35,
            hatch=0.2, depth=2)
    cv.part(cv.mask().rect(x1 - 60, y0 + 8, x1 - 12, y1 - 8, 1.5), "#a68c66", ow=2.0, shade=0.4, light=0.25,
            hatch=0.3, depth=2)
    for j in range(2):
        for i in range(3):
            cv.part(cv.mask().circle(x1 - 52 + i * 15, y0 + 18 + j * 16, 6), "#9ab0a4", ow=1.0, shade=0.2, light=0.4,
                    hatch=0, depth=0.6)
    return finish(cv, "shelves")


def boxes():
    cv = F("boxes", 1.0, 0.7)
    x0, y0, x1, y1 = box(cv)

    def carton(bx0, by0, bx1, by1, rot_seed, open_=False):
        m = cv.mask().rect(bx0, by0, bx1, by1, 2, wobble=0.6)
        cv.part(m, noise_tex(cv.W, cv.H, rng(f"carton{rot_seed}"), "#a88a5e", 0.08, 30, 30, 3), ow=3.0, shade=0.42,
                light=0.25, hatch=0.35, depth=3)
        if open_:
            cv.paint(cv.mask().rect(bx0 + 6, by0 + 6, bx1 - 6, by1 - 6, 1), "#3a2c1e")
            for k in range(4):
                book(cv, bx0 + 16 + k * 12, (by0 + by1) / 2, 10, 26, ["#6a3b2c", "#2f4650", "#8a7a52", "#4d5a3a"][k],
                     rot=8 * (k - 1))
        else:
            cv.paint(cv.mask().rect(bx0, (by0 + by1) / 2 - 3, bx1, (by0 + by1) / 2 + 3), "#c9b98e", 0.9)
            cv.stroke([(bx0, (by0 + by1) / 2), (bx1, (by0 + by1) / 2)], 0.7, INK, 0.6)
            cv.paint(cv.mask().rect(bx0 + 10, by0 + 8, bx0 + 40, by0 + 18, 1), "#e2dccd", 0.9)
            cv.stroke([(bx0 + 13, by0 + 13), (bx0 + 34, by0 + 13)], 0.6, "#3a3630", 0.8)
    carton(x0, y0 + 8, x0 + 62, y1, 1)
    carton(x0 + 56, y0, x1, y0 + 50, 2, open_=True)
    carton(x0 + 70, y0 + 46, x1 - 4, y1, 3)
    return finish(cv, "boxes")


# --------------------------------------------------------------------------
# yard props
# --------------------------------------------------------------------------
def car():
    """Small SUV/hatchback, nose toward +Y, driver's door hanging open."""
    cv = F("car", 2.3, 4.6)
    x0, y0, x1, y1 = box(cv)
    cx = (x0 + x1) / 2
    paint_c = "#4d5864"
    W = 236
    bx0, bx1 = cx - W / 2, cx + W / 2
    by0, by1 = y0 + 14, y1 - 10
    body = cv.mask().poly(catmull([(bx0 + 18, by0), (bx1 - 18, by0), (bx1, by0 + 40), (bx1 + 2, by1 - 90),
                                   (bx1 - 8, by1 - 16), (cx, by1 + 2), (bx0 + 8, by1 - 16), (bx0 - 2, by1 - 90),
                                   (bx0, by0 + 40)], 10), wobble=0.4)
    cv.part(body, gradient(cv.W, cv.H, mix(paint_c, "#ffffff", 0.15), mix(paint_c, "#000000", 0.25), 60), ow=4.6,
            shade=0.4, light=0.3, hatch=0.35, depth=8)
    # roof, glass: rear window (top, -Y), windscreen (+Y)
    roof = cv.mask().rect(bx0 + 26, by0 + 110, bx1 - 26, by1 - 200, 18)
    cv.part(roof, gradient(cv.W, cv.H, mix(paint_c, "#ffffff", 0.08), mix(paint_c, "#000000", 0.2), 60), ow=2.6,
            shade=0.35, light=0.3, hatch=0.3, depth=5)
    for (gy0, gy1) in ((by0 + 52, by0 + 108), (by1 - 198, by1 - 120)):
        g = cv.mask().poly([(bx0 + 30, gy1), (bx1 - 30, gy1), (bx1 - 40, gy0), (bx0 + 40, gy0)])
        cv.part(g, gradient(cv.W, cv.H, "#3a4a56", "#1a2228", 30), ow=2.4, shade=0.2, light=0.5, hatch=0, depth=2)
    # shattered windscreen: radial cracks
    gx, gy = cx + 30, by1 - 150
    for k in range(10):
        a = k * 0.63 + 0.2
        cv.stroke([(gx, gy), (gx + math.cos(a) * 46, gy + math.sin(a) * 26)], 0.7, "#d6e2e8", 0.85)
    for rr_ in (10, 20):
        pts = ellipse_pts(gx, gy, rr_, rr_ * 0.6, 24)
        cv.stroke(pts + [pts[0]], 0.6, "#d6e2e8", 0.6)
    # side windows
    for sx in (bx0 + 20, bx1 - 20):
        cv.stroke([(sx, by0 + 116), (sx, by1 - 206)], 5, INK, 1)
        cv.stroke([(sx, by0 + 116), (sx, by1 - 206)], 3, "#2c3942", 1)
    # bonnet line, headlights, mirrors
    cv.stroke(catmull([(bx0 + 20, by1 - 112), (cx, by1 - 106), (bx1 - 20, by1 - 112)], 10), 1.0, INK, 0.6)
    for sx in (bx0 + 26, bx1 - 26):
        cv.part(cv.mask().ellipse(sx, by1 - 22, 18, 8, rot=(-25 if sx < cx else 25)), "#e6e2d0", ow=1.6, shade=0.2,
                light=0.4, hatch=0, depth=1)
        cv.part(cv.mask().ellipse(sx, by0 + 10, 16, 6), "#7a2018", ow=1.4, shade=0.2, light=0.3, hatch=0, depth=1)
    for (mx, sg) in ((bx0 - 8, -1), (bx1 + 8, 1)):
        cv.part(cv.mask().ellipse(mx, by1 - 214, 9, 6), paint_c, ow=1.8, shade=0.3, light=0.3, hatch=0, depth=1)
    # driver's door hanging open (left side when nose faces +Y is +X... draw on the -X side)
    dx, dy = bx0 + 4, by1 - 200
    door = cv.mask().poly([(dx, dy), (dx - 58, dy + 40), (dx - 64, dy + 34), (dx - 4, dy - 8)])
    cv.part(door, gradient(cv.W, cv.H, mix(paint_c, "#ffffff", 0.1), mix(paint_c, "#000000", 0.3), 30), ow=2.4,
            shade=0.35, light=0.3, hatch=0.3, depth=2)
    # dust and leaves on the roof
    rr = cv.rnd
    for _ in range(18):
        cv.part(cv.mask().ellipse(bx0 + 40 + rr.random() * (W - 80), by0 + 120 + rr.random() * 200, 4, 2.2,
                                  rot=rr.random() * 180), mix("#6a4a2a", "#9a7a3a", rr.random()), ow=0.9, shade=0.2,
                light=0, hatch=0, depth=0.5)
    return finish(cv, "car")


def dead_tree():
    cv = F("dead_tree", 4.6, 4.6)
    cx, cy = cv.w / 2, cv.h / 2
    r = cv.rnd
    branches = cv.mask()

    def grow(x, y, ang, length, width, depth):
        if depth == 0 or width < 0.9:
            return
        pts = [(x, y)]
        a = ang
        n = 6
        for k in range(n):
            a += r.normal(0, 0.18)
            x += math.cos(a) * length / n
            y += math.sin(a) * length / n
            pts.append((x, y))
        branches.curve(pts, width, n=6)
        for k in range(int(r.integers(2, 4))):
            grow(x, y, a + r.normal(0, 0.7), length * (0.55 + 0.2 * r.random()), width * 0.62, depth - 1)
        if r.random() < 0.5:
            mx, my = pts[3]
            grow(mx, my, a + (0.9 if r.random() < 0.5 else -0.9), length * 0.45, width * 0.5, depth - 1)

    for k in range(5):
        a = k * 2 * math.pi / 5 + r.normal(0, 0.3)
        grow(cx, cy, a, 88 + r.random() * 22, 14, 5)
    cv.part(branches, wood_tex(cv.W, cv.H, rng("bark"), "#4a4138", "#1e1a16", "#61574b", rings=200), ow=2.4,
            shade=0.45, light=0.25, hatch=0.45, depth=3)
    trunk = cv.mask().circle(cx, cy, 30, wobble=2.0)
    cv.part(trunk, wood_tex(cv.W, cv.H, rng("trunk"), "#4a4138", "#1e1a16", "#61574b", rings=80), ow=3.6,
            shade=0.5, light=0.3, hatch=0.5, depth=6)
    for rr_ in (20, 12, 5):
        pts = ellipse_pts(cx + 2, cy + 1, rr_, rr_ * 0.9, 40)
        cv.stroke(pts + [pts[0]], 0.7, "#2a241e", 0.6)
    for _ in range(26):   # a few dead leaves clinging on
        a = r.random() * 6.28
        d = 80 + r.random() * 160
        cv.part(cv.mask().ellipse(cx + math.cos(a) * d, cy + math.sin(a) * d, 5, 3, rot=r.random() * 180),
                mix("#5a3e22", "#8a6a36", r.random()), ow=1.0, shade=0.2, light=0, hatch=0, depth=0.5)
    return finish(cv, "dead_tree")


def trash_bin():
    """Wheelie bin knocked over, lid open toward +Y, rubbish spilling out."""
    cv = F("trash_bin", 0.6, 0.9)
    x0, y0, x1, y1 = box(cv)
    body = cv.mask().rect(x0 + 2, y0 + 4, x1 - 2, y1 - 36, 6, wobble=0.3)
    cv.part(body, gradient(cv.W, cv.H, "#4d5c4a", "#2a3329", 60), ow=3.6, shade=0.4, light=0.3, hatch=0.35, depth=4)
    for k in range(4):
        y = y0 + 16 + k * 18
        cv.stroke([(x0 + 8, y), (x1 - 8, y)], 0.7, INK, 0.45)
    for wx in (x0 + 10, x1 - 10):
        cv.part(cv.mask().circle(wx, y0 + 6, 8), "#1c1d1f", ow=1.6, shade=0.3, light=0.3, hatch=0, depth=1)
    lid = cv.mask().poly([(x0 - 4, y1 - 34), (x1 + 4, y1 - 34), (x1 + 8, y1 - 8), (x0 - 8, y1 - 8)], wobble=0.4)
    cv.part(lid, gradient(cv.W, cv.H, "#55654f", "#303a2e", 60), ow=3.0, shade=0.35, light=0.3, hatch=0.3, depth=2)
    rr = cv.rnd
    for k in range(5):
        x = x0 + 10 + rr.random() * (x1 - x0 - 20)
        y = y1 - 30 + rr.random() * 26
        cv.part(cv.mask().ellipse(x, y, 10 + rr.random() * 6, 7 + rr.random() * 4, wobble=1.5), "#1c1c1e", ow=1.6,
                shade=0.3, light=0.45, hatch=0.1, depth=1.5)
    return finish(cv, "trash_bin")


def mailbox():
    cv = F("mailbox", 0.3, 0.3)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0 + 4, y0 + 2, x1 - 4, y1 - 2, 8)
    cv.part(m, gradient(cv.W, cv.H, "#3a3d42", "#1d1f22", 60), ow=3.2, shade=0.35, light=0.35, hatch=0.25, depth=2.5)
    cv.stroke([((x0 + x1) / 2, y0 + 4), ((x0 + x1) / 2, y1 - 4)], 0.8, "#55595e", 0.9)
    cv.part(cv.mask().rect(x1 - 6, y0 + 8, x1 + 2, y0 + 22, 1), "#b8332a", ow=1.2, shade=0.2, light=0.3, hatch=0,
            depth=0.6)
    paper(cv, (x0 + x1) / 2, y1 + 1, 14, 9, rot=6, writing=False)
    return finish(cv, "mailbox")


def streetlight():
    """Pole at the canvas centre; the arm reaches +Y over the road (lamp dead)."""
    cv = F("streetlight", 0.8, 4.4)
    cx, cy = cv.w / 2, cv.h / 2
    cv.part(cv.mask().circle(cx, cy, 12), "#4a4d52", ow=2.6, shade=0.4, light=0.35, hatch=0.3, depth=2)
    arm = cv.mask().curve([(cx, cy), (cx + 6, cy + 90), (cx + 2, cy + 200)], 5, n=10)
    cv.part(arm, "#55585d", ow=2.0, shade=0.3, light=0.3, hatch=0.2, depth=1.5)
    head = cv.mask().rect(cx - 16, cy + 196, cx + 16, cy + 250, 10)
    cv.part(head, gradient(cv.W, cv.H, "#5f6368", "#2f3236", 60), ow=2.8, shade=0.35, light=0.35, hatch=0.3, depth=2)
    cv.paint(cv.mask().rect(cx - 10, cy + 206, cx + 10, cy + 240, 6), "#2a3034")
    cv.stroke([(cx - 6, cy + 212), (cx + 4, cy + 234)], 0.6, "#8a969e", 0.8)
    return finish(cv, "streetlight")


# --------------------------------------------------------------------------
# eerie details (decor), debris, fixtures
# --------------------------------------------------------------------------
def papers():
    cv = F("papers", 0.85, 0.6)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    for k in range(6):
        x = x0 + 20 + rr.random() * (x1 - x0 - 40)
        y = y0 + 18 + rr.random() * (y1 - y0 - 36)
        paper(cv, x, y, 26, 34, rot=rr.normal(0, 40), tone=mix("#e2ddd0", "#c9c2ae", rr.random()))
    cv.paint(cv.mask().ellipse(x0 + 60, y0 + 40, 16, 10, wobble=3), "#5a4632", 0.3)   # a muddy print
    return finish(cv, "papers")


def shoe():
    cv = F("shoe", 0.34, 0.2)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().poly(catmull([(x0, (y0 + y1) / 2), (x0 + 6, y0 + 2), (x1 - 12, y0), (x1, (y0 + y1) / 2 - 2),
                                (x1 - 10, y1), (x0 + 8, y1 - 2)], 8))
    cv.part(m, "#d8d6d0", ow=2.4, shade=0.4, light=0.3, hatch=0.3, depth=2.5)
    cv.paint(cv.mask().ellipse(x0 + 18, (y0 + y1) / 2, 10, 6), "#3a3632")
    for k in range(4):
        x = x0 + 30 + k * 5
        cv.stroke([(x, y0 + 5), (x + 2, y1 - 5)], 0.8, "#b0302a", 0.9)
    cv.stroke(catmull([(x0 + 2, (y0 + y1) / 2 + 4), (x0 + 30, y1 - 2), (x1 - 8, y1 - 4)], 6), 1.4, "#9a3a2a", 0.8)
    return finish(cv, "shoe")


def toy():
    """A red plastic toy dump truck tipped on the lawn (one small saturated accent)."""
    cv = F("toy", 0.5, 0.34)
    x0, y0, x1, y1 = box(cv)
    cab = cv.mask().rect(x1 - 20, y0 + 4, x1, y1 - 4, 4)
    cv.part(cab, "#c0302a", ow=2.4, shade=0.35, light=0.35, hatch=0.2, depth=2)
    cv.paint(cv.mask().rect(x1 - 16, y0 + 10, x1 - 6, y1 - 10, 2), "#3a4a56")
    bed_ = cv.mask().poly([(x0, y0 + 2), (x1 - 22, y0 + 6), (x1 - 22, y1 - 6), (x0 + 4, y1 - 2)])
    cv.part(bed_, "#e0b030", ow=2.4, shade=0.35, light=0.35, hatch=0.2, depth=2)
    for wx in (x0 + 10, x1 - 12):
        for wy in (y0 - 1, y1 + 1):
            cv.part(cv.mask().ellipse(wx, wy, 6, 3), "#1c1c1e", ow=1.2, shade=0.2, light=0.3, hatch=0, depth=0.5)
    return finish(cv, "toy")


def mud_trail():
    """Muddy shoe prints walking toward +X (2.6 m), fading as the mud wears off."""
    cv = F("mud_trail", 2.6, 0.6)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    cy = (y0 + y1) / 2
    x = x0 + 14
    k = 0
    while x < x1 - 24:
        side = 1 if k % 2 else -1
        y = cy + side * 11 + rr.normal(0, 1.5)
        op = 0.75 - 0.4 * (x - x0) / (x1 - x0)
        a = math.radians(rr.normal(0, 5) + side * 4)
        ca, sa = math.cos(a), math.sin(a)
        P = lambda px, py: (x + px * ca - py * sa, y + px * sa + py * ca)
        m = cv.mask()
        m.poly([P(*q) for q in ellipse_pts(10, 0, 11, 5.2, 24)])      # forefoot
        m.poly([P(*q) for q in ellipse_pts(-9, 0, 6.5, 4.3, 20)])      # heel
        m.poly([P(-3, -2.8), P(3, -3.6), P(3, 3.6), P(-3, 2.8)])        # waist
        sole = blur(m.arr, 0.5 * cv.ss)
        cv.paint(sole, "#3a2a1c", op)
        for t in range(4):   # tread lines
            cv.stroke([P(4 + t * 4, -3.5), P(4 + t * 4, 3.5)], 0.7, "#6a5236", op * 0.8)
        for _ in range(3):
            cv.paint(cv.mask().circle(x + rr.normal(0, 12), y + rr.normal(0, 8), 0.8 + rr.random() * 1.4), "#4a3826",
                     op * 0.6)
        x += 34 + rr.normal(0, 2)
        k += 1
    return finish(cv, "mud_trail")


def leaves():
    cv = F("leaves", 1.6, 1.2)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    for _ in range(70):
        a = rr.random() * 6.28
        d = abs(rr.normal(0, 0.33)) * (x1 - x0) / 2
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.7
        colr = mix("#5a3a20", "#a07a3a", rr.random())
        cv.part(cv.mask().ellipse(x, y, 6 + rr.random() * 3, 3 + rr.random() * 1.5, rot=rr.random() * 180, wobble=0.6),
                colr, ow=1.0, shade=0.25, light=0.15, hatch=0.15, depth=0.8)
        cv.stroke([(x - 4, y), (x + 4, y)], 0.4, mix(colr, "#000000", 0.5), 0.6)
    return finish(cv, "leaves")


def _debris(name, kind):
    cv = F(name, 1.0, 0.7)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    dust = cv.mask().ellipse(cx, cy, (x1 - x0) / 2 - 4, (y1 - y0) / 2 - 4, wobble=6)
    cv.paint(blur(dust.arr, 6 * cv.ss), "#b8b0a2" if kind != "planks" else "#8a7a66", 0.4)
    if kind == "planks":
        for k in range(6):
            ln = 30 + rr.random() * 50
            w = 6 + rr.random() * 5
            a = rr.normal(0, 0.6)
            x = cx + rr.normal(0, 22)
            y = cy + rr.normal(0, 14)
            ca, sa = math.cos(a), math.sin(a)
            jag = rr.normal(0, w * 0.4)
            pts = [(x - ca * ln / 2 - sa * w / 2, y - sa * ln / 2 + ca * w / 2), (x - ca * ln / 2 + sa * w / 2, y - sa * ln / 2 - ca * w / 2),
                   (x + ca * ln / 2 + sa * w / 2, y + sa * ln / 2 - ca * w / 2),
                   (x + ca * (ln / 2 - 5) + sa * jag, y + sa * (ln / 2 - 5) - ca * jag),
                   (x + ca * ln / 2 - sa * w / 2, y + sa * ln / 2 + ca * w / 2)]
            dark = k % 2 == 0
            tex = wood_tex(cv.W, cv.H, rng(f"{name}{k}"), "#4b3f35" if dark else "#c9a577", "#1a120c" if dark else "#8a6a44",
                           "#6a5a4a" if dark else "#e0c08e", rings=30)
            cv.part(cv.mask().poly(pts, wobble=0.4), tex, ow=2.0, shade=0.4, light=0.25, hatch=0.3, depth=2)
        for _ in range(20):
            a = rr.random() * 6.28
            x, y = cx + rr.normal(0, 30), cy + rr.normal(0, 18)
            cv.stroke([(x, y), (x + math.cos(a) * 7, y + math.sin(a) * 7)], 1.2, "#c9a577", 0.9)
            cv.stroke([(x, y), (x + math.cos(a) * 7, y + math.sin(a) * 7)], 0.4, INK, 0.7)
        for _ in range(8):
            x, y = cx + rr.normal(0, 30), cy + rr.normal(0, 18)
            cv.part(cv.mask().ellipse(x, y, 5, 3, wobble=1.0), "#c9a96a", ow=0.8, shade=0.2, light=0.2, hatch=0.2, depth=0.6)
    elif kind == "plaster":
        for k in range(14):
            x = cx + rr.normal(0, 26)
            y = cy + rr.normal(0, 15)
            s = 5 + rr.random() * 10
            pts = [(x + math.cos(t) * s * (0.6 + 0.5 * rr.random()), y + math.sin(t) * s * (0.6 + 0.5 * rr.random()))
                   for t in np.linspace(0, 6.28, 6, endpoint=False)]
            cv.part(cv.mask().poly(pts), "#d9d2c3", ow=1.4, shade=0.35, light=0.3, hatch=0.25, depth=1.5)
        for _ in range(60):
            cv.paint(cv.mask().circle(cx + rr.normal(0, 32), cy + rr.normal(0, 20), 0.8 + rr.random()), "#e6e0d4", 0.9)
    else:
        for k in range(22):
            x = cx + rr.normal(0, 28)
            y = cy + rr.normal(0, 16)
            s = 3 + rr.random() * 8
            pts = [(x + math.cos(t) * s * (0.4 + 0.7 * rr.random()), y + math.sin(t) * s * (0.4 + 0.7 * rr.random()))
                   for t in np.linspace(0, 6.28, 4, endpoint=False) + rr.random()]
            cv.part(cv.mask().poly(pts), "#a9c2cc", ow=1.0, shade=0.2, light=0.6, hatch=0, depth=0.8)
            cv.stroke([pts[0], pts[2]], 0.4, "#f2fbff", 0.8)
    return finish(cv, name)


def debris_planks():
    return _debris("debris_planks", "planks")


def debris_plaster():
    return _debris("debris_plaster", "plaster")


def debris_glass():
    return _debris("debris_glass", "glass")


def ceiling_light():
    cv = F("ceiling_light", 0.46, 0.46)
    x0, y0, x1, y1 = box(cv)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    cv.part(cv.mask().circle(cx, cy, 27), gradient(cv.W, cv.H, "#3a3c40", "#16171a", 50), ow=3.0, shade=0.35,
            light=0.45, hatch=0.3, depth=3)
    pts = ellipse_pts(cx, cy, 20, 20, 40)
    cv.stroke(pts + [pts[0]], 0.8, "#5a5d62", 0.8)
    cv.part(cv.mask().circle(cx, cy, 4), "#a8874a", ow=1.0, shade=0.2, light=0.4, hatch=0, depth=0.5)
    return finish(cv, "ceiling_light")


def bulb():
    cv = F("bulb", 0.3, 0.3)
    x0, y0, x1, y1 = box(cv)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    cv.part(cv.mask().circle(cx, cy, 9), "#e8e2cc", ow=2.0, shade=0.25, light=0.5, hatch=0, depth=1.5)
    cv.part(cv.mask().circle(cx, cy, 4), "#6a6a66", ow=1.0, shade=0.2, light=0.3, hatch=0, depth=0.5)
    cv.stroke(catmull([(cx, cy), (cx + 6, cy - 8), (cx + 4, y0)], 6), 1.2, INK, 0.9)
    return finish(cv, "bulb")


def table_lamp():
    cv = F("table_lamp", 0.36, 0.36)
    x0, y0, x1, y1 = box(cv)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    cv.part(cv.mask().circle(cx, cy, 20), fab(cv, "#cfc6b2", 0.06), ow=2.6, shade=0.35, light=0.3, hatch=0.3, depth=3)
    cv.paint(cv.mask().circle(cx, cy, 12), "#4a4236")
    cv.part(cv.mask().circle(cx, cy, 5), "#efe6cf", ow=1.0, shade=0.2, light=0.3, hatch=0, depth=0.8)
    return finish(cv, "table_lamp")


ALL = [sofa, armchair, coffee_table, tv_stand, floor_lamp, bookshelf, dining_table, chair, plant, rug_living, rug_bed,
       bath_mat, counter, sink_counter, stove, fridge, island, stool, bed, nightstand, wardrobe, dresser, bathtub,
       toilet, vanity, water_heater, workbench, washer, shelves, boxes, car, dead_tree, trash_bin, mailbox,
       streetlight, papers, shoe, toy, mud_trail, leaves, debris_planks, debris_plaster, debris_glass, ceiling_light,
       bulb, table_lamp]


def build_all():
    print("furniture, props, details")
    for f in ALL:
        f()


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        for f in sys.argv[1:]:
            globals()[f]()
    else:
        build_all()
