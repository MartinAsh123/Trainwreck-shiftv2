# make_vehicles.py — 1930s Central European road vehicles for the town scenery (Blender 5.x).
#   blender --background --factory-startup --python tools/blender/make_vehicles.py -- <out_dir>
# Writes car_sedan.glb, car_small.glb and truck.glb. Conventions (after glTF export into Godot):
#   - forward is -Z, up +Y, origin on the ground under the middle of the wheelbase
#   - wheels are separate nodes "Wheel_FL/FR/RL/RR" (spin about local X)
#   - the body paint is material "paint" so the game can recolour each car
#   - "lamp_head" / "lamp_tail" are emissive (headlights warm, tail lights red)
#   - a thin "snow" layer lies on roof, hood, fenders and boards
# Built from lofted cross-sections (rounded, with the period's narrow greenhouse), separate swept
# fenders, running boards, radiator shell with slats, bucket headlights, artillery-spoke wheels.
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]


# ————— materials (physically based: metallic 0 or 1; paint = dielectric with clearcoat) —————

def principled(name, color, rough, metallic=0.0, coat=0.0, alpha=1.0, emit=None, emit_strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metallic
    if coat > 0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.06
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


def materials():
    return {
        "paint": principled("paint", (0.03, 0.03, 0.035), 0.32, coat=0.8),
        "chrome": principled("chrome", (0.55, 0.56, 0.55), 0.06, metallic=1.0),
        "black": principled("black_metal", (0.02, 0.02, 0.022), 0.45),
        "rubber": principled("rubber", (0.022, 0.022, 0.022), 0.88),
        "glass": principled("glass", (0.04, 0.05, 0.06), 0.05, alpha=0.62),
        "seat": principled("leather", (0.12, 0.07, 0.045), 0.55),
        "wood": principled("wood_bed", (0.28, 0.18, 0.1), 0.7),
        "canvas": principled("canvas", (0.24, 0.24, 0.2), 0.9),
        "head": principled("lamp_head", (0.9, 0.85, 0.7), 0.1, emit=(1.0, 0.86, 0.6), emit_strength=6.0),
        "tail": principled("lamp_tail", (0.5, 0.02, 0.02), 0.2, emit=(1.0, 0.05, 0.02), emit_strength=3.0),
        "snow": principled("snow", (0.88, 0.9, 0.95), 0.75),
        "plate": principled("plate", (0.85, 0.83, 0.75), 0.6),
    }


def new_obj(name, bm, mats, parent=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if parent:
        o.parent = parent
    for p in me.polygons:
        p.use_smooth = True
    return o


# ————— body: lofted rounded sections —————

def section(hw, zb, zt, belt, n=36, power=5.5, tumble=0.12):
    """Closed cross-section (x, z) around the car: rounded box, narrowing above the belt line."""
    mid = (zb + zt) * 0.5
    hh = (zt - zb) * 0.5
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        x = hw * math.copysign(abs(c) ** (2 / power), c)
        z = mid + hh * math.copysign(abs(s) ** (2 / power), s)
        if z > belt:
            k = min(1.0, (z - belt) / max(zt - belt, 1e-3))
            x *= 1.0 - tumble * k
        pts.append((x, z))
    return pts


def loft(stations, belt_fn, glass_fn, n=36, cap_front=True, cap_back=True):
    """stations: list of (y, hw, zb, zt). Returns bmesh with material index 0 paint, 1 glass."""
    bm = bmesh.new()
    rings = []
    for (y, hw, zb, zt) in stations:
        ring = []
        for (x, z) in section(hw, zb, zt, belt_fn(y), n):
            ring.append(bm.verts.new((x, y, z)))
        rings.append(ring)
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        for i in range(n):
            f = bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
            c = sum((v.co for v in f.verts), Vector()) / 4
            f.material_index = 1 if glass_fn(c) else 0
    if cap_back:
        bm.faces.new(list(reversed(rings[0])))
    if cap_front:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def lathe(bm, prof, segs, axis_y=False, mat=0, center=Vector((0, 0, 0))):
    """Revolve (radius, h) about X (wheel axle: h along X) or Z."""
    rings = []
    for (r, h) in prof:
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            if axis_y:
                p = Vector((h, r * math.cos(a), r * math.sin(a)))
            else:
                p = Vector((r * math.cos(a), r * math.sin(a), h))
            ring.append(bm.verts.new(center + p))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]))
            f.material_index = mat
    return rings


