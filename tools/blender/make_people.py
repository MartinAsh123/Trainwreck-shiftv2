# make_people.py — the townspeople: 30 men and women of the 1930s in winter clothes (Blender 5.x).
#   blender --background --factory-startup --python tools/blender/make_people.py -- <out_dir> [first] [count] [previews]
# Writes <out_dir>/townfolk_NN.glb (NN = 00..29); with "previews", a full-length render of each to
# <out_dir>/../../../docs/people/ for review.
# Built with MPFB (MakeHuman for Blender) from CC0 assets only: the MakeHuman base mesh, skins, eyes,
# hair and the asset packs system / suits01 / shirts01 / hats01 / pants01 / shoes01; flat caps,
# scarves and gloves are modelled here. Every figure carries the MPFB "game_engine" skeleton
# (Unreal-style bone names) and two animations made here: "Idle" (4 s, breathing, a little sway)
# and "Walk" (1 s cycle, about 1.3 m/s; the game moves the figure, the animation walks in place).
# Faces -Y in Blender = +Z in Godot.
import json
import math
import os
import struct
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = argv[0]
FIRST = int(argv[1]) if len(argv) > 1 else 0
COUNT = int(argv[2]) if len(argv) > 2 else 30
PREVIEWS = len(argv) > 3 and argv[3] == "previews"

# ————— the people —————
# hair colours (linear RGB of the lit strands)
BLACK, DKBROWN, BROWN, AUBURN, BLOND, GREY, WHITE = (0.035, 0.03, 0.027), (0.07, 0.045, 0.03), (0.13, 0.08, 0.045), \
    (0.2, 0.07, 0.035), (0.42, 0.3, 0.15), (0.3, 0.29, 0.28), (0.6, 0.59, 0.57)
# wool and felt colours
MAROON, NAVY, BOTTLE, MUSTARD, CREAM, CHARCOAL, BROWNW, GREYW, BURGUNDY, OLIVE, RUST, PLUM = \
    (0.22, 0.04, 0.035), (0.03, 0.045, 0.1), (0.03, 0.09, 0.05), (0.4, 0.27, 0.05), (0.62, 0.57, 0.46), \
    (0.05, 0.05, 0.05), (0.16, 0.09, 0.05), (0.2, 0.2, 0.2), (0.25, 0.03, 0.06), (0.14, 0.15, 0.06), \
    (0.35, 0.1, 0.04), (0.17, 0.05, 0.13)
LEATHER_BROWN, LEATHER_BLACK, LEATHER_TAN = (0.055, 0.035, 0.025), (0.018, 0.016, 0.015), (0.14, 0.08, 0.04)


def man(age, height, weight, muscle, hair, hair_col, outfit, shoes, hat, scarf, gloves, brows=1, tint=None, skin=None):
    return dict(sex="m", age=age, height=height, weight=weight, muscle=muscle, hair=hair, hair_col=hair_col, outfit=outfit,
                shoes=shoes, hat=hat, scarf=scarf, gloves=gloves, brows=brows, tint=tint, skin=skin)


def woman(age, height, weight, muscle, hair, hair_col, outfit, shoes, hat, scarf, gloves, brows=6, tint=None, skin=None):
    return dict(sex="f", age=age, height=height, weight=weight, muscle=muscle, hair=hair, hair_col=hair_col, outfit=outfit,
                shoes=shoes, hat=hat, scarf=scarf, gloves=gloves, brows=brows, tint=tint, skin=skin)


# outfit: list of (clothes asset, recolour) — recolour None, ("all", rgb), ("hue", rgb, h0, h1) or "denim"
JACKET = [("male_casualsuit05", "denim")]
DB_SUIT = [("toigo_male_double-breasted_suit", None)]
SUIT3 = [("toigo_male_suit_3", None)]
SUIT_TIE = [("toigo_male_suit_tie_and_jacket", None)]
ELEGANT_M = [("male_elegantsuit01", None)]


def sweater(rgb):
    return [("toigo_fisherman_sweater", ("all", rgb)), ("toigo_wool_pants", None)]


F_SUIT = [("toigo_female_suit", None)]
F_DB = [("toigo_female_double-breasted_suit", None)]
F_ELEGANT = [("female_elegantsuit01", None)]


def f_suit2(rgb):
    return [("toigo_female_suit_2", ("hue", rgb, 0.75, 0.98))]


def cloche(rgb):
    return ("aethelraed_unraed_cloche_hat", ("all", rgb))


def newsboy(rgb):
    return ("jujube_newsboy_cap", ("all", rgb))


FEDORA = ("fedora01", None)


def boots_f(rgb):
    return ("toigo_ankle_boots_female", ("all", rgb))


