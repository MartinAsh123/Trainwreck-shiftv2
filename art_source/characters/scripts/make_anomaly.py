"""An anomaly: a copy of a finished character (its _face.blend: rig, talking face) with something wrong
about it, exported beside the normal cast for the game to slip in among the passengers.
    blender -b <slug>/<slug>_face.blend -P scripts/make_anomaly.py -- <slug> <kind>
kinds:
    third_eye    an eyeball set into the forehead
    cyclops      both eyes skinned over, one big eye in the middle
    six_fingers  an extra little finger on each hand (a copy of the little finger, beside it, on its bones)
    tail         a long tapering tail out from under the coat at the small of the back
    grey_marks   grey veins and sigils over the face (a decal)
    black_eyes   the eyes all black and glossy (a decal)
    faceless     eyes and mouth skinned over: only the nose is left
    long_neck    the head lifted 10 cm on a stretched neck
-> assets/anomalies/<slug>_<kind>/<slug>_<kind>.glb (+ the character's mumbles copied beside it)
Parts are joined into the body mesh and weighted to the bones they ride on, so the anomaly sits, walks
and talks like the original."""
import bpy, bmesh, os, sys, json, math, shutil
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
slug, kind = args[0], args[1]
name = "%s_%s" % (slug, kind)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))
OUT = os.path.join(PROJ, "assets", "anomalies", name)
os.makedirs(OUT, exist_ok=True)
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
arm = bpy.data.objects[slug + "_rig"]
body = bpy.data.objects[slug + "_body"]
me = body.data
mw = body.matrix_world
inv = mw.inverted()
scn = bpy.context.scene
rng = np.random.default_rng(abs(hash(name)) % (2 ** 32))
MM = 0.001

# ————— the body's surface: rays from the front (-Y), its colour —————
wv = [mw @ v.co for v in me.vertices]
polys = [list(p.vertices) for p in me.polygons]
bvh = BVHTree.FromPolygons(wv, polys)
uvl = me.uv_layers.active.data
_img_cache = {}


def hit_front(x, z, back=False):
    """The first surface seen from the front (or from behind) at (x, z): (point, normal, face index)."""
    if back:
        h = bvh.ray_cast(Vector((x, 2.0, z)), Vector((0, -1, 0)))
    else:
        h = bvh.ray_cast(Vector((x, -2.0, z)), Vector((0, 1, 0)))
    return h[0], h[1], h[2]


def _pixels(img):
    if img.name not in _img_cache:
        w, h = img.size
        _img_cache[img.name] = np.array(img.pixels[:], np.float32).reshape(h, w, 4)
    return _img_cache[img.name]


def color_at(x, z):
    """The texture colour where the front ray at (x, z) meets the body."""
    p, _, fi = hit_front(x, z)
    if p is None:
        return None
    poly = me.polygons[fi]
    mat = me.materials[poly.material_index]
    img = next((n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image), None)
    if img is None:
        return None
    # barycentric over the polygon's fan triangles
    li = list(poly.loop_indices)
    vs = [wv[i] for i in poly.vertices]
    for k in range(1, len(vs) - 1):
        a, b, c = vs[0], vs[k], vs[k + 1]
        v0, v1, v2 = b - a, c - a, p - a
        d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
        d20, d21 = v2.dot(v0), v2.dot(v1)
        den = d00 * d11 - d01 * d01
        if abs(den) < 1e-14:
            continue
        v = (d11 * d20 - d01 * d21) / den
        w = (d00 * d21 - d01 * d20) / den
        u = 1 - v - w
        if min(u, v, w) < -0.05:
            continue
        uv = uvl[li[0]].uv * u + uvl[li[k]].uv * v + uvl[li[k + 1]].uv * w
        px = _pixels(img)
        h, wd = px.shape[:2]
        return px[int(np.clip(uv.y, 0, 0.9999) * h), int(np.clip(uv.x, 0, 0.9999) * wd), :3]
    return None


