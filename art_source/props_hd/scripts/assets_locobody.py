"""Locomotive body, tender and running gear (locomotive.gd space: x = 0 at the tender's rear face,
engine toward -X, y = 0 at the cab/corridor floor, rail top at RAIL_Y).

Static assets have their origin at the locomotive origin. Moving parts are built in the local
frames the GDScript animates: wheels about their own centre (axis Z, crankpin at (0.26, -0.2)),
the coupling rod about its centre, the crosshead about its centre, the connecting rod along +Y
(length CONROD_LEN, small end at -Y, big end at +Y) for _place_rod to stretch between its pins.
"""
import math
from hdlib import *
from assets_crew import screw

A = {}
VIEWS = {}


def asset(fn):
    A[fn.__name__] = fn
    return fn


RAIL_Y = -1.25
GAUGE_HALF = 0.7175
T_LEN, T_HALF_W, T_TOP = 8.6, 1.35, 2.15
COR_HALF, COR_H = 0.45, 2.0
CAB_X0, CAB_X1, CAB_HALF_W, CAB_ROOF = -8.6, -11.2, 1.37, 2.18
FIREBOX_X1, BOILER_X1, SMOKEBOX_X1, BEAM_X = -13.0, -19.5, -21.3, -21.85
BOILER_Y, BOILER_R = 1.1, 0.85
PLATE_Y = 0.15                     # running plate top (raised so the valance clears the coupling rods)
DRIVERS = (-14.05, -16.05, -18.05)
CRANK = (0.26, -0.2)
CYL_X, CYL_Y = -20.35, -0.45
XHEAD_X = -18.95
CONROD_LEN = math.hypot(math.hypot(XHEAD_X - (DRIVERS[1] + CRANK[0]), CYL_Y - (RAIL_Y + 0.95 + CRANK[1])), 0.05)


def prism_x(name, poly_zy, x0, x1, key, bevel=0.004, segs=2, y_off=0.0):
    """Profile in the (z, y) plane extruded along X from x0 to x1."""
    poly = [(-z, y) for z, y in poly_zy]
    return extrude(name, poly, abs(x1 - x0), key, ((x0 + x1) / 2, y_off, 0), rot=(0, math.pi / 2, 0), bevel=bevel, segs=segs, grain="y")


def rivet_row(name, a, b, n, r=0.009, key="loco_black", normal=(0, 0, 1)):
    a, b = Vector(a), Vector(b)
    for i in range(n):
        p = a + (b - a) * (i / max(n - 1, 1))
        lathe(name, [(0, 0), (r, 0), (r * 0.8, r * 0.5), (0, r * 0.65)], tuple(p), key, axis=normal, segs=8, cap_bottom=False)


def band_ring(name, x, r, key="loco_black", w=0.06, gold=True):
    lathe(name, [(r, -w / 2), (r + 0.008, -w / 2 + 0.004), (r + 0.008, w / 2 - 0.004), (r, w / 2)], (x, BOILER_Y, 0), key,
          axis=(1, 0, 0), segs=96, cap_bottom=False, cap_top=False)
    if gold:
        for k in (-1, 1):
            lathe(name + "Line", [(r + 0.0005, -0.004), (r + 0.0095, -0.004), (r + 0.0095, 0.004), (r + 0.0005, 0.004)],
                  (x + k * (w / 2 + 0.012), BOILER_Y, 0), "gold", axis=(1, 0, 0), segs=96, cap_bottom=False, cap_top=False)


def stanchion(x, y, z, zs, key="steel"):
    lathe("Stanchion", [(0, 0), (0.016, 0), (0.012, 0.02), (0.008, 0.07), (0.014, 0.085), (0.014, 0.1), (0, 0.1)],
          (x, y, z - zs * 0.1), key, axis=(0, 0, zs), segs=16)


# ————— boiler, firebox, smokebox —————

