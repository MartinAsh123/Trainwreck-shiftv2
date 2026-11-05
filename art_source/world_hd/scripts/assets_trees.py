"""Snowy Bohemian forest trees for the landscape (run inside Blender 5.2 via build_world.py).

All trees are built 1 unit tall (the scenery scales each instance to its height) in GODOT space
(x right, y up, z toward the viewer), converted per vertex with hdlib.G().

    spruce_a / spruce_b / fir_c  — Norway spruce and silver fir: whorls of drooping branches, each
        a folded card (or two) carrying a scanned fir twig (Poly Haven fir_tree_01, CC0), snow
        pillows lying along the upper branches, a tapered bark trunk
    *_lod  — the same silhouettes as opaque, jagged skirts with the needle-canopy texture, for the
        trees beyond the first ~150 m
    scots_pine (+ _lod) — tall trunk, flat crown of twig rosettes (Poly Haven pine_tree_01 twig)
    birch — bare white birch: forked trunk, swept branches, fine twig cards

Vertex colour (COLOR_0): R = crown occlusion (dark inside, 1 at the tips), G = snow may lie here,
B = bark variant (pine: 0 grey lower bark, 1 orange upper bark). Materials are named for the
Godot shaders that replace them: bark_fir, twig_fir, snow_lump, bark_pine, twig_pine, bark_birch,
twig_birch, needles_mass.
"""
import bpy, bmesh, math, random, json, os
from mathutils import Vector

import hdlib as H

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECTS = json.load(open(os.path.join(ROOT, "twig_rects.json")))
FIR = [RECTS["fir"][i] for i in (0, 1, 2, 3, 4)]           # the big fir twig sprites
FIR_SMALL = [RECTS["fir"][i] for i in (6, 7)]
PINE = [[0.045, 0.03, 0.2, 0.445]]                          # the upright pine twig in its atlas
BIRCH = [[0.0, 0.0, 1.0, 1.0]]
UP = Vector((0, 1, 0))


class Builder:
    """Faces in Godot space with UVs, vertex colours, per-face material and optional custom normals."""

    def __init__(self, name, mats):
        self.name = name
        self.mats = mats
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.col = self.bm.loops.layers.color.new("Col")
        self.normals = []               # per face: list of Godot-space normals per corner (or None)

    def face(self, pts, uvs, cols, mat, normals=None):
        vs = [self.bm.verts.new(H.G(Vector(p))) for p in pts]
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return
        f.material_index = self.mats.index(mat)
        f.smooth = True
        for lp, uv, c in zip(f.loops, uvs, cols):
            lp[self.uv].uv = uv
            lp[self.col] = c if len(c) == 4 else (*c, 1.0)
        self.normals.append((f, normals))

    def quad(self, a, b, c, d, uva, uvb, uvc, uvd, cols, mat, normals=None):
        self.face([a, b, c, d], [uva, uvb, uvc, uvd], cols, mat, normals)

    def finish(self):
        me = bpy.data.meshes.new(self.name)
        # Corner normals in face order (bmesh faces keep creation order).
        self.bm.faces.ensure_lookup_table()
        custom = []
        for f, ns in self.normals:
            if ns is None:
                ns = [None] * len(f.loops)
            for lp, n in zip(f.loops, ns):
                custom.append(H.G(n).normalized() if n is not None else None)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(_mat(m))
        # Faces without explicit normals: use their own (smooth) normal.
        me.update()
        loop_n = []
        for poly in me.polygons:
            for li in poly.loop_indices:
                loop_n.append(None)
        i = 0
        for poly in me.polygons:
            for li in poly.loop_indices:
                n = custom[i] if i < len(custom) else None
                loop_n[li] = n if n is not None else poly.normal.copy()
                i += 1
        me.normals_split_custom_set([tuple(n) for n in loop_n])
        ca = me.color_attributes.get("Col")
        if ca:
            me.color_attributes.active_color = ca
            me.color_attributes.render_color_index = me.color_attributes.find("Col")
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


_mats = {}


