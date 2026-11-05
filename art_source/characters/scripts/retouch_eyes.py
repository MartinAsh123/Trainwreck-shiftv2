"""Repaint a Tripo character's eyes into its sculpted eye openings (eye_frames.json), texture only:
    blender -b <slug>/<slug>.blend -P scripts/retouch_eyes.py -- <slug>
1. the face round both eyes is sampled straight from the front into one flat image (0.08 mm a pixel);
2. that image is warped: per axis a piecewise-linear map, identity at the region's edge, that puts the
   whole painted eye into the opening's box and closes the lid and cheek skin over where the paint was;
3. the warped image is projected back from the front and baked (Cycles, emission) into the character's
   own UVs - only onto the faces seen from the front (hidden socket faces keep their texels), fading to
   the original texture at the region's edge and on surfaces turned away from the front.
Mesh, UVs and brows are untouched. -> <slug>/<slug>_eyefix_tex.blend, textures/<slug>_albedo_eyefix.png"""
import bpy, bmesh, os, sys, json
import numpy as np
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import eye_fit

slug = sys.argv[sys.argv.index("--") + 1:][0]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
FR = json.load(open(os.path.join(ROOT, "eye_frames.json")))[slug]
body = bpy.data.objects[slug + "_body"]
me = body.data
mw = body.matrix_world
scn = bpy.context.scene
face = eye_fit.Face(body, F["mouth"][1])
eyes = [eye_fit.fit_eye(face, Vector(e), FR) for e in F["eyes"]]
for e in eyes:
    e["o"] = (e["oc"][0] - e["ow"] / 2, e["oc"][0] + e["ow"] / 2, e["oc"][1] - e["oh"] / 2, e["oc"][1] + e["oh"] / 2)
    e["q"] = (e["pc"][0] - e["pw"] / 2, e["pc"][0] + e["pw"] / 2, e["pc"][1] - e["ph"] / 2, e["pc"][1] + e["ph"] / 2)
    o, q = e["o"], e["q"]
    e["R"] = (min(o[0], q[0]) - 0.007, max(o[1], q[1]) + 0.007,
              min(o[2], q[2]) - 0.006, max(o[3], q[3]) + 0.0015)       # 1.5 mm over the eye: not the brow

# 1. The front image.
S = 0.00008
X0 = min(e["R"][0] for e in eyes) - 0.002
X1 = max(e["R"][1] for e in eyes) + 0.002
Z0 = min(e["R"][2] for e in eyes) - 0.002
Z1 = max(e["R"][3] for e in eyes) + 0.002
gx = np.arange(X0, X1, S)
gz = np.arange(Z0, Z1, S)
FI = np.zeros((len(gz), len(gx), 4), np.float32)
FI[..., 3] = 1.0
for j, z in enumerate(gz):
    for i, x in enumerate(gx):
        _, uv = face.hit(x, z)
        if uv is not None:
            FI[j, i] = face.color(uv, bilinear=True)

# 2. The warp.
XX, ZZ = np.meshgrid(gx, gz)
SX, SZ = XX.copy(), ZZ.copy()
for e in ([] if os.environ.get("EYEFIX_IDENTITY") else eyes):   # (identity: a test of the bake's round trip)
    o, q, R = e["o"], e["q"], e["R"]
    m = (XX > R[0]) & (XX < R[1]) & (ZZ > R[2]) & (ZZ < R[3])
    SX[m] = np.interp(XX[m], [R[0], o[0], o[1], R[1]], [R[0], q[0], q[1], R[1]])
    SZ[m] = np.interp(ZZ[m], [R[2], o[2], o[3], R[3]], [R[2], q[2], q[3], R[3]])
fi = np.clip((SX - X0) / S, 0, len(gx) - 1.001)
fj = np.clip((SZ - Z0) / S, 0, len(gz) - 1.001)
i0, j0 = np.floor(fi).astype(int), np.floor(fj).astype(int)
ti, tj = (fi - i0)[..., None], (fj - j0)[..., None]
WI = (FI[j0, i0] * (1 - ti) + FI[j0, i0 + 1] * ti) * (1 - tj) + (FI[j0 + 1, i0] * (1 - ti) + FI[j0 + 1, i0 + 1] * ti) * tj
front = bpy.data.images.new("eyefix_front", len(gx), len(gz), alpha=True, float_buffer=True)
front.colorspace_settings.name = "Non-Color"           # (before the pixels: changing it regenerates the image)
front.pixels[:] = WI.astype(np.float32).ravel()

# 3. Bake it back, onto a copy holding only the faces round the eyes seen from the front.
def in_R(x, z, pad=0.0):
    return any(e["R"][0] - pad < x < e["R"][1] + pad and e["R"][2] - pad < z < e["R"][3] + pad for e in eyes)

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
    keep = in_R(c.x, c.z, 0.001) and (rot @ f.normal).y < -0.1
    if keep:
        h = face.bvh.ray_cast(Vector((c.x, face.front_y, c.z)), Vector((0, 1, 0)))
        keep = h[0] is not None and (h[0] - c).length < 0.0005
    if not keep:
        gone.append(f)
bmesh.ops.delete(bm, geom=gone, context="FACES")
bm.to_mesh(dup.data)
bm.free()
dm = dup.data
print("BAKE faces", len(dm.polygons))
orig_uv = dm.uv_layers.active.name
dm.uv_layers.new(name="proj")
dm.uv_layers.active = dm.uv_layers[orig_uv]
proj = dm.uv_layers["proj"]                                    # (fetched again: references go stale)
Wn, Hn = len(gx), len(gz)
for lp in dm.loops:
    p = mw @ dm.vertices[lp.vertex_index].co
    proj.data[lp.index].uv = ((p.x - X0) / (Wn * S) + 0.5 / Wn, (p.z - Z0) / (Hn * S) + 0.5 / Hn)
