# bake_dread.py — bakes the two seamless horror drone loops that DreadBed (scripts/audio/dread_bed.gd)
# swells under the shift. Needs numpy, so run it with Blender's Python:
#   blender --background --factory-startup --python tools/bake_dread.py -- assets/audio
#
#   dread_low.wav   a dark sub drone: two detuned low tones beating slowly, a tritone under them,
#                   and a band of rumbling noise that breathes
#   dread_high.wav  the tension layer: a close minor-second cluster that wavers, a faint
#                   harmonic shimmer and two breaths of air per loop
# Every frequency is a whole number of cycles per loop and the noise is shaped in the frequency
# domain, so both files loop without a seam.
import os
import sys
import wave

import numpy as np

RATE = 44100
SECONDS = 16.0
N = int(RATE * SECONDS)
T = np.arange(N) / RATE
PEAK = 10 ** (-3 / 20)
rng = np.random.default_rng(1931)


def hz(f):
    """Nearest frequency that fits a whole number of cycles in the loop."""
    return round(f * SECONDS) / SECONDS


def tone(f, phase=0.0, fm=0.0, depth=0.0):
    f = hz(f)
    mod = depth * np.sin(2 * np.pi * hz(fm) * T) if fm else 0.0
    return np.sin(2 * np.pi * f * T + phase + mod)


def band_noise(lo, hi, tilt=0.0):
    spec = np.fft.rfft(rng.standard_normal(N))
    fr = np.fft.rfftfreq(N, 1 / RATE)
    mask = ((fr >= lo) & (fr <= hi)).astype(float)
    mask[1:] *= (fr[1:] / max(lo, 1.0)) ** tilt
    x = np.fft.irfft(spec * mask, N)
    return x / (np.abs(x).max() + 1e-9)


def slow(cycles, phase=0.0):
    """A slow 0..1 swell, `cycles` times per loop."""
    return 0.5 + 0.5 * np.sin(2 * np.pi * cycles * T / SECONDS + phase)


def low_layer(side):
    d = 0.19 * side                                   # each ear beats a little differently
    x = (tone(36.75) + 0.8 * tone(36.75 + 0.25 + d, 1.0)
         + 0.45 * tone(52.0 + d, 2.0) + 0.3 * tone(73.5, 0.5, fm=3 / SECONDS, depth=1.5)
         + 0.12 * tone(110.25 - d, 1.3))
    x *= 0.7 + 0.3 * slow(2, side)
    x += 0.35 * band_noise(28.0, 170.0, -1.0) * (0.5 + 0.5 * slow(3, 1.0 + side))
    return np.tanh(1.3 * x)


def high_layer(side):
    d = 0.125 * side
    x = (tone(220.0, 0.0, fm=3 / SECONDS, depth=2.0) + 0.85 * tone(233.0 + d, 1.0, fm=2 / SECONDS, depth=2.5)
         + 0.5 * tone(311.0 - d, 2.0, fm=5 / SECONDS, depth=1.5) + 0.12 * tone(466.0 + d, 0.3)
         + 0.06 * tone(659.0, 1.1, fm=7 / SECONDS, depth=3.0))
    x *= 0.55 + 0.45 * slow(1, 0.7 * side)
    air = band_noise(1500.0, 4200.0) * slow(2, 3.0 + side) ** 4
    return np.tanh(0.9 * x) + 0.18 * air


def write(path, left, right):
    st = np.stack([left, right], axis=1)
    st *= PEAK / np.abs(st).max()
    pcm = (st * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print("wrote", path)


out = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "assets/audio"
write(os.path.join(out, "dread_low.wav"), low_layer(-1.0), low_layer(1.0))
write(os.path.join(out, "dread_high.wav"), high_layer(-1.0), high_layer(1.0))