PEOPLE = [
    man(35, 1.70, 0.52, 0.55, "short01", BLACK, JACKET, ("shoes03", None), ("flatcap", CHARCOAL), MAROON, LEATHER_BROWN),
    man(56, 1.74, 0.62, 0.45, "short02", GREY, DB_SUIT, ("toigo_ankle_boots_male", None), FEDORA, GREYW, LEATHER_BLACK, brows=3),
    man(68, 1.66, 0.48, 0.35, "short03", WHITE, ELEGANT_M, ("shoes01", None), newsboy(BROWNW), BOTTLE, None, brows=8),
    man(23, 1.79, 0.42, 0.6, "short04", BLOND, sweater(CREAM), ("culturalibre_male_boots", None), newsboy(GREYW), None, None, brows=2),
    man(42, 1.76, 0.55, 0.5, "short01", DKBROWN, SUIT_TIE, ("shoes03", None), FEDORA, NAVY, LEATHER_BROWN, brows=4),
    man(31, 1.82, 0.6, 0.65, "short02", BROWN, JACKET, ("culturalibre_male_boots", None), ("flatcap", BROWNW), MUSTARD, None, brows=5),
    man(48, 1.68, 0.7, 0.45, "short03", DKBROWN, sweater(NAVY), ("shoes03", None), ("flatcap", GREYW), None, LEATHER_BROWN, brows=1),
    man(27, 1.73, 0.45, 0.55, "short04", BLACK, SUIT3, ("toigo_ankle_boots_male", None), FEDORA, CREAM, LEATHER_TAN, brows=2),
    man(62, 1.71, 0.58, 0.4, "short02", GREY, sweater(BROWNW), ("culturalibre_male_boots", None), ("flatcap", CHARCOAL), RUST, None, brows=9),
    man(38, 1.77, 0.5, 0.6, "short01", AUBURN, DB_SUIT, ("shoes01", None), newsboy(CHARCOAL), BOTTLE, LEATHER_BLACK, brows=3),
    man(19, 1.75, 0.4, 0.5, "short04", BROWN, sweater(GREYW), ("shoes03", None), ("flatcap", BROWNW), MAROON, None, brows=2),
    man(51, 1.80, 0.66, 0.5, "short01", GREY, ELEGANT_M, ("toigo_ankle_boots_male", None), FEDORA, CHARCOAL, LEATHER_BLACK, brows=4),
    man(44, 1.69, 0.6, 0.62, "short03", BLACK, JACKET, ("shoes01", None), newsboy(BROWNW), NAVY, LEATHER_BROWN, brows=5),
    man(73, 1.64, 0.52, 0.3, "short02", WHITE, SUIT_TIE, ("shoes01", None), FEDORA, GREYW, LEATHER_BROWN, brows=8),
    man(29, 1.78, 0.48, 0.58, "short02", DKBROWN, SUIT3, ("culturalibre_male_boots", None), ("flatcap", GREYW), MUSTARD, None, brows=1),
    man(36, 1.72, 0.55, 0.52, "short04", BLOND, sweater(OLIVE), ("shoes03", None), newsboy(CHARCOAL), CREAM, LEATHER_TAN, brows=2),
    woman(30, 1.64, 0.45, 0.4, "bob01", BLACK, F_SUIT, boots_f(LEATHER_BLACK), cloche(BURGUNDY), CREAM, LEATHER_BLACK),
    woman(24, 1.66, 0.4, 0.4, "bob02", AUBURN, f_suit2(NAVY), boots_f(LEATHER_BROWN), cloche(NAVY), MUSTARD, LEATHER_BROWN, brows=7),
    woman(45, 1.60, 0.58, 0.35, "braid01", BROWN, F_DB, boots_f(LEATHER_BLACK), cloche(BROWNW), BOTTLE, None, brows=10),
    woman(66, 1.56, 0.55, 0.3, "bob01", WHITE, F_SUIT, boots_f(LEATHER_BLACK), cloche(CHARCOAL), PLUM, LEATHER_BLACK, brows=11),
    woman(35, 1.68, 0.48, 0.42, "ponytail01", BLOND, f_suit2(BOTTLE), boots_f(LEATHER_BROWN), cloche(BOTTLE), CREAM, LEATHER_TAN, brows=6),
    woman(21, 1.62, 0.38, 0.4, "bob02", DKBROWN, F_ELEGANT, boots_f(LEATHER_BLACK), cloche(PLUM), MAROON, None, brows=7),
    woman(52, 1.63, 0.62, 0.35, "braid01", GREY, sweater(BROWNW), boots_f(LEATHER_BROWN), None, RUST, None, brows=12),
    woman(28, 1.70, 0.44, 0.45, "bob01", BROWN, f_suit2(BURGUNDY), boots_f(LEATHER_BLACK), cloche(GREYW), GREYW, LEATHER_BLACK, brows=6),
    woman(40, 1.61, 0.52, 0.4, "ponytail01", BLACK, F_DB, boots_f(LEATHER_BROWN), cloche(RUST), NAVY, LEATHER_BROWN, brows=10),
    woman(58, 1.59, 0.6, 0.3, "bob02", GREY, F_ELEGANT, boots_f(LEATHER_BLACK), cloche(NAVY), BURGUNDY, LEATHER_BLACK, brows=11),
    woman(19, 1.65, 0.36, 0.45, "braid01", BLOND, sweater(CREAM), boots_f(LEATHER_BROWN), None, MAROON, None, brows=7),
    woman(33, 1.67, 0.46, 0.4, "bob02", BLACK, f_suit2(PLUM), boots_f(LEATHER_BLACK), cloche(CHARCOAL), CREAM, LEATHER_BLACK, brows=6),
    woman(47, 1.62, 0.55, 0.38, "bob01", AUBURN, F_SUIT, boots_f(LEATHER_BROWN), cloche(OLIVE), MUSTARD, LEATHER_TAN, brows=10),
    woman(71, 1.55, 0.5, 0.28, "braid01", WHITE, sweater(GREYW), boots_f(LEATHER_BLACK), None, BOTTLE, None, brows=12),
]

