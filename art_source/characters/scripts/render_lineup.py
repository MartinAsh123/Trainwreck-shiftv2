"""Front + three-quarter thumbnails of every character in characters_source.blend (background)."""
import bpy, os, math
from mathutils import Vector
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "previews")
os.makedirs(OUT, exist_ok=True)
scn = bpy.context.scene
scn.render.engine = "BLENDER_WORKBENCH"
scn.display.shading.light = "STUDIO"
scn.display.shading.color_type = "TEXTURE"
scn.render.resolution_x = 360
scn.render.resolution_y = 640
world = bpy.data.worlds.new("w"); world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.35, 0.36, 1)
scn.world = world
roots = [o for o in bpy.data.objects if (o.type == "ARMATURE") or (o.type == "MESH" and o.parent is None and o.name not in ("Cube",))]
for o in bpy.data.objects:
    if o.type in ("MESH", "ARMATURE"):
        o.hide_render = True
cam_data = bpy.data.cameras.new("lc"); cam_data.lens = 85
cam = bpy.data.objects.new("lc", cam_data); scn.collection.objects.link(cam); scn.camera = cam
sun = bpy.data.lights.new("ls", "SUN"); sun.energy = 3.5
so = bpy.data.objects.new("ls", sun); scn.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(30))
info = []
for r in roots:
    if all(os.path.exists(os.path.join(OUT, "%s__%s.png" % (r.name.replace(" ", "_"), t))) for t in ("front", "q")):
        continue
    meshes = [c for c in r.children if c.type == "MESH"] if r.type == "ARMATURE" else [r]
    for m in meshes + [r]:
        m.hide_render = False
    pts = [m.matrix_world @ Vector(c) for m in meshes for c in m.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (lo + hi) / 2; h = hi.z - lo.z
    info.append((r.name, round(h, 3)))
    for tag, ang in (("front", 0.0), ("q", 0.6)):
        d = Vector((math.sin(ang), -math.cos(ang), 0.05))
        cam.location = c + d * h * 3.4
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = os.path.join(OUT, "%s__%s.png" % (r.name.replace(" ", "_"), tag))
        bpy.ops.render.render(write_still=True)
    for m in meshes + [r]:
        m.hide_render = True
print("HEIGHTS", info)
