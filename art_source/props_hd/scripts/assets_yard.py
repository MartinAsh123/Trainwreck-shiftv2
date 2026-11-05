"""Station-yard security: the chain-link fence, its gate, the gatehouse, the road barrier and the
warning plates wired to the fence. GODOT space, real metres, front toward -Z.
    fence_chainlink  - 2.5 m bay: galvanised post in a footing, top rail, tension wires, chain-link
                       mesh (material "chainlink": the game draws the diamond wire with a shader),
                       a cranked arm with three strands of barbed wire leaning outward (+Z)
    gate_chainlink   - one 3.2 m leaf of a double gate with its hinge post, padlocked chain, plate
    warning_sign_a/b/c - plates wired to the mesh (railway notices)
    guard_booth      - the gatehouse with a desk, stool, telephone and log book
    boom_barrier     - pedestal and raised red-and-white boom with its rest post
"""
import math
import bmesh
import hdlib
from hdlib import *
import assets_station
from assets_station import snow_box

A = {}


def asset(fn):
    A[fn.__name__] = fn
    return fn


hdlib.MATS.update({
    "chainlink": dict(color=(0.55, 0.56, 0.57), rough=0.4, metal=1.0),
    "sign_white": dict(color=(0.92, 0.92, 0.88), rough=0.35),
    "sign_yellow": dict(color=(0.95, 0.72, 0.05), rough=0.35),
    "sign_red": dict(color=(0.7, 0.05, 0.04), rough=0.35),
    "booth_white": dict(tex="paint_cream", scale=1.2),
})

FENCE_L, FENCE_H = 2.5, 2.0


def chainlink_panel(name, w, h, x0, y0, z):
    """A flat panel of chain-link mesh, w x h, its lower-left corner at (x0, y0) in the plane z;
    UVs in metres (the Godot shader repeats the wire pattern in them)."""
    bm = bmesh.new()
    uv = hdlib._uv_layer(bm)
    vs = [bm.verts.new(G(x0 + x, y0 + y, z)) for x, y in ((0, 0), (w, 0), (w, h), (0, h))]
    f = bm.faces.new(vs)
    for lp, (u, v) in zip(f.loops, ((0, 0), (w, 0), (w, h), (0, h))):
        lp[uv].uv = (u, v)
    bm.normal_update()
    return hdlib._new_obj(name, bm, "chainlink", 0.0, smooth=False)


@asset
def fence_chainlink():
    """Runs along +x from the post at x = 0; outside toward +Z."""
    seed(120)
    L, H = FENCE_L, FENCE_H
    cyl("Footing", 0.12, 0.12, (0, 0.0, 0), "stone_cap", segs=12)
    cyl("Post", 0.03, H + 0.05, (0, (H + 0.05) / 2, 0), "galvanized", segs=12)
    lathe("PostCap", [(0.0, H + 0.05), (0.036, H + 0.05), (0.036, H + 0.08), (0.0, H + 0.1)], (0, 0, 0), "galvanized", segs=12)
    tube("TopRail", [(0.0, H - 0.04, 0.035), (L, H - 0.04, 0.035)], 0.021, "galvanized", 10)
    tube("TensionWire", [(0.0, 0.08, 0.035), (L, 0.08, 0.035)], 0.003, "galvanized", 5)
    tube("MidWire", [(0.0, H * 0.5, 0.035), (L, H * 0.5, 0.035)], 0.003, "galvanized", 5)
    chainlink_panel("Mesh", L, H - 0.07, 0.0, 0.05, 0.04)
    tube("Arm", [(0.0, H + 0.02, 0.0), (0.0, H + 0.4, 0.38)], 0.016, "galvanized", 8)
    for k in range(3):
        t = (k + 0.5) / 3
        y, z = H + 0.06 + 0.32 * t, 0.06 + 0.3 * t
        tube("Barbed", [(0.0, y, z), (L, y - 0.01, z)], 0.0022, "galvanized", 4)
        for b in range(10):
            x = (b + 0.5) * L / 10
            tube("Barb", [(x - 0.012, y - 0.012, z - 0.006), (x + 0.012, y + 0.012, z + 0.006)], 0.0016, "galvanized", 4)
            tube("Barb", [(x - 0.012, y + 0.012, z + 0.006), (x + 0.012, y - 0.012, z - 0.006)], 0.0016, "galvanized", 4)


