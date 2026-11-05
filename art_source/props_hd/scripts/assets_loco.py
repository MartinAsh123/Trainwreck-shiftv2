"""Locomotive fittings (cab, backhead, lamps, tender front, buffers). Godot space; each asset's
origin is noted - most are built in locomotive coordinates relative to that origin so the GDScript
can drop them in at one point."""
import math
import bmesh
from mathutils import Vector
import hdlib
from hdlib import *
from assets_crew import screw

A = {}
VIEWS = {"coal_hole": (-1.0, 0.5, 0.6), "cab_seat": (-0.8, 0.4, -1.0), "water_valve": (-1.0, 0.3, -0.6), "backhead_fittings": (1.0, 0.3, 0.45), "gauge_case": (0.35, 0.25, 1.0), "reverser": (1.0, 0.4, 0.6),
         "water_valve": (-1.0, 0.3, -0.6), "sanding_lever": (0.5, 0.3, 1.0), "shovel": (-1.0, 0.4, 0.5)}


def asset(fn):
    A[fn.__name__] = fn
    return fn


def handwheel(name, r, center, axis, key, spokes=5, rim=None, hub=None):
    """Spoked valve handwheel facing along `axis`."""
    rim = rim or r * 0.16
    hub = hub or r * 0.28
    torus(name + "Rim", r, rim, center, key, axis=axis, segs=48, rsegs=12)
    a = Vector(axis).normalized()
    u = a.orthogonal().normalized()
    v = a.cross(u)
    c = Vector(center)
    for k in range(spokes):
        t = math.tau * k / spokes
        d = u * math.cos(t) + v * math.sin(t)
        tube(name + "Spoke", [tuple(c + d * hub * 0.8), tuple(c + d * (r - rim * 0.5) - a * 0.002)], rim * 0.55, key, 8)
    lathe(name + "Hub", [(0, -rim * 1.6), (hub, -rim * 1.6), (hub * 1.05, 0), (hub, rim * 1.6), (0, rim * 1.6)], center, key, axis=axis, segs=24)


def rivet_ring(name, center, axis, R, n, r=0.006, key="paint_black"):
    a = Vector(axis).normalized()
    u = a.orthogonal().normalized()
    v = a.cross(u)
    c = Vector(center)
    for k in range(n):
        t = math.tau * k / n
        p = c + (u * math.cos(t) + v * math.sin(t)) * R
        sphere(name, r, tuple(p), key, (1, 1, 1), 10, 5)


def railway_lamp(body_key, lens_key):
    """Lamp body centred at the origin, lens toward -Z."""
    box("Body", (0.17, 0.2, 0.17), (0, 0, 0), body_key, 0.012, 3, grain="y")
    lathe("Hood", [(0.0, 0.1), (0.09, 0.1), (0.09, 0.11), (0.07, 0.13), (0.045, 0.14), (0.045, 0.16), (0.055, 0.165),
                   (0.05, 0.175), (0, 0.18)], (0, 0, 0), body_key, segs=32)
    for k in range(4):
        box("Vent", (0.05, 0.004, 0.006), (0, 0.135 + k * 0.0, -0.05 + k * 0.03), "black_paint_gloss", 0.001)
    lathe("LensBezel", [(0.058, 0), (0.078, 0), (0.08, 0.012), (0.074, 0.03), (0.066, 0.032), (0.058, 0.02)], (0, 0, -0.085),
          "brass", axis=(0, 0, -1), segs=48, cap_bottom=False, cap_top=False)
    lathe("Lens", [(0, 0), (0.062, 0), (0.058, 0.01), (0.04, 0.02), (0, 0.024)], (0, 0, -0.09), lens_key, axis=(0, 0, -1), segs=48)
    tube("Bail", [(-0.07, 0.11, 0.0), (-0.07, 0.17, 0.0), (0.07, 0.17, 0.0), (0.07, 0.11, 0.0)], 0.006, "steel_dark", 10, bend=0.03)
    for sx in (-1, 1):
        cyl("BailPivot", 0.01, 0.01, (sx * 0.072, 0.11, 0), "steel_dark", axis=(1, 0, 0), segs=12)
    box("Socket", (0.06, 0.12, 0.03), (0, -0.05, 0.1), "iron", 0.004)
    for sy in (-1, 1):
        cyl("DoorHinge", 0.006, 0.05, (0.087, sy * 0.06, 0.03), "brass", segs=12)
    box("DoorCatch", (0.014, 0.03, 0.02), (-0.088, 0, 0.03), "brass", 0.002)


@asset
def railway_lamp_white():
    seed(61)
    railway_lamp("paint_black", "lens_white")


@asset
def railway_lamp_red():
    seed(62)
    railway_lamp("paint_red", "lens_red")


