"""Sleeper service room, linen store and mail van small goods, rebuilt as soft, textured models
(Godot-space coordinates; see hdlib):

    towel_folded, towel_folded_cream        terry towel folded in three, railway red stripe
    sheet_folded, sheet_folded_ivory        cotton sheet / pillow-case folded flat
    blanket_folded, blanket_folded_grey     thick wool blanket, folded, whipped edge
    pillow                                  feather pillow in a cotton case
    toilet_roll, toilet_roll_tail           tissue roll on a card core (one with a loose sheet)
    laundry_hamper                          wicker hamper, lid ajar, used sheets inside
    mail_sack                               closed canvas mail sack, gathered neck tied with cord
    letters_a, letters_b, letters_c         a bundle of mixed envelopes tied with string
    envelope, envelope_kraft                one envelope (0.16 x 0.1 m) for trays and pigeonholes

Sizes are those the GDScript lays out; it scales each to the space it has. Origins: bottom centre
(folded things, rolls, bundles, hamper), centre (sack, envelope), the front fold faces -Z.
"""
import math
import bmesh
from mathutils import Vector, Matrix
import hdlib
from hdlib import *

A = {}

hdlib.MATS.update({
    "towel_white": dict(tex="towel_white", scale=0.12),
    "towel_cream": dict(tex="towel_cream", scale=0.12),
    "linen_white": dict(tex="linen_white", scale=0.18),
    "linen_ivory": dict(tex="linen_ivory", scale=0.18),
    "tissue": dict(tex="tissue", scale=0.08),
    "wool_green": dict(tex="wool_green", scale=0.22),
    "wool_grey": dict(tex="wool_grey", scale=0.22),
    "wool_red": dict(tex="wool_red", scale=0.12),
    "wicker": dict(tex="wicker", scale=0.25),
    "stripe_red": dict(color=(0.42, 0.06, 0.05), rough=0.9),
    "card_core": dict(tex="kraft", scale=0.15),
    "water_murky": dict(color=(0.08, 0.085, 0.07), rough=0.55),
    "mop_cotton": dict(color=(0.24, 0.22, 0.18), rough=0.95),
})


def asset(fn):
    A[fn.__name__] = fn
    return fn


def _rng():
    return hdlib._rng


# ————— soft folded textiles —————

def folded(name, w, t, d, key, layers=3, sag=0.002, wobble=0.004, nx=24, nz=16):
    """A folded textile lying flat: w (x) by d (z), t thick. The front (-Z) is the rounded fold of
    the top layer over the ones below (`layers` lips show there); the back edge shows the cut
    edges, a little ragged. The top sags and the outline wavers, as cloth does."""
    rng = _rng()
    bm = bmesh.new()
    # Cross-section in (z, y), front fold first, going round: a stadium whose front is a
    # semicircle of radius t/2 and whose back is slightly rounded.
    r = t * 0.5
    prof = []
    for i in range(9):                                 # front fold, bottom -> front -> top
        a = math.radians(270 - 180 * i / 8)
        prof.append((-d / 2 + r + math.cos(a) * r, r + math.sin(a) * r))
    rb = t * 0.25
    for i in range(4):                                 # back, top corner
        a = math.radians(90 - 90 * i / 3)
        prof.append((d / 2 - rb + math.cos(a) * rb, t - rb + math.sin(a) * rb))
    for i in range(4):                                 # back, bottom corner
        a = math.radians(0 - 90 * i / 3)
        prof.append((d / 2 - rb + math.cos(a) * rb, rb + math.sin(a) * rb))
    rows = []
    for ix in range(nx + 1):
        u = ix / nx
        x = -w / 2 + w * u
        ring = []
        wob = math.sin(u * 6.3 + rng.random() * 6) * wobble * 0.5 + (rng.random() - 0.5) * wobble * 0.3
        for (z, y) in prof:
            zz = z + (wob if z < 0 else wob * 0.6)
            yy = y
            if y > t * 0.6:                                # top surface sags between the folds
                yy -= sag * math.sin(u * math.pi) * (0.6 + 0.4 * math.cos((z / d) * math.pi))
            ring.append(bm.verts.new(G(x, yy, zz)))
        rows.append(ring)
    n = len(prof)
    for ix in range(nx):
        for k in range(n - 1):
            bm.faces.new((rows[ix][k], rows[ix + 1][k], rows[ix + 1][k + 1], rows[ix][k + 1]))
        bm.faces.new((rows[ix][n - 1], rows[ix + 1][n - 1], rows[ix + 1][0], rows[ix][0]))
    # End caps (the folded sides, x = ±w/2): fans.
    for ix, flip in ((0, True), (nx, False)):
        c = bm.verts.new(G(-w / 2 if ix == 0 else w / 2, t * 0.5, 0.0))
        ring = rows[ix]
        for k in range(n):
            tri = (ring[k], ring[(k + 1) % n], c)
            bm.faces.new(tri[::-1] if flip else tri)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, key, "x", rng)
    return hdlib._new_obj(name, bm, key, 0.0, smooth=True, angle=60.0)


