# blender -b --factory-startup --python make_watch.py [-- render <out.png>]
# Kevin's digital wristwatch, in detail. Built in Godot's axes for the watch on his wrist: x along
# the forearm (the reading direction), y out of the face, z across the wrist (where the bracelet runs).
#   Case      a cushion-shaped steel case (superellipse footprint), its sides rounded like a barrel,
#             brushed on top; four lugs curving down toward the wrist, with the end pins
#   Bezel     a polished, chamfered steel ring round a black dial plate
#   Dial      the plate, with the display window cut in it; the LCD sits recessed below it
#   Crystal   mineral glass over the dial, domed a little, its edge chamfered
#   Pusher*   four pushers on collars (two each side, along the forearm)
# -> assets/viewmodels/watch_head.glb, and the bracelet's repeating link (centre link polished,
#    outer links brushed, the pins showing) -> assets/viewmodels/watch_link.glb (one link: x its
#    width along the forearm, y outward, z along the bracelet).
# With "-- render <png>" it also lays a ring of links round a dummy wrist and renders a beauty shot.
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix

OUT_HEAD = "A:/Trainwreck-ShiftV2/assets/viewmodels/watch_head.glb"
OUT_LINK = "A:/Trainwreck-ShiftV2/assets/viewmodels/watch_link.glb"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
A, B = 0.0182, 0.0170                         # case half extents (x along the arm, z across)
EXP = 4.2                                     # superellipse exponent: a cushion, not a box
H = 0.0072                                    # case height to the bezel seat
WIN = (0.0262, 0.0150, 0.0019)                # display window: x, z, corner radius
PITCH = 0.0048                                # bracelet link pitch

bpy.ops.wm.read_factory_settings(use_empty=True)
col = bpy.context.scene.collection

def mat(name, rgb, rough, metal=0.0, alpha=1.0, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
        p.inputs["Transmission Weight"].default_value = 1.0
        p.inputs["IOR"].default_value = 1.5
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1)
        p.inputs["Emission Strength"].default_value = 0.4
    return m

BRUSHED = mat("case_brushed", (0.78, 0.78, 0.8), 0.3, 1.0)
POLISHED = mat("steel_polished", (0.85, 0.85, 0.87), 0.1, 1.0)
DIAL = mat("dial_black", (0.012, 0.012, 0.014), 0.25)
LCD = mat("lcd", (0.6, 0.66, 0.6), 0.45, emit=(0.18, 0.3, 0.26))
GLASS = mat("glass", (1.0, 1.0, 1.0), 0.02, 0.0, alpha=0.08)

def superellipse(a, b, n=72, e=EXP):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2 / e), c), b * math.copysign(abs(s) ** (2 / e), s)))
    return pts