@asset
def cab_lamp():
    """Ceiling lamp; origin at the ceiling, hanging down (-Y)."""
    seed(63)
    lathe("Gallery", [(0, 0), (0.07, 0), (0.07, -0.01), (0.05, -0.02), (0.045, -0.035), (0.052, -0.04), (0.052, -0.05), (0, -0.05)],
          (0, 0, 0), "brass", segs=48)
    sphere("Globe", 0.055, (0, -0.1, 0), "lens_white", (1, 1.1, 1), 40, 20)
    for k in range(4):
        t = math.tau * k / 4 + 0.4
        tube("CageWire", [(math.cos(t) * 0.05, -0.045, math.sin(t) * 0.05), (math.cos(t) * 0.064, -0.1, math.sin(t) * 0.064),
                          (math.cos(t) * 0.02, -0.162, math.sin(t) * 0.02)], 0.0025, "brass", 6, bend=0.03)
    torus("CageRing", 0.062, 0.0028, (0, -0.1, 0), "brass", segs=40, rsegs=6)
    sphere("CageFoot", 0.012, (0, -0.164, 0), "brass")


@asset
def gauge_case():
    """Pressure gauge body at radius 0.1 (scaled in Godot): back on the backhead at z = 0, face +Z."""
    seed(64)
    r = 0.1
    lathe("Case", [(0, 0), (r + 0.006, 0), (r + 0.012, 0.01), (r + 0.012, 0.05), (r + 0.006, 0.056), (r - 0.002, 0.056)],
          (0, 0, 0), "paint_black", axis=(0, 0, 1), segs=64, cap_top=False)
    lathe("Bezel", [(r - 0.006, 0.054), (r + 0.016, 0.054), (r + 0.018, 0.06), (r + 0.014, 0.068), (r - 0.002, 0.068), (r - 0.006, 0.062)],
          (0, 0, 0), "brass", axis=(0, 0, 1), segs=72, cap_bottom=False, cap_top=False)
    for k in range(48):
        t = math.tau * k / 48
        box("Knurl", (0.004, 0.003, 0.01), (math.cos(t) * (r + 0.017), math.sin(t) * (r + 0.017), 0.06), "brass", 0.0, rot=(0, 0, t))
    for t in (math.pi * 0.25, math.pi * 0.75):
        box("Lug", (0.03, 0.016, 0.012), (math.cos(t) * (r + 0.02), math.sin(t) * (r + 0.02), 0.006), "paint_black", 0.003, rot=(0, 0, t))
        screw("LugBolt", math.cos(t) * (r + 0.026), math.sin(t) * (r + 0.026), 0.012, 0.005, axis=(0, 0, 1), key="steel")
    # Siphon pigtail from the bottom of the case back into the boiler.
    tube("Siphon", [(0, -r - 0.004, 0.025), (0, -r - 0.04, 0.025), (0.025, -r - 0.065, 0.025), (0.0, -r - 0.09, 0.02),
                    (-0.02, -r - 0.07, 0.015), (0, -r - 0.05, 0.01), (0, -r - 0.05, -0.02)], 0.006, "copper", 10, bend=0.015)
    lathe("SiphonNut", [(0, 0), (0.011, 0), (0.011, 0.016), (0, 0.016)], (0, -r - 0.002, 0.025), "brass", axis=(0, -1, 0), segs=6)


def water_gauge(z, zs):
    """One water gauge assembly in backhead space (x from the backhead face, +X into the cab)."""
    for y, nm in ((1.4, "Top"), (0.93, "Bottom")):
        lathe("Cock" + nm, [(0, -0.035), (0.026, -0.035), (0.03, -0.02), (0.03, 0.02), (0.026, 0.035), (0, 0.035)],
              (0.04, y, z), "brass", segs=24)
        cyl("CockBoss", 0.022, 0.04, (0.02, y, z), "brass", axis=(1, 0, 0), segs=24)
        handwheel("CockWheel" + nm, 0.024, (0.04, y, z + zs * 0.045), (0, 0, zs), "bakelite_brown", 4)
    cyl("GlassTube", 0.014, 0.4, (0.05, 1.165, z), "glass", segs=24)
    cyl("Water", 0.011, 0.24, (0.05, 1.09, z), "water", segs=24)
    for k in (-1, 1):
        tube("Guard", [(0.075, 0.97, z + k * 0.028), (0.075, 1.36, z + k * 0.028)], 0.0045, "brass", 8)
    box("GuardBack", (0.004, 0.36, 0.05), (0.03, 1.165, z), "enamel_white", 0.0)
    for k in range(5):
        box("GuardStripe", (0.002, 0.36, 0.004), (0.031, 1.165, z - 0.02 + k * 0.01), "black_paint_gloss", 0.0)
    tube("DrainPipe", [(0.04, 0.89, z), (0.04, 0.8, z), (0.06, 0.7, z)], 0.008, "copper", 10, bend=0.03)
    tube("DrainHandle", [(0.07, 0.89, z), (0.12, 0.84, z + zs * 0.06)], 0.007, "brass", 10)
    sphere("DrainGrip", 0.013, (0.123, 0.837, z + zs * 0.063), "bakelite_brown", (1, 1, 1.5))