@asset
def loco_boiler():
    seed(80)
    fx = (CAB_X1 + FIREBOX_X1) / 2
    # Belpaire firebox: straight sides, rounded shoulders, flat top; casing in livery green.
    prof = [(-0.8, 0.27)]
    for i in range(9):
        a = math.pi - i / 8 * math.pi / 2
        prof.append((-0.6 + math.cos(a) * 0.2, 1.87 + math.sin(a) * 0.2))
    for i in range(9):
        a = math.pi / 2 - i / 8 * math.pi / 2
        prof.append((0.6 + math.cos(a) * 0.2, 1.87 + math.sin(a) * 0.2))
    prof.append((0.8, 0.27))
    prism_x("Firebox", prof, FIREBOX_X1, CAB_X1 - 0.02, "loco_green", 0.01, 3)
    prism_x("FireboxFoot", [(-0.82, 0.0), (-0.82, 0.3), (0.82, 0.3), (0.82, 0.0)], FIREBOX_X1 - 0.01, CAB_X1 - 0.01, "loco_black", 0.006)
    for zs in (-1, 1):
        for k in range(5):
            lathe("Washout", [(0, 0), (0.035, 0), (0.035, 0.012), (0.024, 0.02), (0, 0.022)],
                  (FIREBOX_X1 + 0.25 + k * 0.33, 1.95, zs * 0.765), "brass", axis=(zs * 0.7, 0.7, 0), segs=16)
        rivet_row("FireboxRivet", (FIREBOX_X1 + 0.05, 0.36, zs * 0.805), (CAB_X1 - 0.08, 0.36, zs * 0.805), 22, normal=(0, 0, zs))
    # Ross pop safety valves on a brass casing, and the whistle ahead of the cab.
    lathe("ValveCasing", [(0, 0), (0.24, 0), (0.25, 0.02), (0.2, 0.06), (0.16, 0.1), (0, 0.1)], (fx - 0.25, 2.06, 0), "brass", segs=48)
    for zs in (-1, 1):
        lathe("SafetyValve", [(0, 0), (0.07, 0), (0.07, 0.12), (0.085, 0.14), (0.085, 0.2), (0.06, 0.23), (0.03, 0.25), (0, 0.25)],
              (fx - 0.25, 2.14, zs * 0.12), "brass", segs=32)
    lathe("Whistle", [(0, 0), (0.03, 0), (0.025, 0.12), (0.045, 0.14), (0.05, 0.3), (0.04, 0.33), (0.012, 0.35), (0, 0.36)],
          (CAB_X1 - 0.25, 2.06, -0.3), "brass", segs=32)
    # Taper boiler barrel with clothing bands and gold lining.
    lathe("Barrel", [(BOILER_R - 0.02, -3.25), (BOILER_R, 3.25)], ((FIREBOX_X1 + BOILER_X1) / 2, BOILER_Y, 0), "loco_green",
          axis=(1, 0, 0), segs=128, cap_bottom=False, cap_top=False)
    for x in (FIREBOX_X1 - 0.03, -15.2, -17.4, BOILER_X1 + 0.03):
        r = BOILER_R - 0.02 * (FIREBOX_X1 - x) / 6.5 + 0.0
        band_ring("Band", x, r)
    # Dome: a casing seated on the barrel, rounded cap.
    lathe("Dome", [(0.4, -0.25), (0.36, 0.0), (0.33, 0.12), (0.32, 0.22), (0.3, 0.3), (0.24, 0.37), (0.13, 0.41), (0, 0.42)],
          (-16.2, BOILER_Y + BOILER_R - 0.02, 0), "loco_green", segs=72, cap_bottom=False)
    torus("DomeBead", 0.335, 0.008, (-16.2, BOILER_Y + BOILER_R + 0.07, 0), "brass", segs=72, rsegs=8)
    # Clack valves, top lamp iron, boiler handrails on stanchions.
    for zs in (-1, 1):
        lathe("Clack", [(0, 0), (0.05, 0), (0.05, 0.08), (0.035, 0.1), (0, 0.1)], (-18.9, BOILER_Y + 0.62, zs * 0.56), "brass",
              axis=(0, 0.75, zs * 0.66), segs=24)
        z = zs * (BOILER_R + 0.09)
        tube("BoilerHandrail", [(FIREBOX_X1 - 0.2, 1.35, z), (BOILER_X1 - 1.6, 1.35, z), (SMOKEBOX_X1 + 0.05, 1.5, zs * 0.6)],
             0.014, "steel", 12, bend=0.3)
        x = FIREBOX_X1 - 0.3
        while x > BOILER_X1 - 1.4:
            stanchion(x, 1.35, z, zs)
            x -= 1.2
    tube("SmokeboxRail", [(SMOKEBOX_X1 + 0.05, 1.5, -0.6), (SMOKEBOX_X1 - 0.02, 1.85, -0.3), (SMOKEBOX_X1 - 0.02, 1.85, 0.3),
                          (SMOKEBOX_X1 + 0.05, 1.5, 0.6)], 0.014, "steel", 12, bend=0.25)
    # Smokebox (satin black) with rivet rings, saddle, the door with straps and dart handles.
    sx = (BOILER_X1 + SMOKEBOX_X1) / 2
    lathe("Smokebox", [(BOILER_R + 0.05, -0.9), (BOILER_R + 0.05, 0.9)], (sx, BOILER_Y, 0), "loco_black", axis=(1, 0, 0), segs=128,
          cap_bottom=False, cap_top=False)
    lathe("SmokeboxRear", [(BOILER_R - 0.03, 0), (BOILER_R + 0.06, 0), (BOILER_R + 0.06, 0.04), (BOILER_R - 0.03, 0.04)],
          (BOILER_X1 - 0.02, BOILER_Y, 0), "loco_black", axis=(1, 0, 0), segs=128)
    for xr in (BOILER_X1 - 0.06, SMOKEBOX_X1 + 0.06):
        for i in range(48):
            a = math.tau * i / 48
            lathe("SmokeboxRivet", [(0, 0), (0.01, 0), (0.008, 0.005), (0, 0.007)],
                  (xr, BOILER_Y + math.sin(a) * (BOILER_R + 0.05), math.cos(a) * (BOILER_R + 0.05)), "loco_black",
                  axis=(0, math.sin(a), math.cos(a)), segs=8, cap_bottom=False)
    box("Saddle", (BOILER_X1 - SMOKEBOX_X1, 0.75, 1.2), (sx, 0.05, 0), "loco_black", 0.02, 3)
    lathe("FrontPlate", [(0, 0), (BOILER_R + 0.07, 0), (BOILER_R + 0.07, 0.03), (0, 0.03)], (SMOKEBOX_X1 + 0.03, BOILER_Y, 0),
          "loco_black", axis=(-1, 0, 0), segs=128)
    lathe("Door", [(0, 0.0), (0.76, 0.0), (0.8, 0.012), (0.79, 0.03), (0.74, 0.05), (0.55, 0.068), (0.0, 0.072)],
          (SMOKEBOX_X1 + 0.0, BOILER_Y, 0), "loco_black", axis=(-1, 0, 0), segs=128)
    torus("DoorRing", 0.81, 0.02, (SMOKEBOX_X1 + 0.005, BOILER_Y, 0), "steel_dark", axis=(1, 0, 0), segs=96, rsegs=10)
    for y in (BOILER_Y + 0.42, BOILER_Y - 0.42):
        n0 = count()
        box("HingeStrap", (0.012, 0.07, 0.78), (0, 0, 0.3), "steel_dark", 0.004)
        cyl("HingeKnuckle", 0.03, 0.09, (0.0, 0, 0.72), "steel_dark", segs=20)
        transform_since(n0, (SMOKEBOX_X1 - 0.066 + 0.0, y, 0.0), (0, 0, 0))
        cyl("HingePin", 0.03, 0.12, (SMOKEBOX_X1 - 0.03, y, 0.83), "steel_dark", segs=20)
    lathe("DartBoss", [(0, 0), (0.07, 0), (0.06, 0.05), (0.03, 0.08), (0, 0.085)], (SMOKEBOX_X1 - 0.07, BOILER_Y, 0), "steel",
          axis=(-1, 0, 0), segs=32)
    for d in ((0, 1, 0), (0, 0, 1)):
        tube("DartHandle", [(SMOKEBOX_X1 - 0.13, BOILER_Y - d[1] * 0.14, -d[2] * 0.14), (SMOKEBOX_X1 - 0.13, BOILER_Y + d[1] * 0.14, d[2] * 0.14)],
             0.014, "steel", 12)
    # Chimney: a capuchon stack with a flared base saddled on the smokebox.
    lathe("Chimney", [(0.42, -0.2), (0.33, 0.0), (0.27, 0.08), (0.235, 0.15), (0.225, 0.38), (0.24, 0.42), (0.275, 0.45),
                      (0.275, 0.49), (0.24, 0.5), (0.2, 0.5), (0.2, 0.3)], (-20.5, BOILER_Y + BOILER_R - 0.02, 0), "loco_black",
          segs=72, cap_bottom=False, cap_top=True)
    # Lamp irons on the smokebox top.
    box("LampIron", (0.03, 0.12, 0.06), (SMOKEBOX_X1 + 0.05, BOILER_Y + BOILER_R + 0.06, 0), "loco_black", 0.004)


VIEWS["loco_boiler"] = (-1.0, 0.45, -0.9)


# ————— running plate, frames, cylinders, front —————

