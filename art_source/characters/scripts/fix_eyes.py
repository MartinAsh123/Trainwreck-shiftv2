"""Make a Tripo character's painted eyes and sculpted eye openings line up (see eye_fit.py), one of two ways:
    blender -b <slug>/<slug>.blend -P scripts/fix_eyes.py -- <slug> relief|geo|tex
relief  depth only: the opening's relief is set under the painted eye; x, z, UVs and texture untouched
        (the one in use: geo and tex left seams / tears).
geo  reshape the mesh round each eye: the opening's vertices (lid edges, socket) move and spread to lie
     under the painted eye, each re-pointed at the texture of where it now is; the image is untouched.
tex  repaint the texture round each eye: the painted eye moves and resizes into the opening (each
     texel there takes its colour from the paint's frame); the mesh is untouched.
Both fade out a few mm round the eye. -> <slug>/<slug>_eyefix_<mode>.blend (tex: and its texture)."""
import bpy, os, sys, json
import numpy as np
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import eye_fit

args = sys.argv[sys.argv.index("--") + 1:]
slug, mode = args[0], args[1]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
body = bpy.data.objects[slug + "_body"]
me = body.data
mw = body.matrix_world
face = eye_fit.Face(body, F["mouth"][1])
_fp = os.path.join(ROOT, "eye_frames.json")              # frames measured by eye, where there are
FRAMES = json.load(open(_fp)).get(slug) if os.path.exists(_fp) else None
eyes = [eye_fit.fit_eye(face, Vector(e), FRAMES) for e in F["eyes"]]
for e in eyes:
    print("EYE opening %.1f x %.1f mm, painted %.1f x %.1f mm, paint off by (%.1f, %.1f) mm" % (
        e["ow"] * 1000, e["oh"] * 1000, e["pw"] * 1000, e["ph"] * 1000,
        (e["pc"][0] - e["oc"][0]) * 1000, (e["pc"][1] - e["oc"][1]) * 1000))


def blur(G, sx, sz):
    """Gaussian blur of a grid (nan filled first with the column means)."""
    G = np.where(np.isnan(G), np.nanmean(G, axis=1, keepdims=True), G)
    for axis, s in ((0, sx), (1, sz)):
        r = int(3 * s)
        k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2)
        k /= k.sum()
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r, r)
        G = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), axis, np.pad(G, pad, mode="edge"))
    return G


