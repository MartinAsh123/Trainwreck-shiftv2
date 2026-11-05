"""Give a Tripo character a talking face (shape keys), from its landmarks (<slug>_face.json).
    blender -b <slug>/<slug>.blend -P scripts/face_rig.py -- <slug>
Writes <slug>/<slug>_face.blend and renders previews/<slug>_faces.png (every shape key).

What it builds, all inside the body mesh (so one skinned mesh, one draw for the skin):
- the mouth opened along the lip seam (an edge path from corner to corner, split), a dark mouth
  cavity, upper and lower teeth and a tongue behind it, weighted to the Head bone;
- shape keys: jaw_open, lips_wide, lips_round, lower_lip_in, lips_press (building blocks),
  viseme_X/A/B/C/D/E/F/G/H (Preston Blair / Rhubarb mouth shapes), smile, sad, angry,
  surprised, suspicious.
The eyes are left exactly as Tripo made them (painted on the skin; nothing may move them, so no blink).
Face toward -Y, Z up, metres (prep_character.py scaled the character to its real height)."""
import bpy, bmesh, os, sys, json, math, heapq
import numpy as np
from mathutils import Vector, Matrix

slug = sys.argv[sys.argv.index("--") + 1:][0]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
arm = bpy.data.objects[slug + "_rig"]
body = bpy.data.objects[slug + "_body"]
me = body.data
M = Vector(F["mouth"])
NOSE = Vector(F["nose"])
CX = F["center_x"]
EYES = [Vector(e) for e in F["eyes"]]
CORN = [Vector(c) for c in F["mouth_corners"]]
HALF_W = max(abs(CORN[0].x - CX), abs(CORN[1].x - CX))


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0) if b != a else (1.0 if x >= a else 0.0)
    return t * t * (3 - 2 * t)


# ————— 1. open the mouth along the lip seam —————

def texture_stats():
    """Per-vertex texture luminance and saturation (max - min of RGB): hair is grey, skin and lips are not."""
    img = [n.image for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image][0]
    W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)[:, :, :3]
    uv = me.uv_layers.active.data
    acc = np.zeros(len(me.vertices)); sat = np.zeros(len(me.vertices)); cnt = np.zeros(len(me.vertices))
    for li, lp in enumerate(me.loops):
        u, v = uv[li].uv
        c = px[min(max(int(v * H), 0), H - 1), min(max(int(u * W), 0), W - 1)]
        acc[lp.vertex_index] += 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        sat[lp.vertex_index] += float(c.max() - c.min())
        cnt[lp.vertex_index] += 1
    return acc / np.maximum(cnt, 1), sat / np.maximum(cnt, 1)


lum, _ = texture_stats()
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
mw = body.matrix_world


def wco(v):
    return mw @ v.co


# Endpoints: the vertices nearest the mouth corners (on the front of the face).
def nearest(p, front=True):
    best, bd = None, 1e9
    for v in bm.verts:
        c = wco(v)
        if front and c.y > M.y + 0.03:
            continue
        d = (c - p).length
        if d < bd:
            best, bd = v, d
    return best


# (only among the vertices joined to the lips' own surface: a moustache or beard can be a separate shell)
m0 = nearest(Vector((CX, M.y, M.z)))
joined = {m0.index}
stack = [m0]
while stack:
    v = stack.pop()
    for e in v.link_edges:
        o = e.other_vert(v)
        if o.index not in joined and (wco(o) - M).length < 0.06:
            joined.add(o.index)
            stack.append(o)
_nearest = nearest


def nearest(p, front=True):
    best, bd = None, 1e9
    for i in joined:
        c = wco(bm.verts[i])
        if front and c.y > M.y + 0.03:
            continue
        d = (c - p).length
        if d < bd:
            best, bd = bm.verts[i], d
    return best


a0 = nearest(CORN[0])
a1 = nearest(CORN[1])
# Dijkstra along edges near the mouth: short, on the sculpted slit (the groove face_landmarks.py followed;
# Tripo's painted lip line can be mm off it), through dark texels.
if F.get("groove"):
    _G = np.array(F["groove"])
    def seam_z(x):
        return float(np.interp(x, _G[:, 0], _G[:, 1]))
