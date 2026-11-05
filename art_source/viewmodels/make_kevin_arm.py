# blender -b --factory-startup --python make_kevin_arm.py
# Kevin's left forearm and hand for first person (the wristwatch), cut from the Mike model: the same
# railway uniform sleeve, his real hand, the same texture as everyone else. The fingers are curled a
# little (relaxed), the pose baked, then everything not weighted to the forearm or the hand is dropped.
# The result is re-based so that, in Godot, the wrist is at the origin, +X runs along the forearm
# toward the hand and +Y is the back of the wrist (where the watch goes).
#   -> assets/viewmodels/kevin_arm.glb
import bpy, bmesh, math
from mathutils import Vector, Matrix

SRC = "A:/Trainwreck-ShiftV2/assets/characters/mike/mike.glb"
OUT = "A:/Trainwreck-ShiftV2/assets/viewmodels/kevin_arm.glb"
KEEP = ("LeftForeArm", "LeftHand")            # bone names containing these (fingers included)
CURL = {"1": 26.0, "2": 32.0, "3": 20.0}      # degrees per finger joint: loosely curled, as when he looks at the watch

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
rig = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
body = bpy.data.objects["mike_body"]
for o in list(bpy.data.objects):
    if o not in (rig, body):
        bpy.data.objects.remove(o)

# A loosely closed hand: each finger joint bent toward the palm. Which local axis (and which way)
# flexes a finger depends on the rig, so it is found by trying: the bend that moves the fingertip
# most toward the palm (-X in the A-pose: the back of the left hand faces out, +X) wins.
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='POSE')
PALM = Vector((-1.0, 0.0, 0.0))
def tip(chain):
    bpy.context.view_layer.update()
    return rig.matrix_world @ rig.pose.bones[chain[-1]].tail
for f in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
    chain = ["mixamorig:LeftHand%s%d" % (f, i) for i in (1, 2, 3)]
    if not all(c in rig.pose.bones for c in chain):
        continue
    for c in chain:
        rig.pose.bones[c].rotation_mode = 'XYZ'
    t0 = tip(chain)
    best, best_gain = None, -1.0
    for axis in range(3):
        for sign in (1.0, -1.0):
            for c in chain:
                e = [0.0, 0.0, 0.0]
                e[axis] = sign * math.radians(30)
                rig.pose.bones[c].rotation_euler = e
            gain = (tip(chain) - t0).dot(PALM)
            if gain > best_gain:
                best, best_gain = (axis, sign), gain
    amounts = (22.0, 30.0, 20.0) if f == "Thumb" else (CURL["1"], CURL["2"], CURL["3"])
    for c, deg in zip(chain, amounts):
        e = [0.0, 0.0, 0.0]
        e[best[0]] = best[1] * math.radians(deg)
        rig.pose.bones[c].rotation_euler = e
    print("CURL", f, "axis", "XYZ"[best[0]], best[1], "gain", round(best_gain, 3))
bpy.ops.object.mode_set(mode='OBJECT')
bpy.context.view_layer.update()

def head(name):
    return rig.matrix_world @ rig.pose.bones["mixamorig:" + name].head
elbow, wrist = head("LeftForeArm"), head("LeftHand")
knuckle = (head("LeftHandIndex1") + head("LeftHandPinky1")) * 0.5

# Bake the posed mesh, then keep the forearm and hand only.
dg = bpy.context.evaluated_depsgraph_get()
me = bpy.data.meshes.new_from_object(body.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
arm = bpy.data.objects.new("kevin_arm", me)
bpy.context.scene.collection.objects.link(arm)
arm.matrix_world = body.matrix_world.copy()
groups = {g.index: g.name for g in body.vertex_groups}
bm = bmesh.new()
bm.from_mesh(me)
dl = bm.verts.layers.deform.verify()
drop = []
for v in bm.verts:
    w_keep = sum(w for gi, w in v[dl].items() if any(k in groups.get(gi, "") for k in KEEP))
    if w_keep < 0.5:
        drop.append(v)
bmesh.ops.delete(bm, geom=drop, context='VERTS')
# Only the skin material: no mouth parts can survive this, but be sure.
skin = [i for i, m in enumerate(me.materials) if m and m.name.endswith("_skin")]
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in skin], context='FACES')
bm.to_mesh(me)
bm.free()
for o in list(bpy.data.objects):
    if o is not arm:
        bpy.data.objects.remove(o)

# Re-base: wrist at the origin; Blender X along the forearm, Z the back of the wrist (glTF +Y).
along = (wrist - elbow).normalized()
# The back of the hand faces away from the thigh: +X in the A-pose; square it to the forearm.
back = Vector((1.0, 0.0, 0.0))
back = (back - along * back.dot(along)).normalized()
side = back.cross(along)                      # Y = Z x X
basis = Matrix((along, side, back)).transposed()
frame = Matrix.Translation(wrist) @ basis.to_4x4()
arm.data.transform(frame.inverted() @ arm.matrix_world)
arm.matrix_world = Matrix.Identity(4)
for vg in list(arm.vertex_groups):
    arm.vertex_groups.remove(vg)
arm.data.update()
print("ARM verts", len(arm.data.vertices), "forearm length", round((wrist - elbow).length, 3),
      "hand length", round((knuckle - wrist).length, 3))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=False, export_skins=False,
                          export_animations=False, export_image_format='JPEG', export_jpeg_quality=90,
                          export_apply=True)
print("WROTE", OUT)