GEO_FADE = 2.4         # the move fades out over ~1.5x the eye's size: long enough not to fold
RELIEF_K = float(args[2]) if len(args) > 2 else 0.5   # how much of the relief moves (all of it stretches the paint on the steep lid)
if mode == "relief":
    # Depth only: every vertex keeps its x, z and UVs (the texture and its mapping are untouched, so
    # nothing can tear or seam); the face's relief round each eye - the upper lid's step, the socket,
    # the lower lid's rim - is taken from the sculpted opening and set under the painted eye, and the
    # old opening is filled to the skin round it. Stops short of the brows.
    import bmesh
    src = body.copy()                                          # Tripo's own normals, to carry over (bmesh drops them)
    src.data = me.copy()
    src.modifiers.clear()
    bpy.context.scene.collection.objects.link(src)
    for _ in range(2):                                         # finer mesh round the eyes, shape unchanged
        bm = bmesh.new()
        bm.from_mesh(me)
        near = set()
        for v in bm.verts:
            p = mw @ v.co
            for e in eyes:
                d_front = eye_fit.bilerp(e, e["D"], p.x, p.z)
                if eye_fit.region_weight(e, p.x, p.z) > 0.05 and not np.isnan(d_front) and p.y <= d_front + 0.012:
                    near.add(v.index)
        edges = [ed for ed in bm.edges if all(v.index in near for v in ed.verts)]
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
        bm.to_mesh(me)
        bm.free()
        me.update()
    print("SUBDIVIDED: faces", len(me.polygons))
    for e in eyes:
        e["base"] = blur(e["D"], 0.004 / 0.0004, 0.004 / 0.00025)       # the face's smooth surface
        e["detail"] = e["D"] - e["base"]                                 # its relief
    dt = body.modifiers.new("normals", "DATA_TRANSFER")
    dt.object = src
    dt.use_loop_data = True
    dt.data_types_loops = {"CUSTOM_NORMAL"}
    dt.loop_mapping = "POLYINTERP_NEAREST"
    with bpy.context.temp_override(object=body, active_object=body):
        bpy.ops.object.modifier_move_to_index(modifier=dt.name, index=0)
        bpy.ops.object.modifier_apply(modifier=dt.name)
    bpy.data.objects.remove(src, do_unlink=True)
    loop_n = np.array([n.vector[:] for n in me.corner_normals])
    moved = np.zeros(len(me.vertices))
    shift = np.zeros(len(me.vertices))
    inv = mw.inverted()
    for v in me.vertices:
        p = mw @ v.co
        dy = 0.0
        for e in eyes:
            w = float(eye_fit.region_weight(e, p.x, p.z, 1.3))
            d_front = eye_fit.bilerp(e, e["D"], p.x, p.z)
            if w <= 0.001 or np.isnan(d_front) or p.y > d_front + 0.012:   # only the face, not the head behind
                continue
            sx, sz = eye_fit.paint_to_open(e, p.x, p.z)                  # where this place is, in the opening
            d_new = eye_fit.bilerp(e, e["detail"], sx, sz)
            d_old = eye_fit.bilerp(e, e["detail"], p.x, p.z)
            if np.isnan(d_new) or np.isnan(d_old):
                continue
            dy += w * RELIEF_K * (d_new - d_old)                         # (hidden vertices go along)
            moved[v.index] = max(moved[v.index], w)
        if moved[v.index] > 0:
            v.co = inv @ Vector((p.x, p.y + dy, p.z))
            shift[v.index] = abs(dy)
    me.update()
    # Normals: Tripo's where the depth hardly changed, the new surface's where it did.
    vn = np.array([n.vector[:] for n in me.vertex_normals])
    loops_v = np.array([lp.vertex_index for lp in me.loops])
    t = np.clip(shift[loops_v] / 0.0015, 0, 1)[:, None]
    nn = loop_n * (1 - t) + vn[loops_v] * t
    nn /= np.linalg.norm(nn, axis=1, keepdims=True)
    me.normals_split_custom_set(nn.tolist())
    print("RELIEF vertices", int((moved > 0).sum()))