else:
    def seam_z(x):
        return M.z
def seam_path(band, w_seam):
    region = {v.index for v in bm.verts if abs(wco(v).x - CX) < HALF_W + 0.012 and abs(wco(v).z - seam_z(wco(v).x)) < band and wco(v).y < M.y + 0.025}
    region |= {a0.index, a1.index}
    dist = {a0.index: 0.0}
    prev = {}
    pq = [(0.0, a0.index)]
    while pq:
        d, i = heapq.heappop(pq)
        if i == a1.index:
            return prev
        if d > dist.get(i, 1e9):
            continue
        v = bm.verts[i]
        for e in v.link_edges:
            o = e.other_vert(v)
            if o.index not in region:
                continue
            c = wco(o)
            cost = e.calc_length() * (1.0 + w_seam * abs(c.z - seam_z(c.x)) + 2.0 * float(lum[o.index]))
            nd = d + cost
            if nd < dist.get(o.index, 1e9):
                dist[o.index] = nd
                prev[o.index] = (i, e)
                heapq.heappush(pq, (nd, o.index))
    return None


prev = seam_path(0.02, 1500.0) or seam_path(0.035, 600.0)        # (wider, if the corners lie off the groove)
path_edges = []
i = a1.index
while i != a0.index:
    j, e = prev[i]
    path_edges.append(e)
    i = j
print("SEAM edges", len(path_edges))
# The seam as a polyline z(x), for telling upper lip from lower lip after the split.
seam_pts = sorted({(round(wco(v).x, 6), round(wco(v).z, 6)) for e in path_edges for v in e.verts})
SEAM_X = np.array([p[0] for p in seam_pts])
SEAM_Z = np.array([p[1] for p in seam_pts])
_src = body.copy()                                    # Tripo's normals, to carry over (the split drops them)
_src.data = me.copy()
_src.modifiers.clear()
bpy.context.scene.collection.objects.link(_src)
n_orig = len(bm.verts)
bmesh.ops.split_edges(bm, edges=path_edges)
# Behind that front edge Tripo's lips are solid, one closed mesh: open, the faces joining them stretched
# into spikes and curtains across the mouth. Through their inside (well behind the lips' front, between
# the slit's ends) the mesh is cut along the lip line's plane and the cut split, so the lips part there
# too. Only new vertices on existing faces: the shut mouth is unchanged.
_PZ = np.polyfit(SEAM_X, SEAM_Z, 1)
_CX0, _CX1 = SEAM_X.min() + 0.002, SEAM_X.max() - 0.002
_bco = np.array([tuple(mw @ v.co) for v in bm.verts])
def _front_ys(xs, zs_):
    out = np.empty(len(xs))
    for i in range(len(xs)):
        sel = (np.abs(_bco[:, 0] - xs[i]) < 0.004) & (np.abs(_bco[:, 2] - zs_[i]) < 0.006) & (_bco[:, 1] < M.y + 0.04)
        out[i] = _bco[sel, 1].min() if sel.any() else M.y
    return out
def _in_core(c):
    """Vertices (world coords, n x 3) inside the lips' solid core around the lip line."""
    pz = np.polyval(_PZ, c[:, 0])
    m = (c[:, 0] > _CX0) & (c[:, 0] < _CX1) & (np.abs(c[:, 2] - pz) < 0.012) & (c[:, 1] < M.y + 0.03)
    if m.any():
        idx = np.where(m)[0]
        m[idx] = c[idx, 1] > _front_ys(c[idx, 0], pz[idx]) + 0.0015
    return m