def _mat(name):
    if name not in _mats:
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        _mats[name] = m
    return _mats[name]


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


# ————— trunk —————

def trunk(B, h, r0, r1, sides, rings, mat, flare=1.5, bark_tile=(0.08, 0.07), col_fn=None, bend=None):
    """Tapered trunk from y = 0 to h, radius r0 -> r1, root flare at the foot. UV: u around (one
    tile per bark_tile[0] of circumference), v up (bark_tile[1] per tile)."""
    prof = []
    for k in range(rings + 1):
        t = k / rings
        y = h * t
        r = lerp(r0, r1, t ** 0.8) * (1.0 + (flare - 1.0) * max(0.0, 1.0 - t * 14.0) ** 2)
        off = bend(t) if bend else Vector((0, 0, 0))
        prof.append((y, r, off))
    circ = math.tau * r0
    for k in range(rings):
        y0, ra, oa = prof[k]
        y1, rb, ob = prof[k + 1]
        for s in range(sides):
            a0 = math.tau * s / sides
            a1 = math.tau * (s + 1) / sides
            p = [Vector((math.cos(a0) * ra, y0, math.sin(a0) * ra)) + oa, Vector((math.cos(a1) * ra, y0, math.sin(a1) * ra)) + oa,
                 Vector((math.cos(a1) * rb, y1, math.sin(a1) * rb)) + ob, Vector((math.cos(a0) * rb, y1, math.sin(a0) * rb)) + ob]
            u0 = s / sides * circ / bark_tile[0]
            u1 = (s + 1) / sides * circ / bark_tile[0]
            v0, v1 = y0 / bark_tile[1], y1 / bark_tile[1]
            n = [Vector((math.cos(a0), 0, math.sin(a0))), Vector((math.cos(a1), 0, math.sin(a1)))]
            c0 = col_fn(y0 / h) if col_fn else (0.8, 0.25, 0.0)
            c1 = col_fn(y1 / h) if col_fn else (0.8, 0.25, 0.0)
            B.quad(p[0], p[3], p[2], p[1], (u0, v0), (u0, v1), (u1, v1), (u1, v0),
                   [c0, c1, c1, c0], mat, [n[0], n[0], n[1], n[1]])


def tube(B, pts, radii, sides, mat, tile=(0.06, 0.08), col=(0.7, 0.3, 0.0)):
    """Swept tube through Godot points with per-point radius (branches)."""
    frames = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = d.cross(UP)
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(d).normalized()
        frames.append((side, up))
    acc = 0.0
    vs = [0.0]
    for i in range(1, len(pts)):
        acc += (pts[i] - pts[i - 1]).length
        vs.append(acc)
    for i in range(len(pts) - 1):
        for s in range(sides):
            a0 = math.tau * s / sides
            a1 = math.tau * (s + 1) / sides
            ring = []
            for j, a in ((i, a0), (i, a1), (i + 1, a1), (i + 1, a0)):
                side, up = frames[j]
                n = side * math.cos(a) + up * math.sin(a)
                ring.append((pts[j] + n * radii[j], n))
            uv = [(s / sides * 0.3 / tile[0], vs[i] / tile[1]), ((s + 1) / sides * 0.3 / tile[0], vs[i] / tile[1]),
                  ((s + 1) / sides * 0.3 / tile[0], vs[i + 1] / tile[1]), (s / sides * 0.3 / tile[0], vs[i + 1] / tile[1])]
            B.quad(ring[0][0], ring[3][0], ring[2][0], ring[1][0], uv[0], uv[3], uv[2], uv[1],
                   [col] * 4, mat, [ring[0][1], ring[3][1], ring[2][1], ring[1][1]])


# ————— cards —————

