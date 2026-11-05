"""Coach underframe and exterior fittings shared by every car (passenger_car.gd space: floor top at
y = 0, car centred on x = 0, default 16.8 m long, 3.15 m wide, floor 0.2 m thick, bogies 3.5 m in)."""
import math
from hdlib import *
from assets_crew import screw

A = {}
VIEWS = {}


def asset(fn):
    A[fn.__name__] = fn
    return fn


LENGTH, WIDTH, FLOOR_T, BOGIE_INSET = 16.8, 3.15, 0.2, 3.5
HALF = LENGTH / 2
W = WIDTH / 2
BOTTOM = -FLOOR_T
END_DOOR_W = 0.9
SIDE_DOOR_W = 0.8


def rivets(name, a, b, n, r=0.008, key="underframe", normal=(0, 0, 1)):
    a, b = Vector(a), Vector(b)
    for i in range(n):
        p = a + (b - a) * (i / max(n - 1, 1))
        lathe(name, [(0, 0), (r, 0), (r * 0.8, r * 0.5), (0, r * 0.65)], tuple(p), key, axis=normal, segs=8, cap_bottom=False)


@asset
def car_underframe():
    seed(100)
    ln = LENGTH - 0.3
    # Channel solebars (web outside, flanges inward) with rivet rows.
    for zs in (-1, 1):
        zo = zs * (W - 0.1)
        zi = zs * (W - 0.22)
        web = [(zo, BOTTOM - 0.28), (zo, BOTTOM), (zo - zs * 0.014, BOTTOM), (zo - zs * 0.014, BOTTOM - 0.28)]
        top = [(zo, BOTTOM), (zi, BOTTOM), (zi, BOTTOM - 0.016), (zo, BOTTOM - 0.016)]
        bot = [(zo, BOTTOM - 0.264), (zi, BOTTOM - 0.264), (zi, BOTTOM - 0.28), (zo, BOTTOM - 0.28)]
        for nm, pr in (("SolebarWeb", web), ("SolebarTop", top), ("SolebarBottom", bot)):
            poly = [(-z, y) for z, y in pr]
            extrude(nm, poly, ln, "underframe", (0, 0, 0), rot=(0, math.pi / 2, 0), bevel=0.003)
        for y in (BOTTOM - 0.035, BOTTOM - 0.245):
            rivets("SolebarRivet", (-ln / 2 + 0.1, y, zo + zs * 0.001), (ln / 2 - 0.1, y, zo + zs * 0.001), 100, 0.007, normal=(0, 0, zs))
        box("MakersPlate", (0.22, 0.09, 0.006), (2.4, BOTTOM - 0.14, zo + zs * 0.004), "brass", 0.002)
    # Headstocks and cross members, bogie bolsters.
    for s in (-1, 1):
        box("Headstock", (0.16, 0.32, WIDTH - 0.3), (s * (HALF - 0.08), BOTTOM - 0.16, 0), "underframe", 0.01, 3)
        for zz in (-1.15, -0.6, 0.6, 1.15):
            screw("HeadstockBolt", s * (HALF + 0.001), BOTTOM - 0.08, zz, 0.012, axis=(s, 0, 0), key="steel_dark")
        box("Bolster", (0.5, 0.06, WIDTH - 0.45), (s * (HALF - BOGIE_INSET), BOTTOM - 0.05, 0), "underframe", 0.008)
    for x in (-6.7, -3.0, -1.0, 1.0, 3.0, 6.7):
        box("CrossMember", (0.1, 0.18, WIDTH - 0.44), (x, BOTTOM - 0.1, 0), "underframe", 0.006)
    # Truss rods with queen posts and a turnbuckle under each side.
    tx = HALF - BOGIE_INSET - 1.9
    for zs in (-1, 1):
        z = zs * (W - 0.4)
        a, b, c, d = (-tx, BOTTOM - 0.25, z), (-1.4, BOTTOM - 0.62, z), (1.4, BOTTOM - 0.62, z), (tx, BOTTOM - 0.25, z)
        tube("TrussRod", [a, b], 0.017, "underframe", 10)
        tube("TrussRod", [b, (-0.18, BOTTOM - 0.62, z)], 0.017, "underframe", 10)
        tube("TrussRod", [(0.18, BOTTOM - 0.62, z), c], 0.017, "underframe", 10)
        tube("TrussRod", [c, d], 0.017, "underframe", 10)
        lathe("Turnbuckle", [(0.0, -0.2), (0.022, -0.2), (0.03, -0.17), (0.03, 0.17), (0.022, 0.2), (0.0, 0.2)], (0, BOTTOM - 0.62, z),
              "steel_dark", axis=(1, 0, 0), segs=12)
        for qx in (-1.4, 1.4):
            box("QueenPost", (0.06, 0.34, 0.05), (qx, BOTTOM - 0.45, z), "underframe", 0.008)
            box("QueenShoe", (0.12, 0.04, 0.07), (qx, BOTTOM - 0.63, z), "underframe", 0.006)
    # Vacuum brake cylinders with trunnions, the brake shaft and the train/steam pipes.
    for x in (-2.0, 2.0):
        lathe("VacuumCylinder", [(0, 0), (0.27, 0), (0.28, 0.03), (0.28, 0.5), (0.27, 0.53), (0.1, 0.56), (0, 0.56)],
              (x, BOTTOM - 0.82, 0.0), "underframe", segs=48)
        for zs in (-1, 1):
            cyl("Trunnion", 0.05, 0.12, (x, BOTTOM - 0.5, zs * 0.33), "steel_dark", axis=(0, 0, 1), segs=16)
            box("TrunnionBracket", (0.12, 0.3, 0.04), (x, BOTTOM - 0.35, zs * 0.38), "underframe", 0.006)
        tube("PistonLink", [(x, BOTTOM - 0.7, 0), (x + 0.25 * (1 if x > 0 else -1), BOTTOM - 0.74, 0)], 0.02, "steel_dark", 8)
    tube("BrakeShaft", [(-3.0, BOTTOM - 0.74, 0), (3.0, BOTTOM - 0.74, 0)], 0.03, "rust", 10)
    for x in (-3.0, -2.25, 2.25, 3.0):
        box("ShaftBracket", (0.05, 0.55, 0.08), (x, BOTTOM - 0.47, 0), "underframe", 0.006)
    for x in (-3.0, 3.0):
        tube("PullRod", [(x, BOTTOM - 0.74, 0), (x * 1.18, BOTTOM - 0.62, 0)], 0.016, "rust", 8)
    tube("TrainPipe", [(-HALF + 0.05, BOTTOM - 0.4, -0.42), (HALF - 0.05, BOTTOM - 0.4, -0.42)], 0.025, "underframe", 10)
    tube("SteamPipe", [(-HALF + 0.05, BOTTOM - 0.4, 0.42), (HALF - 0.05, BOTTOM - 0.4, 0.42)], 0.04, "canvas_dark", 12)
    for x in (-7.5, -5.5, -2.8, 0.0, 2.8, 5.5, 7.5):
        for zz in (-0.42, 0.42):
            box("PipeHanger", (0.03, 0.22, 0.06), (x, BOTTOM - 0.29, zz), "underframe", 0.004)
    for x in (-2.0, 2.0):
        tube("StandPipe", [(x, BOTTOM - 0.4, -0.42), (x, BOTTOM - 0.4, -0.25), (x, BOTTOM - 0.3, -0.05)], 0.018, "underframe", 8, bend=0.05)
    # Battery boxes: timber boxes in iron straps with lids and handles, cable conduit between them.
    for bx in (-0.9, 0.9):
        for zs in (-1, 1):
            z = zs * 0.85
            box("BatteryBox", (1.0, 0.36, 0.3), (bx, BOTTOM - 0.26, z), "wood_dark", 0.008, grain="x")
            box("BatteryLid", (1.02, 0.03, 0.32), (bx, BOTTOM - 0.07, z), "underframe", 0.006)
            for k in (-0.35, 0.0, 0.35):
                box("Strap", (0.03, 0.37, 0.31), (bx + k, BOTTOM - 0.26, z), "underframe", 0.004)
            tube("Handle", [(bx - 0.12, BOTTOM - 0.24, z + zs * 0.15), (bx - 0.12, BOTTOM - 0.24, z + zs * 0.18), (bx + 0.12, BOTTOM - 0.24, z + zs * 0.18),
                            (bx + 0.12, BOTTOM - 0.24, z + zs * 0.15)], 0.008, "steel_dark", 8, bend=0.015)
    tube("Conduit", [(-1.4, BOTTOM - 0.12, 0.85), (1.4, BOTTOM - 0.12, 0.85)], 0.014, "underframe", 8)
    # Dynamo on its bracket, with a pulley toward the bogie.
    dyn_x = -(HALF - BOGIE_INSET - 2.1)
    lathe("Dynamo", [(0, -0.21), (0.11, -0.21), (0.13, -0.18), (0.13, 0.18), (0.11, 0.21), (0, 0.21)], (dyn_x, BOTTOM - 0.36, W - 0.62),
          "underframe", axis=(1, 0, 0), segs=40)
    for k in range(5):
        torus("DynamoRib", 0.13, 0.008, (dyn_x - 0.12 + k * 0.06, BOTTOM - 0.36, W - 0.62), "underframe", axis=(1, 0, 0), segs=40, rsegs=6)
    box("DynamoBracket", (0.36, 0.1, 0.26), (dyn_x, BOTTOM - 0.24, W - 0.62), "underframe", 0.008)
    lathe("Pulley", [(0.03, -0.04), (0.09, -0.04), (0.08, 0.0), (0.09, 0.04), (0.03, 0.04)], (dyn_x - 0.28, BOTTOM - 0.36, W - 0.62),
          "steel_dark", axis=(1, 0, 0), segs=32)


