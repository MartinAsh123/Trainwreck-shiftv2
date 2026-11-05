"""Repaint a Tripo character's face where its paint does not fit its shape:
    blender -b <slug>/<slug>.blend -P scripts/repaint_face.py -- <slug> [eyes,hair]
Tripo paints the eyes, the hairline and the moustache's edges a few mm off the sculpted shapes. Each
feature is sampled straight from the front into a flat image, repainted there to fit the shape, projected
back from the front and baked (Cycles, emission) into the character's own UVs. Mesh and UVs untouched.
eyes  (eye_frames.json) a new eye painted in each sculpted opening, from Tripo's colours and iris; the
      old paint outside it covered with skin, a soft lid crease, a lash line.
lips  the painted lips moved up or down, column by column, onto the sculpted slit (mouth_fit.py),
      fading out 3-10 mm above and below it and past the corners; columns whose dark line is a
      moustache's edge are left out.
hair  head hair and moustache: the surface is split along its creases and steps (where a hair volume
      ends) into areas; an area mostly painted hair is made all hair (its skin-painted edges get hair
      mirrored in from beside them), one mostly skin all skin, within 8 mm of the paint's edge. Faces
      turned down take the paint 1.2 mm above them (a moustache's underside, its hair).
-> <slug>/<slug>_eyefix_paint.blend, textures/<slug>_albedo_eyefix.png,
   previews/<slug>_paint_<feature>.png (repainted on top, original below)"""
import bpy, bmesh, os, sys, json
import numpy as np
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import eye_fit, mouth_fit
from eye_fit import smoothstep as sstep

_args = sys.argv[sys.argv.index("--") + 1:]
slug = _args[0]
FEATURES = (_args[1] if len(_args) > 1 else "eyes,hair,lips").split(",")
PATCH = "bakeatlas" not in FEATURES                            # (the default: a face patch of its own)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
FR = json.load(open(os.path.join(ROOT, "eye_frames.json"))).get(slug)   # (only the eyes measured off)
if FR is None and "eyes" in FEATURES:
    FEATURES.remove("eyes")
body = bpy.data.objects[slug + "_body"]
me = body.data
mw = body.matrix_world
scn = bpy.context.scene
face = eye_fit.Face(body, F["mouth"][1])
CX = F["center_x"]
eyes = [eye_fit.fit_eye(face, Vector(e), FR) for e in F["eyes"]] if FR else []
for e, p in zip(eyes, F["eyes"]):
    e["pupil"] = (p[0], p[2])                                   # the painted pupil (face_landmarks.py)
MM = 0.001
for e in eyes:
    e["o"] = (e["oc"][0] - e["ow"] / 2, e["oc"][0] + e["ow"] / 2, e["oc"][1] - e["oh"] / 2, e["oc"][1] + e["oh"] / 2)
    e["q"] = (e["pc"][0] - e["pw"] / 2, e["pc"][0] + e["pw"] / 2, e["pc"][1] - e["ph"] / 2, e["pc"][1] + e["ph"] / 2)
    o, q = e["o"], e["q"]
    e["R"] = (min(o[0], q[0]) - 6 * MM, max(o[1], q[1]) + 6 * MM, min(o[2], q[2]) - 5 * MM, max(o[3], q[3]) + 5 * MM)
    e["inner"] = 1.0 if CX > e["oc"][0] else -1.0             # which way is the nose

S = 0.00008                                                     # metres a pixel of the current grid


class Grid:
    """The face seen straight from the front over a box: colour FI, depth D, normal N per pixel."""

    def __init__(self, x0, x1, z0, z1, step):
        global S
        S = step
        self.S, self.X0, self.Z0 = step, x0, z0
        self.gx, self.gz = np.arange(x0, x1, step), np.arange(z0, z1, step)
        self.XX, self.ZZ = np.meshgrid(self.gx, self.gz)
        shp = (len(self.gz), len(self.gx))
        self.FI = np.zeros(shp + (3,), np.float32)
        self.D = np.full(shp, np.nan, np.float32)
        self.N = np.zeros(shp + (3,), np.float32)
        for j, z in enumerate(self.gz):
            for i, x in enumerate(self.gx):
                h = face.bvh.ray_cast(Vector((x, face.front_y, z)), Vector((0, 1, 0)))
                if h[0] is None:
                    continue
                _, uv = face.hit(x, z)
                self.FI[j, i] = face.color(uv, bilinear=True)[:3]
                self.D[j, i] = h[0].y
                n = h[1] if h[1].y < 0 else -h[1]
                self.N[j, i] = n[:]


def blur(A, r):
    """Box blur, 3 passes (about gaussian), radius r metres, along both axes."""
    k = max(int(r / S), 1)
    A = A.astype(np.float32)
    for _ in range(3):
        for ax in (0, 1):
            P = np.concatenate([np.repeat(A.take([0], axis=ax), k + 1, axis=ax), A, np.repeat(A.take([-1], axis=ax), k, axis=ax)], axis=ax)
            c = np.cumsum(P, axis=ax, dtype=np.float64)
            n = A.shape[ax]
            A = ((c.take(range(2 * k + 1, 2 * k + 1 + n), axis=ax) - c.take(range(0, n), axis=ax)) / (2 * k + 1)).astype(np.float32)
    return A


def lum(c):
    return c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722