elif mode == "geo":
    # First a finer mesh round the eyes (Tripo leaves ~150 vertices per eye; moved, they would
    # stretch the texture across big triangles): the faces there split in four, shape unchanged.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)

    def in_region(v):
        p = mw @ v.co
        for e in eyes:
            d_front = eye_fit.bilerp(e, e["D"], p.x, p.z)
            if eye_fit.region_weight(e, p.x, p.z, GEO_FADE) > 0.15 and not np.isnan(d_front) and p.y <= d_front + 0.012:
                return True
        return False

    near = {v.index for v in bm.verts if in_region(v)}
    edges = [ed for ed in bm.edges if any(v.index in near for v in ed.verts)]
    n0 = len(bm.faces)
    bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    print("SUBDIVIDED round the eyes: faces %d -> %d" % (n0, len(bm.faces)))
    bm.to_mesh(me)
    bm.free()
    me.update()
    face = eye_fit.Face(body, F["mouth"][1])
    # The eye's own vertices (lid edges, socket) move from the opening's frame into the paint's frame,
    # keeping their depth against the face's smooth surface there (a 4 mm blur of it).
    for e in eyes:
        e["base"] = blur(e["D"], 0.004 / 0.0004, 0.004 / 0.00025)
    loop_n = np.array([n.vector[:] for n in me.corner_normals])
    uvl = me.uv_layers.active
    uv0 = np.array([d.uv[:] for d in uvl.data])
    moved = np.zeros(len(me.vertices))
    inv = mw.inverted()
    P0 = [mw @ v.co for v in me.vertices]                      # where each vertex was
    for v in me.vertices:
        p = mw @ v.co
        dx = dz = dy = 0.0
        for e in eyes:                                          # (where both reach, the bridge of the nose, they add)
            w = float(eye_fit.region_weight(e, p.x, p.z, GEO_FADE))
            d_front = eye_fit.bilerp(e, e["D"], p.x, p.z)
            if w <= 0.001 or np.isnan(d_front) or p.y > d_front + 0.012:   # only the face, not the head behind
                continue
            # the move of the nearest point of the core: outside it the move only fades, it never grows
            # (it would, the frames being scaled, and then fold the skin where the fade ends)
            cx_, cz_ = eye_fit.core_point(e, p.x, p.z)
            sx, sz = eye_fit.open_to_paint(e, cx_, cz_)
            ex_, ez_ = w * (sx - cx_), w * (sz - cz_)
            b0, b1 = eye_fit.bilerp(e, e["base"], p.x, p.z), eye_fit.bilerp(e, e["base"], p.x + ex_, p.z + ez_)
            dx, dz = dx + ex_, dz + ez_
            dy += 0.0 if np.isnan(b0) or np.isnan(b1) else b1 - b0
            moved[v.index] = max(moved[v.index], w)
        if moved[v.index] > 0:
            v.co = inv @ Vector((p.x + dx, p.y + dy, p.z + dz))
    # Each face that moved takes its texture from where it now lies on the original face, all of its
    # corners through one original triangle (the one under its middle): Tripo's atlas cuts the face
    # into many small islands, and corners mapped one by one could fall into different ones.
    # (Redrawing the image under the moved faces instead was tried: blurrier, and Tripo's hidden faces
    # share texels with visible ones, so it tore.)
    from mathutils.geometry import barycentric_transform
    n_faces = 0
    for poly in me.polygons:
        if not any(moved[i] > 0 for i in poly.vertices):
            continue
        P = [mw @ me.vertices[i].co for i in poly.vertices]
        shift = max(Vector((q.x - P0[i].x, 0, q.z - P0[i].z)).length for q, i in zip(P, poly.vertices))
        if shift < 0.002:
            # Barely moved (the fade round the region): it keeps its own island, its texture just slid
            # back by its own mapping, so it meets its unmoved neighbours without a seam.
            A, B, C = (P0[i] for i in poly.vertices[:3])
            UA, UB, UC = (Vector((*uv0[li], 0.0)) for li in poly.loop_indices[:3])
            n = (B - A).cross(C - A)
            if abs(n.y) > 1e-9:
                for li, q in zip(poly.loop_indices, P):
                    y = A.y - (n.x * (q.x - A.x) + n.z * (q.z - A.z)) / n.y
                    uv = barycentric_transform(Vector((q.x, y, q.z)), A, B, C, UA, UB, UC)
                    uvl.data[li].uv = (uv.x, uv.y)
                n_faces += 1
            continue
        c = sum(P, Vector()) / len(P)
        h = face.bvh.ray_cast(Vector((c.x, face.front_y, c.z)), Vector((0, 1, 0)))
        if h[0] is None:
            continue
        T = face.tris[h[2]]
        A, B, C = (face.wv[i] for i in T.vertices)
        UA, UB, UC = (Vector((*uv0[li], 0.0)) for li in T.loops)
        n = (B - A).cross(C - A)
        if abs(n.y) < 1e-9:
            continue
        for li, q in zip(poly.loop_indices, P):
            y = A.y - (n.x * (q.x - A.x) + n.z * (q.z - A.z)) / n.y      # that triangle's plane, straight ahead of q
            uv = barycentric_transform(Vector((q.x, y, q.z)), A, B, C, UA, UB, UC)
            # the corner's own place, where it lies in the same island (close to that estimate)
            hq = face.bvh.ray_cast(Vector((q.x, face.front_y, q.z)), Vector((0, 1, 0)))
            if hq[0] is not None:
                Tq = face.tris[hq[2]]
                uq = barycentric_transform(hq[0], *(face.wv[i] for i in Tq.vertices), *(Vector((*uv0[l], 0.0)) for l in Tq.loops))
                if (uq - uv).length < 0.004:
                    uv = uq
            uvl.data[li].uv = (uv.x, uv.y)
        n_faces += 1
    me.update()
    # Normals: Tripo's own where nothing moved, the reshaped surface's where it did.
    vn = np.array([n.vector[:] for n in me.vertex_normals])
    loops_v = np.array([lp.vertex_index for lp in me.loops])
    t = np.clip(moved[loops_v] * 3.0, 0, 1)[:, None]
    nn = loop_n * (1 - t) + vn[loops_v] * t
    nn /= np.linalg.norm(nn, axis=1, keepdims=True)
    me.normals_split_custom_set(nn.tolist())
    print("MOVED vertices", int((moved > 0).sum()), "re-textured faces", n_faces)
