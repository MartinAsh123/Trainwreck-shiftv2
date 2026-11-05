# weather_bake.py — gives flat, "plasticky" props a believable material finish (Blender, Cycles).
#
#   blender --background --factory-startup --python tools/weather_bake.py -- <in.glb|gltf> <out.glb> [size] [strength] [keepuv] [hints.json]
#
#   keepuv  bake into the model's own first UV map (use for single-atlas models such as the Tripo
#           exports, so existing prefab materials can take the new maps) instead of a fresh one
#   hints   JSON {"regions": [{"hsv": [h, s, v], "tol": [dh, ds, dv], "class": "brass|steel|paint|
#           wood|white|dark|other"}], "strength": 1.0} telling which colours are which material,
#           for textures that carry no metallic information
#
# 1. Imports the model and lays out one fresh, non-overlapping UV map ("BakeUV") over all its meshes.
# 2. Bakes from the original materials into that UV: base colour, roughness, metallic, tangent-space
#    normal (keeps any existing normal map), plus geometry maps: ambient occlusion, an edge mask
#    (Bevel node vs. true normal) and three channels of object-space 3D noise.
# 3. Composes new maps per texel (numpy), by material class guessed from colour + metallic:
#      brass / steel / painted metal / wood / white enamel-plastic-ceramic / dark rubber-bakelite / other
#    - albedo: dirt in cavities, faint grime and colour variation, edge wear (paint chipped to primer
#      or metal, brass polished bright at edges and tarnished in recesses, wood worn lighter)
#    - roughness: variation, rougher dirt, smoother rubbed edges, fingerprint-like smudges on metal
#    - normal: micro relief from the texture's own fine detail + class-specific grain, blended onto
#      the baked normal
#    Everything stays subtle: the original colours and design are kept.
# 4. Rebuilds one material per mesh using the new maps (occlusion/roughness/metallic packed as ORM)
#    and exports a .glb with embedded textures.
import math
import os
import sys

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC = argv[0]
DST = argv[1]
SIZE = int(argv[2]) if len(argv) > 2 else 2048
STRENGTH = float(argv[3]) if len(argv) > 3 else 1.0
KEEP_UV = len(argv) > 4 and argv[4] == "keepuv"
HINTS = {}
if len(argv) > 5 and argv[5] and os.path.exists(argv[5]):
    import json
    HINTS = json.load(open(argv[5], encoding="utf-8"))
UV = "BakeUV"
MARGIN = 8


def log(*a):
    print("[weather]", *a, flush=True)


# ————— scene setup —————

def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for dev_type in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
        try:
            prefs.compute_device_type = dev_type
            prefs.get_devices()
            if any(d.type == dev_type for d in prefs.devices):
                for d in prefs.devices:
                    d.use = d.type == dev_type
                sc.cycles.device = "GPU"
                log("bake device", dev_type)
                break
        except Exception:
            continue
    sc.cycles.samples = 16
    sc.cycles.use_denoising = False
    sc.render.bake.margin = MARGIN
    sc.render.bake.margin_type = "EXTEND"


def import_model(path):
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    return meshes


def bounds(meshes):
    lo = np.array([1e9] * 3)
    hi = np.array([-1e9] * 3)
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ __import__("mathutils").Vector(c)
            lo = np.minimum(lo, np.array(w))
            hi = np.maximum(hi, np.array(w))
    return lo, hi


# ————— UV —————

def make_bake_uv(meshes):
    global UV
    if KEEP_UV:
        UV = meshes[0].data.uv_layers[0].name
        for o in meshes:
            if o.data.uv_layers[0].name != UV:
                o.data.uv_layers[0].name = UV
        return
    for o in meshes:
        me = o.data
        if "BakeUV" not in me.uv_layers:
            me.uv_layers.new(name="BakeUV")
        me.uv_layers.active = me.uv_layers["BakeUV"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


# ————— baking —————

def new_image(name, alpha=False, data=False):
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=alpha, float_buffer=data)
    if data:
        img.colorspace_settings.name = "Non-Color"
    return img


def target_node(mat, img):
    nt = mat.node_tree
    n = nt.nodes.get("__bake_target")
    if n is None:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.name = "__bake_target"
        uv = nt.nodes.new("ShaderNodeUVMap")
        uv.name = "__bake_uv"
        uv.uv_map = UV
        nt.links.new(uv.outputs["UV"], n.inputs["Vector"])
    n.image = img
    for x in nt.nodes:
        x.select = False
    n.select = True
    nt.nodes.active = n