@asset
def loco_frames():
    seed(81)
    px0, px1 = CAB_X1, BEAM_X
    pl = px0 - px1
    xc = (px0 + px1) / 2
    box("RunningPlate", (pl, 0.025, T_HALF_W * 2), (xc, PLATE_Y - 0.0125, 0), "loco_black", 0.004, 2)
    for zs in (-1, 1):
        z = zs * T_HALF_W
        box("Valance", (pl, 0.07, 0.025), (xc, PLATE_Y - 0.035, z - zs * 0.0125), "loco_green", 0.004)
        box("ValanceLine", (pl - 0.1, 0.008, 0.003), (xc, PLATE_Y - 0.035, z + zs * 0.0015), "gold", 0.0)
        # Splasher over the coupled wheels, edged with brass beading.
        sp_x0, sp_x1 = -18.9, -13.0
        box("Splasher", (sp_x0 - sp_x1 + 0.0, 0.62, 0.22), ((sp_x0 + sp_x1) / 2, PLATE_Y + 0.31, zs * 0.74), "loco_green", 0.012, 3)
        box("SplasherTop", (abs(sp_x0 - sp_x1) + 0.01, 0.02, 0.23), ((sp_x0 + sp_x1) / 2, PLATE_Y + 0.625, zs * 0.74), "brass", 0.006)
        box("SplasherLine", (abs(sp_x0 - sp_x1) - 0.12, 0.008, 0.003), ((sp_x0 + sp_x1) / 2, PLATE_Y + 0.55, zs * 0.851), "gold", 0.0)
        # Plate frames with horn guides, axleboxes and springs at the drivers.
        fx0, fx1 = CAB_X0 - 0.1, BEAM_X + 0.05
        box("Frame", (abs(fx0 - fx1), 1.08, 0.04), ((fx0 + fx1) / 2, -0.41, zs * 0.6), "loco_black", 0.006, grain="x")
        rivet_row("FrameRivet", (fx0 - 0.1, 0.08, zs * 0.621), (fx1 + 0.1, 0.08, zs * 0.621), 70, 0.008, normal=(0, 0, zs))
        for x in DRIVERS + (-12.15,):
            for k in (-1, 1):
                box("HornGuide", (0.05, 0.42, 0.06), (x + k * 0.2, RAIL_Y + 0.95 + 0.02, zs * 0.63), "steel_dark", 0.006)
            box("Axlebox", (0.32, 0.3, 0.14), (x, RAIL_Y + 0.95, zs * 0.64), "steel_dark", 0.01, 3)
            for k in range(7):
                box("SpringLeaf", (0.95 - k * 0.11, 0.02, 0.1), (x, -0.84 - k * 0.022, zs * 0.66), "steel_dark", 0.004)
            box("SpringBuckle", (0.1, 0.18, 0.12), (x, -0.83, zs * 0.66), "steel_dark", 0.006)
        # Brake hangers and blocks behind the drivers.
        for x in DRIVERS:
            tube("BrakeHanger", [(x + 0.98, -0.1, zs * GAUGE_HALF), (x + 0.98, RAIL_Y + 0.95, zs * GAUGE_HALF)], 0.022, "rust", 8)
            box("BrakeBlock", (0.09, 0.42, 0.1), (x + 0.92, RAIL_Y + 0.95, zs * GAUGE_HALF), "rust", 0.012, rot=(0, 0, 0.08))
        tube("BrakeRod", [(DRIVERS[0] + 0.98, RAIL_Y + 0.75, zs * 0.5), (DRIVERS[2] + 0.98, RAIL_Y + 0.75, zs * 0.5)], 0.018, "rust", 8)
        # Sandboxes with fillers on the plate, and sand pipes to the rail.
        box("Sandbox", (0.4, 0.3, 0.25), (DRIVERS[0] - 0.7, PLATE_Y + 0.15, zs * 0.42), "loco_green", 0.02)
        lathe("SandFiller", [(0, 0), (0.05, 0), (0.05, 0.06), (0, 0.06)], (DRIVERS[0] - 0.7, PLATE_Y + 0.3, zs * 0.42), "brass", segs=24)
        tube("SandPipe", [(DRIVERS[0] - 0.7, PLATE_Y - 0.03, zs * 0.75), (DRIVERS[0] - 0.85, RAIL_Y + 0.3, zs * 0.75),
                          (DRIVERS[0] - 0.92, RAIL_Y + 0.06, zs * GAUGE_HALF)], 0.02, "loco_black", 10, bend=0.1)
        # Outside cylinder with cladding bands, covers and bolts, valve chest, drain cocks.
        cz = zs * 1.12
        lathe("Cylinder", [(0.335, -0.46), (0.345, -0.43), (0.345, 0.43), (0.335, 0.46)], (CYL_X, CYL_Y, cz), "loco_green", axis=(1, 0, 0),
              segs=64, cap_bottom=False, cap_top=False)
        for k in (-1, 1):
            band_ring("CylBand", CYL_X + k * 0.3, 0.345, "loco_black", 0.03, False)
            move_last(1, (0, CYL_Y - BOILER_Y, cz), (0, 0, 0))
            lathe("CylCover", [(0, 0), (0.33, 0), (0.335, 0.02), (0.3, 0.035), (0.12, 0.05), (0.08, 0.07), (0, 0.07)],
                  (CYL_X + k * 0.46, CYL_Y, cz), "steel", axis=(k, 0, 0), segs=64)
            for i in range(12):
                a = math.tau * i / 12
                screw("CoverBolt", CYL_X + k * 0.475, CYL_Y + math.sin(a) * 0.3, cz + math.cos(a) * 0.3, 0.011, axis=(k, 0, 0), key="steel_dark")
        box("ValveChest", (0.95, 0.3, 0.34), (CYL_X, CYL_Y + 0.4, cz - zs * 0.02), "loco_green", 0.02, 3)
        for k in (-1, 1):
            box("ChestCover", (0.03, 0.26, 0.3), (CYL_X + k * 0.49, CYL_Y + 0.4, cz - zs * 0.02), "steel", 0.006)
        for k in (-1, 1):
            tube("DrainCock", [(CYL_X + k * 0.35, CYL_Y - 0.33, cz), (CYL_X + k * 0.35, CYL_Y - 0.5, cz), (CYL_X + k * 0.5, CYL_Y - 0.58, cz)],
                 0.012, "brass", 8, bend=0.04)
        # Slide bars and the motion bracket that carries them.
        for k in (-1, 1):
            box("SlideBar", (1.3, 0.035, 0.06), (-19.2, CYL_Y + k * 0.085, cz - zs * 0.02), "steel", 0.006)
        box("MotionBracket", (0.08, 0.5, abs(cz) - 0.6), (-18.48, CYL_Y + 0.05, zs * (0.6 + (abs(cz) - 0.6) / 2)), "loco_black", 0.008)
        # Steps behind the buffer beam and ahead of the cab.
        for x in (BEAM_X + 0.3, CAB_X1 + 0.35):
            box("Step", (0.26, 0.025, 0.2), (x, -0.75, zs * 1.15), "steel_dark", 0.005)
            box("StepHanger", (0.03, 0.75, 0.03), (x - 0.1, -0.38, zs * 1.15), "loco_black", 0.004)
    # Leading bogie: frame, axleboxes, springs and centre pivot.
    box("BogieFrame", (1.7, 0.16, 1.0), (-20.47, -0.75, 0), "loco_black", 0.012)
    for zs in (-1, 1):
        box("BogieSide", (1.75, 0.3, 0.04), (-20.47, -0.85, zs * 0.58), "loco_black", 0.008)
        for x in (-19.95, -21.0):
            box("BogieAxlebox", (0.24, 0.24, 0.12), (x, RAIL_Y + 0.45, zs * 0.62), "steel_dark", 0.01)
        for k in range(5):
            box("BogieSpring", (0.7 - k * 0.1, 0.018, 0.09), (-20.47, -0.98 - k * 0.02, zs * 0.62), "steel_dark", 0.003)
    lathe("BogiePivot", [(0, 0), (0.22, 0), (0.22, 0.08), (0, 0.08)], (-20.47, -0.67, 0), "steel_dark", segs=32)
    for zs in (-1, 1):
        box("TrailingAxlebox", (0.3, 0.3, 0.16), (-12.15, RAIL_Y + 0.55, zs * 1.05), "steel_dark", 0.01)
    tube("Drawbar", [(CAB_X0 + 0.1, -0.55, 0), (CAB_X0 - 0.4, -0.55, 0)], 0.04, "steel_dark", 12)
    # Buffer beam (red, lined), screw coupling, vacuum pipe; the beam rises to the running plate.
    box("BufferBeam", (0.15, 0.72, T_HALF_W * 2), (BEAM_X + 0.075, PLATE_Y - 0.36, 0), "loco_red", 0.012, 3)
    for y in (PLATE_Y - 0.04, PLATE_Y - 0.68):
        box("BeamLine", (0.003, 0.012, T_HALF_W * 2 - 0.1), (BEAM_X - 0.0015, y, 0), "loco_black", 0.0)
    for zs in (-1, 1):
        for y in (-0.2, -0.48):
            for zz in (0.75, 1.0):
                screw("BeamBolt", BEAM_X - 0.001, y, zs * zz, 0.014, axis=(-1, 0, 0), key="steel_dark")
    tube("CouplingHook", [(BEAM_X - 0.02, -0.46, 0), (BEAM_X - 0.2, -0.46, 0), (BEAM_X - 0.28, -0.4, 0), (BEAM_X - 0.25, -0.33, 0)], 0.03, "steel_dark",
         12, bend=0.05)
    for k in range(3):
        torus("CouplingLink", 0.06, 0.014, (BEAM_X - 0.32 - k * 0.1, -0.5 - k * 0.06, 0), "steel_dark", axis=(0, 0, 1), segs=20, rsegs=8)
    tube("VacuumPipe", [(BEAM_X, -0.5, -0.35), (BEAM_X - 0.12, -0.65, -0.38), (BEAM_X - 0.25, -0.92, -0.42)], 0.035, "rubber", 14, bend=0.1)
    lathe("VacuumCoupling", [(0, 0), (0.045, 0), (0.05, 0.05), (0.03, 0.1), (0, 0.1)], (BEAM_X - 0.25, -0.92, -0.42), "brass", axis=(0, -1, 0), segs=20)
    for zs in (-1, 0, 1):
        box("BeamLampIron", (0.04, 0.12, 0.05), (BEAM_X - 0.02, PLATE_Y + 0.02, zs * 0.75), "loco_black", 0.004)


