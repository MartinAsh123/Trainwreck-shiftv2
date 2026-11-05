"""Find a Tripo character's facial landmarks from its geometry and painted texture, save them to
<slug>/<slug>_face.json and render a close-up of the head with markers (previews/<slug>_landmarks.png).
    blender -b <slug>/<slug>.blend -P scripts/face_landmarks.py -- <slug>
Face toward -Y (Blender), Z up, metres. Landmarks: nose tip, mouth centre (lip seam), mouth corners,
pupils, brow line, chin."""
import bpy, os, sys, json, math
import numpy as np
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import eye_fit

slug = sys.argv[sys.argv.index("--") + 1:][0]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
arm = bpy.data.objects[slug + "_rig"]
body = bpy.data.objects[slug + "_body"]
me = body.data
mw = body.matrix_world

# Per-vertex albedo from the texture (average of its UV corners).
img = [n.image for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image][0]
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)[:, :, :3]
uv = me.uv_layers.active.data
vcol = np.zeros((len(me.vertices), 3), np.float32)
vcnt = np.zeros(len(me.vertices), np.float32)
for poly in me.polygons:
    for li in poly.loop_indices:
        u, v = uv[li].uv
        x = min(max(int(u * W), 0), W - 1)
        y = min(max(int(v * H), 0), H - 1)
        vi = me.loops[li].vertex_index
        vcol[vi] += px[y, x]
        vcnt[vi] += 1
vcol /= np.maximum(vcnt, 1)[:, None]
lum = vcol @ np.array([0.2126, 0.7152, 0.0722], np.float32)
red = vcol[:, 0] - 0.5 * (vcol[:, 1] + vcol[:, 2])

co = np.array([mw @ v.co for v in me.vertices], np.float32)
# The head: vertices mostly weighted to the Head bone.
gi = body.vertex_groups["mixamorig:Head"].index
hw = np.zeros(len(me.vertices), np.float32)
for v in me.vertices:
    for g in v.groups:
        if g.group == gi:
            hw[v.index] = g.weight
head = hw > 0.6
hz0, hz1 = co[head, 2].min(), co[head, 2].max()
hh = hz1 - hz0
cx0 = float((co[:, 0].min() + co[:, 0].max()) / 2)        # Tripo centres its models: the face's midline
# The face seen straight on (a depth map and the texture, 1 mm apart), for the nose and the eyes.
face3 = eye_fit.Face(body, float(co[head, 1].min()) + 0.25)
GX = np.arange(cx0 - 0.07, cx0 + 0.0701, 0.001)
GZ = np.arange(hz0, hz1, 0.001)
D = np.full((len(GX), len(GZ)), np.nan)
L = np.full((len(GX), len(GZ)), np.nan)
SK = np.zeros((len(GX), len(GZ)), bool)                         # skin coloured
CC = np.zeros((len(GX), len(GZ), 3))
for i, x in enumerate(GX):
    for j, z in enumerate(GZ):
        p, uv = face3.hit(x, z)
        if p is not None:
            c = face3.color(uv)
            D[i, j] = p.y
            L[i, j] = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
            SK[i, j] = c[0] > c[1] > c[2] - 0.02 and c[0] - c[2] > 0.08 and L[i, j] > 0.15
            CC[i, j] = c[:3]
# This face's own skin: the usual colour of the skin-like texels low on the face (a cap or hair can pass
# the test above, but not by being near this).
low = SK & (np.abs(GX - cx0) < 0.025)[:, None] & (GZ < hz0 + 0.4 * hh)[None, :]
ref = np.median(CC[low], axis=0)
SK &= np.linalg.norm(CC - ref, axis=2) < 0.14
# Nose tip: near the midline, the point that stands out most from the face 2 cm either side of it
# and 2 cm above it (a hat's brim stands further forward, but it is wide; a chin stands out from its
# sides, but hardly from the lips above it; the nose stands well out from its bridge).
k = 20
prot = np.full(D.shape, -1.0)
prot[k:-k, :-k] = np.minimum(np.minimum(D[:-2 * k, :-k], D[2 * k:, :-k]), D[k:-k, k:]) - D[k:-k, :-k]
prot[np.isnan(prot) | ~SK] = -1.0
mid_i = np.abs(GX - cx0) < 0.012
prot[~mid_i] = -1.0
prot[:, GZ > hz0 + 0.7 * hh] = -1.0
ni_, nj_ = np.unravel_index(int(np.argmax(prot)), prot.shape)
# (it stands out about as much all down its ridge: the tip is the most forward of those)
ridge = prot > 0.6 * prot.max()
ni_, nj_ = np.unravel_index(int(np.argmin(np.where(ridge, D, np.inf))), D.shape)
nose = np.array(face3.hit(GX[ni_], GZ[nj_])[0], np.float32)
cx = cx0
print("NOSE", nose.round(4), "stands out %.1f mm" % (prot[ni_, nj_] * 1000))
# The mouth: from the shape, not the paint (Tripo paints the lips a few mm off the sculpted slit): the
# slit's groove followed out from the middle (mouth_fit.py); its middle is the mouth, its ends the corners.
import mouth_fit
MF = mouth_fit.fit_mouth(face3, {"center_x": cx, "nose": nose.tolist()})
okg = ~np.isnan(MF["geo"])
if okg.sum() < 20:                                              # no slit sculpted: a flat line at the middle
    MF["geo"][:] = MF["mid_z"]
    okg = np.abs(MF["gx"] - cx) < 0.022
    MF["gcorn"] = (cx - 0.022, cx + 0.022)