@asset
def gate_chainlink():
    """Hinge post at x = 0, the leaf along +x; origin on the ground."""
    seed(121)
    W, H = 3.2, 2.0
    cyl("HingePost", 0.05, H + 0.25, (0, (H + 0.25) / 2, 0), "galvanized", segs=14)
    lathe("PostCap", [(0.0, H + 0.25), (0.058, H + 0.25), (0.058, H + 0.29), (0.0, H + 0.32)], (0, 0, 0), "galvanized", segs=14)
    x0 = 0.1
    pts = [(x0, 0.08, 0), (W, 0.08, 0), (W, H, 0), (x0, H, 0), (x0, 0.08, 0)]
    for i in range(4):
        tube("Frame", [pts[i], pts[i + 1]], 0.024, "galvanized", 10)
    tube("Brace", [(x0, 0.1, 0), (W, H - 0.02, 0)], 0.016, "galvanized", 8)
    tube("MidRail", [(x0, H / 2, 0), (W, H / 2, 0)], 0.016, "galvanized", 8)
    chainlink_panel("Mesh", W - x0 - 0.04, H - 0.14, x0 + 0.02, 0.11, 0.0)
    for y in (0.35, H - 0.3):
        torus("Hinge", 0.06, 0.014, (0.05, y, 0), "steel_dark", segs=16, rsegs=6)
    cyl("DropBolt", 0.012, 0.6, (W - 0.12, 0.3, -0.03), "steel_dark", segs=8)
    tube("Chain", [(W, 1.0, -0.03), (W + 0.04, 0.85, -0.05), (W + 0.02, 0.75, -0.04)], 0.006, "steel_dark", 6, bend=0.04)
    box("Padlock", (0.05, 0.06, 0.025), (W + 0.02, 0.7, -0.04), "brass", 0.006)
    xc = (x0 + W) / 2
    box("PlateBorder", (0.62, 0.42, 0.004), (xc, 1.35, -0.016), "sign_red", 0.003)
    pl = box("Plate", (0.6, 0.4, 0.006), (xc, 1.35, -0.021), "sign_white", 0.004)
    text_on("PlateText", "NO\nUNAUTHORISED\nENTRY", pl, (xc, 1.35, -0.06), 0.06, "sign_red", lift=0.0012)


def _warning(text, key, ink, tri):
    seed(122)
    w, h = 0.5, 0.36
    box("Border", (w + 0.02, h + 0.02, 0.003), (0, 1.55, -0.064), "sign_red" if key == "sign_white" else "poster_ink", 0.002)
    pl = box("Plate", (w, h, 0.004), (0, 1.55, -0.068), key, 0.003)
    if tri:
        tx = -w / 2 + 0.1
        tri_pts = [(-0.07, -0.06), (0.07, -0.06), (0.0, 0.065)]
        extrude("Triangle", tri_pts, 0.002, "poster_ink", (tx, 1.56, -0.072), bevel=0.0)
        extrude("TriangleIn", [(x * 0.7, y * 0.7 - 0.005) for x, y in tri_pts], 0.002, key, (tx, 1.56, -0.074),
                bevel=0.0)
        box("Excl", (0.01, 0.04, 0.002), (tx, 1.565, -0.076), "poster_ink", 0.0)
        box("ExclDot", (0.01, 0.01, 0.002), (tx, 1.533, -0.076), "poster_ink", 0.0)
        text_on("Text", text, pl, (0.065, 1.55, -0.1), 0.042, ink, lift=0.0012)
    else:
        text_on("Text", text, pl, (0.0, 1.55, -0.1), 0.05, ink, lift=0.0012)
    for sx in (-1, 1):
        for sy in (-1, 1):
            torus("Tie", 0.008, 0.0015, (sx * (w / 2 - 0.03), 1.55 + sy * (h / 2 - 0.03), -0.066), "galvanized", axis=(0, 0, 1),
                  segs=10, rsegs=4)


@asset
def warning_sign_a():
    """Plates wired to the fence mesh (the mesh 0.04 in front of the post line at z = 0), facing -Z."""
    _warning("NO UNAUTHORISED\nENTRY", "sign_white", "sign_red", False)


@asset
def warning_sign_b():
    _warning("DANGER!\nRAILWAY LINE\nKEEP OUT", "sign_yellow", "poster_ink", True)


@asset
def warning_sign_c():
    _warning("DANGER\nOF DEATH", "sign_yellow", "poster_ink", True)


