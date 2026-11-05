"""Track, lineside and platform models for the HD landscape (run via build_world.py).

GODOT space (x along the line, y up, z across), real metres.
    sleeper      — weathered timber sleeper, 2.6 m, top at y = -0.02, with ribbed steel baseplates
                   and screw spikes at both rail seats (rail foot sits at y = 0)
    pole         — creosoted telegraph pole, 7.5 m, two crossarms with iron braces and glass
                   insulators on the scenery's WIRE_POINTS, tin cap
    lamp_post    — k.u.k. platform lamp: cast-iron fluted column, ladder bar, glazed lantern
    rock_a/b/c   — Poly Haven scanned rocks (CC0), decimated, 2 m across, base sunk 0.15 m
    stump        — Poly Haven tree_stump_01 (CC0), decimated
    bench        — 1930s platform bench: cast-iron scroll ends, wooden slats, 1.8 m
Materials named for the Godot shaders: sleeper_wood, pole_wood, track_steel, insulator,
cast_iron, lamp_glass; the Poly Haven models keep their own scanned textures.
"""
import bpy, bmesh, math, os
from mathutils import Vector

import hdlib as H

H.MATS.update({
    "sleeper_wood": dict(tex="wood_weathered", scale=1.1),
    "pole_wood": dict(tex="wood_weathered", scale=1.6),
    "track_steel": dict(tex="rail_rust", scale=0.4),
    "insulator": dict(color=(0.32, 0.5, 0.46), rough=0.08),
    "cast_iron": dict(color=(0.05, 0.07, 0.06), rough=0.45, metal=0.6),
    "lamp_glass": dict(color=(1.0, 0.85, 0.6), rough=0.1, emit=(1.0, 0.8, 0.5), emit_k=3.0),
    "bench_wood": dict(tex="planks", scale=1.0),
    "galv_steel": dict(color=(0.5, 0.52, 0.53), rough=0.4, metal=1.0),
    "chainlink": dict(color=(0.55, 0.56, 0.57), rough=0.4, metal=1.0),
})


def sleeper():
    H.box("timber", (0.24, 0.15, 2.6), (0, -0.095, 0), "sleeper_wood", bevel=0.014, segs=1, grain="z")
    for zs in (-1, 1):
        zc = zs * (0.7175 + 0.036)
        # Baseplate with ribbed shoulders either side of the rail foot, four screw-spike heads.
        H.box("plate", (0.17, 0.02, 0.34), (0, -0.01, zc), "track_steel", bevel=0.0)
        for side in (-1, 1):
            H.box("rib", (0.17, 0.018, 0.018), (0, 0.006, zc + side * 0.075), "track_steel", bevel=0.0)
            for xs in (-1, 1):
                H.box("head", (0.028, 0.022, 0.028), (xs * 0.05, 0.008, zc + side * 0.13), "track_steel", bevel=0.0)
    return H.finish("sleeper")


POLE_H = 7.2
WIRE_POINTS = [(0, 6.95, -0.62), (0, 6.95, -0.22), (0, 6.95, 0.22), (0, 6.95, 0.62), (0, 6.35, -0.45), (0, 6.35, 0.45)]


def pole():
    H.lathe("pole", [(0.125, -0.3), (0.12, 1.0), (0.1, 5.0), (0.088, POLE_H)], (0, 0, 0), "pole_wood", segs=14, cap_bottom=False)
    H.lathe("cap", [(0.1, POLE_H - 0.02), (0.098, POLE_H + 0.03), (0.06, POLE_H + 0.07), (0.0, POLE_H + 0.08)], (0, 0, 0), "track_steel", segs=14,
            cap_bottom=False)
    for ay, aw in ((6.85, 0.78), (6.25, 0.58)):
        H.box("arm", (0.1, 0.1, aw * 2.0), (0.11, ay, 0), "pole_wood", bevel=0.008, grain="z")
        H.box("gain", (0.03, 0.16, 0.2), (0.08, ay, 0), "track_steel", bevel=0.004)
        for zs in (-1, 1):
            # Iron brace from the arm down to the pole.
            H.rod("brace", (0.07, ay - 0.05, zs * aw * 0.55), (0.1, ay - 0.55, 0.0), 0.012, "track_steel", segs=6)
    for x, y, z in WIRE_POINTS:
        base = 6.85 if y > 6.5 else 6.25
        H.cyl("pin", 0.012, y - 0.12 - base, (0.11, (base + y - 0.12) / 2 + 0.03, z), "track_steel", segs=8)
        H.lathe("ins", [(0.0, y - 0.13), (0.045, y - 0.12), (0.04, y - 0.06), (0.03, y - 0.04), (0.033, y - 0.015),
                        (0.022, y + 0.0), (0.0, y + 0.01)], (0.11, 0, z), "insulator", segs=12, cap_bottom=False, cap_top=False)
    # Pole number plate.
    H.box("plate", (0.012, 0.09, 0.07), (0.1, 2.3, 0), "track_steel", bevel=0.002)
    return H.finish("pole")


