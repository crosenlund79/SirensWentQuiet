"""Small numpy-only DSP toolkit for the template sounds (no scipy).

Conventions: float64 arrays at SR, mono = shape (n,), stereo = shape (2, n).
Filters are exact IIR responses applied in the frequency domain (causal, the
same phase as the time-domain biquad), with enough zero padding that the
impulse response doesn't wrap. Loops use circular processing, so anything
built from periodic parts stays seamless.
"""
import numpy as np

SR = 44100


def secs(s):
    return int(round(s * SR))


def taxis(n):
    return np.arange(n) / SR


def db(x):
    return 20.0 * np.log10(np.maximum(x, 1e-12))


def undb(d):
    return 10.0 ** (d / 20.0)


def next_pow2(n):
    return 1 << int(np.ceil(np.log2(max(2, n))))


# ---------------------------------------------------------------- noise

def white(n, rng):
    return rng.standard_normal(n)


def colored(n, rng, slope_db_oct):
    """Periodic noise (length n) with a spectral slope in dB/octave
    (-3 pink, -6 brown). Built in the frequency domain, so it loops."""
    k = n // 2 + 1
    spec = rng.standard_normal(k) + 1j * rng.standard_normal(k)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1]
    spec *= (f / 1000.0) ** (slope_db_oct / 6.0206)
    spec[0] = 0.0
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def smooth_random(n, rng, rate_hz, periodic=False):
    """Slow random control signal (roughly -1..1) with energy below rate_hz.
    periodic=True makes it loop exactly over n samples."""
    if periodic:
        k = n // 2 + 1
        f = np.fft.rfftfreq(n, 1.0 / SR)
        spec = (rng.standard_normal(k) + 1j * rng.standard_normal(k)) * np.exp(-(f / rate_hz) ** 2)
        spec[0] = 0.0
        x = np.fft.irfft(spec, n)
    else:
        m = max(4, int(n / SR * rate_hz * 4) + 4)
        pts = rng.standard_normal(m)
        xp = np.linspace(0, n, m)
        x = np.interp(np.arange(n), xp, pts)
        # smooth the linear interpolation with a raised-cosine kernel
        w = max(3, int(SR / rate_hz / 4))
        ker = np.hanning(w)
        ker /= ker.sum()
        x = np.convolve(x, ker, mode="same")
    return x / (np.max(np.abs(x)) + 1e-12)


# ---------------------------------------------------------------- filters