# ————— helpers —————
MPFB = "bl_ext.user_default.mpfb"


def world_bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def find(pattern):
    for o in bpy.data.objects:
        if o.type == "MESH" and pattern.lower() in o.name.lower():
            return o
    return None


def images_of(obj):
    out = []
    for slot in obj.material_slots:
        if slot.material and slot.material.use_nodes:
            for n in slot.material.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and not any(k in n.image.name.lower() for k in ("norm", "bump", "spec")):
                    out.append(n.image)
    return out


def edit_pixels(img, fn, name):
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    px = fn(px)
    new = bpy.data.images.new(name, w, h, alpha=True)
    new.pixels = px.ravel()
    new.file_format = "PNG"
    for m in bpy.data.materials:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image == img:
                    n.image = new
    return new


def lum_of(px):
    return 0.3 * px[..., 0] + 0.59 * px[..., 1] + 0.11 * px[..., 2]


def recolour_all(img, rgb, name):
    def fn(px):
        lum = lum_of(px)
        m = max(float(np.percentile(lum[px[..., 3] > 0.1] if (px[..., 3] > 0.1).any() else lum, 60)), 1e-3)
        k = np.clip(lum / m, 0.0, 1.8)
        for c in range(3):
            px[..., c] = np.clip(k * rgb[c], 0, 1)
        return px
    return edit_pixels(img, fn, name)


def recolour_hue(img, rgb, h0, h1, name):
    def fn(px):
        r, g, b = px[..., 0], px[..., 1], px[..., 2]
        mx = np.maximum(np.maximum(r, g), b)
        mn = np.minimum(np.minimum(r, g), b)
        d = np.maximum(mx - mn, 1e-5)
        sat = d / np.maximum(mx, 1e-5)
        hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
        sel = (sat > 0.25) & (hue >= h0) & (hue <= h1)
        lum = lum_of(px)
        m = max(float(np.median(lum[sel])) if sel.any() else 0.5, 1e-3)
        k = np.clip(lum / m, 0, 1.8)
        for c in range(3):
            px[..., c] = np.where(sel, np.clip(k * rgb[c], 0, 1), px[..., c])
        return px
    return edit_pixels(img, fn, name)


def uv_mask(obj, keep_face, w, h):
    mask = np.zeros((h, w), dtype=bool)
    uv = obj.data.uv_layers.active.data
    mw = obj.matrix_world
    for p in obj.data.polygons:
        if not keep_face(mw @ p.center):
            continue
        pts = [uv[li].uv for li in p.loop_indices]
        for k in range(1, len(pts) - 1):
            tri = [pts[0], pts[k], pts[k + 1]]
            xs = [q.x * w for q in tri]
            ys = [q.y * h for q in tri]
            x0, x1 = max(int(min(xs)) - 1, 0), min(int(max(xs)) + 2, w)
            y0, y1 = max(int(min(ys)) - 1, 0), min(int(max(ys)) + 2, h)
            if x1 <= x0 or y1 <= y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = [(xs[i], ys[i]) for i in range(3)]
            dd = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(dd) < 1e-9:
                continue
            l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / dd
            l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / dd
            mask[y0:y1, x0:x1] |= (l1 >= -0.02) & (l2 >= -0.02) & (1 - l1 - l2 >= -0.02)
    return mask


def denim_to_wool(obj, img, waist, name):
    w_, h_ = img.size
    legs = uv_mask(obj, lambda c: c.z < waist, w_, h_)

    def fn(px):
        r, g, b = px[..., 0], px[..., 1], px[..., 2]
        lum = lum_of(px)
        denim = legs & (b > r + 0.012) & (b >= g - 0.01)
        if not denim.any():
            return px
        base = np.clip(0.055 + (lum - lum[denim].mean()) * 0.18 + 0.02, 0.03, 0.12)
        noise = (np.random.default_rng(3).random(lum.shape) - 0.5) * 0.012
        for c, t in enumerate((1.05, 1.0, 0.94)):
            px[..., c] = np.where(denim, np.clip(base * t + noise, 0, 1), px[..., c])
        return px
    return edit_pixels(img, fn, name)