def card_strip(B, centre, across, rect, mat, cols, normal_fn, fold=0.0, flip=False):
    """A twig card along the polyline `centre` (base -> tip). `across[i]` = half-width vector at
    each point. The sprite's stem runs bottom (base) to top (tip) of its rect. fold > 0 raises the
    card's edges (a V-shaped gutter: twigs splay upward). Two quads across per segment."""
    x0, y0, x1, y1 = rect
    if flip:
        x0, x1 = x1, x0
    n = len(centre)
    for i in range(n - 1):
        ta, tb = i / (n - 1), (i + 1) / (n - 1)
        va, vb = lerp(1 - y1, 1 - y0, ta), lerp(1 - y1, 1 - y0, tb)
        ca, cb = centre[i], centre[i + 1]
        ea, eb = across[i], across[i + 1]
        la, lb = ea.length, eb.length
        lift_a, lift_b = UP * (la * fold), UP * (lb * fold)
        um = (x0 + x1) * 0.5
        for side, u in ((-1, x0), (1, x1)):
            pa = ca + ea * side + lift_a
            pb = cb + eb * side + lift_b
            q = [ca, pa, pb, cb] if side > 0 else [ca, cb, pb, pa]
            uv = [(um, va), (u, va), (u, vb), (um, vb)] if side > 0 else [(um, va), (um, vb), (u, vb), (u, va)]
            cl = [cols[i], cols[i], cols[i + 1], cols[i + 1]] if side > 0 else [cols[i], cols[i + 1], cols[i + 1], cols[i]]
            B.face(q, uv, cl, mat, [normal_fn(p) for p in q])


def snow_pillow(B, centre, width, thick, cols, mat="snow_lump"):
    """A soft ridge of snow lying along a branch: cross-section of 5 points (edges sunk, crown
    raised), tapering at both ends."""
    n = len(centre)
    prof = [(-1.0, -0.2), (-0.4, 0.9), (0.4, 0.9), (1.0, -0.2)]
    rows = []
    for i in range(n):
        t = i / (n - 1)
        taper = math.sin(math.pi * lerp(0.08, 0.92, t)) ** 0.6
        d = (centre[min(i + 1, n - 1)] - centre[max(i - 1, 0)])
        d.y = 0
        side = Vector((-d.z, 0, d.x)).normalized() if d.length > 1e-6 else Vector((1, 0, 0))
        row = []
        for x, y in prof:
            p = centre[i] + side * (x * width * taper) + UP * (y * thick * taper)
            nrm = (side * x * 0.8 + UP * (0.6 + y)).normalized()
            row.append((p, nrm))
        rows.append(row)
    for i in range(n - 1):
        for j in range(len(prof) - 1):
            a, b, c, d = rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]
            B.face([a[0], d[0], c[0], b[0]], [(j / 3, i / n), (j / 3, (i + 1) / n), ((j + 1) / 3, (i + 1) / n), ((j + 1) / 3, i / n)],
                   [cols] * 4, mat, [a[1], d[1], c[1], b[1]])


def radial_normal(axis_y_scale=0.6):
    """Foliage normals pointing out of the crown (mixed with up) so the cards shade like a mass."""
    def fn(p):
        r = Vector((p.x, (p.y - 0.55) * axis_y_scale, p.z))
        if r.length < 1e-4:
            return UP.copy()
        return (r.normalized() * 0.75 + UP * 0.45).normalized()
    return fn


# ————— spruce / fir —————

SPRUCE = {
    "spruce_a": dict(seed=11, whorls=19, lmax=0.27, base_y=0.1, per=(5, 7), droop=0.42, r0=0.019, narrow=0.9),
    "spruce_b": dict(seed=23, whorls=20, lmax=0.22, base_y=0.14, per=(5, 7), droop=0.5, r0=0.017, narrow=1.05),
    "fir_c": dict(seed=37, whorls=18, lmax=0.24, base_y=0.12, per=(4, 6), droop=0.22, r0=0.02, narrow=1.25),
}


def branch_path(base, d, L, pitch, droop, segs=3):
    pts = []
    for k in range(segs + 1):
        s = k / segs
        pts.append(base + d * (L * s) + UP * (L * (math.tan(pitch) * s - droop * s * s)))
    return pts


