"""Generates the template sounds for Sirens Went Quiet (Experiment 002).

Run from the project root:
    python3 tools/audio/make_sounds.py            # everything
    python3 tools/audio/make_sounds.py ui/click   # selected logical names

Needs Python 3 + numpy and ffmpeg with libvorbis. Every sound is synthesised
from scratch (no samples), normalised per category, encoded to Ogg Vorbis at
assets/audio/<group>/template_<name>.ogg, and given a Godot .import file
(loop=true for ambience and music). Afterwards run
    godot --headless --path . --import
and python3 tools/audio/analyze.py for the level table in
docs/experiment-002/audio.md. User overrides go in custom/audio/<logical>.ogg
(see assets/README.md); this script never touches custom/.
"""
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

import numpy as np

sys.dont_write_bytecode = True  # keep tools/audio free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from dsp import (SR, secs, taxis, db, undb, white, colored, smooth_random, filt, filt_circular,
                 spectral, resonators, stft_process, formant_gain, pad_to, place, env_ad,
                 env_points, fade, softclip, osc_phase, additive, trim_tail, reverb_ir, convolve,
                 add_reverb, distance, active_rms_db, peak_db, limit)

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"
HOP = 512


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-12)


def burst(n, rng, attack, decay, stages=None):
    x = white(n, rng) * env_ad(n, attack, decay)
    return filt(x, stages) if stages else x


def impulse(n, at_s=0.0, amp=1.0):
    x = np.zeros(n)
    x[min(n - 1, secs(at_s))] = amp
    return x


def loop_len(seconds):
    return int(round(seconds * SR / HOP)) * HOP


def qfreq(f, n):
    """Nearest frequency with a whole number of cycles in n samples (loops)."""
    T = n / SR
    return max(1, round(f * T)) / T


# ---------------------------------------------------------------- voice

VOWELS = {  # (F1, F2, F3) adult male, Peterson & Barney style
    "a": (730, 1090, 2440), "o": (570, 840, 2410), "u": (300, 870, 2240),
    "uh": (640, 1190, 2390), "er": (490, 1350, 1690), "ae": (660, 1720, 2410),
    "oo": (440, 1020, 2240), "e": (530, 1840, 2480),
}


def vowel_track(points, scale=1.0):
    """points: [(t, vowel)] -> function t -> formant list."""
    ts = [p[0] for p in points]
    fs = np.array([VOWELS[p[1]] for p in points], float) * scale

    def at(t):
        F = [np.interp(t, ts, fs[:, i]) for i in range(3)]
        return F
    return at


def voice(n, rng, f0, vowels, breath, voiced, fry=None, bw_scale=1.0, sub=0.0,
          tremor=0.0, chest=True, tilt=-3.0, extra=None):
    """Source-filter voice: jittery harmonic source + breath + vocal fry,
    shaped by moving formants. f0/breath/voiced/fry are per-sample arrays."""
    jitter = 1.0 + 0.012 * smooth_random(n, rng, 30.0) + 0.004 * white(n, rng)
    f = np.maximum(f0 * jitter, 20.0)
    ph = osc_phase(f)
    K = int(min(60, 5200 / max(40.0, f.max())))
    src = np.zeros(n)
    for k in range(1, K + 1):
        src += np.sin(2 * np.pi * k * ph + rng.uniform(0, 0.3)) / k
    if sub:
        src *= 1.0 + sub * np.sin(np.pi * ph)  # period doubling: subharmonic roughness
    shimmer = 1.0 + 0.10 * smooth_random(n, rng, 40.0)
    src *= shimmer
    noise = white(n, rng) * (0.55 + 0.45 * (0.5 + 0.5 * np.cos(2 * np.pi * ph)))
    exc = norm(src) * voiced + norm(noise) * 0.35 * breath
    if fry is not None:
        pulses = np.zeros(n)
        t = 0.0
        while t < n / SR:
            idx = secs(t)
            if idx < n and fry[idx] > 0.01:
                pulses[idx] += fry[idx] * rng.uniform(0.5, 1.0)
            t += rng.uniform(0.018, 0.04)
        exc += filt(pulses, [("lp", 1800)]) * 6.0
    if tremor:
        exc *= 1.0 + tremor * smooth_random(n, rng, 9.0)
    tr = vowels

    def frame(tc, freqs):
        F1, F2, F3 = tr(tc)
        forms = [(F1, 90 * bw_scale, 0), (F2, 120 * bw_scale, -4), (F3, 180 * bw_scale, -10),
                 (3400, 300 * bw_scale, -16)]
        if chest:
            forms.append((230, 140, -6))
        if extra:
            forms += extra(tc)
        return formant_gain(freqs, forms, tilt)
    return stft_process(exc, frame, nfft=1024, hop=256)


# ---------------------------------------------------------------- weapon

def handgun(rng):
    n = secs(1.6)
    t = taxis(n)
    crack = norm(filt(white(n, rng) * np.exp(-t / 0.0026), [("hp", 1100), ("peak", 3200, 0.9, 6)]))
    body = norm(filt(white(n, rng) * env_ad(n, 0.0003, 0.017),
                     [("lp", 4800), ("hp", 220), ("peak", 1100, 0.9, 6), ("peak", 460, 1.0, 3)]))
    f = 55 + 90 * np.exp(-t / 0.012)
    thump = np.sin(2 * np.pi * osc_phase(f)) * env_ad(n, 0.0005, 0.03)
    clack = norm(resonators(impulse(n, 0.024) - 0.6 * impulse(n, 0.033),
                            [(2650, 18, 1.0), (4320, 22, 0.7), (6900, 25, 0.45), (1480, 12, 0.6)], keep_tail=False))
    dry = 1.0 * crack + 1.0 * body + 0.5 * thump + 0.07 * clack
    dry = softclip(dry * 2.0, 1.0)
    ir = reverb_ir(0.8, rng, predelay=0.005, bright=0.7)
    wet = convolve(filt(dry, [("lp", 4200)]), ir)[:n]
    slap = np.zeros(n)
    place(slap, filt(dry, [("lp", 1700), ("hp", 200)]), 0.088, undb(-13))
    place(slap, filt(dry, [("lp", 1100), ("hp", 200)]), 0.19, undb(-20))
    out = dry + wet * undb(-11) + slap
    return trim_tail(out, -60, 0.08)


def dry_fire(rng):
    n = secs(0.25)
    trig = resonators(impulse(n, 0.002), [(3100, 20, 0.6), (5200, 26, 0.4), (1900, 10, 0.4)], keep_tail=False)
    ham = resonators(impulse(n, 0.03) + 0.3 * impulse(n, 0.0315), [(2350, 24, 1.0), (4100, 30, 0.7), (7200, 30, 0.35), (1250, 9, 0.5)], keep_tail=False)
    tick = filt(white(n, rng) * env_ad(n, 0.0002, 0.0015), [("hp", 2500)])
    tick = pad_to(np.roll(tick, secs(0.03)), n)
    out = 0.45 * norm(trig) + norm(ham) + 0.35 * norm(tick)
    return trim_tail(out, -55)


# ---------------------------------------------------------------- impacts

def splinters(n, rng, count, spread, fc=3500, start=0.003):
    x = np.zeros(n)
    for _ in range(count):
        at = start + rng.exponential(spread)
        if at < n / SR - 0.01:
            x[secs(at)] += rng.uniform(-1, 1) * np.exp(-at / (spread * 2.5))
    return filt(x, [("bp", fc, 0.7), ("peak", fc * 1.6, 2.0, 4)])


def grains(n, rng, count, t0, spread, f_lo, f_hi, dur=(0.002, 0.006), q=1.2, decay_t=None):
    x = np.zeros(n)
    for _ in range(count):
        at = t0 + rng.exponential(spread)
        if at >= n / SR - 0.02:
            continue
        m = secs(rng.uniform(*dur)) + 1
        g = white(m, rng) * np.hanning(m)
        fc = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        g = filt(g, [("bp", fc, q)], keep_tail=True)
        amp = rng.uniform(0.3, 1.0) * (np.exp(-(at - t0) / decay_t) if decay_t else 1.0)
        place(x, g, at, amp)
    return x


