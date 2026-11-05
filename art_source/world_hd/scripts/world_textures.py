"""Turn the downloaded CC0 maps into the game texture set for the HD landscape.

Run with Blender's bundled Python (OpenImageIO + numpy):
    "<blender>/5.2/python/bin/python.exe" world_textures.py

Writes into assets/models/hd_world/textures/:
    <key>_albedo.jpg / _normal.jpg (OpenGL) / _orm.jpg (R AO, G roughness, B metal)
    fir_twig_albedo.png (RGBA, colour dilated under the cut-out so mipmaps keep no dark fringe),
    fir_twig_normal.jpg, pine_twig_*, needles_mass_* (opaque needle canopy for the far trees),
    birch_bark_*, and twig_rects.json (the twig sprites found in each atlas, in UV space).
"""
import os, json, sys
import numpy as np
import OpenImageIO as oiio

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))
DL = os.path.join(ROOT, "downloads", "ph")
OUT = os.path.join(PROJ, "assets", "models", "hd_world", "textures")
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(1930)


def read(path, size=None):
    buf = oiio.ImageBuf(path)
    if size and (buf.spec().width != size or buf.spec().height != size):
        buf = oiio.ImageBufAlgo.resize(buf, roi=oiio.ROI(0, size, 0, size, 0, 1, 0, buf.nchannels))
    px = buf.get_pixels(oiio.FLOAT)
    if px.ndim == 2:
        px = px[:, :, None]
    if px.shape[2] == 1:
        px = np.repeat(px, 3, axis=2)
    return px


def write(name, px, quality=90):
    px = np.clip(px, 0.0, 1.0).astype(np.float32)
    if px.ndim == 2:
        px = px[:, :, None]
    if px.shape[2] == 1:
        px = np.repeat(px, 3, axis=2)
    ch = 4 if name.endswith(".png") and px.shape[2] == 4 else 3
    spec = oiio.ImageSpec(px.shape[1], px.shape[0], ch, oiio.UINT8)
    if name.endswith(".jpg"):
        spec.attribute("CompressionQuality", quality)
    path = os.path.join(OUT, name)
    o = oiio.ImageOutput.create(path)
    o.open(path, spec)
    o.write_image(np.ascontiguousarray(px[:, :, :ch]))
    o.close()
    print("wrote", name, px.shape)


def lum(px):
    return px[:, :, 0:1] * 0.2126 + px[:, :, 1:2] * 0.7152 + px[:, :, 2:3] * 0.0722


def blur(px, r):
    """Box blur (wrapping), r pixels, repeated twice ~ gaussian."""
    out = px
    for _ in range(2):
        c = np.cumsum(np.concatenate([out[-r - 1:], out, out[:r]], axis=0), axis=0)
        out = (c[2 * r + 1:] - c[:-2 * r - 1]) / (2 * r + 1)
        c = np.cumsum(np.concatenate([out[:, -r - 1:], out, out[:, :r]], axis=1), axis=1)
        out = (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)
    return out


def ph_set(folder, aid, size=2048):
    d = os.path.join(DL, folder)
    alb = read(os.path.join(d, aid + "_Diffuse.jpg"), size)[:, :, :3]
    nrm = read(os.path.join(d, aid + "_nor_gl.jpg"), size)[:, :, :3]
    arm = read(os.path.join(d, aid + "_arm.jpg"), size)[:, :, :3]
    return alb, nrm, arm


def flatten_normal(n, k):
    """Scale the tangent-space normal's slope by k (k < 1 = flatter)."""
    v = n * 2.0 - 1.0
    v[:, :, 0:2] *= k
    v /= np.linalg.norm(v, axis=2, keepdims=True) + 1e-6
    return v * 0.5 + 0.5


def save_set(key, alb, nrm, arm):
    write(key + "_albedo.jpg", alb)
    write(key + "_normal.jpg", nrm)
    write(key + "_orm.jpg", arm)


def neutral(alb, mean, contrast=1.0, sat=0.0, tint=(1, 1, 1)):
    """Luminance detail around `mean` (grey, so a vertex colour or uniform can tint it), keeping
    `sat` of the original colour."""
    l = lum(alb)
    m = float(l.mean())
    grey = (mean + (l - m) * contrast) * np.array(tint, np.float32)[None, None, :]
    col = alb[:, :, :3] / max(m, 1e-4) * mean
    return grey * (1.0 - sat) + col * sat