def spruce(name):
    p = SPRUCE[name]
    rng = random.Random(p["seed"])
    B = Builder(name, ["bark_fir", "twig_fir", "snow_lump"])
    nfn = radial_normal()
    trunk(B, 0.985, p["r0"], 0.002, 8, 9, "bark_fir", flare=1.6, bark_tile=(0.07, 0.065),
          col_fn=lambda t: (lerp(0.45, 0.9, t), 0.2, 0.0))
    nw = p["whorls"]
    for i in range(nw):
        t = i / (nw - 1)
        y = lerp(p["base_y"], 0.95, t ** 0.92)
        L = (p["lmax"] * (1.0 - t) ** p["narrow"] + 0.025) * rng.uniform(0.85, 1.1)
        cnt = rng.randint(*p["per"]) if t < 0.85 else 4
        az0 = rng.random() * math.tau
        for b in range(cnt):
            az = az0 + b * math.tau / cnt + rng.uniform(-0.25, 0.25)
            d = Vector((math.cos(az), 0, math.sin(az)))
            side = Vector((-d.z, 0, d.x))
            pitch = math.radians(lerp(-6.0, 32.0, t ** 1.6) + rng.uniform(-6, 6))
            droop = p["droop"] * lerp(1.0, 0.35, t) * rng.uniform(0.8, 1.2)
            base = Vector((0, y, 0)) + d * 0.004
            pts = branch_path(base, d, L, pitch, droop)
            ao = [(lerp(0.35, 1.0, (k / 3) ** 0.7) * lerp(0.75, 1.0, t), 1.0, 0.0) for k in range(4)]
            rect = rng.choice(FIR)
            aspect = (rect[2] - rect[0]) / (rect[3] - rect[1])
            hw = L * aspect * 0.5 * rng.uniform(1.0, 1.25)
            fold_lift = 1.0
            across = [side * (hw * lerp(0.55, 1.0, min(1.0, k / 1.5))) for k in range(4)]
            card_strip(B, pts, across, rect, "twig_fir", ao, nfn, fold=rng.uniform(0.15, 0.35), flip=rng.random() < 0.5)
            # Two side sprays fanning out from the middle of the branch fill the gaps.
            for yaw in (-0.42, 0.42):
                dy = (d * math.cos(yaw) + side * math.sin(yaw)).normalized()
                sy = Vector((-dy.z, 0, dy.x))
                st0 = base + d * (L * 0.22) + UP * (L * (math.tan(pitch) * 0.22 - droop * 0.05) - 0.004)
                pts_s = branch_path(st0, dy, L * 0.72, pitch - 0.05, droop * 1.1, segs=2)
                rect_s = rng.choice(FIR)
                asp_s = (rect_s[2] - rect_s[0]) / (rect_s[3] - rect_s[1])
                hws = L * 0.72 * asp_s * 0.5
                card_strip(B, pts_s, [sy * (hws * 0.7), sy * hws, sy * hws], rect_s, "twig_fir",
                           [ao[1], ao[2], ao[3]], nfn, fold=rng.uniform(0.1, 0.3), flip=rng.random() < 0.5)
            # A second, lower spray hanging under the first (fills the crown from below).
            if t < 0.9:
                d2 = (d + side * rng.uniform(-0.25, 0.25)).normalized()
                side2 = Vector((-d2.z, 0, d2.x))
                pts2 = [q - UP * (0.012 + 0.05 * L * (k / 2)) for k, q in enumerate(branch_path(base, d2, L * 0.85, pitch - 0.1, droop * 1.35, segs=2))]
                rect2 = rng.choice(FIR + FIR_SMALL)
                aspect2 = (rect2[2] - rect2[0]) / (rect2[3] - rect2[1])
                hw2 = L * 0.85 * aspect2 * 0.5
                across2 = [side2 * (hw2 * lerp(0.6, 1.0, k / 2)) for k in range(3)]
                ao2 = [(c[0] * 0.8, 0.35, 0.0) for c in (ao[0], ao[2], ao[3])]
                card_strip(B, pts2, across2, rect2, "twig_fir", ao2, nfn, fold=-0.1, flip=rng.random() < 0.5)
            # Snow lying along the upper side of most branches.
            if t < 0.92 and rng.random() < 0.85:
                s_a, s_b = rng.uniform(0.08, 0.2), rng.uniform(0.78, 0.95)
                seg = [base + d * (L * s) + UP * (L * (math.tan(pitch) * s - droop * s * s) + 0.003 + hw * fold_lift * 0.12)
                       for s in (s_a, lerp(s_a, s_b, 0.33), lerp(s_a, s_b, 0.66), s_b)]
                snow_pillow(B, seg, hw * rng.uniform(0.55, 0.8), L * rng.uniform(0.03, 0.05), (1.0, 1.0, 0.0))
    return B.finish()