DATA = os.path.join(os.environ.get("APPDATA", ""), "Blender Foundation", "Blender", "5.2", "extensions", ".user",
                    "user_default", "mpfb", "data", "clothes")


def ensure_material(o, asset):
    """Some packs' .mhclo name no material (MPFB then loads none): build one from the folder's diffuse
    texture (and normal map)."""
    d = os.path.join(DATA, asset)
    if not os.path.isdir(d):
        return
    pngs = [f for f in os.listdir(d) if f.lower().endswith((".png", ".jpg"))]
    diff = [f for f in pngs if not any(k in f.lower() for k in ("norm", "bump", "spec"))]
    if not diff:
        return
    m = bpy.data.materials.new(asset)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.85
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = bpy.data.images.load(os.path.join(d, diff[0]))
    nt.links.new(tn.outputs["Color"], b.inputs["Base Color"])
    nrm = [f for f in pngs if "norm" in f.lower()]
    if nrm:
        tn2 = nt.nodes.new("ShaderNodeTexImage")
        tn2.image = bpy.data.images.load(os.path.join(d, nrm[0]))
        tn2.image.colorspace_settings.name = "Non-Color"
        nm_ = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn2.outputs["Color"], nm_.inputs["Color"])
        nt.links.new(nm_.outputs["Normal"], b.inputs["Normal"])
    o.data.materials.clear()
    o.data.materials.append(m)