else:
    # Texture warp ("tex"): the image round each eye is warped so the painted eye fills the sculpted
    # opening. Per axis a piecewise-linear map, identity at the region's edge: the opening's box maps
    # onto the paint's box (the whole painted eye, fitted into the opening), and the bands round it onto
    # the bands round the paint (the lid and cheek skin close over where the paint was). Only the
    # triangles seen from the front are redrawn (hidden socket faces can share texels with seen ones).
    # Mesh, UVs, brows untouched.
    def boxes(e):
        o = (e["oc"][0] - e["ow"] / 2, e["oc"][0] + e["ow"] / 2, e["oc"][1] - e["oh"] / 2, e["oc"][1] + e["oh"] / 2)
        q = (e["pc"][0] - e["pw"] / 2, e["pc"][0] + e["pw"] / 2, e["pc"][1] - e["ph"] / 2, e["pc"][1] + e["ph"] / 2)
        R = (min(o[0], q[0]) - 0.007, max(o[1], q[1]) + 0.007,
             min(o[2], q[2]) - 0.006, max(o[3], q[3]) + 0.004)       # up to 4 mm over the eye: not the brow
        return o, q, R

    def pw_map(v, r0, o0, o1, r1, q0, q1):
        """r0..o0..o1..r1  ->  r0..q0..q1..r1, linear in each piece."""
        if v <= r0 or v >= r1:
            return v
        if v < o0:
            return r0 + (v - r0) * (q0 - r0) / (o0 - r0)
        if v <= o1:
            return q0 + (v - o0) * (q1 - q0) / (o1 - o0)
        return q1 + (v - o1) * (r1 - q1) / (r1 - o1)

    def warp(e, x, z):
        o, q, R = e["boxes"]
        if not (R[0] < x < R[1] and R[2] < z < R[3]):
            return None
        return (pw_map(x, R[0], o[0], o[1], R[1], q[0], q[1]), pw_map(z, R[2], o[2], o[3], R[3], q[2], q[3]))

    for e in eyes:
        e["boxes"] = boxes(e)
    img = [n for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image][0]
    W, H = img.image.size
    out = face.px.copy()
    uvl = me.uv_layers.active
    done = 0
    for ti, tri in enumerate(face.tris):
        P = [face.wv[i] for i in tri.vertices]
        c = (P[0] + P[1] + P[2]) / 3
        hits = [e for e in eyes if e["boxes"][2][0] - 0.002 < c.x < e["boxes"][2][1] + 0.002 and e["boxes"][2][2] - 0.002 < c.z < e["boxes"][2][3] + 0.002]
        if not hits:
            continue
        h = face.bvh.ray_cast(Vector((c.x, face.front_y, c.z)), Vector((0, 1, 0)))
        if h[2] != ti:                                             # not seen from the front
            continue
        U = np.array([uvl.data[li].uv[:] for li in tri.loops]) * [W, H]
        x0, y0 = np.floor(U.min(0)).astype(int) - 1
        x1, y1 = np.ceil(U.max(0)).astype(int) + 1
        (ax, ay), (bx, by), (cx, cy) = U
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        for ty in range(max(y0, 0), min(y1 + 1, H)):
            for tx in range(max(x0, 0), min(x1 + 1, W)):
                px_, py_ = tx + 0.5, ty + 0.5
                l1 = ((by - cy) * (px_ - cx) + (cx - bx) * (py_ - cy)) / den
                l2 = ((cy - ay) * (px_ - cx) + (ax - cx) * (py_ - cy)) / den
                l3 = 1 - l1 - l2
                if min(l1, l2, l3) < -0.05:
                    continue
                q = P[0] * l1 + P[1] * l2 + P[2] * l3
                for e in hits:
                    src = warp(e, q.x, q.z)
                    if src is None:
                        continue
                    _, uv = face.hit(*src)
                    if uv is not None:
                        out[ty, tx] = face.color(uv, bilinear=True)
                        done += 1
    new = bpy.data.images.new(slug + "_albedo_eyefix", W, H)
    new.pixels[:] = out.ravel()
    new.filepath_raw = os.path.join(ROOT, slug, "textures", slug + "_albedo_eyefix.png")
    new.file_format = "PNG"
    new.save()
    img.image = new
    print("REPAINTED texels", done)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, slug, "%s_eyefix_%s.blend" % (slug, mode)))
print("SAVED", mode)