def layer_lines(w, t, d, key, layers):
    """The edges of the layers under the top fold, seen on the front: thin rounded lips."""
    for k in range(1, layers):
        y = t * k / layers
        cyl("Lip", t * 0.22, w * 0.985, (0, y, -d / 2 + t * 0.32), key, axis=(1, 0, 0), segs=10)


def stack_wrap(key, w, t, d, layers=3, stripe=None):
    folded("Fold", w, t, d, key, layers)
    layer_lines(w, t, d, key, layers)
    if stripe:
        # Woven stripe across the towel near one end, standing a hair proud.
        x = w * 0.28
        folded("Stripe", 0.022, t + 0.0015, d + 0.0015, stripe, layers, wobble=0.0, nx=2)
        move_last(1, (x, -0.00075, 0))
        folded("Stripe", 0.008, t + 0.0016, d + 0.0016, stripe, layers, wobble=0.0, nx=2)
        move_last(1, (x + 0.022, -0.0008, 0))


@asset
def towel_folded():
    seed(51)
    stack_wrap("towel_white", 0.24, 0.032, 0.2, 3, "stripe_red")


@asset
def towel_folded_cream():
    seed(52)
    stack_wrap("towel_cream", 0.24, 0.032, 0.2, 3, "stripe_red")


@asset
def sheet_folded():
    seed(53)
    stack_wrap("linen_white", 0.28, 0.026, 0.3, 4)


@asset
def sheet_folded_ivory():
    seed(54)
    stack_wrap("linen_ivory", 0.28, 0.026, 0.3, 4)


def blanket(key, seedk):
    seed(seedk)
    w, t, d = 0.3, 0.05, 0.32
    folded("Fold", w, t, d, key, 3, sag=0.004, wobble=0.006)
    layer_lines(w, t, d, key, 3)
    # Blanket-stitched edge: a darker cord along the visible cut edge at the back-top.
    tube("Whip", [(-w / 2 + 0.01, t - 0.004, d / 2 - 0.004), (w / 2 - 0.01, t - 0.004, d / 2 - 0.004)], 0.003, "wool_red", 6)


@asset
def blanket_folded():
    blanket("wool_green", 55)


@asset
def blanket_folded_grey():
    blanket("wool_grey", 56)


@asset
def pillow():
    """Feather pillow, 0.36 x 0.26 m, plump in the middle, corners pinched, a seam round the edge."""
    seed(57)
    rng = _rng()
    w, h, d = 0.36, 0.11, 0.26
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=1.0)
    for v in bm.verts:
        bx, by, bz = v.co.x, v.co.y, v.co.z          # blender (x, y, z): godot x = bx, y = bz, z = -by
        gx, gy, gz = bx, bz, -by
        # Square the outline (circle -> superellipse in x/z), thin toward the edges, plump middle.
        rxz = math.hypot(gx, gz)
        if rxz > 1e-6:
            cx, cz = gx / rxz, gz / rxz
            sq = (abs(cx) ** 4 + abs(cz) ** 4) ** 0.25
            f = 1.0 + (1.0 / sq - 1.0) * 0.9
            gx *= f
            gz *= f
        gy *= (1.0 - min(1.0, rxz) ** 4) ** 0.45 * 0.9 + 0.1
        gy *= 1.0 + 0.05 * math.sin(gx * 9 + rng.random()) * math.sin(gz * 7)
        v.co = G(gx * w / 2, gy * h / 2 + h / 2, gz * d / 2)
    bm.normal_update()
    hdlib._box_uv(bm, "linen_white", "x", rng)
    hdlib._new_obj("Pillow", bm, "linen_white", 0.0, smooth=True, angle=70.0)
    # Piped seam round the middle.
    pts = []
    for i in range(65):
        a = math.tau * i / 64
        cx, cz = math.cos(a), math.sin(a)
        sq = (abs(cx) ** 4 + abs(cz) ** 4) ** 0.25
        f = 1.0 + (1.0 / sq - 1.0) * 0.9
        pts.append((cx * f * w / 2 * 1.0, h / 2, cz * f * d / 2 * 1.0))
    tube("Seam", pts, 0.0035, "linen_ivory", 6, caps=False)