def skin_tone():
    """This face's skin: the median of the cheeks below both eyes."""
    cs = []
    for e in F["eyes"]:
        for dx in np.linspace(-0.012, 0.012, 7):
            for dz in np.linspace(-0.032, -0.022, 5):
                c = color_at(e[0] + dx, e[2] + dz)
                if c is not None:
                    cs.append(c)
    return np.median(np.array(cs), axis=0)


def bone_head(b):
    return arm.matrix_world @ arm.data.bones["mixamorig:" + b].head_local


def save_image(arr, nm):
    """An RGBA float array (rows bottom-up) as a PNG in the anomaly's folder, loaded back."""
    h, w = arr.shape[:2]
    im = bpy.data.images.new(nm, w, h, alpha=True)
    im.pixels[:] = np.clip(arr, 0, 1).ravel()
    path = os.path.join(OUT, nm + ".png")
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    im = bpy.data.images.load(path)
    return im


def material(nm, img=None, color=(0.5, 0.5, 0.5), rough=0.6, blend=False):
    m = bpy.data.materials.new(nm)
    m.use_nodes = True
    bs = m.node_tree.nodes["Principled BSDF"]
    bs.inputs["Roughness"].default_value = rough
    if img is not None:
        t = m.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = img
        m.node_tree.links.new(t.outputs["Color"], bs.inputs["Base Color"])
        if blend:
            m.node_tree.links.new(t.outputs["Alpha"], bs.inputs["Alpha"])
            m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    else:
        bs.inputs["Base Color"].default_value = (*color, 1)
    return m


def add_part(bm_, mat, groups):
    """A new mesh object from bmesh `bm_` (world space), one material, every vertex weighted to
    `groups` ({bone: weight}); joined into the body afterwards."""
    m_ = bpy.data.meshes.new(name + "_part")
    for v in bm_.verts:
        v.co = inv @ v.co
    bm_.to_mesh(m_)
    bm_.free()
    o = bpy.data.objects.new(name + "_part", m_)
    o.matrix_world = mw
    scn.collection.objects.link(o)
    m_.materials.append(mat)
    for b, w in groups.items():
        o.vertex_groups.new(name="mixamorig:" + b).add(list(range(len(m_.vertices))), w, "REPLACE")
    for p in m_.polygons:
        p.use_smooth = True
    PARTS.append(o)
    return o


PARTS = []

# ————— pieces —————

def eye_texture(iris, size=(512, 256)):
    """An equirectangular eye for a UV sphere whose top pole looks forward: rows = latitude."""
    w, h = size
    v = (np.arange(h) + 0.5) / h                      # 0 bottom pole (back) .. 1 top pole (front)
    u = (np.arange(w) + 0.5) / w
    U, V = np.meshgrid(u, v)
    r = 1.0 - V                                       # 0 at the pupil, growing back round the ball
    img = np.zeros((h, w, 4), np.float32)
    img[..., 3] = 1
    sclera = np.array([0.86, 0.83, 0.78])
    vein = (np.sin(U * 2 * np.pi * 23 + np.sin(V * 40) * 2) > 0.93) & (r > 0.24)
    col = np.broadcast_to(sclera, (h, w, 3)).copy()
    col[vein] = [0.62, 0.2, 0.18]
    fib = 0.85 + 0.15 * np.sin(U * 2 * np.pi * 61) * np.sin(r * 90)
    ir = np.array(iris)[None, None, :] * fib[..., None]
    ir *= (1 - 0.5 * np.clip((r - 0.14) / 0.04, 0, 1))[..., None]          # limbal darkening
    col = np.where((r < 0.18)[..., None], ir, col)
    col = np.where((r < 0.07)[..., None], np.array([0.02, 0.02, 0.02]), col)  # pupil
    img[..., :3] = col
    return img