VIEWS["loco_frames"] = (-1.0, 0.25, -1.0)


# ————— cab —————

@asset
def loco_cab():
    seed(82)
    x0, x1 = CAB_X0, CAB_X1
    xc = (x0 + x1) / 2
    ln = x0 - x1
    # Footplate boards with a steel fall plate to the tender.
    for i in range(8):
        z = -CAB_HALF_W + (i + 0.5) * CAB_HALF_W * 2 / 8
        box("FloorBoard", (ln, 0.06, CAB_HALF_W * 2 / 8 - 0.006), (xc, -0.03, z), "pine_dark", 0.003, grain="x")
    box("FallPlate", (0.5, 0.012, COR_HALF * 2 + 0.2), (x0 + 0.1, 0.006, 0), "steel", 0.003)
    w0, wa, wb = -9.75, -9.85, -10.85
    for zs in (-1, 1):
        z = zs * CAB_HALF_W
        box("SideLower", (w0 - x1, 1.25, 0.04), ((w0 + x1) / 2, 0.625, z), "loco_green", 0.008)
        box("SideUpper", (x0 - x1, CAB_ROOF - 1.95, 0.04), (xc, (CAB_ROOF + 1.95) / 2, z), "loco_green", 0.008)
        box("SidePostRear", (w0 - wa if wa < w0 else 0.1, 0.7, 0.04), ((w0 + wa) / 2, 1.6, z), "loco_green", 0.008)
        box("SidePostFront", (wb - x1, 0.7, 0.04), ((wb + x1) / 2, 1.6, z), "loco_green", 0.008)
        box("SideRearUpper", (x0 - w0, CAB_ROOF - 1.55, 0.04), ((x0 + w0) / 2, (CAB_ROOF + 1.55) / 2, z), "loco_green", 0.008)
        # Inner lining on the solid parts only (not over the window or the open cab entrance).
        zl = z - zs * 0.025
        box("SideLining", (w0 - x1, 1.25, 0.01), ((w0 + x1) / 2, 0.625, zl), "paint_cream", 0.0, grain="y")
        box("SideLining", (x0 - x1, CAB_ROOF - 1.95, 0.01), (xc, (CAB_ROOF + 1.95) / 2, zl), "paint_cream", 0.0)
        box("SideLining", (wb - x1, 0.7, 0.01), ((wb + x1) / 2, 1.6, zl), "paint_cream", 0.0, grain="y")
        box("SideLining", (abs(w0 - wa) + 0.0, 0.7, 0.01), ((w0 + wa) / 2, 1.6, zl), "paint_cream", 0.0, grain="y")
        box("SideLining", (x0 - w0, CAB_ROOF - 1.55, 0.01), ((x0 + w0) / 2, (CAB_ROOF + 1.55) / 2, zl), "paint_cream", 0.0, grain="y")
        # Gold lining panel on the cab side and beading round the openings.
        box("LiningH", (w0 - x1 - 0.12, 0.008, 0.003), ((w0 + x1) / 2, 0.08, z + zs * 0.0215), "gold", 0.0)
        box("LiningH", (w0 - x1 - 0.12, 0.008, 0.003), ((w0 + x1) / 2, 1.17, z + zs * 0.0215), "gold", 0.0)
        for xx in (w0 - 0.06, x1 + 0.06):
            box("LiningV", (0.008, 1.09, 0.003), (xx, 0.625, z + zs * 0.0215), "gold", 0.0)
        tube("OpeningBead", [(x0, 0.0, z + zs * 0.02), (x0, 1.55, z + zs * 0.02), (w0, 1.55, z + zs * 0.02), (w0, 1.25, z + zs * 0.02)],
             0.012, "brass", 10, bend=0.06)
        box("WindowGlass", (wa - wb, 0.7, 0.008), ((wa + wb) / 2, 1.6, z), "glass", 0.0)
        for x in (wa, wb):
            box("WindowFrame", (0.035, 0.73, 0.05), (x, 1.6, z), "wood", 0.006, grain="y")
        for y in (1.25, 1.95):
            box("WindowFrame", (wa - wb + 0.035, 0.035, 0.05), ((wa + wb) / 2, y, z), "wood", 0.006)
        box("SlideRail", (abs(x1 - wa) + 0.3, 0.02, 0.03), ((wa + wb) / 2 - 0.15, 1.97, z + zs * 0.03), "brass", 0.004)
        # Half door, hinges and grab handles; steps below.
        box("CabHalfDoor", (x0 - w0 - 0.05, 0.95, 0.035), ((x0 + w0) / 2, 0.5, z), "loco_green", 0.008)
        box("DoorPanelLine", (x0 - w0 - 0.2, 0.008, 0.003), ((x0 + w0) / 2, 0.85, z + zs * 0.019), "gold", 0.0)
        for y in (0.2, 0.8):
            cyl("DoorHinge", 0.015, 0.1, (w0 - 0.02, y, z), "loco_black", segs=16)
        for xx, top in ((x0 + 0.02, 1.6), (w0 + 0.02, 1.5)):
            tube("CabHandrail", [(xx, 0.0, z + zs * 0.05), (xx, top, z + zs * 0.05)], 0.016, "brass", 14)
            for y in (0.05, top - 0.05):
                tube("HandrailBracket", [(xx, y, z), (xx, y, z + zs * 0.05)], 0.01, "brass", 8)
        for k in range(2):
            box("Step", (0.45, 0.03, 0.22), ((x0 + w0) / 2, -0.45 - k * 0.4, z + zs * 0.08), "steel_dark", 0.006)
            for kk in range(5):
                box("StepRib", (0.42, 0.006, 0.01), ((x0 + w0) / 2, -0.43 - k * 0.4, z + zs * 0.08 + (kk - 2) * 0.04), "steel_dark", 0.0)
        for sx in (-1, 1):
            box("StepHanger", (0.04, 0.85, 0.035), ((x0 + w0) / 2 + sx * 0.2, -0.5, z + zs * 0.1), "loco_black", 0.004)
    # Arched roof with rain strips, inner lining and a sliding ventilator.
    rw, rise = CAB_HALF_W + 0.06, 0.28
    arc = [(-rw + i * 2 * rw / 32, CAB_ROOF + rise * (1 - ((-rw + i * 2 * rw / 32) / rw) ** 2)) for i in range(33)]
    outer = arc + [(z, y + 0.03) for z, y in reversed(arc)]
    prism_x("Roof", outer, x1 - 0.15, x0 + 0.15, "loco_black", 0.004, 2)
    inner = [(z * 0.985, y - 0.02) for z, y in arc]
    inner_poly = inner + [(z, y + 0.012) for z, y in reversed(inner)]
    prism_x("RoofLining", inner_poly, x1, x0, "paint_cream", 0.0, 1)
    for zs in (-1, 1):
        tube("RainStrip", [(x1 - 0.1, CAB_ROOF + rise * (1 - 0.8 ** 2) + 0.035, zs * rw * 0.8), (x0 + 0.1, CAB_ROOF + rise * (1 - 0.8 ** 2) + 0.035, zs * rw * 0.8)],
             0.008, "loco_black", 8)
    box("Ventilator", (0.72, 0.05, 0.52), (xc, CAB_ROOF + rise + 0.045, 0), "loco_black", 0.012)
    for zs in (-1, 1):
        box("VentRunner", (0.9, 0.02, 0.03), (xc, CAB_ROOF + rise + 0.03, zs * 0.28), "loco_black", 0.004)
    box("FrontLining", (0.01, CAB_ROOF, CAB_HALF_W * 2 - 0.06), (x1 + 0.006, CAB_ROOF / 2, 0), "paint_cream", 0.0, grain="y")
    # Spectacle rims and glass (the plate itself stays the CSG cut-out in the GDScript).
    for zs in (-1, 1):
        lathe("SpectacleRim", [(0.165, -0.02), (0.205, -0.02), (0.21, 0.0), (0.205, 0.015), (0.165, 0.015)], (x1 + 0.0, 1.72, zs * 1.12),
              "brass", axis=(1, 0, 0), segs=48)
        cyl("SpectacleGlass", 0.17, 0.008, (x1 - 0.02, 1.72, zs * 1.12), "glass", axis=(1, 0, 0), segs=48, bevel=0.0)
        for i in range(8):
            a = math.tau * i / 8
            screw("RimScrew", x1 + 0.016, 1.72 + math.sin(a) * 0.187, zs * 1.12 + math.cos(a) * 0.187, 0.006, axis=(1, 0, 0), key="brass")


