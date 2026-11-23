"""Character tokens (board-game miniatures seen from above, facing +X) and
fallen poses, plus the two light textures.

Token canvas: 128 x 128 px = 1.0 m square, pivot at the centre, facing +X.
Fallen poses: 256 x 128 px = 2.0 m x 1.0 m, head toward +X, pivot at centre.
Structure (base disc, ground shadow, part/limb/hand helpers) adapted from The
Witchening Tales tools/art/tokens.py (the user's own project); figures are new.
"""
from __future__ import annotations

import math

import numpy as np

from core import (Canvas, INK, blur, catmull, col, dilate, ellipse_pts, fabric_tex, gradient, mix, noise_tex,
                  radial, rng, save, smoothstep, edge_band)

S = 128
CX, CY = 64.0, 64.0
RB = 44.0  # base radius (0.34 m)

SKIN = "#c49a7c"
SKIN_PALE = "#bdbab0"


def new(name, w=S, h=S):
    return Canvas(w, h, 4, name=name)


def fab(cv, color, amount=0.14, weave=1.2):
    return fabric_tex(cv.W, cv.H, rng(f"{cv.name}:{color}"), color, amount, weave, cv.ss)


def base(cv, ring, field="#1d1b1c", rim="#34312f", notch="#ece3cc"):
    m = cv.mask().circle(CX, CY, RB)
    g = gradient(cv.W, cv.H, mix(rim, "#ffffff", 0.18), mix(rim, "#000000", 0.45), 45)
    cv.part(m, g, ow=2.2, shade=0.35, light=0.3, hatch=0.35, depth=3)
    inner = cv.mask().circle(CX, CY, RB - 4.5)
    t = noise_tex(cv.W, cv.H, rng(cv.name + "base"), field, 0.18, 10, 10, 4)
    cv.paint(dilate(inner.arr, 1.3 * cv.ss), INK)
    cv.paint(inner, t)
    eb = edge_band(inner.arr, -2.5 * cv.ss, -2.5 * cv.ss, 2.0 * cv.ss)
    cv.mul(eb, 0.5, (0, 0, 0))
    cv.hatch(inner.arr, 45, 2.0, 0.45, 0.16)
    ring_m = np.clip(cv.mask().circle(CX, CY, RB - 2.0).arr - cv.mask().circle(CX, CY, RB - 3.1).arr, 0, 1)
    cv.paint(ring_m, ring, 0.95)
    nt = cv.mask().poly([(CX + RB + 1.0, CY), (CX + RB - 5.5, CY - 4.5), (CX + RB - 5.5, CY + 4.5)])
    cv.paint(dilate(nt.arr, 1.0 * cv.ss), INK)
    cv.paint(nt, notch)


def ground_shadow(cv, x, y, rx, ry, op=0.55):
    m = cv.mask().ellipse(x + 2, y + 3, rx, ry)
    cv.mul(blur(m.arr, 3 * cv.ss), op, (0, 0, 0))


def P(cv, m, fill, ow=1.9, shade=0.45, light=0.3, hatch=0.5, depth=2.6, soft=0.0, **kw):
    return cv.part(m, fill, ow=ow, shade=shade, light=light, hatch=hatch, depth=depth, soft=soft,
                   hatch_spacing=2.0, **kw)


def limb(cv, pts, w, fill, ow=1.6):
    m = cv.mask().curve(pts, w, n=10)
    return P(cv, m, fill, ow=ow, depth=1.4, hatch=0.3)


def hand(cv, x, y, r=3.0, skin=SKIN):
    P(cv, cv.mask().circle(x, y, r), skin, ow=1.4, depth=1.1, hatch=0.2)


def finish(cv, name, shadow=True):
    cv.grain(0.06)
    if shadow:
        cv.drop_shadow(1.5, 2.5, 1.8, 0.5)
    save(cv.image(), name)