def box(bm, c, size, mat=0, rot=None):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    vs = []
    for i in range(8):
        p = Vector((hx * (1 if i & 1 else -1), hy * (1 if i & 2 else -1), hz * (1 if i & 4 else -1)))
        if rot:
            p = rot @ p
        vs.append(bm.verts.new(Vector(c) + p))
    for f in [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]:
        bm.faces.new([vs[i] for i in f]).material_index = mat


def fender(bm, cy, cz, x_in, x_out, r, a0, a1, segs=18, mat=0, drop_front=0.0, drop_back=0.0):
    """Swept fender over a wheel: an arched shell from angle a0 to a1 (radians, 0 = forward)."""
    prof = [(x_in, 0.0), (x_in + 0.02, 0.05), (x_out - 0.02, 0.06), (x_out, 0.0)]
    rings = []
    for k in range(segs + 1):
        a = a0 + (a1 - a0) * k / segs
        rr = r
        y = cy + rr * math.cos(a)
        z = cz + rr * math.sin(a)
        nrm = Vector((0, math.cos(a), math.sin(a)))
        ring = [bm.verts.new(Vector((x, y, z)) + nrm * t) for (x, t) in prof]
        rings.append(ring)
    for k in range(segs):
        for i in range(len(prof) - 1):
            bm.faces.new((rings[k][i], rings[k][i + 1], rings[k + 1][i + 1], rings[k + 1][i])).material_index = mat


def wheel(name, mats, r_tyre, width, spokes, parent, pos):
    bm = bmesh.new()
    rt = r_tyre
    w = width
    tyre = [(rt * 0.72, -w / 2), (rt * 0.92, -w / 2 - 0.004), (rt, -w * 0.3), (rt * 1.005, 0), (rt, w * 0.3),
            (rt * 0.92, w / 2 + 0.004), (rt * 0.72, w / 2)]
    lathe(bm, tyre, 28, axis_y=True, mat=0)
    rim = [(rt * 0.72, w / 2), (rt * 0.68, w * 0.3), (rt * 0.66, -w * 0.3), (rt * 0.72, -w / 2)]
    lathe(bm, rim, 28, axis_y=True, mat=1)
    hub = [(rt * 0.2, w * 0.35), (rt * 0.16, w * 0.55), (rt * 0.05, w * 0.62), (0.001, w * 0.62)]
    lathe(bm, hub, 18, axis_y=True, mat=2)
    for s in range(spokes):
        a = 2 * math.pi * s / spokes
        d = Vector((0, math.cos(a), math.sin(a)))
        mid = d * (rt * 0.43)
        rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix()
        box(bm, mid + Vector((w * 0.18, 0, 0)), (0.03, 0.03, rt * 0.5), mat=1, rot=rot)
    o = new_obj(name, bm, [mats["rubber"], mats["paint"], mats["chrome"]], parent)
    o.location = pos
    return o


def snow_cap(src, mats, thickness=0.025, min_up=0.55, name="Snow"):
    """A thin layer on every upward face of `src` (roof, hood, fenders, boards)."""
    bm = bmesh.new()
    bm.from_mesh(src.data)
    def patchy(f):
        c = f.calc_center_median()
        n = math.sin(c.x * 9.1 + 1.3) * math.sin(c.y * 7.3) + 0.6 * math.sin(c.x * 23.0 + c.y * 19.0)
        return n > -0.55
    keep = [f for f in bm.faces if f.normal.z > min_up and patchy(f)]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for v in bm.verts:
        n = v.normal.copy()
        jitter = 0.6 + 0.8 * ((math.sin(v.co.x * 41.0) * math.sin(v.co.y * 23.0) + 1) * 0.5)
        v.co += n * thickness * jitter
    o = new_obj(name, bm, [mats["snow"]], src.parent)
    o.matrix_parent_inverse = src.matrix_parent_inverse
    o.location = src.location
    return o


# ————— vehicles —————