VIEWS["loco_cab"] = (0.9, 0.5, -1.0)


# ————— tender —————

@asset
def loco_tender():
    seed(83)
    hw = T_HALF_W
    xc = -T_LEN / 2
    side_w = hw - COR_HALF
    for zs in (-1, 1):
        # Tank sides: rounded top outer edge, flared base.
        prof = [(zs * COR_HALF, -0.25), (zs * hw, -0.25), (zs * hw, T_TOP - 0.1)]
        for i in range(6):
            a = i / 5 * math.pi / 2
            prof.append((zs * (hw - 0.1 + math.cos(a) * 0.1), T_TOP - 0.1 + math.sin(a) * 0.1))
        prof.append((zs * COR_HALF, T_TOP))
        if zs > 0:
            prof = list(reversed(prof))
        prism_x("TankSide", prof, -T_LEN, 0.0, "loco_green", 0.01, 2)
        z = zs * (hw + 0.002)
        for y in (0.05, T_TOP - 0.18):
            box("LiningBlack", (T_LEN - 0.3, 0.05, 0.004), (xc, y, z), "loco_black", 0.0)
            box("LiningGold", (T_LEN - 0.36, 0.01, 0.005), (xc, y + (0.04 if y < 1.0 else -0.04), z), "gold", 0.0)
        for x in (-0.15, -T_LEN + 0.15):
            box("LiningBlack", (0.05, T_TOP - 0.23, 0.004), (x, T_TOP / 2 - 0.065, z), "loco_black", 0.0)
            box("LiningGold", (0.01, T_TOP - 0.31, 0.005), (x + (-0.04 if x > -1.0 else 0.04), T_TOP / 2 - 0.065, z), "gold", 0.0)
        rivet_row("TankRivet", (-0.05, -0.18, zs * (hw + 0.001)), (-T_LEN + 0.05, -0.18, zs * (hw + 0.001)), 60, 0.009, normal=(0, 0, zs))
        for x in (-0.03, -T_LEN + 0.03):
            rivet_row("TankRivet", (x, -0.15, zs * (hw + 0.001)), (x, T_TOP - 0.12, zs * (hw + 0.001)), 16, 0.009, normal=(0, 0, zs))
    box("TankTop", (T_LEN, T_TOP - COR_H, COR_HALF * 2), (xc, (T_TOP + COR_H) / 2, 0), "loco_green", 0.004)
    box("TankFloor", (T_LEN, 0.25, COR_HALF * 2), (xc, -0.125, 0), "loco_black", 0.004)
    # Coal space: flared coal rails, front plate and a heaped load of real lumps.
    cx0, cx1 = -T_LEN + 0.15, -T_LEN + 3.4
    for zs in (-1, 1):
        box("CoalRail", (cx1 - cx0, 0.42, 0.04), ((cx0 + cx1) / 2, T_TOP + 0.2, zs * (hw - 0.03)), "loco_green", 0.006, rot=(zs * -0.25, 0, 0))
        tube("CoalRailTop", [(cx0, T_TOP + 0.41, zs * (hw + 0.02)), (cx1, T_TOP + 0.41, zs * (hw + 0.02))], 0.018, "loco_black", 10)
    box("CoalPlate", (0.04, 0.42, hw * 2), (cx1, T_TOP + 0.2, 0), "loco_green", 0.006)
    heap = [(0, 0)]
    for i in range(140):
        u = (math.sin(i * 12.9898) * 43758.5453) % 1.0
        v = (math.sin(i * 78.233) * 43758.5453) % 1.0
        hx = cx0 + 0.15 + u * (cx1 - cx0 - 0.3)
        hz = -hw + 0.18 + v * (2 * hw - 0.36)
        s = 0.07 + 0.08 * ((i * 0.37) % 1.0)
        hy = T_TOP + 0.02 + 0.32 * (1 - abs(hz) / hw) * (0.6 + 0.4 * math.sin((hx - cx0) / (cx1 - cx0) * math.pi))
        coal = sphere("Coal", s, (hx, hy, hz), "coal", (1.0, 0.65, 0.85), 10, 5)
        c = G(hx, hy, hz)
        for vv in coal.data.vertices:
            d = vv.co - c
            vv.co = c + d * (1.0 + 0.25 * math.sin(d.x * 71 + i) * math.cos(d.y * 53 - i) + 0.12 * math.sin(d.z * 91 + i))
        coal.data.set_sharp_from_angle(angle=math.radians(25))
    box("CoalBed", (cx1 - cx0 - 0.05, 0.12, hw * 2 - 0.1), ((cx0 + cx1) / 2, T_TOP + 0.04, 0), "coal", 0.02)
    # Water filler, tank vents, rear ladder, lamp iron, rear doorway frame.
    lathe("WaterFiller", [(0.28, 0), (0.3, 0.0), (0.3, 0.12), (0.28, 0.12)], (-1.3, T_TOP, 0), "loco_green", segs=48, cap_bottom=False)
    lathe("WaterFillerLid", [(0, 0), (0.31, 0), (0.31, 0.02), (0.25, 0.04), (0, 0.045)], (-1.3, T_TOP + 0.12, 0), "loco_black", segs=48)
    tube("LidHandle", [(-1.45, T_TOP + 0.16, 0), (-1.45, T_TOP + 0.2, 0), (-1.15, T_TOP + 0.2, 0), (-1.15, T_TOP + 0.16, 0)], 0.015, "steel", 10, bend=0.03)
    for zs in (-1, 1):
        lathe("TankVent", [(0, 0), (0.06, 0), (0.05, 0.2), (0.09, 0.22), (0.07, 0.3), (0, 0.32)], (-3.0, T_TOP, zs * 0.9), "loco_black", segs=24)
    for i in range(8):
        tube("LadderRung", [(0.05, 0.1 + i * 0.25, 0.62), (0.05, 0.1 + i * 0.25, 1.02)], 0.012, "steel", 8)
    for zz in (0.62, 1.02):
        tube("LadderRail", [(0.0, -0.05, zz), (0.045, 0.0, zz), (0.045, T_TOP, zz), (0.0, T_TOP + 0.05, zz)], 0.016, "loco_black", 10, bend=0.04)
    box("LampIron", (0.06, 0.12, 0.03), (0.04, T_TOP - 0.42, 0.95), "loco_black", 0.004)
    for zs in (-1, 1):
        box("DoorJamb", (0.05, COR_H, 0.06), (0.025, COR_H / 2, zs * (COR_HALF + 0.03)), "loco_black", 0.006)
    box("DoorHead", (0.05, 0.06, COR_HALF * 2 + 0.12), (0.025, COR_H + 0.03, 0), "loco_black", 0.006)
    # Underframe: solebars, rear beam, axleboxes and leaf springs, brake blocks, steps.
    for zs in (-1, 1):
        box("Solebar", (T_LEN - 0.2, 0.32, 0.1), (xc, -0.42, zs * 1.2), "loco_black", 0.008)
        rivet_row("SolebarRivet", (-0.2, -0.3, zs * 1.251), (-T_LEN + 0.2, -0.3, zs * 1.251), 40, 0.008, normal=(0, 0, zs))
        for ax in (-1.4, -4.3, -7.2):
            box("Axlebox", (0.32, 0.36, 0.18), (ax, RAIL_Y + 0.6, zs * 1.2), "steel_dark", 0.012, 3)
            lathe("AxleboxCover", [(0, 0), (0.1, 0), (0.1, 0.02), (0, 0.025)], (ax, RAIL_Y + 0.6, zs * 1.29), "steel_dark", axis=(0, 0, zs), segs=24)
            for k in range(6):
                box("SpringLeaf", (1.0 - k * 0.12, 0.022, 0.12), (ax, RAIL_Y + 0.83 + k * 0.024, zs * 1.2), "steel_dark", 0.004)
            box("SpringBuckle", (0.1, 0.16, 0.14), (ax, RAIL_Y + 0.88, zs * 1.2), "steel_dark", 0.006)
            for k in (-1, 1):
                tube("SpringHanger", [(ax + k * 0.5, RAIL_Y + 0.83, zs * 1.2), (ax + k * 0.55, -0.55, zs * 1.2)], 0.015, "steel_dark", 8)
            box("BrakeBlock", (0.09, 0.32, 0.1), (ax + 0.64, RAIL_Y + 0.6, zs * GAUGE_HALF), "rust", 0.01)
            tube("BrakeHanger", [(ax + 0.64, RAIL_Y + 0.6, zs * GAUGE_HALF), (ax + 0.6, -0.5, zs * GAUGE_HALF)], 0.02, "rust", 8)
        box("RearStep", (0.3, 0.025, 0.2), (-0.3, -0.75, zs * 1.2), "steel_dark", 0.005)
    box("RearBeam", (0.14, 0.45, hw * 2), (-0.07, -0.42, 0), "loco_red", 0.01)
    tube("CouplingHook", [(0.0, -0.46, 0), (0.2, -0.46, 0), (0.28, -0.4, 0), (0.25, -0.33, 0)], 0.03, "steel_dark", 12, bend=0.05)
    tube("VacuumPipe", [(0.0, -0.6, 0.35), (0.15, -0.72, 0.38), (0.3, -0.85, 0.42)], 0.035, "rubber", 14, bend=0.08)
    # Front of the tender, facing the cab: coal hole with its door, shovelling plate, tool cupboards.
    fx = -T_LEN - 0.003
    # Front plate either side of the corridor doorway into the cab, and over it.
    for zs in (-1, 1):
        box("FrontPlate", (0.02, 1.9, hw - COR_HALF - 0.01), (fx + 0.005, 0.95, zs * (COR_HALF + (hw - COR_HALF) / 2)), "loco_green", 0.004, grain="y")
        box("DoorPost", (0.05, COR_H, 0.06), (fx + 0.02, COR_H / 2, zs * (COR_HALF + 0.03)), "loco_black", 0.006)
    box("FrontPlateHead", (0.02, T_TOP - COR_H + 0.01, COR_HALF * 2 + 0.02), (fx + 0.005, (T_TOP + COR_H) / 2, 0), "loco_green", 0.004)
    box("CoalHole", (0.025, 0.5, 0.55), (fx - 0.005, 0.95, 0.85), "coal", 0.006)
    box("CoalDoorFrame", (0.03, 0.56, 0.61), (fx - 0.002, 0.95, 0.85), "steel_dark", 0.006)
    box("ShovellingPlate", (0.35, 0.03, 0.6), (fx - 0.17, 0.7, 0.85), "steel", 0.006)
    for zz in (-1.05, -0.65):
        box("ToolCupboard", (0.025, 0.6, 0.36), (fx - 0.012, 1.45, zz), "loco_green", 0.006)
        box("CupboardBead", (0.004, 0.52, 0.3), (fx - 0.026, 1.45, zz), "loco_green", 0.004)
        sphere("CupboardKnob", 0.02, (fx - 0.035, 1.45, zz + 0.12), "brass")
    for zs in (-1, 1):
        tube("FrontHandrail", [(fx - 0.04, 0.1, zs * (hw - 0.04)), (fx - 0.04, 1.9, zs * (hw - 0.04))], 0.016, "brass", 12)
        for y in (0.15, 1.85):
            tube("RailBracket", [(fx, y, zs * (hw - 0.04)), (fx - 0.04, y, zs * (hw - 0.04))], 0.01, "brass", 8)
    # The corridor through the tank: cream walls, varnished dado and rail, rivets, ceiling, floor.
    for zs in (-1, 1):
        z = zs * (COR_HALF - 0.005)
        box("CorridorWall", (T_LEN, COR_H, 0.01), (xc, COR_H / 2, z), "paint_cream", 0.0, grain="x")
        box("CorridorDado", (T_LEN, 0.9, 0.012), (xc, 0.45, z - zs * 0.004), "wood", 0.002)
        box("DadoRail", (T_LEN, 0.04, 0.03), (xc, 0.91, z - zs * 0.012), "wood", 0.006)
        rivet_row("CorridorRivet", (-0.12, 1.55, z - zs * 0.006), (-T_LEN + 0.12, 1.55, z - zs * 0.006), 34, 0.007, "paint_cream", normal=(0, 0, -zs))
    box("CorridorCeiling", (T_LEN, 0.01, COR_HALF * 2), (xc, COR_H - 0.005, 0), "paint_cream", 0.0)
    for i in range(6):
        z = -COR_HALF + 0.01 + (i + 0.5) * (COR_HALF * 2 - 0.02) / 6
        box("CorridorBoard", (T_LEN, 0.012, (COR_HALF * 2 - 0.02) / 6 - 0.004), (xc, 0.006, z), "pine_dark", 0.002)
    tube("CorridorHandrail", [(-0.3, 1.0, COR_HALF - 0.05), (-T_LEN + 0.3, 1.0, COR_HALF - 0.05)], 0.014, "brass", 12)
    for x in (-0.4, -2.5, -4.6, -6.7, -8.2):
        tube("HandrailBracket", [(x, 1.0, COR_HALF - 0.01), (x, 1.0, COR_HALF - 0.05)], 0.009, "brass", 8)


