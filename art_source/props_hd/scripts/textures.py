"""Turn the downloaded CC0 maps into the game texture set for the HD props.

Run with Blender's bundled Python (it ships OpenImageIO and numpy):
    "<blender>/5.2/python/bin/python.exe" textures.py

For every material key it writes, into assets/models/hd_props/textures/:
    <key>_albedo.jpg   sRGB base colour (optionally recoloured / tinted)
    <key>_normal.jpg   OpenGL (Y+) tangent-space normal, as glTF expects
    <key>_orm.jpg      R = ambient occlusion, G = roughness, B = metalness (glTF ORM packing)
plus generated textures (rug pattern, clock dials, ledger page, parcel label).
"""
import os, math, sys
import numpy as np
import OpenImageIO as oiio

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))
DL = os.path.join(ROOT, "downloads")
OUT = os.path.join(ROOT, "tex_build")              # Blender copies what the models use into the game
FONTS = os.path.join(PROJ, "assets", "fonts")
os.makedirs(OUT, exist_ok=True)


def read(path, size=None):
    buf = oiio.ImageBuf(path)
    if size and (buf.spec().width != size or buf.spec().height != size):
        buf = oiio.ImageBufAlgo.resize(buf, roi=oiio.ROI(0, size, 0, size, 0, 1, 0, buf.nchannels))
    px = buf.get_pixels(oiio.FLOAT)
    if px.ndim == 2:
        px = px[:, :, None]
    return px


def write(name, px, quality=92):
    px = np.clip(px, 0.0, 1.0)
    if px.shape[2] == 1:
        px = np.repeat(px, 3, axis=2)
    spec = oiio.ImageSpec(px.shape[1], px.shape[0], 3, oiio.UINT8)
    spec.attribute("CompressionQuality", quality)
    path = os.path.join(OUT, name)
    o = oiio.ImageOutput.create(path)
    o.open(path, spec)
    o.write_image(px[:, :, :3].astype(np.float32))
    o.close()


def find(folder, *keys):
    for f in sorted(os.listdir(folder)):
        low = f.lower()
        if any(k in low for k in keys):
            return os.path.join(folder, f)
    return None


def lum(px):
    return px[:, :, 0:1] * 0.2126 + px[:, :, 1:2] * 0.7152 + px[:, :, 2:3] * 0.0722


def recolor(alb, color, keep=0.0, contrast=1.0):
    """Replace the hue of `alb` by `color`, keeping its luminance detail (`keep` mixes the original,
    `contrast` scales the detail around the mean)."""
    l = lum(alb)
    l = l / max(float(l.mean()), 1e-4)
    l = 1.0 + (l - 1.0) * contrast
    out = l * np.array(color, np.float32)[None, None, :]
    return out * (1.0 - keep) + alb[:, :, :3] * keep


def acg_set(key, folder, size=2048):
    d = os.path.join(DL, "acg", folder)
    alb = read(find(d, "_color"), size)[:, :, :3]
    if alb.shape[2] == 1:
        alb = np.repeat(alb, 3, axis=2)
    nrm = read(find(d, "normalgl"), size)[:, :, :3]
    rough = read(find(d, "roughness"), size)[:, :, :1]
    met_p = find(d, "metalness")
    met = read(met_p, size)[:, :, :1] if met_p else np.zeros_like(rough)
    ao_p = find(d, "ambientocclusion")
    ao = read(ao_p, size)[:, :, :1] if ao_p else np.ones_like(rough)
    return alb, nrm, np.concatenate([ao, rough, met], axis=2)


def ph_set(folder, size=2048):
    d = os.path.join(DL, "ph", folder)
    alb = read(find(d, "_diffuse"), size)[:, :, :3]
    nrm = read(find(d, "_nor_gl"), size)[:, :, :3]
    arm = read(find(d, "_arm"), size)[:, :, :3]           # AO, rough, metal - already ORM order
    return alb, nrm, arm


def emit(key, alb, nrm, orm, rough_scale=1.0, rough_add=0.0, metal=None, nflat=0.0):
    orm = orm.copy()
    if nflat > 0.0:
        nrm = nrm * (1.0 - nflat) + np.array([0.5, 0.5, 1.0], np.float32) * nflat
    orm[:, :, 1:2] = np.clip(orm[:, :, 1:2] * rough_scale + rough_add, 0.02, 1.0)
    if metal is not None:
        orm[:, :, 2:3] = metal
    write(f"{key}_albedo.jpg", alb)
    write(f"{key}_normal.jpg", nrm)
    write(f"{key}_orm.jpg", orm)
    print("tex", key, alb.shape[0])