def impact_wood(rng):
    n = secs(0.6)
    exc = white(n, rng) * env_ad(n, 0.0003, 0.004)
    knock = resonators(exc, [(190, 9, 1.0), (430, 11, 0.85), (790, 13, 0.6), (1270, 15, 0.45), (2150, 18, 0.3)], keep_tail=False)
    thud = filt(white(n, rng) * env_ad(n, 0.0005, 0.02), [("lp", 500)])
    spl = splinters(n, rng, 26, 0.03, 3400)
    out = norm(knock) + 0.5 * norm(thud) + 0.55 * norm(spl)
    return trim_tail(softclip(out * 1.3), -58)


def impact_plaster(rng):
    n = secs(0.9)
    thud = norm(filt(white(n, rng) * env_ad(n, 0.0006, 0.028), [("lp", 850), ("peak", 260, 1.0, 4)]))
    crumble = norm(grains(n, rng, 90, 0.01, 0.12, 700, 3600, decay_t=0.3))
    bits = norm(grains(n, rng, 14, 0.18, 0.14, 1500, 5000, dur=(0.001, 0.003), q=3))
    dust = norm(filt(white(n, rng) * env_ad(n, 0.01, 0.16), [("hp", 2800), ("lp", 9000)]))
    out = thud + 0.55 * crumble + 0.3 * bits + 0.12 * dust
    return trim_tail(out, -58, 0.05)


def impact_glass(rng):
    n = secs(1.1)
    t = taxis(n)
    crack = norm(filt(white(n, rng) * np.exp(-t / 0.005), [("hp", 2600), ("peak", 5200, 1.5, 4)]))
    shards = np.zeros(n)
    for i in range(18):
        at = rng.exponential(0.12) if i > 2 else rng.uniform(0, 0.01)
        if at > 0.7:
            continue
        m = secs(0.25)
        tt = taxis(m)
        s = np.zeros(m)
        base = rng.uniform(2300, 6500)
        for r, g in ((1.0, 1.0), (rng.uniform(1.4, 1.7), 0.6), (rng.uniform(2.1, 2.7), 0.35)):
            fr = base * r
            if fr < 15000:
                s += g * np.sin(2 * np.pi * fr * tt) * np.exp(-tt / rng.uniform(0.02, 0.09))
        s *= np.clip(tt / 0.0004, 0, 1)
        amp = rng.uniform(0.25, 1.0) * np.exp(-at / 0.35)
        place(shards, s, at, amp)
        if rng.random() < 0.4:
            place(shards, s, at + rng.uniform(0.04, 0.09), amp * 0.35)
    tinkle = grains(n, rng, 30, 0.05, 0.18, 4000, 9000, dur=(0.0008, 0.002), q=6, decay_t=0.3)
    out = 0.8 * crack + norm(shards) + 0.25 * norm(tinkle)
    return trim_tail(out, -58, 0.06)


def impact_metal(rng):
    n = secs(1.3)
    exc = white(n, rng) * env_ad(n, 0.0002, 0.0012)
    base = 330.0
    modes = []
    for r, g in ((1.0, 1.0), (2.32, 0.8), (4.25, 0.6), (6.63, 0.45), (9.38, 0.3), (12.1, 0.2)):
        f = base * r
        q = np.pi * f * 0.4 * (330.0 / f) ** 0.4  # decay time ~0.4 s at the base, shorter above
        modes += [(f, q, g), (f * 1.004, q, g * 0.7)]
    ring = norm(resonators(exc, modes, keep_tail=False))
    clank = norm(filt(white(n, rng) * env_ad(n, 0.0003, 0.007), [("bp", 2200, 1.0)]))
    thud = norm(filt(white(n, rng) * env_ad(n, 0.0005, 0.02), [("lp", 400)]))
    out = ring + 0.7 * clank + 0.4 * thud
    return trim_tail(out, -55, 0.1)


def impact_flesh(rng):
    n = secs(0.45)
    t = taxis(n)
    thud = norm(filt(white(n, rng) * env_ad(n, 0.001, 0.045), [("lp", 340), ("hp", 40)]))
    low = np.sin(2 * np.pi * osc_phase(55 + 35 * np.exp(-t / 0.03))) * env_ad(n, 0.001, 0.055)
    slap = norm(filt(white(n, rng) * env_ad(n, 0.0004, 0.01), [("bp", 950, 1.2)]))
    wet = norm(filt(white(n, rng) * env_ad(n, 0.004, 0.03), [("bp", 1600, 3.0)]))
    out = thud + 0.8 * low + 0.35 * slap + 0.1 * wet
    return trim_tail(softclip(out * 1.4), -58)


def impact_ground(rng):
    n = secs(0.5)
    t = taxis(n)
    thud = norm(filt(white(n, rng) * env_ad(n, 0.001, 0.05), [("lp", 230), ("hp", 35)]))
    low = np.sin(2 * np.pi * 68 * t) * env_ad(n, 0.002, 0.04)
    dirt = norm(grains(n, rng, 22, 0.01, 0.07, 900, 3000, dur=(0.002, 0.005), q=1.0, decay_t=0.12))
    out = thud + 0.5 * low + 0.35 * dirt
    return trim_tail(out, -58)


# ---------------------------------------------------------------- player

def footstep(rng, v):
    n = secs(0.4)
    heel_fc = [780, 900, 700, 980][v]
    toe_at = [0.062, 0.078, 0.07, 0.085][v]
    heel = filt(white(n, rng) * env_ad(n, 0.0015, 0.022), [("lp", heel_fc), ("hp", 70)])
    knock = resonators(impulse(n, 0.001), [(105 + 8 * v, 5, 1.0), (240 + 15 * v, 6, 0.5)], keep_tail=False)
    toe = filt(white(n, rng) * env_ad(n, 0.002, 0.014), [("lp", 1500), ("hp", 120)])
    toe = pad_to(np.concatenate([np.zeros(secs(toe_at)), toe]), n)
    scuff = filt(white(n, rng) * env_ad(n, 0.004, 0.02), [("bp", 2400, 0.8)])
    scuff = pad_to(np.concatenate([np.zeros(secs(toe_at + 0.004)), scuff]), n)
    out = norm(heel) + 0.5 * norm(knock) + 0.55 * norm(toe) + 0.12 * norm(scuff)
    return trim_tail(out, -55)


def player_hurt(rng):
    n = secs(0.6)
    t = taxis(n)
    hit = norm(filt(white(n, rng) * env_ad(n, 0.001, 0.035), [("lp", 400)]))
    f0 = 150 - 40 * np.clip(t / 0.3, 0, 1)
    env = env_points(n, [(0, 0), (0.03, 1), (0.12, 0.8), (0.32, 0)])
    v = voice(n, rng, f0, vowel_track([(0, "uh"), (0.3, "er")]), breath=env * 0.9, voiced=env * 0.8,
              fry=env_points(n, [(0, 0), (0.18, 0), (0.3, 0.5), (0.35, 0)]))
    out = 0.7 * hit + norm(v)
    return trim_tail(out, -55)


def chew(n, rng, at):
    x = grains(n, rng, 40, at, 0.03, 1200, 4500, dur=(0.001, 0.004), q=1.5, decay_t=0.05)
    mouth = filt(white(n, rng) * env_ad(n, 0.005, 0.04), [("lp", 300)])
    return norm(x) + 0.4 * norm(pad_to(np.concatenate([np.zeros(secs(at)), mouth]), n))


def player_eat(rng):
    n = secs(1.5)
    out = np.zeros(n)
    for i, at in enumerate((0.02, 0.33, 0.62)):
        out += chew(n, rng, at) * (1.0 - 0.15 * i)
    m = secs(0.12)
    tt = taxis(m)
    gulp = np.sin(2 * np.pi * osc_phase(340 - 160 * tt / 0.12)) * np.hanning(m) * 0.6
    gulp = filt(gulp + 0.3 * white(m, rng) * np.hanning(m), [("lp", 700)])
    place(out, norm(gulp) * 0.7, 1.05)
    return trim_tail(out, -55, 0.05)


def bubble(rng, f0, dur=0.07):
    m = secs(dur)
    tt = taxis(m)
    f = f0 * (1 + 3.0 * tt)
    return np.sin(2 * np.pi * osc_phase(f)) * np.exp(-tt / (dur / 3)) * np.clip(tt / 0.002, 0, 1)