# ————— toilet rolls —————

def roll(with_tail):
    r, ri, h = 0.052, 0.02, 0.1
    rng = _rng()
    # Paper: the outside slightly uneven, the ends showing the wound layers (rings in the texture)
    # and dished a touch; the card core inside.
    prof = [(ri + 0.001, 0.002), (r * 0.7, 0.0), (r - 0.002, 0.001), (r, 0.004), (r + 0.0006, h * 0.5),
            (r, h - 0.004), (r - 0.002, h - 0.001), (r * 0.7, h), (ri + 0.001, h - 0.002)]
    o = lathe("Paper", prof, (0, 0, 0), "tissue", segs=40, cap_bottom=False, cap_top=False)
    for v in o.data.vertices:
        v.co.x += (rng.random() - 0.5) * 0.0006
        v.co.y += (rng.random() - 0.5) * 0.0006
    lathe("Core", [(ri + 0.0012, 0.0015), (ri, 0.0015), (ri, h - 0.0015), (ri + 0.0012, h - 0.0015)], (0, 0, 0), "card_core",
          segs=24, cap_bottom=False, cap_top=False)
    # Perforation lines: faint grooves round the roll every 0.11 m of paper are invisible at this
    # size; the loose end of the paper is a thin step on the surface instead.
    a0 = rng.random() * math.tau
    box("SheetEdge", (0.004, h - 0.006, 0.0012), (math.cos(a0) * (r + 0.0004), h / 2, math.sin(a0) * (r + 0.0004)), "tissue", 0.0004,
        rot=(0, -a0 + math.pi / 2, 0))
    if with_tail:
        # A sheet hanging off the front, curling down.
        pts = [(0.0, 0.0, -r), (0.0, -0.02, -r - 0.004), (0.0, -0.05, -r - 0.012), (0.0, -0.075, -r - 0.022)]
        for k, p in enumerate(pts[:-1]):
            q = pts[k + 1]
            mid = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2 + h / 2, (p[2] + q[2]) / 2)
            ang = math.atan2(q[2] - p[2], -(q[1] - p[1]))
            box("Tail", (h - 0.008, math.dist(p, q) + 0.002, 0.0008), mid, "tissue", 0.0003, rot=(ang, 0, 0))


@asset
def toilet_roll():
    seed(58)
    roll(False)


def crumple(name, center, radii, key, amp=0.25, waves=7, seedk=0, segs=28, rings=16):
    """A soft heap of cloth: a squashed sphere pushed in and out by random folds (sums of ridged
    sines along random directions), so it reads as crumpled fabric rather than a ball."""
    rng = _rng()
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    dirs = [(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized(),
             rng.uniform(5, 11), rng.uniform(0, 6.3), rng.uniform(0.5, 1.0)) for _ in range(waves)]
    for v in bm.verts:
        n = v.co.normalized()
        d = 0.0
        for dv, fr, ph, a in dirs:
            d += a * (1.0 - abs(math.sin(n.dot(dv) * fr + ph))) / waves
        r = 1.0 + amp * (d * 2.0 - 0.6)
        if n.z < -0.3:                                    # flat underside where it rests
            r *= 0.85
        p = n * r
        v.co = G(center[0] + p.x * radii[0], center[1] + p.z * radii[1], center[2] + p.y * radii[2])
    bm.normal_update()
    hdlib._box_uv(bm, key, "x", rng)
    return hdlib._new_obj(name, bm, key, 0.0, smooth=True, angle=80.0)


