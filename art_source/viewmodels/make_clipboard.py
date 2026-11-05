# blender -b --factory-startup --python make_clipboard.py
# Kevin's clipboard, in detail: a hardboard board with rounded corners and eased edges, a stamped
# steel clip (riveted plate, spring jaw, hinge roll, bent-wire lever), a few sheets under the top one
# (the top sheet is the game's own: a SubViewport page), and a pencil tucked under the clip.
# Built in Godot's axes (x right, y up, z out of the board toward Kevin), turned to Blender's at the
# end. Centimetre-scale details: everything in metres.   -> assets/viewmodels/clipboard.glb
import bpy, bmesh, math
from mathutils import Vector, Matrix

OUT = "A:/Trainwreck-ShiftV2/assets/viewmodels/clipboard.glb"
W, H, T = 0.235, 0.325, 0.004                 # the board
bpy.ops.wm.read_factory_settings(use_empty=True)
col = bpy.context.scene.collection

def mat(name, rgb, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    return m

M_BOARD = mat("hardboard", (0.30, 0.18, 0.09), 0.7)
M_STEEL = mat("clip_steel", (0.62, 0.62, 0.64), 0.32, 1.0)
M_PAPER = mat("paper_under", (0.88, 0.86, 0.79), 0.9)
M_PAINT = mat("pencil_paint", (0.86, 0.62, 0.08), 0.45)
M_WOOD = mat("pencil_wood", (0.78, 0.6, 0.42), 0.8)
M_LEAD = mat("pencil_lead", (0.08, 0.08, 0.09), 0.35, 0.3)
M_BRASS = mat("pencil_ferrule", (0.72, 0.6, 0.32), 0.3, 1.0)
M_RUBBER = mat("pencil_eraser", (0.78, 0.38, 0.38), 0.85)

def obj(name, bm, m, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    o.data.materials.append(m)
    col.objects.link(o)
    return o

def rounded_slab(name, w, h, t, r, m, at=Vector(), seg=8, ease=0.0006):
    bm = bmesh.new()
    vs = [bm.verts.new((x * w / 2, y * h / 2, 0)) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    bm.faces.new(vs)
    bmesh.ops.bevel(bm, geom=bm.verts[:], offset=r, segments=seg, affect='VERTICES')
    f = max(bm.faces, key=lambda q: len(q.verts))
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)], vec=(0, 0, t))
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=(at.x, at.y, at.z - t / 2))
    o = obj(name, bm, m)
    if ease > 0:
        b = o.modifiers.new("ease", 'BEVEL')
        b.width = ease
        b.segments = 2
        b.limit_method = 'ANGLE'
    return o

def cyl(name, r, length, at, axis, m, verts=24, cap=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, segments=verts, radius1=r, radius2=r, depth=length)
    rot = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(at) @ rot, verts=bm.verts[:])
    return obj(name, bm, m, smooth=True)

parts = []
# The board.
parts.append(rounded_slab("Board", W, H, T, 0.011, M_BOARD))
# Sheets under the top one, a little askew.
for i, (rz, dx, dy) in enumerate(((0.012, 0.002, -0.004), (-0.02, -0.003, -0.006))):
    s = rounded_slab("SheetUnder%d" % i, 0.21, 0.28, 0.0003, 0.001, M_PAPER, Vector((dx, dy - 0.012, T / 2 + 0.0004 + i * 0.0004)), seg=1, ease=0)
    s.rotation_euler = (0, 0, rz)
    parts.append(s)
# The clip: a riveted base plate...
cy, cz = 0.142, T / 2 + 0.0016
parts.append(rounded_slab("ClipPlate", 0.112, 0.03, 0.0012, 0.004, M_STEEL, Vector((0, cy, cz + 0.0006))))
for sx in (-1, 1):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=0.0036)
    bmesh.ops.scale(bm, vec=(1, 1, 0.38), verts=bm.verts[:])
    bmesh.ops.translate(bm, vec=(sx * 0.042, cy - 0.004, cz + 0.0016), verts=bm.verts[:])
    parts.append(obj("Rivet", bm, M_STEEL, smooth=True))