def player_drink(rng):
    n = secs(1.7)
    out = np.zeros(n)
    for i, at in enumerate((0.05, 0.36, 0.66, 0.95)):
        throat = filt(white(secs(0.12), rng) * np.hanning(secs(0.12)), [("lp", 260), ("peak", 140, 2, 6)])
        place(out, norm(throat) * 0.8, at)
        for j in range(3):
            place(out, bubble(rng, rng.uniform(380, 720)) * rng.uniform(0.3, 0.6), at + 0.02 + j * rng.uniform(0.015, 0.03))
    slosh = filt(white(n, rng), [("bp", 900, 1.5)]) * env_points(n, [(0, 0), (0.1, 0.12), (1.0, 0.08), (1.1, 0)])
    out += slosh
    m = secs(0.5)
    ah = voice(m, rng, np.full(m, 120.0), vowel_track([(0, "a"), (0.5, "a")]),
               breath=np.hanning(m) * 0.8, voiced=np.zeros(m))
    place(out, norm(ah) * 0.35, 1.15)
    return trim_tail(out, -55, 0.05)


def player_bandage(rng):
    n = secs(1.5)
    out = np.zeros(n)
    m = secs(0.5)
    rate = np.linspace(300, 900, m)
    pulses = np.zeros(m)
    t = 0.0
    while t < 0.48:
        i = secs(t)
        pulses[i] = rng.uniform(-1, 1)
        t += 1.0 / rate[min(i, m - 1)] * rng.uniform(0.4, 1.6)
    tear = filt(pulses, [("bp", 2600, 0.6), ("lp", 7000)]) + 0.15 * filt(white(m, rng), [("bp", 3500, 1.0)])
    tear *= env_points(m, [(0, 0), (0.03, 1), (0.35, 0.9), (0.48, 0)])
    place(out, norm(tear), 0.02)
    for at in (0.65, 1.0):
        k = secs(0.32)
        r = filt(white(k, rng), [("lp", 3200), ("hp", 300)]) * np.hanning(k) * (1 + 0.6 * smooth_random(k, rng, 18))
        place(out, norm(r) * 0.4, at)
    return trim_tail(out, -55, 0.05)


def player_sleep(rng):
    n = secs(3.4)
    t = taxis(n)
    breath_env = env_points(n, [(0, 0), (0.35, 0.8), (1.0, 1.0), (1.9, 0)])
    ex = voice(n, rng, np.full(n, 110.0), vowel_track([(0, "a"), (1.9, "uh")]), breath=breath_env,
               voiced=np.zeros(n), chest=False)
    pad = np.zeros(n)
    for f, g in ((146.83, 1.0), (220.0, 0.7), (277.18, 0.45), (329.63, 0.3)):
        pad += g * (np.sin(2 * np.pi * f * t) + 0.15 * np.sin(4 * np.pi * f * t))
    pad *= env_points(n, [(0, 0), (0.6, 0), (1.6, 1), (3.3, 0)])
    pad = filt(pad, [("lp", 1200)])
    out = norm(filt(ex, [("lp", 2500)])) * 0.8 + norm(pad) * 0.5
    return trim_tail(out, -55, 0.3)


def player_death(rng):
    n = secs(4.6)
    t = taxis(n)
    out = np.zeros(n)
    rustle = filt(white(secs(0.35), rng), [("lp", 3000), ("hp", 300)]) * np.hanning(secs(0.35))
    place(out, norm(rustle) * 0.3, 0.0)
    for at, g in ((0.28, 1.0), (0.46, 0.45)):
        m = secs(0.4)
        tt = taxis(m)
        th = filt(white(m, rng) * env_ad(m, 0.001, 0.06), [("lp", 300)])
        th = norm(th) + 0.8 * np.sin(2 * np.pi * osc_phase(45 + 30 * np.exp(-tt / 0.04))) * env_ad(m, 0.001, 0.08)
        place(out, th * g, at)
    drone = (np.sin(2 * np.pi * 55 * t) + np.sin(2 * np.pi * 58.3 * t) + 0.4 * np.sin(2 * np.pi * 82.4 * t))
    drone += 0.5 * filt(white(n, rng), [("lp", 250)])
    drone *= env_points(n, [(0, 0), (0.5, 0), (1.6, 0.6), (4.4, 0)])
    ring = np.sin(2 * np.pi * 3150 * t) * env_points(n, [(0, 0), (0.5, 0), (0.8, 0.05), (3.6, 0)])
    out = norm(out) + 0.45 * norm(drone) + ring
    return trim_tail(out, -55, 0.4)


# ---------------------------------------------------------------- building

def wood_knock(n, rng, at, base=180, q=8, decay=0.004, gain=1.0):
    exc = pad_to(np.concatenate([np.zeros(secs(at)), white(secs(0.02), rng) * env_ad(secs(0.02), 0.0003, decay)]), n)
    return gain * norm(resonators(exc, [(base, q, 1.0), (base * 2.3, q + 2, 0.7), (base * 4.1, q + 4, 0.45), (base * 6.8, q + 6, 0.25)], keep_tail=False))


def build_place(rng):
    n = secs(0.5)
    knock = wood_knock(n, rng, 0.0, 135, 6, 0.006)
    thud = norm(filt(white(n, rng) * env_ad(n, 0.001, 0.03), [("lp", 420)]))
    rattle = norm(splinters(n, rng, 6, 0.02, 2200, start=0.012))
    out = knock + 0.6 * thud + 0.15 * rattle
    return trim_tail(out, -58)


def build_hammer(rng):
    n = secs(1.0)
    out = np.zeros(n)
    for i, at in enumerate((0.0, 0.31)):
        p = 1.0 - 0.06 * i
        ping = resonators(impulse(n, at), [(3100 * p, 45, 1.0), (4700 * p, 55, 0.6), (6250 * p, 60, 0.35)], keep_tail=False)
        body = wood_knock(n, rng, at, 260 * p, 7, 0.003)
        hit = filt(white(n, rng) * env_ad(n, 0.0002, 0.003), [("hp", 1500)])
        hit = pad_to(np.concatenate([np.zeros(secs(at)), hit]), n)
        out += 0.5 * norm(ping) + body + 0.4 * norm(hit)
    ir = reverb_ir(0.35, rng, bright=0.8)
    out = add_reverb(out, ir, -16)[:n]
    return trim_tail(out, -58)


def creak(n, rng, dur, rate0, rate1, modes, at=0.0, jitter=0.25):
    """Stick-slip friction: an irregular pulse train through resonances."""
    x = np.zeros(n)
    t = 0.0
    while t < dur:
        r = rate0 + (rate1 - rate0) * (t / dur) + 6 * np.sin(2 * np.pi * t * 1.7)
        i = secs(at + t)
        if i < n:
            x[i] += rng.uniform(0.6, 1.0) * np.sin(np.pi * min(1.0, t / dur)) ** 0.6
        t += (1.0 / max(5.0, r)) * (1 + rng.uniform(-jitter, jitter))
    return resonators(x, modes, keep_tail=False)


def build_demolish(rng):
    n = secs(1.8)
    out = np.zeros(n)
    cr = creak(n, rng, 0.42, 22, 55, [(480, 14, 1.0), (980, 18, 0.7), (1650, 20, 0.4)])
    out += 0.5 * norm(cr)
    snap = filt(white(n, rng) * env_ad(n, 0.0003, 0.012), [("lp", 4000)])
    snap = pad_to(np.concatenate([np.zeros(secs(0.45)), snap]), n)
    out += norm(snap) + wood_knock(n, rng, 0.45, 210, 7, 0.006, 0.8)
    out += 0.6 * norm(splinters(n, rng, 40, 0.04, 3000, start=0.452))
    for at, b, g in ((0.78, 150, 0.8), (0.93, 190, 0.55), (1.06, 170, 0.6), (1.18, 230, 0.3)):
        out += wood_knock(n, rng, at, b, 6, 0.005, g)
    ir = reverb_ir(0.5, rng, bright=0.8)
    out = add_reverb(softclip(out * 1.2), ir, -14)[:n]
    return trim_tail(out, -58, 0.08)