def eyeball(center, radius, iris=(0.25, 0.32, 0.22), look=Vector((0, -1, 0))):
    bm_ = bmesh.new()
    bm_.loops.layers.uv.new(me.uv_layers.active.name)
    bmesh.ops.create_uvsphere(bm_, u_segments=32, v_segments=16, radius=radius, calc_uvs=True)
    q = Vector((0, 0, 1)).rotation_difference(look)
    for v in bm_.verts:
        v.co = center + q @ v.co
    mat = material(name + "_eye", save_image(eye_texture(iris), name + "_eye"), rough=0.12)
    return add_part(bm_, mat, {"Head": 1.0})


def decal(x0, x1, z0, z1, rgba_fn, nm, step=0.0012, offset=0.0005):
    """A sheet laid on the face over a box seen from the front, `offset` in front of the skin, showing
    the image rgba_fn(XX, ZZ) -> (h, w, 4) (alpha-blended)."""
    xs = np.arange(x0, x1 + step, step)
    zs = np.arange(z0, z1 + step, step)
    XX, ZZ = np.meshgrid(np.linspace(x0, x1, 256), np.linspace(z0, z1, 256))
    img = save_image(rgba_fn(XX, ZZ), nm)
    bm_ = bmesh.new()
    uvb = bm_.loops.layers.uv.new(me.uv_layers.active.name)
    grid = {}
    for i, x in enumerate(xs):
        for j, z in enumerate(zs):
            p, n, _ = hit_front(x, z)
            if p is None or abs(p.y - F["nose"][1]) > 0.08:
                continue
            grid[(i, j)] = bm_.verts.new(p - Vector((0, offset, 0)))
    for (i, j), v in grid.items():
        q = [grid.get(k) for k in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
        if all(q):
            f = bm_.faces.new(q)
            for lp in f.loops:
                c = lp.vert.co
                lp[uvb].uv = ((c.x - x0) / (x1 - x0), (c.z - z0) / (z1 - z0))
    bm_.normal_update()
    for f in bm_.faces:
        if f.normal.y > 0:
            f.normal_flip()
    return add_part(bm_, material(nm, img, rough=0.5, blend=True), {"Head": 1.0})


def soft_ellipse(XX, ZZ, cx, cz, rx, rz, feather=0.35):
    d = np.sqrt(((XX - cx) / rx) ** 2 + ((ZZ - cz) / rz) ** 2)
    return np.clip((1.0 - d) / feather, 0, 1)


def skin_cover(boxes, nm):
    """Smooth skin over the given ellipses (cx, cz, rx, rz), the face's own tone with a little mottling."""
    tone = skin_tone()
    xs = [b[0] - b[2] for b in boxes] + [b[0] + b[2] for b in boxes]
    zs = [b[1] - b[3] for b in boxes] + [b[1] + b[3] for b in boxes]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)

    def fn(XX, ZZ):
        a = np.zeros(XX.shape, np.float32)
        for b in boxes:
            a = np.maximum(a, soft_ellipse(XX, ZZ, *b))
        noise = rng.normal(0, 1, XX.shape)
        k = np.ones(9) / 9
        for ax in (0, 1):
            noise = np.apply_along_axis(lambda m: np.convolve(m, k, "same"), ax, noise)
        col = tone[None, None, :] * (1 + 0.05 * noise[..., None])
        col *= (1 - 0.06 * (1 - a))[..., None]        # a faint seam where it meets the face
        return np.concatenate([col, a[..., None]], axis=2)
    return decal(x0, x1, z0, z1, fn, nm)


def eye_boxes(rx=0.025, rz=0.017, lift=0.004):
    return [(e[0], e[2] + lift, rx, rz) for e in F["eyes"]]