_core = _in_core(_bco)
bm.verts.ensure_lookup_table()
_reg = [f for f in bm.faces if all(_core[v.index] for v in f.verts if v.index < len(_core)) and all(v.index < len(_core) for v in f.verts)]
if _reg:
    _inv = mw.inverted_safe()
    _nw = Vector((-_PZ[0], 0.0, 1.0)).normalized()
    _pc = _inv @ Vector((CX, M.y, float(np.polyval(_PZ, CX))))
    _pn = (mw.to_3x3().transposed() @ _nw).normalized()
    _ge = {e for f in _reg for e in f.edges}
    _gv = {v for f in _reg for v in f.verts}
    _res = bmesh.ops.bisect_plane(bm, geom=list(_gv) + list(_ge) + _reg, dist=1e-7, plane_co=_pc, plane_no=_pn)
    _cut = [e for e in _res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    bmesh.ops.split_edges(bm, edges=_cut)
    print("CORE cut faces", len(_reg), "edges", len(_cut))
bm.to_mesh(me)
bm.free()
me.update()
_dt = body.modifiers.new("normals", "DATA_TRANSFER")
_dt.object = _src
_dt.use_loop_data = True
_dt.data_types_loops = {"CUSTOM_NORMAL"}
_dt.loop_mapping = "POLYINTERP_NEAREST"
with bpy.context.temp_override(object=body, active_object=body):
    bpy.ops.object.modifier_move_to_index(modifier=_dt.name, index=0)
    bpy.ops.object.modifier_apply(modifier=_dt.name)
bpy.data.objects.remove(_src, do_unlink=True)

# Which side of the seam each vertex is on: compared with the seam polyline at the vertex's own x
# (the seam zigzags between the mesh's rows); the doubled seam vertices by the side their faces lie on.
co = np.array([mw @ v.co for v in me.vertices])
nv = len(me.vertices)
zs = np.interp(co[:, 0], SEAM_X, SEAM_Z)
inside = (co[:, 0] > SEAM_X.min() - 1e-4) & (co[:, 0] < SEAM_X.max() + 1e-4) & (co[:, 1] < M.y + 0.03)
lower = np.where(inside, co[:, 2] < zs - 1e-5, co[:, 2] < M.z)
vf = [[] for _ in range(nv)]
for poly in me.polygons:
    c = mw @ poly.center
    for k in poly.vertices:
        vf[k].append(c)
on_seam = inside & (np.abs(co[:, 2] - zs) <= 1e-4)
for k in np.where(on_seam)[0]:
    if vf[k]:
        lower[k] = float(np.mean([c.z for c in vf[k]])) < zs[k]
# Then flood from the chin through the lower lip (the slit keeps it from crossing to the upper lip;
# the flood may not pass the ends of the slit, so it cannot go round the corners).
adj = [[] for _ in range(nv)]
for e in me.edges:
    i0, i1 = e.vertices
    adj[i0].append(i1)
    adj[i1].append(i0)
lane = (co[:, 0] > SEAM_X.min() + 5e-4) & (co[:, 0] < SEAM_X.max() - 5e-4) & (co[:, 2] > M.z - 0.05) & (co[:, 2] < M.z + 0.025) & (co[:, 1] < M.y + 0.03)
seeds = [i for i in np.where(lane & (co[:, 2] < M.z - 0.02))[0]]
reached = np.zeros(nv, bool)
reached[seeds] = True
stack = list(seeds)
while stack:
    i = stack.pop()
    for j in adj[i]:
        if lane[j] and not reached[j] and not (on_seam[j] and not lower[j]):
            reached[j] = True
            stack.append(j)
# (On 26 of the cast the flood found a way round the seam and climbed the philtrum to the nose: jaw_open
# dragged the shut mouth down whole.)
# The flood decides only right at the slit (its path zigzags between the mesh's rows); off it, which
# side of the slit's line the vertex is on.
lower = np.where(lane, np.where(inside & (np.abs(co[:, 2] - zs) > 0.0015), co[:, 2] < zs, reached), lower)
# In the cut core the plane decides (on it: the side the vertex's faces lie on).
_core2 = lane & _in_core(co)
_pz2 = np.polyval(_PZ, co[:, 0])
lower = np.where(_core2, co[:, 2] < _pz2, lower)
for k in np.where(_core2 & (np.abs(co[:, 2] - _pz2) < 2e-5))[0]:
    if vf[k]:
        lower[k] = float(np.mean([c.z for c in vf[k]])) < _pz2[k]
print("LOWER", int(lower[inside].sum()), "UPPER", int((~lower)[inside].sum()), "ON SEAM", int(on_seam.sum()), "reached", int(reached.sum()))
# Tripo's lips are joined behind the slit too (the split only parts their front edges): the few faces in
# there with corners on both lips stretched across the opening as the mouth opened, spikes between the
# teeth. Each is cut loose at its odd corners (new vertices in the same places, so the shut mouth is
# exactly as before) and goes wholly with the lip most of it is on.
_src = body.copy()                                    # (the normals, carried over again after)
_src.data = me.copy()
_src.modifiers.clear()
bpy.context.scene.collection.objects.link(_src)
_bm = bmesh.new()
_bm.from_mesh(me)
_bm.verts.ensure_lookup_table()
bridges = [f for f in _bm.faces if all(lane[v.index] for v in f.verts) and len({bool(lower[v.index]) for v in f.verts}) == 2]
_new_lower = []
for f in bridges:
    vs = list(f.verts)
    side = sum(bool(lower[v.index]) for v in vs) * 2 >= len(vs)
    for v in vs:
        if bool(lower[v.index]) != side:
            nv_ = bmesh.utils.face_vert_separate(f, v)
            if nv_ != v:
                _new_lower.append(side)
_bm.to_mesh(me)
_bm.free()
me.update()
_dt = body.modifiers.new("normals", "DATA_TRANSFER")
_dt.object = _src
_dt.use_loop_data = True
_dt.data_types_loops = {"CUSTOM_NORMAL"}
_dt.loop_mapping = "POLYINTERP_NEAREST"
with bpy.context.temp_override(object=body, active_object=body):
    bpy.ops.object.modifier_move_to_index(modifier=_dt.name, index=0)
    bpy.ops.object.modifier_apply(modifier=_dt.name)
bpy.data.objects.remove(_src, do_unlink=True)
lower = np.concatenate([lower, np.array(_new_lower, bool)])
adj = [[] for _ in range(len(me.vertices))]
for e in me.edges:
    adj[e.vertices[0]].append(e.vertices[1])
    adj[e.vertices[1]].append(e.vertices[0])
print("BRIDGES cut loose", len(bridges), "new verts", len(_new_lower))

# ————— 2. mouth cavity, teeth, tongue (joined into the body, weighted to the head) —————

def add_part(name, bm2, col):
    mesh = bpy.data.meshes.new(name)
    bm2.to_mesh(mesh)
    bm2.free()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(o)
    mname = slug + "_" + name.split("_seal")[0]                # (the seals share the cavity's material)
    m = bpy.data.materials.get(mname) or bpy.data.materials.new(mname)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*col, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.35 if not name.startswith("mouth_cavity") else 0.8
    mesh.materials.append(m)
    return o


def ellipsoid(c, r, segs=16, rings=10, inside=False, keep=lambda p: True):
    b = bmesh.new()
    bmesh.ops.create_uvsphere(b, u_segments=segs, v_segments=rings, radius=1.0)
    for v in b.verts:
        v.co = Vector((c.x + v.co.x * r[0], c.y + v.co.y * r[1], c.z + v.co.z * r[2]))
    gone = [v for v in b.verts if not keep(v.co)]
    bmesh.ops.delete(b, geom=gone, context="VERTS")
    if inside:
        bmesh.ops.reverse_faces(b, faces=b.faces)
    return b


depth = 0.013                                       # the teeth stand this far behind the skin
_co0 = np.array([mw @ v.co for v in me.vertices])
n_skin0 = len(_co0)
# The lips' own surface (a moustache or beard over them can be a separate shell, standing in front):
# the original vertices joined to the lips, and the seam's doubles (added at the end by the split).
_lips = np.zeros(n_skin0, bool)
_lips[[i for i in joined if i < n_skin0]] = True
_lips[n_orig:] = True


def skin_y(x, z):
    """Depth (Blender y) of the face's front surface at (x, z): the most forward skin vertex near it."""
    sel = (np.abs(_co0[:, 0] - x) < 0.004) & (np.abs(_co0[:, 2] - z) < 0.006) & (_co0[:, 1] < M.y + 0.04) & _lips
    return float(_co0[sel, 1].min()) if sel.any() else M.y
front_y = skin_y(CX, M.z)
cav_c = Vector((CX, front_y + 0.034, M.z - 0.004))
cavity = add_part("mouth_cavity", ellipsoid(cav_c, (HALF_W * 0.95, 0.03, 0.022), 20, 12, inside=True,
                                            keep=lambda p: p.y > skin_y(p.x, p.z) + 0.004), (0.1, 0.025, 0.025))


def slit_back(x):
    """The deepest skin (Blender y) along the sculpted slit near x: where the lips meet."""
    sel = (np.abs(_co0[:, 0] - x) < 0.004) & (np.abs(_co0[:, 2] - seam_z(x)) < 0.0025) & (_co0[:, 1] < M.y + 0.03)
    sel &= _lips
    return float(_co0[sel, 1].max()) if sel.any() else M.y


def teeth_arc(dz, h, name):
    """Teeth along the slit (dz: their middle's height off it), behind the lips."""
    b = bmesh.new()
    n = 14
    rows = []
    for k in range(n + 1):
        t = (k / n - 0.5) * 2.0
        x = CX + t * HALF_W * 0.8
        zc = seam_z(x) + dz
        y = max(skin_y(x, zc + h * 0.5), skin_y(x, zc - h * 0.5)) + depth
        y = max(y, slit_back(x) + 0.004)                     # behind the slit's bottom: unseen at rest
        rows.append([b.verts.new((x, y, zc + h * 0.5)), b.verts.new((x, y, zc - h * 0.5))])
    for k in range(n):
        b.faces.new((rows[k][0], rows[k + 1][0], rows[k + 1][1], rows[k][1]))
    return b


# (clear of the slit: some sculpts leave it a real hole, and at rest it must show the dark between the
# teeth, not their edges)
teeth_up = add_part("teeth_upper", teeth_arc(0.0062, 0.009, "u"), (0.86, 0.82, 0.72))
teeth_lo = add_part("teeth_lower", teeth_arc(-0.0068, 0.008, "l"), (0.82, 0.78, 0.68))
tongue = add_part("tongue", ellipsoid(Vector((CX, front_y + 0.03, M.z - 0.013)), (HALF_W * 0.62, 0.02, 0.005), 14, 8),
                  (0.55, 0.22, 0.22))


def seal(up, name):
    """A dark strip just behind the slit (upper half stays, lower half goes with the jaw): at rest the slit
    (a real hole in some sculpts) shows it, not the teeth; open, the two halves part."""
    b = bmesh.new()
    n = 24
    rows = []
    for k in range(n + 1):
        t = (k / n - 0.5) * 2.0
        x = (SEAM_X.min() + SEAM_X.max()) / 2 + t * ((SEAM_X.max() - SEAM_X.min()) / 2 - 0.0025)
        z0 = seam_z(x)
        y = slit_back(x) + 0.0015
        hh = 0.0028 * math.sqrt(max(1.0 - t * t, 0.0))          # tapering to nothing at the corners
        za, zb = (z0 + hh, z0) if up else (z0, z0 - hh)
        rows.append([b.verts.new((x, y, za)), b.verts.new((x, y, zb))])
    for k in range(n):
        b.faces.new((rows[k][0], rows[k + 1][0], rows[k + 1][1], rows[k][1]))
    bmesh.ops.reverse_faces(b, faces=b.faces)                   # (facing the viewer, -Y)
    return b


seal_up = add_part("mouth_cavity_sealu", seal(True, "u"), (0.1, 0.025, 0.025))
seal_lo = add_part("mouth_cavity_seall", seal(False, "l"), (0.1, 0.025, 0.025))
parts = [cavity, teeth_up, teeth_lo, tongue, seal_up, seal_lo]
lower_parts = {teeth_lo.name, tongue.name}
# Safeguard: no part of the mouth's inside may show through the skin at rest (a chin, a lip corner, a
# moustache's underside): any part vertex seen, from where a player's eyes can be (40 cm off, below,
# level, above, to the sides), goes back along that view until hidden.
from mathutils.bvhtree import BVHTree
_bvh = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [p.vertices[:] for p in me.polygons])
pushed = 0
EYES_AT = [Vector((CX + dx, M.y - 0.4, M.z + dz)) for dx in (-0.15, 0.0, 0.15) for dz in (-0.2, -0.1, 0.0, 0.12)]
for _ in range(4):                                             # (a push can bare another view)
    moved_any = False
    for o in [cavity, teeth_up, teeth_lo, tongue]:
        for v in o.data.vertices:
            q = o.matrix_world @ v.co
            for c in EYES_AT:
                d = (q - c).normalized()
                dist = (q - c).length
                h = _bvh.ray_cast(c, d, dist + 0.002)
                if h[0] is None or (h[0] - c).length > dist - 0.0015:   # seen from c: back, along that view
                    q = q + d * 0.002
                    pushed += 1
                    moved_any = True
            v.co = o.matrix_world.inverted() @ q
    if not moved_any:
        break
