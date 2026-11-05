"""Close-ups of a character's face with each shape key at full strength -> previews/<slug>_face_<key>.png
    blender -b <slug>/<slug>_face.blend -P scripts/render_faces.py -- <slug> [keys,comma,separated] [angle]"""
import bpy, os, sys, json, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
slug = args[0]
only = args[1].split(",") if len(args) > 1 and args[1] else None
ang = float(args[2]) if len(args) > 2 else 0.35
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
body = bpy.data.objects[slug + "_body"]
scn = bpy.context.scene
scn.render.engine = "BLENDER_WORKBENCH"
scn.display.shading.light = "STUDIO"
scn.display.shading.color_type = "TEXTURE"
scn.display.shading.show_backface_culling = True     # as in the game
scn.render.resolution_x = 520
scn.render.resolution_y = 520
cam_d = bpy.data.cameras.new("fc"); cam_d.lens = 110
cam = bpy.data.objects.new("fc", cam_d); scn.collection.objects.link(cam); scn.camera = cam
n = Vector(F["nose"])
tgt = Vector((F["center_x"], n.y, n.z + 0.0))
d = Vector((math.sin(ang), -math.cos(ang), 0.05))
cam.location = tgt + d * 0.62
cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
kbs = body.data.shape_keys.key_blocks
names = [k.name for k in kbs if k.name != "Basis"]
if only:
    names = [k for k in names if k in only]
for name in ["Basis"] + names:
    for k in kbs:
        k.value = 0.0
    if name != "Basis":
        kbs[name].value = 1.0
    scn.render.filepath = os.path.join(ROOT, "previews", "%s_face_%s.png" % (slug, name))
    bpy.ops.render.render(write_still=True)
print("FACES", len(names) + 1)
