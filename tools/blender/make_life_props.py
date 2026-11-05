# make_life_props.py â€” roadside and farm props for the villages and fields (Blender 5.x).
#   blender --background --factory-startup --python tools/blender/make_life_props.py -- <out_dir>
# One .glb per prop. Conventions after glTF export into Godot: up +Y, origin on the ground at the
# foot of the prop, and the readable face of every sign toward Godot +Z (Blender -Y). Text is not
# modelled: the game puts Label3D text on the blank boards (positions listed per prop below).
#   haystack_cone   conical stack round a pole, snow cap               (â‰ˆ Ã˜4.6 Ã— 4.8 m)
#   haystack_loaf   long field rick with a ridged thatch, snow cap     (â‰ˆ 9 Ã— 4 Ã— 3.8 m, long along X)
#   fence           one 3 m bay of a split-rail fence from x=0 to x=3 (post at x=0 only)
#   barrier_post    level-crossing barrier pedestal, pivot at (0, 1.0, 0)
#   barrier_arm     the striped arm alone, pivot at its origin, reaching along +X 7 m; turns about Z
#   cross_andrew    St Andrew's cross on its post (red-bordered white boards)
#   sign_gate       warning triangle "level crossing with gates"   (1926 Paris convention)
#   sign_train      warning triangle "level crossing without gates"
#   sign_curve      warning triangle "bend"
#   sign_crossroads warning triangle "crossroads"
#   signpost        finger post, two blank arms (text at y 2.30 and 1.98, arms span x 0.15..1.25 / -1.25..-0.15)
#   village_sign    name board on two posts (face 1.7 Ã— 0.5, centre y 1.75, front at z +0.03)
#   km_stone        roadside hectometre stone, red cap
#   hanging_sign    wrought-iron wall bracket with a board (board centre (0.55, -0.55, 0), faces Â±Z)
#   apple_tree      bare, pruned orchard tree with snow on the branches
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1]


