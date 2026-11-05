"""The textures of the anomalies' monster face and what they leave behind (AnomalyFrenzy):
    python make_textures.py          (Blender's own python: it has OpenImageIO and numpy)

From art_source/frenzy/raw (Poly Haven, CC0; see README.md), re-encoded so nothing of the downloads but
their pixels comes through:
    skin_n.png        wrinkled, pored hide: normal map (OpenGL), tiles
    skin_mask.png     R roughness, G height, B cracks, tiles
Made here:
    face_map.png      R veins (a grown, branching tree: thick at the sockets and the mouth, height), G their
                      core (only the thick ones), B blotches. Face space: 0.17 m square, eyes in the upper half.
    hand_print.png    a hand in pale grave-ash on the floor, which is dark wood and dark carpet (RGBA)
    claw_marks.png    four pale furrows torn in the floor (RGBA)
"""
import os
import numpy as np
import OpenImageIO as oiio

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "textures", "frenzy"))
os.makedirs(OUT, exist_ok=True)
SIZE = 1024
rng = np.random.default_rng(1913)


def load(name):
    b = oiio.ImageBuf(os.path.join(RAW, name))
    if b.has_error:
        raise RuntimeError(b.geterror())
    px = b.get_pixels(oiio.FLOAT)
    return px if px.ndim == 3 else px[..., None]