print("PARTS pushed behind the skin:", pushed)
head_gi = body.vertex_groups["mixamorig:Head"]
n_body = len(me.vertices)
part_ranges = []
for o in parts:
    vg = o.vertex_groups.new(name="mixamorig:Head")
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
for o in parts:
    part_ranges.append((o.name, len(o.data.vertices)))
with bpy.context.temp_override(active_object=body, selected_editable_objects=[body] + parts, selected_objects=[body] + parts):
    bpy.ops.object.join()
me = body.data
co = np.array([mw @ v.co for v in me.vertices])
lower = np.concatenate([lower, np.zeros(len(me.vertices) - n_body, bool)])
start = n_body
for name, cnt in part_ranges:
    if any(name.startswith(p) for p in ("teeth_lower", "tongue", "mouth_cavity_seall")):
        lower[start:start + cnt] = True
    start += cnt
is_part = np.zeros(len(me.vertices), bool)
is_part[n_body:] = True

# The lips' inner faces (inside the slit, turned up or down toward each other): some sculpts leave the slit
# a real gap, and these faces, painted as skin, show through it as a pale band. They take a dark inner-lip
# material (they show only as the shadowed line between the lips).
_mfp = os.path.join(ROOT, "mouth_frames.json")
INNER_DARK = bool((json.load(open(_mfp)).get(slug) or {}).get("inner_dark")) if os.path.exists(_mfp) else False
_inner = bpy.data.materials.get(slug + "_inner_lip") or bpy.data.materials.new(slug + "_inner_lip")
_inner.use_nodes = True
_inner.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.022, 0.004, 0.0035, 1)   # (linear: dark red)
_inner.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.5
me.materials.append(_inner)
_mi = len(me.materials) - 1
_rot = mw.to_3x3()
n_inner = 0
for poly in me.polygons:
    if not INNER_DARK or poly.material_index != 0 or any(v >= n_body for v in poly.vertices):
        continue                                                # (only where asked: a slit sculpted as a gap)
    c = mw @ poly.center
    if abs(c.x - CX) > HALF_W + 0.002 or abs(c.z - seam_z(c.x)) > 0.003:
        continue
    nrm = _rot @ poly.normal
    if abs(nrm.z) < 0.55 or c.y < skin_y(c.x, c.z) + 0.0008:            # turned up/down, and behind the lips' front
        continue
    poly.material_index = _mi
    n_inner += 1