def standard():
    # Woods: varnished furniture walnut is glossier than the raw scans.
    a, n, o = acg_set("wood_furniture", "wood_furniture")
    emit("wood_furniture", a * np.array([0.95, 0.9, 1.3]), n, o, 0.7)
    emit("wood_furniture_dark", a * np.array([0.6, 0.55, 0.75]), n, o, 0.7)
    a, n, o = acg_set("wood_dark", "wood_dark")
    emit("wood_dark", a, n, o, 0.75)
    a, n, o = acg_set("wood_pine", "wood_pine")
    emit("wood_pine", a, n, o, 1.0, 0.1)
    emit("wood_pine_dark", a * np.array([0.62, 0.55, 0.48]), n, o, 1.0, 0.12)
    a, n, o = acg_set("wood_handle", "wood_handle")
    emit("wood_handle", a, n, o, 0.85)
    # Metals.
    a, n, o = acg_set("brass", "brass")
    emit("brass", a, n, o, 0.9)
    a, n, o = acg_set("steel", "steel")
    emit("steel", a, n, o)
    emit("steel_dark", a * 0.42, n, o, 1.0, 0.08)
    a, n, o = acg_set("iron", "iron")
    emit("iron", a, n, o)
    emit("iron_green", recolor(a, (0.05, 0.085, 0.06), 0.15), n, o, 0.9, 0.0, 0.25)
    a, n, o = acg_set("paint_black", "paint_black")
    emit("paint_black", a, n, o)
    a, n, o = acg_set("galvanized", "galvanized", 2048)
    emit("galvanized", recolor(a, (0.62, 0.63, 0.62), 0.25), n, o, 0.9, 0.0, 0.55)
    a, n, o = acg_set("copper", "copper", 1024)
    emit("copper", a, n, o, 0.9)
    a, n, o = acg_set("gold", "gold", 1024)
    emit("gold", a, n, o, 1.2, 0.05)
    # Painted metal (the locker's green), and recoloured from it: railway red and the livery green.
    a, n, o = ph_set("paint_green")
    emit("paint_green", a, n, o)
    emit("paint_red", recolor(a, (0.42, 0.05, 0.035), 0.1), n, o, 0.75)
    emit("paint_livery", recolor(a, (0.10, 0.20, 0.13), 0.1), n, o, 0.6)
    # Leathers.
    a, n, o = ph_set("leather_brown")
    emit("leather_brown", a, n, o)
    emit("leather_green", recolor(a, (0.07, 0.15, 0.09), 0.08), n, o, 0.8)
    a, n, o = acg_set("leather_red", "leather_red", 1024)
    emit("leather_red", a * np.array([0.85, 0.7, 0.65]), n, o)
    a, n, o = acg_set("leather_black", "leather_black", 1024)
    emit("leather_black", a, n, o)
    # Textiles and paper.
    a, n, o = ph_set("canvas")
    emit("canvas", a, n, o)
    emit("canvas_dark", a * np.array([0.78, 0.74, 0.66]), n, o)
    emit("canvas_green", recolor(a, (0.2, 0.27, 0.18), 0.1), n, o)
    a, n, o = acg_set("felt_navy", "felt_navy", 1024)
    emit("felt_navy", recolor(a, (0.06, 0.075, 0.13), 0.2), n, o)
    a, n, o = acg_set("kraft", "kraft")
    emit("kraft", a, n, o)
    emit("kraft_dark", a * np.array([0.82, 0.74, 0.66]), n, o)
    a, n, o = acg_set("kraft_crumpled", "kraft_crumpled", 1024)
    emit("kraft_crumpled", a, n, o)
    a, n, o = acg_set("paper", "paper", 1024)
    emit("paper", a * np.array([0.97, 0.95, 0.88]), n, o)
    emit("paper_aged", a * np.array([0.9, 0.84, 0.7]), n, o)
    a, n, o = acg_set("rubber", "rubber", 1024)
    emit("rubber", a, n, o)
    a, n, o = acg_set("coal", "coal", 1024)
    emit("coal", recolor(a, (0.03, 0.03, 0.032), 0.0), n, o, 0.55, 0.0, 0.15)
    # Locomotive / car body paints (clean paint scan, recoloured), underframe iron, roof canvas.
    a, n, o = acg_set("paint_clean", "paint_clean")
    emit("loco_green", recolor(a, (0.115, 0.215, 0.14), 0.0, 0.25), n, o, 0.15, 0.3, 0.0, 0.7)
    emit("loco_black", recolor(a, (0.022, 0.022, 0.024), 0.0, 0.25), n, o, 0.3, 0.45, 0.0, 0.6)
    emit("loco_red", recolor(a, (0.42, 0.045, 0.03), 0.0, 0.25), n, o, 0.15, 0.32, 0.0, 0.7)
    emit("paint_cream", recolor(a, (0.8, 0.76, 0.66), 0.0, 0.25), n, o, 0.2, 0.5, 0.0, 0.8)
    emit("paint_detail", a, n, o)
    emit("coach_green", recolor(a, (0.122, 0.231, 0.153), 0.0, 0.25), n, o, 0.15, 0.3, 0.0, 0.7)
    a, n, o = acg_set("underframe", "underframe")
    emit("underframe", a * 0.42, n, o, 1.0, 0.1)
    a, n, o = acg_set("underframe_rust", "underframe_rust")
    emit("underframe_rust", a * 0.6, n, o)
    a, n, o = acg_set("rust", "rust", 1024)
    emit("rust", a, n, o)
    a, n, o = acg_set("roof_canvas", "roof_canvas")
    emit("roof_canvas", recolor(a, (0.23, 0.235, 0.24), 0.0), n, o, 1.0, 0.1)
    return a


