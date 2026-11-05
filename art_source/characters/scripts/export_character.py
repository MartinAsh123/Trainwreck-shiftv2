"""Export a finished character (rig + talking-face body) for Godot:
    blender -b <slug>/<slug>_face.blend -P scripts/export_character.py -- <slug>
-> assets/characters/<slug>/<slug>.glb (skin, Mixamo skeleton, shape keys, 2K texture embedded)."""
import bpy, os, sys

args = sys.argv[sys.argv.index("--") + 1:]
slug = args[0]
out_name = args[1] if len(args) > 1 else slug          # another name: a test export beside the real one
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))
out_dir = os.path.join(PROJ, "assets", "characters", slug)
os.makedirs(out_dir, exist_ok=True)
arm = bpy.data.objects[slug + "_rig"]
body = bpy.data.objects[slug + "_body"]
for k in (body.data.shape_keys.key_blocks if body.data.shape_keys else []):
    k.value = 0.0
for o in bpy.context.scene.objects:
    o.select_set(o in (arm, body))
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(
    filepath=os.path.join(out_dir, out_name + ".glb"), export_format="GLB", use_selection=True,
    export_yup=True, export_apply=False, export_skins=True, export_morph=True, export_morph_normal=True,
    export_animations=False, export_materials="EXPORT", export_image_format="AUTO",
    export_cameras=False, export_lights=False)
print("EXPORTED", os.path.join(out_dir, out_name + ".glb"), os.path.getsize(os.path.join(out_dir, out_name + ".glb")) // 1024, "KB")