print("INNER LIP faces", n_inner)

_, sat_all = texture_stats()
hair = np.zeros(len(me.vertices))
hair[:n_body] = (sat_all[:n_body] < 0.12).astype(float)
for _ in range(2):                                   # soften its edge over the neighbouring vertices
    hair[:n_body] = np.array([max(hair[i], 0.5 * max((hair[j] for j in adj[i]), default=0.0)) for i in range(n_body)])
print("HAIR verts", int((hair > 0.9).sum()))

# ————— 3. shape keys —————

if not me.shape_keys:
    body.shape_key_add(name="Basis", from_mix=False)
BASE = co.copy()
inv = mw.inverted()


def key(name, disp):
    sk = body.shape_key_add(name=name, from_mix=False)
    for k in range(len(me.vertices)):
        d = disp[k]
        if d[0] != 0.0 or d[1] != 0.0 or d[2] != 0.0:
            sk.data[k].co = inv @ Vector(BASE[k] + d)
    return sk


def gauss(p, c, r):
    return np.exp(-np.sum(((p - np.array(c)) / r) ** 2, axis=1))


rel = BASE - np.array([CX, M.y, M.z])
ax = np.abs(rel[:, 0])
face_front = BASE[:, 1] < M.y + 0.06
# Jaw: everything below the seam on the lower face (lower lip, chin, lower teeth, tongue) turns about
# a hinge near the ears; it fades out toward the cheeks, the jaw corners and down the neck.
hinge = np.array([CX, M.y + 0.085, M.z + 0.03])
w_jaw = np.where(lower, 1.0, 0.0) * face_front
w_jaw *= 1.0 - np.clip((ax - HALF_W - 0.004) / 0.02, 0, 1)
w_jaw *= 1.0 - 0.85 * hair * (ax > HALF_W * 0.6)
w_jaw *= 1.0 - np.clip((M.z - 0.055 - BASE[:, 2]) / 0.03, 0, 1)
w_jaw = np.where(is_part & lower, 1.0, w_jaw)
w_jaw = np.where(is_part & ~lower, 0.0, w_jaw)