def surfaces():
    # Snow: keep the relief, wash out the debris marks the photos carry.
    for key, folder, aid in (("snow", "snow_powder", "snow_02"), ("snow_trodden", "snow_trodden", "snow_01"),
                             ("snow_trampled", "snow_trampled", "snow_03")):
        alb, nrm, arm = ph_set(folder, aid)
        l = lum(alb)
        m = float(l.mean())
        local = blur(l, 24)
        l2 = np.maximum(l, local - 0.035)          # dark specks lifted to the local level
        a = np.clip(0.92 + (l2 - m) * 0.55, 0.0, 1.0)
        alb2 = a * np.array([0.97, 0.985, 1.0], np.float32)[None, None, :]
        if key != "snow":
            # Trodden snow keeps a little of its grey-brown slush.
            alb2 = alb2 * 0.7 + alb * 0.3 / max(m, 1e-4) * 0.85
        arm[:, :, 1:2] = np.clip(0.55 + (arm[:, :, 1:2] - arm[:, :, 1:2].mean()) * 0.6, 0.3, 0.9)
        arm[:, :, 2:3] = 0.0
        save_set(key, alb2, nrm, arm)
    # Ballast: crushed stone, a shade greyer than the photo.
    alb, nrm, arm = ph_set("ballast", "rock_ground")
    save_set("ballast", neutral(alb, 0.36, 1.25, 0.45, (1.0, 0.97, 0.93)), nrm, arm)
    # Timber: sleepers, poles, platform planks (weathered grey-brown).
    alb, nrm, arm = ph_set("wood_weathered", "rough_wood")
    save_set("wood_weathered", neutral(alb, 0.34, 1.1, 0.6, (1.0, 0.93, 0.85)), nrm, arm)
    alb, nrm, arm = ph_set("planks", "planks_brown_10", 1024)
    save_set("planks", alb, nrm, arm)
    alb, nrm, arm = ph_set("planks_green", "green_rough_planks", 1024)
    save_set("planks_green", alb, nrm, arm)
    # Roofs: Bohemian clay pantiles, dark slate.
    alb, nrm, arm = ph_set("roof_clay", "clay_roof_tiles_02")
    save_set("roof_clay", alb * 0.9, nrm, arm)
    alb, nrm, arm = ph_set("roof_slate", "roof_slates_02")
    save_set("roof_slate", neutral(alb, 0.3, 1.2, 0.3, (0.92, 0.95, 1.0)), nrm, arm)
    # Plaster: grey detail, coloured per house by the vertex colour.
    alb, nrm, arm = ph_set("plaster", "painted_plaster_wall")
    save_set("plaster", neutral(alb, 0.8, 1.6), flatten_normal(nrm, 0.8), arm)
    # Stone plinths and platform setts.
    alb, nrm, arm = ph_set("stone_wall", "rustic_stone_wall", 1024)
    save_set("stone_wall", neutral(alb, 0.45, 1.0, 0.5), nrm, arm)
    alb, nrm, arm = ph_set("platform", "stone_tiles_03", 1024)
    save_set("platform", neutral(alb, 0.42, 1.1, 0.35), nrm, arm)
    # Rock for cliffs, cuttings and mountain faces: cold grey.
    alb, nrm, arm = ph_set("rock_face", "rock_face_03")
    save_set("rock", neutral(alb, 0.36, 1.35, 0.25, (0.93, 0.95, 1.0)), nrm, arm)
    # Rails: rusty steel sides.
    alb, nrm, arm = ph_set("rail_rust", "rusty_metal_02", 1024)
    save_set("rail_rust", alb, nrm, arm)
    # Bark: spruce/fir trunk and pine.
    d = os.path.join(DL, "fir")
    save_set("fir_bark", read(os.path.join(d, "fir_tree_01_bark_diff.jpg"), 1024),
             read(os.path.join(d, "fir_tree_01_bark_nor_gl.jpg"), 1024), read(os.path.join(d, "fir_tree_01_bark_arm.jpg"), 1024))
    alb, nrm, arm = ph_set("pine_bark", "pine_bark", 1024)
    save_set("pine_bark", alb, nrm, arm)


# ————— tree twig atlases —————