def drape(name, path, width, key, thick=0.003, nu=6, wav=0.006):
    """A strip of cloth following `path` (list of Godot-space points), `width` wide across the
    horizontal normal of the path, slightly wavy across, given a little thickness."""
    rng = _rng()
    bm = bmesh.new()
    pts = [Vector(q) for q in path]
    rows = []
    for i, q in enumerate(pts):
        tng = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = tng.cross(Vector((0, 1, 0)))
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(tng).normalized()
        row = []
        for j in range(nu + 1):
            u = j / nu - 0.5
            off = math.sin(u * 9 + i * 1.7 + rng.random()) * wav
            g = q + side * (u * width * (1.0 + 0.15 * i / len(pts))) + up * off
            row.append(bm.verts.new(G(g.x, g.y, g.z)))
        rows.append(row)
    for i in range(len(rows) - 1):
        for j in range(nu):
            bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thick)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, key, "x", rng)
    return hdlib._new_obj(name, bm, key, 0.0, smooth=True, angle=70.0)


# ————— laundry hamper —————

@asset
def laundry_hamper():
    """Wicker laundry hamper (Ø0.4 m, 0.58 m), slightly tapered, bound rims, lid lifted and propped
    on the back, a used sheet bundled at the mouth. Origin: floor at its centre."""
    seed(60)
    rng = _rng()
    rb, rt, hgt = 0.17, 0.2, 0.56
    o = lathe("Basket", [(0.0, 0.0), (rb - 0.01, 0.0), (rb, 0.012), (rt, hgt), (rt - 0.012, hgt), (rb - 0.012, 0.02), (0.0, 0.02)],
              (0, 0, 0), "wicker", segs=56, cap_bottom=False, cap_top=False)
    for v in o.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        if 0.03 < g.y < hgt - 0.03:
            f = 1.0 + 0.012 * math.sin(math.atan2(g.z, g.x) * 3 + g.y * 9)
            v.co.x *= f
            v.co.y *= f
    for y, rr in ((0.012, rb + 0.004), (hgt * 0.5, (rb + rt) / 2 + 0.004), (hgt - 0.008, rt + 0.006)):
        torus("Rim", rr, 0.009 if y > 0.1 else 0.007, (0, y, 0), "wicker", segs=56, rsegs=10)
    for s in (-1, 1):
        torus("Handle", 0.035, 0.007, (s * (rt + 0.008), hgt - 0.06, 0), "wicker", axis=(1, 0, 0), segs=24, rsegs=8, arc=math.pi)
    # Lid: dished disc with a rim, hinged at the back (+Z), propped open ~70 degrees.
    # Lid: dished disc with a rim, built with its hinge (back edge) at the origin, then swung
    # up about the hinge and set on the basket's back rim.
    lid_parts = count()
    lathe("Lid", [(0.0, 0.025), (rt * 0.6, 0.02), (rt + 0.01, 0.0), (rt + 0.01, -0.012), (rt - 0.004, -0.012), (rt * 0.6, 0.008), (0.0, 0.012)],
          (0, 0, -rt), "wicker", segs=56, cap_bottom=False, cap_top=False)
    torus("LidRim", rt + 0.012, 0.008, (0, -0.004, -rt), "wicker", segs=56, rsegs=8)
    sphere("LidKnob", 0.018, (0, 0.03, -rt), "wicker", scale=(1, 0.6, 1))
    transform_since(lid_parts, (0, hgt + 0.004, rt), (math.radians(68), 0, 0))
    # Used linen heaped in the mouth, one corner of a sheet hanging out over the front rim.
    crumple("Linen", (0.0, hgt - 0.03, -0.02), (rt - 0.025, 0.09, rt - 0.03), "linen_ivory", 0.35, 8)
    crumple("Towel", (0.07, hgt + 0.03, -0.06), (0.09, 0.045, 0.08), "towel_white", 0.3, 6)
    a = math.radians(-25)
    def rim(r, y):
        return (math.sin(a) * r, y, -math.cos(a) * r)
    drape("SheetCorner", [rim(rt - 0.06, hgt + 0.02), rim(rt - 0.01, hgt + 0.035), rim(rt + 0.02, hgt + 0.02),
                          rim(rt + 0.03, hgt - 0.04), rim(rt + 0.025, hgt - 0.12), rim(rt + 0.02, hgt - 0.17)],
          0.16, "linen_ivory", 0.003, 6, 0.008)

# ————— mail —————