def spruce_lod(name, tiers=9, spokes=12, suffix="_lod"):
    """Opaque low-detail spruce: drooping star-shaped skirts (upper side snowy, lower side dark
    needles), same silhouette as the card tree."""
    p = SPRUCE[name]
    rng = random.Random(p["seed"] + 100)
    B = Builder(name + suffix, ["bark_fir", "needles_mass"])
    trunk(B, 0.95, p["r0"], 0.003, 4 if tiers < 9 else 5, 1 if tiers < 9 else 2, "bark_fir", flare=1.3, bark_tile=(0.07, 0.065))
    for i in range(tiers):
        t = i / tiers
        y_rim = lerp(p["base_y"] + 0.02, 0.9, t ** 0.9)
        R = (p["lmax"] * (1.0 - t) ** p["narrow"] + 0.03) * 1.02
        tier_h = lerp(0.17, 0.12, t)
        collar = Vector((0, y_rim + tier_h, 0))
        under = Vector((0, y_rim + tier_h * 0.3, 0))
        rot = rng.random() * math.tau
        rim = []
        n = spokes * 2
        for k in range(n):
            a = rot + math.tau * k / n
            tip = k % 2 == 0
            rr = R * (1.0 if tip else 0.7) * rng.uniform(0.9, 1.1)
            dr = (0.045 if tip else 0.0) * (1.0 - t * 0.5) * (p["droop"] / 0.42)
            rim.append(Vector((math.cos(a) * rr, y_rim - dr, math.sin(a) * rr)))
        for k in range(n):
            a2, b2 = rim[k], rim[(k + 1) % n]
            ua, ub = k / n * 4.0, (k + 1) / n * 4.0
            na = (Vector((a2.x, 0.0, a2.z)).normalized() * 0.6 + UP * 0.8).normalized()
            nb = (Vector((b2.x, 0.0, b2.z)).normalized() * 0.6 + UP * 0.8).normalized()
            B.face([collar, b2, a2], [((ua + ub) / 2, 0.0), (ub, R * 3.0), (ua, R * 3.0)],
                   [(0.8, 1.0, 0.0), (1.0, 1.0, 0.0), (1.0, 1.0, 0.0)], "needles_mass", [UP, nb, na])
            B.face([under, a2, b2], [((ua + ub) / 2, 0.0), (ua, R * 3.0), (ub, R * 3.0)],
                   [(0.35, 0.0, 0.0), (0.7, 0.0, 0.0), (0.7, 0.0, 0.0)], "needles_mass",
                   [-UP, (na - UP * 1.2).normalized(), (nb - UP * 1.2).normalized()])
    return B.finish()


# ————— Scots pine —————