def strokes(XX, ZZ, n_veins, n_sigils, color, x0, x1, z0, z1, avoid):
    """Grey veins (random branching walks) and a few round sigils."""
    a = np.zeros(XX.shape, np.float32)
    S = (x1 - x0) / XX.shape[1]

    def line(p, q, wdt):
        d = np.asarray(q) - np.asarray(p)
        L = max(np.hypot(*d), 1e-6)
        t = np.clip(((XX - p[0]) * d[0] + (ZZ - p[1]) * d[1]) / (L * L), 0, 1)
        dist = np.hypot(XX - (p[0] + t * d[0]), ZZ - (p[1] + t * d[1]))
        return np.clip(1 - dist / wdt, 0, 1)

    for _ in range(n_veins):
        p = np.array([rng.uniform(x0, x1), rng.uniform(z0, z1)])
        ang = rng.uniform(0, 2 * np.pi)
        wdt = rng.uniform(1.1, 1.8) * MM
        for _s in range(rng.integers(8, 16)):
            ang += rng.normal(0, 0.6)
            q = p + 0.004 * np.array([np.cos(ang), np.sin(ang)])
            a = np.maximum(a, line(p, q, wdt))
            if rng.random() < 0.25:                    # a branch
                b = p + 0.003 * np.array([np.cos(ang + 1.2), np.sin(ang + 1.2)])
                a = np.maximum(a, line(p, b, wdt * 0.6))
            p, wdt = q, wdt * 0.92
    for _ in range(n_sigils):
        c = np.array([rng.uniform(x0 + 0.01, x1 - 0.01), rng.uniform(z0 + 0.01, z1 - 0.01)])
        r = rng.uniform(0.005, 0.008)
        d = np.hypot(XX - c[0], ZZ - c[1])
        a = np.maximum(a, np.clip(1 - np.abs(d - r) / (1.0 * MM), 0, 1))
        for k in range(3):
            t = rng.uniform(0, 2 * np.pi)
            a = np.maximum(a, line(c, c + r * 1.5 * np.array([np.cos(t), np.sin(t)]), 0.9 * MM))
    for (cx, cz, rx, rz) in avoid:                     # (never over the eyes themselves)
        a *= 1 - soft_ellipse(XX, ZZ, cx, cz, rx, rz, 0.2)
    col = np.broadcast_to(np.array(color, np.float32), XX.shape + (3,))
    return np.concatenate([col, (0.95 * a)[..., None]], axis=2)


def human_eye(cx, cz, w, h, iris):
    """A human eye painted into the skin (a decal): an almond opening with the iris half under the upper
    lid, a lash line, the lid crease above and a soft shadow below - no eyeball standing out of the face."""
    tone = skin_tone()
    x0, x1, z0, z1 = cx - 0.75 * w, cx + 0.75 * w, cz - 1.1 * h, cz + 1.4 * h

    def fn(XX, ZZ):
        u = (XX - (cx - w / 2)) / w
        inx = (u > 0) & (u < 1)
        uc = np.clip(u, 1e-4, 1 - 1e-4)
        top = cz + h / 2 * np.sin(np.pi * uc ** 0.9) ** 0.75
        bot = cz - h / 2 * np.sin(np.pi * uc ** 1.1)
        din = np.where(inx, np.minimum(ZZ - bot, top - ZZ), -1.0)
        a_eye = np.clip(din / (0.25 * MM) + 0.5, 0, 1)
        sclera = np.array([0.84, 0.81, 0.77]) * (1 - 0.3 * np.abs(2 * uc - 1) ** 3)[..., None]
        icx, icz, ri = cx + 0.02 * w, cz + 0.06 * h, 0.52 * h
        r = np.hypot(XX - icx, ZZ - icz)
        ang = np.arctan2(ZZ - icz, XX - icx)
        fib = 0.85 + 0.12 * np.sin(ang * 37) * np.sin(r / ri * 9) + 0.06 * np.sin(ang * 83)
        ir = np.array(iris)[None, None, :] * fib[..., None]
        ir *= (1 - 0.55 * np.clip((r - 0.8 * ri) / (0.2 * ri), 0, 1))[..., None]
        ai = np.clip((ri - r) / (0.06 * ri), 0, 1)[..., None]
        col = sclera * (1 - ai) + ir * ai
        ap = np.clip((0.4 * ri - r) / (0.05 * ri), 0, 1)[..., None]
        col = col * (1 - ap) + 0.03 * ap
        col *= (1 - 0.5 * np.clip((ZZ - (top - 0.45 * h)) / (0.45 * h), 0, 1))[..., None]     # upper lid's shadow
        hl = np.exp(-(np.hypot(XX - (icx - 0.3 * ri), ZZ - (icz + 0.35 * ri)) / (0.12 * ri)) ** 2)
        col += (0.95 - col) * (0.8 * hl)[..., None]
        # round it: lash line, crease, lower-lid shadow, in the skin's own tone
        over = ZZ - top
        lash = np.clip(1 - np.abs(over - 0.35 * MM) / (0.45 * MM + 0.35 * MM * (1 - uc)), 0, 1) * inx
        crease = np.exp(-((ZZ - (top + 0.38 * h)) / (0.9 * MM)) ** 2) * np.sin(np.pi * uc) * inx
        under = np.exp(-(np.clip(bot - ZZ, 0, None) / (1.2 * MM))) * (ZZ < bot) * np.sin(np.pi * uc) * inx
        out = np.broadcast_to(tone * 0.45, XX.shape + (3,)).copy()
        a_out = np.maximum.reduce([0.9 * lash, 0.35 * crease, 0.25 * under])
        out = np.where((lash > 0.3)[..., None], tone * 0.15, out)
        rgb = col * a_eye[..., None] + out * (1 - a_eye[..., None])
        alpha = np.maximum(a_eye, a_out)
        return np.concatenate([rgb, alpha[..., None]], axis=2)
    d = decal(x0, x1, z0, z1, fn, name + "_eye", step=0.0007, offset=0.0011)
    d.data.materials[-1].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.5
    return d