def label(mask):
    """4-connected components of a boolean mask (small images). Returns label image and count."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and lab[y, x] == 0:
                n += 1
                stack = [(y, x)]
                lab[y, x] = n
                while stack:
                    cy, cx = stack.pop()
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = n
                            stack.append((ny, nx))
    return lab, n


def dilate_colour(rgb, alpha, steps=40):
    """Push the colour of opaque texels outward into the transparent area (mip-safe cut-outs)."""
    out = rgb.copy()
    known = alpha > 0.5
    for _ in range(steps):
        acc = np.zeros_like(out)
        cnt = np.zeros(alpha.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(out, (dy, dx), (0, 1)) * k[:, :, None]
            cnt += k
        new = (~known) & (cnt > 0)
        out[new] = acc[new] / cnt[new][:, None]
        known = known | new
        if known.all():
            break
    return out


def twigs(key, aid, folder, region):
    """Cut the twig sprites out of a Poly Haven tree atlas. `region` (u0, v0, u1, v1) limits the
    search to the twig part of the atlas (the rest holds bark and branch strips)."""
    d = os.path.join(DL, folder)
    size = 2048
    rgb = read(os.path.join(d, aid + "_twig_diff.jpg"), size)[:, :, :3]
    a = read(os.path.join(d, aid + "_twig_alpha.jpg"), size)[:, :, 0]
    nrm = read(os.path.join(d, aid + "_twig_nor_gl.jpg"), size)[:, :, :3]
    arm = read(os.path.join(d, aid + "_twig_arm.jpg"), size)[:, :, :3]
    u0, v0, u1, v1 = region
    keep = np.zeros_like(a, bool)
    keep[int(v0 * size):int(v1 * size), int(u0 * size):int(u1 * size)] = True
    a = np.where(keep, a, 0.0)
    # Sprites: components of the downsampled mask, grown a little so the needles stay joined.
    s = 256
    small = a.reshape(s, size // s, s, size // s).max(axis=(1, 3)) > 0.4
    grown = small.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
        grown |= np.roll(small, (dy, dx), (0, 1))
    lab, n = label(grown)
    rects = []
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        if len(ys) < 60:
            continue
        rects.append([float(xs.min()) / s, float(ys.min()) / s, float(xs.max() + 1) / s, float(ys.max() + 1) / s])
    rects.sort(key=lambda r: -(r[2] - r[0]) * (r[3] - r[1]))
    # Colour: a little colder and darker (winter spruce), dilated under the alpha.
    l = lum(rgb)
    rgb = rgb * np.array([0.82, 0.92, 0.9], np.float32)[None, None, :] * 0.95
    rgb = dilate_colour(rgb, a)
    write(key + "_twig_albedo.png", np.concatenate([rgb, a[:, :, None]], axis=2))
    write(key + "_twig_normal.jpg", nrm)
    write(key + "_twig_orm.jpg", arm)
    return rects, (rgb, a, nrm)


def needles_mass(src):
    """Opaque needle canopy texture (1024, tiling): twig sprites scattered densely over a dark
    shadowed base, for the low-detail trees seen from a distance."""
    rgb, a, nrm = src
    size = 1024
    s2 = rgb[::2, ::2]
    a2 = a[::2, ::2]
    n2 = nrm[::2, ::2]
    out = np.zeros((size, size, 3), np.float32) + np.array([0.035, 0.05, 0.04], np.float32)
    on = np.zeros((size, size, 3), np.float32) + np.array([0.5, 0.5, 1.0], np.float32)
    ys, xs = np.nonzero(a2 > 0.5)
    # Stamp 220 random 128 px patches of twig texture where the atlas is opaque.
    for _ in range(420):
        i = RNG.integers(len(ys))
        cy, cx = ys[i], xs[i]
        p = 64
        y0, x0 = max(cy - p, 0), max(cx - p, 0)
        patch = s2[y0:y0 + 2 * p, x0:x0 + 2 * p]
        pa = a2[y0:y0 + 2 * p, x0:x0 + 2 * p]
        pn = n2[y0:y0 + 2 * p, x0:x0 + 2 * p]
        if patch.shape[0] < 2 * p or patch.shape[1] < 2 * p:
            continue
        ty, tx = RNG.integers(size), RNG.integers(size)
        yy = (np.arange(2 * p) + ty) % size
        xx = (np.arange(2 * p) + tx) % size
        k = pa[:, :, None] * RNG.uniform(0.7, 1.05)
        out[np.ix_(yy, xx)] = out[np.ix_(yy, xx)] * (1 - k) + patch * k
        on[np.ix_(yy, xx)] = on[np.ix_(yy, xx)] * (1 - pa[:, :, None]) + pn * pa[:, :, None]
    write("needles_mass_albedo.jpg", out)
    write("needles_mass_normal.jpg", on)


def birch_bark():
    """White birch bark: chalky white with dark horizontal lenticels and black diamond scars.
    UV: u around the trunk, v up it (1 tile = 0.6 m round x 1.2 m up)."""
    w, h = 512, 1024
    base = np.ones((h, w), np.float32) * 0.86
    noise = blur(RNG.random((h, w)).astype(np.float32)[:, :, None], 6)[:, :, 0]
    base += (noise - 0.5) * 0.25
    dark = np.zeros((h, w), np.float32)
    for _ in range(260):                                   # lenticels: short horizontal dashes
        y, x = RNG.integers(h), RNG.integers(w)
        L = RNG.integers(14, 70)
        t = RNG.integers(2, 5)
        yy = np.arange(y, y + t) % h
        xx = np.arange(x, x + L) % w
        dark[np.ix_(yy, xx)] = np.maximum(dark[np.ix_(yy, xx)], RNG.uniform(0.5, 0.95))
    for _ in range(14):                                    # branch scars: dark chevrons
        y, x = RNG.integers(h), RNG.integers(w)
        for i in range(40):
            for s in (-1, 1):
                yy = (y + abs(i) // 2 + np.arange(5)) % h
                xx = (x + s * i) % w
                dark[yy, xx] = 1.0
    dark = blur(dark[:, :, None], 1)[:, :, 0]
    l = np.clip(base * (1.0 - dark * 0.9), 0.0, 1.0)
    alb = np.stack([l * 0.97, l * 0.96, l * 0.93], axis=2)
    hgt = blur((l)[:, :, None], 2)[:, :, 0]
    gy, gx = np.gradient(hgt)
    nrm = np.stack([-gx * 6.0, gy * 6.0, np.ones_like(gx)], axis=2)
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    orm = np.stack([np.ones_like(l), 0.55 + dark * 0.3, np.zeros_like(l)], axis=2)
    write("birch_bark_albedo.jpg", alb)
    write("birch_bark_normal.jpg", nrm * 0.5 + 0.5)
    write("birch_bark_orm.jpg", orm)


def birch_twigs():
    """Fine bare twigs (RGBA cut-out) for the birch crown."""
    sys.path.insert(0, os.path.join(PROJ, "art_source", "props_hd", ".pydeps"))
    from PIL import Image, ImageDraw
    S = 1024
    im = Image.new("RGBA", (S, S), (60, 48, 42, 0))
    dr = ImageDraw.Draw(im)
    rng = np.random.default_rng(7)

    def branch(x, y, ang, length, width, depth):
        if depth == 0 or length < 6:
            return
        x2 = x + np.cos(ang) * length
        y2 = y - np.sin(ang) * length
        c = (int(70 + depth * 6), int(55 + depth * 4), int(48 + depth * 3), 255)
        dr.line([(x, y), (x2, y2)], fill=c, width=max(int(width), 1))
        for _ in range(2 if depth > 2 else 3):
            t = rng.uniform(0.35, 1.0)
            bx, by = x + (x2 - x) * t, y + (y2 - y) * t
            branch(bx, by, ang + rng.uniform(-0.75, 0.75), length * rng.uniform(0.45, 0.7), width * 0.65, depth - 1)

    branch(S / 2, S - 4, np.pi / 2, S * 0.42, 9, 6)
    px = np.asarray(im).astype(np.float32) / 255.0
    rgb = dilate_colour(px[:, :, :3].copy(), px[:, :, 3], 30)
    write("birch_twig_albedo.png", np.concatenate([rgb, px[:, :, 3:4]], axis=2))


if __name__ == "__main__":
    what = sys.argv[1:] or ["surfaces", "trees"]
    if "surfaces" in what:
        surfaces()
    if "trees" in what:
        fir_rects, fir_src = twigs("fir", "fir_tree_01", "fir", (0.25, 0.0, 1.0, 0.86))
        pine_rects, _ = twigs("pine", "pine_tree_01", "pine", (0.0, 0.0, 1.0, 1.0))
        needles_mass(fir_src)
        birch_bark()
        birch_twigs()
        with open(os.path.join(ROOT, "twig_rects.json"), "w") as f:
            json.dump({"fir": fir_rects, "pine": pine_rects}, f, indent=1)
        print("fir rects", fir_rects)
        print("pine rects", pine_rects)