def build_invalid(rng):
    n = secs(0.36)
    t = taxis(n)
    out = np.zeros(n)
    for at, f in ((0.0, 124.0), (0.14, 116.0)):
        m = secs(0.11)
        tt = taxis(m)
        ph = osc_phase(np.full(m, f))
        w = additive(ph, [1.0, 0.0, 0.33, 0.0, 0.2, 0.0, 0.14, 0, 0.1])
        w *= np.sin(np.pi * np.clip(tt / 0.11, 0, 1)) ** 1.5
        place(out, w, at)
    out = filt(out, [("lp", 650, 0.6), ("hp", 80)])
    return trim_tail(out, -60, 0.03)


def build_upgrade(rng):
    n = secs(1.4)
    t = taxis(n)
    out = np.zeros(n)
    exc = white(n, rng) * env_ad(n, 0.001, 0.01)
    sheet = resonators(exc, [(73, 30, 1.0), (118, 34, 0.8), (167, 38, 0.6), (241, 40, 0.45), (389, 50, 0.3), (612, 60, 0.2)], keep_tail=False)
    sheet = norm(sheet) * (1 + 0.35 * np.sin(2 * np.pi * 5.5 * t) * np.exp(-t / 0.4))
    out += sheet + 0.5 * norm(filt(white(n, rng) * env_ad(n, 0.001, 0.02), [("lp", 600)]))
    for at, p in ((0.42, 1.0), (0.63, 1.05)):
        ping = resonators(impulse(n, at), [(2900 * p, 60, 1.0), (4450 * p, 70, 0.6), (5900 * p, 70, 0.3)], keep_tail=False)
        out += 0.35 * norm(ping) + 0.25 * norm(pad_to(np.concatenate([np.zeros(secs(at)), filt(white(secs(0.01), rng), [("hp", 2000)])]), n))
    return trim_tail(out, -58, 0.1)


# ---------------------------------------------------------------- doors and structure

DOOR_MODES = [(520, 30, 1.0), (1100, 34, 0.7), (1750, 36, 0.5), (2600, 40, 0.3), (330, 18, 0.4)]


def latch(n, rng, at, gain=1.0):
    return gain * norm(resonators(impulse(n, at) + 0.5 * impulse(n, at + 0.012),
                                  [(2900, 30, 1.0), (4800, 35, 0.6), (1700, 15, 0.5)], keep_tail=False))


def door_open(rng):
    n = secs(1.2)
    out = latch(n, rng, 0.0, 0.5)
    cr = creak(n, rng, 0.75, 28, 75, DOOR_MODES, at=0.08)
    out += norm(cr)
    air = filt(white(n, rng), [("lp", 700)]) * env_points(n, [(0, 0), (0.3, 0.08), (0.9, 0)])
    out += air
    return trim_tail(filt(out, [("hp", 90)]), -58, 0.06)


def door_close(rng):
    n = secs(0.8)
    out = 0.5 * norm(creak(n, rng, 0.2, 60, 35, DOOR_MODES))
    out += wood_knock(n, rng, 0.22, 110, 6, 0.008, 1.0)
    out += 0.5 * norm(filt(pad_to(np.concatenate([np.zeros(secs(0.22)), white(secs(0.1), rng) * env_ad(secs(0.1), 0.001, 0.02)]), n), [("lp", 350)]))
    out += latch(n, rng, 0.235, 0.45)
    ir = reverb_ir(0.4, rng, bright=0.7)
    out = add_reverb(out, ir, -16)[:n]
    return trim_tail(out, -58)


def door_bash(rng):
    n = secs(0.9)
    exc = white(n, rng) * env_ad(n, 0.0008, 0.012)
    bang = norm(resonators(exc, [(92, 8, 1.0), (168, 9, 0.8), (290, 10, 0.6), (480, 12, 0.4), (820, 14, 0.25)], keep_tail=False))
    thud = norm(filt(white(n, rng) * env_ad(n, 0.001, 0.04), [("lp", 500)]))
    rattle = np.zeros(n)
    for _ in range(6):
        at = rng.uniform(0.01, 0.12)
        rattle += latch(n, rng, at, rng.uniform(0.2, 0.6))
    out = bang + 0.7 * thud + 0.35 * norm(rattle)
    ir = reverb_ir(0.45, rng, bright=0.6)
    out = add_reverb(softclip(out * 1.6), ir, -14)[:n]
    return trim_tail(out, -58, 0.06)


def structure_break(rng):
    n = secs(2.2)
    t = taxis(n)
    crack = norm(filt(white(n, rng) * env_ad(n, 0.0004, 0.02), [("lp", 3200), ("hp", 80)]))
    snap = wood_knock(n, rng, 0.0, 170, 6, 0.008, 1.0)
    spl = norm(splinters(n, rng, 70, 0.05, 2800))
    debris = np.zeros(n)
    for _ in range(55):
        at = 0.06 + rng.exponential(0.28)
        if at < 1.7:
            debris += wood_knock(n, rng, at, rng.uniform(250, 1200), 5, 0.002, rng.uniform(0.15, 0.6) * np.exp(-at / 0.8))
    dust = norm(grains(n, rng, 120, 0.05, 0.35, 900, 4500, decay_t=0.6))
    rumble = norm(filt(white(n, rng), [("lp", 120), ("hp", 45)])) * env_ad(n, 0.01, 0.45)
    out = crack + snap + 0.6 * spl + 0.5 * norm(debris) + 0.3 * dust + 0.7 * rumble
    ir = reverb_ir(0.6, rng, bright=0.7)
    out = add_reverb(softclip(out * 1.5), ir, -13)[:n]
    return trim_tail(out, -58, 0.15)


def structure_crumble(rng):
    n = secs(1.9)
    dust = norm(grains(n, rng, 160, 0.0, 0.45, 600, 3800, decay_t=0.8))
    thuds = np.zeros(n)
    for at in (0.05, 0.42, 0.9):
        thuds += norm(filt(pad_to(np.concatenate([np.zeros(secs(at)), white(secs(0.2), rng) * env_ad(secs(0.2), 0.002, 0.04)]), n), [("lp", 380)])) * np.exp(-at)
    hiss = norm(filt(white(n, rng), [("hp", 2500)])) * env_points(n, [(0, 0), (0.1, 0.1), (1.2, 0.05), (1.8, 0)])
    out = dust + 0.8 * thuds + hiss
    return trim_tail(out, -58, 0.2)


# ---------------------------------------------------------------- enemies

def uncanny_extra(tc):
    return [(1650 + 120 * np.sin(tc * 2.1), 70, -9)]  # a stray nasal resonance


def enemy_moan_1(rng):
    n = secs(2.8)
    t = taxis(n)
    f0 = 92 - 12 * np.clip(t / 1.0, 0, 1) + 9 * np.exp(-((t - 1.45) / 0.25) ** 2) - 24 * np.clip((t - 1.7) / 1.0, 0, 1)
    env = env_points(n, [(0, 0), (0.25, 0.8), (1.2, 1.0), (1.9, 0.75), (2.7, 0)])
    out = voice(n, rng, f0, vowel_track([(0, "o"), (0.9, "uh"), (1.6, "oo"), (2.6, "u")], 0.86), breath=env * 0.8,
                voiced=env * 0.75, fry=env_points(n, [(0, 0), (1.7, 0.1), (2.3, 0.7), (2.7, 0)]),
                bw_scale=1.4, sub=0.35, tremor=0.3, extra=uncanny_extra)
    return trim_tail(filt(out, [("hp", 55)]), -55, 0.2)


def enemy_moan_2(rng):
    n = secs(2.4)
    t = taxis(n)
    f0 = 76 + 22 * np.sin(np.pi * np.clip(t / 1.5, 0, 1)) - 10 * np.clip((t - 1.5) / 0.8, 0, 1)
    env = env_points(n, [(0, 0), (0.4, 0.5), (0.9, 1.0), (1.6, 0.8), (2.3, 0)])
    out = voice(n, rng, f0, vowel_track([(0, "a"), (0.8, "ae"), (1.4, "er"), (2.2, "uh")], 0.84),
                breath=env_points(n, [(0, 0), (0.3, 1.0), (0.6, 0.7), (2.3, 0.6)]),
                voiced=env * env_points(n, [(0, 0), (0.35, 0), (0.7, 1), (2.4, 1)]),
                fry=env_points(n, [(0, 0), (1.5, 0.1), (1.9, 0.9), (2.3, 0)]), bw_scale=1.5, sub=0.5,
                tremor=0.45, extra=uncanny_extra)
    rattle = filt(white(n, rng), [("bp", 420, 2.0)]) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 23 * t))) \
        * env_points(n, [(0, 0), (1.7, 0), (2.0, 0.6), (2.35, 0)])
    out = norm(out) + 0.25 * norm(rattle)
    return trim_tail(filt(out, [("hp", 55)]), -55, 0.2)


