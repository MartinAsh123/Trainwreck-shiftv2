"""Write each character of cast.json out of characters_source.blend into its own small file, in one
session (the source is ~1 GB; opening it once per character is slow):
    blender -b characters_source.blend -P scripts/batch_extract.py [-- slug slug ...]
-> <slug>/<slug>_src.blend (its armature, mesh, materials, texture), for prep_character.py."""
import bpy, os, sys, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
cast = json.load(open(os.path.join(ROOT, "cast.json")))["cast"]
for c in cast:
    if "skip" in c or (only and c["slug"] not in only):
        continue
    arm = bpy.data.objects.get(c["src"])
    meshes = [o for o in arm.children if o.type == "MESH"] if arm else []
    if not meshes:
        print("EXTRACT FAIL", c["slug"], "no armature or mesh")
        continue
    os.makedirs(os.path.join(ROOT, c["slug"]), exist_ok=True)
    path = os.path.join(ROOT, c["slug"], c["slug"] + "_src.blend")
    bpy.data.libraries.write(path, {arm, *meshes}, compress=True)
    print("EXTRACT", c["slug"], os.path.getsize(path) // (1024 * 1024), "MB")