VIEWS["loco_tender"] = (1.0, 0.6, -1.0)


# ————— wheels (built about their own centre, axis Z) —————

def wheel(r, spokes, tread_key, centre_key, crank, side):
    """side = -1 for the wheel at -GAUGE_HALF (its flange faces +Z), +1 for the other."""
    inward = -side
    tyre_w = 0.14
    t = 0.07 if r > 0.8 else 0.05
    # Tyre: tread with a coned face and the flange on the inside edge.
    prof = [(r - t, -tyre_w / 2), (r - 0.004, -tyre_w / 2), (r, -tyre_w / 2 + 0.006), (r, tyre_w / 2 - 0.035), (r + 0.03, tyre_w / 2 - 0.02),
            (r + 0.03, tyre_w / 2 - 0.006), (r + 0.015, tyre_w / 2), (r - t, tyre_w / 2)]
    if inward < 0:
        prof = [(a, -b) for a, b in prof]
    lathe("Tyre", prof, (0, 0, 0), tread_key, axis=(0, 0, 1), segs=96, cap_bottom=False, cap_top=False)
    rim_in = r - t - 0.06
    lathe("Rim", [(rim_in, -0.045), (r - t + 0.002, -0.05), (r - t + 0.002, 0.05), (rim_in, 0.045)], (0, 0, 0), centre_key, axis=(0, 0, 1),
          segs=96, cap_bottom=False, cap_top=False)
    lathe("RimInner", [(rim_in, 0.045), (rim_in, -0.045)], (0, 0, 0), centre_key, axis=(0, 0, 1), segs=96, cap_bottom=False, cap_top=False)
    hub = r * 0.2
    lathe("Hub", [(0, -0.08), (hub, -0.08), (hub * 1.05, -0.06), (hub * 1.05, 0.06), (hub, 0.08), (hub * 0.55, 0.1), (0, 0.1)],
          (0, 0, side * 0.0), centre_key, axis=(0, 0, side), segs=48)
    lathe("AxleEnd", [(0, 0), (0.07, 0), (0.07, 0.03), (0.05, 0.05), (0, 0.05)], (0, 0, side * 0.1), "steel", axis=(0, 0, side), segs=24)
    for i in range(spokes):
        a = math.tau * i / spokes
        d = Vector((math.cos(a), math.sin(a), 0))
        # Tapered spoke of oval section, thicker at the hub.
        p0 = d * (hub * 0.95)
        p1 = d * (rim_in + 0.01)
        tube("Spoke", [tuple(p0), tuple(p1)], 0.03 if r > 0.8 else 0.022, centre_key, 10, radii=[r * 0.04 + 0.006, r * 0.025 + 0.004])
    if crank:
        # Balance weight filling the spokes opposite the crank.
        ang = math.atan2(-CRANK[1], -CRANK[0])
        pts = []
        for i in range(13):
            aa = ang - 0.55 + 1.1 * i / 12
            pts.append((math.cos(aa) * (rim_in + 0.005), math.sin(aa) * (rim_in + 0.005)))
        for i in range(13):
            aa = ang + 0.55 - 1.1 * i / 12
            pts.append((math.cos(aa) * (r * 0.42), math.sin(aa) * (r * 0.42)))
        extrude("BalanceWeight", pts, 0.07, centre_key, (0, 0, 0), bevel=0.01, segs=2)
        px, py = CRANK
        lathe("CrankBoss", [(0, 0), (0.1, 0), (0.1, 0.06), (0.085, 0.1), (0, 0.1)], (px, py, 0.0), centre_key, axis=(0, 0, side), segs=40)
        lathe("CrankPin", [(0, 0), (0.048, 0), (0.048, 0.2), (0.058, 0.205), (0.058, 0.23), (0.04, 0.25), (0, 0.255)],
              (px, py, side * 0.1), "steel", axis=(0, 0, side), segs=32)