VIEWS["car_underframe"] = (-0.6, -0.35, -1.0)


@asset
def car_end_gear():
    """Fittings of the +X end (the GDScript turns a copy round for the -X end)."""
    seed(101)
    ex = HALF
    # Screw coupling: hook, links and the screw with its weighted handle.
    tube("Hook", [(ex - 0.05, BOTTOM - 0.16, 0), (ex + 0.18, BOTTOM - 0.16, 0), (ex + 0.27, BOTTOM - 0.1, 0), (ex + 0.24, BOTTOM - 0.04, 0)], 0.028,
         "steel_dark", 12, bend=0.05)
    for k, y in ((0, BOTTOM - 0.22), (1, BOTTOM - 0.3)):
        torus("Link", 0.07, 0.014, (ex + 0.24 + k * 0.08, y, 0), "steel_dark", axis=(0, 0, 1), segs=20, rsegs=8)
    lathe("Screw", [(0, -0.12), (0.022, -0.12), (0.022, 0.12), (0, 0.12)], (ex + 0.3, BOTTOM - 0.36, 0), "steel_dark", axis=(1, 0, 0), segs=12)
    tube("ScrewHandle", [(ex + 0.3, BOTTOM - 0.36, 0), (ex + 0.3, BOTTOM - 0.55, 0.05)], 0.012, "steel_dark", 8)
    sphere("HandleBall", 0.035, (ex + 0.3, BOTTOM - 0.57, 0.055), "steel_dark")
    # Vacuum and steam-heat hoses with couplings, hanging from their stubs.
    for zs, key, r in ((-1, "rubber", 0.028), (1, "rubber", 0.034)):
        z = zs * 0.42
        top = (ex + 0.04, BOTTOM - 0.3, z)
        tube("PipeStub", [(ex - 0.1, BOTTOM - 0.3, z), top], 0.03, "underframe", 10)
        tube("Hose", [top, (ex + 0.14, BOTTOM - 0.38, z + zs * 0.02), (ex + 0.22, BOTTOM - 0.55, z + zs * 0.04), (ex + 0.26, BOTTOM - 0.63, z + zs * 0.05)],
             r, key, 14, bend=0.08)
        for k in range(4):
            torus("HoseClip", r + 0.002, 0.004, (ex + 0.07 + k * 0.05, BOTTOM - 0.33 - k * 0.07, z + zs * 0.01 * k), "steel", axis=(1, -0.6, 0), segs=16, rsegs=4)
        lathe("HoseCoupling", [(0, 0), (0.045, 0), (0.05, 0.04), (0.04, 0.09), (0.055, 0.1), (0.055, 0.12), (0, 0.12)],
              (ex + 0.26, BOTTOM - 0.63, z + zs * 0.05), "brass", axis=(0.3, -1, 0), segs=24)
        box("DummyBracket", (0.03, 0.12, 0.08), (ex + 0.03, BOTTOM - 0.7, z), "underframe", 0.004)
    # Lamp brackets, end grab handles and the step ladder by the gangway door.
    for zs in (-1, 1):
        lz = zs * (W - 0.18)
        for y, zz in ((0.9, lz), (2.1, lz * 0.55)):
            box("LampBracket", (0.1, 0.03, 0.08), (ex + 0.05, y, zz), "underframe", 0.004)
            box("LampBracketBack", (0.012, 0.12, 0.06), (ex + 0.006, y - 0.04, zz), "underframe", 0.003)
        z = zs * (END_DOOR_W / 2 + 0.18)
        tube("EndHandle", [(ex + 0.004, 0.3, z), (ex + 0.05, 0.32, z), (ex + 0.05, 1.78, z), (ex + 0.004, 1.8, z)], 0.014, "brass", 12, bend=0.03)
    lz = -(END_DOOR_W / 2 + 0.45)
    for y in (0.1, 0.45, 0.8, 1.15, 1.5, 1.85):
        tube("LadderRung", [(ex + 0.06, y, lz - 0.2), (ex + 0.06, y, lz + 0.2)], 0.012, "underframe", 8)
    for zz in (lz - 0.2, lz + 0.2):
        tube("LadderRail", [(ex + 0.004, 0.06, zz), (ex + 0.06, 0.1, zz), (ex + 0.06, 1.85, zz), (ex + 0.004, 1.92, zz)], 0.014, "underframe", 10, bend=0.03)