def make_mat(name, color, rough, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if sheen:
        b.inputs["Sheen Weight"].default_value = sheen
    return m


def knit_mat(name, rgb, seed):
    m = make_mat(name, (1, 1, 1), 0.95, sheen=0.5)
    kw = 128
    ky, kx = np.mgrid[0:kw, 0:kw] / kw
    rib = 0.5 + 0.5 * np.cos(kx * 2 * np.pi * 8)
    st = 0.5 + 0.5 * np.cos((ky * 16 + np.abs(((kx * 8) % 1.0) - 0.5)) * 2 * np.pi)
    v = 0.6 + 0.28 * rib * (0.7 + 0.3 * st) + (np.random.default_rng(seed).random(kx.shape) - 0.5) * 0.08
    px = np.stack([rgb[0] * v / 0.75, rgb[1] * v / 0.75, rgb[2] * v / 0.75, np.ones_like(v)], axis=-1).astype(np.float32)
    img = bpy.data.images.new(name + "_knit", kw, kw)
    img.pixels = np.clip(px, 0, 1).ravel()
    img.pack()
    tn = m.node_tree.nodes.new("ShaderNodeTexImage")
    tn.image = img
    m.node_tree.links.new(tn.outputs["Color"], m.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    return m


def weight_of(obj, v_index, names):
    tot = 0.0
    for g in obj.data.vertices[v_index].groups:
        gn = obj.vertex_groups[g.group].name.lower()
        if any(n in gn for n in names):
            tot += g.weight
    return tot


def shell(src, name, keep, offset, mat, thickness):
    o = src.copy()
    o.data = src.data.copy()
    o.name = name
    for m in list(o.modifiers):
        if m.type != "ARMATURE":
            o.modifiers.remove(m)
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    mw = o.matrix_world
    dead = [f for f in bm.faces if not all(keep(mw @ v.co, v.index) for v in f.verts)]
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    sc = max(mw.to_scale().x, 1e-6)
    for v in bm.verts:
        v.co += v.normal * (offset / sc)
    bm.to_mesh(o.data)
    bm.free()
    o.data.materials.clear()
    o.data.materials.append(mat)
    s = o.modifiers.new("Solidify", "SOLIDIFY")
    s.thickness = thickness / sc
    s.offset = 1.0
    o.modifiers.move(len(o.modifiers) - 1, 0)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


# ————— one person —————
def build(i, spec, out_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module=MPFB)
    from bl_ext.user_default.mpfb.services.humanservice import HumanService
    female = spec["sex"] == "f"
    age = spec["age"]
    age_v = 0.5 + (age - 25.0) / 65.0 * 0.5 if age >= 25 else 0.1875 + (age - 11.0) / 14.0 * 0.3125
    stage = "young" if age < 33 else ("middleage" if age < 60 else "old")
    skin = spec["skin"] or "%s_caucasian_%s" % (stage, "female" if female else "male")
    info = HumanService._create_default_human_info_dict()
    info["name"] = "Townfolk%02d" % i
    info["phenotype"].update({"gender": 0.0 if female else 1.0, "age": age_v, "muscle": spec["muscle"],
                              "weight": spec["weight"], "proportions": 0.6, "height": 0.5, "cupsize": 0.5, "firmness": 0.5,
                              "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}})
    info["rig"] = "game_engine"
    info["eyes"] = "low-poly.mhclo"
    info["eyebrows"] = "eyebrow%03d.mhclo" % spec["brows"]
    info["eyelashes"] = "eyelashes01.mhclo"
    info["hair"] = spec["hair"] + ".mhclo"
    clothes = [c[0] + ".mhclo" for c in spec["outfit"]] + [spec["shoes"][0] + ".mhclo"]
    hat = spec["hat"]
    if hat and hat[0] != "flatcap":
        clothes.append(hat[0] + ".mhclo")
    info["clothes"] = clothes
    info["skin_mhmat"] = skin + ".mhmat"
    info["skin_material_type"] = "MAKESKIN"
    info["eyes_material_type"] = "MAKESKIN"
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    body = HumanService.deserialize_from_dict(info, settings)
    rig = body.parent
    bpy.context.view_layer.update()
    for o in [c for c in bpy.data.objects if c.type == "MESH" and c.data.shape_keys]:
        mix = o.shape_key_add(name="mix", from_mix=True)
        coords = [p.co.copy() for p in mix.data]
        o.shape_key_clear()
        for v, co in zip(o.data.vertices, coords):
            v.co = co
    bpy.context.view_layer.objects.active = body
    for m in list(body.modifiers):
        if m.type == "MASK":
            bpy.ops.object.modifier_apply(modifier=m.name)

    # Height: MPFB stands the bare feet on z = 0.
    lo, hi = world_bbox([body])
    k = spec["height"] / hi.z
    rig.scale = (rig.scale.x * k, rig.scale.y * k, rig.scale.z * k)
    bpy.context.view_layer.update()
    lo, hi = world_bbox([body])
    H = hi.z

    # Colours.
    hair = find(spec["hair"])
    if hair:
        for img in images_of(hair):
            recolour_all(img, spec["hair_col"], "hair_%02d" % i)
    for part in ("eyebrow", "eyelashes"):
        o = find(part)
        if o:
            for img in images_of(o):
                c = spec["hair_col"] if part == "eyebrow" and spec["hair_col"] in (GREY, WHITE) else (0.035, 0.028, 0.022)
                c = tuple(min(x, 0.2) for x in c)

                def flat(px, c=c):
                    px[..., 0], px[..., 1], px[..., 2] = c
                    return px
                edit_pixels(img, flat, "%s_%02d" % (part, i))
    for asset, rec in spec["outfit"] + [spec["shoes"]] + ([hat] if hat and hat[0] != "flatcap" else []):
        o = find(asset)
        if o and not images_of(o):
            ensure_material(o, asset)
        if not o or not rec:
            continue
        for img in images_of(o)[:1]:
            if rec == "denim":
                denim_to_wool(o, img, H * 0.565, "%s_%02d" % (asset, i))
            elif rec[0] == "all":
                recolour_all(img, rec[1], "%s_%02d" % (asset, i))
            elif rec[0] == "hue":
                recolour_hue(img, rec[1], rec[2], rec[3], "%s_%02d" % (asset, i))

    def bone_name(*cands):
        names = {b.name.lower(): b.name for b in rig.data.bones}
        for c in cands:
            if c in names:
                return names[c]
        return rig.data.bones[0].name

    def skinned(name, bm, mat, groups):
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        o.data.materials.append(mat)
        for p in me.polygons:
            p.use_smooth = True
        for g, wgt in groups.items():
            vg = o.vertex_groups.new(name=g)
            vg.add(list(range(len(me.vertices))), wgt, "REPLACE")
        o.parent = rig
        o.matrix_parent_inverse = rig.matrix_world.inverted()
        am = o.modifiers.new("Armature", "ARMATURE")
        am.object = rig
        return o

    # Gloves.
    if spec["gloves"]:
        HAND = ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_")
        shell(body, "Gloves", lambda co, vi: weight_of(body, vi, HAND) > 0.35, 0.0035,
              make_mat("gloves_%02d" % i, spec["gloves"], 0.5), 0.002)

    # Scarf round the neck, two short ends in front.
    if spec["scarf"]:
        neck_pts = [body.matrix_world @ v.co for v in body.data.vertices if weight_of(body, v.index, ("neck",)) > 0.5]
        nz0 = min(p.z for p in neck_pts)
        nz1 = max(p.z for p in neck_pts)
        neck_z = nz0 + (nz1 - nz0) * 0.3
        ring_pts = [p for p in neck_pts if abs(p.z - neck_z) < 0.015]
        nc = Vector(((min(p.x for p in ring_pts) + max(p.x for p in ring_pts)) / 2, (min(p.y for p in ring_pts) + max(p.y for p in ring_pts)) / 2))
        nr = Vector(((max(p.x for p in ring_pts) - min(p.x for p in ring_pts)) / 2, (max(p.y for p in ring_pts) - min(p.y for p in ring_pts)) / 2))
        bm = bmesh.new()
        rings = []
        n_a, n_t = 32, 8
        for ia in range(n_a):
            a = 2 * math.pi * ia / n_a
            lump = 1.0 + 0.06 * math.sin(a * 5.0 + i) + 0.03 * math.sin(a * 11.0 + 1.0)
            cx = nc.x + math.sin(a) * (nr.x + 0.028)
            cy = nc.y - math.cos(a) * (nr.y + 0.028)
            out = Vector((math.sin(a), -math.cos(a), 0.0))
            ring = []
            for j in range(n_t):
                b_ = 2 * math.pi * j / n_t
                rr = 0.026 * lump
                ring.append(bm.verts.new(Vector((cx, cy, neck_z - 0.015 + 0.02 * math.sin(a * 2.0 + 0.6))) + out * math.cos(b_) * rr * 1.1
                                         + Vector((0, 0, 1)) * math.sin(b_) * rr * 1.25))
            rings.append(ring)
        for ia in range(n_a):
            for j in range(n_t):
                bm.faces.new((rings[ia][j], rings[(ia + 1) % n_a][j], rings[(ia + 1) % n_a][(j + 1) % n_t], rings[ia][(j + 1) % n_t]))
        for side in (-1.0, 1.0):
            prev = None
            for kk in range(6):
                tt = kk / 5
                cz = neck_z - 0.035 - tt * 0.09
                cy = nc.y - nr.y - 0.04 - 0.012 * tt
                cx = nc.x + side * (0.018 + 0.03 * tt)
                ring = []
                for j in range(8):
                    b_ = 2 * math.pi * j / 8
                    rr = 0.02 * (1.0 - 0.2 * tt)
                    ring.append(bm.verts.new((cx + math.cos(b_) * rr * 1.5, cy + math.sin(b_) * rr * 0.45, cz)))
                if prev:
                    for j in range(8):
                        bm.faces.new((prev[j], prev[(j + 1) % 8], ring[(j + 1) % 8], ring[j]))
                prev = ring
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        scarf = skinned("Scarf", bm, knit_mat("scarf_%02d" % i, spec["scarf"], i), {bone_name("neck_01", "neck"): 0.6,
                                                                                      bone_name("spine_03", "spine_02"): 0.4})
        bpy.context.view_layer.objects.active = scarf
        scarf.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        for luv in scarf.data.uv_layers.active.data:
            luv.uv *= 6.0
        scarf.select_set(False)
        s = scarf.modifiers.new("Solidify", "SOLIDIFY")
        s.thickness = 0.008
        scarf.modifiers.move(1, 0)

    head_pts = [body.matrix_world @ v.co for v in body.data.vertices if weight_of(body, v.index, ("head",)) > 0.9]
    top = max(p.z for p in head_pts)
    cut_z = None
    # Flat cap (modelled).
    if hat and hat[0] == "flatcap":
        sel = [p for p in body.data.vertices if top - 0.075 < (body.matrix_world @ p.co).z < top - 0.055]
        pts = [body.matrix_world @ v.co for v in sel]
        hc = Vector(((min(p.x for p in pts) + max(p.x for p in pts)) / 2, (min(p.y for p in pts) + max(p.y for p in pts)) / 2))
        hr = Vector(((max(p.x for p in pts) - min(p.x for p in pts)) / 2, (max(p.y for p in pts) - min(p.y for p in pts)) / 2))
        band_z = top - 0.072
        bm = bmesh.new()
        n_a, n_v = 32, 8
        grid = []
        for j in range(n_v + 1):
            v_ = j / n_v
            row = []
            for ia in range(n_a):
                a = 2 * math.pi * ia / n_a
                fwd = -math.cos(a)
                swell = 1.0 + 0.2 * math.sin(v_ * math.pi * 0.8) + 0.12 * max(fwd, 0) * v_
                shrink = math.cos(v_ * math.pi * 0.5) ** 0.35
                x = hc.x + math.sin(a) * (hr.x + 0.012) * swell * shrink
                y = hc.y - math.cos(a) * (hr.y + 0.014) * swell * shrink - 0.03 * v_
                z = band_z + (top - band_z + 0.012) * math.sin(v_ * math.pi * 0.5) ** 0.7 - 0.035 * max(fwd, 0) * v_ ** 0.5
                row.append(bm.verts.new((x, y, z)))
            grid.append(row)
        for j in range(n_v):
            for ia in range(n_a):
                bm.faces.new((grid[j][ia], grid[j][(ia + 1) % n_a], grid[j + 1][(ia + 1) % n_a], grid[j + 1][ia]))
        bm.faces.new(list(reversed(grid[n_v])))
        pk = []
        for j in range(4):
            t_ = j / 3
            row = []
            for ia in range(11):
                a = math.radians(-58 + 116 * ia / 10)
                row.append(bm.verts.new((hc.x + math.sin(a) * (hr.x + 0.012 + 0.012 * t_),
                                         hc.y - math.cos(a) * (hr.y + 0.012) - 0.042 * t_ * math.cos(a) ** 0.5,
                                         band_z + 0.004 - 0.018 * t_ * t_)))
            pk.append(row)
        for j in range(3):
            for ia in range(10):
                bm.faces.new((pk[j][ia], pk[j][ia + 1], pk[j + 1][ia + 1], pk[j + 1][ia]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        cap = skinned("Cap", bm, make_mat("cap_%02d" % i, hat[1], 0.92, sheen=0.35), {bone_name("head"): 1.0})
        s = cap.modifiers.new("Solidify", "SOLIDIFY")
        s.thickness = 0.006
        cap.modifiers.move(1, 0)
        cut_z = band_z + 0.004
    elif hat:
        ho = find(hat[0])
        if ho:
            hlo, hhi = world_bbox([ho])
            cut_z = hlo.z + 0.035
    # Hair under a hat: trim what the hat covers.
    if hair and cut_z is not None:
        bm = bmesh.new()
        bm.from_mesh(hair.data)
        mw = hair.matrix_world
        face_y = min(p.y for p in head_pts) + 0.06        # the face's front (MakeHuman faces -Y)
        hat_low = cut_z - 0.035
        def covered(co):
            # Under the hat; and with a deep hat (cloche) any lock hanging in front of the face.
            return co.z > cut_z or (hat[0] != "flatcap" and co.y < face_y and co.z > hat_low - 0.12)
        dead = [f for f in bm.faces if all(covered(mw @ v.co) for v in f.verts)]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        bm.to_mesh(hair.data)
        bm.free()

    # Textures: 1024 at most (the skin 2048), to keep 30 people light.
    for img in list(bpy.data.images):
        if img.size[0] == 0:
            continue
        lim = 2048 if "skin" in img.name.lower() or "lightskinned" in img.name.lower() else 1024
        if max(img.size) > lim:
            f = lim / max(img.size)
            img.scale(int(img.size[0] * f), int(img.size[1] * f))

    animate(rig, i)
    if PREVIEWS:
        preview(i, out_path)
    export(out_path)
    lo, hi = world_bbox([o for o in bpy.data.objects if o.type == "MESH"])
    print("[people] %02d wrote %s  %.2f m  tris %d" % (i, os.path.basename(out_path), hi.z - lo.z,
          sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")))


# ————— animation —————
def animate(rig, seed):
    """Two actions on the rig: Idle (4 s) and Walk (1 s), keyed on pose-bone quaternions."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    pb = rig.pose.bones
    for b in pb:
        b.rotation_mode = "QUATERNION"
    names = {b.name.lower(): b.name for b in rig.data.bones}

    def nm(n):
        return names.get(n)

    rest = {b.name: b.matrix_local.to_3x3() for b in rig.data.bones}       # armature space
    order = [b.name for b in rig.data.bones]                                # parents first

    def apply(deltas):
        """deltas: bone -> world (armature-space) rotation Matrix applied at that bone, on top of the
        parents' rotations. Sets every pose bone's local rotation accordingly."""
        acc = {}
        for bn in order:
            bone = rig.data.bones[bn]
            P = acc[bone.parent.name] if bone.parent else Matrix.Identity(3)
            R = deltas.get(bn, Matrix.Identity(3))
            M = rest[bn]
            L = M.inverted() @ P.inverted() @ R @ P @ M
            pb[bn].rotation_quaternion = L.to_quaternion()
            acc[bn] = R @ P
        return acc

    X = Vector((1, 0, 0))
    Y = Vector((0, 1, 0))
    Z = Vector((0, 0, 1))

    def rot(axis, deg):
        return Matrix.Rotation(math.radians(deg), 3, axis)

    def arm_down(side):
        ub = nm("upperarm_" + side)
        lb = nm("lowerarm_" + side)
        if not ub or not lb:
            return Matrix.Identity(3)
        a = rig.data.bones[ub]
        d = (a.tail_local - a.head_local).normalized()
        want = Vector((0.16 * math.copysign(1, d.x), -0.04, -1.0)).normalized()
        return d.rotation_difference(want).to_matrix()

    down = {"l": arm_down("l"), "r": arm_down("r")}
    pelvis = nm("pelvis")
    rng = np.random.default_rng(seed)
    lean = rng.uniform(-2.0, 3.0)

    def key(frame, deltas, pelvis_dz=0.0):
        apply(deltas)
        for b in pb:
            b.keyframe_insert("rotation_quaternion", frame=frame)
        if pelvis:
            pb[pelvis].location = rig.data.bones[pelvis].matrix_local.to_3x3().inverted() @ Vector((0, 0, pelvis_dz / rig.scale.z))
            pb[pelvis].keyframe_insert("location", frame=frame)

    def base():
        d = {}
        for s in ("l", "r"):
            if nm("upperarm_" + s):
                d[nm("upperarm_" + s)] = down[s]
            if nm("lowerarm_" + s):
                d[nm("lowerarm_" + s)] = rot(X, -7)
        if nm("spine_01"):
            d[nm("spine_01")] = rot(X, -lean)
        return d

    rig.animation_data_create()
    # Idle: 4 s at 24 fps — breathing (chest), a slow weight shift, the head looking about.
    idle = bpy.data.actions.new("Idle")
    idle.use_fake_user = True
    rig.animation_data.action = idle
    for f in range(0, 97, 8):
        t = f / 96.0 * 2 * math.pi
        d = base()
        if nm("spine_02"):
            d[nm("spine_02")] = rot(X, -1.2 * math.sin(t * 4))
        if nm("pelvis"):
            d[nm("pelvis")] = rot(Y, 1.5 * math.sin(t))
        if nm("head"):
            d[nm("head")] = rot(Z, 8 * math.sin(t + seed)) @ rot(X, 2 * math.sin(t * 2))
        key(f + 1, d, 0.004 * math.sin(t * 4))
    # Walk: 1 s cycle (24 frames) — thighs swing ±24°, knees flex in the swing, arms counter-swing,
    # the pelvis bobs and twists. Negative rotation about X moves a limb forward (-Y).
    walk = bpy.data.actions.new("Walk")
    walk.use_fake_user = True
    rig.animation_data.action = walk
    for f in range(0, 25, 2):
        ph = f / 24.0 * 2 * math.pi
        d = base()
        for s, off in (("l", 0.0), ("r", math.pi)):
            p = ph + off
            th = nm("thigh_" + s)
            ca = nm("calf_" + s)
            fo = nm("foot_" + s)
            if th:
                d[th] = rot(X, -24 * math.sin(p))
            if ca:
                d[ca] = rot(X, 6 + 38 * max(0.0, math.sin(p + 1.25)) ** 1.4)
            if fo:
                d[fo] = rot(X, -10 * math.sin(p + 0.6))
            ua = nm("upperarm_" + s)
            if ua:
                d[ua] = rot(X, 16 * math.sin(p)) @ down[s]
            la = nm("lowerarm_" + s)
            if la:
                d[la] = rot(X, -14 - 8 * max(0.0, -math.sin(p)))
        if nm("pelvis"):
            d[nm("pelvis")] = rot(Z, 4 * math.sin(ph))
        if nm("spine_02"):
            d[nm("spine_02")] = rot(Z, -5 * math.sin(ph))
        key(f + 1, d, 0.018 * (math.cos(2 * ph) * 0.5 - 0.5))
    rig.animation_data.action = idle
    bpy.ops.object.mode_set(mode="OBJECT")


# ————— preview and export —————
def preview(i, out_path):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    sc.render.resolution_x = 360
    sc.render.resolution_y = 640
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.32, 0.34, 0.37, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = world
    for (r_, en) in (((math.radians(55), 0, math.radians(-35)), 3.5), ((math.radians(60), 0, math.radians(150)), 1.5)):
        ld = bpy.data.lights.new("sun", "SUN")
        ld.energy = en
        lo_ = bpy.data.objects.new("sun", ld)
        lo_.rotation_euler = r_
        sc.collection.objects.link(lo_)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    pos, look = Vector((0.9, -3.6, 1.0)), Vector((0, 0, 0.88))
    cam.location = pos
    cam.rotation_euler = (look - pos).to_track_quat("-Z", "Y").to_euler()
    sc.frame_set(1)
    d = os.path.join(os.path.dirname(out_path), "previews")
    os.makedirs(d, exist_ok=True)
    sc.render.filepath = os.path.join(d, "townfolk_%02d.png" % i)
    bpy.ops.render.render(write_still=True)
    for o in list(bpy.data.objects):
        if o.type in ("LIGHT", "CAMERA"):
            bpy.data.objects.remove(o)


def export(out_path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type in ("MESH", "ARMATURE"):
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_skins=True, export_animations=True, export_animation_mode="ACTIONS",
                              export_image_format="AUTO", export_image_quality=88)
    with open(out_path, "rb") as f:
        data = f.read()
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen])
    for m in gltf.get("materials", []):
        if any(k in m.get("name", "").lower() for k in ("eyebrow", "eyelash")):
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = 0.25
            m["doubleSided"] = True
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    rest = data[20 + jlen:]
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 20 + len(js) + len(rest)) + struct.pack("<I", len(js)) + b"JSON" + js + rest)


os.makedirs(OUT_DIR, exist_ok=True)
for i in range(FIRST, min(FIRST + COUNT, len(PEOPLE))):
    try:
        build(i, PEOPLE[i], os.path.join(OUT_DIR, "townfolk_%02d.glb" % i))
    except Exception as e:   # one failure must not stop the batch
        import traceback
        traceback.print_exc()
        print("[people] %02d FAILED: %s" % (i, e))