@asset
def backhead_fittings():
    """Firebox backhead with its fittings; origin at (BH_X, 0, 0) in locomotive space, +X into the cab."""
    seed(65)
    W = 0.95
    # The lower plate is built round the firehole (an opening 0.36 x 0.3 m at fy).
    fy = 0.62
    hz, hy = 0.18, 0.15
    box("BackheadLower", (0.16, fy - hy, W * 2.0), (-0.08, (fy - hy) / 2, 0), "paint_black", 0.01, 3, grain="y")
    box("BackheadLower", (0.16, 1.05 - fy - hy, W * 2.0), (-0.08, (1.05 + fy + hy) / 2, 0), "paint_black", 0.01, 3, grain="y")
    for zs in (-1, 1):
        box("BackheadLower", (0.16, 2 * hy, W - hz), (-0.08, fy, zs * (W + hz) / 2), "paint_black", 0.002, 2, grain="y")
    half_disc("BackheadTop", W, 1.05, -0.16, 0.0, "paint_black")      # the top half only: the firehole is below
    torus("Ring", W - 0.005, 0.012, (0.0, 1.05, 0), "steel", axis=(1, 0, 0), segs=96, rsegs=12)
    rivet_ring("Rivet", (0.002, 1.05, 0), (1, 0, 0), W - 0.05, 72, 0.009)
    for z in (-W + 0.05, W - 0.05):
        for k in range(10):
            sphere("Rivet", 0.009, (0.002, 0.08 + k * 0.1, z), "paint_black", (1, 1, 1), 10, 5)
    # Firehole: oval ring, the two sliding leaves run open along their runners, deflector plate
    # above. Through the mouthpiece: the firebox, its brick walls lit by a bright fire bed.
    torus("FireholeRing", 0.22, 0.03, (0.02, fy, 0), "steel_dark", axis=(1, 0, 0), segs=64, rsegs=12)
    for zs in (-1, 1):
        box("Mouth", (0.16, 2 * hy, 0.012), (-0.08, fy, zs * (hz - 0.006)), "iron", 0.002)
        box("Mouth", (0.16, 0.012, 2 * hz), (-0.08, fy + zs * (hy - 0.006), 0), "iron", 0.002)
    for zs in (-1, 1):
        zc = zs * (0.12 + 0.235)                         # slid fully open
        box("Leaf", (0.03, 0.34, 0.235), (0.045, fy, zc), "iron", 0.008, 3, grain="y")
        for k in range(4):
            box("LeafRib", (0.008, 0.012, 0.2), (0.062, fy - 0.12 + k * 0.08, zc), "iron", 0.003)
        hzz = zc - zs * 0.08
        tube("Handle", [(0.06, fy + 0.06, hzz), (0.1, fy + 0.06, hzz), (0.1, fy - 0.06, hzz), (0.06, fy - 0.06, hzz)],
             0.011, "steel", 12, bend=0.02)
    box("Runner", (0.03, 0.03, 1.1), (0.045, fy + 0.2, 0), "iron", 0.006)
    box("Runner", (0.03, 0.03, 1.1), (0.045, fy - 0.2, 0), "iron", 0.006)
    box("Deflector", (0.14, 0.02, 0.52), (0.09, fy + 0.25, 0), "steel", 0.004)
    firebox_inside(fy, hz, hy)
    # Water gauges either side.
    for zs in (-1, 1):
        water_gauge(zs * 0.62, zs)
    # Regulator: boss, quadrant, long handle with a wooden grip (driver's side, -Z).
    lathe("RegBoss", [(0, 0), (0.065, 0), (0.06, 0.04), (0.04, 0.08), (0, 0.085)], (0.0, 1.42, -0.05), "steel", axis=(1, 0, 0), segs=40)
    pts = [(0.0, 1.42 + 0.17 * math.cos(t), -0.05 - 0.17 * math.sin(t)) for t in [i * 0.08 for i in range(12)]]
    tube("RegQuadrant", pts, 0.008, "brass", 8)
    tube("RegHandle", [(0.08, 1.42, -0.05), (0.1, 1.36, -0.3), (0.12, 1.3, -0.48)], 0.016, "steel", 16, bend=0.1)
    lathe("RegGrip", [(0, 0), (0.02, 0.0), (0.026, 0.04), (0.024, 0.09), (0.015, 0.11), (0, 0.112)], (0.12, 1.3, -0.48), "handle",
          axis=(0.0, -0.3, -1.0), segs=24)
    # Steam manifold with its valve wheels (injectors, blower, ejector, whistle).
    cyl("Manifold", 0.05, 1.0, (0.06, 1.92, 0), "brass", axis=(0, 0, 1), segs=40, bevel=0.006)
    for z in (-0.5, 0.5):
        lathe("ManifoldCap", [(0, 0), (0.06, 0), (0.06, 0.02), (0.04, 0.03), (0, 0.03)], (0.06, 1.92, z), "brass", axis=(0, 0, 1 if z > 0 else -1), segs=32)
    lathe("Turret", [(0, 0), (0.07, 0), (0.07, 0.08), (0.05, 0.12), (0, 0.12)], (0.06, 1.95, 0), "brass", segs=40)
    for i in range(5):
        z = -0.4 + i * 0.2
        lathe("ValveBody", [(0, 0), (0.03, 0), (0.034, 0.03), (0.024, 0.06), (0, 0.06)], (0.06, 1.92, z), "brass", axis=(1, -0.5, 0), segs=24)
        tube("Spindle", [(0.09, 1.905, z), (0.17, 1.86, z)], 0.008, "steel", 10)
        handwheel("ValveWheel%d" % i, 0.045, (0.17, 1.86, z), (1, -0.5, 0), "paint_red" if i % 2 == 0 else "paint_black", 5)
    tube("WhistleCord", [(0.1, 2.0, 0.41), (0.2, 1.3, 0.41)], 0.004, "string", 6)
    lathe("WhistleHandle", [(0, 0), (0.016, 0), (0.02, 0.02), (0.016, 0.05), (0, 0.055)], (0.2, 1.24, 0.41), "handle", segs=20)
    # Copper steam pipes with flanged joints.
    for zs in (-1, 1):
        tube("SteamPipe", [(0.05, 1.92, zs * 0.5), (0.05, 1.7, zs * 0.75), (0.05, 1.5, zs * 0.85), (0.05, 0.2, zs * 0.88)],
             0.02, "copper", 16, bend=0.12)
        for y in (1.2, 0.6):
            cyl("Flange", 0.034, 0.016, (0.05, y, zs * 0.875), "brass", segs=24)
            for k in range(4):
                t = math.tau * k / 4
                screw("FlangeBolt", 0.05 + math.cos(t) * 0.026, y + 0.009, zs * 0.875 + math.sin(t) * 0.026, 0.005, axis=(0, 1, 0), key="steel")
    # Driver's brake valve (-Z side).
    lathe("BrakeValve", [(0, 0), (0.07, 0), (0.075, 0.04), (0.06, 0.14), (0.045, 0.18), (0, 0.19)], (0.08, 1.06, -0.85), "brass", segs=40)
    cyl("BrakeValveCap", 0.04, 0.03, (0.08, 1.265, -0.85), "brass", segs=32)
    tube("BrakeHandle", [(0.13, 1.25, -0.85), (0.22, 1.29, -0.8), (0.3, 1.3, -0.75)], 0.012, "steel", 12, bend=0.05)
    sphere("BrakeGrip", 0.024, (0.3, 1.3, -0.75), "bakelite", (1, 1, 1.4))
    box("BrakePlate", (0.004, 0.05, 0.12), (0.157, 1.15, -0.85), "brass", 0.001)