def enemy_attack(rng):
    n = secs(0.7)
    t = taxis(n)
    sweep_c = np.interp(t, [0, 0.08, 0.2, 0.3], [500, 1400, 2600, 900])
    swish = white(n, rng) * env_points(n, [(0, 0), (0.1, 0.6), (0.17, 1.0), (0.3, 0)])

    def frame(tc, freqs):
        c = float(np.interp(tc, t[::64], sweep_c[::64]))
        return 1.0 / (1.0 + ((freqs - c) / (c * 0.45)) ** 2)
    swish = stft_process(swish, frame, nfft=512, hop=128)
    f0 = 125 - 40 * np.clip(t / 0.35, 0, 1)
    env = env_points(n, [(0, 0), (0.05, 1.0), (0.25, 0.8), (0.4, 0)])
    grunt = voice(n, rng, f0, vowel_track([(0, "a"), (0.4, "uh")], 0.85), breath=env, voiced=env * 0.9,
                  fry=env * 0.6, bw_scale=1.3, sub=0.6)
    out = 0.8 * norm(swish) + norm(softclip(norm(grunt) * 2.0))
    return trim_tail(out, -55)


def enemy_hit(rng):
    n = secs(0.5)
    t = taxis(n)
    f0 = 110 - 45 * np.clip(t / 0.25, 0, 1)
    env = env_points(n, [(0, 0), (0.015, 1.0), (0.12, 0.7), (0.32, 0)])
    v = voice(n, rng, f0, vowel_track([(0, "uh"), (0.3, "u")], 0.85), breath=env * 0.9, voiced=env,
              fry=env_points(n, [(0, 0), (0.1, 0.2), (0.25, 0.8), (0.32, 0)]), bw_scale=1.3, sub=0.5, tremor=0.3)
    return trim_tail(norm(softclip(norm(v) * 1.8)), -55)


def enemy_death(rng):
    n = secs(2.8)
    t = taxis(n)
    f0 = 88 - 43 * np.clip(t / 1.7, 0, 1) ** 0.8
    env = env_points(n, [(0, 0), (0.06, 1.0), (0.6, 0.85), (1.5, 0.5), (1.85, 0)])
    v = voice(n, rng, f0, vowel_track([(0, "a"), (0.8, "o"), (1.6, "u")], 0.85), breath=env * 0.9,
              voiced=env * env_points(n, [(0, 1), (1.2, 0.6), (1.7, 0.2)]),
              fry=env_points(n, [(0, 0), (0.8, 0.3), (1.5, 1.0), (1.85, 0)]), bw_scale=1.5, sub=0.55, tremor=0.4,
              extra=uncanny_extra)
    m = secs(0.5)
    tt = taxis(m)
    slump = norm(filt(white(m, rng) * env_ad(m, 0.002, 0.07), [("lp", 260)]))
    slump += 0.7 * np.sin(2 * np.pi * osc_phase(48 + 25 * np.exp(-tt / 0.05))) * env_ad(m, 0.002, 0.09)
    out = norm(v)
    place(out, norm(slump) * 0.75, 1.9)
    place(out, norm(slump) * 0.25, 2.07)
    return trim_tail(filt(out, [("hp", 40)]), -55, 0.15)


# ---------------------------------------------------------------- ambience loops

def wind_bed(n, rng, gust, fc_lo, fc_hi, whistle=0.0, slope=-4.5):
    """Stereo periodic wind: band-limited noise whose level and brightness
    follow a periodic gust envelope (0..1)."""
    chans = []
    tg = np.arange(0, n, HOP)
    for c in range(2):
        base = colored(n, rng, slope)
        g = np.roll(gust, c * secs(0.35))  # the gust reaches each ear a little apart

        def frame(tc, freqs, g=g):
            gv = float(g[secs(tc) % n])
            fc = fc_lo + (fc_hi - fc_lo) * gv ** 1.3
            amp = 0.25 + 0.75 * gv ** 1.6
            resp = amp / np.sqrt(1.0 + (freqs / fc) ** 4) / np.sqrt(1.0 + (40.0 / np.maximum(freqs, 1)) ** 4)
            if whistle:
                fw = 480 + 300 * gv
                resp += whistle * gv ** 3 / (1.0 + ((freqs - fw) / 18.0) ** 2)
                resp += 0.5 * whistle * gv ** 3 / (1.0 + ((freqs - fw * 1.51) / 25.0) ** 2)
            return resp
        chans.append(stft_process(base, frame, nfft=2048, hop=HOP, circular=True))
    return np.stack(chans)


def ambient_wind_day(rng):
    n = loop_len(48.0)
    g = smooth_random(n, rng, 0.11, periodic=True)
    g2 = smooth_random(n, rng, 0.5, periodic=True)
    gust = np.clip(0.5 + 0.42 * g + 0.12 * g2, 0, 1)
    out = wind_bed(n, rng, gust, 260, 1500, whistle=0.06)
    rustle_mod = np.clip(gust - 0.35, 0, 1) ** 1.5 * (0.6 + 0.4 * smooth_random(n, rng, 7.0, periodic=True))
    rustle = np.stack([filt_circular(colored(n, rng, -1.0), [("hp", 2600), ("lp", 9000)]) * rustle_mod for _ in range(2)])
    out = filt_circular(out, [("hp", 45)])
    out = out / np.std(out) + 0.3 * rustle / (np.std(rustle) + 1e-9)
    return out


def ambient_night(rng):
    n = loop_len(52.0)
    g = smooth_random(n, rng, 0.06, periodic=True)
    gust = np.clip(0.35 + 0.4 * g, 0, 1)
    out = wind_bed(n, rng, gust, 160, 520, whistle=0.025, slope=-5.5)
    out = filt_circular(out, [("hp", 55)])
    out /= np.std(out)
    ir = reverb_ir(1.6, rng, predelay=0.02, bright=0.6, stereo=True)
    # house settling: a few soft creaks, panned
    for at, pan, rate in ((7.5, 0.3, 24), (26.0, 0.75, 18), (40.5, 0.5, 30)):
        m = secs(1.4)
        cr = creak(m, rng, rng.uniform(0.35, 0.6), rate, rate * 1.4,
                   [(380, 12, 1.0), (760, 15, 0.6), (1300, 18, 0.35)])
        cr = filt(norm(cr), [("lp", 1800)])
        st = np.stack([cr * np.cos(pan * np.pi / 2), cr * np.sin(pan * np.pi / 2)])
        st = add_reverb(st, ir, -6)
        place(out, st * 0.9, at, circular=True)
    # a far-off dog, three barks, deep in the fog
    dog = np.zeros(secs(1.6))
    for at in (0.0, 0.42, 0.95):
        m = secs(0.16)
        tt = taxis(m)
        env = np.sin(np.pi * np.clip(tt / 0.15, 0, 1)) ** 0.7
        b = voice(m, rng, 430 - 120 * tt / 0.16, vowel_track([(0, "a"), (0.16, "uh")], 1.25), breath=env * 0.6,
                  voiced=env, fry=None, bw_scale=1.5, chest=False)
        place(dog, norm(b), at)
    dog = filt(dog, [("lp", 1100), ("hp", 250)])
    dist_ir = reverb_ir(2.4, rng, predelay=0.05, bright=0.4, stereo=True)
    dogst = add_reverb(np.stack([dog * 0.8, dog * 0.5]), dist_ir, 0.0, dry_db=-10.0)
    place(out, dogst * 0.55, 18.0, circular=True)
    # one hesitant cricket that keeps stopping
    t = 0.0
    while t < 52.0:
        if 30.0 < t < 44.0:
            t += 1.0
            continue
        m = secs(0.12)
        tt = taxis(m)
        chirp = np.sin(2 * np.pi * 4650 * tt) * (0.5 + 0.5 * np.sin(2 * np.pi * 30 * tt - np.pi / 2)) * np.hanning(m)
        place(out, np.stack([chirp * 0.035, chirp * 0.05]), t, circular=True)
        t += rng.uniform(0.6, 1.1) if rng.random() > 0.15 else rng.uniform(3, 7)
    return out