@asset
def mail_sack():
    """Closed canvas mail sack lying on its side, about 0.66 x 0.3 x 0.42 m: a sack (lathed along X,
    a round seamed bottom, a full body, the canvas drawn in to a gathered neck tied with cord and
    a lead seal), slumped flat where it lies, lumpy with parcels, creased toward the neck."""
    seed(61)
    rng = _rng()
    L = 0.56
    prof = [(0.0, -L / 2), (0.1, -L / 2 + 0.004), (0.165, -L / 2 + 0.03), (0.19, -L / 2 + 0.09), (0.2, -0.1), (0.198, 0.05),
            (0.185, 0.14), (0.15, 0.2), (0.1, 0.24), (0.06, L / 2 - 0.01), (0.045, L / 2)]
    o = lathe("Sack", prof, (0, 0, 0), "canvas", axis=(1, 0, 0), segs=56, smooth_angle=70.0, cap_top=False)
    bumps = [(Vector((rng.uniform(-0.2, 0.15), rng.uniform(-0.1, 0.12), rng.uniform(-0.18, 0.18))), rng.uniform(0.015, 0.03), rng.uniform(0.07, 0.12)) for _ in range(7)]
    for v in o.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))                 # godot frame
        # Slump: flatten the underside on the floor and squash the height.
        g.y *= 0.72
        if g.y < -0.1:
            g.y = -0.1 - (g.y + 0.1) * 0.2
            g.z *= 1.08
        # Parcels pushing the canvas out.
        for c, amp, rad in bumps:
            dd = (g - c).length
            if dd < rad * 2:
                n = Vector((0, g.y, g.z)).normalized() if abs(g.y) + abs(g.z) > 1e-4 else Vector((0, 1, 0))
                g += n * amp * math.exp(-(dd / rad) ** 2)
        # Creases radiating into the neck.
        ang = math.atan2(g.z, g.y)
        k = max(0.0, (g.x - 0.05) / 0.25)
        r = math.hypot(g.y, g.z)
        r *= 1.0 + 0.06 * k * math.sin(ang * 11 + g.x * 20)
        if r > 1e-4:
            g.y, g.z = math.cos(ang) * r, math.sin(ang) * r
        v.co = G(g.x, g.y + 0.1, g.z)
    # Gathered neck: bunched canvas, the cord wound round it, the ear sticking out past it.
    nx = L / 2 - 0.005
    lathe("Neck", [(0.042, 0.0), (0.034, 0.015), (0.03, 0.035), (0.038, 0.05), (0.055, 0.075), (0.05, 0.088), (0.025, 0.095)],
          (nx, 0.1, 0.0), "canvas", axis=(1, 0, 0), segs=24)
    for k in range(3):
        torus("Cord", 0.033 - k * 0.0015, 0.0035, (nx + 0.016 + k * 0.007, 0.1, 0.0), "string", axis=(1, 0, 0), segs=24, rsegs=6)
    tube("CordEnd", [(nx + 0.026, 0.07, 0.0), (nx + 0.03, 0.03, 0.02), (nx + 0.04, 0.0, 0.03)], 0.0025, "string", 6, bend=0.01)
    lathe("Seal", [(0.0, -0.004), (0.013, -0.004), (0.014, 0.0), (0.013, 0.004), (0.0, 0.004)], (nx + 0.042, -0.004, 0.034), "steel_dark",
          axis=(0, 0, 1), segs=16)
    # Bottom seam across the round end.
    tube("Seam", [(-L / 2 + 0.02, 0.1 + 0.13, 0.0), (-L / 2 + 0.003, 0.1, 0.0), (-L / 2 + 0.02, 0.1 - 0.095, 0.0)], 0.004, "canvas_dark", 6, bend=0.06)
    transform_since(0, (0, -0.1, 0))


