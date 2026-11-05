# make_stations.py — station buildings and the train shed (Blender 5.x), after the user's references:
#   (1) a big town station: an arched iron-and-glass train shed over the track and platform on
#       cast-iron columns, an iron arcade along the platform, lanterns hanging from the trusses,
#       fan-glazed screens at the ends;
#   (2) a country station in rubble stone (Ellicott's Mills type): a broad roof whose platform side
#       runs on as a long canopy on timber posts with curved brackets, half-timbered gables with
#       diagonal boarding, a louvred ventilator turret with a little dome, a brick chimney, a name
#       board under the gable, a boarded annexe and an iron railing along the open shelter.
#   blender --background --factory-startup --python tools/blender/make_stations.py -- <out_dir>
# Writes station_house, halt_house, shed_bay, shed_end and, for the station yards, island_canopy,
# goods_shed, boxcar, buffer_stop and station_fence (.glb).
#
# Built in Godot's frame (helper G): x along the track, y up, z across; buildings face the platform
# with their -Z side, origin on the ground at the middle of the main block. The shed's frame is the
# station's (track at z = 0, platform toward +z). Material names are Buildings.mat() keys
# (stone, wall, wood, wood_green, roof, roof_dark, iron, glass_lit, glass_dark, enamel, lamp, brick);
# the game swaps in its own snow-aware materials by name, so no UVs are needed.
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1]
MATS = ["stone", "wall", "wood", "wood_green", "roof", "roof_dark", "iron", "glass_lit", "glass_dark",
        "enamel", "lamp", "brick", "glass_clear"]
PREVIEW = {   # only for previews in Blender / other viewers; the game replaces them
    "stone": (0.42, 0.4, 0.37), "wall": (0.85, 0.8, 0.68), "wood": (0.3, 0.2, 0.12),
    "wood_green": (0.12, 0.22, 0.15), "roof": (0.35, 0.16, 0.1), "roof_dark": (0.15, 0.15, 0.17),
    "iron": (0.05, 0.06, 0.055), "glass_lit": (1.0, 0.6, 0.25), "glass_dark": (0.03, 0.035, 0.045),
    "enamel": (0.9, 0.9, 0.86), "lamp": (1.0, 0.85, 0.6), "brick": (0.4, 0.15, 0.1),
    "glass_clear": (0.6, 0.7, 0.75),
}


def G(x, y, z):
    """Godot frame -> Blender (glTF export turns Blender +Y into Godot -Z)."""
    return Vector((x, -z, y))


class Mesh:
    def __init__(self):
        self.bm = bmesh.new()

    def face(self, pts, m):
        vs = [self.bm.verts.new(G(*p)) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = MATS.index(m)
        return f

    def box(self, c, size, m, rot_y=0.0):
        """Axis box (Godot frame), optionally turned about the vertical."""
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        R = Matrix.Rotation(rot_y, 3, "Y")
        cs = []
        for i in range(8):
            p = Vector((hx * (1 if i & 1 else -1), hy * (1 if i & 2 else -1), hz * (1 if i & 4 else -1)))
            cs.append(Vector(c) + R @ p)
        for f in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]:
            self.face([tuple(cs[i]) for i in f], m)

    def beam(self, a, b, w, h, m, up=(0, 1, 0)):
        """Rectangular member from a to b (Godot frame), w across, h along `up`."""
        a, b = Vector(a), Vector(b)
        d = (b - a).normalized()
        u = Vector(up)
        s = d.cross(u)
        if s.length < 1e-4:
            s = d.cross(Vector((1, 0, 0)))
        s.normalize()
        u = s.cross(d).normalized()
        cs = []
        for p in (a, b):
            for (i, j) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                cs.append(p + s * (w / 2 * i) + u * (h / 2 * j))
        for f in [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (0, 3, 2, 1), (4, 5, 6, 7)]:
            self.face([tuple(cs[i]) for i in f], m)

    def lathe(self, prof, segs, m, base=(0, 0, 0), flutes=0):
        """Revolve (radius, y) about the vertical through `base` (Godot frame)."""
        rings = []
        for (r, y) in prof:
            ring = []
            for k in range(segs):
                a = 2 * math.pi * k / segs
                rr = r * (1.0 - 0.06 * (k % 2) if flutes and 0.6 < y < prof[-1][1] - 0.6 else 1.0)
                ring.append(self.bm.verts.new(G(base[0] + rr * math.cos(a), base[1] + y, base[2] + rr * math.sin(a))))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for k in range(segs):
                f = self.bm.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][(k + 1) % segs], rings[i][(k + 1) % segs]))
                f.material_index = MATS.index(m)
        top = self.bm.faces.new(rings[-1])
        top.material_index = MATS.index(m)

    def sweep(self, pts, w, h, m, up=(1, 0, 0)):
        """A member along a polyline (each segment a beam; joints overlap slightly)."""
        for i in range(len(pts) - 1):
            a, b = Vector(pts[i]), Vector(pts[i + 1])
            d = (b - a).normalized()
            self.beam(a - d * 0.01, b + d * 0.01, w, h, m, up)

    def obj(self, name, parent):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for k in MATS:
            me.materials.append(material(k))
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        o.parent = parent
        return o


_mat_cache = {}


def material(k):
    if k not in _mat_cache:
        m = bpy.data.materials.new(k)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*PREVIEW[k], 1.0)
        b.inputs["Roughness"].default_value = 0.8
        b.inputs["Metallic"].default_value = 1.0 if k == "iron" else 0.0
        if k in ("glass_lit", "lamp"):
            b.inputs["Emission Color"].default_value = (*PREVIEW[k], 1.0)
            b.inputs["Emission Strength"].default_value = 2.0
        _mat_cache[k] = m
    return _mat_cache[k]


def root(name):
    r = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(r)
    return r


# ————— country station (reference 2) —————