def shrink(a, f):
    h, w = a.shape[:2]
    return a[:h - h % f, :w - w % f].reshape(h // f, f, w // f, f, -1).mean(axis=(1, 3))


def save(name, a):
    a = np.clip(a, 0.0, 1.0)
    h, w = a.shape[:2]
    spec = oiio.ImageSpec(w, h, a.shape[2], oiio.UINT8)
    o = oiio.ImageOutput.create(os.path.join(OUT, name))
    o.open(os.path.join(OUT, name), spec)
    o.write_image(a.astype(np.float32))
    o.close()
    print(name, w, h, a.shape[2], os.path.getsize(os.path.join(OUT, name)) // 1024, "KB")


def blur(a, r):
    """Wrapping box blur, three passes: close enough to a Gaussian."""
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(np.concatenate([np.take(a, range(-r - 1, 0), axis=ax), a, np.take(a, range(0, r), axis=ax)], axis=ax), axis=ax)
            hi = np.take(c, range(2 * r + 1, c.shape[ax]), axis=ax)
            lo = np.take(c, range(0, c.shape[ax] - 2 * r - 1), axis=ax)
            a = (hi - lo) / (2 * r + 1)
    return a


def fbm(n, cells, octaves, seed):
    """Tileable value noise, octaves summed, 0..1."""
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        g = r.random((c, c))
        x = np.arange(n) * c / n
        i = x.astype(int)
        f = x - i
        f = f * f * (3 - 2 * f)
        j = (i + 1) % c
        i %= c
        row = g[i][:, i] * (1 - f)[None, :] + g[i][:, j] * f[None, :]
        row2 = g[j][:, i] * (1 - f)[None, :] + g[j][:, j] * f[None, :]
        out += amp * (row * (1 - f)[:, None] + row2 * f[:, None])
        tot += amp
        amp *= 0.5
    return out / tot


def skin():
    n = shrink(load("fabric_leather_01_nor_gl_2k.jpg")[..., :3], 2)
    r = shrink(load("fabric_leather_01_rough_2k.jpg")[..., :1], 2)[..., 0]
    h = shrink(load("fabric_leather_01_disp_2k.jpg")[..., :1], 2)[..., 0]
    c = shrink(load("mud_cracked_dry_03_disp_2k.jpg")[..., :1], 2)[..., 0]
    # The cracks are the low ground of the dried mud.
    low = blur(c, 28)
    cr = np.clip((low - c - 0.015) / 0.06, 0.0, 1.0)
    h = (h - h.min()) / (h.max() - h.min())
    save("skin_n.png", n)
    save("skin_mask.png", np.dstack([r, h, cr]))


# ————— veins: space colonisation, seeds round the sockets and the mouth, growing out over the face —————

def veins():
    n = SIZE
    # Face space, x -1..1, y -1..1 (y up), 0.17 m across in all.
    seeds = []
    for ex in (-0.37, 0.37):
        for a in np.linspace(0, 2 * np.pi, 6, endpoint=False):
            seeds.append((ex + 0.11 * np.cos(a), 0.3 + 0.08 * np.sin(a)))
    seeds += [(-0.43, -0.42), (0.43, -0.42), (-0.5, -0.5), (0.5, -0.5), (-0.12, -0.72), (0.15, -0.74), (0.0, 0.62), (-0.8, 0.05), (0.8, 0.0)]
    nodes = np.array(seeds, float)
    parent = [-1] * len(nodes)
    # Attractors, thinner up the middle of the forehead and the nose.
    att = rng.uniform(-1.05, 1.05, (5200, 2))
    keep = rng.random(len(att)) < (0.25 + 0.75 * np.clip(np.abs(att[:, 0]) / 0.3, 0, 1))
    att = att[keep]
    REACH, KILL, STEP = 0.2, 0.024, 0.016
    for it in range(170):
        if len(att) == 0:
            break
        d = np.linalg.norm(att[:, None, :] - nodes[None, :, :], axis=2)
        near = d.argmin(axis=1)
        dist = d[np.arange(len(att)), near]
        grow = {}
        for a in np.where(dist < REACH)[0]:
            v = att[a] - nodes[near[a]]
            grow.setdefault(int(near[a]), []).append(v / max(np.linalg.norm(v), 1e-6))
        if not grow:
            break
        new = []
        for k, vs in grow.items():
            v = np.mean(vs, axis=0) + rng.normal(0, 0.28, 2)     # a wander, or they run straight as rulers
            v /= max(np.linalg.norm(v), 1e-6)
            new.append(nodes[k] + v * STEP)
            parent.append(k)
        nodes = np.vstack([nodes, new])
        d = np.linalg.norm(att[:, None, :] - nodes[None, :, :], axis=2).min(axis=1)
        att = att[d > KILL]
    print("vein nodes", len(nodes))
    # Thickness: the pipe model, from the tips in.
    w = np.full(len(nodes), 1.0)
    for i in range(len(nodes) - 1, -1, -1):
        p = parent[i]
        if p >= 0:
            w[p] = (w[p] ** 2.3 + w[i] ** 2.3) ** (1 / 2.3)
    height = np.zeros((n, n))
    core = np.zeros((n, n))
    to_px = lambda q: (q + 1.0) * 0.5 * (n - 1)
    for i in range(len(nodes)):
        p = parent[i]
        if p < 0:
            continue
        r = 0.9 + 1.25 * w[i] ** 0.62                         # px
        a, b = to_px(nodes[i]), to_px(nodes[p])
        lo = np.floor(np.minimum(a, b) - r - 2).astype(int).clip(0, n - 1)
        hi = np.ceil(np.maximum(a, b) + r + 2).astype(int).clip(0, n - 1)
        ys, xs = np.mgrid[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1]
        ab = b - a
        t = np.clip(((xs - a[0]) * ab[0] + (ys - a[1]) * ab[1]) / max(ab @ ab, 1e-6), 0, 1)
        d = np.hypot(xs - a[0] - t * ab[0], ys - a[1] - t * ab[1])
        v = np.clip(1.0 - (d / r) ** 2, 0, 1)
        v = np.sqrt(v)
        reg = height[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1]
        np.maximum(reg, v, out=reg)
        if w[i] > 3.2:
            reg = core[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1]
            np.maximum(reg, v * min(1.0, (w[i] - 3.2) / 5.0), out=reg)
    blot = fbm(n, 5, 5, 7)
    blot = np.clip((blot - 0.46) / 0.2, 0, 1)
    # (rows run top-down in the file, y up here)
    save("face_map.png", np.dstack([height, core, blot])[::-1])


# ————— what it leaves behind —————

def seg(xs, ys, a, b):
    ab = np.array(b, float) - a
    t = np.clip(((xs - a[0]) * ab[0] + (ys - a[1]) * ab[1]) / (ab @ ab), 0, 1)
    return np.hypot(xs - a[0] - t * ab[0], ys - a[1] - t * ab[1]), t


def hand_print():
    n = 256
    ys, xs = np.mgrid[0:n, 0:n] / (n - 1.0)
    wob = (fbm(n, 6, 4, 3) - 0.5) * 0.05
    d = np.hypot((xs - 0.5) / 0.17, (ys - 0.62) / 0.17)
    m = np.clip((1.0 - d) * 8.0, 0, 1)
    for tip, base, r in (((0.2, 0.42), (0.34, 0.6), 0.036), ((0.27, 0.14), (0.4, 0.5), 0.03), ((0.42, 0.06), (0.46, 0.46), 0.031),
                         ((0.57, 0.08), (0.53, 0.46), 0.03), ((0.72, 0.17), (0.61, 0.5), 0.027)):
        dd, t = seg(xs + wob, ys + wob, np.array(tip), base)
        m = np.maximum(m, np.clip((r * (0.55 + 0.45 * t) - dd) * 80.0, 0, 1))
    grain = fbm(n, 12, 4, 5)
    a = m * np.clip((grain - 0.3) * 3.2, 0.12, 1.0)
    rgb = np.dstack([0.5 + 0.2 * grain, 0.46 + 0.2 * grain, 0.46 + 0.22 * grain])
    save("hand_print.png", np.dstack([rgb, a]))


def claw_marks():
    n = 512
    ys, xs = np.mgrid[0:n, 0:n] / (n - 1.0)
    wob = (fbm(n, 4, 4, 11) - 0.5) * 0.03
    fine = fbm(n, 40, 2, 12)
    m = np.zeros((n, n))
    for x0, x1, y0, y1, r in ((0.2, 0.3, 0.1, 0.92, 0.012), (0.38, 0.44, 0.04, 0.97, 0.016), (0.56, 0.58, 0.07, 0.96, 0.015), (0.73, 0.71, 0.15, 0.86, 0.011)):
        t = np.clip((ys - y0) / (y1 - y0), 0, 1)
        cx = x0 + (x1 - x0) * t + 0.04 * np.sin(t * 2.6) + wob
        w = r * np.sin(np.pi * t) ** 0.55
        m = np.maximum(m, np.clip((w - np.abs(xs - cx)) / (0.5 * r), 0, 1) * ((ys > y0) & (ys < y1)))
    a = m * np.clip((fine - 0.22) * 4.0, 0.25, 1.0)
    rgb = np.dstack([0.56 + 0.2 * fine, 0.48 + 0.2 * fine, 0.42 + 0.2 * fine])
    save("claw_marks.png", np.dstack([rgb, a]))


skin()
veins()
hand_print()
claw_marks()