@asset
def reverser():
    """Screw reverser; origin at the pedestal's foot (-10.55, 0, -1.05), wheel toward +X."""
    seed(66)
    lathe("Pedestal", [(0, 0), (0.12, 0), (0.12, 0.02), (0.09, 0.04), (0.07, 0.1), (0.062, 0.85), (0.075, 0.9), (0.08, 0.95), (0, 0.95)],
          (0, 0, 0), "paint_black", segs=40)
    box("Housing", (0.18, 0.12, 0.14), (0.02, 0.98, 0), "paint_black", 0.012)
    box("Scale", (0.012, 0.32, 0.1), (0.08, 0.75, 0), "brass", 0.003, grain="y")
    for k in range(7):
        box("Tick", (0.003, 0.003 if k % 3 else 0.005, 0.05 if k % 3 else 0.07), (0.0875, 0.62 + k * 0.045, 0), "black_paint_gloss", 0.0)
    box("Pointer", (0.02, 0.006, 0.02), (0.095, 0.8, -0.03), "steel", 0.002)
    tube("Spindle", [(0.1, 0.98, 0), (0.25, 0.98, 0)], 0.02, "steel", 16)
    handwheel("Wheel", 0.165, (0.25, 0.98, 0), (1, 0, 0), "steel", 6, rim=0.017, hub=0.035)
    tube("HandleArm", [(0.25, 1.12, 0.06), (0.27, 1.12, 0.06)], 0.01, "steel", 8)
    lathe("Handle", [(0, 0), (0.016, 0), (0.019, 0.03), (0.017, 0.08), (0.012, 0.09), (0, 0.092)], (0.27, 1.12, 0.06), "handle",
          axis=(1, 0, 0), segs=20)
    box("Catch", (0.04, 0.03, 0.03), (0.12, 1.05, 0.06), "steel_dark", 0.004)


