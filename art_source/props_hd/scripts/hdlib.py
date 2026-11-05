"""Blender helpers for the HD props (run inside Blender 5.2).

All builder coordinates are in GODOT space - x right, y up, z toward the viewer - so the numbers
match the GDScript frames the props are placed in (furniture: origin on the wall at floor level,
local -Z out of the wall). G() converts to Blender's z-up space; the glTF exporter (+Y up) turns
it back into exactly these Godot coordinates.

Every primitive is real geometry with bevelled edges (Bevel modifier, harden normals), smooth
shading and UVs: box projection that follows a given wood-grain axis, cylindrical UVs on lathed
and swept shapes. Materials are PBR sets (albedo / OpenGL normal / ORM) from tex_build/.
"""
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix, Euler

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))
TEX = os.path.join(ROOT, "tex_build")
OUT = os.path.join(PROJ, "assets", "models", "hd_props")
BLEND = os.path.join(ROOT, "blend")
PREVIEW = os.path.join(ROOT, "previews")
DL = os.path.join(ROOT, "downloads")

AX = {"x": 0, "y": 1, "z": 2}


def G(x, y=None, z=None):
    """Godot (x, y, z) -> Blender vector."""
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


GODOT_TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def g_matrix(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """A transform written in Godot space (Euler YXZ like Godot's default), as a Blender matrix."""
    rx, ry, rz = rot
    m = (Matrix.Translation(Vector(loc)) @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
         @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Diagonal(Vector((*scale, 1.0))))
    return GODOT_TO_BLENDER @ m @ GODOT_TO_BLENDER.inverted()


# ————— materials —————

# key: texture set in tex_build (albedo/normal/orm) + metres per texture tile; or flat values.
MATS = {
    "wood": dict(tex="wood_furniture", scale=1.8),
    "wood_darkstain": dict(tex="wood_furniture_dark", scale=1.8),
    "wood_dark": dict(tex="wood_dark", scale=1.4),
    "pine": dict(tex="wood_pine", scale=0.8),
    "pine_dark": dict(tex="wood_pine_dark", scale=0.8),
    "handle": dict(tex="wood_dark", scale=0.6),
    "brass": dict(tex="brass", scale=0.35),
    "steel": dict(tex="steel", scale=0.4),
    "steel_dark": dict(tex="steel_dark", scale=0.4),
    "iron": dict(tex="iron", scale=0.5),
    "iron_green": dict(tex="iron_green", scale=0.5),
    "paint_black": dict(tex="paint_black", scale=0.5),
    "galvanized": dict(tex="galvanized", scale=0.5),
    "copper": dict(tex="copper", scale=0.4),
    "gold": dict(tex="gold", scale=0.3),
    "paint_green": dict(tex="paint_green", scale=1.2),
    "paint_red": dict(tex="paint_red", scale=0.8),
    "paint_livery": dict(tex="paint_livery", scale=1.0),
    "paint_cream": dict(tex="paint_cream", scale=1.0),
    "leather": dict(tex="leather_brown", scale=0.45),
    "leather_red": dict(tex="leather_red", scale=0.3),
    "leather_black": dict(tex="leather_black", scale=0.3),
    "canvas": dict(tex="canvas", scale=0.55),
    "canvas_dark": dict(tex="canvas_dark", scale=0.55),
    "canvas_green": dict(tex="canvas_green", scale=0.6),
    "felt_navy": dict(tex="felt_navy", scale=0.25),
    "kraft": dict(tex="kraft", scale=0.7),
    "kraft_dark": dict(tex="kraft_dark", scale=0.7),
    "paper": dict(tex="paper", scale=0.35),
    "paper_aged": dict(tex="paper_aged", scale=0.35),
    "rubber": dict(tex="rubber", scale=0.3),
    "coal": dict(tex="coal", scale=0.25),
    "rug": dict(tex="rug", scale=1.0, uv="unit"),
    "loco_green": dict(tex="loco_green", scale=1.6),
    "loco_black": dict(tex="loco_black", scale=1.6),
    "loco_red": dict(tex="loco_red", scale=1.2),
    "underframe": dict(tex="underframe", scale=1.2),
    "underframe_rust": dict(tex="underframe_rust", scale=1.2),
    "rust": dict(tex="rust", scale=0.8),
    "roof_canvas": dict(tex="roof_canvas", scale=1.5),
    # Generated albedo on a flat-ish surface (normal/orm borrowed from paper).
    "dial_station": dict(albedo="dial_station_albedo.jpg", normal="paper", scale=1.0, uv="unit", rough=0.45),
    "dial_guard": dict(albedo="dial_guard_albedo.jpg", normal="paper", scale=1.0, uv="unit", rough=0.45),
    "ledger_page": dict(albedo="ledger_page_albedo.jpg", normal="paper", scale=1.0, uv="unit", rough=0.85),
    "parcel_label": dict(albedo="parcel_label_albedo.jpg", normal="paper", scale=1.0, uv="unit", rough=0.85),
    # Flat materials.
    "enamel_white": dict(color=(0.86, 0.84, 0.79), rough=0.12, coat=True),
    "enamel_blue": dict(color=(0.05, 0.1, 0.28), rough=0.15),
    "bakelite": dict(color=(0.02, 0.018, 0.015), rough=0.18),
    "bakelite_brown": dict(color=(0.16, 0.06, 0.03), rough=0.2),
    "ink": dict(color=(0.02, 0.02, 0.05), rough=0.05),
    "string": dict(color=(0.74, 0.66, 0.5), rough=0.95),
    "leather_green": dict(tex="leather_green", scale=0.45),
    "glass": dict(color=(0.16, 0.2, 0.21), rough=0.03, alpha=0.32),
    "lens_red": dict(color=(0.6, 0.03, 0.02), rough=0.05, emit=(1.0, 0.06, 0.02), emit_k=2.0),
    "lens_white": dict(color=(0.95, 0.92, 0.8), rough=0.05, emit=(1.0, 0.92, 0.7), emit_k=2.0),
    "lcd": dict(color=(0.3, 0.38, 0.2), rough=0.2, emit=(0.22, 0.32, 0.1), emit_k=0.6),
    "bulb": dict(color=(1.0, 0.95, 0.8), rough=0.1, emit=(1.0, 0.86, 0.6), emit_k=6.0),
    "tea": dict(color=(0.16, 0.07, 0.02), rough=0.02),
    "water": dict(color=(0.35, 0.5, 0.55), rough=0.02, alpha=0.55),
    "black_paint_gloss": dict(color=(0.015, 0.015, 0.015), rough=0.3),
}

_mat_cache = {}


def _img(name, data):
    path = os.path.join(TEX, name)
    im = bpy.data.images.load(path, check_existing=True)
    if data:
        im.colorspace_settings.name = "Non-Color"
    return im


def _gltf_output_group():
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is None:
        ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        ng.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        ng.interface.new_socket("Thickness", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def mat(key):
    if key in _mat_cache:
        return _mat_cache[key]
    spec = MATS[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    links = nt.links
    if "tex" in spec or "albedo" in spec:
        base = spec.get("tex")
        alb = nt.nodes.new("ShaderNodeTexImage")
        alb.image = _img(spec.get("albedo") or base + "_albedo.jpg", False)
        tint = spec.get("tint")
        if tint:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            links.new(alb.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = (*tint, 1.0)
            links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
        nbase = spec.get("normal", base)
        nrm = nt.nodes.new("ShaderNodeTexImage")
        nrm.image = _img(nbase + "_normal.jpg", True)
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = spec.get("nstrength", 1.0)
        links.new(nrm.outputs["Color"], nmap.inputs["Color"])
        links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        if "albedo" in spec:
            bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.6)
            bsdf.inputs["Metallic"].default_value = 0.0
        else:
            orm = nt.nodes.new("ShaderNodeTexImage")
            orm.image = _img(base + "_orm.jpg", True)
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            links.new(orm.outputs["Color"], sep.inputs["Color"])
            links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
            links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
            grp = nt.nodes.new("ShaderNodeGroup")
            grp.node_tree = _gltf_output_group()
            links.new(sep.outputs["Red"], grp.inputs["Occlusion"])
    else:
        bsdf.inputs["Base Color"].default_value = (*spec["color"], 1.0)
        bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.5)
        bsdf.inputs["Metallic"].default_value = spec.get("metal", 0.0)
        if spec.get("coat"):
            bsdf.inputs["Coat Weight"].default_value = 0.6
        if "emit" in spec:
            bsdf.inputs["Emission Color"].default_value = (*spec["emit"], 1.0)
            bsdf.inputs["Emission Strength"].default_value = spec.get("emit_k", 1.0)
        if "alpha" in spec:
            bsdf.inputs["Alpha"].default_value = spec["alpha"]
            m.surface_render_method = "BLENDED"
    if "emit" in spec and ("tex" in spec or "albedo" in spec):
        bsdf.inputs["Emission Color"].default_value = (*spec["emit"], 1.0)
        bsdf.inputs["Emission Strength"].default_value = spec.get("emit_k", 1.0)
    _mat_cache[key] = m
    return m


def tex_scale(key):
    return MATS[key].get("scale", 1.0)


# ————— scene and objects —————

_parts = []


def reset():
    global _parts
    _parts = []
    _mat_cache.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def _new_obj(name, bm, key, bevel=0.0, segs=3, angle=30.0, smooth=True, harden=True):
    me = bpy.data.meshes.new(name)
    for f in bm.faces:
        f.smooth = smooth
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(key))
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if bevel > 0.0:
        md = obj.modifiers.new("Bevel", "BEVEL")
        md.width = bevel
        md.segments = segs
        md.limit_method = "ANGLE"
        md.angle_limit = math.radians(angle)
        md.harden_normals = harden
        md.miter_outer = "MITER_ARC"
        md.use_clamp_overlap = True
    elif smooth:
        me.set_sharp_from_angle(angle=math.radians(angle))
    _parts.append(obj)
    return obj


FONT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "assets", "fonts")