def principled(name, color, rough, metallic=0.0, emit=None, emit_strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metallic
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


def materials():
    return {
        "wood": principled("wood_grey", (0.2, 0.17, 0.14), 0.85),
        "wood_dark": principled("wood_dark", (0.11, 0.08, 0.06), 0.8),
        "bark": principled("bark", (0.09, 0.08, 0.07), 0.92),
        "straw": principled("straw", (0.42, 0.33, 0.17), 0.95),
        "straw_old": principled("straw_old", (0.27, 0.22, 0.13), 0.95),
        "snow": principled("snow", (0.88, 0.9, 0.95), 0.75),
        "enamel_white": principled("enamel_white", (0.85, 0.85, 0.82), 0.3),
        "enamel_red": principled("enamel_red", (0.5, 0.03, 0.025), 0.32),
        "enamel_black": principled("enamel_black", (0.02, 0.02, 0.02), 0.35),
        "iron": principled("iron_painted", (0.03, 0.035, 0.03), 0.5),
        "stone": principled("stone_white", (0.62, 0.61, 0.57), 0.8),
        "concrete": principled("concrete", (0.4, 0.39, 0.37), 0.85),
        "steel": principled("steel", (0.5, 0.5, 0.5), 0.35, metallic=1.0),
    }


def new_obj(name, bm, mats, parent=None, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if parent:
        o.parent = parent
    for p in me.polygons:
        p.use_smooth = smooth
    return o


def box(bm, c, size, mat=0, rot=None):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    vs = []
    for i in range(8):
        p = Vector((hx * (1 if i & 1 else -1), hy * (1 if i & 2 else -1), hz * (1 if i & 4 else -1)))
        if rot:
            p = rot @ p
        vs.append(bm.verts.new(Vector(c) + p))
    for f in [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]:
        bm.faces.new([vs[i] for i in f]).material_index = mat


def tube(bm, a, b, ra, rb, segs=8, mat=0, cap=True):
    """Tapered cylinder from a to b."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix()
    ring_a, ring_b = [], []
    for k in range(segs):
        t = 2 * math.pi * k / segs
        p = rot @ Vector((math.cos(t), math.sin(t), 0))
        ring_a.append(bm.verts.new(a + p * ra))
        ring_b.append(bm.verts.new(b + p * rb))
    for k in range(segs):
        bm.faces.new((ring_a[k], ring_a[(k + 1) % segs], ring_b[(k + 1) % segs], ring_b[k])).material_index = mat
    if cap:
        bm.faces.new(list(reversed(ring_a))).material_index = mat
        bm.faces.new(ring_b).material_index = mat


def lathe(bm, prof, segs, mat=0, noise=None):
    """Revolve (radius, z) about Z; optional noise(angle, z) -> radius factor."""
    rings = []
    for (r, z) in prof:
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            rr = r * (noise(a, z) if noise else 1.0)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k])).material_index = mat
    return rings


def snow_cap(src, mats, thickness=0.03, min_up=0.5, name="Snow", patch=True):
    bm = bmesh.new()
    bm.from_mesh(src.data)
    bm.transform(src.matrix_basis)
    def patchy(f):
        if not patch:
            return True
        c = f.calc_center_median()
        n = math.sin(c.x * 5.1 + 1.3) * math.sin(c.y * 4.3) + 0.6 * math.sin(c.x * 13.0 + c.y * 11.0)
        return n > -0.7
    keep = [f for f in bm.faces if f.normal.z > min_up and patchy(f)]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for v in bm.verts:
        jitter = 0.6 + 0.8 * ((math.sin(v.co.x * 31.0) * math.sin(v.co.y * 17.0) + 1) * 0.5)
        v.co += v.normal * thickness * jitter
    return new_obj(name, bm, [mats["snow"]], src.parent, smooth=True)


def root_empty(name):
    r = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(r)
    return r


# â€”â€”â€”â€”â€” farm â€”â€”â€”â€”â€”

def haystack_cone(mats, r):
    root = root_empty("haystack_cone")
    rnd = random.Random(3)
    bm = bmesh.new()
    prof = [(1.9, 0.0), (2.2, 0.5), (2.35, 1.3), (2.25, 2.2), (1.85, 3.0), (1.2, 3.7), (0.55, 4.25), (0.12, 4.55)]
    def noise(a, z):
        return 1.0 + 0.05 * math.sin(a * 5 + z * 2.1) + 0.035 * math.sin(a * 13 + z * 5.0) + rnd.uniform(-0.02, 0.02)
    fine = []
    for i in range(len(prof) - 1):
        for k in range(5):
            u = k / 5
            fine.append((prof[i][0] + (prof[i + 1][0] - prof[i][0]) * u, prof[i][1] + (prof[i + 1][1] - prof[i][1]) * u))
    fine.append(prof[-1])
    rings = lathe(bm, fine, 48, 0, noise)
    bm.faces.new(rings[-1])
    o = new_obj("Stack", bm, [mats["straw"]], root, smooth=True)
    # Old, darker weathered bottom band (separate ring of faces would need UVs; add a skirt instead).
    bm2 = bmesh.new()
    lathe(bm2, [(1.93, 0.02), (2.24, 0.5), (2.27, 0.75)], 28, 0, lambda a, z: 1.012 + 0.04 * math.sin(a * 5 + z * 2.1))
    new_obj("Skirt", bm2, [mats["straw_old"]], root, smooth=True)
    bm3 = bmesh.new()
    tube(bm3, (0.05, 0.02, 4.3), (0.08, 0.05, 5.2), 0.06, 0.04, 6)
    new_obj("Pole", bm3, [mats["wood_dark"]], root)
    s = snow_cap(o, mats, 0.09, 0.42, "Snow", patch=False)
    return root


def haystack_loaf(mats, r):
    root = root_empty("haystack_loaf")
    bm = bmesh.new()
    L, W, H = 9.0, 4.0, 3.8
    nx, na = 44, 36
    rings = []
    for i in range(nx + 1):
        x = -L / 2 + L * i / nx
        u = abs(2 * i / nx - 1.0)
        end = math.sqrt(max(0.0, 1.0 - u ** 6))       # rounded ends
        ring = []
        for k in range(na + 1):
            a = math.pi * k / na
            # Walls bulge, then a ridged roof.
            yy = math.cos(a) * W / 2 * (1.0 + 0.06 * math.sin(a * 2)) * (0.35 + 0.65 * end)
            zz = (math.sin(a) ** 0.7) * H * (0.25 + 0.75 * end)
            zz += 0.04 * math.sin(x * 3.1 + a * 7)
            ring.append(bm.verts.new((x, yy, zz)))
        rings.append(ring)
    for i in range(nx):
        for k in range(na):
            bm.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][k + 1], rings[i][k + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = new_obj("Rick", bm, [mats["straw"]], root, smooth=True)
    snow_cap(o, mats, 0.1, 0.35, "Snow", patch=False)
    return root


def fence(mats, r):
    root = root_empty("fence")
    rnd = random.Random(7)
    bm = bmesh.new()
    tube(bm, (0, 0, -0.1), (0.02, 0.01, 1.25), 0.07, 0.06, 7)
    new_obj("Post", bm, [mats["wood"]], root)
    bmr = bmesh.new()
    for zz in (0.55, 1.05):
        a = Vector((0.0, 0.08, zz + rnd.uniform(-0.04, 0.04)))
        b = Vector((3.0, 0.08, zz + rnd.uniform(-0.04, 0.04)))
        mid = (a + b) / 2 + Vector((0, 0.01, -0.05))
        tube(bmr, a, mid, 0.055, 0.05, 6)
        tube(bmr, mid, b, 0.05, 0.055, 6)
    rails = new_obj("Rails", bmr, [mats["wood"]], root)
    snow_cap(rails, mats, 0.03, 0.45, "Snow", patch=True)
    return root


def barrier_post(mats, r):
    root = root_empty("barrier_post")
    bm = bmesh.new()
    box(bm, (0, 0, 0.1), (0.5, 0.5, 0.2), 0)                         # concrete footing
    box(bm, (0, 0, 0.6), (0.22, 0.3, 0.9), 1)                         # iron pedestal
    box(bm, (0, 0, 1.0), (0.12, 0.42, 0.18), 1)                       # pivot bearing
    tube(bm, (0, -0.24, 1.0), (0, 0.24, 1.0), 0.05, 0.05, 10, 2)        # axle
    o = new_obj("Post", bm, [mats["concrete"], mats["iron"], mats["steel"]], root)
    snow_cap(o, mats, 0.03, 0.6, "Snow", patch=False)
    return root


def barrier_arm(mats, r):
    root = root_empty("barrier_arm")
    bm = bmesh.new()
    # Counterweight behind the pivot, then a tapering arm in alternating red/white bands.
    box(bm, (-0.55, 0, 0), (0.6, 0.16, 0.26), 2)
    box(bm, (-0.15, 0, 0), (0.3, 0.1, 0.12), 2)
    n = 7
    L = 7.0
    for i in range(n):
        x0 = L * i / n
        x1 = L * (i + 1) / n
        r0 = 0.07 - 0.03 * i / n
        r1 = 0.07 - 0.03 * (i + 1) / n
        tube(bm, (x0, 0, 0), (x1, 0, 0), r0, r1, 10, i % 2, cap=(i == n - 1))
    tube(bm, (L - 0.02, 0, -0.42), (L - 0.02, 0, 0), 0.015, 0.015, 6, 2)   # drop rod at the tip
    new_obj("Arm", bm, [mats["enamel_red"], mats["enamel_white"], mats["iron"]], root, smooth=True)
    return root


def _post(bm, h, mat, r=0.045):
    tube(bm, (0, 0.05, -0.2), (0, 0.05, h), r, r, 8, mat)


def cross_andrew(mats, r):
    root = root_empty("cross_andrew")
    bm = bmesh.new()
    _post(bm, 2.9, 2)
    for ang in (math.radians(35), math.radians(-35)):
        rot = Matrix.Rotation(ang, 3, "Y")
        box(bm, (0, 0, 2.45), (1.2, 0.025, 0.2), 1, rot)           # red border board
        box(bm, (0, -0.006, 2.45), (1.12, 0.025, 0.13), 0, rot)    # white face, slightly proud
    o = new_obj("Cross", bm, [mats["enamel_white"], mats["enamel_red"], mats["iron"]], root)
    snow_cap(o, mats, 0.02, 0.5, "Snow", patch=False)
    return root


def _triangle(bm, c, side, mat, y):
    h = side * math.sqrt(3) / 2
    pts = [Vector((-side / 2, y, -h / 3)), Vector((side / 2, y, -h / 3)), Vector((0, y, 2 * h / 3))]
    back = [p + Vector((0, 0.02, 0)) for p in pts]
    vf = [bm.verts.new(Vector(c) + p) for p in pts]
    vb = [bm.verts.new(Vector(c) + p) for p in back]
    bm.faces.new(list(reversed(vf))).material_index = mat
    bm.faces.new(vb).material_index = mat
    for i in range(3):
        bm.faces.new((vf[i], vf[(i + 1) % 3], vb[(i + 1) % 3], vb[i])).material_index = mat


def warning_sign(mats, name, symbol):
    root = root_empty(name)
    bm = bmesh.new()
    _post(bm, 2.35, 3)
    c = Vector((0, 0, 2.3))
    _triangle(bm, c, 0.9, 1, 0.0)            # red
    _triangle(bm, c, 0.66, 0, -0.004)        # white field
    k = 0.016
    y = -0.012
    if symbol == "gate":                     # a little gated fence
        for x in (-0.16, -0.05, 0.06, 0.17):
            box(bm, c + Vector((x, y, -0.05)), (0.025, k, 0.2), 2)
        box(bm, c + Vector((0.005, y, 0.03)), (0.4, k, 0.03), 2)
        box(bm, c + Vector((0.005, y, -0.12)), (0.4, k, 0.03), 2)
    elif symbol == "train":                  # a locomotive
        box(bm, c + Vector((0.02, y, -0.06)), (0.28, k, 0.1), 2)
        box(bm, c + Vector((0.13, y, 0.0)), (0.08, k, 0.12), 2)
        box(bm, c + Vector((-0.1, y, 0.03)), (0.04, k, 0.08), 2)
        for x in (-0.07, 0.03, 0.12):
            box(bm, c + Vector((x, y, -0.13)), (0.05, k, 0.05), 2)
    elif symbol == "curve":                  # an S-bend
        prev = None
        for i in range(9):
            t = i / 8
            p = c + Vector((0.09 * math.sin(t * math.pi * 1.6 - 0.8), y, -0.15 + 0.32 * t))
            if prev is not None:
                d = p - prev
                rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
                box(bm, (p + prev) / 2, (0.035, k, d.length + 0.02), 2, rot)
            prev = p
    elif symbol == "crossroads":
        box(bm, c + Vector((0, y, 0.0)), (0.04, k, 0.34), 2)
        box(bm, c + Vector((0, y, 0.02)), (0.3, k, 0.04), 2)
    o = new_obj("Sign", bm, [mats["enamel_white"], mats["enamel_red"], mats["enamel_black"], mats["iron"]], root)
    snow_cap(o, mats, 0.02, 0.6, "Snow", patch=False)
    return root


def signpost(mats, r):
    root = root_empty("signpost")
    bm = bmesh.new()
    box(bm, (0, 0, 1.2), (0.11, 0.11, 2.8), 1)
    tube(bm, (0, 0, 2.6), (0, 0, 2.72), 0.1, 0.0, 4, 1, cap=True)   # little pyramid cap
    for (zz, sgn) in ((2.30, 1), (1.98, -1)):
        # Arm: board with a pointed end, both faces white with a black edge stripe.
        x0, x1 = 0.08 * sgn, 1.3 * sgn
        box(bm, ((x0 + x1) / 2 - 0.06 * sgn, 0, zz), (abs(x1 - x0) - 0.12, 0.035, 0.2), 0)
        tip = bm.verts.new((x1, 0.0, zz))
        a = bm.verts.new((x1 - 0.12 * sgn, -0.018, zz + 0.1))
        b = bm.verts.new((x1 - 0.12 * sgn, -0.018, zz - 0.1))
        a2 = bm.verts.new((x1 - 0.12 * sgn, 0.018, zz + 0.1))
        b2 = bm.verts.new((x1 - 0.12 * sgn, 0.018, zz - 0.1))
        for f in ((a, b, tip), (b2, a2, tip), (a, tip, a2), (b, b2, tip)):
            try:
                bm.faces.new(f).material_index = 0
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = new_obj("Post", bm, [mats["enamel_white"], mats["wood"]], root)
    snow_cap(o, mats, 0.02, 0.6, "Snow", patch=False)
    return root


def village_sign(mats, r):
    root = root_empty("village_sign")
    bm = bmesh.new()
    for x in (-0.75, 0.75):
        tube(bm, (x, 0.04, -0.2), (x, 0.04, 2.05), 0.035, 0.035, 8, 2)
    box(bm, (0, 0.0, 1.75), (1.78, 0.03, 0.58), 1)      # black border
    box(bm, (0, -0.008, 1.75), (1.7, 0.03, 0.5), 0)     # white face
    o = new_obj("Board", bm, [mats["enamel_white"], mats["enamel_black"], mats["iron"]], root)
    snow_cap(o, mats, 0.025, 0.6, "Snow", patch=False)
    return root


def km_stone(mats, r):
    root = root_empty("km_stone")
    bm = bmesh.new()
    box(bm, (0, 0, 0.25), (0.22, 0.14, 0.7), 0)
    lathe(bm, [(0.11, 0.6), (0.11, 0.62), (0.06, 0.68), (0.0, 0.7)], 10, 1)
    o = new_obj("Stone", bm, [mats["stone"], mats["enamel_red"]], root)
    snow_cap(o, mats, 0.03, 0.6, "Snow", patch=False)
    return root


def hanging_sign(mats, r):
    root = root_empty("hanging_sign")
    bm = bmesh.new()
    # Wall plate, horizontal bar, a scroll brace, two short chains (as rods) and the board.
    box(bm, (0, 0, 0), (0.06, 0.08, 0.5), 0)
    tube(bm, (0, 0, 0.18), (1.05, 0, 0.18), 0.015, 0.012, 6, 0)
    prev = None
    for i in range(13):
        t = i / 12
        a = t * math.pi * 0.5
        p = Vector((0.75 * (1 - math.cos(a)), 0, -0.2 + 0.38 * math.sin(a)))
        if prev is not None:
            tube(bm, prev, p, 0.01, 0.01, 5, 0, cap=False)
        prev = p
    for x in (0.25, 0.85):
        tube(bm, (x, 0, 0.18), (x, 0, 0.05), 0.006, 0.006, 4, 0)
    new_obj("Bracket", bm, [mats["iron"]], root)
    bmb = bmesh.new()
    box(bmb, (0.55, 0, -0.18), (0.72, 0.035, 0.46), 0)
    box(bmb, (0.55, 0, -0.18), (0.66, 0.045, 0.4), 1)
    new_obj("Board", bmb, [mats["wood_dark"], mats["enamel_white"]], root)
    # Blender Y is depth here; rotate so the board faces Â±Y (Godot Â±Z) and the bracket reaches +X.
    return root


def apple_tree(mats, r):
    root = root_empty("apple_tree")
    rnd = random.Random(11)
    bm = bmesh.new()
    segs_of = lambda rad: 7 if rad > 0.06 else (5 if rad > 0.025 else 4)

    def grow(p, d, length, rad, depth):
        end = p + d * length
        tube(bm, p, end, rad, rad * 0.72, segs_of(rad), 0, cap=False)
        if depth == 0 or rad < 0.012:
            return
        n = 3 if depth > 3 else rnd.choice((2, 3))
        for i in range(n):
            # Pruned vase shape: branches climb outward, then up; slight droop at the tips.
            ax = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)).normalized()
            spread = rnd.uniform(0.35, 0.7)
            nd = (d + ax * spread + Vector((0, 0, 0.15 if depth > 1 else -0.1))).normalized()
            grow(end, nd, length * rnd.uniform(0.62, 0.8), rad * 0.68, depth - 1)

    # Short trunk, crown of 4 scaffold limbs.
    tube(bm, (0, 0, -0.2), (0.03, 0.02, 1.25), 0.13, 0.11, 9, 0, cap=False)
    top = Vector((0.03, 0.02, 1.25))
    for i in range(4):
        a = i * math.pi / 2 + rnd.uniform(-0.3, 0.3)
        d = Vector((math.cos(a) * 0.75, math.sin(a) * 0.75, 0.7)).normalized()
        grow(top, d, 1.25, 0.085, 5)
    o = new_obj("Tree", bm, [mats["bark"]], root, smooth=True)
    snow_cap(o, mats, 0.025, 0.55, "Snow", patch=True)
    return root


def round_sign(mats, r):
    """Round enamel sign on a post (speed limit and the like): red ring, white field, face toward
    Godot +Z (Blender -Y), centre at y 2.25; the game writes the figure on it (z +0.03)."""
    root = root_empty("sign_round")
    bm = bmesh.new()
    _post(bm, 2.6, 2)
    for (rad, y, m) in ((0.36, 0.0, 1), (0.29, -0.006, 0)):
        c = Vector((0, y, 2.25))
        ring_f, ring_b = [], []
        for k in range(32):
            a = 2 * math.pi * k / 32
            ring_f.append(bm.verts.new(c + Vector((rad * math.cos(a), 0, rad * math.sin(a)))))
            ring_b.append(bm.verts.new(c + Vector((rad * math.cos(a), 0.02, rad * math.sin(a)))))
        bm.faces.new(list(reversed(ring_f))).material_index = m
        bm.faces.new(ring_b).material_index = m
        for k in range(32):
            bm.faces.new((ring_f[k], ring_f[(k + 1) % 32], ring_b[(k + 1) % 32], ring_b[k])).material_index = m
    o = new_obj("Sign", bm, [mats["enamel_white"], mats["enamel_red"], mats["iron"]], root)
    snow_cap(o, mats, 0.02, 0.6, "Snow", patch=False)
    return root


BUILDERS = {
    "sign_round": round_sign,
    "haystack_cone": haystack_cone,
    "haystack_loaf": haystack_loaf,
    "fence": fence,
    "barrier_post": barrier_post,
    "barrier_arm": barrier_arm,
    "cross_andrew": cross_andrew,
    "sign_gate": lambda m, r: warning_sign(m, "sign_gate", "gate"),
    "sign_train": lambda m, r: warning_sign(m, "sign_train", "train"),
    "sign_curve": lambda m, r: warning_sign(m, "sign_curve", "curve"),
    "sign_crossroads": lambda m, r: warning_sign(m, "sign_crossroads", "crossroads"),
    "signpost": signpost,
    "village_sign": village_sign,
    "km_stone": km_stone,
    "hanging_sign": hanging_sign,
    "apple_tree": apple_tree,
}


def export(root, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + list(root.children_recursive):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 2:] or list(BUILDERS)
    for name in only:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        mats = materials()
        root = BUILDERS[name](mats, None)
        export(root, os.path.join(OUT, name + ".glb"))
        tris = sum(len(o.data.polygons) for o in root.children_recursive if o.type == "MESH")
        print("[props] wrote", name, "faces", tris)


main()