def rounded_rect(w, d, r, seg=6):
    pts = []
    for cx, cz, a0 in ((w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180), (w / 2 - r, -d / 2 + r, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts

def loft(name, outline, rings, m, cap_top=True, cap_bottom=True, smooth=True):
    """Rings of `outline` (x, z) scaled by s at height y, bridged; (s, y) from bottom to top."""
    bm = bmesh.new()
    loops = []
    for s, y in rings:
        loops.append([bm.verts.new((x * s, y, z * s)) for x, z in outline])
    n = len(outline)
    for a, b in zip(loops, loops[1:]):
        for i in range(n):
            f = bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
            f.smooth = smooth
    if cap_bottom:
        bm.faces.new(list(reversed(loops[0])))
    if cap_top:
        bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj(name, bm, m)

def ring_between(name, outer, inner, y_out, y_in, m, smooth=False):
    """A flat or sloped band between an outer and an inner outline (same point count)."""
    bm = bmesh.new()
    o = [bm.verts.new((x, y_out, z)) for x, z in outer]
    i_ = [bm.verts.new((x, y_in, z)) for x, z in inner]
    n = len(outer)
    for k in range(n):
        f = bm.faces.new((o[k], o[(k + 1) % n], i_[(k + 1) % n], i_[k]))
        f.smooth = smooth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        if f.normal.y < 0:
            f.normal_flip()
    return obj(name, bm, m)

def obj(name, bm, m):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    o.data.materials.append(m)
    col.objects.link(o)
    return o

def resample(pts, n):
    """`pts` (a closed outline) resampled to n points evenly by length, starting at angle 0."""
    seg = [(Vector(pts[i]), Vector(pts[(i + 1) % len(pts)])) for i in range(len(pts))]
    total = sum((b - a).length for a, b in seg)
    out, acc, k = [], 0.0, 0
    for j in range(n):
        want = total * j / n
        while acc + (seg[k][1] - seg[k][0]).length < want:
            acc += (seg[k][1] - seg[k][0]).length
            k += 1
        a, b = seg[k]
        t = (want - acc) / max((b - a).length, 1e-9)
        p = a.lerp(b, t)
        out.append((p.x, p.y))
    return out

head = []
N = 96
case_o = superellipse(A, B, N)
# The case: a barrel side, the top edge chamfered (polished) above the brushed flank.
head.append(loft("Case", case_o, [(0.9, 0.0), (0.955, 0.0007), (0.985, 0.0018), (1.0, 0.0034), (0.998, 0.0048),
                                   (0.99, 0.0058), (0.975, 0.0065), (0.955, H)], BRUSHED, cap_top=False))   # (the bezel closes it)
# The bezel: a polished chamfer from the case top inward and up, then flat, then down to the dial.
bz_out = [(x * 0.955, z * 0.955) for x, z in case_o]
bz_mid = [(x * 0.9, z * 0.9) for x, z in case_o]
bz_in = [(x * 0.84, z * 0.84) for x, z in case_o]
head.append(ring_between("BezelChamfer", bz_out, bz_mid, H, H + 0.0011, POLISHED))
head.append(ring_between("BezelTop", bz_mid, bz_in, H + 0.0011, H + 0.0011, POLISHED))
head.append(ring_between("BezelInner", bz_in, [(x * 0.832, z * 0.832) for x, z in case_o], H + 0.0011, H + 0.0004, POLISHED))
# The dial plate: black, the display window cut from it (the outline resampled to match).
dial_o = [(x * 0.832, z * 0.832) for x, z in case_o]
win = resample(rounded_rect(WIN[0], WIN[1], WIN[2]), N)
# (start both outlines at the same angle so the band does not twist)
def start_at_angle(pts):
    k = min(range(len(pts)), key=lambda i: abs(math.atan2(pts[i][1], pts[i][0])))
    return pts[k:] + pts[:k]
head.append(ring_between("Dial", start_at_angle(dial_o), start_at_angle(win), H + 0.0004, H + 0.0004, DIAL))
# The window's wall down to the LCD, and the LCD itself.
win_s = start_at_angle(win)
head.append(ring_between("WindowWall", win_s, [(x * 0.985, z * 0.985) for x, z in win_s], H + 0.0004, H - 0.0002, DIAL))
bm = bmesh.new()
vs = [bm.verts.new((x * 0.985, H - 0.0002, z * 0.985)) for x, z in win_s]
f = bm.faces.new(vs)
if f.normal.y < 0:
    f.normal_flip()
head.append(obj("LCD", bm, LCD))
# The crystal: domed a little, its edge chamfered down onto the bezel's inner step.
cr_o = [(x * 0.838, z * 0.838) for x, z in case_o]
rings = []
for k in range(7):
    s = 1.0 - k / 6
    rings.append((max(s, 0.001), H + 0.0012 + 0.0006 * (1 - s * s) + (0.0003 if k > 0 else 0.0)))
cr = loft("Crystal", cr_o, [(1.0, H + 0.0004)] + rings, GLASS, cap_bottom=False, cap_top=False)
head.append(cr)
# Lugs: from the case's ends across the wrist, curving down, with the pins between them.
for sz in (-1, 1):
    for sx in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(0.0036, 0.0042, 0.0062), verts=bm.verts[:])
        for v in bm.verts:
            t = (v.co.z * sz + 0.0031) / 0.0062                    # 0 at the case, 1 at the tip
            v.co.y += 0.0030 - 0.0026 * t * t                      # (curving down to the wrist)
            v.co.x *= 1.0 - 0.15 * t
        bmesh.ops.translate(bm, vec=(sx * 0.0112, 0, sz * (B * 0.82 + 0.0031)), verts=bm.verts[:])
        if sz < 0:
            bmesh.ops.scale(bm, vec=(1, 1, 1), verts=bm.verts[:])
        lug = obj("Lug", bm, BRUSHED)
        bv = lug.modifiers.new("round", 'BEVEL')
        bv.width = 0.0012
        bv.segments = 4
        lug.modifiers.new("smooth", 'SUBSURF').levels = 1
        for p in lug.data.polygons:
            p.use_smooth = True
        head.append(lug)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.0008, radius2=0.0008, depth=0.0228)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((0, 0.0013, sz * (B * 0.82 + 0.0047))) @ Matrix.Rotation(math.radians(90), 4, 'Y'), verts=bm.verts[:])
    head.append(obj("Pin", bm, POLISHED))
# Pushers: a collar and a cap, two each side along the arm.
for sx in (-1, 1):
    for sz in (-0.0085, 0.0085):
        for r, ln, off, m in ((0.0017, 0.0012, 0.0004, BRUSHED), (0.0012, 0.0022, 0.0018, POLISHED)):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=r, radius2=r, depth=ln)
            x = sx * (A * 0.985 + off)
            bmesh.ops.transform(bm, matrix=Matrix.Translation((x, 0.0036, sz)) @ Matrix.Rotation(math.radians(90), 4, 'Z'), verts=bm.verts[:])
            o = obj("Pusher", bm, m)
            for p in o.data.polygons:
                p.use_smooth = len(p.vertices) == 4
            bv = o.modifiers.new("ease", 'BEVEL')
            bv.width = 0.00025
            bv.segments = 2
            bv.limit_method = 'ANGLE'
            head.append(o)