# --------------------------------------------------------------------------
# player: dark jacket, rust-orange accent (pack straps + hood lining), handgun
# --------------------------------------------------------------------------
def player():
    cv = new("player")
    base(cv, ring="#b08a4a")
    cv.xf = (1.32, 62.0, 64.0)
    ground_shadow(cv, 62, 64, 24, 28)
    jacket = "#2b323b"
    accent = "#c2622e"
    # backpack behind (-X)
    pack = cv.mask().rect(36, 49, 56, 79, 6, wobble=0.5)
    P(cv, pack, fab(cv, "#3f4434"), depth=3, soft=0.3)
    roll = cv.mask().rect(33, 51, 40, 77, 3.5, wobble=0.4)
    P(cv, roll, fab(cv, "#5b5a4a"), depth=1.5, hatch=0.3)
    for yy in (57, 71):
        cv.stroke([(34, yy), (40, yy)], 0.8, INK, 0.8)
    cv.paint(cv.mask().rect(44, 60, 52, 68, 1.5), accent, 0.95)   # reflective patch
    cv.stroke([(44, 60), (52, 60), (52, 68), (44, 68), (44, 60)], 0.6, INK, 0.9)
    # shoulders / jacket
    sh = cv.mask().ellipse(60, 64, 13.5, 22, wobble=0.4)
    P(cv, sh, fab(cv, jacket), depth=3, soft=0.35)
    # pack straps over the shoulders (accent)
    for yy in (51, 77):
        cv.stroke(catmull([(50, yy), (58, yy + (1 if yy < 64 else -1) * 1), (66, yy + (3 if yy < 64 else -3))], 6),
                  2.2, INK, 1.0)
        cv.stroke(catmull([(50, yy), (58, yy + (1 if yy < 64 else -1) * 1), (66, yy + (3 if yy < 64 else -3))], 6),
                  1.3, accent, 1.0)
    # arms extended in a two-handed grip
    limb(cv, [(60, 44), (74, 50), (86, 61)], 7.0, fab(cv, jacket))
    limb(cv, [(60, 84), (74, 78), (86, 67)], 7.0, fab(cv, jacket))
    # handgun
    gun = cv.mask().rect(86, 61.5, 104, 66.5, 1.0)
    P(cv, gun, "#1c1d20", ow=1.2, depth=1.0, hatch=0.0, light=0.45)
    cv.stroke([(90, 64), (103, 64)], 0.5, "#6a6d73", 0.9)
    hand(cv, 87, 61.5, 3.2)
    hand(cv, 87, 66.5, 3.2)
    # hood folded down behind the head with accent lining
    hood = cv.mask().ellipse(57, 64, 7, 11, wobble=0.3)
    P(cv, hood, fab(cv, jacket), depth=1.5, ow=1.3)
    cv.paint(cv.mask().ellipse(58, 64, 4.2, 7.5), accent, 0.85)
    # head: short dark hair, ears
    hx, hy = 66, 64
    for ey in (hy - 8.6, hy + 8.6):
        P(cv, cv.mask().ellipse(hx + 1, ey, 2.0, 1.4), SKIN, ow=1.0, depth=0.6, hatch=0)
    head = cv.mask().ellipse(hx, hy, 9.5, 9.0)
    P(cv, head, SKIN, ow=2.0, depth=1.8)
    hr = cv.mask().ellipse(hx - 1.5, hy, 9.0, 9.0, wobble=0.35)
    P(cv, hr, fab(cv, "#2a2420", 0.2), ow=1.1, depth=2.0, soft=0.2)
    for k in range(6):
        yy = hy - 7 + k * 2.8
        cv.stroke(catmull([(hx + 6, hy + (yy - hy) * 0.4), (hx, yy), (hx - 8, yy * 0.92 + hy * 0.08)], 6), 0.45,
                  "#4a3f38", 0.8)
    cv.paint(cv.mask().ellipse(hx + 9.6, hy, 1.6, 1.5), mix(SKIN, "#000000", 0.12))
    return finish(cv, "player")