@asset
def cab_seat():
    """Crew seat: a cast pedestal bolted to the footplate, a wooden seat with a buttoned leather
    cushion (top 0.7 m) and a padded backrest on two stays behind it (+X, toward the tender), a
    footrest bar, and a strap to the cab side (+Z, at z = 0.2). Origin: floor under the seat."""
    seed(67)
    lathe("Foot", [(0, 0), (0.13, 0), (0.13, 0.012), (0.06, 0.04), (0.035, 0.07), (0, 0.07)], (0, 0, 0), "paint_black", segs=40)
    for k in range(4):
        t = math.tau * k / 4 + math.pi / 4
        screw("FootBolt", math.cos(t) * 0.1, 0.012, math.sin(t) * 0.1, 0.01, axis=(0, 1, 0), key="steel_dark")
    cyl("Column", 0.03, 0.56, (0, 0.34, 0), "paint_black", segs=24)
    lathe("Head", [(0, 0), (0.045, 0), (0.07, 0.04), (0.07, 0.05), (0, 0.05)], (0, 0.6, 0), "paint_black", segs=32)
    torus("Footrest", 0.17, 0.011, (0, 0.24, 0), "steel", segs=40, rsegs=8)
    for k in range(3):
        t = math.tau * k / 3 + 0.3
        tube("FootrestStay", [(0, 0.24, 0), (math.cos(t) * 0.165, 0.24, math.sin(t) * 0.165)], 0.008, "paint_black", 8)
    tube("WallStrap", [(0, 0.45, 0.02), (0, 0.45, 0.19)], 0.012, "paint_black", 8)
    box("WallPlate", (0.1, 0.14, 0.012), (0, 0.45, 0.194), "paint_black", 0.003, grain="y")
    box("Seat", (0.38, 0.04, 0.34), (0, 0.67, 0), "wood_dark", 0.008, grain="x")
    box("Cushion", (0.35, 0.05, 0.31), (0, 0.712, 0), "leather", 0.02, 4)
    for sx in (-1, 1):
        for sz in (-1, 1):
            sphere("Button", 0.006, (sx * 0.08, 0.738, sz * 0.07), "leather", (1, 0.4, 1), 12, 6)
    # Backrest: two flat stays from under the seat, curving up behind it.
    for sz in (-1, 1):
        tube("BackStay", [(0.12, 0.66, sz * 0.12), (0.19, 0.68, sz * 0.12), (0.22, 0.8, sz * 0.12), (0.24, 0.98, sz * 0.12)],
             0.011, "paint_black", 8, bend=0.04)
    box("BackBoard", (0.03, 0.2, 0.36), (0.25, 0.92, 0), "wood_dark", 0.006, grain="z", rot=(0, 0, 0.12))
    box("BackPad", (0.04, 0.17, 0.32), (0.226, 0.92, 0), "leather", 0.016, 3, rot=(0, 0, 0.12))


@asset
def shovel():
    """Fireman's shovel leaning on the tender; origin at (-8.75, 0, 0.42)."""
    seed(68)
    n0 = count()
    pts = [(-0.13, 0.0), (0.13, 0.0), (0.12, 0.3), (0.06, 0.34), (-0.06, 0.34), (-0.12, 0.3)]
    obj = extrude("Blade", pts, 0.004, "steel_dark", (0, 0, 0), rot=(math.pi / 2, 0, 0), bevel=0.0015)
    for v in obj.data.vertices:                       # dish the blade
        gx, gz = v.co.x, -v.co.y
        v.co.z += 0.03 * (gx / 0.13) ** 2
    for sx in (-1, 1):
        box("Lip", (0.004, 0.03, 0.3), (sx * 0.128, 0.028, 0.15), "steel_dark", 0.0015)
    tube("Socket", [(0, 0.01, 0.32), (0, 0.03, 0.42)], 0.02, "steel_dark", 12, radii=[0.022, 0.018])
    transform_since(n0, (0, 0.06, 0), (math.radians(-80), math.pi / 2, 0.18))
    tube("Shaft", [(-0.01, 0.42, 0), (0.07, 1.05, 0)], 0.018, "handle", 16)
    tube("GripStem", [(0.07, 1.05, 0), (0.074, 1.08, 0)], 0.016, "handle", 12)
    tube("DGrip", [(0.074, 1.08, -0.06), (0.074, 1.08, 0.06)], 0.016, "handle", 12)
    for sz in (-1, 1):
        tube("DSide", [(0.074, 1.08, sz * 0.06), (0.072, 1.04, sz * 0.04), (0.07, 1.03, 0)], 0.01, "steel_dark", 8, bend=0.02)


@asset
def fire_irons():
    """Rack of three fire irons on the tender front; origin at (-8.66, 0, 0), irons along Z."""
    seed(69)
    for z in (-0.4, 0.9):
        box("Bracket", (0.03, 0.3, 0.03), (0.0, 1.83, z), "paint_black", 0.004, grain="y")
        for k in range(3):
            tube("Hook", [(0.0, 1.75 + k * 0.08 - 0.02, z), (-0.03, 1.75 + k * 0.08 - 0.02, z), (-0.035, 1.75 + k * 0.08 + 0.015, z)],
                 0.006, "paint_black", 8, bend=0.01)
    for k, kind in enumerate(("clinker", "pricker", "dart")):
        y = 1.75 + k * 0.08
        tube("Iron", [(-0.025, y, -0.6), (-0.025, y, 1.2)], 0.012, "steel_dark", 12)
        torus("HandleLoop", 0.035, 0.008, (-0.025, y, -0.64), "steel_dark", axis=(1, 0, 0), segs=24, rsegs=8)
        if kind == "clinker":
            box("Paddle", (0.01, 0.07, 0.12), (-0.025, y - 0.03, 1.24), "steel_dark", 0.003, rot=(0.3, 0, 0))
        elif kind == "pricker":
            tube("Tip", [(-0.025, y, 1.2), (-0.025, y - 0.1, 1.24)], 0.01, "steel_dark", 10, bend=0.03)
        else:
            extrude("Dart", [(0, 0.0), (0.035, 0.04), (0.0, 0.16), (-0.035, 0.04)], 0.008, "steel_dark", (-0.025, y, 1.2), rot=(math.pi / 2, 0, 0), bevel=0.002)