def text_on(name, text, target, center, size, key, font="Oswald.ttf", lift=0.003, line=0.85, inward=(0, 0, 1), flat=False):
    """Lettering lying on the surface of `target` (an object built here, still at its local
    coordinates): the text is laid out facing -Z around Godot `center`, then every vertex is
    pulled onto the target's nearest surface and lifted `lift` off it, so stencils and painted
    names follow the curve of a sack or a drum instead of floating in front of it. `inward` is the
    direction from the reader into the surface (default: a face toward -Z)."""
    fnt = bpy.data.fonts.load(os.path.join(FONT_DIR, font), check_existing=True)
    cu = bpy.data.curves.new(name + "Text", "FONT")
    cu.body = text
    cu.font = fnt
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.space_line = line
    ob = bpy.data.objects.new(name + "Text", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    for _ in range(0 if flat else 3):           # curved targets: enough vertices to follow them
        long = [e for e in bm.edges if e.calc_length() > size * 0.07]
        if long:
            bmesh.ops.subdivide_edges(bm, edges=long, cuts=1, use_grid_fill=False)
            bmesh.ops.triangulate(bm, faces=bm.faces[:])
    c = Vector(center)
    into = Vector(inward).normalized()               # Godot direction from the reader into the surface
    up = Vector((0, 1, 0))
    right = up.cross(-into).normalized()             # reading direction as seen by the reader
    up = (-into).cross(right).normalized()
    ray = G(*into)
    for v in bm.verts:
        u, w = v.co.x, v.co.y
        p = c + right * u + up * w
        hit, loc, nrm, _ = target.ray_cast(G(*(p - into * 1.0)), ray)
        if hit:
            if nrm.dot(ray) > 0:
                nrm = -nrm
            v.co = loc + nrm.normalized() * lift
        else:
            v.co = G(*p)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    _box_uv(bm, key, "x", _rng)
    return _new_obj(name, bm, key, 0.0, smooth=False)


def _uv_layer(bm):
    return bm.loops.layers.uv.verify()


def _box_uv(bm, key, grain, rng, local_of=None):
    """Box projection in Godot space; on each face the U axis follows `grain` where it can."""
    uv = _uv_layer(bm)
    s = tex_scale(key)
    off = (rng.random(), rng.random())
    gi = AX[grain] if grain else None
    for f in bm.faces:
        n = f.normal
        ng = (abs(n.x), abs(n.z), abs(n.y))            # blender normal -> godot axes |x|,|y|,|z|
        a = max(range(3), key=lambda i: ng[i])
        others = [i for i in range(3) if i != a]
        if gi is not None and gi in others:
            ua, va = gi, [o for o in others if o != gi][0]
        else:
            ua, va = others
        for lp in f.loops:
            co = lp.vert.co
            gc = (co.x, co.z, -co.y)
            lp[uv].uv = (gc[ua] / s + off[0], gc[va] / s + off[1])


_rng = random.Random(1)


def seed(k):
    _rng.seed(k)


def box(name, size, center, key, bevel=0.003, segs=3, grain="x", rot=(0, 0, 0)):
    """Box of Godot `size` centred at Godot `center`, rotated by Godot Euler `rot` (radians)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = size
    bmesh.ops.scale(bm, vec=Vector((sx, sz, sy)), verts=bm.verts)
    bm.normal_update()
    _box_uv(bm, key, grain, _rng)
    bmesh.ops.transform(bm, matrix=g_matrix(center, rot), verts=bm.verts)
    b = min(bevel, min(size) * 0.45)
    return _new_obj(name, bm, key, b, segs)


def _frame_from_axis(axis):
    """Rotation taking +Y (Godot up) to `axis` (a Godot vector)."""
    a = Vector(axis).normalized()
    up = Vector((0, 1, 0))
    if (a - up).length < 1e-6:
        return Matrix.Identity(3)
    if (a + up).length < 1e-6:
        return Matrix.Rotation(math.pi, 3, "X")
    return up.rotation_difference(a).to_matrix()


def lathe(name, profile, center, key, axis=(0, 1, 0), segs=64, smooth_angle=40.0, cap_bottom=True, cap_top=True,
          bevel=0.0, uv_rot=0.0):
    """Surface of revolution. `profile` = [(radius, height), ...] bottom to top (Godot local, about +Y),
    then rotated to `axis` and moved to `center`. Radii of 0 make poles."""
    bm = bmesh.new()
    uv = _uv_layer(bm)
    rings = []
    s = tex_scale(key)
    rot = _frame_from_axis(axis)
    for (r, h) in profile:
        ring = []
        for i in range(segs):
            t = math.tau * i / segs + uv_rot
            p = rot @ Vector((math.cos(t) * r, h, math.sin(t) * r))
            ring.append(bm.verts.new(G(p.x + center[0], p.y + center[1], p.z + center[2])))
        rings.append(ring)
    # Profile arc length for V.
    acc = [0.0]
    for k in range(1, len(profile)):
        (r0, h0), (r1, h1) = profile[k - 1], profile[k]
        acc.append(acc[-1] + math.hypot(r1 - r0, h1 - h0))
    rmax = max(max(r for r, _ in profile), 1e-3)
    circ = math.tau * rmax
    off = _rng.random()
    for k in range(len(rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            us = [i / segs * circ / s + off, (i + 1) / segs * circ / s + off]
            vs = [acc[k] / s, acc[k + 1] / s]
            for lp, (uu, vv) in zip(f.loops, ((us[0], vs[0]), (us[1], vs[0]), (us[1], vs[1]), (us[0], vs[1]))):
                lp[uv].uv = (uu, vv)
    for cap, ring, flip in ((cap_bottom, rings[0], True), (cap_top, rings[-1], False)):
        r = profile[0][0] if flip else profile[-1][0]
        if cap and r > 1e-5:
            f = bm.faces.new(list(reversed(ring)) if flip else ring)
            for lp in f.loops:
                c = lp.vert.co
                lp[uv].uv = (c.x / s, c.y / s)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_obj(name, bm, key, bevel, 2, smooth_angle, True, False)


def cyl(name, r, h, center, key, axis=(0, 1, 0), segs=48, r_top=None, bevel=0.002):
    """Cylinder (or cone frustum) centred at `center` along `axis`, with small bevelled rims."""
    rt = r if r_top is None else r_top
    b = min(bevel, r * 0.3, h * 0.3)
    prof = [(0.0, -h / 2), (r - b, -h / 2), (r, -h / 2 + b), (rt, h / 2 - b), (rt - b, h / 2), (0.0, h / 2)] if b > 0 \
        else [(0.0, -h / 2), (r, -h / 2), (rt, h / 2), (0.0, h / 2)]
    return lathe(name, prof, center, key, axis, segs, 35.0)


def sphere(name, r, center, key, scale=(1, 1, 1), segs=32, rings=16):
    prof = [(math.sin(math.pi * k / rings) * r, -math.cos(math.pi * k / rings) * r) for k in range(rings + 1)]
    obj = lathe(name, prof, (0, 0, 0), key, (0, 1, 0), segs, 80.0, False, False)
    obj.data.transform(g_matrix(center, (0, 0, 0), scale))
    return obj


def torus(name, R, r, center, key, axis=(0, 1, 0), segs=48, rsegs=16, arc=math.tau):
    bm = bmesh.new()
    uv = _uv_layer(bm)
    rot = _frame_from_axis(axis)
    s = tex_scale(key)
    closed = abs(arc - math.tau) < 1e-6
    n_major = segs if closed else segs + 1
    grid = []
    for i in range(n_major):
        t = arc * i / segs
        ring = []
        for j in range(rsegs):
            p = math.tau * j / rsegs
            rr = R + math.cos(p) * r
            v = rot @ Vector((math.cos(t) * rr, math.sin(p) * r, math.sin(t) * rr))
            ring.append(bm.verts.new(G(v.x + center[0], v.y + center[1], v.z + center[2])))
        grid.append(ring)
    for i in range(segs):
        i2 = (i + 1) % n_major if closed else i + 1
        for j in range(rsegs):
            j2 = (j + 1) % rsegs
            f = bm.faces.new((grid[i][j], grid[i2][j], grid[i2][j2], grid[i][j2]))
            for lp, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                lp[uv].uv = (a / segs * arc * R / s, b / rsegs * math.tau * r / s)
    if not closed:
        for ring, flip in ((grid[0], True), (grid[-1], False)):
            bm.faces.new(list(reversed(ring)) if flip else ring)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_obj(name, bm, key, 0.0, 2, 60.0)


def _fillet(points, bend):
    """Round the corners of a polyline with arcs of radius `bend`."""
    if bend <= 0 or len(points) < 3:
        return [Vector(p) for p in points]
    pts = [Vector(p) for p in points]
    out = [pts[0]]
    for k in range(1, len(pts) - 1):
        a, b, c = pts[k - 1], pts[k], pts[k + 1]
        d0 = (b - a).normalized()
        d1 = (c - b).normalized()
        ang = d0.angle(d1) if d0.length and d1.length else 0.0
        if ang < 1e-3:
            out.append(b)
            continue
        t = min(bend * math.tan(ang / 2), (b - a).length * 0.49, (c - b).length * 0.49)
        p0 = b - d0 * t
        p1 = b + d1 * t
        n = max(3, int(ang / math.radians(12)))
        for i in range(n + 1):
            u = i / n
            q = (1 - u) ** 2 * p0 + 2 * (1 - u) * u * b + u ** 2 * p1      # quadratic Bezier
            out.append(q)
    out.append(pts[-1])
    return out


def tube(name, points, radius, key, segs=16, bend=0.0, caps=True, radii=None):
    """Swept circle along a polyline of Godot points (rotation-minimising frames)."""
    pts = _fillet(points, bend)
    bm = bmesh.new()
    uv = _uv_layer(bm)
    s = tex_scale(key)
    rings = []
    t_prev = None
    nrm = None
    acc = [0.0]
    for k in range(1, len(pts)):
        acc.append(acc[-1] + (pts[k] - pts[k - 1]).length)
    for k, p in enumerate(pts):
        if k == 0:
            t = (pts[1] - pts[0]).normalized()
        elif k == len(pts) - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = ((pts[k + 1] - pts[k]).normalized() + (pts[k] - pts[k - 1]).normalized()).normalized()
        if nrm is None:
            helper = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
            nrm = t.cross(helper).normalized()
        else:
            nrm = (nrm - t * nrm.dot(t)).normalized()
        bin_ = t.cross(nrm)
        rr = radius if radii is None else radii[min(k, len(radii) - 1)]
        ring = []
        for j in range(segs):
            a = math.tau * j / segs
            q = p + (nrm * math.cos(a) + bin_ * math.sin(a)) * rr
            ring.append(bm.verts.new(G(q.x, q.y, q.z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for j in range(segs):
            j2 = (j + 1) % segs
            f = bm.faces.new((rings[k][j], rings[k][j2], rings[k + 1][j2], rings[k + 1][j]))
            for lp, (a, b) in zip(f.loops, ((j, k), (j + 1, k), (j + 1, k + 1), (j, k + 1))):
                lp[uv].uv = (a / segs * math.tau * radius / s, acc[b] / s)
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new_obj(name, bm, key, 0.0, 2, 50.0)


def rod(name, a, b, r, key, segs=16):
    return tube(name, [a, b], r, key, segs)


def extrude(name, poly, depth, key, center=(0, 0, 0), rot=(0, 0, 0), bevel=0.002, segs=2, grain="x"):
    """Flat shape: 2D polygon (x, y) in the local XY plane, extruded along local Z by `depth`
    (centred), then rotated/moved (Godot space)."""
    bm = bmesh.new()
    vs = [bm.verts.new(Vector((x, 0.0, y))) for x, y in poly]
    f = bm.faces.new(vs)
    if f.normal.y > 0:
        f.normal_flip()
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    moved = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, -depth, 0)), verts=moved)
    bmesh.ops.translate(bm, vec=Vector((0, depth / 2, 0)), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    _box_uv(bm, key, grain, _rng)
    bmesh.ops.transform(bm, matrix=g_matrix(center, rot), verts=bm.verts)
    return _new_obj(name, bm, key, bevel, segs)


def plane(name, size, center, key, normal="z", rot=(0, 0, 0), uv_unit=True, flip=False):
    """Single-sided quad (for printed dials, labels and the rug face) with 0-1 UVs."""
    w, h = size
    bm = bmesh.new()
    uv = _uv_layer(bm)
    corners = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    if normal == "z":                  # facing Godot -Z (out of a wall) when not flipped
        vs = [bm.verts.new(G(-x if not flip else x, y, 0)) for x, y in corners]
    else:                              # facing Godot +Y (lying on a table/floor)
        vs = [bm.verts.new(G(x, 0, -y if not flip else y)) for x, y in corners]
    f = bm.faces.new(vs)
    for lp, (u, v) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        lp[uv].uv = (u, v)
    bm.normal_update()
    bmesh.ops.transform(bm, matrix=g_matrix(center, rot), verts=bm.verts)
    return _new_obj(name, bm, key, 0.0, 1, 30.0, False)


def disc(name, r, center, key, segs=72, rot=(0, 0, 0)):
    """Round single-sided face toward Godot -Z with 0-1 UVs across its diameter (dials, labels)."""
    bm = bmesh.new()
    uv = _uv_layer(bm)
    c0 = bm.verts.new(G(0, 0, 0))
    ring = [bm.verts.new(G(-math.cos(math.tau * i / segs) * r, math.sin(math.tau * i / segs) * r, 0)) for i in range(segs)]
    for i in range(segs):
        f = bm.faces.new((c0, ring[i], ring[(i + 1) % segs]))
        for lp in f.loops:
            co = lp.vert.co
            lp[uv].uv = (0.5 - co.x / (2 * r), 0.5 + co.z / (2 * r))
    bm.normal_update()
    if next(iter(bm.faces)).normal.y < 0:
        for f in bm.faces:
            f.normal_flip()
    bmesh.ops.transform(bm, matrix=g_matrix(center, rot), verts=bm.verts)
    return _new_obj(name, bm, key, 0.0, 1, 30.0, False)


def move_last(n, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Transform the last n parts (Godot space) - for sub-assemblies built at the origin."""
    m = g_matrix(loc, rot)
    for o in _parts[-n:]:
        o.data.transform(m)


def count():
    return len(_parts)


def transform_since(start, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    m = g_matrix(loc, rot, scale)
    for o in _parts[start:]:
        o.data.transform(m)


# ————— finishing —————

def _apply_modifiers(objs):
    # Meshes edited in place (data.transform) must be tagged, or the depsgraph evaluates the
    # modifiers on the stale geometry.
    for o in objs:
        if o.modifiers:
            o.data.update()
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        if not o.modifiers:
            continue
        ev = o.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
        o.modifiers.clear()
        o.data = me


def finish(name):
    """Apply bevels, join every part into one mesh named `name`, return it."""
    objs = [o for o in _parts if o.name in bpy.data.objects]
    _apply_modifiers(objs)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    obj = objs[0]
    obj.name = name
    obj.data.name = name
    return obj


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def export(obj, name):
    os.makedirs(OUT, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT, name + ".gltf"), export_format="GLTF_SEPARATE",
        export_texture_dir="textures", use_selection=True, export_yup=True, export_apply=True,
        export_normals=True, export_tangents=True, export_materials="EXPORT",
        export_image_format="AUTO", export_cameras=False, export_lights=False, export_animations=False)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, name + ".blend"), compress=True)