def ambient_tension(rng):
    n = loop_len(24.0)
    t = taxis(n)
    T = n / SR
    out = np.zeros((2, n))
    for c in range(2):
        d = 0.04 * (1 if c else -1)
        for f, g in ((41.2, 1.0), (43.65, 0.7), (82.4, 0.45), (116.54, 0.25)):
            fq = qfreq(f + d, n)
            ph = fq * t
            out[c] += g * additive(ph, [1.0, 0.45, 0.25, 0.12, 0.06])
        breath = filt_circular(colored(n, rng, -6.0), [("lp", 380)])
        swell = 0.5 + 0.5 * np.sin(2 * np.pi * (4 / T) * t - np.pi / 2 + c * 0.6)
        out[c] = norm(out[c]) + 0.35 * norm(breath) * swell
        shimmer = np.sin(2 * np.pi * qfreq(1318.5, n) * t) + np.sin(2 * np.pi * qfreq(1396.9 + c * 0.7, n) * t)
        out[c] += 0.025 * shimmer * (0.5 + 0.5 * np.sin(2 * np.pi * (3 / T) * t + c))
    pulse = np.zeros(n)
    beat = T / 16
    for k in range(16):
        m = secs(0.45)
        tt = taxis(m)
        p = np.sin(2 * np.pi * 52 * tt) * env_ad(m, 0.01, 0.09)
        place(pulse, p, k * beat, circular=True)
        place(pulse, p * 0.55, k * beat + 0.24, circular=True)  # lub-dub
    out += 0.35 * np.stack([pulse, pulse])
    return filt_circular(out, [("hp", 28)])


def distant_scrape(rng):
    n = secs(4.2)
    t = taxis(n)
    stick = np.clip(smooth_random(n, rng, 35.0), 0, 1) ** 2 + 0.2
    exc = white(n, rng) * stick * env_points(n, [(0, 0), (0.6, 0.7), (1.8, 1.0), (2.6, 0.6), (3.4, 0)])
    glide = 1.0 + 0.05 * np.sin(2 * np.pi * 0.35 * t) + 0.03 * smooth_random(n, rng, 1.5)

    def frame(tc, freqs):
        gl = float(glide[min(n - 1, secs(tc))])
        forms = [(f * gl, bw, g) for f, bw, g in ((612, 14, 0), (1385, 20, -3), (2230, 26, -6), (3120, 30, -9), (940, 18, -6))]
        return formant_gain(freqs, forms) + 0.03
    sc = stft_process(exc, frame, nfft=4096, hop=512)
    sc = filt(norm(sc), [("lp", 2600), ("hp", 200)])
    ir = reverb_ir(2.8, rng, predelay=0.04, bright=0.45)
    out = add_reverb(sc, ir, 0.0, dry_db=-9.0)
    return trim_tail(out, -55, 0.4)


def distant_shriek(rng):
    n = secs(1.6)
    t = taxis(n)
    f0 = np.interp(t, [0, 0.25, 0.7, 1.3], [560, 860, 780, 520])
    env = env_points(n, [(0, 0), (0.08, 0.8), (0.4, 1.0), (1.0, 0.7), (1.4, 0)])
    vt = vowel_track([(0, "ae"), (0.5, "a"), (1.3, "uh")], 1.35)
    a = voice(n, rng, f0, vt, breath=env * 0.9, voiced=env, bw_scale=1.6, chest=False, tremor=0.35)
    b = voice(n, rng, f0 * 1.031, vt, breath=env * 0.6, voiced=env * 0.7, bw_scale=1.6, chest=False, tremor=0.5)
    sh = filt(norm(a) + 0.7 * norm(b), [("lp", 2800), ("hp", 300)])
    ir = reverb_ir(3.2, rng, predelay=0.06, bright=0.4)
    out = add_reverb(sh, ir, 0.0, dry_db=-11.0)
    return trim_tail(out, -55, 0.5)


def siren_tone(f, amp, rng):
    ph = osc_phase(f)
    ph2 = osc_phase(f * 1.2)  # the two-tone chord of a mechanical air-raid siren
    w = additive(ph, [1.0, 0.42, 0.22, 0.12, 0.07]) + 0.75 * additive(ph2, [1.0, 0.4, 0.2, 0.1])
    return w * amp


def distant_siren(rng):
    n = secs(11.5)
    t = taxis(n)
    f = np.interp(t, [0, 2.8, 5.0, 5.15, 5.6, 6.0, 9.2], [150, 470, 480, 380, 430, 420, 95])
    f *= 1.0 + 0.006 * smooth_random(n, rng, 3.0)
    amp = env_points(n, [(0, 0), (1.2, 0.6), (2.8, 1.0), (5.0, 1.0), (5.12, 0.25), (5.35, 0.9), (5.45, 0.4),
                         (5.6, 0.85), (6.2, 0.8), (8.6, 0.25), (9.4, 0)])
    amp *= 1.0 + 0.25 * smooth_random(n, rng, 0.7)  # the wind carries it in and out
    s = siren_tone(f, amp, rng)
    s = filt(s, [("lp", 1600, 0.6), ("hp", 180)])
    ir = reverb_ir(3.4, rng, predelay=0.08, bright=0.35)
    out = add_reverb(s, ir, 0.0, dry_db=-8.0)
    return trim_tail(out, -55, 0.8)


# ---------------------------------------------------------------- UI

def ui_click(rng):
    n = secs(0.09)
    t = taxis(n)
    tick = np.sin(2 * np.pi * 1850 * t) * env_ad(n, 0.0003, 0.006)
    body = np.sin(2 * np.pi * 420 * t) * env_ad(n, 0.0005, 0.012)
    nz = filt(white(n, rng) * env_ad(n, 0.0001, 0.0012), [("lp", 4500)])
    out = 0.8 * tick + 0.6 * body + 0.4 * norm(nz)
    return trim_tail(filt(out, [("lp", 6000)]), -60, 0.01)


def ui_hover(rng):
    n = secs(0.06)
    t = taxis(n)
    out = np.sin(2 * np.pi * 2400 * t) * env_ad(n, 0.002, 0.006) + 0.6 * norm(filt(white(n, rng) * env_ad(n, 0.001, 0.005), [("bp", 2600, 2)]))
    return trim_tail(filt(out, [("lp", 5000)]), -60, 0.01)


def ui_tone(rng, f_a, f_b, dur):
    n = secs(dur + 0.15)
    t = taxis(n)
    f = np.interp(t, [0, dur * 0.4, dur], [f_a, f_b, f_b])
    tone = (np.sin(2 * np.pi * osc_phase(f)) + 0.2 * np.sin(4 * np.pi * osc_phase(f))) * env_ad(n, 0.008, dur * 0.4)
    sw = white(n, rng) * env_points(n, [(0, 0), (dur * 0.3, 0.3), (dur, 0)])
    sw = filt(sw, [("bp", (f_a + f_b) * 2, 1.2)])
    return trim_tail(norm(tone) + 0.25 * norm(sw), -60, 0.03)


def ui_open(rng):
    return ui_tone(rng, 520, 780, 0.22)


def ui_close(rng):
    return ui_tone(rng, 760, 500, 0.2)


def ui_error(rng):
    n = secs(0.34)
    out = np.zeros(n)
    for at, f in ((0.0, 232.0), (0.115, 216.0)):
        m = secs(0.18)
        tt = taxis(m)
        place(out, (np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt) + 0.1 * np.sin(6 * np.pi * f * tt)) * env_ad(m, 0.004, 0.05), at)
    return trim_tail(filt(out, [("lp", 1800)]), -60, 0.03)


# ---------------------------------------------------------------- stingers