VIEWS["car_end_gear"] = (1.0, 0.3, -0.7)


@asset
def boarding_steps():
    """Footboard and lower step at a boarding door (+Z side; origin at the door's x, car floor level)."""
    seed(102)
    def tread(cx, y, z, w, d):
        box("Tread", (w, 0.045, d), (cx, y, z), "steel_dark", 0.006)
        box("Nosing", (w, 0.05, 0.03), (cx, y + 0.003, z + d / 2 - 0.015), "brass", 0.006)
        for i in range(int((d - 0.05) / 0.035)):
            box("Rib", (w - 0.06, 0.006, 0.012), (cx, y + 0.024, z - d / 2 + 0.03 + i * 0.035), "steel_dark", 0.002)
    tread(0, BOTTOM - 0.13, W + 0.1, SIDE_DOOR_W + 0.4, 0.24)
    tread(0, BOTTOM - 0.46, W + 0.2, SIDE_DOOR_W + 0.1, 0.2)
    for sx in (-1, 1):
        hx = sx * (SIDE_DOOR_W / 2 - 0.02)
        box("Hanger", (0.04, 0.36, 0.03), (hx, BOTTOM - 0.3, W + 0.14), "underframe", 0.005)
        box("FootboardBracket", (0.04, 0.12, 0.3), (sx * (SIDE_DOOR_W / 2 + 0.12), BOTTOM - 0.18, W - 0.02), "underframe", 0.005)
        for y in (BOTTOM - 0.18, BOTTOM - 0.42):
            screw("HangerBolt", hx, y, W + 0.157, 0.008, axis=(0, 0, 1), key="steel_dark")


VIEWS["boarding_steps"] = (0.6, 0.4, 1.0)


@asset
def torpedo_vent():
    """Torpedo roof ventilator; origin on the roof ridge."""
    seed(103)
    lathe("Body", [(0, -0.17), (0.03, -0.165), (0.065, -0.12), (0.075, -0.05), (0.075, 0.08), (0.06, 0.14), (0.03, 0.168), (0, 0.17)],
          (0, 0.12, 0), "underframe", axis=(1, 0, 0), segs=32)
    for k in range(5):
        box("Slot", (0.012, 0.004, 0.09), (-0.06 + k * 0.03, 0.05, 0), "black_paint_gloss", 0.001)
    lathe("Stem", [(0, -0.02), (0.05, -0.02), (0.035, 0.0), (0.032, 0.08), (0, 0.08)], (0, -0.02, 0), "underframe", segs=24)
    for zs in (-1, 1):
        tube("Stay", [(0, 0.0, zs * 0.08), (0, 0.06, zs * 0.06)], 0.006, "underframe", 6)


VIEWS["torpedo_vent"] = (-0.6, 0.5, -1.0)