# ——— the bracelet link: x its width, y outward, z along the bracelet ———
link = []
def rounded_box(name, sx, sy, sz, at, m, bevel):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts[:])
    bmesh.ops.translate(bm, vec=at, verts=bm.verts[:])
    o = obj(name, bm, m)
    bv = o.modifiers.new("round", 'BEVEL')
    bv.width = bevel
    bv.segments = 4
    for p in o.data.polygons:
        p.use_smooth = True
    return o
link.append(rounded_box("CentreLink", 0.0074, 0.0026, PITCH * 0.92, (0, 0.0013, 0), POLISHED, 0.0009))
for sx in (-1, 1):
    link.append(rounded_box("OuterLink", 0.0047, 0.0024, PITCH * 0.92, (sx * 0.0064, 0.0012, PITCH * 0.5), BRUSHED, 0.0008))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.00045, radius2=0.00045, depth=0.0004)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((sx * 0.0088, 0.0012, PITCH * 0.5)) @ Matrix.Rotation(math.radians(90), 4, 'Y'), verts=bm.verts[:])
    link.append(obj("LinkPin", bm, POLISHED))

turn = Matrix.Rotation(math.radians(90), 4, 'X')        # Godot (x, y, z) -> Blender (x, -z, y)

def export(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)

for o in head + link:
    o.matrix_world = turn @ o.matrix_world
bpy.context.view_layer.update()
# One mesh for the link (it is instanced many times in the game).
bpy.ops.object.select_all(action='DESELECT')
for o in link:
    for md in list(o.modifiers):
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=md.name)
    o.select_set(True)
bpy.context.view_layer.objects.active = link[0]
bpy.ops.object.join()
link_obj = link[0]
link_obj.name = "Link"
export(head, OUT_HEAD)
export([link_obj], OUT_LINK)
print("WROTE", OUT_HEAD, OUT_LINK)

# ——— a beauty shot for review ———
if len(ARGS) >= 2 and ARGS[0] == "render":
    sc = bpy.context.scene
    # The bracelet round a dummy wrist (radius 30 mm, centred under the case).
    R = 0.0315
    cy = -R - 0.0005
    n = int(2 * math.pi * R / PITCH)
    for k in range(n):
        a = 2 * math.pi * k / n
        if abs(math.sin(a)) < 0.62 and math.cos(a) > 0:   # (not under the case)
            continue
        d = Vector((0, math.cos(a), math.sin(a)))
        t = Vector((0, -math.sin(a), math.cos(a)))
        basis = Matrix((Vector((1, 0, 0)), d, Vector((1, 0, 0)).cross(d))).transposed()
        m4 = Matrix.Translation(Vector((0, cy, 0)) + d * R) @ basis.to_4x4()
        c = link_obj.copy()
        c.matrix_world = turn @ m4
        col.objects.link(c)
    # Digits on the display (DSEG7), for the picture only.
    fnt = bpy.data.fonts.load("A:/Trainwreck-ShiftV2/assets/fonts/DSEG7Classic-Bold.ttf")
    def text(body, size, at, colr):
        cu = bpy.data.curves.new("t", 'FONT')
        cu.body = body
        cu.font = fnt
        cu.size = size
        cu.align_x = 'CENTER'
        cu.align_y = 'CENTER'
        cu.offset_x = -0.0019                          # (DSEG's colon leaves the line off-centre)
        cu.fill_mode = 'BOTH'
        o = bpy.data.objects.new("t", cu)
        mm = mat("ink", colr, 0.5)
        o.data.materials.append(mm)
        col.objects.link(o)
        o.matrix_world = turn @ Matrix.Translation(at) @ Matrix.Rotation(math.radians(-90), 4, 'X')
        # (as a mesh: a font curve this small renders nothing)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
        print("TEXT MESH verts", len(me.vertices))
        mo = bpy.data.objects.new("digits", me)
        mo.matrix_world = o.matrix_world.copy()
        col.objects.link(mo)
        bpy.data.objects.remove(o)
        return mo
    t = text("19:08", 0.0078, Vector((0.0, H - 0.00012, 0.0004)), (0.02, 0.025, 0.022))
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
    sc.render.resolution_x, sc.render.resolution_y = 1400, 1000
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.012, 0.014, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, -0.07))
    bpy.context.object.data.materials.append(mat("floor", (0.035, 0.03, 0.028), 0.7))
    for loc, en, sz in (((0.22, 0.02, 0.1), 1.6, 0.12), ((-0.18, 0.1, 0.12), 0.7, 0.2), ((0.0, 0.2, 0.04), 0.5, 0.1)):
        ld = bpy.data.lights.new("L", 'AREA')
        ld.energy = en
        ld.size = sz
        lo = bpy.data.objects.new("L", ld)
        col.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0.003)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 90
    col.objects.link(cam)
    sc.camera = cam
    cam.location = (0.035, -0.085, 0.11)
    cam.rotation_euler = (Vector((0, 0, 0.002)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = ARGS[1]
    bpy.ops.render.render(write_still=True)
    print("RENDERED", ARGS[1])