def bundle(seedk, n):
    seed(seedk)
    rng = _rng()
    y = 0.0
    keys = ["paper", "paper_aged", "kraft", "paper", "paper_aged"]
    for k in range(n):
        w = rng.uniform(0.142, 0.156)
        d = rng.uniform(0.088, 0.097)
        t = rng.uniform(0.0018, 0.0032)
        key = keys[rng.randrange(len(keys))]
        box("Envelope", (w, t, d), (rng.uniform(-0.004, 0.004), y + t / 2, rng.uniform(-0.003, 0.003)), key, 0.0005,
            rot=(0, rng.uniform(-0.05, 0.05), 0))
        # Flap edge on the top face of every few.
        if k % 2 == 0:
            box("Flap", (w * 0.96, 0.0003, 0.002), (0, y + t + 0.00015, -d * 0.12), key, 0.0)
        y += t
    # String, twice round each way, knotted on top.
    hw, hd = 0.0785, 0.0495
    for x in (0.02, 0.026):
        pts = [(x, -0.0005, -hd), (x, y + 0.0012, -hd), (x, y + 0.0012, hd), (x, -0.0005, hd)]
        tube("String", pts + [pts[0]], 0.0011, "string", 5, bend=0.002, caps=False)
    pts = [(-hw, -0.0005, 0.0), (-hw, y + 0.0012, 0.0), (hw, y + 0.0012, 0.0), (hw, -0.0005, 0.0)]
    tube("String", pts + [pts[0]], 0.0011, "string", 5, bend=0.002, caps=False)
    sphere("Knot", 0.0045, (0.023, y + 0.002, 0.0), "string", scale=(1.2, 0.7, 1.0))
    tube("Loop", [(0.023, y + 0.003, 0.0), (0.035, y + 0.004, -0.012), (0.04, y + 0.002, -0.022)], 0.001, "string", 5, bend=0.004)


@asset
def letters_a():
    bundle(62, 9)


@asset
def letters_b():
    bundle(63, 14)


@asset
def letters_c():
    bundle(64, 20)


def single_envelope(key):
    """0.16 x 0.1 m envelope standing in the XY plane (face toward -Z): body, back flap outline,
    a stamp corner and an address block of faint lines on the front."""
    w, h, t = 0.16, 0.1, 0.0018
    box("Body", (w, h, t), (0, 0, 0), key, 0.0004)
    # Back flap (on +Z): a shallow V.
    for s in (-1, 1):
        box("FlapEdge", (w * 0.56, 0.0012, 0.0004), (s * w * 0.24, h * 0.18, t / 2 + 0.0002), key, 0.0, rot=(0, 0, s * -0.42))
    box("Stamp", (0.022, 0.026, 0.0004), (w / 2 - 0.018, h / 2 - 0.02, -t / 2 - 0.0002), "paint_red", 0.0)
    for k in range(3):
        box("Line", (0.06 - k * 0.008, 0.0016, 0.0003), (-0.005, -0.006 - k * 0.011, -t / 2 - 0.00015), "ink", 0.0)


@asset
def envelope():
    seed(65)
    single_envelope("paper")


@asset
def envelope_kraft():
    seed(66)
    single_envelope("kraft")


VIEWS = {"mop_bucket": (0.8, 0.6, -1.0), "mail_sack": (-0.6, 0.6, -1.0), "envelope": (-0.3, 0.2, -1.0), "envelope_kraft": (-0.3, 0.2, -1.0)}


# ————— compartment sliding door —————

def _door_face(zf, s, x0, x1, key):
    """Stiles, rails and two raised panels on the door face at z = zf, facing s (-1 corridor, +1 room)."""
    st, top_r, mid0, mid1, bot = 0.105, 0.105, 0.94, 1.09, 0.22
    h = 1.91
    w = x1 - x0
    xc = (x0 + x1) / 2
    dz = 0.008                                           # frame stands proud of the core
    for xs in (x0 + st / 2, x1 - st / 2):
        box("Stile", (st, h - 0.01, dz), (xs, 0.005 + (h - 0.01) / 2, zf + s * dz / 2), key, 0.002, grain="y")
    for (y0, y1) in ((h - top_r, h), (mid0, mid1), (0.005, bot)):
        box("Rail", (w - 2 * st, y1 - y0, dz), (xc, (y0 + y1) / 2, zf + s * dz / 2), key, 0.002)
    for (y0, y1) in ((mid1, h - top_r), (bot, mid0)):
        pw, ph = w - 2 * st, y1 - y0
        # Bevelled raised field with a flat border, and a bolection moulding round it.
        box("PanelBorder", (pw, ph, 0.004), (xc, (y0 + y1) / 2, zf + s * 0.002), key, 0.001, grain="y")
        box("PanelField", (pw - 0.07, ph - 0.07, 0.012), (xc, (y0 + y1) / 2, zf + s * 0.006), key, 0.005, segs=2, grain="y")
        for (cx, cy, sw, sh) in ((xc, y1 - 0.006, pw, 0.012), (xc, y0 + 0.006, pw, 0.012),
                                 (x0 + st + 0.006, (y0 + y1) / 2, 0.012, ph), (x1 - st - 0.006, (y0 + y1) / 2, 0.012, ph)):
            box("Moulding", (sw, sh, 0.006), (cx, cy, zf + s * (dz + 0.002)), key, 0.003, segs=2, grain="y" if sh > sw else "x")