def jaw_disp(angle, w):
    c, s = math.cos(angle), math.sin(angle)
    p = BASE - hinge
    rot = np.stack([p[:, 0], p[:, 1] * c - p[:, 2] * s, p[:, 1] * s + p[:, 2] * c], axis=1)
    return (rot - p) * w[:, None]


JAW = math.radians(10.0)
d_jaw = jaw_disp(JAW, w_jaw)
# Upper lip lifts a hair when the mouth opens.
w_up = (~lower) * face_front * np.exp(-((rel[:, 2] - 0.004) / 0.006) ** 2) * (1 - np.clip((ax - HALF_W) / 0.012, 0, 1))
w_up = np.where(is_part, 0.0, w_up)
d_jaw[:, 2] += 0.0018 * w_up
key("jaw_open", d_jaw)

w_corner = np.zeros(len(BASE))
for cc in CORN:
    w_corner += gauss(BASE, cc, np.array([0.016, 0.02, 0.012]))
w_corner = np.where(is_part, 0.0, w_corner) * face_front
sx = np.sign(rel[:, 0])
d = np.zeros_like(BASE)
d[:, 0] = sx * 0.006 * w_corner
d[:, 1] = 0.001 * w_corner
key("lips_wide", d)

w_lips = face_front * np.exp(-(rel[:, 0] / (HALF_W * 1.2)) ** 2 - (rel[:, 2] / 0.012) ** 2) * (BASE[:, 1] < M.y + 0.012)
w_lips = np.where(is_part, 0.0, w_lips)
d = np.zeros_like(BASE)
d[:, 0] = -sx * 0.008 * w_corner
d[:, 1] = -0.006 * w_lips - 0.002 * w_corner
key("lips_round", d)