def biquad(kind, f0, q=0.7071, gain_db=0.0):
    """RBJ cookbook coefficients (b, a), a[0] == 1."""
    f0 = min(max(f0, 5.0), SR * 0.49)
    w0 = 2 * np.pi * f0 / SR
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2 * q)
    A = 10 ** (gain_db / 40.0)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":  # 0 dB peak gain
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "lowshelf":
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sq)]
        a = [(A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sq]
    elif kind == "highshelf":
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sq)]
        a = [(A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sq]
    else:
        raise ValueError(kind)
    b = np.array(b) / a[0]
    a = np.array(a) / a[0]
    return b, a


def _response(stages, nfft):
    w = 2 * np.pi * np.arange(nfft // 2 + 1) / nfft
    z1 = np.exp(-1j * w)
    z2 = z1 * z1
    h = np.ones_like(z1)
    tail = 0
    for st in stages:
        b, a = biquad(*st)
        h *=(b[0] + b[1] * z1 + b[2] * z2) / (a[0] + a[1] * z1 + a[2] * z2)
        r = np.max(np.abs(np.roots(a)))
        if r < 1:
            tail = max(tail, int(np.log(1e-6) / np.log(r)))
    return h, tail


def filt(x, stages, keep_tail=False):
    """Cascade of biquads, e.g. [("lp", 800), ("hp", 60, 0.7)]. Causal.
    Works on mono or stereo. keep_tail extends the output by the ringing."""
    if x.ndim == 2:
        return np.stack([filt(c, stages, keep_tail) for c in x])
    _, tail = _response(stages, 64)
    tail = min(tail, secs(6.0))
    nfft = next_pow2(len(x) + tail + 1)
    h, _ = _response(stages, nfft)
    y = np.fft.irfft(np.fft.rfft(x, nfft) * h, nfft)
    return y[: len(x) + (tail if keep_tail else 0)]


def filt_circular(x, stages):
    """Same filter, circular (for loops: the ringing wraps around)."""
    if x.ndim == 2:
        return np.stack([filt_circular(c, stages) for c in x])
    w = 2 * np.pi * np.arange(len(x) // 2 + 1) / len(x)
    hh = np.ones(len(w), complex)
    z1 = np.exp(-1j * w)
    for st in stages:
        b, a = biquad(*st)
        hh *= (b[0] + b[1] * z1 + b[2] * z1 * z1) / (a[0] + a[1] * z1 + a[2] * z1 * z1)
    return np.fft.irfft(np.fft.rfft(x) * hh, len(x))


def spectral(x, gain_fn, circular=False):
    """Zero-phase magnitude filter: gain_fn(freqs) -> gains."""
    if x.ndim == 2:
        return np.stack([spectral(c, gain_fn, circular) for c in x])
    n = len(x) if circular else next_pow2(len(x) + secs(0.25))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    y = np.fft.irfft(np.fft.rfft(x, n) * gain_fn(f), n)
    return y[: len(x)]


def resonators(x, modes, keep_tail=True):
    """Parallel band-pass resonators: modes = [(freq, q, gain), ...]."""
    out = None
    for f0, q, g in modes:
        if f0 >= SR * 0.45:
            continue
        y = filt(x, [("bp", f0, q)], keep_tail=keep_tail) * g
        if out is None:
            out = y
        else:
            m = max(len(out), len(y))
            out = pad_to(out, m) + pad_to(y, m)
    return out


def stft_process(x, frame_fn, nfft=2048, hop=512, circular=False):
    """Time-varying spectral processing. frame_fn(t_seconds, freqs) returns
    a gain (or complex) vector. sqrt-Hann analysis/synthesis, 75 % overlap.
    circular=True needs len(x) % hop == 0 and gives an exactly periodic result."""
    if x.ndim == 2:
        return np.stack([stft_process(c, frame_fn, nfft, hop, circular) for c in x])
    n = len(x)
    win = np.sqrt(np.hanning(nfft + 1)[:-1])
    norm = (nfft / hop) / 2.0  # periodic Hann at this overlap sums to nfft/hop/2
    freqs = np.fft.rfftfreq(nfft, 1.0 / SR)
    if circular:
        assert n % hop == 0 and nfft % hop == 0
        pad = nfft
        xe = np.concatenate([x[-pad:], x, x[:pad]])
    else:
        pad = nfft
        xe = np.concatenate([np.zeros(pad), x, np.zeros(pad)])
    ye = np.zeros(len(xe) + nfft)
    for start in range(0, len(xe) - nfft + 1, hop):
        seg = xe[start:start + nfft] * win
        tc = (start + nfft / 2 - pad) / SR
        if circular:
            tc = tc % (n / SR)
        spec = np.fft.rfft(seg) * frame_fn(tc, freqs)
        ye[start:start + nfft] += np.fft.irfft(spec, nfft) * win
    return ye[pad:pad + n] / norm


def formant_gain(freqs, formants, tilt_db_oct=0.0):
    """Spectral envelope: sum of resonance peaks [(F, bandwidth, gain_db)]."""
    g = np.zeros_like(freqs)
    for F, bw, gdb in formants:
        g += undb(gdb) / (1.0 + ((freqs - F) / (bw / 2.0)) ** 2)
    if tilt_db_oct:
        g *= (np.maximum(freqs, 50.0) / 500.0) ** (tilt_db_oct / 6.0206)
    return g


# ---------------------------------------------------------------- shaping

def pad_to(x, n):
    if x.shape[-1] >= n:
        return x[..., :n]
    widths = [(0, 0)] * (x.ndim - 1) + [(0, n - x.shape[-1])]
    return np.pad(x, widths)


def place(buf, x, at_s, gain=1.0, circular=False):
    """Mixes x into buf starting at at_s seconds (wrapping if circular)."""
    i = secs(at_s)
    n = buf.shape[-1]
    m = x.shape[-1]
    if circular:
        idx = (np.arange(m) + i) % n
        if buf.ndim == 2:
            xx = x if x.ndim == 2 else np.stack([x, x])
            for c in range(2):
                np.add.at(buf[c], idx, xx[c] * gain)
        else:
            np.add.at(buf, idx, x * gain)
        return buf
    if i >= n:
        return buf
    m = min(m, n - i)
    if buf.ndim == 2 and x.ndim == 1:
        buf[:, i:i + m] += x[:m] * gain
    else:
        buf[..., i:i + m] += x[..., :m] * gain
    return buf


def env_ad(n, attack, decay, curve=1.0):
    """Attack (linear) then exponential decay with time constant `decay`."""
    t = taxis(n)
    a = np.clip(t / max(attack, 1e-5), 0, 1) ** curve
    return a * np.exp(-np.maximum(t - attack, 0) / decay)


def env_points(n, pts):
    """Piecewise-linear envelope from [(t_seconds, value), ...]."""
    ts = np.array([p[0] for p in pts]) * SR
    vs = np.array([p[1] for p in pts])
    return np.interp(np.arange(n), ts, vs)


def fade(x, fin=0.0, fout=0.0):
    x = x.copy()
    n = x.shape[-1]
    if fin > 0:
        k = min(n, secs(fin))
        x[..., :k] *= np.sin(np.linspace(0, np.pi / 2, k)) ** 2
    if fout > 0:
        k = min(n, secs(fout))
        x[..., n - k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return x


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def osc_phase(freq):
    """Phase (in cycles) from an instantaneous frequency track."""
    return np.cumsum(freq) / SR


def additive(phase_cycles, amps):
    """Sum of harmonics sin(2 pi k phase) * amps[k-1]."""
    out = np.zeros_like(phase_cycles)
    for k, a in enumerate(amps, start=1):
        if a != 0:
            out += a * np.sin(2 * np.pi * k * phase_cycles)
    return out


def trim_tail(x, floor_db=-66.0, fout=0.02):
    """Cuts trailing silence below floor_db relative to the peak, then fades."""
    mono = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
    thr = np.max(mono) * undb(floor_db)
    idx = np.nonzero(mono > thr)[0]
    end = int(idx[-1]) + secs(0.01) if len(idx) else mono.shape[0]
    x = x[..., :min(end, x.shape[-1])]
    return fade(x, fout=fout)


def to_stereo(x, width=0.0, rng=None, delay_ms=0.0):
    if x.ndim == 2:
        return x
    left = x
    right = x.copy()
    if delay_ms:
        d = secs(delay_ms / 1000.0)
        right = np.concatenate([np.zeros(d), right[:-d]]) if d else right
    return np.stack([left, right])


# ---------------------------------------------------------------- space

def reverb_ir(rt60, rng, predelay=0.008, bright=1.0, stereo=False, early=6, size=1.0):
    """Synthetic room response: band-split decaying noise (highs decay
    faster) plus a few early reflections. Energy-normalised."""
    n = secs(rt60 * 1.3 + predelay + 0.05)
    t = taxis(n)
    chans = []
    for c in range(2 if stereo else 1):
        noise = rng.standard_normal(n)
        ir = np.zeros(n)
        bands = [(0, 400, 1.0), (400, 1600, 0.85), (1600, 5000, 0.62 * bright), (5000, 20000, 0.38 * bright)]
        spec = np.fft.rfft(noise)
        f = np.fft.rfftfreq(n, 1.0 / SR)
        for lo, hi, k in bands:
            band = np.fft.irfft(spec * ((f >= lo) & (f < hi)), n)
            ir += band * np.exp(-6.9078 * t / max(rt60 * k, 0.02))
        ir *= np.clip((t - predelay) / 0.004, 0, 1)
        for j in range(early):
            et = predelay * 0.5 + rng.uniform(0.004, 0.035) * size * (1 + j * 0.4)
            i = secs(et)
            if i < n:
                ir[i] += rng.choice([-1, 1]) * rng.uniform(0.6, 1.4) * np.sqrt(np.mean(ir ** 2)) * 40 * np.exp(-et * 8)
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
        chans.append(ir)
    return np.stack(chans) if stereo else chans[0]


def convolve(x, ir, circular=False):
    """FFT convolution. Linear output grows by len(ir)-1 unless circular."""
    if x.ndim == 2 or ir.ndim == 2:
        xs = x if x.ndim == 2 else np.stack([x, x])
        irs = ir if ir.ndim == 2 else np.stack([ir, ir])
        return np.stack([convolve(xs[c], irs[c], circular) for c in range(2)])
    if circular:
        n = len(x)
        h = ir[:n] if len(ir) > n else ir
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h, n), n)
    n = next_pow2(len(x) + len(ir))
    y = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    return y[: len(x) + len(ir) - 1]


def add_reverb(x, ir, wet_db, dry_db=0.0, circular=False):
    wet = convolve(x, ir, circular)
    dry = x if circular else pad_to(x, wet.shape[-1])
    if dry.ndim == 1 and wet.ndim == 2:
        dry = np.stack([dry, dry])
    return dry * undb(dry_db) + wet * undb(wet_db)


def distance(x, fc=2200.0, rng=None):
    """Air and fog: gentle low-pass plus a highs shelf cut."""
    return filt(x, [("lp", fc, 0.6), ("highshelf", fc * 0.6, 0.7, -6.0)])


# ---------------------------------------------------------------- loudness

def frames_rms(x, win_s=0.05, hop_s=0.01):
    mono = np.sqrt(np.mean(x ** 2, axis=0)) if x.ndim == 2 else np.abs(x)
    p = (x ** 2).mean(axis=0) if x.ndim == 2 else x ** 2
    w = max(1, secs(win_s))
    h = max(1, secs(hop_s))
    if len(p) <= w:
        return np.array([np.mean(p)])
    c = np.concatenate([[0.0], np.cumsum(p)])
    starts = np.arange(0, len(p) - w + 1, h)
    return (c[starts + w] - c[starts]) / w


def active_rms_db(x, gate_db=-20.0):
    """RMS over the 50 ms windows within gate_db of the loudest window."""
    ms = frames_rms(x)
    mx = ms.max()
    sel = ms[ms >= mx * undb(gate_db) ** 2]
    return 10 * np.log10(max(sel.mean(), 1e-20))


def peak_db(x):
    return db(np.max(np.abs(x)))


def true_peak_db(x, os=4):
    """Peak of a 4x band-limited upsampled copy (inter-sample peaks)."""
    chans = x if x.ndim == 2 else x[None, :]
    best = 0.0
    for c in chans:
        n = len(c)
        spec = np.fft.rfft(c)
        up = np.fft.irfft(spec, n * os) * os
        best = max(best, np.max(np.abs(up)))
    return db(best)


def limit(x, ceiling_db=-1.5, lookahead_s=0.0015, release_s=0.05):
    """Look-ahead peak limiter (channel-linked)."""
    mono = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
    ceil = undb(ceiling_db)
    need = np.minimum(1.0, ceil / np.maximum(mono, 1e-12))
    if need.min() >= 1.0:
        return x
    la = max(1, secs(lookahead_s))
    padded = np.concatenate([need, np.ones(la)])
    from numpy.lib.stride_tricks import sliding_window_view
    gmin = sliding_window_view(padded, la + 1).min(axis=1)[: len(need)]
    # release: one-pole smoothing towards 1 (vectorised with a running min trick)
    rel = np.exp(-1.0 / max(1, secs(release_s)))
    g = gmin.copy()
    # block-wise recursion is fast enough for short one-shots
    out = np.empty_like(g)
    cur = 1.0
    for i, v in enumerate(g):
        cur = v if v < cur else v + (cur - v) * rel
        out[i] = cur
    # smooth the attack with a short moving average (stays below the need)
    ker = np.ones(la) / la
    sm = np.convolve(np.concatenate([np.ones(la - 1), out]), ker, mode="valid")
    sm = np.minimum(sm, out)
    return x * sm


def loopify(x, xfade_s):
    """Turns len(x) samples into a seamless loop of len(x) - xfade samples
    by equal-power cross-fading the tail into the head."""
    k = secs(xfade_s)
    n = x.shape[-1] - k
    head = x[..., :k]
    tail = x[..., n:n + k]
    t = np.linspace(0, np.pi / 2, k)
    out = x[..., :n].copy()
    out[..., :k] = head * np.sin(t) + tail * np.cos(t)
    return out