dm.color_attributes.new("mask", "FLOAT_COLOR", "POINT")
mask = dm.color_attributes["mask"]
for v in dm.vertices:
    p = mw @ v.co
    m = 0.0
    for e in eyes:
        R = e["R"]
        d = min(p.x - R[0], R[1] - p.x, p.z - R[2], R[3] - p.z)
        m = max(m, float(eye_fit.smoothstep(0.0, 0.002, d)))
    m *= float(eye_fit.smoothstep(0.15, 0.45, -(rot @ v.normal).y))
    mask.data[v.index].color = (m, m, m, 1.0)
print("PROJ uv range", np.round(np.array([d.uv[:] for d in dm.uv_layers["proj"].data]).min(0), 3), np.round(np.array([d.uv[:] for d in dm.uv_layers["proj"].data]).max(0), 3),
      "mask mean %.2f" % float(np.mean([c.color[0] for c in dm.color_attributes["mask"].data])), "front mean", np.round(WI[..., :3].mean(axis=(0, 1)), 3))

src_img = [n.image for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image][0]
TW, TH = src_img.size
# Raw values throughout (no colour management on the way in or out of the bake: it shifted the colours).
cs0 = src_img.colorspace_settings.name
src_img.colorspace_settings.name = "Non-Color"
target = bpy.data.images.new("eyefix_bake", TW, TH, alpha=True, float_buffer=True)
target.colorspace_settings.name = "Non-Color"
target.pixels[:] = np.zeros(TW * TH * 4, np.float32)
mat = bpy.data.materials.new("eyefix_bake")
mat.use_nodes = True
nt = mat.node_tree
nt.nodes.clear()
uv_o = nt.nodes.new("ShaderNodeUVMap"); uv_o.uv_map = orig_uv
uv_p = nt.nodes.new("ShaderNodeUVMap"); uv_p.uv_map = "proj"
t_o = nt.nodes.new("ShaderNodeTexImage"); t_o.image = src_img; t_o.interpolation = "Closest"
t_p = nt.nodes.new("ShaderNodeTexImage"); t_p.image = front; t_p.extension = "EXTEND"
att = nt.nodes.new("ShaderNodeAttribute"); att.attribute_name = "mask"
mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
emi = nt.nodes.new("ShaderNodeEmission")
out = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(uv_o.outputs["UV"], t_o.inputs["Vector"])
nt.links.new(uv_p.outputs["UV"], t_p.inputs["Vector"])
nt.links.new(att.outputs["Fac"], mix.inputs["Factor"])
col_in = [x for x in mix.inputs if x.type == "RGBA"]           # (the Mix node has A/B sockets of every type)
col_out = [x for x in mix.outputs if x.type == "RGBA"][0]
nt.links.new(t_o.outputs["Color"], col_in[0])
nt.links.new(t_p.outputs["Color"], col_in[1])
nt.links.new(col_out, emi.inputs["Color"])
nt.links.new(emi.outputs["Emission"], out.inputs["Surface"])
t_t = nt.nodes.new("ShaderNodeTexImage"); t_t.image = target
nt.nodes.active = t_t
dm.materials.clear()
dm.materials.append(mat)

scn.render.engine = "CYCLES"
scn.cycles.samples = 1
scn.cycles.device = "CPU"
scn.render.bake.margin = 3
scn.render.bake.use_clear = False
for o in scn.objects:
    o.select_set(o == dup)
bpy.context.view_layer.objects.active = dup
bpy.ops.object.bake(type="EMIT", margin=3, use_clear=False)

B = np.array(target.pixels[:], np.float32).reshape(TH, TW, 4)
src_img.colorspace_settings.name = cs0
O = face.px.copy()
A_ = B[..., 3]
print("ALPHA", np.histogram(A_[A_ > 0], bins=[0, 0.1, 0.5, 0.9, 0.99, 1.01])[0].tolist())
covered = A_ > 0.02
B[..., :3] = np.where(covered[..., None], B[..., :3] / np.maximum(A_, 1e-4)[..., None], 0.0)   # premultiplied
if os.environ.get("EYEFIX_IDENTITY"):
    jj, ii = np.nonzero(covered)
    for k in range(0, len(jj), max(len(jj) // 6, 1)):
        print("DBG texel", jj[k], ii[k], "baked", np.round(B[jj[k], ii[k]], 3), "orig", np.round(face.px[jj[k], ii[k]], 3))
_m = covered & (np.abs(B[..., :3] - face.px[..., :3]).max(axis=2) < 0.5)
print("ROUNDTRIP mean |baked - original| over baked texels: %.4f" % float(np.abs(B[..., :3] - face.px[..., :3])[_m].mean()))
NEW = np.where(covered[..., None], np.concatenate([B[..., :3], O[..., 3:]], axis=2), O)
# (where the mask was 0 the bake should give back the original texel: how closely it does)
print("BAKED texels", int(covered.sum()), "changed", int((np.abs(NEW - O)[..., :3].max(axis=2) > 0.02).sum()))
bpy.data.objects.remove(dup, do_unlink=True)
new = bpy.data.images.new(slug + "_albedo_eyefix", TW, TH)
new.pixels[:] = NEW.ravel()
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
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, slug, slug + "_eyefix_tex.blend"))
print("SAVED", slug)