def socket_shadow(cx, cz, r):
    """A dark, raw rim round an eye set into the skin."""
    def fn(XX, ZZ):
        d = np.hypot(XX - cx, ZZ - cz) / r
        a = np.clip(1 - np.abs(d - 1.0) / 0.35, 0, 1) * 0.9
        col = np.zeros(XX.shape + (3,), np.float32) + np.array([0.22, 0.09, 0.08])
        return np.concatenate([col, a[..., None]], axis=2)
    return decal(cx - 1.6 * r, cx + 1.6 * r, cz - 1.6 * r, cz + 1.6 * r, fn, name + "_socket", step=0.0008)


# ————— the kinds —————

eyes = F["eyes"]
ex = float(np.mean([e[0] for e in eyes]))
ez = float(np.mean([e[2] for e in eyes]))
eye_gap = abs(eyes[0][0] - eyes[1][0])

if kind == "third_eye":
    human_eye(ex, ez + 0.034, 0.022, 0.0085, (0.42, 0.3, 0.14))
elif kind == "cyclops":
    skin_cover(eye_boxes(), name + "_lids")
    human_eye(ex, ez + 0.012, 0.027, 0.0105, (0.22, 0.33, 0.38))
elif kind == "faceless":
    m = F["mouth"]
    mc = F["mouth_corners"]
    half = abs(mc[1][0] - mc[0][0]) / 2 + 0.008
    skin_cover(eye_boxes(0.02, 0.012) + [(m[0], m[2], half, 0.011)], name + "_skin")
elif kind == "black_eyes":
    def fn(XX, ZZ):
        a = np.zeros(XX.shape, np.float32)
        for e in eyes:
            a = np.maximum(a, soft_ellipse(XX, ZZ, e[0], e[2], 0.0145, 0.0068, 0.25))
        col = np.zeros(XX.shape + (3,), np.float32) + 0.008
        return np.concatenate([col, a[..., None]], axis=2)
    x0, x1 = min(e[0] for e in eyes) - 0.02, max(e[0] for e in eyes) + 0.02
    d = decal(x0, x1, ez - 0.012, ez + 0.012, fn, name + "_black", step=0.0008, offset=0.0006)
    d.data.materials[0].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.05
elif kind == "grey_marks":
    x0, x1 = ex - 0.07, ex + 0.07
    z0, z1 = F["mouth"][2] - 0.03, ez + 0.05
    avoid = eye_boxes(0.015, 0.008)
    decal(x0, x1, z0, z1, lambda XX, ZZ: strokes(XX, ZZ, 18, 3, (0.30, 0.32, 0.35), x0, x1, z0, z1, avoid),
          name + "_marks", step=0.0015)