@asset
def guard_booth():
    """2 x 2 m gatehouse, windows on three sides, door at the back (+Z), front (-Z) to the road."""
    seed(123)
    W, D, H = 2.0, 2.0, 2.45
    box("Floor", (W, 0.15, D), (0, 0.075, 0), "stone_cap", 0.01)
    for k in range(4):
        a = k * math.pi / 2
        ca, sa = math.cos(a), math.sin(a)
        if k == 2:
            box("BackWall", (W - 0.95, H - 0.15, 0.06), (-0.45, 0.15 + (H - 0.15) / 2, D / 2 - 0.03), "booth_white", 0.008, grain="y")
            box("Door", (0.85, 2.05, 0.05), (0.5, 0.15 + 1.025, D / 2 - 0.03), "paint_green", 0.008, grain="y")
            box("DoorGlass", (0.5, 0.6, 0.01), (0.5, 1.75, D / 2), "glass", 0.0)
            continue
        box("Lower", (W - 0.06, 1.0, 0.06), (sa * (W / 2 - 0.03), 0.65, -ca * (D / 2 - 0.03)), "booth_white", 0.008, rot=(0, a, 0))
        box("Glass", (W - 0.2, H - 1.35, 0.012), (sa * (W / 2 - 0.03), 1.15 + (H - 1.35) / 2, -ca * (D / 2 - 0.03)), "glass", 0.0,
            rot=(0, a, 0))
        box("Sill", (W, 0.05, 0.14), (sa * (W / 2), 1.17, -ca * (D / 2)), "stone_cap", 0.006, rot=(0, a, 0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            box("Post", (0.1, H - 0.15, 0.1), (sx * (W / 2 - 0.05), 0.15 + (H - 0.15) / 2, sz * (D / 2 - 0.05)), "booth_white", 0.01,
                grain="y")
    box("Roof", (W + 0.5, 0.15, D + 0.5), (0, H + 0.075, 0), "paint_black", 0.02)
    snow_box("RoofSnow", (W + 0.4, 0.08, D + 0.4), (0, H + 0.19, 0))
    pl = box("NamePlate", (1.1, 0.2, 0.02), (0, H - 0.12, -D / 2 - 0.02), "enamel_blue", 0.004)
    text_on("NameText", "GATEHOUSE", pl, (0, H - 0.12, -D / 2 - 0.06), 0.11, "poster_cream", lift=0.0012)
    box("Desk", (1.7, 0.04, 0.5), (0, 0.9, -D / 2 + 0.33), "wood_dark", 0.006)
    box("DeskFront", (1.7, 0.75, 0.03), (0, 0.525, -D / 2 + 0.56), "wood_dark", 0.006, grain="y")
    box("Phone", (0.18, 0.08, 0.2), (0.5, 0.96, -D / 2 + 0.3), "bakelite", 0.01)
    tube("Handset", [(0.42, 1.01, -D / 2 + 0.3), (0.58, 1.01, -D / 2 + 0.3)], 0.02, "bakelite", 8)
    box("LogBook", (0.3, 0.03, 0.22), (-0.3, 0.935, -D / 2 + 0.32), "leather_green", 0.004)
    cyl("Stool", 0.17, 0.04, (0.1, 0.62, 0.1), "wood_dark", segs=16)
    for k in range(3):
        t = math.tau * k / 3
        tube("StoolLeg", [(0.1 + math.cos(t) * 0.12, 0.6, 0.1 + math.sin(t) * 0.12),
                          (0.1 + math.cos(t) * 0.17, 0.15, 0.1 + math.sin(t) * 0.17)], 0.014, "steel_dark", 6)
    lathe("CeilingLamp", [(0.0, H - 0.05), (0.12, H - 0.05), (0.1, H - 0.15), (0.0, H - 0.17)], (0, 0, 0), "panel_lit", segs=16)


@asset
def boom_barrier():
    """Pedestal at the origin, the boom (when down) along +x; here raised."""
    seed(124)
    box("Pedestal", (0.32, 1.0, 0.32), (0, 0.5, 0), "sign_red", 0.02, grain="y")
    box("Cap", (0.36, 0.06, 0.36), (0, 1.03, 0), "paint_black", 0.01)
    cyl("Pivot", 0.06, 0.4, (0, 0.92, 0), "steel_dark", axis=(0, 0, 1), segs=16)
    n0 = count()
    L = 4.2
    for k in range(7):
        x0, x1 = 0.15 + k * L / 7, 0.15 + (k + 1) * L / 7
        box("Boom", (x1 - x0, 0.08, 0.06), ((x0 + x1) / 2, 0.0, 0), "sign_red" if k % 2 == 0 else "sign_white", 0.01)
    box("Counterweight", (0.4, 0.18, 0.16), (-0.35, 0.0, 0), "paint_black", 0.02)
    sphere("Lamp", 0.035, (L * 0.5, 0.05, 0), "lens_red", segs=12, rings=6)
    transform_since(n0, (0, 0.92, 0), (0, 0, math.radians(82)))
    box("Rest", (0.12, 0.85, 0.12), (L + 0.1, 0.425, 0.35), "sign_red", 0.01, grain="y")
    box("RestFork", (0.16, 0.08, 0.16), (L + 0.1, 0.89, 0.35), "paint_black", 0.01)


VIEWS = {"fence_chainlink": (0.6, 0.4, -1.0), "gate_chainlink": (0.6, 0.3, -1.0), "guard_booth": (0.7, 0.5, -1.0),
         "boom_barrier": (0.4, 0.3, -1.0), "warning_sign_a": (0.0, 0.0, -1.0), "warning_sign_b": (0.0, 0.0, -1.0)}
