# slice_sfx.py — prepares the ElevenLabs sound effects for the game (run inside Blender, which
# ships the `aud` audio library):
#   blender --background --factory-startup --python tools/slice_sfx.py -- <raw_dir> <out_dir>
#
#   loops      (*_loop, loco_idle, crt_hum)  copied as they are: generated as seamless loops
#   multi-hit  (step_*, pc_keys)             cut at each onset into name_1.wav, name_2.wav, …
#                                            (pc_keys -> pc_key_N)
#   one-shots  (everything else)             leading/trailing silence trimmed, faded, normalised
import os
import shutil
import sys

import aud
import numpy as np

LOOPS = {"rail_loop", "wind_loop", "loco_idle", "crt_hum"}
MULTI = {"step_wood": "step_wood", "step_carpet": "step_carpet", "step_metal": "step_metal",
         "step_snow": "step_snow", "pc_keys": "pc_key"}
FIRST_HIT = {"pc_click", "land"}         # keep only the first hit of these
PEAK = 10 ** (-3 / 20)


def load(path):
    snd = aud.Sound(path)
    rate, _channels = snd.specs
    data = snd.data()                      # (frames, channels) float32
    if data.ndim == 1:
        data = data[:, None]
    return data.astype(np.float32), int(rate)


def save(path, data, rate):
    peak = float(np.max(np.abs(data))) or 1.0
    data = data * (PEAK / peak)
    buf = aud.Sound.buffer(np.ascontiguousarray(data, dtype=np.float32), rate)
    buf.write(path, rate=rate, channels=aud.CHANNELS_STEREO if data.shape[1] > 1 else aud.CHANNELS_MONO,
              format=aud.FORMAT_S16, container=aud.CONTAINER_WAV, codec=aud.CODEC_PCM)


def envelope(data, rate, win=0.01):
    mono = np.abs(data).mean(axis=1)
    n = max(1, int(rate * win))
    frames = len(mono) // n
    return mono[: frames * n].reshape(frames, n).max(axis=1), n


def fade(data, rate, fin=0.004, fout=0.04):
    a = int(rate * fin)
    b = int(rate * fout)
    data = data.copy()
    if a > 0 and len(data) > a:
        data[:a] *= np.linspace(0, 1, a)[:, None]
    if b > 0 and len(data) > b:
        data[-b:] *= np.linspace(1, 0, b)[:, None]
    return data


def trim(data, rate):
    env, n = envelope(data, rate)
    top = env.max() or 1.0
    on = np.nonzero(env > top * 0.03)[0]
    if len(on) == 0:
        return data
    start = max(0, (on[0] - 1) * n)
    end = min(len(data), (on[-1] + 4) * n)
    return fade(data[start:end], rate, 0.003, 0.08)


def slice_hits(data, rate, max_hits=10):
    env, n = envelope(data, rate)
    top = env.max() or 1.0
    thr = top * 0.22
    hits = []
    last = -10 ** 9
    for i in range(1, len(env)):
        if env[i] > thr and env[i - 1] <= thr and (i - last) * n > rate * 0.16:
            hits.append(i)
            last = i
    out = []
    for k, h in enumerate(hits[:max_hits]):
        start = max(0, (h - 1) * n)
        nxt = hits[k + 1] * n - int(rate * 0.02) if k + 1 < len(hits) else len(data)
        end = min(nxt, start + int(rate * 0.5), len(data))
        piece = data[start:end]
        if len(piece) > rate * 0.05:
            out.append(fade(piece, rate, 0.002, 0.05))
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    raw, out = argv[0], argv[1]
    os.makedirs(out, exist_ok=True)
    for fn in sorted(os.listdir(raw)):
        if not fn.endswith(".mp3"):
            continue
        name = fn[:-4]
        src = os.path.join(raw, fn)
        if name in LOOPS:
            shutil.copy(src, os.path.join(out, fn))
            print("loop     ", name)
            continue
        data, rate = load(src)
        if name in MULTI:
            pieces = slice_hits(data, rate)
            for i, p in enumerate(pieces):
                save(os.path.join(out, "%s_%d.wav" % (MULTI[name], i + 1)), p, rate)
            print("sliced   ", name, len(pieces))
        elif name in FIRST_HIT:
            pieces = slice_hits(data, rate)
            t = pieces[0] if pieces else trim(data, rate)
            save(os.path.join(out, name + ".wav"), t, rate)
            print("first hit", name, "%.2fs" % (len(t) / rate))
        else:
            t = trim(data, rate)
            save(os.path.join(out, name + ".wav"), t, rate)
            print("one-shot ", name, "%.2fs" % (len(t) / rate))


main()