def _flush_pull(x, y, zf, s):
    """Brass flush pull let into the door face: oval plate, recessed cup, finger bar."""
    lathe("PullPlate", [(0.0, 0.0), (0.024, 0.0), (0.026, 0.0015), (0.024, 0.003), (0.0, 0.003)], (x, y, zf), "brass",
          axis=(0, 0, s), segs=32)
    o = hdlib._parts[-1]
    # Stretch the round plate into a tall oval about its centre.
    c = G(x, y, zf)
    for v in o.data.vertices:
        d = v.co - c
        v.co = c + Vector((d.x * 0.75, d.y, d.z * 3.2))
    box("PullCup", (0.026, 0.12, 0.004), (x, y, zf + s * 0.0035), "bakelite", 0.002)
    box("PullBar", (0.006, 0.09, 0.008), (x - 0.004, y, zf + s * 0.004), "brass", 0.002)
    for dy in (-0.062, 0.062):
        screw("PullScrew", x, y + dy, zf + s * 0.003, axis=(0, 0, s))


def screw(name, x, y, z, r=0.0025, axis=(0, 0, -1), key="brass"):
    lathe(name, [(0, 0), (r, 0), (r * 0.95, r * 0.35), (r * 0.6, r * 0.6), (0, r * 0.65)], (x, y, z), key, axis=axis, segs=12)


@asset
def door_compartment():
    """Walnut sliding door of a sleeping compartment, in the frame of the old Tripo door scene:
    leaf x -0.634..0.138, y 0..1.915, faces at z = ±0.0424 (corridor -Z, room +Z); it slides
    toward +X, so both flush pulls sit by the closing edge (-X); a turn-lock knob on the room
    face, a keyhole escutcheon on the corridor face. The overhead track (x ±0.676, above the
    leaf) and the two hangers are part of it (the game splits the track off as a static part)."""
    seed(70)
    x0, x1, zf, key = -0.634, 0.138, 0.0344, "wood_darkstain"
    xc = (x0 + x1) / 2
    core = box("Core", (x1 - x0, 1.91, zf * 2), (xc, 0.005 + 0.955, 0.0), key, 0.003, grain="y")
    # Rows of vertices up the edges (the game measures the leaf from its vertices at mid height).
    bm = bmesh.new()
    bm.from_mesh(core.data)
    tall = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1.0]
    bmesh.ops.subdivide_edges(bm, edges=tall, cuts=12, use_grid_fill=True)
    bm.to_mesh(core.data)
    bm.free()
    for s in (-1, 1):
        _door_face(s * zf, s, x0, x1, key)
        _flush_pull(x0 + 0.072, 0.9, s * (zf + 0.008), s)
    # Room side: turn-lock knob on a round rose. Corridor side: keyhole escutcheon.
    lathe("LockRose", [(0.0, 0.0), (0.02, 0.0), (0.021, 0.002), (0.018, 0.004), (0.0, 0.004)], (x0 + 0.072, 1.025, zf + 0.008), "brass",
          axis=(0, 0, 1), segs=32)
    lathe("LockKnob", [(0.0, 0.0), (0.008, 0.0), (0.006, 0.01), (0.012, 0.016), (0.011, 0.022), (0.0, 0.024)],
          (x0 + 0.072, 1.025, zf + 0.012), "brass", axis=(0, 0, 1), segs=24)
    lathe("Escutcheon", [(0.0, 0.0), (0.016, 0.0), (0.017, 0.002), (0.0, 0.003)], (x0 + 0.072, 1.025, -zf - 0.008), "brass",
          axis=(0, 0, -1), segs=28)
    box("Keyhole", (0.004, 0.012, 0.002), (x0 + 0.072, 1.023, -zf - 0.0112), "bakelite", 0.0)
    # Overhead track: a brass-capped walnut pelmet carrying a steel channel, and the hangers.
    box("TrackChannel", (1.352, 0.03, 0.05), (0.0, 1.94, 0.0), "steel_dark", 0.003)
    box("Pelmet", (1.352, 0.07, 0.016), (0.0, 1.96, -0.034), key, 0.003)
    box("PelmetCap", (1.36, 0.01, 0.07), (0.0, 1.998, 0.0), "brass", 0.002)
    for hx in (x0 + 0.1, x1 - 0.1):
        box("Hanger", (0.04, 0.03, 0.012), (hx, 1.912, -0.02), "steel_dark", 0.002)
        cyl("HangerWheel", 0.012, 0.01, (hx, 1.93, 0.0), "steel_dark", axis=(0, 0, 1), segs=16)
    # Foot guide on the floor under the leaf (kept with the leaf).
    box("Shoe", (0.05, 0.012, 0.03), (x1 - 0.06, 0.006, 0.0), "brass", 0.002)


