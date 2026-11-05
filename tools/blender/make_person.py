# make_person.py — a man in his thirties in 1930s winter clothes, for the stations and towns.
#   blender --background --factory-startup --python tools/blender/make_person.py -- <out.glb> [preview.png]
# Needs the MPFB extension (MakeHuman for Blender, GPL tool) and the MakeHuman system asset pack
# in MPFB's user data; every asset used is CC0 (body, skin, eyes, hair, clothes).
#   body:    male, about 35, average build, caucasian, 1.70 m; clean-shaven
#   hair:    short01, tinted black
#   clothes: padded field jacket and shirt (male_casualsuit05) with the jeans turned to charcoal wool
#            trousers, black boots (shoes03); modelled here: a wool flat cap, a knitted scarf and
#            leather gloves, all skinned to the same rig
#   rig:     MPFB "game_engine" skeleton (Unreal-style bone names), for animation in Godot
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
PREVIEW = argv[1] if len(argv) > 1 else ""
HEIGHT = 1.70

bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)

info = HumanService._create_default_human_info_dict()
info["name"] = "Person"
info["phenotype"].update({"gender": 1.0, "age": 0.578, "muscle": 0.55, "weight": 0.52, "proportions": 0.6,
                          "height": 0.42, "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}})
info["rig"] = "game_engine"
info["eyes"] = "high-poly.mhclo"
info["eyebrows"] = "eyebrow001.mhclo"
info["eyelashes"] = "eyelashes01.mhclo"
info["teeth"] = "teeth_base.mhclo"
info["tongue"] = "tongue01.mhclo"
info["hair"] = "short01.mhclo"
info["clothes"] = ["male_casualsuit05.mhclo", "shoes03.mhclo"]
info["skin_mhmat"] = "young_caucasian_male.mhmat"
info["skin_material_type"] = "MAKESKIN"
info["eyes_material_type"] = "MAKESKIN"
settings = HumanService.get_default_deserialization_settings()
settings["subdiv_levels"] = 0
settings["mask_helpers"] = True
body = HumanService.deserialize_from_dict(info, settings)
rig = body.parent
bpy.context.view_layer.update()

# Remove the helper geometry (MakeHuman's joint/tights helpers) for good: masked anyway.
bpy.context.view_layer.objects.active = body
# Bake the phenotype (MakeHuman's targets are shape keys) into the mesh.
for o in [body] + [c for c in bpy.data.objects if c.type == "MESH" and c.data.shape_keys and c != body]:
    if not o.data.shape_keys:
        continue
    mix = o.shape_key_add(name="mix", from_mix=True)
    coords = [p.co.copy() for p in mix.data]
    o.shape_key_clear()
    for v, co in zip(o.data.vertices, coords):
        v.co = co
bpy.context.view_layer.objects.active = body
for m in list(body.modifiers):
    if m.type == "MASK":
        bpy.ops.object.modifier_apply(modifier=m.name)

children = [o for o in bpy.data.objects if o.type == "MESH"]
print("[person] objects:", [(o.name, len(o.data.vertices)) for o in children])


def world_bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


# ————— scale to 1.70 m (barefoot crown height) —————
lo, hi = world_bbox([body])
# MPFB stands the bare feet on z = 0; the feet under the boots are masked away, so measure the crown.
k = HEIGHT / hi.z
rig.scale = (rig.scale.x * k, rig.scale.y * k, rig.scale.z * k)
bpy.context.view_layer.update()
print("[person] crown", hi.z, "-> scale", k)


def find(pattern):
    for o in bpy.data.objects:
        if o.type == "MESH" and pattern in o.name.lower():
            return o
    return None


# ————— textures: black hair, wool trousers —————
def image_of(obj):
    for slot in obj.material_slots:
        if slot.material and slot.material.use_nodes:
            for n in slot.material.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and "normal" not in n.image.name.lower():
                    return n.image
    return None


def edit_pixels(img, fn, name):
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    px = fn(px)
    new = bpy.data.images.new(name, w, h, alpha=True)
    new.pixels = px.ravel()
    new.file_format = "PNG"
    # Re-point every texture node that used the old image.
    for m in bpy.data.materials:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image == img:
                    n.image = new
    return new


hair = find("short01")
if hair and image_of(hair):
    def black(px):
        lum = px[..., :3].mean(axis=2, keepdims=True)
        px[..., :3] = np.clip(lum * 0.28, 0, 1) * np.array([1.0, 0.95, 0.9])
        return px
    edit_pixels(image_of(hair), black, "hair_black")

# Eyebrows and eyelashes: their textures carry only the alpha; give them a near-black colour.
for part in ("eyebrow001", "eyelashes01"):
    o = find(part)
    if o and image_of(o):
        def dark(px):
            px[..., 0] = 0.035
            px[..., 1] = 0.028
            px[..., 2] = 0.022
            return px
        edit_pixels(image_of(o), dark, part + "_dark")

suit = find("casualsuit05")


def uv_mask(obj, keep_face, w, h):
    """Texture-space mask of the faces of `obj` for which keep_face(world centre) is true."""
    mask = np.zeros((h, w), dtype=bool)
    uv = obj.data.uv_layers.active.data
    mw = obj.matrix_world
    for p in obj.data.polygons:
        if not keep_face(mw @ p.center):
            continue
        pts = [uv[li].uv for li in p.loop_indices]
        for k in range(1, len(pts) - 1):
            tri = [pts[0], pts[k], pts[k + 1]]
            xs = [q.x * w for q in tri]
            ys = [q.y * h for q in tri]
            x0, x1 = max(int(min(xs)) - 1, 0), min(int(max(xs)) + 2, w)
            y0, y1 = max(int(min(ys)) - 1, 0), min(int(max(ys)) + 2, h)
            if x1 <= x0 or y1 <= y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = [(xs[i], ys[i]) for i in range(3)]
            d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) < 1e-9:
                continue
            l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / d
            l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / d
            inside = (l1 >= -0.02) & (l2 >= -0.02) & (1 - l1 - l2 >= -0.02)
            mask[y0:y1, x0:x1] |= inside
    return mask


if suit and image_of(suit):
    img = image_of(suit)
    lo_b, hi_b = world_bbox([body])
    waist = hi_b.z * 0.565
    w_, h_ = img.size
    legs = uv_mask(suit, lambda c: c.z < waist, w_, h_)

    def wool(px):
        r, g, b = px[..., 0], px[..., 1], px[..., 2]
        lum = 0.3 * r + 0.59 * g + 0.11 * b
        # Charcoal wool: the denim's light and shade kept, but compressed and greyed, the worn
        # pale patches flattened out; a fine weave noise.
        denim = legs & (b > r + 0.012) & (b >= g - 0.01)     # the jacket's hem (grey-green) shares the UV area
        base = np.clip(0.055 + (lum - lum[denim].mean()) * 0.18 + 0.02, 0.03, 0.12)
        noise = (np.random.default_rng(3).random(lum.shape) - 0.5) * 0.012
        for c, tint in enumerate((1.05, 1.0, 0.94)):
            px[..., c] = np.where(denim, np.clip(base * tint + noise, 0, 1), px[..., c])
        return px
    edit_pixels(img, wool, "suit_wool")


# ————— modelled garments, skinned like the body —————
def make_mat(name, color, rough, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if sheen:
        b.inputs["Sheen Weight"].default_value = sheen
    return m


def shell(src, name, keep, offset, mat, thickness=0.004):
    """A garment cut from `src` (keeping its weights): the faces whose every vertex passes keep(co,
    v_index), pushed `offset` m out along the normals, given a little thickness."""
    o = src.copy()
    o.data = src.data.copy()
    o.name = name
    for m in list(o.modifiers):
        if m.type not in ("ARMATURE",):
            o.modifiers.remove(m)
    o.shape_key_clear() if o.data.shape_keys else None
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    mw = o.matrix_world
    dead = [f for f in bm.faces if not all(keep(mw @ v.co, v.index) for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * (offset / max(mw.to_scale().x, 1e-6))
    bm.to_mesh(o.data)
    bm.free()
    o.data.materials.clear()
    o.data.materials.append(mat)
    if thickness > 0:
        s = o.modifiers.new("Solidify", "SOLIDIFY")
        s.thickness = thickness / max(mw.to_scale().x, 1e-6)
        s.offset = 1.0
        o.modifiers.move(len(o.modifiers) - 1, 0)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def weight_of(obj, v_index, names):
    tot = 0.0
    v = obj.data.vertices[v_index]
    for g in v.groups:
        gn = obj.vertex_groups[g.group].name.lower()
        if any(n in gn for n in names):
            tot += g.weight
    return tot


lo, hi = world_bbox([body])
lo.z = 0.0
H = hi.z

# Gloves: the hands and a little of the wrist.
HAND = ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_")
leather = make_mat("gloves_leather", (0.055, 0.035, 0.025), 0.5)
gloves = shell(body, "Gloves", lambda co, i: weight_of(body, i, HAND) > 0.35, 0.0035, leather, 0.002)

def skinned(name, bm, mat, groups):
    """A mesh object from bmesh `bm` (world space), weighted to `groups` {bone: weight} and deformed
    by the rig like the body."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    for g, wgt in groups.items():
        vg = o.vertex_groups.new(name=g)
        vg.add(list(range(len(me.vertices))), wgt, "REPLACE")
    o.parent = rig
    o.matrix_parent_inverse = rig.matrix_world.inverted()
    am = o.modifiers.new("Armature", "ARMATURE")
    am.object = rig
    return o


def bone_name(*cands):
    names = {b.name.lower(): b.name for b in rig.data.bones}
    for c in cands:
        if c in names:
            return names[c]
    return rig.data.bones[0].name


def weight_of_pt(p):
    return True


def ring_fit(z0, z1, pred):
    """Centre (x, y) and half extents (rx, ry) of the body's cross-section between heights z0..z1."""
    pts = [body.matrix_world @ v.co for v in body.data.vertices]
    sel = [p for p in pts if z0 < p.z < z1 and pred(p)]
    xs = [p.x for p in sel]
    ys = [p.y for p in sel]
    return Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)), Vector(((max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2))


# Scarf: a knitted wool scarf wound once round the neck (a fat, slightly lumpy roll) with one end
# hanging down the chest inside the open jacket. MakeHuman faces -Y.
wool_red = make_mat("scarf_wool", (1.0, 1.0, 1.0), 0.95, sheen=0.5)
# A knitted rib texture (maroon wool), mapped by a box projection added below.
_kw = 256
_ky, _kx = np.mgrid[0:_kw, 0:_kw] / _kw
_rib = 0.5 + 0.5 * np.cos(_kx * 2 * np.pi * 16)
_st = 0.5 + 0.5 * np.cos((_ky * 32 + np.abs(((_kx * 16) % 1.0) - 0.5)) * 2 * np.pi)
_v = 0.55 + 0.3 * _rib * (0.7 + 0.3 * _st) + (np.random.default_rng(5).random(_kx.shape) - 0.5) * 0.08
_knit = np.stack([0.32 * _v, 0.055 * _v, 0.05 * _v, np.ones_like(_v)], axis=-1).astype(np.float32)
_kimg = bpy.data.images.new("scarf_knit", _kw, _kw)
_kimg.pixels = _knit.ravel()
_kimg.pack()
_tn = wool_red.node_tree.nodes.new("ShaderNodeTexImage")
_tn.image = _kimg
wool_red.node_tree.links.new(_tn.outputs["Color"], wool_red.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
# Fit to the neck itself: the vertices the neck bone carries.
neck_pts = [body.matrix_world @ v.co for v in body.data.vertices if weight_of(body, v.index, ("neck",)) > 0.5]
nz0 = min(p.z for p in neck_pts)
nz1 = max(p.z for p in neck_pts)
neck_z = nz0 + (nz1 - nz0) * 0.3
_ring = [p for p in neck_pts if abs(p.z - neck_z) < 0.015]
nc = Vector(((min(p.x for p in _ring) + max(p.x for p in _ring)) / 2, (min(p.y for p in _ring) + max(p.y for p in _ring)) / 2))
nr = Vector(((max(p.x for p in _ring) - min(p.x for p in _ring)) / 2, (max(p.y for p in _ring) - min(p.y for p in _ring)) / 2))
print("[person] neck", nc, nr, neck_z)
bm = bmesh.new()
rings = []
n_a, n_t = 36, 10
for i in range(n_a):
    a = 2 * math.pi * i / n_a
    lump = 1.0 + 0.06 * math.sin(a * 5.0) + 0.03 * math.sin(a * 11.0 + 1.0)
    cx = nc.x + math.sin(a) * (nr.x + 0.028)
    cy = nc.y - math.cos(a) * (nr.y + 0.028)
    out = Vector((math.sin(a), -math.cos(a), 0.0))
    ring = []
    for j in range(n_t):
        b_ = 2 * math.pi * j / n_t
        rr = 0.026 * lump
        p = Vector((cx, cy, neck_z - 0.015 + 0.02 * math.sin(a * 2.0 + 0.6))) + out * math.cos(b_) * rr * 1.1 + Vector((0, 0, 1)) * math.sin(b_) * rr * 1.25
        ring.append(bm.verts.new(p))
    rings.append(ring)
for i in range(n_a):
    for j in range(n_t):
        bm.faces.new((rings[i][j], rings[(i + 1) % n_a][j], rings[(i + 1) % n_a][(j + 1) % n_t], rings[i][(j + 1) % n_t]))
# Two short ends tucked down into the open front of the jacket: tapering knitted tubes.
for side in (-1.0, 1.0):
    prev = None
    for k in range(7):
        tt = k / 6
        cz = neck_z - 0.035 - tt * 0.09
        cy = nc.y - nr.y - 0.04 - 0.012 * tt
        cx = nc.x + side * (0.018 + 0.03 * tt)
        ring = []
        for j in range(8):
            b_ = 2 * math.pi * j / 8
            rr = 0.02 * (1.0 - 0.2 * tt)
            ring.append(bm.verts.new((cx + math.cos(b_) * rr * 1.5, cy + math.sin(b_) * rr * 0.45, cz)))
        if prev:
            for j in range(8):
                bm.faces.new((prev[j], prev[(j + 1) % 8], ring[(j + 1) % 8], ring[j]))
        prev = ring
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
neck_bone = bone_name("neck_01", "neck")
chest_bone = bone_name("spine_03", "spine_02", "spine")
scarf = skinned("Scarf", bm, wool_red, {neck_bone: 0.6, chest_bone: 0.4})
bpy.context.view_layer.objects.active = scarf
scarf.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(scale_to_bounds=False)
bpy.ops.object.mode_set(mode="OBJECT")
for l in scarf.data.uv_layers.active.data:
    l.uv *= 6.0
scarf.select_set(False)
s = scarf.modifiers.new("Solidify", "SOLIDIFY")
s.thickness = 0.008
scarf.modifiers.move(1, 0)

# Flat cap: an eight-panel wool cap — a soft crown pulled forward over a short stiff peak — sitting
# above the brow, skinned to the head.
tweed = make_mat("cap_tweed", (0.075, 0.068, 0.058), 0.92, sheen=0.35)
head_pts = [body.matrix_world @ v.co for v in body.data.vertices if weight_of(body, v.index, ("head",)) > 0.9]
top = max(p.z for p in head_pts)
hc, hr = ring_fit(top - 0.075, top - 0.055, lambda p: True)
band_z = top - 0.072
bm = bmesh.new()
n_a, n_v = 40, 10
grid = []
for j in range(n_v + 1):
    v_ = j / n_v                                  # 0 at the band .. 1 at the crown's top
    row = []
    for i in range(n_a):
        a = 2 * math.pi * i / n_a
        fwd = -math.cos(a)                         # 1 at the front (-Y)
        # A flat cap: low, wide soft crown, its top pulled forward and down onto the peak.
        swell = 1.0 + 0.2 * math.sin(v_ * math.pi * 0.8) + 0.12 * max(fwd, 0) * v_
        shrink = math.cos(v_ * math.pi * 0.5) ** 0.35
        rx = (hr.x + 0.012) * swell * shrink
        ry = (hr.y + 0.014) * swell * shrink
        z = band_z + (top - band_z + 0.012) * math.sin(v_ * math.pi * 0.5) ** 0.7 - 0.035 * max(fwd, 0) * v_ ** 0.5
        x = hc.x + math.sin(a) * rx
        y = hc.y - math.cos(a) * ry - 0.03 * v_       # the crown pulled forward
        row.append(bm.verts.new((x, y, z)))
    grid.append(row)
for j in range(n_v):
    for i in range(n_a):
        bm.faces.new((grid[j][i], grid[j][(i + 1) % n_a], grid[j + 1][(i + 1) % n_a], grid[j + 1][i]))
bm.faces.new(list(reversed(grid[n_v])))
# Peak: a stiff curved visor ahead of the band.
pk = []
for j in range(4):
    t_ = j / 3
    row = []
    for i in range(11):
        a = math.radians(-58 + 116 * i / 10)
        x = hc.x + math.sin(a) * (hr.x + 0.012 + 0.012 * t_)
        y = hc.y - math.cos(a) * (hr.y + 0.012) - 0.042 * t_ * math.cos(a) ** 0.5
        z = band_z + 0.004 - 0.018 * t_ * t_
        row.append(bm.verts.new((x, y, z)))
    pk.append(row)
for j in range(3):
    for i in range(10):
        bm.faces.new((pk[j][i], pk[j][i + 1], pk[j + 1][i + 1], pk[j + 1][i]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
cap = skinned("Cap", bm, tweed, {bone_name("head"): 1.0})
s = cap.modifiers.new("Solidify", "SOLIDIFY")
s.thickness = 0.006
cap.modifiers.move(1, 0)

# Hair under the cap: trim what the cap covers so none pokes through.
if hair:
    bm = bmesh.new()
    bm.from_mesh(hair.data)
    mw = hair.matrix_world
    dead = [f for f in bm.faces if all((mw @ v.co).z > band_z + 0.004 for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(hair.data)
    bm.free()

# ————— preview render —————
if PREVIEW:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x = 1200
    sc.render.resolution_y = 1200
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.34, 0.37, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = world
    for (rot, en) in (((math.radians(55), 0, math.radians(-35)), 3.5), ((math.radians(60), 0, math.radians(150)), 1.5)):
        ld = bpy.data.lights.new("sun", "SUN")
        ld.energy = en
        lo_ = bpy.data.objects.new("sun", ld)
        lo_.rotation_euler = rot
        sc.collection.objects.link(lo_)
    lo, hi = world_bbox([o for o in bpy.data.objects if o.type == "MESH"])
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    for name, pos, look in (("full", Vector((1.6, -3.4, 1.15)), Vector((0, 0, 0.88))), ("face", Vector((0.25, -0.8, 1.6)), Vector((0, 0, 1.55)))):
        cam.location = pos
        d = look - pos
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = PREVIEW.replace(".png", "_%s.png" % name)
        bpy.ops.render.render(write_still=True)

# ————— export —————
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type in ("MESH", "ARMATURE"):
        o.select_set(True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                          export_skins=True, export_animations=False, export_image_format="AUTO")
# Fine hair cards (eyebrows, eyelashes) as alpha-tested, not blended: blended ones lose their
# sorting against the skin in the game and vanish.
import json
import struct
with open(OUT, "rb") as f:
    data = f.read()
jlen = struct.unpack("<I", data[12:16])[0]
gltf = json.loads(data[20:20 + jlen])
for m in gltf.get("materials", []):
    if any(k in m.get("name", "").lower() for k in ("eyebrow", "eyelash")):
        m["alphaMode"] = "MASK"
        m["alphaCutoff"] = 0.25
        m["doubleSided"] = True
js = json.dumps(gltf, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
rest = data[20 + jlen:]
out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + len(rest)) + struct.pack("<I", len(js)) + b"JSON" + js + rest
with open(OUT, "wb") as f:
    f.write(out)
for o in bpy.data.objects:
    if o.type == "MESH":
        l_, h_ = world_bbox([o])
        print("[person] bbox", o.name, "%.3f..%.3f" % (l_.z, h_.z))
lo, hi = world_bbox([o for o in bpy.data.objects if o.type == "MESH"])
print("[person] wrote", OUT, "height with boots/cap %.3f" % (hi.z - lo.z),
      "tris", sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH"))