# ————— generated textures —————

def font(name):
    return os.path.join(FONTS, name)


sys.path.insert(0, os.path.join(ROOT, ".pydeps"))       # Pillow, installed locally for text
from PIL import Image, ImageDraw, ImageFont


class Canvas:
    def __init__(self, w, h, color):
        self.img = Image.new("RGB", (w, h), tuple(int(c * 255) for c in color))
        self.draw = ImageDraw.Draw(self.img)


def canvas_rgb(w, h, color):
    return Canvas(w, h, color)


_fonts = {}
def text(buf, x, y, s, size, color, fnt="Oswald.ttf", align="center"):
    key = (fnt, int(size))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(font(fnt), int(size))
    anchor = {"center": "mm", "left": "lm", "right": "rm"}[align]
    buf.draw.text((x, y), s, fill=tuple(int(c * 255) for c in color), font=_fonts[key], anchor=anchor)


def line(buf, x0, y0, x1, y1, color, width=1):
    buf.draw.line([(x0, y0), (x1, y1)], fill=tuple(int(c * 255) for c in color), width=int(width))


def box(buf, x0, y0, x1, y1, color, width=1):
    buf.draw.rectangle([x0, y0, x1, y1], outline=tuple(int(c * 255) for c in color), width=int(width))


def save_buf(name, buf, paper_detail=None):
    px = np.asarray(buf.img, np.float32)[:, :, :3] / 255.0
    if paper_detail is not None:
        px = px * paper_detail
    write(name, px)


def paper_detail(size):
    a = read(find(os.path.join(DL, "acg", "paper"), "_color"), size)[:, :, :3]
    l = lum(a)
    return np.clip(l / l.mean(), 0.85, 1.12)


def clock_dial(name, roman=False, label=""):
    S = 1024
    c = S / 2
    buf = canvas_rgb(S, S, (0.93, 0.9, 0.8))
    ink = (0.06, 0.05, 0.04)
    r = S * 0.47
    for i in range(60):
        a = math.tau * i / 60
        r0 = r * (0.86 if i % 5 == 0 else 0.92)
        x0, y0 = c + math.sin(a) * r0, c - math.cos(a) * r0
        x1, y1 = c + math.sin(a) * r * 0.97, c - math.cos(a) * r * 0.97
        line(buf, x0, y0, x1, y1, ink, 10 if i % 5 == 0 else 4)
    nums = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"] if roman else [str(i) for i in [12] + list(range(1, 12))]
    for i, s in enumerate(nums):
        a = math.tau * i / 12
        x, y = c + math.sin(a) * r * 0.71, c - math.cos(a) * r * 0.71
        text(buf, x, y, s, 92 if not roman else 70, ink, "PlayfairDisplay.ttf")
    if label:
        text(buf, c, c + r * 0.36, label, 34, (0.45, 0.06, 0.04), "Oswald.ttf")
        text(buf, c, c - r * 0.33, "G.C.R.", 40, ink, "PlayfairDisplay.ttf")
    save_buf(name, buf, paper_detail(S))
    print("dial", name)