VIEWS["door_compartment"] = (0.6, 0.3, -1.0)

@asset
def mop_bucket():
    """Galvanised mop bucket (Ø0.33 m, 0.3 m) with rolled rim, ribs and wire bail, murky water,
    and a cotton string mop standing in it, its handle leaning on the wall behind (+Z).
    Origin: floor at the bucket's centre; the wall is at z = +0.2."""
    seed(67)
    rng = _rng()
    lathe("Bucket", [(0, 0), (0.125, 0), (0.13, 0.008), (0.158, 0.29), (0.166, 0.3), (0.158, 0.302), (0.15, 0.295),
                     (0.122, 0.014), (0, 0.014)], (0, 0, 0), "galvanized", segs=64, cap_top=False)
    for y in (0.06, 0.15, 0.24):
        torus("Rib", 0.131 + y * 0.095, 0.003, (0, y, 0), "galvanized", segs=64, rsegs=6)
    cyl("Water", 0.149, 0.012, (0, 0.23, 0), "water_murky", segs=48, bevel=0.0)
    tube("Bail", [(-0.163, 0.25, 0), (-0.15, 0.36, -0.08), (0.0, 0.4, -0.12), (0.15, 0.36, -0.08), (0.163, 0.25, 0)],
         0.0035, "steel_dark", 8, bend=0.06)
    for sx in (-1, 1):
        sphere("Ear", 0.013, (sx * 0.162, 0.25, 0), "galvanized", (0.5, 1, 1), 12, 6)
    # The mop: turned handle to the wall, a ferrule and a head of cotton strands in the water.
    foot = Vector((0.02, 0.2, 0.03))
    tip = Vector((0.05, 1.45, 0.17))
    tube("Handle", [tuple(foot), tuple(tip)], 0.013, "wood_dark", 12)
    sphere("HandleEnd", 0.015, tuple(tip + (tip - foot).normalized() * 0.004), "wood_dark", segs=12, rings=6)
    cyl("Ferrule", 0.018, 0.05, tuple(foot + Vector((0, 0.02, 0))), "galvanized", segs=16)
    # Mop head: a sodden mass of cotton in the water, strands twisting up to the ferrule.
    crumple("MopHead", (0.0, 0.17, 0.0), (0.12, 0.09, 0.12), "mop_cotton", 0.45, 9, segs=24, rings=12)
    for k in range(18):
        a = k / 18 * math.tau + rng.random() * 0.3
        over = False
        if over:
            pts = [tuple(foot), (math.cos(a) * 0.1, 0.27, math.sin(a) * 0.1),
                   (math.cos(a) * 0.165, 0.31, math.sin(a) * 0.165), (math.cos(a) * 0.178, 0.24, math.sin(a) * 0.178),
                   (math.cos(a) * 0.176, 0.17, math.sin(a) * 0.176)]
        else:
            rr = 0.05 + rng.random() * 0.05
            pts = [tuple(foot + Vector((0, 0.01, 0))),
                   (foot.x + math.cos(a) * rr * 0.5, 0.23, foot.z + math.sin(a) * rr * 0.5),
                   (math.cos(a) * rr, 0.2 + rng.random() * 0.02, math.sin(a) * rr)]
        tube("Strand", pts, 0.009, "mop_cotton", 6, bend=0.012)
