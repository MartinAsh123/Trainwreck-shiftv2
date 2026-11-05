"""Extract one character from characters_source.blend into its own working file:
    blender -b characters_source.blend -P scripts/prep_character.py -- "<armature name>" <slug> <height m>
- deletes everything else, scales the character to its real height (scale applied on rig and mesh),
- names the rig <slug>_rig and the mesh <slug>_body,
- reduces the base-colour texture to 2048 px and saves it next to the file (textures/<slug>_albedo.png),
- saves art_source/characters/<slug>/<slug>.blend."""
import bpy, os, sys

args = sys.argv[sys.argv.index("--") + 1:]
name, slug, height = args[0], args[1], float(args[2])
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, slug)
os.makedirs(os.path.join(OUT, "textures"), exist_ok=True)

arm = bpy.data.objects[name]
body = [c for c in arm.children if c.type == "MESH"][0]
for o in (arm, body):                       # (a file from batch_extract.py has them in no scene)
    if o.name not in bpy.context.scene.objects:
        bpy.context.scene.collection.objects.link(o)
keep = {arm, body}
for o in list(bpy.data.objects):
    if o not in keep:
        bpy.data.objects.remove(o, do_unlink=True)
for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
    for d in list(coll):
        if d.users == 0:
            coll.remove(d)

# Real height: the Tripo characters arrive 1 m tall.
pts = [body.matrix_world @ v.co for v in body.data.vertices]
cur = max(p.z for p in pts) - min(p.z for p in pts)
k = height / cur
arm.scale = (k, k, k)
for o in bpy.data.objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
arm.name = slug + "_rig"
arm.data.name = slug + "_rig"
body.name = slug + "_body"
body.data.name = slug + "_body"

# Texture: 8K -> 2K, saved as a file next to the blend.
mat = body.data.materials[0]
mat.name = slug + "_skin"
for n in mat.node_tree.nodes:
    if n.type == "TEX_IMAGE" and n.image:
        im = n.image
        if im.size[0] > 2048:
            im.scale(2048, 2048)
        im.filepath_raw = os.path.join(OUT, "textures", slug + "_albedo.png")
        im.file_format = "PNG"
        im.save()
        im.name = slug + "_albedo"
        if im.packed_file:
            im.unpack(method="REMOVE")
            im.filepath = os.path.join(OUT, "textures", slug + "_albedo.png")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, slug + ".blend"))
print("PREP", slug, "scale", round(k, 4), "verts", len(body.data.vertices))