def ledger_page():
    S = 1024
    buf = canvas_rgb(S, S, (0.93, 0.9, 0.8))
    blue = (0.45, 0.55, 0.72)
    rng = np.random.default_rng(7)
    for k in range(26):
        y = 110 + k * 34
        line(buf, 30, y, S - 30, y, blue, 2)
    line(buf, 150, 40, 150, S - 30, (0.7, 0.2, 0.2), 3)
    line(buf, 700, 90, 700, S - 30, (0.7, 0.2, 0.2), 2)
    text(buf, S / 2, 55, "OCCURRENCE BOOK", 44, (0.15, 0.12, 0.1), "PlayfairDisplay.ttf")
    ink = (0.12, 0.13, 0.25)
    for k in range(22):
        y = 110 + k * 34 - 9
        text(buf, 90, y, f"{19 + (k // 4) % 10:02d}.{(k * 7) % 60:02d}", 22, ink, "Oswald.ttf")
        x = 170
        end = 160 + rng.integers(300, 520)
        while x < end:                                  # handwriting-like scribbles
            w = rng.integers(20, 70)
            pts = np.linspace(x, x + w, 7)
            ys = y + rng.normal(0, 4, 7)
            for i in range(6):
                line(buf, pts[i], ys[i], pts[i + 1], ys[i + 1], ink, 2)
            x += w + rng.integers(8, 16)
        text(buf, 760, y, ["IN ORDER", "SEEN", "REPORTED", "NIL", "CAR 3", "CHECKED"][k % 6], 22, ink, "Oswald.ttf", "left")
    save_buf("ledger_page_albedo.jpg", buf, paper_detail(S))


def parcel_label():
    W, H = 1024, 640
    buf = canvas_rgb(W, H, (0.92, 0.88, 0.76))
    ink = (0.1, 0.08, 0.06)
    red = (0.6, 0.08, 0.05)
    box(buf, 12, 12, W - 13, H - 13, red, 4)
    text(buf, W / 2, 70, "GRAND CONTINENTAL RAILWAY", 46, red, "PlayfairDisplay.ttf")
    text(buf, W / 2, 130, "PARCELS  -  TO BE CALLED FOR", 34, ink, "Oswald.ttf")
    rng = np.random.default_rng(3)
    for k in range(4):
        y = 230 + k * 85
        line(buf, 60, y + 22, W - 60, y + 22, (0.5, 0.45, 0.38), 2)
        x = 80
        while x < W - 200 - k * 60:
            w = rng.integers(30, 90)
            pts = np.linspace(x, x + w, 8)
            ys = y + rng.normal(0, 6, 8)
            for i in range(7):
                line(buf, pts[i], ys[i], pts[i + 1], ys[i + 1], (0.1, 0.1, 0.25), 3)
            x += w + 18
    save_buf("parcel_label_albedo.jpg", buf, paper_detail(1024)[:H, :W])