groove = [[float(x), float(z)] for x, z in zip(MF["gx"][okg], MF["geo"][okg])]


def surface(x, z):
    p, _ = face3.hit(x, z)
    return np.array(p, np.float32)


mouth = surface(cx, MF["mid_z"])
half = float(np.clip(np.mean([cx - MF["gcorn"][0], MF["gcorn"][1] - cx]), 0.018, 0.03))
corners = []
for sgn in (-1, 1):
    xc_ = cx + sgn * half
    zc_ = float(np.interp(xc_, MF["gx"][okg], MF["geo"][okg]))
    corners.append([float(xc_), float(surface(xc_, zc_)[1]), zc_])
print("MOUTH groove at %.4f, corners +-%.1f mm" % (MF["mid_z"], half * 1000))
# Pupils: each side of the nose, the darkest spot (averaged over 7 x 3 mm, the size of an iris and its
# lashes) 1.8 to 4.5 cm out and 1.5 to 6.5 cm up; of two dark spots (an eye and its brow) the lower.
# The two are then made a mirror pair about the nose (where they disagree, the darker one is trusted).
Lf = np.where(np.isnan(L), 1.0, L)
pad = np.pad(Lf, ((3, 3), (1, 1)), mode="edge")
Lm = sum(pad[a:a + Lf.shape[0], b:b + Lf.shape[1]] for a in range(7) for b in range(3)) / 21.0
cands = []
for sgn in (-1, 1):
    ok = ((GX - cx) * sgn > 0.018)[:, None] & ((GX - cx) * sgn < 0.045)[:, None] & (GZ > nose[2] + 0.015)[None, :] & (GZ < nose[2] + 0.065)[None, :]
    M = np.where(ok, Lm, 9.0)
    best = float(M.min())
    dark = M < best + 0.08                                  # dark enough to be an eye or a brow
    jj = np.nonzero(dark.any(axis=0))[0]
    # the lowest dark band: its darkest spot
    j_lo = jj.min()
    band = M[:, j_lo:j_lo + 12]
    i, j = np.unravel_index(int(np.argmin(band)), band.shape)
    p, _ = face3.hit(GX[i], GZ[j_lo + j])
    cands.append((np.array(p), float(band[i, j])))
(pr, lr), (pl, ll) = cands
dxr, dxl = cx - pr[0], pl[0] - cx
if abs(dxr - dxl) < 0.006 and abs(pr[2] - pl[2]) < 0.005:
    dx, ez = (dxr + dxl) / 2, (pr[2] + pl[2]) / 2
else:
    dx, ez = (dxr, pr[2]) if lr <= ll else (dxl, pl[2])
eyes = []
for sgn in (-1, 1):
    p, _ = face3.hit(cx + sgn * dx, ez)
    eyes.append([float(p[0]), float(p[1]), float(p[2])])
face = {"slug": slug, "head_z": [float(hz0), float(hz1)], "center_x": cx, "nose": nose.tolist(), "mouth": mouth.tolist(),
        "mouth_corners": corners, "eyes": eyes, "chin": [cx, float(mouth[1]) + 0.01, float(mouth[2] - 0.045)],
        "groove": groove}
json.dump(face, open(os.path.join(ROOT, slug, slug + "_face.json"), "w"), indent=1)
print("FACE", json.dumps(face))

# Close-up with markers.
scn = bpy.context.scene
scn.render.engine = "BLENDER_WORKBENCH"
scn.display.shading.light = "STUDIO"
scn.display.shading.color_type = "TEXTURE"
scn.render.resolution_x = 900
scn.render.resolution_y = 900
def mark(p, col, r=0.003):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=p)
    o = bpy.context.active_object
    m = bpy.data.materials.new("mk"); m.diffuse_color = (*col, 1)
    o.data.materials.append(m); o.color = (*col, 1)
mark(nose, (0, 1, 0)); mark(mouth, (1, 0, 0))
for c in corners: mark(c, (1, 1, 0))
for e in eyes: mark(e, (0, 0.6, 1))
scn.display.shading.color_type = "TEXTURE"
cam_d = bpy.data.cameras.new("c"); cam_d.lens = 100
cam = bpy.data.objects.new("c", cam_d); scn.collection.objects.link(cam); scn.camera = cam
tgt = Vector((cx, nose[1], nose[2] + 0.005))
cam.location = tgt + Vector((0, -0.75, 0.02))
cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
scn.render.filepath = os.path.join(ROOT, "previews", slug + "_landmarks.png")
bpy.ops.render.render(write_still=True)