# --------------------------------------------------------------------------
# psychos: pale, hunched, ragged everyday clothes (ambiguous, not monsters)
# --------------------------------------------------------------------------
def _rips(cv, cx, cy, rx, ry, n, rnd, cloth):
    for _ in range(n):
        a = rnd.random() * 2 * math.pi
        d = 0.4 + 0.5 * rnd.random()
        x, y = cx + math.cos(a) * rx * d, cy + math.sin(a) * ry * d
        m = cv.mask().ellipse(x, y, 2.2 + rnd.random() * 2.5, 1.0 + rnd.random() * 1.2, rot=rnd.random() * 180, wobble=0.5)
        cv.paint(dilate(m.arr, 0.6 * cv.ss), mix(cloth, "#000000", 0.6))
        cv.paint(m, SKIN_PALE, 0.9)
        for k in range(3):
            cv.stroke([(x + rnd.normal(0, 2), y + rnd.normal(0, 1.5)), (x + rnd.normal(0, 3), y + rnd.normal(0, 3))],
                      0.35, mix(cloth, "#ffffff", 0.3), 0.8)


def _stains(cv, cx, cy, rx, ry, n, rnd, color="#4a3a2a"):
    for _ in range(n):
        x, y = cx + rnd.normal(0, rx * 0.4), cy + rnd.normal(0, ry * 0.4)
        m = cv.mask().ellipse(x, y, 2 + rnd.random() * 4, 1.5 + rnd.random() * 3, wobble=1.0, rot=rnd.random() * 180)
        cv.paint(blur(m.arr, 0.8 * cv.ss), color, 0.45)