def all_materials(meshes):
    mats = []
    for o in meshes:
        if not o.data.materials:
            m = bpy.data.materials.new("auto_" + o.name)
            m.use_nodes = True
            o.data.materials.append(m)
        for m in o.data.materials:
            if m and m not in mats:
                if not m.use_nodes:
                    m.use_nodes = True
                mats.append(m)
    return mats


def bake(meshes, mats, img, bake_type, **kw):
    for m in mats:
        target_node(m, img)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.bake(type=bake_type, use_clear=True, margin=MARGIN, uv_layer=UV, **kw)


def out_socket(mat):
    nt = mat.node_tree
    for n in nt.nodes:
        if n.type == "OUTPUT_MATERIAL" and n.is_active_output:
            return n
    n = nt.nodes.new("ShaderNodeOutputMaterial")
    return n


def principled(mat):
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def bake_emit_from(meshes, mats, img, make_source):
    """Temporarily routes a per-material source socket into an Emission shader and bakes EMIT."""
    saved = []
    for m in mats:
        nt = m.node_tree
        out = out_socket(m)
        prev = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].links else None
        em = nt.nodes.new("ShaderNodeEmission")
        em.name = "__bake_emit"
        make_source(m, nt, em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        saved.append((m, prev, em))
    bake(meshes, mats, img, "EMIT")
    for m, prev, em in saved:
        nt = m.node_tree
        out = out_socket(m)
        nt.nodes.remove(em)
        if prev is not None:
            nt.links.new(prev, out.inputs["Surface"])


def link_value(nt, socket_from_input, dst, scalar=True):
    """Connects whatever feeds a Principled input (or its constant) to dst."""
    if socket_from_input is None:
        dst.default_value = (0.0, 0.0, 0.0, 1.0)
        return
    if socket_from_input.links:
        nt.links.new(socket_from_input.links[0].from_socket, dst)
    else:
        v = socket_from_input.default_value
        if scalar:
            dst.default_value = (v, v, v, 1.0)
        else:
            dst.default_value = tuple(v)


def img_array(img):
    a = np.array(img.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)
    return a


def set_pixels(img, arr):
    img.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    img.update()


# ————— composing —————

def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.max(rgb, axis=-1)
    mn = np.min(rgb, axis=-1)
    d = mx - mn + 1e-6
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    s = np.where(mx > 1e-4, (mx - mn) / (mx + 1e-6), 0.0)
    return h, s, mx


def blur(a, r):
    """Cheap separable box blur (repeated) on a 2D array."""
    out = a.copy()
    for _ in range(2):
        c = np.cumsum(np.pad(out, ((0, 0), (r + 1, r)), mode="edge"), axis=1)
        out = (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)
        c = np.cumsum(np.pad(out, ((r + 1, r), (0, 0)), mode="edge"), axis=0)
        out = (c[2 * r + 1:, :] - c[:-2 * r - 1, :]) / (2 * r + 1)
    return out


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def compose(base, rough, metal, nrm, ao, edge, noise):
    rgb = base[..., :3]
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    h, s, v = rgb_to_hsv(np.clip(rgb, 0, 1) ** (1 / 2.2))
    n1, n2, n3 = noise[..., 0], noise[..., 1], noise[..., 2]
    k = STRENGTH
    valid = smooth(0.2, 0.6, base[..., 3])
    # Models without a metallic map (most Tripo exports): gold-hued, bright, saturated texels are brass.
    if float(metal.max()) < 0.05:
        metal = (smooth(0.3, 0.45, s) * (1 - smooth(0.04, 0.07, np.abs(h - 0.12))) * smooth(0.45, 0.6, v)).astype(np.float32)
    # Classes (soft weights).
    is_metal = smooth(0.35, 0.65, metal)
    brass = is_metal * smooth(0.25, 0.45, s) * (1 - smooth(0.17, 0.22, np.abs(h - 0.12) + 0.0))
    steel = is_metal * (1 - brass)
    nonm = 1 - is_metal
    wood = nonm * smooth(0.25, 0.4, s) * (1 - smooth(0.06, 0.1, np.abs(h - 0.07))) * (1 - smooth(0.55, 0.75, v))
    white = nonm * (1 - smooth(0.12, 0.25, s)) * smooth(0.62, 0.8, v)
    dark = nonm * (1 - smooth(0.1, 0.25, v))
    paint = np.clip(nonm - wood - white - dark, 0, 1) * smooth(0.2, 0.35, s)
    other = np.clip(1 - brass - steel - wood - white - dark - paint, 0, 1)
    cls = {"brass": brass, "steel": steel, "wood": wood, "white": white, "dark": dark, "paint": paint, "other": other}
    for reg in HINTS.get("regions", []):
        c = reg["hsv"]
        t = reg.get("tol", [0.04, 0.12, 0.15])
        dh = np.minimum(np.abs(h - c[0]), 1 - np.abs(h - c[0]))
        w = (1 - smooth(t[0] * 0.6, t[0], dh)) * (1 - smooth(t[1] * 0.6, t[1], np.abs(s - c[1])))             * (1 - smooth(t[2] * 0.6, t[2], np.abs(v - c[2])))
        w = w * valid
        for name in cls:
            cls[name] = cls[name] * (1 - w)
        cls[reg["class"]] = cls[reg["class"]] + w
        if reg["class"] in ("brass", "steel"):
            metal = np.maximum(metal, w * reg.get("metallic", 1.0))
        else:
            metal = metal * (1 - w)
    brass, steel, wood, white, dark, paint, other = (cls[n] for n in ("brass", "steel", "wood", "white", "dark", "paint", "other"))
    is_metal = np.clip(brass + steel, 0, 1)
    nonm = 1 - is_metal
    k = k * HINTS.get("strength", 1.0)

    cav = np.clip((1 - ao) * 1.6, 0, 1) ** 1.3                    # recesses
    grime = smooth(0.45, 0.75, n1)                                  # large blotches
    wear = smooth(0.25, 0.7, edge) * smooth(0.35, 0.65, n3 * 0.7 + n2 * 0.3)   # broken-up edges
    # — albedo —
    col = rgb.copy()
    var = 1.0 + (n2 - 0.5) * 0.08 * k + (n1 - 0.5) * 0.06 * k
    col *= var[..., None]
    dirt_col = np.array([0.11, 0.095, 0.08], dtype=np.float32)
    dirt_amt = (cav * (0.45 * paint + 0.35 * white + 0.25 * wood + 0.5 * steel + 0.55 * brass + 0.25 * dark + 0.3 * other)
                + grime * 0.06 * (white + paint + other)) * k
    col = col * (1 - dirt_amt[..., None] * 0.65) + dirt_col * (dirt_amt[..., None] * 0.35)
    # Tarnish in brass recesses (brown-green), polish on brass edges.
    tarnish = np.array([0.18, 0.15, 0.07], dtype=np.float32)
    col = col * (1 - (brass * cav * 0.5 * k)[..., None]) + tarnish * (brass * cav * 0.5 * k)[..., None]
    col = col * (1 + (brass * wear * 0.35 * k)[..., None])
    gold = np.array([1.0, 0.78, 0.42], dtype=np.float32)
    col = col * (1 - (brass * 0.35)[..., None]) + (col * gold * 1.05) * (brass * 0.35)[..., None]
    # Paint chipped at worn edges: primer-dark metal shows through.
    chip = paint * smooth(0.55, 0.8, wear) * 0.8 * k
    bare = np.array([0.22, 0.21, 0.2], dtype=np.float32)
    col = col * (1 - chip[..., None]) + bare * chip[..., None]
    # Wood edges rubbed lighter, white things slightly yellowed with age.
    col = col * (1 + (wood * wear * 0.25 * k)[..., None])
    aged = np.array([1.0, 0.97, 0.9], dtype=np.float32)
    col = col * (1 - (white * 0.6 * k)[..., None] * 0.15) + (col * aged) * ((white * 0.6 * k)[..., None] * 0.15)
    col = np.clip(col, 0, 1)
    # — roughness —
    r = rough.copy()
    r += (n2 - 0.5) * 0.12 * k + (n1 - 0.5) * 0.08 * k
    r += cav * 0.15 * k
    smudge = smooth(0.55, 0.8, n1) * (steel + brass) * 0.15 * k
    r += smudge
    r -= wear * (steel + brass) * 0.12 * k
    # Lift plastic-perfect gloss on non-metals (the main "cartoon" cue).
    r = np.where(nonm > 0.5, np.maximum(r, 0.22 + 0.1 * dark), r)
    r = np.clip(r, 0.04, 1.0)
    m = np.clip(metal + chip * 0.6, 0, 1)
    # — micro relief (height) —
    detail = lum - blur(lum, 3)                                     # the texture's own fine detail
    hgt = detail * (1.5 * wood + 1.0 * other + 0.6 * paint + 0.4 * white + 0.8 * dark + 0.3 * (steel + brass))
    hgt += (n2 - 0.5) * 0.035 * (paint + white) + (n3 - 0.5) * 0.12 * (steel + brass) + (n2 - 0.5) * 0.08 * dark
    hgt -= chip * 0.6
    hgt *= k
    gy, gx = np.gradient(hgt)
    sc = 2.5 * SIZE / 2048.0
    nx, ny = -gx * sc, -gy * sc
    bn = nrm[..., :3] * 2 - 1
    out_n = np.stack([bn[..., 0] + nx, bn[..., 1] + ny, bn[..., 2]], axis=-1)
    out_n /= np.linalg.norm(out_n, axis=-1, keepdims=True) + 1e-6
    out_n = out_n * 0.5 + 0.5
    occ = np.clip(0.35 + 0.65 * ao, 0, 1)
    stats = {"metal": float(is_metal.mean()), "brass": float(brass.mean()), "wood": float(wood.mean()),
             "white": float(white.mean()), "dark": float(dark.mean()), "paint": float(paint.mean())}
    return col, r, m, out_n, occ, stats


# ————— main —————

def main():
    setup()
    meshes = import_model(SRC)
    if not meshes:
        log("no meshes in", SRC)
        return
    lo, hi = bounds(meshes)
    size = float(np.max(hi - lo))
    log("meshes", len(meshes), "size %.3f m" % size)
    mats = all_materials(meshes)
    make_bake_uv(meshes)

    # Base colour (no lighting).
    # Emission first (lamp bulbs, dials) from the materials as they are.
    img_emit = new_image("w_emit")
    bake(meshes, mats, img_emit, "EMIT")
    # Base colour straight from the Base Color input: Cycles' diffuse-colour pass is black on metals.
    img_base = new_image("w_base", alpha=True)

    def base_src(m, nt, dst):
        p = principled(m)
        if p is None:
            dst.default_value = (0.5, 0.5, 0.5, 1.0)
            return
        link_value(nt, p.inputs["Base Color"], dst, scalar=False)
    bake_emit_from(meshes, mats, img_base, base_src)
    # Roughness straight from the material input (Cycles' ROUGHNESS pass writes roughness squared).
    img_rough = new_image("w_rough", data=True)
    bake_emit_from(meshes, mats, img_rough,
                   lambda m, nt, dst: link_value(nt, principled(m).inputs["Roughness"] if principled(m) else None, dst)
                   if principled(m) else setattr(dst, "default_value", (0.5, 0.5, 0.5, 1.0)))
    img_metal = new_image("w_metal", data=True)
    bake_emit_from(meshes, mats, img_metal,
                   lambda m, nt, dst: link_value(nt, principled(m).inputs["Metallic"] if principled(m) else None, dst))
    img_nrm = new_image("w_nrm", data=True)
    bake(meshes, mats, img_nrm, "NORMAL", normal_space="TANGENT")
    img_ao = new_image("w_ao", data=True)
    bpy.context.scene.world = bpy.data.worlds.new("w") if bpy.context.scene.world is None else bpy.context.scene.world
    bpy.context.scene.world.light_settings.distance = max(size * 0.12, 0.01)

    def ao_src(m, nt, dst):
        n = nt.nodes.new("ShaderNodeAmbientOcclusion")
        n.name = "__bake_ao"
        n.samples = 24
        n.inputs["Distance"].default_value = max(size * 0.08, 0.008)
        nt.links.new(n.outputs["AO"], dst)
    bake_emit_from(meshes, mats, img_ao, ao_src)

    def edge_src(m, nt, dst):
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 8
        bev.inputs["Radius"].default_value = max(size * 0.006, 0.0015)
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        nt.links.new(bev.outputs["Normal"], dot.inputs[0])
        nt.links.new(geo.outputs["Normal"], dot.inputs[1])
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 1.0
        nt.links.new(dot.outputs["Value"], inv.inputs[1])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = 12.0
        mul.use_clamp = True
        nt.links.new(inv.outputs["Value"], mul.inputs[0])
        nt.links.new(mul.outputs["Value"], dst)
    img_edge = new_image("w_edge", data=True)
    bake_emit_from(meshes, mats, img_edge, edge_src)

    def noise_src(m, nt, dst):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        comb = nt.nodes.new("ShaderNodeCombineColor")
        for i, (scale, detail) in enumerate([(2.5 / size, 4.0), (40.0 / size, 2.0), (12.0 / size, 6.0)]):
            nz = nt.nodes.new("ShaderNodeTexNoise")
            nz.inputs["Scale"].default_value = scale
            nz.inputs["Detail"].default_value = detail
            nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
            if i == 2:
                # Scratch-like: noise stretched along one axis.
                mp = nt.nodes.new("ShaderNodeMapping")
                mp.inputs["Scale"].default_value = (1.0, 1.0, 8.0)
                nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
                nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
            nt.links.new(nz.outputs["Fac"], comb.inputs[i])
        nt.links.new(comb.outputs["Color"], dst)
    img_noise = new_image("w_noise", data=True)
    bake_emit_from(meshes, mats, img_noise, noise_src)

    base = img_array(img_base)
    col, r, m, n, occ, stats = compose(base, img_array(img_rough)[..., 0], img_array(img_metal)[..., 0],
                                       img_array(img_nrm), img_array(img_ao)[..., 0], img_array(img_edge)[..., 0],
                                       img_array(img_noise)[..., :3])
    log("classes", {k: round(v, 3) for k, v in stats.items()})

    name = os.path.splitext(os.path.basename(DST))[0]
    out_col = bpy.data.images.new(name + "_albedo", SIZE, SIZE, alpha=True)
    set_pixels(out_col, np.concatenate([col, base[..., 3:4]], axis=-1))
    out_orm = bpy.data.images.new(name + "_orm", SIZE, SIZE)
    out_orm.colorspace_settings.name = "Non-Color"
    set_pixels(out_orm, np.stack([occ, r, m, np.ones_like(r)], axis=-1))
    out_n = bpy.data.images.new(name + "_normal", SIZE, SIZE)
    out_n.colorspace_settings.name = "Non-Color"
    set_pixels(out_n, np.concatenate([n, np.ones_like(r)[..., None]], axis=-1))
    for im in (out_col, out_orm, out_n):
        im.file_format = "PNG"
        im.pack()

    # One new material for every mesh.
    has_alpha = bool((base[..., 3] < 0.98).mean() > 0.002)
    mat = bpy.data.materials.new(name + "_weathered")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = principled(mat)
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = UV

    def tex(im):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = im
        nt.links.new(uv.outputs["UV"], t.inputs["Vector"])
        return t
    tc = tex(out_col)
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    emit = img_array(img_emit)[..., :3]
    if float(emit.max()) > 0.02:
        out_e = bpy.data.images.new(name + "_emission", SIZE, SIZE)
        set_pixels(out_e, np.concatenate([emit, np.ones_like(emit[..., :1])], axis=-1))
        out_e.file_format = "PNG"
        out_e.pack()
        te = tex(out_e)
        nt.links.new(te.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    if has_alpha:
        nt.links.new(tc.outputs["Alpha"], bsdf.inputs["Alpha"])
    to = tex(out_orm)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    tn = tex(out_n)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.uv_map = UV
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    # glTF occlusion (the exporter reads a group called "glTF Material Output").
    grp = bpy.data.node_groups.get("glTF Material Output")
    if grp is None:
        grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    gn = nt.nodes.new("ShaderNodeGroup")
    gn.node_tree = grp
    nt.links.new(sep.outputs["Red"], gn.inputs["Occlusion"])

    for o in meshes:
        o.data.materials.clear()
        o.data.materials.append(mat)
        # Only the bake UV survives (glTF TEXCOORD_0).
        for uvl in list(o.data.uv_layers):
            if uvl.name != UV:
                o.data.uv_layers.remove(uvl)

    os.makedirs(os.path.dirname(os.path.abspath(DST)), exist_ok=True)
    if DST.lower().endswith(".gltf"):
        # glTF + .bin with the maps in a folder of their own (shared texture folders stay untouched).
        bpy.ops.export_scene.gltf(filepath=DST, export_format="GLTF_SEPARATE", export_image_format="AUTO",
                                  export_texture_dir="textures_weathered", export_materials="EXPORT",
                                  export_texcoords=True, export_normals=True, export_tangents=True, export_yup=True)
    else:
        bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_image_format="AUTO",
                                  export_materials="EXPORT", export_texcoords=True, export_normals=True,
                                  export_tangents=True, export_yup=True)
    # Blender's exporter leaves emissiveFactor out when the colour comes from a texture.
    if DST.lower().endswith(".gltf"):
        import json
        g = json.load(open(DST, encoding="utf-8"))
        for m in g.get("materials", []):
            if "emissiveTexture" in m:
                m["emissiveFactor"] = [1.0, 1.0, 1.0]
                m.setdefault("extensions", {})["KHR_materials_emissive_strength"] = {"emissiveStrength": 4.0}
                if "KHR_materials_emissive_strength" not in g.setdefault("extensionsUsed", []):
                    g["extensionsUsed"].append("KHR_materials_emissive_strength")
        json.dump(g, open(DST, "w", encoding="utf-8"))
    if HINTS.get("save_maps"):
        d = os.path.join(os.path.dirname(os.path.abspath(DST)), name + "_maps")
        os.makedirs(d, exist_ok=True)
        for im in (out_col, out_orm, out_n):
            im.filepath_raw = os.path.join(d, im.name + ".png")
            im.save()
    log("wrote", DST)


main()