w_ll = w_lips * lower
d = np.zeros_like(BASE)
d[:, 2] = 0.0035 * w_ll
d[:, 1] = 0.004 * w_ll
key("lower_lip_in", d)

d = np.zeros_like(BASE)
d[:, 2] = 0.0012 * w_ll - 0.0008 * w_lips * (~lower)
key("lips_press", d)

# Visemes: blends of the building blocks, baked as their own keys.
blocks = {"jaw": d_jaw, "wide": None, "round": None, "lli": None, "press": None}
blocks["wide"] = np.array([sk.co for sk in me.shape_keys.key_blocks["lips_wide"].data]) if False else None


def block(name):
    kb = me.shape_keys.key_blocks[name]
    arr = np.array([mw @ v.co for v in kb.data])
    return arr - BASE


B = {n: block(n) for n in ("jaw_open", "lips_wide", "lips_round", "lower_lip_in", "lips_press")}
VIS = {
    "viseme_X": {},
    "viseme_A": {"lips_press": 1.0},
    "viseme_B": {"jaw_open": 0.22, "lips_wide": 0.7},
    "viseme_C": {"jaw_open": 0.5, "lips_wide": 0.35},
    "viseme_D": {"jaw_open": 1.0, "lips_wide": 0.15},
    "viseme_E": {"jaw_open": 0.42, "lips_round": 0.55},
    "viseme_F": {"jaw_open": 0.15, "lips_round": 1.0},
    "viseme_G": {"lower_lip_in": 1.0, "jaw_open": 0.08},
    "viseme_H": {"jaw_open": 0.55, "lips_wide": 0.2},
}
for name, mix in VIS.items():
    d = np.zeros_like(BASE)
    for n, wgt in mix.items():
        d += B[n] * wgt
    key(name, d)