def preview(obj, name, view=(-0.55, 0.45, -1.0)):
    """EEVEE studio render from the front three-quarter (Godot `view` direction toward the camera)."""
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE"
    scn.render.resolution_x = 640
    scn.render.resolution_y = 640
    scn.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.31, 0.3, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scn.world = world
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    c = (lo + hi) / 2
    size = (hi - lo).length
    d = G(*view).normalized()
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 60
    cam = bpy.data.objects.new("cam", cam_data)
    scn.collection.objects.link(cam)
    cam.location = c + d * size * 1.55
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    for nm, en, loc in (("key", 450, d * size * 2 + G(1.5, 2.5, 0.0) * size),
                        ("fill", 180, G(-2.0, 1.0, -1.0) * size * 1.5 + c),
                        ("rim", 300, G(0.5, 2.0, 2.0) * size * 1.5 + c)):
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy = en * size * size
        ld.size = size
        lo_ = bpy.data.objects.new(nm, ld)
        scn.collection.objects.link(lo_)
        lo_.location = loc if nm != "key" else c + loc
        lo_.rotation_euler = (c - lo_.location).to_track_quat("-Z", "Y").to_euler()
    # Floor plane under it.
    bpy.ops.mesh.primitive_plane_add(size=size * 6, location=(c.x, c.y, lo.z - 0.0005))
    os.makedirs(PREVIEW, exist_ok=True)
    scn.render.filepath = os.path.join(PREVIEW, name + ".png")
    bpy.ops.render.render(write_still=True)