def rug():
    """Oriental runner: madder-red field, indigo/green borders, a central medallion and corner
    pieces, small repeating motifs; modulated by the pile scan's luminance for fibre detail."""
    W, H = 2048, 1080
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    u = (x + 0.5) / W
    v = (y + 0.5) / H
    red = np.array([0.42, 0.07, 0.06])
    indigo = np.array([0.07, 0.1, 0.2])
    green = np.array([0.1, 0.2, 0.14])
    ivory = np.array([0.82, 0.74, 0.58])
    gold = np.array([0.62, 0.45, 0.18])
    img = np.zeros((H, W, 3), np.float32) + red
    # Distance to the edge in rug units (aspect corrected).
    ax = np.minimum(u, 1 - u) * W / H
    ay = np.minimum(v, 1 - v)
    d = np.minimum(ax, ay)
    def band(lo, hi, col):
        m = ((d >= lo) & (d < hi))[..., None]
        return np.where(m, col, img)
    img = band(0.0, 0.03, indigo)
    img = band(0.03, 0.04, ivory)
    img = band(0.04, 0.12, green)
    img = band(0.12, 0.13, ivory)
    img = band(0.13, 0.16, indigo)
    # Running-dog motif in the green border.
    s = np.where(ax < ay, v * H / H, u * W / H)
    motif = (np.sin(s * 70.0) * np.sin(np.minimum(d - 0.04, 0.08) / 0.08 * math.pi) > 0.55) & (d > 0.045) & (d < 0.115)
    img = np.where(motif[..., None], gold, img)
    # Central medallion: a lozenge with a stepped edge, ivory centre with an indigo star.
    cx, cy = 0.5 * W / H, 0.5
    px, py = u * W / H - cx, v - cy
    loz = np.abs(px) / 0.42 + np.abs(py) / 0.3
    img = np.where(((loz < 1.0) & (d > 0.16))[..., None], indigo, img)
    img = np.where((loz < 0.86)[..., None], gold, img)
    img = np.where((loz < 0.78)[..., None], ivory, img)
    star = (np.abs(px) / 0.2 + np.abs(py) / 0.2 < 1.0) | ((np.abs(px) < 0.05) & (np.abs(py) < 0.22)) | ((np.abs(py) < 0.05) & (np.abs(px) < 0.3))
    img = np.where((star & (loz < 0.78))[..., None], red, img)
    img = np.where(((np.abs(px) / 0.08 + np.abs(py) / 0.08) < 1.0)[..., None], indigo, img)
    # Corner spandrels.
    for sx in (-1, 1):
        for sy in (-1, 1):
            qx = u * W / H - (0.5 * W / H + sx * (0.5 * W / H - 0.16))
            qy = v - (0.5 + sy * 0.34)
            q = (np.abs(qx) / 0.2 + np.abs(qy) / 0.14)
            img = np.where(((q < 1.0) & (d > 0.16))[..., None], green, img)
            img = np.where(((q < 0.6) & (d > 0.16))[..., None], gold, img)
    # Small boteh-like dots scattered in the red field.
    dots = (np.sin(u * W / H * 62.0) * np.sin(v * 46.0) > 0.93) & (loz > 1.05) & (d > 0.19)
    img = np.where(dots[..., None], ivory * 0.9, img)
    # Pile detail and gentle wear.
    pile = read(find(os.path.join(DL, "acg", "rug_pile"), "_color"), 2048)[:H, :W, :3]
    l = lum(pile)
    img = img * np.clip(l / l.mean(), 0.7, 1.3)
    rng = np.random.default_rng(11)
    wear = np.clip(1.0 - 0.15 * np.exp(-((u - 0.5) ** 2 / 0.05 + (v - 0.5) ** 2 / 0.12)), 0, 1)[..., None]
    img = img * wear + rng.normal(0, 0.01, img.shape).astype(np.float32)
    write("rug_albedo.jpg", img)
    d2 = os.path.join(DL, "acg", "rug_pile")
    write("rug_normal.jpg", read(find(d2, "normalgl"), 2048)[:, :, :3])
    rough = read(find(d2, "roughness"), 2048)[:, :, :1]
    ao = read(find(d2, "ambientocclusion"), 2048)[:, :, :1]
    write("rug_orm.jpg", np.concatenate([ao, rough, np.zeros_like(rough)], axis=2))
    print("rug")


def detail_maps():
    """Grey detail maps (mean 0.5, x2 in the shader = neutral) for the procedural car shaders."""
    for name, folder, contrast in (("detail_wood", "wood_furniture", 1.0), ("detail_floor", "wood_dark", 1.0), ("detail_paper", "paper", 1.6)):
        a = read(find(os.path.join(DL, "acg", folder), "_color"), 2048)[:, :, :3]
        l = lum(a)
        l = 0.5 + (l / max(float(l.mean()), 1e-4) - 1.0) * 0.5 * contrast
        write(name + ".jpg", np.clip(l, 0.0, 1.0))
        print("detail", name)