elif kind == "six_fingers":
    # A sixth finger beyond the little one on each hand: a tapering three-jointed digit a little longer
    # than the little finger, in the hand's own colour, bending with the little finger's bones.
    vg = {g.index: g.name.replace("mixamorig:", "") for g in body.vertex_groups}

    def centroid(bones_):
        ws, acc = 0.0, Vector()
        for v in me.vertices:
            w = sum(g.weight for g in v.groups if vg.get(g.group) in bones_)
            if w > 0.3:
                acc += wv[v.index] * w
                ws += w
        return acc / ws if ws else None

    for side in ("Left", "Right"):
        hand = bone_head(side + "Hand")
        pc = centroid({side + "HandPinky%d" % k for k in (1, 2, 3)})
        mc = centroid({side + "HandMiddle%d" % k for k in (1, 2, 3)})
        if pc is None or mc is None:
            print("SIX: no %s finger weights" % side)
            continue
        fwd = (mc - hand).normalized()                       # along the hand, toward the fingertips
        spread = pc - mc
        spread -= fwd * spread.dot(fwd)
        spread = spread.normalized()                         # across the hand, beyond the little finger
        base = pc + spread * 0.013 - fwd * 0.015
        d = (fwd + spread * 0.3).normalized()
        L = 0.085
        cs = [color_at(c.x, c.z) for c in [pc + fwd * a + spread * b for a in (-0.02, 0, 0.02) for b in (-0.03, -0.015, 0)]]
        cs = [c for c in cs if c is not None]
        tone = np.percentile(np.array(cs), 70, axis=0) if cs else np.array([0.5, 0.4, 0.35])
        tone = tuple(float(c) for c in tone)
        side_ax = spread
        bend_ax = d.cross(side_ax).normalized()
        N, seg = 16, 10
        pts, rads, bones = [], [], []
        for i in range(N):
            t = i / (N - 1)
            curl = 0.25 * t * t                              # curling down a little toward the tip
            pts.append(base + d * (L * t) - bend_ax * (L * curl * 0.5))
            rads.append(0.0105 * (1 - 0.3 * t) * (1 - 0.6 * max(t - 0.85, 0) / 0.15))
            bones.append(side + ("HandPinky1" if t < 0.38 else "HandPinky2" if t < 0.7 else "HandPinky3"))
        bm_ = bmesh.new()
        rings = []
        for i, (c, r) in enumerate(zip(pts, rads)):
            dd = (pts[min(i + 1, N - 1)] - pts[max(i - 1, 0)]).normalized()
            ax = dd.cross(side_ax).normalized()
            bx = dd.cross(ax)
            rings.append([bm_.verts.new(c + r * (math.cos(k * 2 * math.pi / seg) * ax + math.sin(k * 2 * math.pi / seg) * bx)) for k in range(seg)])
        for i in range(N - 1):
            for k in range(seg):
                bm_.faces.new([rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k]])
        tip = bm_.verts.new(pts[-1] + d * rads[-1] * 1.2)
        for k in range(seg):
            bm_.faces.new([rings[-1][k], rings[-1][(k + 1) % seg], tip])
        bmesh.ops.recalc_face_normals(bm_, faces=bm_.faces)
        o = add_part(bm_, material(name + "_finger_" + side, color=tone, rough=0.75), {})
        for i in range(N):
            g = o.vertex_groups.get("mixamorig:" + bones[i]) or o.vertex_groups.new(name="mixamorig:" + bones[i])
            g.add([i * seg + k for k in range(seg)], 1.0, "REPLACE")
        g = o.vertex_groups.get("mixamorig:" + bones[-1])
        g.add([N * seg], 1.0, "REPLACE")
        print("SIX: %s finger %.1f cm, colour %s" % (side, L * 100, tuple(round(c, 2) for c in tone)))