# ————— Poly Haven model import (fit into a box in Godot space) —————

def import_ph(asset, fit, origin="bottom", yaw=0.0, keep=None, drop=None, drop_mats=()):
    """Import a downloaded Poly Haven glTF, join it, turn it by `yaw` (Godot radians about +Y) and
    scale it uniformly to fit inside Godot box `fit` = (w, h, d). origin: 'bottom' = bottom centre,
    'back' = bottom of the back face at z = 0 with the front toward -Z (wall frame)."""
    path = os.path.join(DL, "ph_models", asset, asset + ".gltf")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    if keep:
        meshes = [o for o in meshes if any(k in o.name for k in keep)]
    if drop:
        meshes = [o for o in meshes if not any(k in o.name for k in drop)]
    for o in new:
        if o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    for o in meshes:
        o.data = o.data.copy()
        if o.data.shape_keys:          # the evaluated mesh would follow the keys, not the moved vertices
            o.shape_key_clear()
        o.data.transform(o.matrix_world)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
        o.data.transform(g_matrix((0, 0, 0), (0, yaw, 0)))
        if drop_mats:
            bm = bmesh.new()
            bm.from_mesh(o.data)
            names = [m.name if m else "" for m in o.data.materials]
            gone = [f for f in bm.faces if any(k in names[f.material_index] for k in drop_mats)]
            bmesh.ops.delete(bm, geom=gone, context="FACES")
            bm.to_mesh(o.data)
            bm.free()
    _parts.extend(meshes)
    pts = [v.co for o in meshes for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    # Blender -> Godot extents: w = x, h = z, d = y
    w, h, d = hi.x - lo.x, hi.z - lo.z, hi.y - lo.y
    k = min(fit[0] / w if fit[0] else 1e9, fit[1] / h if fit[1] else 1e9, fit[2] / d if fit[2] else 1e9)
    cx = (lo.x + hi.x) / 2
    cy = (lo.y + hi.y) / 2
    if origin == "back":
        # Godot back face (max Godot z) = Blender min y.
        t = Matrix.Translation(Vector((-cx, -lo.y, -lo.z)))
    else:
        t = Matrix.Translation(Vector((-cx, -cy, -lo.z)))
    for o in meshes:
        o.data.transform(Matrix.Diagonal(Vector((k, k, k, 1))) @ t)
    return meshes, k
