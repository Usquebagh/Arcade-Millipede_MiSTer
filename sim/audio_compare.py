#!/usr/bin/env python3
"""Compare simulation audio (audio.raw, 48 kHz s16 mono) with a MAME -wavwrite recording.
Prints RMS levels, the best envelope alignment and its correlation, and saves an image with
both envelopes and spectrograms.
Usage: audio_compare.py audio.raw mame.wav out.png"""
import sys, wave
import numpy as np
from PIL import Image, ImageDraw

sim = np.fromfile(sys.argv[1], dtype="<i2").astype(np.float64)
w = wave.open(sys.argv[2])
ref = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64)
if w.getnchannels() == 2:
    ref = ref.reshape(-1, 2).mean(axis=1)
rate = w.getframerate()
assert rate == 48000, rate

def env(x, win=960):           # 20 ms RMS
    n = len(x) // win
    return np.sqrt((x[:n * win].reshape(n, win) ** 2).mean(axis=1))

es, er = env(sim), env(ref)
n = min(len(es), len(er))
best = (-2, 0)
for lag in range(-50, 51):       # +-1 s
    a = es[max(0, lag):n + min(0, lag)]
    b = er[max(0, -lag):n - max(0, lag)]
    m = min(len(a), len(b))
    if m > 50 and a[:m].std() > 0 and b[:m].std() > 0:
        c = np.corrcoef(a[:m], b[:m])[0, 1]
        best = max(best, (c, lag))
print(f"sim {len(sim)/48000:.2f} s, RMS {np.sqrt((sim**2).mean()):.0f}; "
      f"MAME {len(ref)/48000:.2f} s, RMS {np.sqrt((ref**2).mean()):.0f}")
print(f"envelope correlation {best[0]:.3f} at lag {best[1] * 20} ms (sim later if positive)")

def spec(x):
    hop, nfft = 960, 2048
    frames = [np.abs(np.fft.rfft(x[i:i + nfft] * np.hanning(nfft)))[:400]
              for i in range(0, len(x) - nfft, hop)]
    s = 20 * np.log10(np.array(frames).T + 1)
    s = np.clip((s - 40) / 80, 0, 1)
    return (255 * s[::-1]).astype(np.uint8)

ss, sr = spec(sim), spec(ref)
W = max(ss.shape[1], sr.shape[1])
img = Image.new("RGB", (W, 400 * 2 + 200 + 30), "black")
img.paste(Image.fromarray(ss).convert("RGB"), (0, 0))
img.paste(Image.fromarray(sr).convert("RGB"), (0, 415))
d = ImageDraw.Draw(img)
d.text((2, 2), "sim", fill="yellow"); d.text((2, 417), "MAME", fill="yellow")
top = max(es.max(), er.max(), 1)
for e, col in ((es, "red"), (er, "cyan")):
    pts = [(i, 1029 - int(190 * v / top)) for i, v in enumerate(e[:W])]
    d.line(pts, fill=col)
img.save(sys.argv[3])