def window(M, x, y0, z, w, h, face, lit, frame="wood_green", glass=None):
    """A window on a wall plane z (face -1: wall faces -z, +1: faces +z; or 'x' walls via face=±2)."""
    o = 0.04
    g = glass or ("glass_lit" if lit else "glass_dark")
    if abs(face) == 1:
        s = face
        M.box((x, y0 + h / 2, z + s * 0.01), (w, h, 0.04), g)
        for (cx, cy, sx, sy) in ((x, y0 + h + 0.05, w + 0.24, 0.12), (x, y0 - 0.04, w + 0.3, 0.1),
                                 (x - w / 2 - 0.05, y0 + h / 2, 0.1, h + 0.1), (x + w / 2 + 0.05, y0 + h / 2, 0.1, h + 0.1),
                                 (x, y0 + h * 0.62, w, 0.05), (x, y0 + h / 2, 0.05, h)):
            M.box((cx, cy, z + s * o), (sx, sy, 0.07), frame)
        # Dressed stone lintel and sill.
        M.box((x, y0 + h + 0.24, z + s * 0.05), (w + 0.5, 0.26, 0.1), "wall")
        M.box((x, y0 - 0.12, z + s * 0.08), (w + 0.4, 0.08, 0.16), "wall")
    else:
        s = 1 if face > 0 else -1
        M.box((z + s * 0.01, y0 + h / 2, x), (0.04, h, w), g)
        for (cx, cy, sx, sy) in ((x, y0 + h + 0.05, w + 0.24, 0.12), (x, y0 - 0.04, w + 0.3, 0.1),
                                 (x - w / 2 - 0.05, y0 + h / 2, 0.1, h + 0.1), (x + w / 2 + 0.05, y0 + h / 2, 0.1, h + 0.1),
                                 (x, y0 + h * 0.62, w, 0.05), (x, y0 + h / 2, 0.05, h)):
            M.box((z + s * o, cy, cx), (0.07, sy, sx), frame)
        M.box((z + s * 0.05, y0 + h + 0.24, x), (0.1, 0.26, w + 0.5), "wall")
        M.box((z + s * 0.08, y0 - 0.12, x), (0.16, 0.08, w + 0.4), "wall")


def door(M, x, z, w, h, s):
    M.box((x, h / 2, z + s * 0.03), (w, h, 0.06), "wood_green")
    for k in (-1, 1):                            # two leaves with raised panels
        for py in (0.55, 1.45):
            M.box((x + k * w / 4, py, z + s * 0.07), (w / 2 - 0.2, 0.6, 0.03), "wood_green")
    M.box((x, h + 0.25, z + s * 0.02), (w, 0.4, 0.04), "glass_lit")      # transom light
    M.box((x, h + 0.55, z + s * 0.06), (w + 0.5, 0.26, 0.12), "wall")    # lintel
    M.box((x, h + 0.05, z + s * 0.06), (w + 0.1, 0.08, 0.1), "wood_green")


WALL_T = 0.4         # wall thickness of the stations one can walk into


def holed_wall(M, along, c, span, H, t, out, holes, mat_out="stone", mat_in="wall"):
    """A wall slab with openings. along = "x" (a front or back wall at z = c, outside toward `out`
    = -1/+1 in z) or "z" (an end wall at x = c). span = (a0, a1) along the wall, holes =
    [(a0, a1, y0, y1)]. The slab is stone; a thin plaster lining covers its inner face."""
    def put(a0, a1, y0, y1):
        if a1 - a0 < 0.01 or y1 - y0 < 0.01:
            return
        for (mat, d0, d1) in ((mat_out, 0.0, t - 0.02), (mat_in, t - 0.02, t)):
            mid = c - out * (d0 + d1) / 2          # from the outer face inward
            th = d1 - d0
            if along == "x":
                M.box(((a0 + a1) / 2, (y0 + y1) / 2, mid), (a1 - a0, y1 - y0, th), mat)
            else:
                M.box((mid, (y0 + y1) / 2, (a0 + a1) / 2), (th, y1 - y0, a1 - a0), mat)
    hs = sorted(holes)
    a = span[0]
    for (h0, h1, y0, y1) in hs:
        put(a, h0, 0.0, H)                 # pier
        put(h0, h1, 0.0, y0)               # under the opening
        put(h0, h1, y1, H)                 # over it
        a = h1
    put(a, span[1], 0.0, H)


def open_door(T, x, z, w, h, s):
    """A double door standing open: the frame round the opening, both leaves swung in against the
    reveals (s = -1: the wall's outside toward -z), the glazed transom kept over the opening."""
    T.box((x, h + 0.04, z + s * 0.02), (w + 0.2, 0.1, 0.1), "wood_green")
    for k in (-1, 1):
        T.box((x + k * (w / 2 + 0.05), h / 2, z + s * 0.02), (0.1, h, 0.1), "wood_green")
        # The leaf against the inside of the reveal, square to the wall.
        lx = x + k * (w / 2 - 0.04)
        T.box((lx, h / 2, z - s * (WALL_T + w / 4 + 0.02)), (0.05, h - 0.05, w / 2 - 0.02), "wood_green")
        T.box((lx - k * 0.03, h * 0.68, z - s * (WALL_T + w / 4 + 0.02)), (0.01, h * 0.38, w / 2 - 0.2), "glass_clear")
    T.box((x, h + 0.38, z + s * 0.01), (w, 0.5, 0.04), "glass_lit")