def wicker(size=1024):
    """Generated wicker weave: vertical stakes, round weavers going over and under them; straw
    colour with per-strand variation. Albedo / normal / ORM."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    stakes = 24                                         # across the tile
    rows = 32
    sx = xx * stakes
    ry = yy * rows
    row = np.floor(ry)
    col = np.floor(sx)
    over = ((row + col) % 2 == 0)
    fy = ry - row                                       # 0..1 across a weaver
    fx = sx - col
    weaver = np.sqrt(np.clip(1.0 - (2 * fy - 1) ** 2, 0, 1))        # round strand profile
    stake = np.sqrt(np.clip(1.0 - ((2 * fx - 1) / 0.45) ** 2, 0, 1))
    # The weaver bulges where it passes over a stake and dips where it goes under.
    bulge = np.where(over, 0.25 * np.cos((fx - 0.5) * np.pi), -0.25 * np.cos((fx - 0.5) * np.pi))
    h_w = weaver * (0.75 + bulge)
    h_s = stake * 0.55
    show_stake = (~over) & (stake > 0.0)
    h = np.where(show_stake & (h_s > h_w), h_s, h_w)
    rng = np.random.default_rng(7)
    tone_row = rng.uniform(0.82, 1.12, rows)[row.astype(int) % rows]
    tone_col = rng.uniform(0.85, 1.05, stakes)[col.astype(int) % stakes]
    tone = np.where(show_stake & (h_s > h_w), tone_col, tone_row)
    grain = 1.0 + 0.08 * np.sin(xx * 900.0 + np.sin(yy * 60.0) * 3.0)
    gaps = np.clip(h * 1.6, 0.0, 1.0) ** 0.6
    base = np.array([0.6, 0.46, 0.26], np.float32)
    alb = (base[None, None, :] * (tone * grain * (0.35 + 0.65 * gaps))[:, :, None])
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * size / 256.0
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * size / 256.0
    nrm = np.stack([-gx, gy, np.ones_like(h)], 2)
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    nrm = nrm * 0.5 + 0.5
    orm = np.stack([0.55 + 0.45 * gaps, np.full_like(h, 0.82), np.zeros_like(h)], 2)
    emit("wicker", alb, nrm, orm)


def service():
    """Service-room textiles: terry towels, cotton sheets and pillowcases, wool blankets, tissue."""
    a, n, o = acg_set("towel", "towel", 1024)
    emit("towel_white", recolor(a, (0.86, 0.85, 0.82), 0.0, 1.2), n, o, 1.0, 0.1)
    emit("towel_cream", recolor(a, (0.8, 0.75, 0.64), 0.0, 1.2), n, o, 1.0, 0.1)
    a, n, o = acg_set("linen", "linen", 1024)
    emit("linen_white", recolor(a, (0.88, 0.87, 0.84), 0.0, 0.8), n, o, 1.0, 0.08, None, 0.3)
    emit("linen_ivory", recolor(a, (0.86, 0.83, 0.74), 0.0, 0.8), n, o, 1.0, 0.08, None, 0.3)
    emit("tissue", recolor(a, (0.9, 0.89, 0.86), 0.0, 0.4), n, o, 1.0, 0.15, None, 0.6)
    a, n, o = acg_set("wool", "wool", 1024)
    emit("wool_green", recolor(a, (0.17, 0.22, 0.13), 0.0, 1.1), n, o, 1.0, 0.1)
    emit("wool_grey", recolor(a, (0.3, 0.29, 0.27), 0.0, 1.1), n, o, 1.0, 0.1)
    emit("wool_red", recolor(a, (0.36, 0.07, 0.06), 0.0, 1.1), n, o, 1.0, 0.1)
    wicker()
    # Station yards and towns: brick, snow caps, the painted enamel of street furniture.
    a, n, o = ph_set("brick", 1024)
    emit("brick", a, n, o)
    a, n, o = ph_set("snow", 1024)
    emit("snow", a * 1.05, n, o, 1.0, 0.0, 0.0)
    # Station hall: warm matt plaster (the landscape's CC0 painted_plaster_wall scan), chequered
    # floor, marble counter tops.
    d = os.path.join(os.path.dirname(DL), "..", "world_hd", "downloads", "ph", "plaster")
    pa = read(find(d, "_diffuse"), 1024)[:, :, :3]
    pn = read(find(d, "_nor_gl"), 1024)[:, :, :3]
    po = read(find(d, "_arm"), 1024)[:, :, :3]
    emit("plaster_warm", recolor(pa, (0.86, 0.79, 0.66), 0.0, 0.6), pn, po, 1.0, 0.25, 0.0, 0.3)
    a, n, o = ph_set("floor_checker", 1024)
    emit("floor_checker", a, n, o, 0.6)
    a, n, o = ph_set("marble", 1024)
    emit("marble", a, n, o, 0.5)
    # Coal in the bunker and on the footplate: the same scan, duller and without metal.
    a, n, o = acg_set("coal", "coal", 1024)
    emit("coal_matte", recolor(a, (0.05, 0.05, 0.054), 0.0, 1.5), n, o, 0.8, 0.0, 0.0)


if __name__ == "__main__":
    if "service" in sys.argv:
        service()
        sys.exit(0)
    if "gen" not in sys.argv:
        standard()
        service()
    if "only_gen" in sys.argv:
        sys.exit(0)
    detail_maps()
    clock_dial("dial_station_albedo.jpg", False, "RAILWAY TIME")
    clock_dial("dial_guard_albedo.jpg", True)
    ledger_page()
    parcel_label()
    rug()
    print("done")