def fill(A, known, iters=300):
    """Fill the unknown pixels of A smoothly from the known ones round them (a membrane), on a grid
    4 times coarser, then back up."""
    f = 4
    h, w = A.shape[0] // f * f, A.shape[1] // f * f
    a = A[:h, :w].reshape(h // f, f, w // f, f, 3).mean(axis=(1, 3))
    k = known[:h, :w].reshape(h // f, f, w // f, f).mean(axis=(1, 3)) > 0.99
    u = a.copy()
    u[~k] = a[k].mean(axis=0)
    for _ in range(iters):
        p = np.pad(u, ((1, 1), (1, 1), (0, 0)), mode="edge")
        avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4
        u = np.where(k[..., None], a, avg)
    up = np.repeat(np.repeat(u, f, axis=0), f, axis=1)
    out = A.copy()
    out[:h, :w] = np.where(known[:h, :w, None], A[:h, :w], up)
    return out


def skew_arc(u, peak):
    """0 at u=0 and u=1, 1 at u=peak: a sine bent so its top is at `peak`."""
    u = np.clip(u, 1e-6, 1 - 1e-6)
    return np.sin(np.pi * u ** (np.log(0.5) / np.log(peak)))


def paint_eyes():
    """The eyes' grid and its repainted image and weight."""
    X0 = min(e["R"][0] for e in eyes) - 3 * MM
    X1 = max(e["R"][1] for e in eyes) + 3 * MM
    Z0 = min(e["R"][2] for e in eyes) - 16 * MM                 # (room below the eyes for the skin's grain)
    Z1 = max(e["R"][3] for e in eyes) + 3 * MM
    g = Grid(X0, X1, Z0, Z1, 0.00008)
    gx, gz, XX, ZZ, FI = g.gx, g.gz, g.XX, g.ZZ, g.FI
    OUT = FI.copy()
    WEIGHT = np.zeros(XX.shape, np.float32)
    # One iris colour for both eyes: the ring 1.2-3.5 mm round both painted pupils, neither skin, lash nor glint.
    L_ = lum(FI)
    sat_ = FI.max(axis=2) - FI.min(axis=2)
    ring_all = np.zeros(XX.shape, bool)
    for e in eyes:
        nr = np.hypot(XX - e["pupil"][0], ZZ - e["pupil"][1])
        ring_all |= (nr > 1.2 * MM) & (nr < 3.5 * MM)
    below_all = np.zeros(XX.shape, bool)
    for e in eyes:
        below_all |= (np.abs(XX - e["pupil"][0]) < 8 * MM) & (np.abs(ZZ - (e["pupil"][1] - 10 * MM)) < 1.5 * MM)
    sk_ = np.median(FI[below_all], axis=0)
    not_skin = ~((FI[..., 0] >= FI[..., 1]) & (FI[..., 1] >= FI[..., 2] - 0.02) & (sat_ > 0.55 * float(sk_.max() - sk_.min())) & (L_ > 0.45 * float(lum(sk_))))
    near_p = np.zeros(XX.shape, bool)
    for e in eyes:
        near_p |= np.hypot(XX - e["pupil"][0], ZZ - e["pupil"][1]) < 2.5 * MM
    cand = near_p & not_skin & (np.linalg.norm(FI - sk_, axis=2) > 0.12)
    cand &= L_ > 0.1                                             # (not pupil or lash)
    cool_ = cand & (FI[..., 2] >= FI[..., 0] - 0.01) & (L_ > 0.2)      # a grey, blue or green iris
    if cool_.sum() > 0.25 * cand.sum():
        cand = cool_
    if cand.sum() > 40:
        lo, hi = np.percentile(L_[cand], [30, 75])
        pick = cand & (L_ >= lo) & (L_ <= hi)
        IRIS_SHARED = np.median(FI[pick], axis=0)
        print("IRIS raw", IRIS_SHARED.round(3), "from", int(pick.sum()), "L range %.2f..%.2f" % (lo, hi))
    else:
        IRIS_SHARED = np.array([0.30, 0.28, 0.25])
    if FR.get("iris"):                                           # (set by hand where the paint has none)
        IRIS_SHARED = np.array(FR["iris"], float)
    # One sclera colour for both eyes too: the painted whites beside both pupils (light, unsaturated).
    scl_all = np.zeros(XX.shape, bool)
    for e in eyes:
        q = e["q"]
        qb = (XX > q[0] - 3 * MM) & (XX < q[1] + 3 * MM) & (ZZ > q[2] - 2 * MM) & (ZZ < q[3] + 1 * MM)
        scl_all |= qb & (np.abs(ZZ - e["pupil"][1]) < 2 * MM) & (np.hypot(XX - e["pupil"][0], ZZ - e["pupil"][1]) > 4 * MM)
    scl_all &= (L_ > 0.5) & (sat_ < 0.15)
    SCLERA_SHARED = np.median(FI[scl_all], axis=0) if scl_all.sum() > 40 else np.array([0.80, 0.77, 0.73])
    SCLERA_SHARED = lum(SCLERA_SHARED) + (SCLERA_SHARED - lum(SCLERA_SHARED)) * 0.5   # (half its tint: no purple whites)
    for e in eyes:
        o, q, R = e["o"], e["q"], e["R"]
        inside_R = (XX > R[0]) & (XX < R[1]) & (ZZ > R[2]) & (ZZ < R[3])
        xc, zc, w, h = (o[0] + o[1]) / 2, (o[2] + o[3]) / 2, o[1] - o[0], o[3] - o[2]
        t = (XX - xc) / (w / 2)                                     # -1..1 across the opening
        u = (t * e["inner"] + 1) / 2                                # 0 at the outer corner, 1 at the inner
        inx = np.abs(t) < 1
        top = np.where(inx, zc + h / 2 * skew_arc(u, 0.56) ** 0.8, zc)
        bot = np.where(inx, zc - h / 2 * skew_arc(u, 0.42), zc)
        A = inx & (ZZ < top) & (ZZ > bot)
        d_edge = np.minimum(ZZ - bot, top - ZZ)                     # depth inside the opening (vertical)
        aA = np.where(inx, sstep(-0.08 * MM, 0.12 * MM, d_edge), 0.0)

        # Tripo's colours: skin under the eye, the painted eye's sclera and iris.
        qbox = (XX > q[0] - 3 * MM) & (XX < q[1] + 3 * MM) & (ZZ > q[2] - 2 * MM) & (ZZ < q[3] + 1 * MM)   # (not up to the brow)
        below = (np.abs(XX - xc) < 8 * MM) & (np.abs(ZZ - (q[2] - 7 * MM)) < 1.2 * MM)
        skin = np.median(FI[below], axis=0)
        s_sat, s_lum = float(skin.max() - skin.min()), float(lum(skin))
        sat = FI.max(axis=2) - FI.min(axis=2)
        L = lum(FI)
        skinlike = (FI[..., 0] >= FI[..., 1]) & (FI[..., 1] >= FI[..., 2] - 0.02) & (sat > 0.55 * s_sat) & (L > 0.45 * s_lum)
        painted = qbox & ~skinlike
        near = np.hypot(XX - e["pupil"][0], ZZ - e["pupil"][1])
        sclera = SCLERA_SHARED * min(1.0, 0.74 / max(float(lum(SCLERA_SHARED)), 1e-3))
        # the iris: the ring 1.2-3.5 mm round the painted pupil, without lashes (dark) or glints (bright)
        ring = (near > 1.2 * MM) & (near < 3.5 * MM) & ~skinlike & (L > 0.12) & (L < 0.45)
        cool = ring & (FI[..., 0] - FI[..., 2] < 0.6 * float(skin[0] - skin[2]))   # not skin- or lash-brown
        # (a green, grey or blue iris anywhere in the painted eye wins over a ring that caught lid or lash)
        cold = qbox & (FI[..., 1] >= FI[..., 0] - 0.01) & (L > 0.12) & (L < 0.45) & ~skinlike
        irs = FI[cold] if cold.sum() > 60 else FI[cool] if cool.sum() > 30 else FI[ring]
        print("IRIS candidates: ring %s (%d)  cool %s (%d)  cold %s (%d)" % (
            np.median(FI[ring], axis=0).round(3) if ring.any() else "-", ring.sum(),
            np.median(FI[cool], axis=0).round(3) if cool.any() else "-", cool.sum(),
            np.median(FI[cold], axis=0).round(3) if cold.any() else "-", cold.sum()))
        iris = IRIS_SHARED.copy()
        iris = np.clip(lum(iris) + (iris - lum(iris)) * 1.3, 0.02, 1.0) * 0.85  # (painted irises read a little greyer)
        iris = iris * (0.20 / max(float(lum(iris)), 0.05)) ** 0.5    # a dark mid-tone, as Tripo paints them
        print("EYE colours: skin", skin.round(3), "sclera", sclera.round(3), "iris", iris.round(3))

        # The region to repaint: the old paint (a little grown) and the opening.
        rg = blur((painted | A).astype(np.float32), 0.9 * MM) > 0.05
        # and a smooth outline round the old paint and the opening (a rounded box 1.2 mm out), with the old
        # paint left just outside it (lash tips) taken in, so the skin is filled in from clean skin
        bx0, bx1 = min(q[0], o[0]) - 1.2 * MM, max(q[1], o[1]) + 1.2 * MM
        bz0, bz1 = min(q[2], o[2]) - 1.0 * MM, max(q[3], o[3]) + 1.2 * MM
        rg |= (np.abs((XX - (bx0 + bx1) / 2) / ((bx1 - bx0) / 2)) ** 3 + np.abs((ZZ - (bz0 + bz1) / 2) / ((bz1 - bz0) / 2)) ** 3) < 1
        rg |= (blur(rg.astype(np.float32), 1.5 * MM) > 0.01) & ~skinlike
        rg &= inside_R & (ZZ < max(q[3], o[3]) + 1.5 * MM)
        # Skin over it: filled in from round it, with the grain of the cheek 12 mm lower added back.
        sk = fill(FI, ~rg)
        # (only from clean skin: 12 mm lower from the upper lid is the old lower lash line, so then 18 or 24)
        hp = FI - blur(FI, 0.8 * MM)
        busy = blur(rg.astype(np.float32), 1.0 * MM) > 0.01
        grain = np.zeros_like(FI)
        got = np.zeros(XX.shape, bool)
        for k in (12, 18, 24):
            shift = int(k * MM / S)
            if shift >= len(gz):
                break
            take = np.zeros(XX.shape, bool)
            take[shift:] = ~busy[:-shift] & ~got[shift:]
            src = np.zeros_like(FI)
            src[shift:] = hp[:-shift]
            grain[take] = src[take]
            got |= take
        sk = sk + 1.7 * np.clip(grain, -0.06, 0.06) * rg[..., None]
        # The lid: a soft crease above the opening, a shadow just over the lash line.
        zcrease = top + 2.6 * MM * h / (6.75 * MM)
        crease = np.exp(-((ZZ - zcrease) / (0.55 * MM)) ** 2) * sstep(0.0, 0.25, u) * sstep(1.0, 0.8, u) * inx
        sk *= (1 - 0.0 * crease)[..., None]
        over = ZZ - top
        sk *= (1 - 0.22 * (np.exp(-np.clip(over, 0, None) / (0.7 * MM)) * (over > 0) * inx))[..., None]

        # The eye.
        eye = np.broadcast_to(sclera * 0.86, FI.shape).copy()
        eye = eye * (1 + 0.04 * np.sin(XX / (0.9 * MM)) * np.sin(ZZ / (0.7 * MM) + XX / (2.3 * MM)))[..., None]
        eye = eye * (1 - 0.25 * sstep(0.6, 1.0, np.abs(t)))[..., None]                     # corners darker
        pink = np.array([0.72, 0.44, 0.42])
        kp = 0.7 * sstep(0.78, 1.0, u)[..., None]
        eye = eye * (1 - kp) + pink * kp                                                      # inner corner
        rI = float(FR["iris_r"]) * MM if FR.get("iris_r") else min(0.62 * h, 5.6 * MM)
        cxI, czI = xc + 0.03 * w * e["inner"], zc + 0.06 * h
        r = np.hypot(XX - cxI, ZZ - czI)
        ang = np.arctan2(ZZ - czI, XX - cxI)
        # Tripo's own iris (round the painted pupil, its radius from its dark area), scaled to this one;
        # its painted catchlight shards toned down to the iris colour.
        dark_area = float(((near < 5 * MM) & ~skinlike & (L < 0.5)).sum()) * S * S
        rS = float(np.clip(np.sqrt(dark_area / np.pi), 2.5 * MM, 5 * MM))
        sx = e["pupil"][0] + (XX - cxI) * rS / rI
        sz = e["pupil"][1] + (ZZ - czI) * rS / rI
        fi_ = np.clip((sx - X0) / S, 0, len(gx) - 1.001)
        fj_ = np.clip((sz - Z0) / S, 0, len(gz) - 1.001)
        i0, j0 = fi_.astype(int), fj_.astype(int)
        ti_, tj_ = (fi_ - i0)[..., None], (fj_ - j0)[..., None]
        ir = (FI[j0, i0] * (1 - ti_) + FI[j0, i0 + 1] * ti_) * (1 - tj_) + (FI[j0 + 1, i0] * (1 - ti_) + FI[j0 + 1, i0 + 1] * ti_) * tj_
        shard = sstep(0.1, 0.22, np.abs(lum(ir) - float(lum(iris))))[..., None]     # glints and lashes over it
        shard = np.maximum(shard, sstep(0.12, 0.25, np.abs(ir - iris).max(axis=-1))[..., None])
        fib = 0.86 + 0.10 * np.sin(ang * 37 + 2.0) * np.sin(ang * 11 + r / rI * 9) + 0.07 * np.sin(ang * 83)
        ir = iris[None, None, :] * fib[..., None]
        ir = ir * (1 + 0.25 * np.exp(-((r - 0.45 * rI) / (0.13 * rI)) ** 2))[..., None]        # collar
        ir = ir * (1 - 0.2 * sstep(0.5 * rI, 0.0, r))[..., None]                                # darker in
        ir *= (1 - 0.6 * sstep(0.78 * rI, 1.0 * rI, r))[..., None]                          # limbal ring
        pup = (1 - sstep(0.26 * rI, 0.31 * rI, r))[..., None]
        ir = ir * (1 - pup) + np.array([0.035, 0.035, 0.04]) * pup                         # pupil
        a_i = (1 - sstep(0.96 * rI, 1.04 * rI, r))[..., None]
        eye = eye * (1 - a_i) + ir * a_i
        eye *= (1 - 0.55 * sstep(top - 0.55 * h, top, ZZ))[..., None]                       # the upper lid's shadow
        hl = np.exp(-(np.hypot(XX - (cxI - 0.28 * rI * e["inner"]), ZZ - (czI + 0.32 * rI)) / (0.45 * MM)) ** 2)
        eye = eye + (np.array([0.95, 0.95, 0.95]) - eye) * (0.8 * hl)[..., None]          # a small catchlight
        wet = np.exp(-((ZZ - bot - 0.18 * MM) / (0.16 * MM)) ** 2) * inx
        eye = eye + (np.array([0.80, 0.58, 0.54]) - eye) * (0.5 * wet)[..., None]          # wet lower rim

        # Paint: skin, then the eye, then the lash line and the lower lashes' shadow.
        img = np.where(rg[..., None], sk, FI)
        img = img * (1 - aA[..., None]) + eye * aA[..., None]
        th = (0.45 + 0.55 * sstep(0.55, 0.0, u)) * MM                                       # thicker outward
        th = (0.75 + 0.55 * sstep(0.55, 0.0, u)) * MM
        lash = sstep(-float(FR.get("lash_in", 0.3)) * MM, -0.05 * MM, over) * (1 - sstep(th - 0.25 * MM, th, over)) * sstep(1.0, 0.8, u) * inx
        lash = np.clip(blur(lash.astype(np.float32), 0.08 * MM), 0, 1) * 0.92
        img = img * (1 - lash[..., None]) + (skin * 0.16) * lash[..., None]
        under = ZZ - bot
        lls = np.exp(-(np.clip(-under, 0, None) / (0.35 * MM))) * (under < 0) * sstep(1.0, 0.7, u) * inx
        img *= (1 - 0.22 * lls)[..., None]
        wgt = np.clip(blur((rg | (lash > 0.01) | (lls > 0.05)).astype(np.float32), 1.4 * MM) * 1.6, 0, 1)
        wgt *= inside_R
        OUT = OUT * (1 - wgt[..., None]) + img * wgt[..., None]
        WEIGHT = np.maximum(WEIGHT, wgt)
    return g, OUT, WEIGHT


def dilate(M, n=1):
    M = M.copy()
    for _ in range(n):
        m = M.copy()
        m[1:] |= M[:-1]; m[:-1] |= M[1:]; m[:, 1:] |= M[:, :-1]; m[:, :-1] |= M[:, 1:]
        M = m
    return M


HAS_MOUSTACHE = [False]


def paint_hair(x0, x1, z0, z1, name, main_min=0.0):
    """Hair (or a hat, a scarf: anything not skin) and skin made to follow the shape's creases."""
    g = Grid(x0, x1, z0, z1, 0.00025)
    FI, D, N, XX, ZZ = g.FI, g.D, g.N, g.XX, g.ZZ
    valid = ~np.isnan(D)
    Dn = np.where(valid, D, np.nanmax(D) + 0.05)
    # Creases and steps: the normal turning by more than ~25 degrees, or the depth jumping by more than
    # 1 mm, over half a millimetre.
    k = 2
    e = ~valid
    st = np.zeros_like(valid)
    for ax in (0, 1):
        Nr, Dr = np.roll(N, -k, axis=ax), np.roll(Dn, -k, axis=ax)
        e |= ((N * Nr).sum(axis=2) < 0.9) | (np.abs(Dn - Dr) > 0.001)
        st |= np.abs(Dn - Dr) > 0.001                               # (steps alone: a volume standing off the skin)
    E = dilate(e, 1)
    STEP = dilate(st & valid, 1)
    # Never the brows (and what is round the eyes): nothing changes below 3.2 cm over the eyes, except
    # out at the temples.
    ez = float(np.mean([p[2] for p in F["eyes"]]))
    allowed = (ZZ > ez + 0.032) | (np.abs(XX - CX) > 0.06)
    # What is painted skin: like the face's usual skin (the median of the skin-coloured pixels here).
    sat = FI.max(axis=2) - FI.min(axis=2)
    L = lum(FI)
    warm = valid & (FI[..., 0] > FI[..., 1]) & (FI[..., 1] > FI[..., 2] - 0.02) & (FI[..., 0] - FI[..., 2] > 0.1) & (L > 0.2)
    ref = np.median(FI[warm], axis=0)
    s_sat, s_lum = float(ref.max() - ref.min()), float(lum(ref))
    skin = valid & (FI[..., 0] >= FI[..., 1]) & (FI[..., 1] >= FI[..., 2] - 0.02) & (sat > 0.55 * s_sat) & (L > 0.45 * s_lum) \
        & (np.linalg.norm(FI - ref, axis=2) < 0.3)
    HP = valid & ~skin                                              # painted hair (or cloth)
    if name == "moustache":                                         # lips (and their dark line) are not hair
        redness = FI[..., 0] - 0.5 * (FI[..., 1] + FI[..., 2])
        ref_red = float(ref[0] - 0.5 * (ref[1] + ref[2]))
        lipish = redness > max(ref_red * 1.05, 0.08)                # redder than this face's skin
        HP &= ~lipish
    # Areas between the creases; the crease pixels go to the most forward area beside them (a step's
    # wall belongs to the volume in front).
    lab, n = eye_fit.label(~E & valid)
    for _ in range(80):                                           # (until every crease pixel has one)
        if not ((lab == 0) & valid).any():
            break
        bestD = np.full(lab.shape, np.inf)
        bestL = np.zeros_like(lab)
        for ax in (0, 1):
            for sh in (-1, 1, -k, k):
                lr, dr = np.roll(lab, sh, axis=ax), np.roll(Dn, sh, axis=ax)
                take = (lr > 0) & (dr < bestD)
                bestD = np.where(take, dr, bestD)
                bestL = np.where(take, lr, bestL)
        lab = np.where((lab == 0) & valid & (bestL > 0), bestL, lab)
    cnt = np.bincount(lab.ravel(), minlength=n + 1).astype(np.float64)
    hp = np.bincount(lab.ravel(), weights=HP.ravel().astype(np.float64), minlength=n + 1)
    frac = np.where(cnt > 0, hp / np.maximum(cnt, 1), 0.5)
    big = cnt * g.S * g.S > 4e-6                                    # over 4 mm2
    fr = frac[lab]
    band = int(8 * MM / g.S)
    near = dilate(HP, band) & dilate(skin, band)                    # within 8 mm of the paint's edge
    ok = (lab > 0) & big[lab] & near
    # Crease pixels (a step's wall, a moustache's rim) beside a hair area are hair, never made skin.
    hair_area = dilate((lab > 0) & big[lab] & (fr > 0.6) & ~E, 6)
    hair_fr = 0.3 if name == "brows" else 0.6                   # (a brow: its volume is hair even if half of it is painted skin)
    hair_area = dilate((lab > 0) & big[lab] & (fr > hair_fr) & ~E, 6)
    to_hair = (ok & skin & (fr > hair_fr) & ~E) | (STEP & valid & skin & hair_area & near)
    # Only paint that belongs to the main mass of hair (connected to it) may become skin: brows, lashes,
    # lips and wrinkles are paint on purpose.
    hl, hn = eye_fit.label(HP)
    hsize = np.bincount(hl.ravel(), minlength=hn + 1) * g.S * g.S
    hsize[0] = 0
    main = np.isin(hl, np.nonzero(hsize >= max(main_min, 0.5 * hsize.max()))[0]) if hn else np.zeros_like(HP)
    to_skin = ok & HP & (fr < 0.25) & ~E & main & dilate(hair_area, int(4 * MM / g.S))   # only beside the hair's edge
    if name == "moustache":
        HAS_MOUSTACHE[0] = hsize.max() >= main_min
    if hsize.max() < main_min:                                      # (no hair here to speak of)
        print("HAIR %s: none (largest patch %.0f mm2)" % (name, hsize.max() * 1e6))
        return g, FI.copy(), np.zeros(FI.shape[:2], np.float32)
    to_hair &= dilate(main, int(8 * MM / g.S))
    if name == "head":
        to_hair &= allowed
        to_skin &= allowed
    if name == "brows":                                         # (brows: the sculpted brow made all hair, nothing made skin)
        to_skin[:] = False
    # The old paint's soft hair edge (light, half skin) now inside the hair: repainted too.
    halo = dilate(to_hair, int(1.5 * MM / g.S)) & HP & (L > 0.42) & hair_area & ~to_hair
    to_hair |= halo
    # Hair for the skin-painted parts of hair areas: mirrored in from the nearest hair of the same area.
    src = HP & ~halo
    SI = np.where(src, np.arange(HP.shape[1])[None, :], -1)
    SJ = np.where(src, np.arange(HP.shape[0])[:, None], -1)
    for _ in range(band + 2):
        for ax in (0, 1):
            for sh in (-1, 1):
                si, sj, lr = np.roll(SI, sh, axis=ax), np.roll(SJ, sh, axis=ax), np.roll(lab, sh, axis=ax)
                take = (SI < 0) & (si >= 0) & ((lr == lab) | E)
                SI = np.where(take, si, SI)
                SJ = np.where(take, sj, SJ)
    jj, ii = np.nonzero(to_hair & (SI >= 0))
    mi = np.clip(2 * SI[jj, ii] - ii, 0, HP.shape[1] - 1)
    mj = np.clip(2 * SJ[jj, ii] - jj, 0, HP.shape[0] - 1)
    good = src[mj, mi] & (lab[mj, mi] == lab[jj, ii])
    mi = np.where(good, mi, SI[jj, ii])
    mj = np.where(good, mj, SJ[jj, ii])
    OUT = FI.copy()
    if name == "brows":
        hm = np.median(FI[src], axis=0) if src.any() else np.array([0.15, 0.12, 0.1])
        rng_ = np.random.default_rng(7)
        nz = blur(rng_.standard_normal(FI.shape[:2]).astype(np.float32)[..., None].repeat(3, axis=2), 0.15 * MM)[..., 0]
        nz = nz / max(float(nz.std()), 1e-6)
        OUT[jj, ii] = hm[None, :] * (1 + 0.12 * nz[jj, ii])[:, None]      # the brow's own colour, a fine grain
    else:
        OUT[jj, ii] = FI[mj, mi] * 0.93
    # Skin for the hair-painted parts of skin areas: filled in from round, with skin grain 6 mm lower.
    if to_skin.any():
        sk = fill(FI, ~to_skin, iters=200)
        sh_ = int(6 * MM / g.S)
        grain = np.zeros_like(FI)
        grain[sh_:] = (FI - blur(FI, 0.8 * MM))[:-sh_]
        OUT = np.where(to_skin[..., None], sk + grain, OUT)
    changed = (to_hair & (SI >= 0)) | to_skin
    W = np.clip(blur(changed.astype(np.float32), 0.35 * MM) * 1.6, 0, 1)
    print("DBG %s: unlabelled %d, hair-area skin without a hair source %d, skin in hair areas outside the band %d, ok-skin with 0.25<fr<0.6 %d" % (
        name, int(((lab == 0) & valid).sum()), int((to_hair & (SI < 0)).sum()), int(((lab > 0) & skin & (fr > 0.6) & ~near).sum()),
        int((ok & skin & (fr > 0.25) & (fr <= 0.6)).sum())))
    print("HAIR %s: areas %d, to hair %.0f mm2, to skin %.0f mm2" % (name, n, (to_hair & (SI >= 0)).sum() * g.S * g.S * 1e6, to_skin.sum() * g.S * g.S * 1e6))
    # (a check image: creases red, made hair green, made skin blue)
    dbg = FI.copy() * 0.6
    dbg[E] = (0.8, 0.1, 0.1)
    dbg[to_hair & (SI >= 0)] = (0.1, 0.8, 0.1)
    dbg[to_skin] = (0.1, 0.2, 0.9)
    dbg[ok & skin & (fr > 0.25) & (fr <= 0.6)] = (0.9, 0.9, 0.1)      # undecided (yellow)
    dbg[(lab == 0) & valid] = (1.0, 0.0, 1.0)                         # unlabelled (magenta)
    save_preview(g, OUT, name, extra=dbg)
    return g, OUT, W


def save_preview(g, OUT, name, extra=None):
    rows = [OUT, g.FI] + ([extra] if extra is not None else [])
    A = np.clip(np.concatenate(rows[::-1], axis=0), 0, 1)          # (image rows go bottom-up: OUT on top)
    im = bpy.data.images.new("prev_" + name, A.shape[1], A.shape[0])
    im.pixels[:] = np.concatenate([A, np.ones(A.shape[:2] + (1,), np.float32)], axis=2).ravel()
    im.filepath_raw = os.path.join(ROOT, "previews", "%s_paint_%s.png" % (slug, name))
    im.file_format = "PNG"
    im.save()


CUR = face.px.copy()                                                # the texture as it is being repainted
src_img = [n.image for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image][0]
TW, TH = src_img.size


PATCHES = []                                                    # [(grid, OUT, W, name)] for the face patch


def bake(g, OUT, W, box, name):
    """Project OUT from the front onto the faces in the box and bake it into the texture (CUR).
    (Unless PATCH: then it is kept for the face patch, see make_patch - Tripo's atlas cuts the face into
    many small islands, some shared, so baking into it tears.)"""
    global CUR
    if PATCH:
        PATCHES.append((g, OUT, W, name))
        return
    gx, gz = g.gx, g.gz
    front = bpy.data.images.new("proj_" + name, len(gx), len(gz), alpha=True, float_buffer=True)
    front.colorspace_settings.name = "Non-Color"           # (before the pixels: changing it regenerates the image)
    front.pixels[:] = np.concatenate([OUT, np.ones(OUT.shape[:2] + (1,), np.float32)], axis=2).ravel()
    cur = bpy.data.images.new("cur_" + name, TW, TH, alpha=True, float_buffer=True)
    cur.colorspace_settings.name = "Non-Color"
    cur.pixels[:] = CUR.ravel()
    bx0, bx1, bz0, bz1 = box
    dup = body.copy()
    dup.data = me.copy()
    dup.modifiers.clear()
    if dup.data.shape_keys:
        dup.shape_key_clear()
    scn.collection.objects.link(dup)
    bm = bmesh.new()
    bm.from_mesh(dup.data)
    rot = mw.to_3x3()
    gone = []
    for f in bm.faces:
        c = mw @ f.calc_center_median()
        keep = bx0 - MM < c.x < bx1 + MM and bz0 - MM < c.z < bz1 + MM and (rot @ f.normal).y < 0.25   # not facing away
        if keep:                                                        # on the face, not deep inside the head
            h = face.bvh.ray_cast(Vector((c.x, face.front_y, c.z)), Vector((0, 1, 0)))
            keep = h[0] is not None and c.y - h[0].y < 0.012
        if not keep:
            gone.append(f)
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(dup.data)
    bm.free()
    dm = dup.data
    orig_uv = dm.uv_layers.active.name
    dm.uv_layers.new(name="proj")
    dm.uv_layers.active = dm.uv_layers[orig_uv]
    proj = dm.uv_layers["proj"]                                    # (fetched again: references go stale)
    Wn, Hn = len(gx), len(gz)
    vz = np.array([(rot @ v.normal).z for v in dm.vertices])
    for lp in dm.loops:
        p = mw @ dm.vertices[lp.vertex_index].co
        up = 1.2 * MM if vz[lp.vertex_index] < -0.35 else 0.0       # turned down: the paint just above
        proj.data[lp.index].uv = ((p.x - g.X0) / (Wn * g.S) + 0.5 / Wn, (p.z + up - g.Z0) / (Hn * g.S) + 0.5 / Hn)
    dm.color_attributes.new("mask", "FLOAT_COLOR", "POINT")
    mask = dm.color_attributes["mask"]
    rr = max(int(0.5 * MM / g.S), 1)
    for v in dm.vertices:
        p = mw @ v.co
        i = int(np.clip(round((p.x - g.X0) / g.S), 0, Wn - 1))
        j = int(np.clip(round((p.z - g.Z0) / g.S), 0, Hn - 1))
        m = float(np.clip(W[max(j - rr, 0):j + rr + 1, max(i - rr, 0):i + rr + 1].max() * 1.5, 0, 1))
        m *= float(sstep(-0.25, 0.1, -(rot @ v.normal).y))
        mask.data[v.index].color = (m, m, m, 1.0)
    target = bpy.data.images.new("bake_" + name, TW, TH, alpha=True, float_buffer=True)
    target.colorspace_settings.name = "Non-Color"
    target.pixels[:] = np.zeros(TW * TH * 4, np.float32)
    mat = bpy.data.materials.new("bake_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    uv_o = nt.nodes.new("ShaderNodeUVMap"); uv_o.uv_map = orig_uv
    uv_p = nt.nodes.new("ShaderNodeUVMap"); uv_p.uv_map = "proj"
    t_o = nt.nodes.new("ShaderNodeTexImage"); t_o.image = cur; t_o.interpolation = "Closest"
    t_p = nt.nodes.new("ShaderNodeTexImage"); t_p.image = front; t_p.extension = "EXTEND"
    att = nt.nodes.new("ShaderNodeAttribute"); att.attribute_name = "mask"
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    emi = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    col_in = [x for x in mix.inputs if x.type == "RGBA"]           # (the Mix node has A/B sockets of every type)
    nt.links.new(uv_o.outputs["UV"], t_o.inputs["Vector"])
    nt.links.new(uv_p.outputs["UV"], t_p.inputs["Vector"])
    nt.links.new(att.outputs["Fac"], mix.inputs["Factor"])
    nt.links.new(t_o.outputs["Color"], col_in[0])
    nt.links.new(t_p.outputs["Color"], col_in[1])
    nt.links.new([x for x in mix.outputs if x.type == "RGBA"][0], emi.inputs["Color"])
    nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])
    t_t = nt.nodes.new("ShaderNodeTexImage"); t_t.image = target
    nt.nodes.active = t_t
    dm.materials.clear()
    dm.materials.append(mat)
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 1
    scn.cycles.device = "CPU"
    for ob in scn.objects:
        ob.select_set(ob == dup)
    bpy.context.view_layer.objects.active = dup
    bpy.ops.object.bake(type="EMIT", margin=3, use_clear=False)
    B = np.array(target.pixels[:], np.float32).reshape(TH, TW, 4)
    a_ = B[..., 3]
    covered = a_ > 0.02
    B[..., :3] = np.where(covered[..., None], B[..., :3] / np.maximum(a_, 1e-4)[..., None], 0.0)   # premultiplied
    CUR = np.where(covered[..., None], np.concatenate([B[..., :3], CUR[..., 3:]], axis=2), CUR)
    face.px = CUR                                                    # (the next feature samples the repainted face)
    print("BAKED %s: faces %d, texels %d" % (name, len(dm.polygons), int(covered.sum())))
    bpy.data.objects.remove(dup, do_unlink=True)


class Flat:
    """A grid made elsewhere (mouth_fit.py), in the shape bake() wants."""

    def __init__(self, gx, gz, FI):
        self.gx, self.gz, self.FI = gx, gz, FI
        self.X0, self.Z0, self.S = float(gx[0]), float(gz[0]), float(gx[1] - gx[0])


def paint_lips():
    if HAS_MOUSTACHE[0]:                                        # (the dark line is the moustache's edge: hair's job)
        print("LIPS: moustache - left to the hair step")
        return None
    MF = mouth_fit.fit_mouth(face, F)
    gx, gz, FI, geo, paint = MF["gx"], MF["gz"], MF["C"], MF["geo"].copy(), MF["paint"].copy()
    step = float(gx[1] - gx[0])
    # Columns whose dark line has hair just above it (a moustache's edge, not the lips') are left out.
    sat = FI.max(axis=2) - FI.min(axis=2)
    L = lum(FI)
    warm = (FI[..., 0] > FI[..., 1]) & (FI[..., 1] > FI[..., 2] - 0.02) & (FI[..., 0] - FI[..., 2] > 0.1) & (L > 0.2)
    ref = np.median(FI[warm], axis=0)                           # this face's skin (and lips)
    s_sat, s_lum = float(ref.max() - ref.min()), float(lum(ref))
    skinlike = (FI[..., 0] >= FI[..., 1]) & (FI[..., 1] >= FI[..., 2] - 0.02) & (sat > 0.55 * s_sat) & (L > 0.45 * s_lum)
    hairy = ~skinlike                                           # grey, white, dark: hair
    _mp = os.path.join(ROOT, "mouth_frames.json")
    if ((json.load(open(_mp)).get(slug) or {}) if os.path.exists(_mp) else {}).get("stubble"):
        hairy[:] = False                                        # (stubble over the lip, not a moustache's edge)
    for i in range(len(gx)):
        if not np.isnan(paint[i]):
            j = int(np.argmin(np.abs(gz - paint[i])))
            if hairy[j + 2:j + 2 + int(2.5 * MM / step), i].mean() > 0.5:
                paint[i] = np.nan
    both = ~np.isnan(geo) & ~np.isnan(paint)
    _mf = (json.load(open(_mp)).get(slug) or {}) if os.path.exists(_mp) else {}
    if "paint_offset" in _mf:                                   # (measured by eye: the paint this far above)
        paint = np.where(np.isnan(geo), np.nan, geo + _mf["paint_offset"] / 1000.0)
        both = ~np.isnan(geo)
    if both.sum() < max(0.3 * (~np.isnan(geo)).sum(), 40):
        print("LIPS: too few columns to trust (%d of %d), left as they are" % (both.sum(), (~np.isnan(geo)).sum()))
        return None
    xs, off = gx[both], (paint - geo)[both]
    keep = np.ones(len(xs), bool)
    for _ in range(3):                                          # a gentle curve through the offsets
        c = np.polyfit(xs[keep] - MF["cx"], off[keep], 2)
        keep = np.abs(np.polyval(c, xs - MF["cx"]) - off) < 1.5 * MM
    okg = ~np.isnan(geo)
    gc0, gc1 = MF["gcorn"]
    dz = np.polyval(c, np.clip(gx, gc0, gc1) - MF["cx"])
    dz = np.clip(dz, off[keep].min(), off[keep].max())          # (no more than measured: the curve's ends overshoot)
    groove = np.interp(gx, gx[okg], geo[okg])
    XX, ZZ = np.meshgrid(gx, gz)
    hor = (1 - sstep(gc1, gc1 + 10 * MM, XX)) * (1 - sstep(-gc0, -gc0 + 10 * MM, -XX))
    ver = 1 - sstep(6 * MM, 22 * MM, np.abs(ZZ - groove[None, :]))
    w = (hor * ver).astype(np.float32)
    sz = ZZ + dz[None, :] * w                                   # where each pixel's paint comes from
    fj = np.clip((sz - gz[0]) / step, 0, len(gz) - 1.001)
    j0 = fj.astype(int)
    t = (fj - j0)[..., None]
    ii = np.arange(len(gx))[None, :].repeat(len(gz), axis=0)
    OUT = FI[j0, ii] * (1 - t) + FI[j0 + 1, ii] * t
    print("LIPS: paint moved by %+.1f mm in the middle (%+.1f..%+.1f across), %d of %d columns measured" % (
        -float(np.polyval(c, 0)) * 1000, -float(dz.max()) * 1000, -float(dz.min()) * 1000, both.sum(), okg.sum()))
    g = Flat(gx, gz, FI)
    save_preview(g, OUT, "lips")
    return g, OUT, w


def paint_skin():
    """The face's skin evened out and given a grain: a texture baked under one-sided light (a light cheek,
    a dark one) is made symmetric in its broad tone (each side the mean of itself and its mirror), its own
    fine detail kept, and fine pores and a little mottling added. Skin-coloured, front-facing pixels only."""
    ez = float(np.mean([e[2] for e in F["eyes"]]))
    x0, x1 = CX - 0.07, CX + 0.07
    z0, z1 = F["mouth"][2] - 0.05, ez + 0.035
    g = Grid(x0, x1, z0, z1, 0.0002)
    FI = g.FI
    valid = ~np.isnan(g.D) & (g.N[..., 1] < -0.05)        # (the nose's and cheeks' steep sides too)
    L = lum(FI)
    sat = FI.max(axis=2) - FI.min(axis=2)
    ref = np.median(FI[valid], axis=0)
    skin = valid & (FI[..., 0] >= FI[..., 2]) & (L > 0.35 * float(lum(ref))) & (L < 2.2 * float(lum(ref))) & (sat > 0.25 * float(ref.max() - ref.min()))
    # (the baked highlights - grey, unsaturated - inside the skin are skin too)
    region = valid & (blur(skin.astype(np.float32), 6.0 * MM) > 0.45)
    m = blur(region.astype(np.float32), 2.0 * MM)
    low = blur(np.where(skin[..., None], FI, ref), 6.0 * MM)
    sym = 0.5 * (low + low[:, ::-1])
    rng_ = np.random.default_rng(7)
    pores = blur(rng_.normal(0, 1, FI.shape[:2]).astype(np.float32), 0.15 * MM)
    pores /= max(float(pores.std()), 1e-6)
    mott = blur(rng_.normal(0, 1, FI.shape[:2]).astype(np.float32), 2.0 * MM)
    mott /= max(float(mott.std()), 1e-6)
    OUT = FI - low + sym
    # every pixel in the skin's own hue (the grey highlights brown again), its brightness kept
    warm = FI[skin & (sat > np.percentile(sat[skin], 60))]
    tone = np.median(warm, axis=0) if len(warm) > 100 else ref     # (the warm skin, not the grey shine)
    hue = tone / max(float(lum(tone)), 1e-4)
    OUT = OUT * 0.35 + (lum(OUT)[..., None] * hue[None, None, :]) * 0.65
    OUT *= (1 + 0.022 * pores + 0.025 * mott)[..., None]
    W = np.clip((m - 0.5) * 2.5, 0, 1) * (m > 0.2)
    sx = 1 - np.clip((np.abs(g.XX - CX) - 0.055) / 0.015, 0, 1)    # fading out at the sides
    W = (W * sx).astype(np.float32)
    print("SKIN: %.0f%% of the box evened, tone %s" % (100 * float((W > 0.5).mean()), ref.round(3)))
    return g, np.clip(OUT, 0, 1), W


if "skin" in FEATURES:
    g, OUT, W = paint_skin()
    save_preview(g, OUT, "skin")
    bake(g, OUT, W, (g.gx[0], g.gx[-1], g.gz[0], g.gz[-1]), "skin")
if "eyes" in FEATURES:
    g, OUT, W = paint_eyes()
    save_preview(g, OUT, "eyes")
    bake(g, OUT, W, (g.gx[0], g.gx[-1], g.gz[0], g.gz[-1]), "eyes")
if "hair" in FEATURES:
    ez = float(np.mean([e[2] for e in F["eyes"]]))
    boxes = [("head", (CX - 0.09, CX + 0.09, ez + 0.022, F["head_z"][1] + 0.005)),
             ("moustache", (CX - 0.05, CX + 0.05, F["mouth"][2] - 0.018, F["nose"][2] - 0.005))]
    for name, b in boxes:
        g, OUT, W = paint_hair(*b, name, main_min=1.5e-4 if name == "moustache" else 0.0)   # a moustache: 150 mm2 or more
        if W.max() > 0:
            bake(g, OUT, W, b, name)

def paint_lips_moustache():
    """Lips under a moustache: per column, the moustache's lower edge stays; the painted upper lip
    (edge .. painted slit) stretches down to the sculpted slit; the lower lip (painted slit .. 8 mm
    below it) moves down onto the sculpted lower lip; below that it fades back to the chin's own paint
    over 10 mm. Hair pixels never move."""
    MF = mouth_fit.fit_mouth(face, F)
    gx, gz, FI = MF["gx"], MF["gz"], MF["C"]
    step = float(gx[1] - gx[0])
    okg = ~np.isnan(MF["geo"])
    geo = np.interp(gx, gx[okg], MF["geo"][okg])
    sat = FI.max(axis=2) - FI.min(axis=2)
    L = lum(FI)
    warm = (FI[..., 0] > FI[..., 1]) & (FI[..., 1] > FI[..., 2] - 0.02) & (FI[..., 0] - FI[..., 2] > 0.1) & (L > 0.2)
    ref = np.median(FI[warm], axis=0)
    s_sat, s_lum = float(ref.max() - ref.min()), float(lum(ref))
    hair = ~((FI[..., 0] >= FI[..., 1]) & (FI[..., 1] >= FI[..., 2] - 0.02) & (sat > 0.55 * s_sat) & (L > 0.45 * s_lum))
    redness = FI[..., 0] - 0.5 * (FI[..., 1] + FI[..., 2])
    lip = redness > max(float(ref[0] - 0.5 * (ref[1] + ref[2])) * 1.05, 0.08)
    hair &= ~lip
    # Per column, the moustache's lower edge and the painted slit (the darkest reddish row under it); then
    # smooth curves through them across the mouth (single picks wobble), outliers dropped.
    OUT = FI.copy()
    W = np.zeros(FI.shape[:2], np.float32)
    xs, es, ss = [], [], []
    for i in range(len(gx)):
        if not (MF["gcorn"][0] + 0.002 < gx[i] < MF["gcorn"][1] - 0.002):
            continue
        jg = int(np.argmin(np.abs(gz - geo[i])))
        up = range(jg, min(jg + int(0.014 / step), len(gz)))
        nh = int(0.0015 / step)                                  # (a real edge: 1.5 mm of hair above it, not
        hj = [j for j in up if hair[j:j + nh, i].mean() > 0.8]   # the painted slit's dark line)
        if not hj:
            continue
        je = min(hj)
        band = range(max(je - int(0.010 / step), 0), je + 1)
        if len(band) < 3:
            continue
        js = min(band, key=lambda j: L[j, i] - 0.5 * redness[j, i])
        xs.append(gx[i]); es.append(gz[je]); ss.append(gz[js])
    _mp = os.path.join(ROOT, "mouth_frames.json")
    MFR = json.load(open(_mp)).get(slug) if os.path.exists(_mp) else None
    UPPER = (MFR or {}).get("upper", "lip")
    # the lower lip: painted LP tall under the painted slit, sculpted LS tall under the sculpted one
    LP, LS = [v / 1000.0 for v in (MFR or {}).get("lower", [8, 8])]
    if MFR:                                                     # measured by eye: these, not the picks
        oz = float(F["mouth"][2])
        pe, ps = np.array(MFR["moustache_edge"], float), np.array(MFR["paint_slit"], float)
        xs = np.linspace(MF["gcorn"][0] - 0.004, MF["gcorn"][1] + 0.004, 80)     # (to past the corners; ends held)
        base = np.interp(xs, gx, geo) if MFR.get("rel") == "groove" else oz
        es = base + np.interp((xs - MF["cx"]) * 1000, pe[:, 0], pe[:, 1]) / 1000.0
        ss = base + np.interp((xs - MF["cx"]) * 1000, ps[:, 0], ps[:, 1]) / 1000.0
        print("LIPS-M: measured frames")
    if len(xs) < 20:
        print("LIPS-M: nothing to move (%d columns)" % len(xs))
        return None
    xs, es, ss = np.array(xs), np.array(es), np.array(ss)

    def fit(y):
        keep = np.ones(len(xs), bool)
        for _ in range(4):
            c = np.polyfit(xs[keep] - MF["cx"], y[keep], 2)
            res = np.abs(np.polyval(c, xs - MF["cx"]) - y)
            keep = res < max(1.2 * MM, 2.0 * float(np.median(res)))
        return c

    ce, cs = fit(es), fit(ss)
    shifts = []
    x0, x1 = float(xs.min()), float(xs.max())
    for i in range(len(gx)):
        if not (x0 <= gx[i] <= x1):
            continue
        ze, zs_, zg = np.polyval(ce, gx[i] - MF["cx"]), np.polyval(cs, gx[i] - MF["cx"]), geo[i]
        if zs_ <= zg + 0.5 * MM or ze <= zs_:
            continue
        # below the slit: the painted lower lip moved down (fading back to the chin's paint); the slit's
        # dark line onto the sculpted slit; above it, up to the moustache, the lower lip's texture
        # mirrored, darkening into the moustache's shadow (the upper lip is not painted under it)
        ztop = ze + (0.0018 if UPPER == "hair" else 0.0)     # (hair mode: over the old edge line too)
        jj = np.nonzero((gz >= zg - LS - 0.010) & (gz < ztop))[0]
        z = gz[jj]
        line = 0.0008
        lip_h = 0.0035                                          # (the lower lip's top 3.5 mm, squeezed to fit)
        up_t = np.clip((z - zg - line) / max(ze - zg - line, 1e-4), 0, 1)
        if UPPER == "hair":                                     # the moustache down to the slit: its own hair
            # (just over the slit the moustache's own edge and shadow line, 1.2 mm of it; above that its hair,
            # copied unstretched from as far above as the edge has come down)
            ew = 0.0012
            sz = np.where(z <= zg + line, np.interp(z, [zg - LS - 0.010, zg - LS, zg, zg + line], [zg - LS - 0.010, zs_ - LP, zs_, zs_ + line]),
                          np.where(z <= zg + line + ew, zs_ + line + (z - zg - line), z + (ze - zg)))
            shade = np.ones_like(z)
        else:
            sz = np.where(z <= zg + line, np.interp(z, [zg - LS - 0.010, zg - LS, zg, zg + line], [zg - LS - 0.010, zs_ - LP, zs_, zs_ + line]),
                          zs_ - line - up_t * lip_h)
            shade = np.where(z > zg + line, 1.0 - 0.22 * up_t, 1.0)
        fj = np.clip((sz - gz[0]) / step, 0, len(gz) - 1.001)
        j0 = fj.astype(int)
        t = (fj - j0)[:, None]
        OUT[jj, i] = (FI[j0, i] * (1 - t) + FI[j0 + 1, i] * t) * shade[:, None]
        W[jj, i] = float(sstep(x0, x0 + 6 * MM, gx[i]) * (1 - sstep(x1 - 6 * MM, x1, gx[i])))   # fading past the corners
        W[jj, i] *= sstep(zg - LS - 0.010, zg - LS - 0.004, gz[jj])   # (its bottom fades into the chin's own paint)
        if UPPER == "hair":                                     # (the copy's top fades into the moustache)
            W[jj, i] *= 1.0 - sstep(ztop - 0.0009, ztop, gz[jj])
        shifts.append((zs_ - zg) * 1000)
    cols = len(shifts)
    if os.environ.get("LIPS_DEBUG"):
        for xm in range(-30, 31, 5):
            ic = int(np.argmin(np.abs(gx - (MF["cx"] + xm / 1000.0))))
            sel = np.nonzero((gz > geo[ic] + 0.0005) & (gz < geo[ic] + 0.010))[0]
            Lc = blur(L[:, ic:ic + 1, None].repeat(3, axis=2), 0.0003)[:, 0, 0] if False else L[:, ic]
            js = sel[int(np.argmin(Lc[sel]))]
            print("DARK x %+3d mm: darkest at %+.1f mm over the slit (L %.2f)" % (xm, (gz[js] - geo[ic]) * 1000, Lc[js]))
        ic = int(np.argmin(np.abs(gx - MF["cx"])))
        zg_c = geo[ic]
        for j in range(len(gz)):
            dz = (gz[j] - zg_c) * 1000
            if -4 < dz < 9 and j % 2 == 0:
                print("DBG dz %+5.1f  orig L %.2f  new L %.2f  W %.2f" % (dz, lum(FI[j, ic]), lum(OUT[j, ic]), W[j, ic]))
        print("DBG geo-mouth %.1f mm; ze %.1f zs %.1f (from geo)" % ((zg_c - F["mouth"][2]) * 1000, (np.polyval(ce, 0) - zg_c) * 1000, (np.polyval(cs, 0) - zg_c) * 1000))
    # columns smoothed (the edge and slit picks wobble), and the moved band feathered sideways
    W = np.clip(blur(W, 1.5 * MM) * 1.4, 0, 1)
    OUT = FI * (1 - W[..., None]) + blur(OUT, 0.12 * MM) * W[..., None]
    print("LIPS-M: %d columns, lips moved down %.1f mm (median; %.1f..%.1f)" % (cols, np.median(shifts), min(shifts), max(shifts)))
    g = Flat(gx, gz, FI)
    save_preview(g, OUT, "lipsm")
    return g, OUT, W


def paint_lip_volume():
    """The sculpted lips coloured as lips, wherever the paint left them skin: between the slit and the crease
    under the lower lip (the lower lip, its underside too), and between the slit and the moustache's edge or
    the upper lip's border (the upper lip). The texture's own detail is kept (its colour divided by its local
    mean, times the lip colour); a dark line along the slit; hair (a moustache) is never touched."""
    MF = mouth_fit.fit_mouth(face, F)
    gx, gz, FI, D = MF["gx"], MF["gz"], MF["C"], MF["D"]
    step = float(gx[1] - gx[0])
    okg = ~np.isnan(MF["geo"])
    geo = np.interp(gx, gx[okg], MF["geo"][okg])
    c0, c1 = MF["gcorn"]
    Dn = np.where(np.isnan(D), np.nanmax(D), D)
    k = int(1.2 * MM / step)
    up, dn = np.roll(Dn, -k, axis=0), np.roll(Dn, k, axis=0)
    cav = np.minimum(Dn - up, Dn - dn)                          # a groove: deeper than 1.2 mm above and below
    # the crease under the lower lip, and (no moustache) the upper lip's border: per column, then a smooth fit
    xs, lo, hi = [], [], []
    for i in range(len(gx)):
        if not (c0 + 0.004 < gx[i] < c1 - 0.004):
            continue
        sel = np.nonzero((gz > geo[i] - 0.014) & (gz < geo[i] - 0.003))[0]
        if len(sel):
            xs.append(gx[i]); lo.append(gz[sel[int(np.argmax(cav[sel, i]))]])
    xs, lo = np.array(xs), np.array(lo)
    keep = np.ones(len(xs), bool)
    for _ in range(4):
        cl = np.polyfit(xs[keep] - MF["cx"], lo[keep], 2)
        res = np.abs(np.polyval(cl, xs - MF["cx"]) - lo)
        keep = res < max(1.0 * MM, 2.0 * float(np.median(res)))
    sat = FI.max(axis=2) - FI.min(axis=2)
    L = lum(FI)
    warm = (FI[..., 0] > FI[..., 1]) & (FI[..., 1] > FI[..., 2] - 0.02) & (FI[..., 0] - FI[..., 2] > 0.1) & (L > 0.2)
    ref = np.median(FI[warm], axis=0)
    hair = ~((FI[..., 0] >= FI[..., 1]) & (FI[..., 1] >= FI[..., 2] - 0.02) & (sat > 0.55 * float(ref.max() - ref.min())) & (L > 0.45 * float(lum(ref))))
    redness = FI[..., 0] - 0.5 * (FI[..., 1] + FI[..., 2])
    lipish = (redness > float(ref[0] - 0.5 * (ref[1] + ref[2])) * 1.08) & ~hair
    hair &= ~lipish
    XX, ZZ = np.meshgrid(gx, gz)
    lower_b = np.polyval(cl, np.clip(XX, c0, c1) - MF["cx"])
    lip_h = np.maximum(geo[None, :] - lower_b, 0.003)
    upper_b = geo[None, :] + 0.75 * lip_h
    inx = sstep(c0 - 0.001, c0 + 0.004, XX) * (1 - sstep(c1 - 0.004, c1 + 0.001, XX))
    vert = sstep(-0.0006, 0.0004, ZZ - lower_b) * (1 - sstep(-0.0004, 0.0006, ZZ - upper_b))
    M_ = np.clip(inx * vert, 0, 1) * (1 - blur(hair.astype(np.float32), 0.25 * MM))
    M_ = blur(M_.astype(np.float32), 0.3 * MM)
    # the lip colour: the reddest quarter of the painted lips (inside the sculpted lips, not hair), and at
    # least as red as lips over this skin
    band = (M_ > 0.5) & ~hair
    rr = redness[band]
    lip_col = np.median(FI[band][rr >= np.percentile(rr, 75)], axis=0) if band.sum() > 200 else ref
    want = ref * 0.62 + np.array([0.70, 0.36, 0.36]) * 0.38
    if float(lip_col[0] - 0.5 * (lip_col[1] + lip_col[2])) < float(want[0] - 0.5 * (want[1] + want[2])):
        lip_col = lip_col * 0.4 + want * 0.6
    detail = FI / np.maximum(blur(FI, 1.2 * MM), 1e-3)
    tinted = np.clip(lip_col[None, None, :] * detail, 0, 1)
    tinted *= (1 - 0.18 * sstep(0.0, 1.0, (ZZ - geo[None, :]) / np.maximum(upper_b - geo[None, :], 1e-4)))[..., None]   # upper lip: in shade
    line = np.exp(-((ZZ - geo[None, :] - 0.0002) / (0.7 * MM)) ** 2) * inx
    tinted *= (1 - 0.3 * line)[..., None]
    OUT = FI * (1 - M_[..., None]) + tinted * M_[..., None]
    print("LIPS-V: lip colour %s; lower lip %.1f mm tall in the middle" % (lip_col.round(3), float(np.interp(MF["cx"], gx, geo) - np.polyval(cl, 0)) * 1000))
    g = Flat(gx, gz, FI)
    save_preview(g, OUT, "lipsv")
    return g, OUT, M_


if "lipsv" in FEATURES:
    r = paint_lip_volume()
    if r:
        g, OUT, W = r
        bake(g, OUT, W, (g.gx[0], g.gx[-1], g.gz[0], g.gz[-1]), "lipsv")
if "lipsm" in FEATURES:
    r = paint_lips_moustache()
    if r:
        g, OUT, W = r
        bake(g, OUT, W, (g.gx[0], g.gx[-1], g.gz[0], g.gz[-1]), "lipsm")
if "brows" in FEATURES:
    ez = float(np.mean([e[2] for e in F["eyes"]]))
    b = (CX - 0.07, CX + 0.07, ez + 0.003, ez + 0.032)
    g, OUT, W = paint_hair(*b, "brows")
    if W.max() > 0:
        bake(g, OUT, W, b, "brows")
if "lips" in FEATURES:
    r = paint_lips()
    if r:
        g, OUT, W = r
        bake(g, OUT, W, (g.gx[0], g.gx[-1], g.gz[0], g.gz[-1]), "lips")

def make_patch():
    """The repainted features on a texture of their own: the faces they change (any corner with weight) get
    a second material with that texture and UVs projected straight from the front; everything else keeps
    Tripo's texture and UVs untouched. At the patch's edges the weight is 0, so its colours are the
    original's there and the faces meet without a seam."""
    X0 = min(g.gx[0] for g, _, _, _ in PATCHES); X1 = max(g.gx[-1] for g, _, _, _ in PATCHES)
    Z0 = min(g.gz[0] for g, _, _, _ in PATCHES); Z1 = max(g.gz[-1] for g, _, _, _ in PATCHES)
    PN = 2048
    step = max(X1 - X0, Z1 - Z0) / PN
    PW, PH = int(np.ceil((X1 - X0) / step)) + 1, int(np.ceil((Z1 - Z0) / step)) + 1
    px_ = X0 + np.arange(PW) * step
    pz_ = Z0 + np.arange(PH) * step
    P = np.zeros((PH, PW, 3), np.float32)
    WA = np.zeros((PH, PW), np.float32)
    have = np.zeros((PH, PW), bool)

    def resample(g, A):
        """A (on grid g) at the patch's pixels inside g; -> (rows, cols, values)."""
        i0, i1 = np.searchsorted(px_, g.gx[0]), np.searchsorted(px_, g.gx[-1])
        j0, j1 = np.searchsorted(pz_, g.gz[0]), np.searchsorted(pz_, g.gz[-1])
        fx = (px_[i0:i1] - g.gx[0]) / g.S
        fz = (pz_[j0:j1] - g.gz[0]) / g.S
        ix = np.clip(fx.astype(int), 0, len(g.gx) - 2); tx = (fx - ix)[None, :]
        iz = np.clip(fz.astype(int), 0, len(g.gz) - 2); tz = (fz - iz)[:, None]
        if A.ndim == 3:
            tx, tz = tx[..., None], tz[..., None]
        a = A[iz][:, ix] * (1 - tx) + A[iz][:, ix + 1] * tx
        b = A[iz + 1][:, ix] * (1 - tx) + A[iz + 1][:, ix + 1] * tx
        return slice(j0, j1), slice(i0, i1), a * (1 - tz) + b * tz

    for g, OUT, W, name in PATCHES:
        rs, cs, fi = resample(g, g.FI)
        _, _, out = resample(g, OUT)
        _, _, w = resample(g, W)
        P[rs, cs] = np.where(have[rs, cs][..., None], P[rs, cs], fi)
        have[rs, cs] = True
        P[rs, cs] = P[rs, cs] * (1 - w[..., None]) + out * w[..., None]
        WA[rs, cs] = np.maximum(WA[rs, cs], w)
    # the patch's faces: facing front, down or up (not away), on the face, a corner with weight
    rot = mw.to_3x3()
    inv_ = mw.inverted()
    vw = np.zeros(len(me.vertices))
    for v in me.vertices:
        q = mw @ v.co
        i, j = int(round((q.x - X0) / step)), int(round((q.z - Z0) / step))
        if 0 <= i < PW and 0 <= j < PH and have[j, i]:
            vw[v.index] = WA[j, i]
    mat2 = me.materials[0].copy()
    mat2.name = me.materials[0].name + "_face"
    img = bpy.data.images.new(slug + "_facepatch", PW, PH)
    img.pixels[:] = np.concatenate([np.clip(P, 0, 1), np.ones((PH, PW, 1), np.float32)], axis=2).ravel()
    img.filepath_raw = os.path.join(ROOT, slug, "textures", slug + "_facepatch.png")
    img.file_format = "PNG"
    img.save()
    path = img.filepath_raw
    bpy.data.images.remove(img)
    img = bpy.data.images.load(path)
    for n in mat2.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image == src_img:
            n.image = img
    # (no normal map on the patch: the atlas's normal map read through the patch's front-projected UVs
    # lights its faces in stray wedges)
    for n in list(mat2.node_tree.nodes):
        if n.type == "NORMAL_MAP":
            for t in [l.from_node for l in n.inputs["Color"].links]:
                mat2.node_tree.nodes.remove(t)
            mat2.node_tree.nodes.remove(n)
    me.materials.append(mat2)
    mi = len(me.materials) - 1
    uvl = me.uv_layers.active
    n_faces = 0
    # a dark pixel of the patch, for hidden faces: the darkest of the repainted area, not black
    Lp = P @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    Lp = np.where(WA > 0.9, Lp, 9.0)
    jd, id_ = np.unravel_index(int(np.argmin(np.where(Lp > 0.04, Lp, 9.0))), Lp.shape)
    DARK_UV = ((id_ + 0.5) / PW, (jd + 0.5) / PH)
    for poly in me.polygons:
        if poly.material_index != 0 or max(vw[i] for i in poly.vertices) <= 0.02:
            continue
        c = mw @ poly.center
        nrm = rot @ poly.normal
        if nrm.y > 0.25:
            continue
        # A projection from the front reads a face true only where the front view sees that face: its middle
        # and every corner the first surface straight ahead (within 0.6 mm). A face hidden behind another (a
        # lid's or brow's underside) would take the other's paint: it keeps Tripo's texture.
        seen = True
        inside = True                                           # (every corner over the patch's painted pixels)
        for i in poly.vertices:
            q = mw @ me.vertices[i].co
            pi, pj = int(round((q.x - X0) / step)), int(round((q.z - Z0) / step))
            if not (0 <= pi < PW and 0 <= pj < PH and have[pj, pi]):
                inside = False
        if not inside:
            continue
        for q in [c] + [mw @ me.vertices[i].co for i in poly.vertices]:
            h = face.bvh.ray_cast(Vector((q.x, face.front_y, q.z)), Vector((0, 1, 0)))
            if h[0] is None or q.y - h[0].y > 0.0006:
                seen = False
                break
        # (but faces wholly inside the repaint - the old eye paint on the lid's underside - take it anyway:
        # from the front they show what lies in front of them, the new lid)
        if not seen and min(vw[i] for i in poly.vertices) < 0.5:
            continue
        # (an upper lid's underside facing down is seen nearly edge-on from the front: the lash line would
        # stretch over it into teeth when seen from below - it takes the lid's skin like a hidden face)
        if seen and nrm.z < -0.55:
            for e in eyes:
                o = e["o"]
                if o[0] - 0.002 < c.x < o[1] + 0.002 and (o[2] + o[3]) / 2 < c.z < o[3] + 0.003:
                    seen = False
        poly.material_index = mi
        for li in poly.loop_indices:
            if not seen:                                        # (hidden - a lid's underside: the lid's own skin,
                q = mw @ me.vertices[me.loops[li].vertex_index].co   #  just over the opening's top edge)
                zt = q.z + 0.002
                for e in eyes:
                    if e["o"][0] - 0.003 < q.x < e["o"][1] + 0.003 and abs(q.z - (e["o"][2] + e["o"][3]) / 2) < 0.012:
                        zt = max(q.z, e["o"][3]) + 0.0025
                        if q.z < (e["o"][2] + e["o"][3]) / 2:          # (below the eye: the cheek's skin under it)
                            zt = min(q.z, e["o"][2]) - 0.0025
                        # (just over the opening's top edge: the lash line, where the eye sheet meets the lid)
                        o = e["o"]
                        t = (q.x - (o[0] + o[1]) / 2) / ((o[1] - o[0]) / 2)
                        if abs(t) < 1:
                            top = (o[2] + o[3]) / 2 + (o[3] - o[2]) / 2 * float(skew_arc(np.array((t * e["inner"] + 1) / 2), 0.56)) ** 0.8
                            if (o[2] + o[3]) / 2 < q.z < top + 0.0015:
                                zt = top + 0.00035
                uvl.data[li].uv = ((q.x - X0) / (PW * step) + 0.5 / PW, (zt - Z0) / (PH * step) + 0.5 / PH)
                continue
            q = mw @ me.vertices[me.loops[li].vertex_index].co
            uvl.data[li].uv = ((q.x - X0) / (PW * step) + 0.5 / PW, (q.z - Z0) / (PH * step) + 0.5 / PH)
        n_faces += 1
    print("PATCH %d x %d px (%.3f mm a pixel), %d faces" % (PW, PH, step * 1000, n_faces))
    # The eyes' sheets: over each sculpted opening a thin sheet 0.4 mm in front of the socket, showing the
    # same front image (so it lines up with the patch round it exactly), its rim tucked 1.5 mm behind the
    # skin. The socket's own faces sit at all angles and are partly hidden from the front, so painting them
    # tears; the sheet is the front view itself, and hides them from every angle a player sees it from.
    if "eyes" in FEATURES and eyes:
        import bmesh as _bm
        # how far in front of the socket's floor (a deep, faceted socket pokes through a sheet too close)
        SHEET_FRONT = float(FR.get("sheet_front", 0.4)) * 0.001
        sheets = []
        g_ = 0.0002
        for e in eyes:
            o = e["o"]
            xc, zc, w, h = (o[0] + o[1]) / 2, (o[2] + o[3]) / 2, o[1] - o[0], o[3] - o[2]
            xs = np.arange(o[0] - 0.0015, o[1] + 0.0015 + g_, g_)
            zs = np.arange(o[2] - 0.0015, o[3] + 0.0015 + g_, g_)
            bm = _bm.new()
            uvb = bm.loops.layers.uv.new(uvl.name)
            grid = {}
            for i, x in enumerate(xs):
                t = (x - xc) / (w / 2)
                u = (t * e["inner"] + 1) / 2
                inside_x = abs(t) < 1
                top = zc + h / 2 * float(skew_arc(np.array(u), 0.56)) ** 0.8 if inside_x else zc
                bot = zc - h / 2 * float(skew_arc(np.array(u), 0.42)) if inside_x else zc
                for j, z in enumerate(zs):
                    hit = face.bvh.ray_cast(Vector((x, face.front_y, z)), Vector((0, 1, 0)))
                    if hit[0] is None:
                        continue
                    d_in = min(z - bot, top - z) if inside_x else -1.0       # how far inside the opening
                    # in front of the socket inside the opening, behind the skin outside it, going over
                    # smoothly across the opening's edge (a step would show the grid as a staircase)
                    t_ = float(np.clip((d_in + 0.0012) / 0.0014, 0.0, 1.0))
                    t_ = t_ * t_ * (3 - 2 * t_)
                    y = hit[0].y + 0.0015 * (1 - t_) - SHEET_FRONT * t_
                    grid[(i, j)] = bm.verts.new(inv_ @ Vector((x, y, z)))
            for (i, j), v in grid.items():
                q = [grid.get(k) for k in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
                if all(q):
                    f = bm.faces.new(q)
                    f.smooth = True
                    for lp in f.loops:
                        w_ = mw @ lp.vert.co
                        lp[uvb].uv = ((w_.x - X0) / (PW * step) + 0.5 / PW, (w_.z - Z0) / (PH * step) + 0.5 / PH)
            bm.normal_update()
            if sum((rot @ f.normal).y for f in bm.faces) > 0:
                _bm.ops.reverse_faces(bm, faces=bm.faces)
            m_ = bpy.data.meshes.new("eye_sheet")
            bm.to_mesh(m_)
            bm.free()
            o_ = bpy.data.objects.new("eye_sheet", m_)
            o_.matrix_world = mw
            scn.collection.objects.link(o_)
            m_.materials.append(mat2)
            o_.vertex_groups.new(name="mixamorig:Head").add(list(range(len(m_.vertices))), 1.0, "REPLACE")
            sheets.append(o_)
        n_sheet = sum(len(o_.data.polygons) for o_ in sheets)
        with bpy.context.temp_override(active_object=body, selected_editable_objects=[body] + sheets, selected_objects=[body] + sheets):
            bpy.ops.object.join()
        # The sheets' own smooth normals: joined into a mesh with custom normals they come out with stray
        # ones (a fan of light and dark wedges across the eye); the body keeps Tripo's.
        cn = [l.vector.copy() for l in me.corner_normals]
        first = len(me.polygons) - n_sheet
        vn = {}
        for pi in range(first, len(me.polygons)):
            pp = me.polygons[pi]
            for vi in pp.vertices:
                vn[vi] = vn.get(vi, Vector()) + pp.normal * pp.area
        # (mostly facing straight out: the sheet follows the socket's facets, which its own normals would
        # light as a fan of wedges across the eye)
        fwd = (mw.inverted().to_3x3() @ Vector((0, -1, 0))).normalized()
        for pi in range(first, len(me.polygons)):
            for li in me.polygons[pi].loop_indices:
                cn[li] = (vn[me.loops[li].vertex_index].normalized() * 0.25 + fwd * 0.75).normalized()
        me.normals_split_custom_set(cn)
        print("EYE SHEETS", len(sheets))


if PATCH and PATCHES:
    make_patch()
new = bpy.data.images.new(slug + "_albedo_eyefix", TW, TH)
new.pixels[:] = CUR.ravel()
new.filepath_raw = os.path.join(ROOT, slug, "textures", slug + "_albedo_eyefix.png")
new.file_format = "PNG"
new.save()
path = new.filepath_raw
bpy.data.images.remove(new)
new = bpy.data.images.load(path)                       # a file image: the glTF exporter copies it as is
new.name = slug + "_albedo_eyefix"                     # (a generated one goes through the view transform)
for n in me.materials[0].node_tree.nodes:
    if n.type == "TEX_IMAGE" and n.image == src_img:
        n.image = new
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, slug, slug + "_eyefix_paint.blend"))
print("SAVED", slug)