def coal_lump(center, s, k, key="coal", segs=14, rings=7):
    """A lump of coal of size s: a rough ball cut by random planes into flat, sharp facets (coal
    breaks conchoidally into angular chunks), flattened a little to lie on its broad side."""
    seed(700 + k)
    rng = hdlib._rng
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    for _ in range(7 + int(rng.random() * 4)):
        n = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        d = rng.uniform(0.45, 0.8)
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=n * d, plane_no=n,
                                     clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    sx, sy, sz = 1.0, 0.6 + rng.random() * 0.15, 0.75 + rng.random() * 0.2
    yaw = rng.random() * math.tau
    cy, sn = math.cos(yaw), math.sin(yaw)
    for v in bm.verts:
        x, z, y = v.co.x * sx * s, v.co.y * sz * s, v.co.z * sy * s
        x, z = x * cy - z * sn, x * sn + z * cy
        v.co = G(center[0] + x, center[1] + y, center[2] + z)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, key, "x", rng)
    return hdlib._new_obj("Coal", bm, key, 0.0, smooth=False)


hdlib.MATS.update({
    "firebrick_hot": dict(tex="rust", tint=(0.9, 0.42, 0.25), scale=0.3, emit=(0.8, 0.18, 0.03), emit_k=0.12),
    "firebrick_glow": dict(tex="rust", tint=(1.0, 0.55, 0.3), scale=0.3, emit=(0.9, 0.22, 0.03), emit_k=0.12),
    "coal_dull": dict(tex="coal_matte", scale=0.25),
    "embers": dict(tex="coal", scale=0.2, emit=(1.0, 0.2, 0.02), emit_k=0.3),
    "embers_hot": dict(tex="coal", scale=0.2, emit=(1.0, 0.42, 0.06), emit_k=0.85),
})

def half_disc(name, r, yc, xa, xb, key, segs=64):
    """The upper half of a disc of radius r centred at height yc, between x = xa and xb (Godot)."""
    bm = bmesh.new()
    prof = [(math.cos(math.pi * i / segs) * r, yc + math.sin(math.pi * i / segs) * r) for i in range(segs + 1)]
    fa = [bm.verts.new(G(xa, y, z)) for z, y in prof]
    fb = [bm.verts.new(G(xb, y, z)) for z, y in prof]
    bm.faces.new(fa)
    bm.faces.new(fb[::-1])
    for i in range(segs):
        bm.faces.new((fa[i], fa[i + 1], fb[i + 1], fb[i]))
    bm.faces.new((fa[segs], fa[0], fb[0], fb[segs]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, key, "x", hdlib._rng)
    return hdlib._new_obj(name, bm, key, 0.0, smooth=False)


def firebox_inside(fy, hz, hy):
    """What shows through the open firehole: the firebox (back at x = -0.16), its firebrick walls
    glowing, the brick arch above and the fire bed, banked up toward the back of the box."""
    x0, x1 = -0.16, -0.56                     # the firebox casing's end cap stands at -0.62
    zw, ytop, yb = 0.62, fy + 0.45, fy - 0.42
    xc = (x0 + x1) / 2
    L = x0 - x1
    for zs in (-1, 1):
        box("FireboxSide", (L, ytop - yb, 0.04), (xc, (ytop + yb) / 2, zs * zw), "firebrick_hot", 0.0, 1)
    box("FireboxTop", (L, 0.04, 2 * zw), (xc, ytop, 0), "firebrick_hot", 0.0, 1)
    box("FireboxBack", (0.04, ytop - yb, 2 * zw), (x1, (ytop + yb) / 2, 0), "firebrick_glow", 0.0, 1)
    box("BrickArch", (0.26, 0.05, 2 * zw), (x1 + 0.14, fy + 0.3, 0), "firebrick_hot", 0.0, 1, rot=(0, 0, -0.35))
    # Fire bed: a mound, highest under the door, falling away to the front of the box.
    seed(640)
    rng = hdlib._rng
    nx, nz = 14, 12
    bm = bmesh.new()
    rows = []
    for i in range(nx + 1):
        x = x0 - 0.01 - (L - 0.05) * i / nx
        row = []
        for j in range(nz + 1):
            z = -zw + 0.02 + (2 * zw - 0.04) * j / nz
            u = i / nx
            y = fy - hy - 0.05 + 0.24 * u ** 1.3 - 0.06 * (z / zw) ** 2 + (rng.random() - 0.5) * 0.03
            row.append(bm.verts.new(G(x, y, z)))
        rows.append(row)
    for i in range(nx):
        for j in range(nz):
            bm.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, "embers", "x", rng)
    o = hdlib._new_obj("FireBed", bm, "embers", 0.0, smooth=True, angle=60.0)
    for f in o.data.polygons:
        if f.normal.z < 0:
            f.flip()
    # Lumps on the bed: incandescent, and some fresh (black) coal just fired on top.
    for k in range(70):
        u = rng.random() ** 0.7
        z = (rng.random() * 2 - 1) * (zw - 0.08)
        x = x0 - 0.04 - (L - 0.12) * u
        y = fy - hy - 0.05 + 0.24 * u ** 1.3 - 0.06 * (z / zw) ** 2
        s = 0.02 + rng.random() * 0.028
        coal_lump((x, y + s * 0.3, z), s, 300 + k, "coal" if k % 3 == 0 else ("embers_hot" if k % 2 else "embers"), 10, 5)


