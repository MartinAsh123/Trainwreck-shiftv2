"""A character's right eye (on the image's left) straight on, on a millimetre grid, for reading the eye's
frames by eye: textured on top, shape only below. The grid is centred on the painted pupil found by
face_landmarks.py (the thick cross); lines every 1 mm, darker every 5 mm; image right = toward the nose.
    blender -b <file>.blend -P scripts/eye_grid.py -- <slug> [tag]
-> previews/<slug>_eye_grid[_tag].png (56 x 30 mm, 20 px a mm); tag mouth*: centred on the mouth"""
import bpy, os, sys, json
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
slug = args[0]
tag = "_" + args[1] if len(args) > 1 else ""
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
eyes = sorted(F["eyes"], key=lambda e: e[0])
ex = Vector(eyes[0])                                            # the character's right eye: -x
if tag == "_mouth" or tag.startswith("_mouth"):                 # (tag "mouth...": the mouth, centred on the lip seam)
    ex = Vector(F["mouth"])
if tag.startswith("_hair"):                                     # (tag "hair...": the forehead and hairline)
    ex = Vector((F["center_x"], F["nose"][1], F["head_z"][1] - 0.075))
W_MM, H_MM, PX = (80, 44, 14) if tag.startswith("_mouth") else (160, 90, 7) if tag.startswith("_hair") else (56, 30, 20)
RX, RY = W_MM * PX, H_MM * PX
scn = bpy.context.scene
cam_d = bpy.data.cameras.new("eg")
cam_d.type = "ORTHO"
cam_d.ortho_scale = W_MM / 1000.0
cam = bpy.data.objects.new("eg", cam_d)
scn.collection.objects.link(cam)
scn.camera = cam
cam.location = Vector((ex.x, ex.y - 0.4, ex.z))
cam.rotation_euler = (1.5708, 0, 0)
scn.render.resolution_x, scn.render.resolution_y = RX, RY
scn.render.engine = "BLENDER_WORKBENCH"
scn.view_settings.view_transform = "Standard"


def render(color_type):
    scn.display.shading.color_type = color_type
    scn.display.shading.single_color = (0.75, 0.75, 0.75)
    scn.display.shading.light = "STUDIO" if color_type == "SINGLE" else "FLAT"
    path = os.path.join(ROOT, "previews", "_eg_%s%s_%s.png" % (slug, tag, color_type))
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(path)
    a = np.array(im.pixels[:], dtype=np.float32).reshape(RY, RX, 4)
    bpy.data.images.remove(im)
    os.remove(path)
    # The grid (rows go bottom-up; the pupil at the centre).
    cx, cy = RX // 2, RY // 2
    for mm in range(-W_MM // 2, W_MM // 2 + 1):
        x = cx + mm * PX
        if 0 <= x < RX:
            k = 0.55 if mm % 5 == 0 else 0.2
            a[:, x, :3] = a[:, x, :3] * (1 - k) + np.array((0.0, 0.6, 1.0)) * k
    for mm in range(-H_MM // 2, H_MM // 2 + 1):
        y = cy + mm * PX
        if 0 <= y < RY:
            k = 0.55 if mm % 5 == 0 else 0.2
            a[y, :, :3] = a[y, :, :3] * (1 - k) + np.array((0.0, 0.6, 1.0)) * k
    a[cy - 1:cy + 2, :, :3] = (1.0, 0.1, 0.1)
    a[:, cx - 1:cx + 2, :3] = (1.0, 0.1, 0.1)
    return a


both = np.concatenate([render("SINGLE"), render("TEXTURE")], axis=0)   # rows go bottom-up: textured on top
out = bpy.data.images.new("eg_out", RX, RY * 2)
out.pixels[:] = both.ravel()
out.filepath_raw = os.path.join(ROOT, "previews", slug + "_eye_grid" + tag + ".png")
out.file_format = "PNG"
out.save()
print("SAVED", out.filepath_raw)