elif kind == "tail":
    hp = bone_head("Hips")
    p, _, _ = hit_front(hp.x, hp.z - 0.06, back=True)
    start = p - Vector((0, 0.02, 0)) if p is not None else hp + Vector((0, 0.12, -0.06))
    pts, rads = [], []
    N = 40
    for i in range(N):
        t = i / (N - 1)
        pts.append(start + Vector((0.06 * math.sin(t * 5.0), 0.05 + 0.32 * t, -0.62 * t ** 1.15 + 0.12 * math.sin(t * 3.4))))
        rads.append(0.034 * (1 - t) ** 0.9 + 0.004)
    bm_ = bmesh.new()
    rings = []
    seg = 12
    for i, (c, r) in enumerate(zip(pts, rads)):
        d = (pts[min(i + 1, N - 1)] - pts[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized()
        b = d.cross(a)
        rings.append([bm_.verts.new(c + r * (math.cos(k * 2 * math.pi / seg) * a + math.sin(k * 2 * math.pi / seg) * b)) for k in range(seg)])
    for i in range(N - 1):
        for k in range(seg):
            bm_.faces.new([rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k]])
    bm_.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm_, faces=bm_.faces)
    add_part(bm_, material(name + "_tail", color=(0.16, 0.12, 0.1), rough=0.75), {"Hips": 1.0})
elif kind == "long_neck":
    LIFT = 0.20
    vg = {g.index: g.name.replace("mixamorig:", "") for g in body.vertex_groups}
    up = np.zeros(len(me.vertices))
    for v in me.vertices:
        w = {vg.get(g.group): g.weight for g in v.groups}
        up[v.index] = LIFT * (w.get("Head", 0) + w.get("HeadTop_End", 0) + 0.5 * w.get("Neck", 0))
    lz = inv.to_3x3() @ Vector((0, 0, 1))
    for v in me.vertices:
        v.co += lz * up[v.index]
    if me.shape_keys:
        for kb in me.shape_keys.key_blocks:
            for i, d in enumerate(kb.data):
                d.co += lz * up[i]
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    al = arm.matrix_world.inverted().to_3x3() @ Vector((0, 0, 1))
    eb = arm.data.edit_bones
    neck, head = eb["mixamorig:Neck"], eb["mixamorig:Head"]
    for b in [head] + list(head.children_recursive):
        b.head += al * LIFT
        b.tail += al * LIFT
    neck.tail = head.head
    bpy.ops.object.mode_set(mode="OBJECT")
    # (the neck is now twice its length: its skin stretches up with it)
else:
    raise SystemExit("unknown kind " + kind)

if PARTS:
    with bpy.context.temp_override(active_object=body, selected_editable_objects=[body] + PARTS, selected_objects=[body] + PARTS):
        bpy.ops.object.join()
    for mat in me.materials:
        if mat and mat.name.startswith(name) and kind in ("grey_marks", "black_eyes", "cyclops", "faceless"):
            if hasattr(mat, "surface_render_method"):
                mat.surface_render_method = "BLENDED"

# ————— export —————
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, slug, name + ".blend"))
for k in (me.shape_keys.key_blocks if me.shape_keys else []):
    k.value = 0.0
for o in scn.objects:
    o.select_set(o in (arm, body))
bpy.context.view_layer.objects.active = arm
out = os.path.join(OUT, name + ".glb")
bpy.ops.export_scene.gltf(
    filepath=out, export_format="GLB", use_selection=True,
    export_yup=True, export_apply=False, export_skins=True, export_morph=True, export_morph_normal=True,
    export_animations=False, export_materials="EXPORT", export_image_format="AUTO",
    export_cameras=False, export_lights=False)
for k in (1, 2, 3):
    src = os.path.join(PROJ, "assets", "characters", slug, "mumble_%d.mp3" % k)
    if os.path.exists(src):
        shutil.copy(src, os.path.join(OUT, "mumble_%d.mp3" % k))
print("ANOMALY", name, os.path.getsize(out) // 1024, "KB")