# Nothing that moves the skin may reach the painted eyes (their texture would slide onto the lids).
eye_still = np.ones(len(BASE))
for e in EYES:
    near = (np.abs(BASE[:, 0] - e[0]) < 0.026) & (np.abs(BASE[:, 2] - e[2]) < 0.016)
    eye_still *= np.where(near, np.clip((np.abs(BASE[:, 2] - e[2]) - 0.009) / 0.006, 0, 1), 1.0)


def region(c, rad):
    return gauss(BASE, c, np.array(rad)) * (~is_part) * eye_still


brow = [np.array([e[0], e[1] + 0.006, e[2] + 0.022]) for e in EYES]
brow_in = [np.array([CX + (e[0] - CX) * 0.35, e[1] - 0.002, e[2] + 0.02]) for e in EYES]
w_brow = sum(region(b, [0.03, 0.02, 0.013]) for b in brow)
w_brow_in = sum(region(b, [0.016, 0.02, 0.012]) for b in brow_in)
cheek = sum(region(np.array([c[0] + (c[0] - CX) * 0.25, c[1] + 0.004, c[2] + 0.02]), [0.022, 0.02, 0.02]) for c in CORN)
lid_lo = sum(region(np.array([e[0], e[1], e[2] - 0.009]), [0.016, 0.015, 0.006]) for e in EYES)

d = np.zeros_like(BASE)                                      # smile
d[:, 0] = sx * 0.006 * w_corner
d[:, 1] = -0.0005 * w_corner
d[:, 2] = 0.007 * w_corner + 0.004 * cheek
key("smile", d)
d = np.zeros_like(BASE)                                      # sad
d[:, 2] = -0.007 * w_corner + 0.0065 * w_brow_in - 0.0015 * w_brow
key("sad", d)
d = np.zeros_like(BASE)                                      # angry
d[:, 2] = -0.0075 * w_brow_in - 0.0025 * w_corner
d[:, 0] = -sx * 0.003 * w_brow_in
d[:, 1] = -0.001 * w_brow_in
d += B["lips_press"] * 1.0
key("angry", d)
d = np.zeros_like(BASE)                                      # surprised
d[:, 2] = 0.009 * w_brow + 0.004 * w_brow_in
d += B["jaw_open"] * 0.45 + B["lips_round"] * 0.3
key("surprised", d)
d = np.zeros_like(BASE)                                      # suspicious: one brow down, that eye narrowed
left = BASE[:, 0] > CX
d[:, 2] = np.where(left, -0.006 * w_brow, 0.0045 * w_brow)
d[:, 0] = sx * 0.002 * w_corner * left
d[:, 2] += 0.002 * w_corner * left
key("suspicious", d)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, slug, slug + "_face.blend"))
print("KEYS", [k.name for k in me.shape_keys.key_blocks])