def lamp_post():
    H.lathe("base", [(0.0, 0.0), (0.2, 0.0), (0.2, 0.08), (0.16, 0.12), (0.15, 0.32), (0.11, 0.4), (0.075, 0.5)], (0, 0, 0), "cast_iron", segs=24)
    H.lathe("shaft", [(0.075, 0.5), (0.06, 1.2), (0.05, 3.2), (0.065, 3.28), (0.065, 3.34), (0.05, 3.4)], (0, 0, 0), "cast_iron", segs=16,
            cap_bottom=False)
    # Fluting: thin ribs on the shaft.
    for k in range(8):
        a = k * math.tau / 8
        H.rod("flute", (math.cos(a) * 0.062, 0.6, math.sin(a) * 0.062), (math.cos(a) * 0.05, 3.1, math.sin(a) * 0.05), 0.008, "cast_iron", segs=5)
    # Ladder bar.
    H.rod("ladder", (-0.38, 3.15, 0), (0.38, 3.15, 0), 0.016, "cast_iron", segs=8)
    for xs in (-1, 1):
        H.rod("strut", (xs * 0.3, 3.15, 0), (0.0, 2.8, 0), 0.012, "cast_iron", segs=6)
        H.sphere("knob", 0.025, (xs * 0.38, 3.15, 0), "cast_iron", segs=10, rings=6)
    # Lantern: tapered four-sided glazed box, roof and finial.
    H.box("seat", (0.26, 0.05, 0.26), (0, 3.44, 0), "cast_iron", bevel=0.006)
    for k in range(4):
        a = k * math.pi / 2
        H.rod("frame", (math.cos(a + math.pi / 4) * 0.15, 3.46, math.sin(a + math.pi / 4) * 0.15),
              (math.cos(a + math.pi / 4) * 0.22, 3.95, math.sin(a + math.pi / 4) * 0.22), 0.012, "cast_iron", segs=6)
    H.lathe("glass", [(0.105, 3.46), (0.155, 3.95)], (0, 0, 0), "lamp_glass", segs=4, cap_bottom=True, cap_top=True)
    H.lathe("roof", [(0.24, 3.94), (0.26, 3.97), (0.12, 4.12), (0.05, 4.18), (0.05, 4.24), (0.0, 4.3)], (0, 0, 0), "cast_iron", segs=4,
            cap_bottom=True)
    H.sphere("finial", 0.035, (0, 4.33, 0), "cast_iron", segs=10, rings=6)
    return H.finish("lamp_post")


def _decimate(objs, ratio):
    for o in objs:
        md = o.modifiers.new("dec", "DECIMATE")
        md.ratio = ratio


def ph_rock(asset, fit, ratio, pick=None):
    meshes, k = H.import_ph(asset, fit, origin="bottom", drop=None)
    if pick is not None and len(meshes) > 1:
        meshes.sort(key=lambda o: -len(o.data.vertices))
        for o in meshes[1:]:
            H._parts.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
        meshes = meshes[:1]
    _decimate(meshes, ratio)
    for o in meshes:
        o.data.transform(H.g_matrix((0, -0.15 * fit[1] / 2.0, 0)))
    return meshes


def rock(asset, ratio):
    def b():
        ph_rock(asset, (2.0, 1.6, 2.0), ratio, pick=0)
        return H.finish(asset)
    return b


def stump():
    meshes, k = H.import_ph("tree_stump_01", (0.9, 0.7, 0.9), origin="bottom")
    _decimate(meshes, 0.08)
    return H.finish("stump")


