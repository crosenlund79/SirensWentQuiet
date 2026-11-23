"""Analyses the template sounds and prints a Markdown table.

Run from the project root:
    python3 tools/audio/analyze.py                  # table for docs/experiment-002/audio.md
    python3 tools/audio/analyze.py --png DIR        # also writes spectrogram PNGs to DIR
    python3 tools/audio/analyze.py --check          # exit 1 if any file breaks the rules

Every file is decoded with ffmpeg (what a player would hear), then measured:
sample peak, 4x oversampled true peak, active RMS (50 ms windows within
20 dB of the loudest), a BS.1770-style gated loudness, spectral centroid,
energy below 40 Hz and above 8 kHz, DC offset, clipped samples and, for
loops, the seam (sample jump and a high-pass click detector across the
wrap-around point, plus the level change between the end and the start).
This is measurement, not listening: nothing here was auditioned by ear.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.dont_write_bytecode = True  # keep tools/audio free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from dsp import SR, db, filt, active_rms_db, peak_db, true_peak_db  # noqa: E402
import make_sounds  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def probe_channels(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                          "stream=channels,sample_rate", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout.strip().split(",")
    return int(out[1]) if len(out) > 1 else int(out[0])


def loudness_lufs(x):
    """BS.1770-style: K-weighting, 400 ms blocks (75 % overlap), -70 LUFS
    absolute and -10 LU relative gates. Short sounds use one block."""
    chans = x if x.ndim == 2 else x[None, :]
    kw = np.stack([filt(c, [("highshelf", 1681.0, 0.7071, 4.0), ("hp", 38.0, 0.5)]) for c in chans])
    n = kw.shape[1]
    blk = int(0.4 * SR)
    hop = blk // 4
    if n <= blk:
        ms = [np.sum(np.mean(kw ** 2, axis=1))]
    else:
        ms = [np.sum(np.mean(kw[:, s:s + blk] ** 2, axis=1)) for s in range(0, n - blk + 1, hop)]
    ms = np.array(ms)
    lk = -0.691 + 10 * np.log10(np.maximum(ms, 1e-20))
    ms = ms[lk > -70]
    if len(ms) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(ms.mean()) - 10
    lk = -0.691 + 10 * np.log10(ms)
    sel = ms[lk > rel]
    return -0.691 + 10 * np.log10(sel.mean())


def spectrum_stats(x):
    mono = x.mean(axis=0) if x.ndim == 2 else x
    spec = np.abs(np.fft.rfft(mono)) ** 2
    f = np.fft.rfftfreq(len(mono), 1.0 / SR)
    total = spec.sum() + 1e-20
    centroid = float((f * spec).sum() / total)
    sub = float(spec[f < 40].sum() / total * 100)
    high = float(spec[f > 8000].sum() / total * 100)
    return centroid, sub, high


def seam(x):
    """Loop seam on the wrap-around (end -> start): the second-difference
    step there in dBFS, the same step relative to the largest normal steps
    (99.9th percentile) within half a second of the seam, and the level
    change between the last and first half second."""
    chans = x if x.ndim == 2 else x[None, :]
    k = int(0.5 * SR)
    steps, ratios, levels = [], [], []
    for c in chans:
        w = np.concatenate([c[-k:], c[:k]])
        d2 = np.abs(np.diff(w, 2))
        at = abs((c[0] - c[-1]) - (c[-1] - c[-2]))
        steps.append(db(at))
        ratios.append(at / (np.percentile(d2, 99.9) + 1e-12))
        levels.append(abs(db(np.sqrt(np.mean(c[-k:] ** 2))) - db(np.sqrt(np.mean(c[:k] ** 2)))))
    return max(steps), max(ratios), max(levels)


def spectrogram_png(x, path, title):
    from PIL import Image, ImageDraw
    mono = x.mean(axis=0) if x.ndim == 2 else x
    nfft = 2048
    hop = max(64, min(1024, len(mono) // 1200))
    mono = np.pad(mono, (nfft // 2, nfft))
    win = np.hanning(nfft)
    frames = [np.abs(np.fft.rfft(mono[s:s + nfft] * win)) for s in range(0, len(mono) - nfft + 1, hop)]
    S = 20 * np.log10(np.array(frames).T + 1e-9)
    S = np.clip((S - (S.max() - 80)) / 80, 0, 1)
    # mel-spaced rows from 30 Hz to 16 kHz, interpolated between bins
    f = np.fft.rfftfreq(nfft, 1.0 / SR)
    rows = 256
    mel = np.linspace(2595 * np.log10(1 + 30 / 700), 2595 * np.log10(1 + 16000 / 700), rows)
    lf = 700 * (10 ** (mel / 2595) - 1)
    S = np.stack([np.interp(lf, f, S[:, j]) for j in range(S.shape[1])], axis=1)
    img = (S[::-1] * 255).astype(np.uint8)
    width = min(1400, max(600, img.shape[1]))
    im = Image.fromarray(img).resize((width, rows))
    wave = Image.new("L", (width, 80), 0)
    dr = ImageDraw.Draw(wave)
    step = max(1, len(mono) // width)
    for i in range(width):
        seg = mono[i * step:(i + 1) * step]
        if len(seg):
            a = int(np.max(np.abs(seg)) * 40)
            dr.line([(i, 40 - a), (i, 40 + a)], fill=200)
    out = Image.new("L", (width, rows + 80 + 14), 30)
    out.paste(wave, (0, 14))
    out.paste(im, (0, 94))
    dr = ImageDraw.Draw(out)
    dr.text((4, 1), "%s  (%.2f s)" % (title, len(mono) / SR), fill=255)
    for hz, label in ((100, "100"), (500, "500"), (1000, "1k"), (2000, "2k"), (5000, "5k"), (10000, "10k")):
        m = 2595 * np.log10(1 + hz / 700)
        y = 94 + rows - 1 - int((m - mel[0]) / (mel[-1] - mel[0]) * (rows - 1))
        for x0 in range(0, width, 8):
            dr.point((x0, y), fill=128)
        dr.text((width - 26, y - 11), label, fill=160)
    out.save(path)


def analyse(name):
    path = make_sounds.out_path(name)
    chans = probe_channels(path)
    x = make_sounds.decode(path, chans)
    loop = make_sounds.SOUNDS[name][3]
    n = x.shape[-1]
    centroid, sub, high = spectrum_stats(x)
    row = {
        "name": name, "path": path, "dur": n / SR, "ch": chans, "kb": path.stat().st_size / 1024,
        "peak": peak_db(x), "tp": true_peak_db(x), "rms": active_rms_db(x), "lufs": loudness_lufs(x),
        "centroid": centroid, "sub": sub, "high": high,
        "dc": float(np.max(np.abs(x.mean(axis=-1)))), "clip": int(np.sum(np.abs(x) >= 0.999)),
        "loop": loop, "samples": n, "x": x,
    }
    if loop:
        row["seam_db"], row["seam_ratio"], row["seam_level"] = seam(x)
    return row


def problems(r):
    out = []
    if r["peak"] > -1.0:
        out.append("peak above -1 dBFS")
    if r["clip"]:
        out.append("clipped samples")
    if r["dc"] > 0.002:
        out.append("DC offset")
    if r["sub"] > 25:
        out.append("too much energy below 40 Hz")
    if r["loop"]:
        if r["seam_db"] > r["rms"] - 30.0 and r["seam_ratio"] > 4.0:
            out.append("loop seam click")
        if r["seam_level"] > 3.0:
            out.append("loop level step")
        if r["samples"] % make_sounds.HOP:
            out.append("loop length changed by encoding")
    return out


def main():
    args = sys.argv[1:]
    png_dir = None
    if "--png" in args:
        png_dir = Path(args[args.index("--png") + 1])
        png_dir.mkdir(parents=True, exist_ok=True)
    rows = [analyse(nm) for nm in make_sounds.SOUNDS]
    bad = 0
    print("| Logical name | Dur (s) | Ch | Size (KB) | Peak (dBFS) | True peak (dBTP) | Active RMS (dBFS) | Loudness (LUFS) | Centroid (Hz) | <40 Hz % | >8 kHz % | Loop seam |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
    total = 0.0
    for r in rows:
        total += r["kb"]
        seam_txt = "—"
        if r["loop"]:
            seam_txt = "step %.0f dBFS (%.1fx local), level %.1f dB" % (r["seam_db"], r["seam_ratio"], r["seam_level"])
        print("| `%s` | %.2f | %d | %.1f | %.1f | %.1f | %.1f | %.1f | %d | %.1f | %.1f | %s |" % (
            r["name"], r["dur"], r["ch"], r["kb"], r["peak"], r["tp"], r["rms"], r["lufs"], r["centroid"],
            r["sub"], r["high"], seam_txt))
        p = problems(r)
        if p:
            bad += 1
            print("<!-- PROBLEM %s: %s -->" % (r["name"], ", ".join(p)))
        if png_dir:
            spectrogram_png(r["x"], png_dir / (r["name"].replace("/", "__") + ".png"), r["name"])
    print("\nTotal: %d files, %.0f KB (%.2f MB)." % (len(rows), total, total / 1024))
    if "--check" in args and bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