def build_car(kind):
    mats = materials()
    root = bpy.data.objects.new(kind, None)
    bpy.context.scene.collection.objects.link(root)
    if kind == "car_sedan":
        L, wheel_r, wb, track = 4.3, 0.37, 2.95, 1.34
        # Bustle trunk, tall cabin with a raked screen, cowl, then a narrow bonnet between the wings.
        st = [(-2.08, 0.62, 0.55, 0.86), (-2.0, 0.7, 0.5, 1.06), (-1.8, 0.74, 0.48, 1.28), (-1.52, 0.77, 0.47, 1.5),
              (-1.3, 0.78, 0.47, 1.6), (0.0, 0.78, 0.47, 1.64), (0.45, 0.78, 0.47, 1.62), (0.62, 0.77, 0.48, 1.56),
              (0.8, 0.62, 0.52, 1.12), (0.9, 0.4, 0.55, 1.09), (1.4, 0.37, 0.57, 1.07), (1.88, 0.36, 0.58, 1.05),
              (1.95, 0.34, 0.6, 1.0)]
        belt = 1.08
        glass = lambda c: (c.z > belt + 0.07 and c.z < 1.57 and -1.45 < c.y < 0.56
                           and not (-0.32 < c.y < -0.2) and abs(c.x) > 0.3) \
            or (0.6 < c.y < 0.8 and 1.15 < c.z < 1.55 and abs(c.x) < 0.66) \
            or (-1.75 < c.y < -1.4 and 1.2 < c.z < 1.46 and abs(c.x) < 0.42)
        cab = None
    elif kind == "car_small":
        L, wheel_r, wb, track = 3.6, 0.33, 2.45, 1.24
        # Fastback two-door: the roof runs down into the tail.
        st = [(-1.8, 0.6, 0.52, 0.86), (-1.62, 0.68, 0.48, 1.2), (-1.3, 0.71, 0.46, 1.44), (-0.9, 0.72, 0.46, 1.54),
              (0.15, 0.72, 0.46, 1.55), (0.38, 0.71, 0.47, 1.5), (0.58, 0.58, 0.5, 1.06), (0.68, 0.36, 0.53, 1.03),
              (1.2, 0.33, 0.55, 1.0), (1.58, 0.32, 0.56, 0.98), (1.65, 0.3, 0.58, 0.94)]
        belt = 1.0
        glass = lambda c: (c.z > belt + 0.07 and c.z < 1.47 and -1.2 < c.y < 0.32 and not (-0.45 < c.y < -0.35)
                           and abs(c.x) > 0.28) or (0.38 < c.y < 0.6 and 1.08 < c.z < 1.46 and abs(c.x) < 0.6)
        cab = None
    else:  # truck: cab + bonnet loft, flat bed behind
        L, wheel_r, wb, track = 5.4, 0.42, 3.2, 1.5
        st = [(0.1, 0.84, 0.5, 1.9), (0.3, 0.85, 0.5, 2.0), (0.95, 0.85, 0.5, 2.0), (1.18, 0.82, 0.52, 1.95),
              (1.4, 0.76, 0.55, 1.38), (2.1, 0.5, 0.6, 1.3), (2.62, 0.44, 0.62, 1.26), (2.7, 0.4, 0.64, 1.22)]
        belt = 1.32
        glass = lambda c: (c.z > belt + 0.08 and c.z < 1.88 and 0.35 < c.y < 1.0 and abs(c.x) > 0.4) \
            or (1.05 < c.y < 1.4 and 1.4 < c.z < 1.9)
        cab = True
    belt_fn = lambda y: belt
    body = new_obj("Body", loft(st, belt_fn, glass), [mats["paint"], mats["glass"]], root)
    bev = body.modifiers.new("edges", "BEVEL")
    bev.width = 0.012
    bev.segments = 2
    bev.limit_method = "ANGLE"
    # Wheel positions (y along the car, forward +Y).
    fy = (st[-1][0] - 0.55) if cab is None else 2.2
    ry = fy - wb
    wz = wheel_r
    hx = track / 2
    # Fenders: front long and sweeping into the board, rear shorter.
    bmf = bmesh.new()
    for side in (-1, 1):
        x_in, x_out = side * (hx - 0.13), side * (hx + 0.15)
        if side < 0:
            x_in, x_out = x_out, x_in
        fender(bmf, fy, wz, x_in, x_out, wheel_r + 0.07, math.radians(-25), math.radians(200))
        fender(bmf, ry, wz, x_in, x_out, wheel_r + 0.07, math.radians(-15), math.radians(185))
        # Running board between the wheels.
        if cab is None or True:
            box(bmf, (side * (hx + 0.02), (fy + ry) / 2, 0.44), (0.3, abs(fy - ry) - wheel_r * 2.0, 0.03), mat=1)
    fen = new_obj("Fenders", bmf, [mats["paint"], mats["black"]], root)
    # Chrome: radiator shell with slats, bumpers, headlight buckets on a bar; lamps.
    front = st[-1][0]
    rad_top = st[-1][3] - 0.02
    bmc = bmesh.new()
    box(bmc, (0, front + 0.02, (0.55 + rad_top) / 2), (0.62 if cab is None else 0.72, 0.06, rad_top - 0.5), mat=0)
    for i in range(9):
        box(bmc, (-0.24 + i * 0.06, front + 0.055, (0.58 + rad_top) / 2), (0.018, 0.02, rad_top - 0.6), mat=2)
    box(bmc, (0, front + 0.3, 0.5), (track + 0.3, 0.07, 0.1), mat=0)
    for side in (-1, 1):
        box(bmc, (side * 0.45, front + 0.18, 0.52), (0.04, 0.24, 0.04), mat=1)
    rear = st[0][0] if cab is None else -L + 2.75
    box(bmc, (0, rear - 0.12, 0.5), (track + 0.3, 0.07, 0.1), mat=0)
    for side in (-1, 1):
        box(bmc, (side * 0.45, rear - 0.05, 0.52), (0.04, 0.16, 0.04), mat=1)
    if cab:
        for side in (-1, 1):
            box(bmc, (side * 0.42, (rear + 2.6) / 2 - 0.4, 0.62), (0.08, abs(2.6 - rear) + 0.4, 0.16), mat=1)
    box(bmc, (0, front + 0.1, 0.98 if cab is None else 1.1), (0.9, 0.03, 0.03), mat=0)
    lamp_y = front + 0.1
    lamp_z = 1.02 if cab is None else 1.14
    for side in (-1, 1):
        lathe(bmc, [(0.0, 0.0), (0.09, 0.03), (0.115, 0.12), (0.12, 0.17)], 20, axis_y=False, mat=0,
              center=Vector((side * 0.42, lamp_y, lamp_z)))
    chrome = new_obj("Chrome", bmc, [mats["chrome"], mats["black"], mats["black"]], root)
    for o in (chrome,):
        for v in o.data.vertices:
            pass
    # Headlight lenses (emissive discs facing forward) and tail lights.
    bml = bmesh.new()
    for side in (-1, 1):
        c = Vector((side * 0.42, lamp_y + 0.165, lamp_z))
        ring = [bml.verts.new(c + Vector((math.cos(a) * 0.11, 0.0, math.sin(a) * 0.11)))
                for a in [2 * math.pi * k / 20 for k in range(20)]]
        f = bml.faces.new(ring)
    # The lathe above opens along +Z; turn the buckets to face forward afterwards.
    lenses = new_obj("Headlights", bml, [mats["head"]], root)
    bmt = bmesh.new()
    for side in (-1, 1):
        box(bmt, (side * (hx + 0.05), (rear if cab is None else -L + 2.85) + 0.05, 0.75), (0.08, 0.04, 0.06), mat=0)
    tails = new_obj("Taillights", bmt, [mats["tail"]], root)
    # Fix the headlight buckets: built along +Z, rotate each to face +Y.
    _turn_buckets(chrome, lamp_y, lamp_z)
    # Interior: seats behind the glass.
    bms = bmesh.new()
    if cab is None:
        for y in (-0.15, -1.0):
            box(bms, (0, y, 0.75), (track - 0.2, 0.5, 0.18), mat=0)
            box(bms, (0, y - 0.25, 1.05), (track - 0.2, 0.1, 0.55), mat=0)
    else:
        box(bms, (0, 0.55, 0.95), (1.3, 0.5, 0.2), mat=0)
    new_obj("Seats", bms, [mats["seat"]], root)
    # Truck bed: planked deck with sides and a lashed canvas load.
    if cab:
        bmb = bmesh.new()
        bed_y0, bed_y1 = -L + 2.75, 0.0
        box(bmb, (0, (bed_y0 + bed_y1) / 2, 0.82), (track + 0.5, bed_y1 - bed_y0, 0.08), mat=0)
        for side in (-1, 1):
            box(bmb, (side * (track / 2 + 0.24), (bed_y0 + bed_y1) / 2, 1.07), (0.05, bed_y1 - bed_y0, 0.42), mat=0)
        box(bmb, (0, bed_y0 + 0.02, 1.07), (track + 0.5, 0.05, 0.42), mat=0)
        bed = new_obj("Bed", bmb, [mats["wood"]], root)
        bmk = bmesh.new()
        bmk_rings = []
        for i in range(9):
            y = bed_y0 + 0.2 + i * (bed_y1 - bed_y0 - 0.5) / 8
            ring = []
            for k in range(13):
                a = math.pi * k / 12
                ring.append(bmk.verts.new((math.cos(a) * (track / 2 + 0.1), y, 0.88 + math.sin(a) * 0.55 * (1.0 - 0.15 * abs(math.cos(a))))))
            bmk_rings.append(ring)
        for i in range(8):
            for k in range(12):
                bmk.faces.new((bmk_rings[i][k], bmk_rings[i][k + 1], bmk_rings[i + 1][k + 1], bmk_rings[i + 1][k]))
        load = new_obj("Load", bmk, [mats["canvas"]], root)
        snow_cap(load, mats, 0.035, 0.4, "SnowLoad")
    # Wheels (spare on the back of the cars).
    spokes = 10
    for (nm, x, y) in [("Wheel_FL", -hx, fy), ("Wheel_FR", hx, fy), ("Wheel_RL", -hx, ry), ("Wheel_RR", hx, ry)]:
        w = wheel(nm, mats, wheel_r, 0.14 if cab is None else 0.18, spokes, root, (x, y, wz))
        if x < 0:
            w.rotation_euler = (0, 0, math.pi)
    if cab is None:
        sp = wheel("SpareWheel", mats, wheel_r, 0.14, spokes, root, (0, st[0][0] - 0.12, 0.72))
        sp.rotation_euler = (0, 0, math.pi * 0.5)
    # Number plate.
    bmp = bmesh.new()
    box(bmp, (0, front + 0.33, 0.6), (0.36, 0.01, 0.1), mat=0)
    new_obj("Plate", bmp, [mats["plate"]], root)
    # Snow on the upper surfaces (body evaluated with its subdivision first).
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(deps)
    tmp = bpy.data.meshes.new_from_object(ev)
    tmp_o = bpy.data.objects.new("BodyEval", tmp)
    bpy.context.scene.collection.objects.link(tmp_o)
    tmp_o.parent = root
    snow_cap(tmp_o, mats, 0.018, 0.82, "SnowBody")
    bpy.data.objects.remove(tmp_o)
    snow_cap(fen, mats, 0.015, 0.75, "SnowFenders")
    return root


def _turn_buckets(chrome, lamp_y, lamp_z):
    """The headlight buckets were lathed about +Z; rotate their vertices to open toward +Y."""
    me = chrome.data
    for v in me.vertices:
        if abs(v.co.z - lamp_z) < 0.25 and abs(v.co.y - lamp_y) < 0.2 and abs(abs(v.co.x) - 0.42) < 0.14:
            c = Vector((math.copysign(0.42, v.co.x), lamp_y, lamp_z))
            d = v.co - c
            # (dx, dy, dz) about +Z  ->  (dx, dz, -dy): opening toward +Y
            v.co = c + Vector((d.x, d.z, -d.y))


def export(root, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + list(root.children_recursive):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind in ("car_sedan", "car_small", "truck"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        root = build_car(kind)
        export(root, os.path.join(OUT, kind + ".glb"))
        print("[vehicles] wrote", kind)


main()