def piano_note(f0, dur, vel, rng, bright=0.5):
    """Soft felt-piano-like tone: stiff-string partials, three detuned
    strings, two-stage decay, a little hammer noise."""
    n = secs(dur)
    t = taxis(n)
    B = 0.00035
    out = np.zeros(n)
    t60 = 7.0 * (220.0 / f0) ** 0.55
    for k in range(1, 40):
        fk = k * f0 * np.sqrt(1 + B * k * k)
        if fk > 9000:
            break
        a = (1.0 / k ** (1.4 - 0.5 * vel)) * abs(np.sin(np.pi * k / 7.3)) * np.exp(-fk / (1800 + 2500 * bright * vel))
        tk = t60 / (1 + 0.35 * (k - 1))
        env = 0.65 * np.exp(-t * 6.9 / (tk * 0.25)) + 0.35 * np.exp(-t * 6.9 / tk)
        for d in (-0.9, 0.0, 1.1):
            fd = fk * 2 ** (d * (0.6 + 0.2 * k ** 0.5) / 1200)
            out += a * env * np.sin(2 * np.pi * fd * t + rng.uniform(0, 2 * np.pi)) / 3
    out *= np.clip(t / 0.004, 0, 1)
    ham = filt(white(n, rng) * env_ad(n, 0.0005, 0.006), [("lp", 1200 + 1500 * vel)])
    out = norm(out) + 0.04 * vel * norm(ham)
    return out * vel


def stinger_invasion(rng):
    n = secs(7.5)
    t = taxis(n)
    hit_t = 4.6
    cluster = np.zeros((2, n))
    for c in range(2):
        for f, g in ((55.0, 1.0), (58.27, 0.8), (82.41, 0.6), (110.0, 0.5), (155.56, 0.35), (233.08, 0.2)):
            fq = f * (1 + (0.0015 if c else -0.0015))
            cluster[c] += g * additive(fq * t, [1, 0.5, 0.33, 0.25, 0.2, 0.16, 0.13, 0.11, 0.09, 0.08])
    swell = np.clip(t / hit_t, 0, 1) ** 2.2
    after = np.exp(-np.maximum(t - hit_t, 0) / 0.9)
    lvl = np.where(t < hit_t, swell, after)

    def frame(tc, freqs):
        fc = 140 + 1500 * min(1.0, tc / hit_t) ** 2 if tc < hit_t else 1600 * np.exp(-(tc - hit_t) / 1.0) + 160
        return 1.0 / np.sqrt(1 + (freqs / fc) ** 4)
    cluster = stft_process(cluster, frame) * lvl
    rev = white(n, rng) * np.clip((t - 2.4) / (hit_t - 2.4), 0, 1) ** 3 * (t < hit_t)
    rev = filt(rev, [("hp", 1200), ("lp", 9000)])
    ghost = siren_tone(np.interp(t, [1.0, hit_t], [200, 410]), env_points(n, [(0, 0), (1.5, 0), (3.6, 0.5), (hit_t, 0)]), rng)
    ghost = filt(ghost, [("lp", 1400)])
    m = secs(3.0)
    tt = taxis(m)
    boom = np.sin(2 * np.pi * osc_phase(49 + 30 * np.exp(-tt / 0.08))) * env_ad(m, 0.002, 0.8)
    boom += 0.6 * norm(filt(white(m, rng) * env_ad(m, 0.001, 0.12), [("lp", 500)]))
    shim = np.zeros(m)
    for f in (1840, 2710, 3390, 4620, 5810):
        shim += np.sin(2 * np.pi * f * tt + rng.uniform(0, 6)) * np.exp(-tt / rng.uniform(0.5, 1.4))
    hit = norm(boom) + 0.12 * norm(shim)
    out = 0.8 * norm(cluster) + np.stack([0.18 * norm(rev)] * 2) + 0.12 * np.stack([norm(ghost)] * 2)
    place(out, np.stack([hit, hit]), hit_t, 1.1)
    ir = reverb_ir(3.2, rng, predelay=0.03, bright=0.6, stereo=True)
    out = add_reverb(out, ir, -8.0)
    return trim_tail(filt(out, [("hp", 38)]), -55, 0.5)


def stinger_dawn(rng):
    n = secs(6.5)
    t = taxis(n)
    pad = np.zeros((2, n))
    for c in range(2):
        for f, g in ((146.83, 1.0), (220.0, 0.8), (293.66, 0.55), (329.63, 0.35), (369.99, 0.4)):
            fq = f * (1 + (0.0012 if c else -0.0012))
            pad[c] += g * (np.sin(2 * np.pi * fq * t) + 0.18 * np.sin(4 * np.pi * fq * t))
    pad *= env_points(n, [(0, 0), (1.4, 0.8), (3.2, 1.0), (6.0, 0)])
    pad = filt(pad, [("lp", 1400)])
    out = 0.7 * norm(pad)
    for at, f, v in ((0.7, 440.0, 0.6), (1.5, 369.99, 0.5), (2.5, 587.33, 0.55)):
        nt = piano_note(f, 4.0, v, rng, bright=0.3)
        place(out, np.stack([nt * 0.9, nt * 0.75]) * 0.5, at)
    for at in (3.3, 3.62):
        m = secs(0.11)
        tt = taxis(m)
        ch = np.sin(2 * np.pi * osc_phase(np.interp(tt, [0, 0.11], [3200, 4700]))) * np.hanning(m)
        place(out, np.stack([ch * 0.04, ch * 0.07]), at)
    ir = reverb_ir(2.6, rng, predelay=0.02, bright=0.7, stereo=True)
    out = add_reverb(out, ir, -6.0)
    return trim_tail(out, -55, 0.6)


# ---------------------------------------------------------------- music

def music_menu(rng):
    n = loop_len(72.0)
    T = n / SR
    t = taxis(n)
    out = np.zeros((2, n))
    # drone: D2 + A2 + soft D3, slowly breathing, exactly periodic
    for c in range(2):
        for f, g in ((73.42, 1.0), (110.0, 0.55), (146.83, 0.3), (73.42 * 1.0016, 0.6)):
            fq = qfreq(f * (1 + (0.0007 if c else -0.0007)), n)
            out[c] += g * additive(fq * t, [1.0, 0.35, 0.2, 0.1, 0.06, 0.03])
        breathe = 0.7 + 0.3 * np.sin(2 * np.pi * (5 / T) * t + c * 0.8)
        out[c] *= breathe
    out = norm(out) * 0.45
    air = np.stack([filt_circular(colored(n, rng, -3.0), [("bp", 900, 0.5)]) for _ in range(2)])
    air *= 0.5 + 0.5 * np.sin(2 * np.pi * (3 / T) * t - np.pi / 2)
    out += 0.04 * air / np.std(air)
    # slow, sad piano-like plucks in D minor
    melody = [
        (1.5, [293.66, 220.0], 0.55), (5.0, [349.23], 0.45), (8.4, [329.63], 0.42), (12.2, [261.63, 220.0], 0.4),
        (17.0, [293.66], 0.5), (19.6, [261.63], 0.38), (23.2, [220.0], 0.42), (28.0, [233.08, 293.66], 0.5),
        (31.2, [349.23], 0.45), (34.6, [329.63], 0.4), (37.4, [293.66], 0.44), (42.5, [196.0, 233.08], 0.42),
        (47.0, [440.0], 0.36), (50.2, [392.0], 0.34), (53.6, [349.23], 0.38), (58.2, [329.63, 261.63], 0.42),
        (63.2, [293.66], 0.45), (66.4, [220.0], 0.35),
    ]
    for at, notes, vel in melody:
        for j, f in enumerate(notes):
            nt = piano_note(f, 9.0, vel * (0.75 if j else 1.0), rng, bright=0.35)
            pan = 0.35 + 0.3 * rng.random()
            place(out, np.stack([nt * np.cos(pan * np.pi / 2), nt * np.sin(pan * np.pi / 2)]) * 0.55,
                  at + 0.02 * j, circular=True)
    ir = reverb_ir(3.4, rng, predelay=0.03, bright=0.55, stereo=True)
    out = add_reverb(out, ir, -5.0, circular=True)
    return filt_circular(out, [("hp", 30)])


# ---------------------------------------------------------------- registry