# ...the hinge roll along its top edge...
hy, hz = cy + 0.012, cz + 0.0055
parts.append(cyl("HingeRoll", 0.0042, 0.104, Vector((0, hy, hz)), (1, 0, 0), M_STEEL))
# ...the spring jaw: a curved strip from the roll down onto the paper...
bm = bmesh.new()
n = 14
rows = []
for i in range(n + 1):
    a = math.radians(90 + 105 * i / n)
    p = Vector((0, hy + math.cos(a) * 0.0 + (i / n) * -0.028, hz + math.sin(a) * 0.0042 * (1 - i / n) - 0.0047 * (i / n)))
    rows.append([bm.verts.new((x, p.y, p.z)) for x in (-0.05, 0.05)])
for i in range(n):
    bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
jaw = obj("ClipJaw", bm, M_STEEL)
sol = jaw.modifiers.new("thick", 'SOLIDIFY')
sol.thickness = 0.0009
parts.append(jaw)
# A row of stamped ribs across the jaw (it is pressed steel, not a flat plate).
for sx in (-0.03, 0.0, 0.03):
    parts.append(cyl("JawRib", 0.0011, 0.016, Vector((sx, hy - 0.016, hz - 0.0018)), (0, 1, -0.32), M_STEEL, verts=10))
# ...and the bent-wire lever over the roll.
cu = bpy.data.curves.new("lever", 'CURVE')
cu.dimensions = '3D'
cu.bevel_depth = 0.0016
cu.bevel_resolution = 3
sp = cu.splines.new('POLY')
pts = [(-0.044, hy, hz), (-0.046, hy + 0.012, hz + 0.012), (-0.03, hy + 0.024, hz + 0.017), (0.03, hy + 0.024, hz + 0.017),
       (0.046, hy + 0.012, hz + 0.012), (0.044, hy, hz)]
sp.points.add(len(pts) - 1)
for p, c in zip(sp.points, pts):
    p.co = (*c, 1)
lever = bpy.data.objects.new("ClipLever", cu)
col.objects.link(lever)
lever.data.materials.append(M_STEEL)
parts.append(lever)
# A pencil tucked under the jaw on the right, lying down across the sheet's corner.
pl = 0.165
d = Vector((0.18, -1.0, 0)).normalized()
start = Vector((0.084, 0.168, T / 2 + 0.0045))
def along(u):
    return start + d * u
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.0037, radius2=0.0037, depth=pl - 0.03)
rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
bmesh.ops.transform(bm, matrix=Matrix.Translation(along(0.012 + (pl - 0.03) / 2)) @ rot, verts=bm.verts[:])
parts.append(obj("PencilBody", bm, M_PAINT))
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.0037, radius2=0.0011, depth=0.016)
bmesh.ops.transform(bm, matrix=Matrix.Translation(along(pl - 0.018 + 0.008)) @ rot, verts=bm.verts[:])
parts.append(obj("PencilWood", bm, M_WOOD, smooth=True))
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.0011, radius2=0.0002, depth=0.005)
bmesh.ops.transform(bm, matrix=Matrix.Translation(along(pl - 0.002 + 0.0005)) @ rot, verts=bm.verts[:])
parts.append(obj("PencilLead", bm, M_LEAD, smooth=True))
parts.append(cyl("PencilFerrule", 0.0039, 0.009, along(0.0075), d, M_BRASS, verts=16))
parts.append(cyl("PencilEraser", 0.0035, 0.006, along(0.0), d, M_RUBBER, verts=16))
# Rings pressed into the ferrule.
for u in (0.004, 0.011):
    parts.append(cyl("FerruleRing", 0.0041, 0.0008, along(u), d, M_BRASS, verts=16))

# Into Blender's axes (glTF writes y-up again): Godot (x, y, z) -> Blender (x, -z, y).
turn = Matrix.Rotation(math.radians(90), 4, 'X')
for o in parts:
    o.matrix_world = turn @ o.matrix_world
bpy.context.view_layer.update()
for o in parts:
    o.select_set(True)
print("PARTS", len(parts))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=True, export_yup=True)
print("WROTE", OUT)