for _nm, _r, _sp, _crank in (("driver_wheel", 0.95, 18, True), ("bogie_wheel", 0.45, 10, False),
                             ("trailing_wheel", 0.55, 12, False), ("tender_wheel", 0.6, 10, False)):
    for _side, _tag in ((-1, "L"), (1, "R")):
        def _make(r=_r, sp=_sp, cr=_crank, side=_side):
            seed(90)
            wheel(r, sp, "steel_dark", "loco_green", cr, side)
        _make.__name__ = "%s_%s" % (_nm, _tag)
        A[_make.__name__] = _make
        VIEWS[_make.__name__] = (0.6 * _side, 0.3, 0.0) if False else (0.35, 0.25, 1.0 * _side)


# ————— rods —————

@asset
def coupling_rod():
    """Fluted coupling rod, centred, spanning the three drivers (bosses at x = -2, 0, +2)."""
    seed(91)
    ln = DRIVERS[0] - DRIVERS[2] + 0.25
    poly = [(-ln / 2 + 0.07, -0.04), (ln / 2 - 0.07, -0.04), (ln / 2 - 0.07, 0.04), (-ln / 2 + 0.07, 0.04)]
    extrude("RodBody", [(-ln / 2 + 0.05, -0.045), (-0.05, -0.05), (0.05, -0.05), (ln / 2 - 0.05, -0.045),
                        (ln / 2 - 0.05, 0.045), (0.05, 0.05), (-0.05, 0.05), (-ln / 2 + 0.05, 0.045)], 0.045, "steel", (0, 0, 0), bevel=0.008, segs=3)
    for sz in (-1, 1):
        box("Flute", (ln / 2 - 0.22, 0.04, 0.006), (sz * (ln / 4), 0, -0.0215), "steel_dark", 0.002)
        box("Flute", (ln / 2 - 0.22, 0.04, 0.006), (sz * (ln / 4), 0, 0.0215), "steel_dark", 0.002)
    for x in (-2.0, 0.0, 2.0):
        lathe("Boss", [(0.05, -0.035), (0.085, -0.035), (0.09, -0.025), (0.09, 0.025), (0.085, 0.035), (0.05, 0.035)], (x, 0, 0), "steel",
              axis=(0, 0, 1), segs=40)
        lathe("Bush", [(0.046, -0.036), (0.05, -0.036), (0.05, 0.036), (0.046, 0.036)], (x, 0, 0), "brass", axis=(0, 0, 1), segs=24,
              cap_bottom=False, cap_top=False)
        lathe("OilCup", [(0, 0), (0.014, 0), (0.016, 0.02), (0.012, 0.035), (0, 0.04)], (x, 0.085, 0), "brass", segs=16)
    box("KnuckleJoint", (0.08, 0.1, 0.06), (1.0, 0, 0), "steel", 0.012)