@asset
def coal_hole():
    """The tender's shovelling hole: a steel hood out of the tender front (origin on the front face,
    cab toward -X, centre of the hole at z = 0), a coal board in its guides, the shovelling plate
    at its sill, and the bunker's coal sliding down through it and spilling onto the plate."""
    seed(74)
    rng = hdlib._rng
    D, hw, y0, y1 = 0.24, 0.29, 0.7, 1.25
    for zs in (-1, 1):
        box("HoodSide", (D, y1 - y0, 0.012), (-D / 2, (y0 + y1) / 2, zs * hw), "loco_green", 0.003, grain="y")
        box("Guide", (0.03, y1 - y0 - 0.02, 0.022), (-D + 0.016, (y0 + y1) / 2, zs * (hw - 0.017)), "paint_black", 0.003, grain="y")
        box("Angle", (0.012, y1 - y0 + 0.02, 0.04), (-D - 0.004, (y0 + y1) / 2, zs * (hw + 0.012)), "paint_black", 0.002, grain="y")
    box("HoodTop", (D + 0.02, 0.012, 2 * hw + 0.03), (-D / 2 - 0.01, y1, 0), "loco_green", 0.003)
    box("TopAngle", (0.04, 0.012, 2 * hw + 0.06), (-D - 0.01, y1 - 0.02, 0), "paint_black", 0.002, rot=(0, 0, 1.2))
    box("Soot", (0.006, y1 - y0, 2 * hw - 0.01), (-0.004, (y0 + y1) / 2, 0), "coal_dull", 0.0)
    box("CoalBoard", (0.022, 0.12, 2 * hw - 0.03), (-D + 0.016, y0 + 0.075, 0), "wood_dark", 0.004, grain="z")
    box("ShovellingPlate", (0.38, 0.02, 2 * hw + 0.04), (-0.19, y0 - 0.01, 0), "steel", 0.004)
    box("PlateLip", (0.02, 0.05, 2 * hw + 0.04), (-0.37, y0 - 0.035, 0), "steel", 0.003)
    for zs in (-1, 1):
        tube("PlateStay", [(-0.33, y0 - 0.02, zs * (hw - 0.02)), (-0.02, y0 - 0.3, zs * (hw - 0.02))], 0.012, "paint_black", 8)
    # Coal: a surface rising from the plate's front to the top of the hole at the back, its
    # sides slumped, then loose lumps over it.
    L = 0.36
    def height(x, z):
        t = min(max((x + L) / L, 0.0), 1.0)
        w = hw - 0.02 if t > 0.35 else 0.1 + (hw - 0.12) * t / 0.35
        top = y0 + 0.012 + 0.49 * t ** 1.7
        e = min(abs(z) / w, 1.0)
        return top - (top - y0 - 0.012) * 0.85 * e ** 3, w
    nx, nz = 18, 14
    bm = bmesh.new()
    rows = []
    for i in range(nx + 1):
        x = -L + (L - 0.012) * i / nx
        _, w = height(x, 0)
        row = []
        for j in range(nz + 1):
            z = -w + 2 * w * j / nz
            y, _ = height(x, z)
            y += (rng.random() - 0.5) * 0.02
            row.append(bm.verts.new(G(x, y, z)))
        rows.append(row)
    for i in range(nx):
        for j in range(nz):
            bm.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, "coal_dull", "x", rng)
    o = hdlib._new_obj("CoalHeap", bm, "coal_dull", 0.0, smooth=False)
    for f in o.data.polygons:
        if f.normal.z < 0:
            f.flip()
    for k in range(60):
        x = -L + 0.02 + (L - 0.04) * rng.random() ** 0.8
        _, w = height(x, 0)
        z = (rng.random() * 2 - 1) * w * 0.9
        y, _ = height(x, z)
        sz = 0.018 + rng.random() * 0.035
        coal_lump((x, y + sz * 0.25, z), sz, 400 + k, "coal_dull", 10, 5)


@asset
def coal_lumps():
    """Spilt coal on the footplate; origin at locomotive (0, 0, 0) (lumps at their cab positions)."""
    for i in range(14):
        cx = -8.85 - ((i * 0.61) % 1.0) * 0.5
        cz = 0.55 + ((i * 0.37) % 1.0) * 0.6
        s = 0.045 + 0.04 * ((i * 0.43) % 1.0)
        coal_lump((cx, s * 0.45, cz), s, i, "coal_dull")