# name: (function, category, target active RMS dBFS, loop, vorbis quality)
SOUNDS = {
    "weapon/handgun_fire": (handgun, "weapon", -12.0, False, 5),
    "weapon/dry_fire": (dry_fire, "weapon", -24.0, False, 5),
    "impact/wood": (impact_wood, "impact", -18.0, False, 4),
    "impact/plaster": (impact_plaster, "impact", -19.0, False, 4),
    "impact/glass": (impact_glass, "impact", -19.0, False, 5),
    "impact/metal": (impact_metal, "impact", -19.0, False, 4),
    "impact/flesh": (impact_flesh, "impact", -18.0, False, 4),
    "impact/ground": (impact_ground, "impact", -20.0, False, 4),
    "player/footstep_1": (lambda r: footstep(r, 0), "footstep", -27.0, False, 4),
    "player/footstep_2": (lambda r: footstep(r, 1), "footstep", -27.0, False, 4),
    "player/footstep_3": (lambda r: footstep(r, 2), "footstep", -27.0, False, 4),
    "player/footstep_4": (lambda r: footstep(r, 3), "footstep", -27.0, False, 4),
    "player/hurt": (player_hurt, "player", -19.0, False, 4),
    "player/eat": (player_eat, "player", -23.0, False, 4),
    "player/drink": (player_drink, "player", -23.0, False, 4),
    "player/bandage": (player_bandage, "player", -23.0, False, 4),
    "player/sleep": (player_sleep, "player", -24.0, False, 4),
    "player/death": (player_death, "player", -18.0, False, 4),
    "build/place": (build_place, "build", -19.0, False, 4),
    "build/hammer": (build_hammer, "build", -19.0, False, 4),
    "build/demolish": (build_demolish, "build", -18.0, False, 4),
    "build/invalid": (build_invalid, "build", -25.0, False, 4),
    "build/upgrade": (build_upgrade, "build", -19.0, False, 4),
    "door/open": (door_open, "door", -22.0, False, 4),
    "door/close": (door_close, "door", -21.0, False, 4),
    "door/bash": (door_bash, "door", -16.0, False, 4),
    "structure/break": (structure_break, "structure", -15.0, False, 4),
    "structure/crumble": (structure_crumble, "structure", -20.0, False, 4),
    "enemy/moan_1": (enemy_moan_1, "enemy", -20.0, False, 4),
    "enemy/moan_2": (enemy_moan_2, "enemy", -20.0, False, 4),
    "enemy/attack": (enemy_attack, "enemy", -17.0, False, 4),
    "enemy/hit": (enemy_hit, "enemy", -18.0, False, 4),
    "enemy/death": (enemy_death, "enemy", -18.0, False, 4),
    "ambient/wind_day": (ambient_wind_day, "ambience", -30.0, True, 2),
    "ambient/night": (ambient_night, "ambience", -33.0, True, 2),
    "ambient/tension": (ambient_tension, "ambience", -28.0, True, 2),
    "ambient/distant_1": (distant_scrape, "distant", -20.0, False, 3),
    "ambient/distant_2": (distant_shriek, "distant", -20.0, False, 3),
    "ambient/distant_3": (distant_siren, "distant", -20.0, False, 3),
    "ui/click": (ui_click, "ui", -24.0, False, 5),
    "ui/hover": (ui_hover, "ui", -31.0, False, 5),
    "ui/open": (ui_open, "ui", -27.0, False, 5),
    "ui/close": (ui_close, "ui", -27.0, False, 5),
    "ui/error": (ui_error, "ui", -25.0, False, 5),
    "stinger/invasion": (stinger_invasion, "stinger", -17.0, False, 4),
    "stinger/dawn": (stinger_dawn, "stinger", -21.0, False, 4),
    "music/menu": (music_menu, "music", -24.0, True, 3),
}

# Where a loop may start (seconds; negative = before the end). Default: anywhere.
SEAM_SEARCH = {"music/menu": (-3.0, 1.2)}

PEAK_CEILING = -1.5      # dBFS before encoding
MAX_LIMIT_DB = 6.0       # never squash more than this to reach the RMS target
DECODED_PEAK_MAX = -1.0  # dBFS after decoding


def finish(x, target, loop):
    """DC/infrasonic cleanup, loudness normalisation, peak safety."""
    if not loop:
        x = filt(x, [("hp", 22, 0.7)])
        x = fade(x, fin=0.0004)
    else:
        x = filt_circular(x, [("hp", 22, 0.7)])
    gain = target - active_rms_db(x)
    y = x * undb(gain)
    over = peak_db(y) - PEAK_CEILING
    if over > 0:
        if loop or over > MAX_LIMIT_DB:
            y = y * undb(-max(0.0, over - (0 if loop else MAX_LIMIT_DB)))
        if not loop:
            y = limit(y, PEAK_CEILING)
    return y


def encode(x, path, q):
    chans = 2 if x.ndim == 2 else 1
    data = (x.T if chans == 2 else x).astype(np.float32).tobytes()
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(SR),
                    "-ac", str(chans), "-i", "-", "-c:a", "libvorbis", "-q:a", str(q),
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(path)],
                   input=data, check=True)


def decode(path, chans):
    out = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path), "-f", "f32le",
                          "-ac", str(chans), "-"], capture_output=True, check=True).stdout
    y = np.frombuffer(out, np.float32).astype(np.float64)
    return y.reshape(-1, chans).T if chans == 2 else y


def seam_step(y):
    """Largest second-difference jump across the wrap-around (end -> start)."""
    st = y if y.ndim == 2 else y[None, :]
    return max(abs((c[0] - c[-1]) - (c[-1] - c[-2])) for c in st)


def seam_rotation(x, q, search=None, candidates=6):
    """Vorbis reconstructs the first and last samples of a file less exactly
    when the signal is far from zero there, which can tick at the loop point.
    The loops are exactly periodic, so rotate them to start where all
    channels are quiet and slow, and keep the candidate whose encoded seam
    is smoothest. search = (from_s, to_s), may be negative (before the end)."""
    n = x.shape[-1]
    st = x if x.ndim == 2 else x[None, :]
    lo, hi = (secs(search[0]), secs(search[1])) if search else (0, n)
    idx = np.arange(lo, hi) % n
    score = np.abs(st[:, idx]).sum(0) + 4 * np.abs(st[:, (idx + 1) % n] - st[:, idx]).sum(0)
    picks = []
    for o in np.argsort(score):
        if all(abs(int(o) - p) > secs(0.01) for p in picks):
            picks.append(int(o))
        if len(picks) >= candidates:
            break
    best = None
    with tempfile.TemporaryDirectory() as tmp:
        probe = Path(tmp) / "seam.ogg"
        for p in picks:
            r = np.roll(x, -int(idx[p]), axis=-1)
            encode(r, probe, q)
            d = seam_step(decode(probe, st.shape[0]))
            if best is None or d < best[0]:
                best = (d, r)
    return best[1]


IMPORT_TEMPLATE = """[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"

[params]

loop={loop}
loop_offset=0.0
bpm=0.0
beat_count=0
bar_beats=4
"""


def write_import(ogg, loop):
    imp = ogg.with_name(ogg.name + ".import")
    flag = "true" if loop else "false"
    if imp.exists():
        lines = imp.read_text().splitlines()
        lines = [("loop=" + flag) if ln.startswith("loop=") else ln for ln in lines]
        imp.write_text("\n".join(lines) + "\n")
    else:
        imp.write_text(IMPORT_TEMPLATE.format(loop=flag))


def out_path(name):
    group, base = name.split("/")
    return OUT / group / ("template_%s.ogg" % base)


def build(name):
    fn, cat, target, loop, q = SOUNDS[name]
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    x = finish(fn(rng), target, loop)
    if loop:
        x = seam_rotation(x, q, SEAM_SEARCH.get(name))
    path = out_path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    chans = 2 if x.ndim == 2 else 1
    for _ in range(4):
        encode(x, path, q)
        y = decode(path, chans)
        pk = peak_db(y)
        if pk <= DECODED_PEAK_MAX:
            break
        x = x * undb(DECODED_PEAK_MAX - pk - 0.3)
    write_import(path, loop)
    print("%-22s %5.2fs %s rms %6.1f peak %6.1f  %6.1f KB" % (
        name, x.shape[-1] / SR, "st" if chans == 2 else "mo", active_rms_db(x), pk, path.stat().st_size / 1024))
    return path


if __name__ == "__main__":
    names = sys.argv[1:] or list(SOUNDS)
    for nm in names:
        if nm not in SOUNDS:
            sys.exit("unknown sound " + nm)
        build(nm)