@asset
def crosshead():
    seed(92)
    box("Body", (0.22, 0.12, 0.08), (0, 0, 0), "steel", 0.012, 3)
    for k in (-1, 1):
        box("Slipper", (0.26, 0.025, 0.07), (0, k * 0.07, 0), "brass", 0.006)
    lathe("GudgeonPin", [(0, -0.07), (0.03, -0.07), (0.03, 0.07), (0, 0.07)], (0.02, 0, 0), "steel_dark", axis=(0, 0, 1), segs=24)
    lathe("PistonBoss", [(0, 0), (0.04, 0), (0.035, 0.05), (0, 0.05)], (-0.11, 0, 0), "steel", axis=(-1, 0, 0), segs=24)


@asset
def connecting_rod():
    """Along +Y, length CONROD_LEN between pin centres; depth along X, thickness along Z."""
    seed(93)
    L = CONROD_LEN
    poly = [(-0.045, -L / 2 + 0.06), (-0.075, L / 2 - 0.12), (0.075, L / 2 - 0.12), (0.045, -L / 2 + 0.06)]
    extrude("Shank", poly, 0.05, "steel", (0, 0, 0), bevel=0.01, segs=3, grain="y")
    for sz in (-1, 1):
        extrude("Flute", [(-0.03, -L / 2 + 0.15), (-0.05, L / 2 - 0.22), (0.05, L / 2 - 0.22), (0.03, -L / 2 + 0.15)], 0.006,
                "steel_dark", (0, 0, sz * 0.024), bevel=0.002, grain="y")
    # Big end with a strap, cotter and bolts; small end eye.
    box("BigEnd", (0.22, 0.24, 0.07), (0, L / 2, 0), "steel", 0.02, 3)
    box("Strap", (0.24, 0.06, 0.075), (0, L / 2 + 0.1, 0), "steel_dark", 0.01)
    for k in (-1, 1):
        cyl("StrapBolt", 0.012, 0.09, (k * 0.09, L / 2 + 0.06, 0), "steel_dark", axis=(0, 0, 1), segs=12)
    lathe("BigBush", [(0.055, -0.037), (0.065, -0.037), (0.065, 0.037), (0.055, 0.037)], (0, L / 2, 0), "brass", axis=(0, 0, 1), segs=32,
          cap_bottom=False, cap_top=False)
    lathe("SmallEye", [(0.03, -0.03), (0.06, -0.03), (0.065, -0.02), (0.065, 0.02), (0.06, 0.03), (0.03, 0.03)], (0, -L / 2, 0), "steel",
          axis=(0, 0, 1), segs=32)
    lathe("OilBox", [(0, 0), (0.03, 0), (0.03, 0.05), (0.022, 0.065), (0, 0.07)], (0.0, L / 2 - 0.02, 0), "brass", axis=(1, 0, 0), segs=16)


VIEWS.update({"coupling_rod": (0.2, 0.3, 1.0), "crosshead": (0.5, 0.4, 1.0), "connecting_rod": (0.3, 0.2, 1.0)})