def scots_pine(name="scots_pine"):
    rng = random.Random(5)
    B = Builder(name, ["bark_pine", "twig_pine", "snow_lump"])
    nfn = radial_normal(1.2)
    lean = Vector((rng.uniform(-1, 1), 0, rng.uniform(-1, 1))).normalized() * 0.03
    bend = lambda t: lean * (t * t)
    trunk(B, 0.93, 0.016, 0.004, 8, 8, "bark_pine", flare=1.4, bark_tile=(0.06, 0.06),
          col_fn=lambda t: (lerp(0.55, 0.95, t), 0.25, smoothstep(0.45, 0.7, t)), bend=bend)
    rosettes = []
    for lvl in range(10):
        t = lvl / 9
        y = lerp(0.58, 0.93, t)
        cnt = rng.randint(3, 4)
        for b in range(cnt):
            az = rng.random() * math.tau
            d = Vector((math.cos(az), 0, math.sin(az)))
            L = lerp(0.17, 0.06, t) * rng.uniform(0.75, 1.15)
            rise = lerp(0.35, 0.8, t)
            base = Vector((0, y, 0)) + bend((y / 0.93))
            pts = [base + d * (L * s) + UP * (L * (rise * s - 0.25 * s * s)) for s in (0.0, 0.35, 0.7, 1.0)]
            tube(B, pts, [0.006, 0.004, 0.003, 0.0015], 5, "bark_pine", col=(0.6, 0.2, 1.0))
            for s in (0.35, 0.6, 0.8, 1.0):
                rosettes.append((pts[0].lerp(pts[3], s) + UP * (L * (rise * s - 0.25 * s * s) - (pts[0].lerp(pts[3], s) - pts[0]).y), d, t))
    rosettes.append((Vector((0, 0.95, 0)) + bend(1.0), UP, 1.0))
    for c, d, t in rosettes:
        size = rng.uniform(0.075, 0.105)
        for k in range(3):
            a = rng.random() * math.tau
            out = (d * 0.6 + UP * 0.5 + Vector((math.cos(a), 0, math.sin(a))) * 0.6).normalized()
            side = out.cross(UP)
            if side.length < 1e-3:
                side = Vector((1, 0, 0))
            side.normalize()
            pts = [c + out * (size * s) for s in (0.0, 0.5, 1.0)]
            rect = PINE[0]
            aspect = (rect[2] - rect[0]) / (rect[3] - rect[1])
            across = [side * (size * aspect * 0.5)] * 3
            card_strip(B, pts, across, rect, "twig_pine", [(0.55, 1.0, 0.0), (0.85, 1.0, 0.0), (1.0, 1.0, 0.0)], nfn, fold=0.2,
                       flip=rng.random() < 0.5)
        if rng.random() < 0.7:
            seg = [c + d * (size * s) + UP * (0.012) for s in (-0.3, 0.0, 0.3, 0.6)]
            snow_pillow(B, seg, size * 0.45, size * 0.18, (1.0, 1.0, 0.0))
    return B.finish()


def scots_pine_lod(name="scots_pine_lod"):
    rng = random.Random(6)
    B = Builder(name, ["bark_pine", "needles_mass"])
    trunk(B, 0.9, 0.016, 0.005, 5, 3, "bark_pine", flare=1.2, bark_tile=(0.06, 0.06),
          col_fn=lambda t: (0.8, 0.25, 1.0 if t > 0.55 else 0.0))
    # Crown: three flattened, lumpy discs.
    for i, (y, R) in enumerate(((0.7, 0.15), (0.8, 0.13), (0.9, 0.08))):
        n = 10
        rim = [Vector((math.cos(math.tau * k / n) * R * rng.uniform(0.8, 1.15), y + rng.uniform(-0.02, 0.01),
                       math.sin(math.tau * k / n) * R * rng.uniform(0.8, 1.15))) for k in range(n)]
        top = Vector((0, y + 0.06, 0))
        bot = Vector((0, y - 0.03, 0))
        for k in range(n):
            a2, b2 = rim[k], rim[(k + 1) % n]
            B.face([top, b2, a2], [(0.5, 0.5), (b2.x * 3 + 0.5, b2.z * 3 + 0.5), (a2.x * 3 + 0.5, a2.z * 3 + 0.5)],
                   [(0.9, 1.0, 0.0)] * 3, "needles_mass", [UP, (b2 - Vector((0, y, 0))).normalized() * 0.5 + UP, (a2 - Vector((0, y, 0))).normalized() * 0.5 + UP])
            B.face([bot, a2, b2], [(0.5, 0.5), (a2.x * 3 + 0.5, a2.z * 3 + 0.5), (b2.x * 3 + 0.5, b2.z * 3 + 0.5)],
                   [(0.4, 0.0, 0.0)] * 3, "needles_mass", [-UP, -UP, -UP])
    return B.finish()