def station_house(name, L, D, H, pitch_deg, canopy, shelter, cupola, annex, lit_seed):
    r = root(name)
    M = Mesh()
    T = Mesh()     # timber, iron and glass details (no shadows needed; separate object)
    hx, hz = L / 2, D / 2
    # Rubble-stone walls with a slightly proud plinth and quoins. The full station is built to walk
    # into: walls with real door and window openings, a plaster lining and ceiling inside (the
    # booking hall's fittings are a model of their own); the halt stays a solid block.
    hollow = L > 9
    n_bays = max(2, int(L / 2.8))
    bay_x = [-hx + (i + 0.5) * L / n_bays for i in range(n_bays)]
    front_doors = [bay_x[n_bays // 2 - 1], bay_x[n_bays // 2]]
    if hollow:
        t = WALL_T
        holes_f = [(x - 0.65, x + 0.65, 0.0, 2.35) if x in front_doors else (x - 0.5, x + 0.5, 1.0, 2.8) for x in bay_x]
        holes_b = [(x - 0.5, x + 0.5, 1.0, 2.8) for i, x in enumerate(bay_x) if i % 2 == 0 and i != n_bays // 2]
        holes_b.append((bay_x[n_bays // 2] - 0.75, bay_x[n_bays // 2] + 0.75, 0.0, 2.3))     # to the town
        holed_wall(M, "x", -hz, (-hx, hx), H, t, -1, holes_f)
        holed_wall(M, "x", hz, (-hx, hx), H, t, 1, holes_b)
        holed_wall(M, "z", -hx, (-hz + t, hz - t), H, t, -1, [(-0.5, 0.5, 1.0, 2.6)])
        holed_wall(M, "z", hx, (-hz + t, hz - t), H, t, 1, [])
        M.face([(-hx + t, H - 0.01, -hz + t), (hx - t, H - 0.01, -hz + t), (hx - t, H - 0.01, hz - t), (-hx + t, H - 0.01, hz - t)],
               "wall")                                                       # ceiling (faces down)
        M.box((0, H + 0.05, 0), (L, 0.1, D), "stone")                         # wall tops / attic floor
    else:
        M.box((0, H / 2, 0), (L, H, D), "stone")
    M.box((0, 0.3, 0), (L + 0.12, 0.6, D + 0.12), "stone") if not hollow else None
    if hollow:
        # The proud plinth round the outside, broken at the doors.
        for (along, c, out, span, holes) in (("x", -hz, -1, (-hx - 0.06, hx + 0.06), [(x - 0.65, x + 0.65) for x in front_doors]),
                                             ("x", hz, 1, (-hx - 0.06, hx + 0.06), [(bay_x[n_bays // 2] - 0.75, bay_x[n_bays // 2] + 0.75)])):
            a = span[0]
            for (h0, h1) in sorted(holes) + [(span[1], span[1])]:
                if h0 - a > 0.01:
                    M.box(((a + h0) / 2, 0.3, c + out * 0.03), (h0 - a, 0.6, 0.06), "stone")
                a = h1
        for sx in (-1, 1):
            M.box((sx * (hx + 0.03), 0.3, 0), (0.06, 0.6, D + 0.12), "stone")
    for sx in (-1, 1):
        for sz in (-1, 1):
            for i in range(int(H / 0.55)):
                y = 0.6 + i * 0.55 + 0.25
                if y > H - 0.2:
                    break
                lw = 0.5 if i % 2 == 0 else 0.32
                M.box((sx * (hx - lw / 2 + 0.03), y, sz * (hz + 0.03)), (lw, 0.48, 0.08), "wall")
                M.box((sx * (hx + 0.03), y, sz * (hz - (0.32 if i % 2 == 0 else 0.5) / 2 + 0.03)), (0.08, 0.48, 0.32 if i % 2 == 0 else 0.5), "wall")
    # Gable roof, ridge along x.
    pitch = math.radians(pitch_deg)
    eave = 0.55
    over = 0.7
    rise = (hz + eave) * math.tan(pitch)
    ridge = H + rise - eave * math.tan(pitch) + 0.15
    y_e = ridge - (hz + eave) * math.tan(pitch)
    t = 0.16
    for s in (-1, 1):
        a = (-hx - over, ridge, 0)
        b = (hx + over, ridge, 0)
        c = (hx + over, y_e, s * (hz + eave))
        d = (-hx - over, y_e, s * (hz + eave))
        M.face([a, b, c, d], "roof")
        M.face([(p[0], p[1] - t, p[2]) for p in (d, c, b, a)], "wood")       # boarded soffit
        M.face([c, d, (d[0], d[1] - t, d[2]), (c[0], c[1] - t, c[2])], "wood")
    # Gable walls (triangles) in cream plaster with dark half-timbering (diagonal boards), and
    # bargeboards along the verges.
    for sx in (-1, 1):
        x = sx * hx
        M.face([(x, H, -hz), (x, H, hz), (x, ridge - 0.2, 0)], "wall")
        xo = x + sx * 0.06
        T.beam((xo, H + 0.05, -hz), (xo, H + 0.05, hz), 0.08, 0.2, "wood", up=(1, 0, 0))
        T.beam((xo, H, 0), (xo, ridge - 0.25, 0), 0.08, 0.18, "wood", up=(1, 0, 0))
        n_d = 4
        for i in range(1, n_d + 1):
            for sz in (-1, 1):
                z0 = sz * hz * i / (n_d + 0.5)
                y_top = ridge - 0.2 - (abs(z0) / hz) * (ridge - 0.2 - H)
                # Diagonals from the tie beam up toward the king post (the reference's sunburst).
                zt = z0 * 0.35
                yt = ridge - 0.2 - (abs(zt) / hz) * (ridge - 0.2 - H)
                T.beam((xo, H + 0.1, z0), (xo, yt - 0.1, zt), 0.07, 0.12, "wood", up=(1, 0, 0))
        for sz in (-1, 1):
            T.beam((x + sx * (over - 0.05), ridge + 0.05, 0), (x + sx * (over - 0.05), y_e - 0.05, sz * (hz + eave)), 0.06, 0.3, "wood", up=(1, 0, 0))
        # Name board under the gable (text added in the game).
        T.box((x + sx * 0.1, H - 0.55, 0), (0.05, 0.5, min(D * 0.6, 3.4)), "enamel")
        T.box((x + sx * 0.08, H - 0.55, 0), (0.04, 0.58, min(D * 0.6, 3.4) + 0.1), "wood")
        # A window in each end wall.
        window(T, 0.0, 1.0, x, 1.0, 1.6, 2 * sx, lit_seed % 2 == 0, glass="glass_clear" if L > 9 and sx < 0 else None)
    # Front (platform side, -z): doors and windows; back: windows (and the town door, whose
    # steps and doors are a model of their own). The walk-in station's windows are clear glass.
    for i in range(n_bays):
        x = bay_x[i]
        if i in (n_bays // 2 - 1, n_bays // 2) and L > 9:
            open_door(T, x, -hz, 1.3, 2.35, -1)
        elif L <= 9 and i == n_bays // 2:
            door(T, x, -hz, 1.1, 2.2, -1)
        else:
            window(T, x, 1.0, -hz, 1.0, 1.8, -1, (i + lit_seed) % 3 != 0, glass="glass_clear" if hollow else None)
        if (i % 2 == 0 or L <= 9) and not (hollow and i == n_bays // 2):
            window(T, x, 1.0, hz, 1.0, 1.8, 1, (i + lit_seed) % 2 == 0, glass="glass_clear" if hollow else None)
    # Brackets under the eaves along the walls (curved, as in the reference).
    for s in (-1, 1):
        for i in range(int(L / 1.6) + 1):
            x = -hx + i * L / int(L / 1.6)
            z = s * hz
            pts = []
            for k in range(7):
                a = k / 6 * math.pi / 2
                pts.append((x, H - 0.75 + 0.75 * math.sin(a), z + s * (0.5 * (1 - math.cos(a)) + 0.02)))
            T.sweep(pts, 0.08, 0.1, "wood")
    # The canopy over the platform: a lean-to from under the front eave out over the platform,
    # running past the building into an open shelter at one end.
    x0 = -hx - shelter
    x1 = hx + 0.6
    z_in = -hz + 0.05
    z_out = -hz - canopy
    y_in = H - 0.05
    y_out = H - 0.05 - canopy * math.tan(math.radians(14))
    M.face([(x0, y_in, z_in), (x1, y_in, z_in), (x1, y_out, z_out), (x0, y_out, z_out)], "roof")
    M.face([(x0, y_out - 0.1, z_out), (x1, y_out - 0.1, z_out), (x1, y_in - 0.1, z_in), (x0, y_in - 0.1, z_in)], "wood")
    M.face([(x0, y_out, z_out), (x1, y_out, z_out), (x1, y_out - 0.32, z_out), (x0, y_out - 0.32, z_out)], "wood")
    for x in (x0, x1):
        M.face([(x, y_in, z_in), (x, y_out, z_out), (x, y_out - 0.32, z_out), (x, y_in - 0.1, z_in)], "wood")
    # Posts with curved knee braces along x and toward the wall.
    zp = z_out + 0.45
    yp = y_out + (y_in - y_out) * (0.45 / canopy) - 0.12
    n_posts = max(2, int((x1 - x0) / 3.4))
    for i in range(n_posts + 1):
        x = x0 + 0.3 + i * (x1 - x0 - 0.6) / n_posts
        T.beam((x, 0.0, zp), (x, yp, zp), 0.18, 0.18, "wood")
        T.box((x, 0.08, zp), (0.3, 0.16, 0.3), "stone")
        for k in (-1, 1):
            if (i == 0 and k < 0) or (i == n_posts and k > 0):
                continue
            pts = []
            for j in range(7):
                a = j / 6 * math.pi / 2
                pts.append((x + k * 0.9 * (1 - math.cos(a)), yp - 0.9 + 0.9 * math.sin(a), zp))
            T.sweep(pts, 0.1, 0.12, "wood", up=(0, 0, 1))
        # Brace toward the building (or the shelter's back posts).
        pts = []
        for j in range(7):
            a = j / 6 * math.pi / 2
            pts.append((x, yp - 0.8 + 0.8 * math.sin(a), zp + 0.8 * (1 - math.cos(a))))
        T.sweep(pts, 0.1, 0.12, "wood", up=(1, 0, 0))
    T.beam((x0, yp + 0.02, zp), (x1, yp + 0.02, zp), 0.2, 0.24, "wood")
    # The open shelter's back: posts along the wall line and an iron railing between them.
    if shelter > 0.5:
        xs_end = -hx - 0.2
        nb = max(1, int(shelter / 3.4))
        for i in range(nb + 1):
            x = x0 + 0.3 + i * (xs_end - x0 - 0.3) / nb
            T.beam((x, 0.0, z_in), (x, y_in - 0.1, z_in), 0.18, 0.18, "wood")
        T.beam((x0, y_in - 0.15, z_in), (xs_end, y_in - 0.15, z_in), 0.2, 0.2, "wood")
        for y in (0.12, 1.05):
            T.beam((x0 + 0.3, y, z_in - 0.05), (xs_end, y, z_in - 0.05), 0.04, 0.05, "iron")
        x = x0 + 0.45
        while x < xs_end - 0.1:
            T.beam((x, 0.1, z_in - 0.05), (x, 1.12, z_in - 0.05), 0.022, 0.022, "iron")
            x += 0.14
        # Bench-height back board under the railing (timber dado) for the waiting passengers.
        T.box(((x0 + xs_end) / 2, 0.45, z_in + 0.03), (xs_end - x0, 0.9, 0.05), "wood")
    # Ventilator turret with a little dome on the ridge.
    if cupola:
        cx = L * 0.12
        cw = 1.25 if L > 9 else 0.85
        ch = 1.0 if L > 9 else 0.7
        yb = ridge - 0.35
        M.box((cx, yb + ch / 2, 0), (cw, ch, cw), "wall")
        for sx in (-1, 1):                                  # louvres on all four faces
            for i in range(5):
                y = yb + 0.15 + i * (ch - 0.25) / 4
                T.box((cx + sx * (cw / 2 + 0.03), y, 0), (0.05, 0.05, cw - 0.2), "wood", )
                T.box((cx, y, sx * (cw / 2 + 0.03)), (cw - 0.2, 0.05, 0.05), "wood")
        M.box((cx, yb + ch + 0.06, 0), (cw + 0.3, 0.12, cw + 0.3), "wood")
        M.lathe([(cw * 0.58, 0.0), (cw * 0.56, 0.12), (cw * 0.48, 0.32), (cw * 0.32, 0.5), (cw * 0.12, 0.62), (0.02, 0.66)],
                16, "roof_dark", base=(cx, yb + ch + 0.12, 0))
        T.beam((cx, yb + ch + 0.75, 0), (cx, yb + ch + 1.3, 0), 0.04, 0.04, "iron")
        T.lathe([(0.07, 0.0), (0.07, 0.06), (0.0, 0.14)], 8, "iron", base=(cx, yb + ch + 1.3, 0))
    # Brick chimney through the back slope.
    chx = -L * 0.25
    chz = hz * 0.45
    y_roof = ridge - chz * math.tan(pitch)
    M.box((chx, (y_roof + ridge + 1.0) / 2 - 0.3, chz), (0.6, ridge + 1.6 - y_roof, 0.5), "brick")
    M.box((chx, ridge + 1.05, chz), (0.75, 0.12, 0.65), "stone")
    # Boarded annexe (lean-to) at the far end.
    if annex:
        aw, ad, ah = 4.0, D * 0.7, H * 0.72
        ax = hx + aw / 2
        az = hz - ad / 2
        M.box((ax, ah / 2, az), (aw, ah, ad), "wood")
        for i in range(int(ad / 0.3) + 1):                  # battens
            T.box((hx + aw + 0.03, ah / 2, az - ad / 2 + i * 0.3), (0.04, ah, 0.06), "wood")
        for i in range(int(aw / 0.3) + 1):
            T.box((hx + i * 0.3, ah / 2, az - ad / 2 - 0.03), (0.06, ah, 0.04), "wood")
        door(T, ax, az - ad / 2, 1.6, 2.2, -1)
        y_hi = ah + 0.45
        M.face([(hx, y_hi, az - ad / 2 - 0.4), (hx + aw + 0.4, ah - 0.1, az - ad / 2 - 0.4),
                (hx + aw + 0.4, ah - 0.1, az + ad / 2 + 0.4), (hx, y_hi, az + ad / 2 + 0.4)], "roof_dark")
        M.face([(hx, y_hi - 0.08, az + ad / 2 + 0.4), (hx + aw + 0.4, ah - 0.18, az + ad / 2 + 0.4),
                (hx + aw + 0.4, ah - 0.18, az - ad / 2 - 0.4), (hx, y_hi - 0.08, az - ad / 2 - 0.4)], "wood")
    M.obj("Body", r)
    T.obj("Details", r)
    return r


# ————— train shed (reference 1) —————

# Spans the main track, both platforms and the loop track (z0 just beyond track 2 at -8.74).
SHED = dict(z0=-10.4, z1=6.75, spring=6.0, rise=5.6, bay=8.0)


def _arc(r_off=0.0, n=36):
    z0, z1, ys, rise = SHED["z0"], SHED["z1"], SHED["spring"], SHED["rise"]
    w = z1 - z0
    R = (w * w / 4 + rise * rise) / (2 * rise)
    zc = (z0 + z1) / 2
    yc = ys + rise - R
    a0 = math.atan2(ys - yc, z0 - zc)
    a1 = math.atan2(ys - yc, z1 - zc)
    pts = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        pts.append((zc + (R + r_off) * math.cos(a), yc + (R + r_off) * math.sin(a)))
    return pts


def column(M, x, z, h):
    M.lathe([(0.26, 0.0), (0.26, 0.25), (0.2, 0.32), (0.16, 0.45), (0.13, 0.6), (0.12, h - 0.7),
             (0.15, h - 0.5), (0.22, h - 0.3), (0.3, h - 0.12), (0.3, h)], 12, "iron", base=(x, 0, z), flutes=1)


def truss(M, x):
    outer = _arc(0.0)
    inner = _arc(-0.55)
    M.sweep([(x, y, z) for (z, y) in outer], 0.14, 0.12, "iron", up=(1, 0, 0))
    M.sweep([(x, y, z) for (z, y) in inner], 0.12, 0.1, "iron", up=(1, 0, 0))
    for i in range(len(outer) - 1):              # lattice web
        a = outer[i] if i % 2 == 0 else inner[i]
        b = inner[i + 1] if i % 2 == 0 else outer[i + 1]
        M.beam((x, a[1], a[0]), (x, b[1], b[0]), 0.05, 0.05, "iron", up=(1, 0, 0))
    # Tie rod across at the springing, with a pendant.
    M.beam((x, SHED["spring"], SHED["z0"]), (x, SHED["spring"], SHED["z1"]), 0.035, 0.035, "iron")


def shed_bay():
    r = root("shed_bay")
    M = Mesh()     # iron
    R = Mesh()     # roof
    bay = SHED["bay"]
    hx = bay / 2
    truss(M, 0.0)
    for z in (SHED["z0"], SHED["z1"]):
        column(M, 0.0, z, SHED["spring"])
    # Roof: slate-and-glass skin on the outer chord, purlins under it, glazing bars over the glazed
    # middle band, snow settles on top in the game.
    outer = _arc(0.12)
    for i in range(len(outer) - 1):
        (za, ya), (zb, yb) = outer[i], outer[i + 1]
        glazed = 6 <= i < len(outer) - 6
        R.face([(-hx, ya, za), (hx, ya, za), (hx, yb, zb), (-hx, yb, zb)], "glass_dark" if glazed else "roof_dark")
        if glazed:
            # A thin snow-bearing skin just above the glass, open in lights between the bars.
            pass
        if i % 3 == 0:
            M.beam((-hx, ya - 0.1, za), (hx, ya - 0.1, za), 0.08, 0.14, "iron")
    for gx in [(-hx + k * bay / 8) for k in range(9)]:
        pts = [(gx, y + 0.02, z) for (z, y) in outer[6:len(outer) - 5]]
        M.sweep(pts, 0.03, 0.04, "iron", up=(1, 0, 0))
    # Longitudinal eaves girders on the columns, and the arcade arches between the columns on
    # both sides (springing from the capitals, apex under the girder).
    for z in (SHED["z0"], SHED["z1"]):
        M.beam((-hx, SHED["spring"] + 0.1, z), (hx, SHED["spring"] + 0.1, z), 0.25, 0.4, "iron")
        for k in (-1, 1):
            pts = []
            for j in range(9):
                a = j / 8 * math.pi / 2
                pts.append((k * hx * (1 - math.cos(a)), SHED["spring"] - 1.5 + 1.4 * math.sin(a), z))
            M.sweep(pts, 0.1, 0.12, "iron", up=(0, 0, 1))
            # Ring in the spandrel.
            cx = k * hx * 0.42
            cy = SHED["spring"] - 0.35
            ring = [(cx + 0.38 * math.cos(2 * math.pi * j / 12), cy + 0.38 * math.sin(2 * math.pi * j / 12), z) for j in range(13)]
            M.sweep(ring, 0.04, 0.04, "iron", up=(0, 0, 1))
    # Gutter / cornice along both eaves.
    for z, s in ((SHED["z0"], -1), (SHED["z1"], 1)):
        R.box((0, SHED["spring"] + 0.42, z + s * 0.25), (bay, 0.25, 0.5), "roof_dark")
    # Lanterns hanging from the truss over both platforms.
    for lz in (4.4, -4.4):
        _lantern(M, lz)
    M.obj("Iron", r)
    R.obj("Roof", r)
    return r


def _lantern(M, lz):
    ly = SHED["spring"] - 2.2
    top_y = None
    for (z, y) in _arc(-0.55):
        if abs(z - lz) < 0.6:
            top_y = y
            break
    top_y = top_y or SHED["spring"] + 2.0
    M.beam((0, top_y, lz), (0, ly + 0.55, lz), 0.02, 0.02, "iron")
    M.lathe([(0.04, 0.0), (0.22, 0.08), (0.2, 0.12)], 8, "iron", base=(0, ly + 0.5, lz))
    M.lathe([(0.12, 0.0), (0.18, 0.1), (0.18, 0.42), (0.14, 0.5)], 8, "lamp", base=(0, ly, lz))
    M.lathe([(0.2, 0.0), (0.05, 0.14), (0.0, 0.16)], 8, "iron", base=(0, ly + 0.5, lz))


def shed_end():
    """The end screen: a fan-glazed lunette in the arch above the tie, at x = 0 (faces -x)."""
    r = root("shed_end")
    M = Mesh()
    G_ = Mesh()
    outer = _arc(-0.1, 40)
    ys = SHED["spring"]
    zc = (SHED["z0"] + SHED["z1"]) / 2
    # Glass: a fan of quads from the hub at the springing line's middle.
    hub = (0.0, ys, zc)
    for i in range(len(outer) - 1):
        (za, ya), (zb, yb) = outer[i], outer[i + 1]
        G_.face([hub, (0.0, ya, za), (0.0, yb, zb)], "glass_lit")
    # Radial bars, two concentric rings, the hub, and a heavy end truss.
    for i in range(0, len(outer), 4):
        z, y = outer[i]
        M.beam((0.02, ys, zc), (0.02, y, z), 0.05, 0.06, "iron", up=(1, 0, 0))
    for f in (0.35, 0.7):
        pts = [(0.02, ys + (y - ys) * f, zc + (z - zc) * f) for (z, y) in outer]
        M.sweep(pts, 0.05, 0.05, "iron", up=(1, 0, 0))
    hubr = [(0.02, ys + 0.5 * math.sin(math.pi * j / 10), zc + 0.5 * math.cos(math.pi * j / 10)) for j in range(11)]
    M.sweep(hubr, 0.08, 0.08, "iron", up=(1, 0, 0))
    M.sweep([(0.0, y, z) for (z, y) in _arc(0.05, 40)], 0.3, 0.3, "iron", up=(1, 0, 0))
    M.beam((0.0, ys, SHED["z0"]), (0.0, ys, SHED["z1"]), 0.3, 0.35, "iron")
    M.obj("Frame", r)
    G_.obj("Glass", r)
    return r


# ————— station yard (island platform, goods, fence) —————

def island_canopy():
    """One 6 m bay of an island-platform umbrella canopy: a cast-iron column on the platform's
    centre line, curved brackets both ways, a shallow butterfly roof (boarded underside, valances)."""
    r = root("island_canopy")
    M = Mesh()
    T = Mesh()
    bay, half_w, h = 6.0, 2.3, 3.1
    column(T, 0.0, 0.0, h)
    T.beam((-bay / 2, h + 0.05, 0), (bay / 2, h + 0.05, 0), 0.2, 0.3, "iron")
    for s in (-1, 1):
        # Cantilever bracket from the capital out toward the roof edge, with a ring in the spandrel.
        pts = [(0, h - 0.9 + 0.9 * math.sin(k / 6 * math.pi / 2), s * half_w * 0.85 * (1 - math.cos(k / 6 * math.pi / 2))) for k in range(7)]
        T.sweep(pts, 0.08, 0.1, "iron", up=(1, 0, 0))
        T.beam((0, h + 0.05, 0), (0, h + 0.25, s * half_w), 0.1, 0.16, "iron", up=(1, 0, 0))
        ring = [(0.0, h - 0.35 + 0.22 * math.sin(2 * math.pi * j / 12), s * 0.55 + 0.22 * math.cos(2 * math.pi * j / 12)) for j in range(13)]
        T.sweep(ring, 0.035, 0.035, "iron", up=(1, 0, 0))
        # Roof: rises gently to the outer edges (butterfly), boarded underneath.
        M.face([(-bay / 2, h + 0.15, 0), (bay / 2, h + 0.15, 0), (bay / 2, h + 0.45, s * (half_w + 0.2)), (-bay / 2, h + 0.45, s * (half_w + 0.2))], "roof_dark")
        M.face([(-bay / 2, h + 0.06, 0), (-bay / 2, h + 0.36, s * (half_w + 0.2)), (bay / 2, h + 0.36, s * (half_w + 0.2)), (bay / 2, h + 0.06, 0)], "wood")
        # Fretted valance along the edge.
        z = s * (half_w + 0.21)
        T.box((0, h + 0.3, z), (bay, 0.16, 0.04), "wood")
        n = int(bay / 0.2)
        for i in range(n):
            x = -bay / 2 + (i + 0.5) * bay / n
            T.face([(x - 0.09, h + 0.23, z), (x + 0.09, h + 0.23, z), (x, h - 0.08, z)], "wood")
    M.box((0, h + 0.12, 0), (bay, 0.1, 0.25), "iron")          # valley gutter
    M.obj("Roof", r)
    T.obj("Details", r)
    return r


def goods_shed():
    """Timber goods shed on a stone loading platform along the siding (track side -z), sliding doors,
    a broad roof running out as a canopy over the loading edge."""
    r = root("goods_shed")
    M = Mesh()
    T = Mesh()
    L, D, H, ph = 16.0, 7.0, 4.2, 1.1
    M.box((0, ph / 2 - 0.4, -0.6), (L + 2.0, ph + 0.8, D + 2.4), "stone")          # loading platform
    M.box((0, ph + H / 2, 0), (L, H, D), "wood_green")
    nb = int(L / 0.35)
    for i in range(nb + 1):                                                         # vertical boarding
        x = -L / 2 + i * L / nb
        for s in (-1, 1):
            T.box((x, ph + H / 2, s * (D / 2 + 0.025)), (0.06, H, 0.04), "wood_green")
    for xs in (-L * 0.25, L * 0.25):                                                # sliding doors (track side)
        T.box((xs, ph + 1.4, -D / 2 - 0.06), (3.0, 2.8, 0.06), "wood")
        for k in range(4):
            T.box((xs, ph + 0.35 + k * 0.7, -D / 2 - 0.1), (3.0, 0.08, 0.04), "wood")
        T.beam((xs - 1.6, ph + 2.95, -D / 2 - 0.12), (xs + 1.6, ph + 2.95, -D / 2 - 0.12), 0.06, 0.08, "iron")
    pitch = math.radians(22)
    over = 0.6
    ridge = ph + H + (D / 2 + over) * math.tan(pitch)
    for s in (-1, 1):
        ext = 2.4 if s < 0 else over                                                # canopy over the loading edge
        y_e = ridge - (D / 2 + ext) * math.tan(pitch)
        M.face([(-L / 2 - 0.5, ridge, 0), (L / 2 + 0.5, ridge, 0), (L / 2 + 0.5, y_e, s * (D / 2 + ext)), (-L / 2 - 0.5, y_e, s * (D / 2 + ext))], "roof_dark")
        M.face([(-L / 2 - 0.5, y_e - 0.1, s * (D / 2 + ext)), (L / 2 + 0.5, y_e - 0.1, s * (D / 2 + ext)), (L / 2 + 0.5, ridge - 0.1, 0), (-L / 2 - 0.5, ridge - 0.1, 0)], "wood")
    for sx in (-1, 1):
        y_top = ridge - over * math.tan(pitch)
        M.face([(sx * L / 2, ph + H, -D / 2), (sx * L / 2, ph + H, D / 2), (sx * L / 2, ridge - 0.05, 0)], "wood_green")
        window(T, 0.0, ph + 1.6, sx * L / 2, 1.2, 1.0, 2 * sx, False, "wood")
    for i in range(5):                                                              # canopy brackets
        x = -L / 2 + 1 + i * (L - 2) / 4
        T.beam((x, ph + H - 1.2, -D / 2), (x, ph + H - 0.05, -D / 2 - 2.2), 0.1, 0.12, "wood", up=(1, 0, 0))
    T.box((L / 2 - 1.5, ph + H - 0.6, -D / 2 - 0.08), (2.2, 0.45, 0.05), "enamel")      # name board
    M.obj("Body", r)
    T.obj("Details", r)
    return r


def boxcar():
    """Two-axle covered goods wagon (Austrian/Czechoslovak type), about 8.5 m over buffers, a low
    arched roof (snow lies on it in the game). Origin at rail-top level under the middle."""
    r = root("boxcar")
    M = Mesh()
    T = Mesh()
    L, W, H = 7.4, 2.75, 2.25
    y0 = 1.05                     # floor above rail top
    M.box((0, y0 + H / 2, 0), (L, H, W), "brick")                                    # body (oxide red)
    nb = int(L / 0.3)
    for i in range(nb + 1):
        x = -L / 2 + i * L / nb
        for s in (-1, 1):
            T.box((x, y0 + H / 2, s * (W / 2 + 0.015)), (0.04, H, 0.03), "brick")
    for s in (-1, 1):
        zz = s * (W / 2 + 0.04)
        for y in (y0 + 0.1, y0 + H - 0.1):
            T.beam((-L / 2, y, zz), (L / 2, y, zz), 0.08, 0.12, "iron")
        for x in (-L / 2 + 0.1, -1.0, 1.0, L / 2 - 0.1):
            T.beam((x, y0, zz), (x, y0 + H, zz), 0.08, 0.06, "iron", up=(0, 0, 1))
        T.beam((-1.0, y0 + 0.2, zz + s * 0.01), (1.0, y0 + H - 0.2, zz + s * 0.01), 0.06, 0.05, "iron", up=(0, 0, 1))
        T.beam((1.0, y0 + 0.2, zz + s * 0.01), (-1.0, y0 + H - 0.2, zz + s * 0.01), 0.06, 0.05, "iron", up=(0, 0, 1))
        T.beam((-1.2, y0 + H + 0.05, s * (W / 2 + 0.1)), (1.2, y0 + H + 0.05, s * (W / 2 + 0.1)), 0.05, 0.05, "iron")
    n = 10
    for i in range(n):                                                              # low arched roof
        a0 = -0.5 + i / n
        a1 = -0.5 + (i + 1) / n
        z0, z1 = a0 * (W + 0.1), a1 * (W + 0.1)
        y_0 = y0 + H + 0.32 * (1 - (2 * a0) ** 2)
        y_1 = y0 + H + 0.32 * (1 - (2 * a1) ** 2)
        M.face([(-L / 2 - 0.1, y_0, z0), (L / 2 + 0.1, y_0, z0), (L / 2 + 0.1, y_1, z1), (-L / 2 - 0.1, y_1, z1)], "roof_dark")
    for sx in (-1, 1):
        pts = [(sx * L / 2, y0 + H, -W / 2)]
        for k in range(1, n):
            a = -0.5 + k / n
            pts.append((sx * L / 2, y0 + H + 0.32 * (1 - (2 * a) ** 2), a * W))
        pts.append((sx * L / 2, y0 + H, W / 2))
        M.face(pts, "brick")
    M.box((0, y0 - 0.2, 0), (L + 0.6, 0.3, W - 0.6), "iron")                         # underframe
    for sx in (-1, 1):                                                              # buffers
        for sz in (-0.85, 0.85):
            bx = sx * (L / 2 + 0.3)
            T.beam((bx, y0 - 0.2, sz), (bx + sx * 0.35, y0 - 0.2, sz), 0.16, 0.16, "iron")
            T.beam((bx + sx * 0.35, y0 - 0.2, sz), (bx + sx * 0.42, y0 - 0.2, sz), 0.36, 0.36, "iron")
    for ax in (-2.25, 2.25):
        for sz in (-1, 1):
            z = sz * 0.7175
            T.box((ax, 0.47, sz * 0.95), (0.35, 0.3, 0.2), "iron")                    # axlebox
            T.box((ax, 0.72, sz * 0.95), (1.4, 0.1, 0.12), "iron")                    # leaf spring
            segs = 18
            for k in range(segs):                                                   # tyre band
                a = 2 * math.pi * k / segs
                b = 2 * math.pi * (k + 1) / segs
                pa = (ax + 0.47 * math.cos(a), 0.47 + 0.47 * math.sin(a))
                pb = (ax + 0.47 * math.cos(b), 0.47 + 0.47 * math.sin(b))
                T.face([(pa[0], pa[1], z - 0.07), (pb[0], pb[1], z - 0.07), (pb[0], pb[1], z + 0.07), (pa[0], pa[1], z + 0.07)], "iron")
            for k in range(8):                                                      # spokes
                a = 2 * math.pi * k / 8
                T.beam((ax, 0.47, z), (ax + 0.44 * math.cos(a), 0.47 + 0.44 * math.sin(a), z), 0.05, 0.04, "iron", up=(0, 0, 1))
        T.beam((ax, 0.47, -0.95), (ax, 0.47, 0.95), 0.1, 0.1, "iron")
    M.obj("Body", r)
    T.obj("Details", r)
    return r


def buffer_stop():
    """Rail-built buffer stop: raking struts each side, a timber beam painted red and white."""
    r = root("buffer_stop")
    T = Mesh()
    for sz in (-0.7175, 0.7175):
        T.beam((0.0, 0.15, sz), (0.0, 1.05, sz), 0.12, 0.14, "iron")
        T.beam((0.0, 1.0, sz), (2.2, 0.15, sz), 0.12, 0.14, "iron", up=(0, 0, 1))
    T.box((-0.1, 1.02, 0), (0.3, 0.32, 2.2), "brick")
    for k in range(5):
        T.box((-0.26, 1.02, -0.9 + k * 0.45), (0.02, 0.3, 0.2), "enamel")
    T.box((-0.27, 1.45, 0), (0.04, 0.45, 0.45), "enamel")                          # stop board
    T.box((-0.29, 1.45, 0), (0.02, 0.12, 0.38), "brick")
    T.obj("Details", r)
    return r


def station_fence():
    """2.5 m bay of the yard fence, 2.2 m high: a low stone plinth, a square post with a cap, and
    iron railings with spear points between two rails, painted dark green-black.
    Runs along +x from x = 0; its face toward +z."""
    r = root("station_fence")
    T = Mesh()
    L = 2.5
    T.box((L / 2, 0.12, 0.05), (L, 0.44, 0.3), "stone")                         # plinth (sunk 0.1)
    T.box((L / 2, 0.36, 0.05), (L + 0.04, 0.06, 0.34), "stone")                 # plinth coping
    T.beam((0.0, -0.1, 0.05), (0.0, 2.15, 0.05), 0.16, 0.16, "iron")
    T.box((0.0, 2.18, 0.05), (0.22, 0.06, 0.22), "iron")
    T.lathe([(0.08, 0.0), (0.0, 0.16)], 4, "iron", base=(0.0, 2.21, 0.05))
    for y in (0.55, 1.85):
        T.beam((0.0, y, 0.05), (L, y, 0.05), 0.04, 0.06, "iron", up=(0, 0, 1))
    n = 20
    for i in range(n):
        x = 0.1 + (i + 0.5) * (L - 0.2) / n
        T.beam((x, 0.38, 0.05), (x, 2.0, 0.05), 0.022, 0.022, "iron")
        T.lathe([(0.03, 0.0), (0.0, 0.12)], 4, "iron", base=(x, 2.0, 0.05))      # spear point
    T.obj("Details", r)
    return r


def export(root_obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in [root_obj] + list(root_obj.children_recursive):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")


BUILD = {
    "station_house": lambda: station_house("station_house", 16.0, 9.0, 4.6, 36.0, 4.2, 12.0, True, True, 1),
    "halt_house": lambda: station_house("halt_house", 7.5, 5.2, 3.3, 38.0, 3.0, 5.0, True, False, 2),
    "shed_bay": shed_bay,
    "shed_end": shed_end,
    "island_canopy": island_canopy,
    "goods_shed": goods_shed,
    "boxcar": boxcar,
    "buffer_stop": buffer_stop,
    "station_fence": station_fence,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 2:] or list(BUILD)
    for name in only:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _mat_cache.clear()
        r = BUILD[name]()
        export(r, os.path.join(OUT, name + ".glb"))
        faces = sum(len(o.data.polygons) for o in r.children_recursive if o.type == "MESH")
        print("[stations] wrote", name, "faces", faces)


main()