@asset
def oil_can():
    import_ph("small_oil_can_01", (0.2, 0.3, 0.2), origin="bottom", yaw=0.0)


@asset
def sanding_lever():
    """Sanding lever on the driver's side wall; origin at (-10.2, 0, -CAB_HALF_W), wall at z = 0, +Z into the cab."""
    seed(70)
    extrude("Quadrant", [(-0.03, 0.55), (0.03, 0.55), (0.16, 1.2), (0.12, 1.24)], 0.012, "paint_black", (0, 0, 0.012), bevel=0.003)
    for k in range(5):
        box("Notch", (0.012, 0.012, 0.014), (0.06 + k * 0.022, 0.86 + k * 0.08, 0.02), "steel_dark", 0.001)
    cyl("Pivot", 0.022, 0.04, (0, 0.6, 0.03), "steel", axis=(0, 0, 1), segs=24)
    tube("Lever", [(0, 0.6, 0.04), (0.1, 1.25, 0.1)], 0.014, "steel", 12)
    sphere("Grip", 0.024, (0.1, 1.25, 0.1), "bakelite", (1, 1.4, 1))


@asset
def handbrake():
    """Tender handbrake column; origin at its foot, wheel on top (horizontal)."""
    seed(71)
    lathe("Column", [(0, 0), (0.09, 0), (0.09, 0.02), (0.05, 0.05), (0.035, 0.1), (0.03, 0.9), (0.04, 0.95), (0.04, 0.99), (0, 0.99)],
          (0, 0, 0), "paint_black", segs=32)
    box("Gearbox", (0.12, 0.12, 0.12), (0, 0.35, 0), "paint_black", 0.012)
    handwheel("Wheel", 0.145, (0, 1.02, 0), (0, 1, 0), "paint_black", 6, rim=0.016, hub=0.03)
    tube("Knob", [(0.145, 1.02, 0), (0.145, 1.1, 0)], 0.014, "handle", 12)


@asset
def water_valve():
    """Tender water feed valve: a flanged outlet from the tank (origin, the tender front, cab
    toward -X), a globe valve body, its spindle and red handwheel facing the crew, and the feed
    pipe dropping from the valve through the footplate (to the injector hose)."""
    seed(72)
    lathe("Flange", [(0, 0), (0.07, 0), (0.07, 0.016), (0, 0.016)], (0, 0, 0), "paint_black", axis=(-1, 0, 0), segs=6)
    for k in range(4):
        t = math.tau * k / 4 + math.pi / 4
        screw("FlangeBolt", -0.016, math.sin(t) * 0.05, math.cos(t) * 0.05, 0.008, axis=(-1, 0, 0), key="steel_dark")
    tube("Outlet", [(-0.016, 0, 0), (-0.09, 0, 0)], 0.025, "copper", 16)
    sphere("Body", 0.05, (-0.12, 0, 0), "brass", (1.0, 0.9, 0.9), 24, 12)
    lathe("Bonnet", [(0, 0), (0.035, 0), (0.035, 0.03), (0.022, 0.05), (0.018, 0.08), (0, 0.08)], (-0.12, 0.03, 0), "brass", segs=24)
    tube("Spindle", [(-0.12, 0.1, 0), (-0.12, 0.16, 0)], 0.01, "steel", 12)
    handwheel("Wheel", 0.06, (-0.12, 0.165, 0), (0, 1, 0), "paint_red", 5)
    tube("FeedPipe", [(-0.12, -0.04, 0), (-0.12, -0.46, 0)], 0.022, "copper", 16)
    for y in (-0.15, -0.3):
        torus("PipeClip", 0.026, 0.006, (-0.12, y, 0), "steel_dark", segs=16, rsegs=6)


@asset
def buffer():
    """Spring buffer; origin at the headstock face, pointing +X."""
    seed(73)
    lathe("Flange", [(0, 0), (0.15, 0), (0.15, 0.03), (0, 0.03)], (0.0, 0, 0), "paint_black", axis=(1, 0, 0), segs=6)
    lathe("Stock", [(0.1, 0.0), (0.105, 0.03), (0.09, 0.06), (0.09, 0.2), (0.1, 0.21), (0.1, 0.23), (0.075, 0.24)], (0, 0, 0),
          "paint_black", axis=(1, 0, 0), segs=40, cap_bottom=False)
    cyl("Plunger", 0.07, 0.12, (0.29, 0, 0), "steel_dark", axis=(1, 0, 0), segs=40)
    lathe("Head", [(0, 0), (0.17, 0), (0.19, 0.01), (0.19, 0.035), (0.17, 0.045), (0.06, 0.05), (0, 0.05)], (0.32, 0, 0), "steel",
          axis=(1, 0, 0), segs=64)
    for k in range(4):
        t = math.tau * k / 4 + math.pi / 4
        screw("FlangeBolt", 0.03, math.cos(t) * 0.12, math.sin(t) * 0.12, 0.012, axis=(1, 0, 0), key="steel_dark")