# ————— birch —————

def birch(name="birch"):
    rng = random.Random(77)
    B = Builder(name, ["bark_birch", "twig_birch"])
    lean = Vector((0.02, 0, -0.015))
    trunk(B, 0.62, 0.016, 0.008, 8, 6, "bark_birch", flare=1.3, bark_tile=(0.06, 0.12),
          bend=lambda t: lean * t * t, col_fn=lambda t: (0.85, 0.15, 0.0))
    tips = []

    def grow(p0, d, L, r, depth):
        pts = [p0 + d * (L * s) + Vector((0, -0.03 * L * s * s * (3 - depth), 0)) for s in (0.0, 0.33, 0.66, 1.0)]
        tube(B, pts, [r, r * 0.8, r * 0.6, r * 0.4], 5 if depth > 1 else 4, "bark_birch", col=(0.9, 0.15, 0.0))
        if depth == 0:
            tips.append((pts[-1], d, L))
            tips.append((pts[2], d, L * 0.7))
            return
        for k in range(3 if depth > 1 else 2):
            s = rng.uniform(0.4, 1.0)
            q = pts[0].lerp(pts[3], s)
            nd = (d + Vector((rng.uniform(-0.8, 0.8), rng.uniform(0.0, 0.5), rng.uniform(-0.8, 0.8)))).normalized()
            grow(q, nd, L * rng.uniform(0.45, 0.65), r * 0.55, depth - 1)

    top = Vector((0, 0.62, 0)) + lean
    for k in range(4):
        a = k * math.tau / 4 + rng.uniform(-0.4, 0.4)
        d = Vector((math.cos(a) * 0.45, 0.85, math.sin(a) * 0.45)).normalized()
        grow(top - Vector((0, rng.uniform(0.0, 0.18), 0)), d, rng.uniform(0.25, 0.38), 0.008, 2)
    grow(top, Vector((0.05, 1, 0.02)).normalized(), 0.36, 0.008, 2)
    nfn = radial_normal(0.8)
    for p, d, L in tips:
        size = L * 1.4
        side = d.cross(UP)
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        for roll in (0.0, 1.2):
            s2 = (side * math.cos(roll) + side.cross(d).normalized() * math.sin(roll)).normalized()
            pts = [p - d * (size * 0.2) + d * (size * s) for s in (0.0, 0.5, 1.0)]
            card_strip(B, pts, [s2 * size * 0.45] * 3, BIRCH[0], "twig_birch", [(0.9, 0.2, 0.0)] * 3, nfn, 0.0, rng.random() < 0.5)
    return B.finish()


# ————— export —————

def export_mesh(obj, name):
    os.makedirs(H.OUT, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(H.OUT, name + ".gltf"), export_format="GLTF_SEPARATE",
        use_selection=True, export_yup=True, export_apply=True, export_normals=True,
        export_tangents=True, export_materials="EXPORT", export_vertex_color="ACTIVE",
        export_cameras=False, export_lights=False, export_animations=False)
    os.makedirs(H.BLEND, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(H.BLEND, name + ".blend"), compress=True)


BUILDERS = {
    "spruce_a": lambda: spruce("spruce_a"), "spruce_b": lambda: spruce("spruce_b"), "fir_c": lambda: spruce("fir_c"),
    "spruce_a_lod": lambda: spruce_lod("spruce_a"), "spruce_b_lod": lambda: spruce_lod("spruce_b"),
    "fir_c_lod": lambda: spruce_lod("fir_c"),
    "spruce_a_lod2": lambda: spruce_lod("spruce_a", 5, 8, "_lod2"), "spruce_b_lod2": lambda: spruce_lod("spruce_b", 5, 8, "_lod2"),
    "scots_pine": scots_pine, "scots_pine_lod": scots_pine_lod, "birch": birch,
}