def psycho(name, cloth, hair, style):
    cv = new(name)
    rnd = rng(name + "detail")
    base(cv, ring="#6e2b24", notch="#b9aa98")
    cv.xf = (1.34, 62.0, 64.0)
    ground_shadow(cv, 60, 62, 24, 28)
    skin = SKIN_PALE
    if style == "a":
        # torn grey hoodie, hood up and ragged; one arm reaching, one hanging back
        sh = cv.mask().poly(catmull([(64, 41), (52, 41), (44, 50), (42, 64), (45, 78), (54, 87), (64, 86)], 8)
                            + [(70, 76), (70, 52)], wobble=0.7)
        P(cv, sh, fab(cv, cloth, 0.2), depth=3, soft=0.35, hatch=0.6)
        _rips(cv, 56, 64, 12, 20, 5, rnd, cloth)
        _stains(cv, 56, 64, 12, 20, 6, rnd)
        limb(cv, [(62, 44), (76, 40), (90, 46)], 6.5, fab(cv, cloth, 0.2))
        hand(cv, 92, 47, 3.0, skin)
        for k in range(3):   # splayed fingers
            a = -0.5 + k * 0.45
            cv.stroke([(93, 47), (93 + math.cos(a) * 5, 47 + math.sin(a) * 5)], 1.1, skin, 1.0)
            cv.stroke([(93, 47), (93 + math.cos(a) * 5, 47 + math.sin(a) * 5)], 0.4, INK, 0.6)
        limb(cv, [(60, 84), (66, 92), (74, 94)], 6.0, fab(cv, cloth, 0.2))
        hand(cv, 76, 94, 2.8, skin)
        # hood (up), head pushed forward and low
        hood = cv.mask().ellipse(66, 63, 11, 11.5, wobble=0.6)
        P(cv, hood, fab(cv, mix(cloth, "#000000", 0.15), 0.2), depth=2.2, soft=0.3, ow=1.6)
        cv.paint(cv.mask().ellipse(69, 63, 7.0, 8.0), "#141212")
        head = cv.mask().ellipse(71, 63, 6.8, 7.0)
        P(cv, head, skin, ow=1.3, depth=1.4, hatch=0.3)
        for k in range(7):   # greasy strands falling forward
            y = 57 + k * 2.0
            cv.stroke(catmull([(66, y), (71, y + rnd.normal(0, 0.6)), (76, y + rnd.normal(0, 1.0))], 5), 0.6, hair, 0.95)
        # drawstrings
        for yy in (58, 68):
            cv.stroke([(74, yy), (79, yy + (yy - 63) * 0.5 + rnd.normal(0, 1))], 0.6, "#cfcac0", 0.9)
    else:
        # stained office shirt, loosened tie, thinning hair; both arms reaching
        sh = cv.mask().poly(catmull([(64, 43), (54, 41), (46, 49), (44, 64), (46, 79), (54, 86), (64, 85)], 8)
                            + [(69, 74), (69, 53)], wobble=0.6)
        P(cv, sh, fab(cv, cloth, 0.16), depth=3, soft=0.3, hatch=0.55)
        _stains(cv, 56, 64, 12, 20, 9, rnd, "#5a4632")
        _rips(cv, 56, 64, 12, 20, 3, rnd, cloth)
        for yy in (45, 83):   # rolled sleeves -> bare forearms
            sgn = -1 if yy < 64 else 1
            limb(cv, [(62, yy), (72, yy + sgn * 1), (78, yy - sgn * 6)], 6.2, fab(cv, cloth, 0.16))
            limb(cv, [(78, yy - sgn * 6), (86, yy - sgn * 10), (92, yy - sgn * 12)], 4.6, skin)
            hand(cv, 93, yy - sgn * 12, 2.8, skin)
        tie = cv.mask().poly([(66, 62), (70, 61.5), (80, 66), (78, 70), (68, 66)], wobble=0.4)
        P(cv, tie, fab(cv, "#3a2a35", 0.1), ow=1.0, depth=1.0, hatch=0.2)
        head = cv.mask().ellipse(68, 64, 8.6, 8.2)
        P(cv, head, skin, ow=1.8, depth=1.8)
        for k in range(9):
            a = math.pi * (0.55 + k / 8 * 0.9)
            x, y = 68 + math.cos(a) * 7.5, 64 + math.sin(a) * 7.5
            cv.stroke([(x, y), (x - 3 + rnd.normal(0, 0.7), y + rnd.normal(0, 1.2))], 0.6, hair, 0.9)
        for k in range(3):
            cv.stroke(catmull([(63, 60 + k * 3), (68, 59.5 + k * 3.5), (73, 61 + k * 2.5)], 5), 0.35, hair, 0.8)
        cv.paint(cv.mask().ellipse(76.2, 64, 1.5, 1.4), mix(skin, "#000000", 0.15))
    return finish(cv, name)


