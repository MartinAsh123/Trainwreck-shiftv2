"""Mark where a Tripo character's painted eyes overflow the sculpted eye openings.
    blender -b <file>.blend -P scripts/eye_overflow.py -- <slug> [tag]
-> previews/<slug>_eye_overflow[_tag].png: front close-up, textured (top) and shape only (bottom), with
   red    the sculpted opening (the socket under the upper lid, down to the lower lid's rim),
   yellow the painted eye (sclera, iris, lashes: texels that are not skin) outside that opening."""
import bpy, os, sys, json
import numpy as np
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import eye_fit

args = sys.argv[sys.argv.index("--") + 1:]
slug = args[0]
tag = "_" + args[1] if len(args) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
body = bpy.data.objects[slug + "_body"]
face = eye_fit.Face(body, F["mouth"][1])
_fp = os.path.join(ROOT, "eye_frames.json")              # frames measured by eye, where there are
FRAMES = json.load(open(_fp)).get(slug) if os.path.exists(_fp) else None

scn = bpy.context.scene
e0, e1 = Vector(F["eyes"][0]), Vector(F["eyes"][1])
mid = (e0 + e1) / 2
cam_d = bpy.data.cameras.new("eo")
cam_d.type = "ORTHO"
cam_d.ortho_scale = 0.13
cam = bpy.data.objects.new("eo", cam_d)
scn.collection.objects.link(cam)
scn.camera = cam
cam.location = mid + Vector((0, -0.5, -0.004))
cam.rotation_euler = (1.5708, 0, 0)
RX, RY = 1300, 560
scn.render.resolution_x, scn.render.resolution_y = RX, RY
scn.render.engine = "BLENDER_WORKBENCH"
scn.view_settings.view_transform = "Standard"

marks_red, marks_yel = [], []
for e in F["eyes"]:
    ex = Vector(e)
    E = eye_fit.fit_eye(face, ex, FRAMES)
    xs, t_, b_ = E["open_xs"], E["open_top"], E["open_bot"]
    outline = [(x, z) for x, z in zip(xs, t_)] + [(x, z) for x, z in zip(xs[::-1], b_[::-1])] + [(xs[0], t_[0])]
    for (xa, za), (xb, zb) in zip(outline[:-1], outline[1:]):
        for t in np.linspace(0, 1, 12):
            p, _ = face.hit(xa + (xb - xa) * t, za + (zb - za) * t)
            if p is not None:
                marks_red.append(p)
    over = [p for p in E["painted"] if not eye_fit.inside(xs, t_, b_, p[0], p[2])]
    marks_yel += [Vector(p) for p in over]
    print("EYE at x %.3f: opening %.1f x %.1f mm at (%.1f, %.1f); painted %.1f x %.1f mm at (%.1f, %.1f); %d%% of the paint outside" % (
        ex.x, E["ow"] * 1000, E["oh"] * 1000, (E["oc"][0] - ex.x) * 1000, (E["oc"][1] - ex.z) * 1000,
        E["pw"] * 1000, E["ph"] * 1000, (E["pc"][0] - ex.x) * 1000, (E["pc"][1] - ex.z) * 1000,
        100 * len(over) // max(len(E["painted"]), 1)))


def render(color_type):
    scn.display.shading.color_type = color_type
    scn.display.shading.single_color = (0.75, 0.75, 0.75)
    scn.display.shading.light = "STUDIO" if color_type == "SINGLE" else "FLAT"
    path = os.path.join(ROOT, "previews", "_eo_%s%s_%s.png" % (slug, tag, color_type))     # (several run at once)
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(path)
    a = np.array(im.pixels[:], dtype=np.float32).reshape(RY, RX, 4)
    bpy.data.images.remove(im)
    os.remove(path)
    for pts, col, r, alpha in ((marks_yel, (1.0, 0.85, 0.0), 1, 0.55), (marks_red, (1.0, 0.05, 0.05), 2, 1.0)):
        for p in pts:
            q = world_to_camera_view(scn, cam, p)
            px, py = int(q.x * RX), int(q.y * RY)
            if r <= px < RX - r and r <= py < RY - r:
                a[py - r:py + r + 1, px - r:px + r + 1, :3] = a[py - r:py + r + 1, px - r:px + r + 1, :3] * (1 - alpha) + np.array(col) * alpha
    return a


both = np.concatenate([render("SINGLE"), render("TEXTURE")], axis=0)   # rows go bottom-up: textured on top
out = bpy.data.images.new("eo_out", RX, RY * 2)
out.pixels[:] = both.ravel()
out.filepath_raw = os.path.join(ROOT, "previews", slug + "_eye_overflow" + tag + ".png")
out.file_format = "PNG"
out.save()
print("SAVED", out.filepath_raw)