def bench():
    """Platform bench of the 1930s: cast-iron ends (back leg rising into the back support, front
    leg, seat rail, armrest ending in a scroll), wooden seat and back slats with gaps. 1.8 m long,
    seat 0.46 m high, front toward -Z, origin on the ground at the middle."""
    for x in (-0.82, 0.82):
        H.tube("back_leg", [(x, y, z) for z, y in ((0.24, 0.0), (0.21, 0.18), (0.19, 0.44), (0.24, 0.64), (0.31, 0.9))],
               0.022, "cast_iron", segs=8, bend=0.08)
        H.tube("front_leg", [(x, y, z) for z, y in ((-0.25, 0.0), (-0.19, 0.16), (-0.18, 0.3), (-0.21, 0.44))],
               0.022, "cast_iron", segs=8, bend=0.06)
        H.tube("seat_rail", [(x, 0.44, -0.24), (x, 0.45, 0.21)], 0.02, "cast_iron", segs=8)
        H.tube("arm", [(x, y, z) for z, y in ((0.25, 0.66), (0.05, 0.665), (-0.18, 0.645), (-0.26, 0.61), (-0.27, 0.56),
                                              (-0.23, 0.535), (-0.2, 0.56), (-0.215, 0.59))], 0.02, "cast_iron", segs=8, bend=0.03)
        H.tube("arm_post", [(x, 0.45, -0.19), (x, 0.64, -0.2)], 0.018, "cast_iron", segs=8)
        for z in (-0.27, 0.26):
            H.box("foot", (0.07, 0.025, 0.09), (x, 0.012, z), "cast_iron", bevel=0.005, segs=1)
    for k in range(5):
        z = -0.2 + k * 0.092
        H.box("seat_slat", (1.86, 0.035, 0.07), (0.0, 0.475, z), "bench_wood", bevel=0.006, segs=1, grain="x")
    for k, (y, z) in enumerate(((0.6, 0.235), (0.71, 0.268), (0.82, 0.3))):
        H.box("back_slat", (1.86, 0.08, 0.03), (0.0, y, z), "bench_wood", bevel=0.006, segs=1, grain="x", rot=(-0.28, 0, 0))
    return H.finish("bench")


def fence_lineside():
    """One 3 m bay of the boundary fence along the line and the platforms: a galvanised tube post
    (at x = 0) with a cap, a top rail, a tension wire at the foot and one at mid height, and the
    chain-link mesh (material "chainlink": the game draws the diamond wire). 1.8 m high, runs along
    +x from the post; the mesh on the +z face of the post."""
    L, Hh = 3.0, 1.8
    H.cyl("post", 0.03, Hh + 0.05, (0, (Hh + 0.05) / 2 - 0.05, 0), "galv_steel", segs=10)
    H.lathe("cap", [(0.0, Hh), (0.036, Hh), (0.036, Hh + 0.03), (0.0, Hh + 0.05)], (0, 0, 0), "galv_steel", segs=10)
    H.rod("rail", (0.0, Hh - 0.04, 0.035), (L, Hh - 0.04, 0.035), 0.02, "galv_steel", segs=8)
    for y in (0.08, Hh * 0.5):
        H.rod("wire", (0.0, y, 0.035), (L, y, 0.035), 0.003, "galv_steel", segs=4)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    pts = ((0, 0.04), (L, 0.04), (L, Hh - 0.05), (0, Hh - 0.05))
    vs = [bm.verts.new(H.G(x, y, 0.04)) for x, y in pts]
    f = bm.faces.new(vs)
    for lp, (x, y) in zip(f.loops, pts):
        lp[uv].uv = (x, y)
    bm.normal_update()
    H._new_obj("mesh", bm, "chainlink", 0.0, smooth=False)
    return H.finish("fence_lineside")


def export_model(obj, name, images):
    os.makedirs(H.OUT, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(H.OUT, name + ".gltf"), export_format="GLTF_SEPARATE",
        export_texture_dir="textures", use_selection=True, export_yup=True, export_apply=True,
        export_normals=True, export_tangents=True, export_materials="EXPORT",
        export_image_format="AUTO" if images else "NONE",
        export_cameras=False, export_lights=False, export_animations=False)
    os.makedirs(H.BLEND, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(H.BLEND, name + ".blend"), compress=True)


# name -> (builder, export images?)
MODELS = {
    "sleeper": (sleeper, False), "pole": (pole, False), "lamp_post": (lamp_post, False),
    "rock_a": (rock("rock_07", 0.08), True), "rock_b": (rock("rock_09", 0.09), True),
"stump": (stump, True), "bench": (bench, False), "fence_lineside": (fence_lineside, False),
}
BUILDERS = {k: v[0] for k, v in MODELS.items()}