def psycho_dead(name, cloth, hair, style):
    """Collapsed face-down, arms flung, legs trailing toward -X. 2 m x 1 m."""
    cv = new(name, 256, 128)
    rnd = rng(name + "dead")
    cy = 64
    sh = cv.mask().ellipse(120, cy + 4, 52, 26)
    cv.mul(blur(sh.arr, 5 * cv.ss), 0.5, (0, 0, 0))
    trousers = "#2f3136" if style == "a" else "#3d3a33"
    # legs
    limb(cv, [(128, cy - 7), (104, cy - 13), (84, cy - 15), (68, cy - 12)], 15, fab(cv, trousers, 0.15))
    limb(cv, [(128, cy + 7), (106, cy + 12), (88, cy + 22), (74, cy + 30)], 15, fab(cv, trousers, 0.15))
    for (x, y, rot) in ((62, cy - 12, 8), (68, cy + 32, 35)):
        P(cv, cv.mask().ellipse(x, y, 9, 5.5, rot=rot), "#1c1a18", ow=1.6, depth=1.4, hatch=0.2)
    # torso
    torso = cv.mask().poly(catmull([(118, cy - 19), (150, cy - 23), (170, cy - 15), (174, cy + 1), (169, cy + 17),
                                    (148, cy + 23), (118, cy + 17)], 8), wobble=0.7)
    P(cv, torso, fab(cv, cloth, 0.18), depth=3.2, soft=0.35, hatch=0.6)
    _stains(cv, 146, cy, 22, 14, 7, rnd)
    _rips(cv, 146, cy, 20, 12, 4, rnd, cloth)
    # arms flung
    limb(cv, [(160, cy - 18), (176, cy - 32), (196, cy - 36)], 10, fab(cv, cloth, 0.18))
    hand(cv, 200, cy - 36, 4.2, SKIN_PALE)
    limb(cv, [(158, cy + 19), (166, cy + 33), (150, cy + 45)], 10, fab(cv, cloth, 0.18))
    hand(cv, 147, cy + 46, 4.2, SKIN_PALE)
    # head turned, face down
    head = cv.mask().ellipse(185, cy + 2, 11.5, 11)
    P(cv, head, SKIN_PALE, ow=2.0, depth=2.0)
    hr = cv.mask().ellipse(184, cy + 1, 11, 10.5, wobble=0.5)
    P(cv, hr, fab(cv, hair, 0.22), ow=1.1, depth=2.0, soft=0.25)
    for k in range(8):
        y = cy - 7 + k * 2.2
        cv.stroke(catmull([(175, y), (185, y + rnd.normal(0, 0.8)), (196, y + rnd.normal(0, 1.4))], 5), 0.5,
                  mix(hair, "#000000", 0.4), 0.8)
    return finish(cv, name)


# --------------------------------------------------------------------------
# light textures (pure intensity, no style): soft radial and a centred cone
# --------------------------------------------------------------------------
def light_soft():
    N = 512
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    d = np.hypot(x - N / 2 + 0.5, y - N / 2 + 0.5) / (N / 2)
    a = np.exp(-(d * d) / (2 * 0.36 * 0.36)) * np.clip((0.97 - d) / 0.12, 0, 1)
    img = np.dstack([np.full_like(a, 255), np.full_like(a, 255), np.full_like(a, 255), a * 255]).astype(np.uint8)
    from PIL import Image
    save(Image.fromarray(img, "RGBA"), "light_soft")


def light_cone():
    """Apex at the texture centre, pointing +X (the light node sits at the gun)."""
    N = 1024
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    dx, dy = x - N / 2, y - N / 2
    d = np.hypot(dx, dy) / (N / 2)
    ang = np.abs(np.arctan2(dy, dx))
    half = math.radians(24)
    edge = np.clip((half - ang) / math.radians(9), 0, 1) ** 1.5
    core = np.clip((math.radians(9) - ang) / math.radians(9), 0, 1) * 0.25
    fall = np.clip(1 - d, 0, 1) ** 1.3 * np.clip(d / 0.03, 0, 1)
    a = np.clip((edge + core) * fall * 1.05, 0, 1)
    halo = np.exp(-(d * d) / (2 * 0.05 * 0.05)) * 0.55
    a = np.clip(a + halo, 0, 1)
    img = np.dstack([np.full_like(a, 255), np.full_like(a, 255), np.full_like(a, 255), a * 255]).astype(np.uint8)
    from PIL import Image
    save(Image.fromarray(img, "RGBA"), "light_cone")


def build_all():
    print("tokens & lights")
    player()
    psycho("psycho_a", "#77797a", "#2a2622", "a")
    psycho("psycho_b", "#b3ad9e", "#4a443c", "b")
    psycho_dead("psycho_a_dead", "#77797a", "#2a2622", "a")
    psycho_dead("psycho_b_dead", "#b3ad9e", "#4a443c", "b")
    light_soft()
    light_cone()


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        for f in sys.argv[1:]:
            globals()[f]()
    else:
        build_all()
