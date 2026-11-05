"""Coach body mouldings per car type (from the layouts exported by export_layouts.gd) and the
coach bogie (frame + separate wheelset so the wheels can turn).

Body space = passenger_car.gd space (floor top y = 0, car centred on x = 0). Bogie space = the
bogie marker's: origin on the rail top between the rails, X across the track, Z along it."""
import json, math, os
from hdlib import *
from assets_crew import screw

A = {}
VIEWS = {}
LAYOUTS = os.path.join(ROOT, "layouts")


def asset(fn):
    A[fn.__name__] = fn
    return fn


BEAD = "coach_green"
MATS["coach_green"] = dict(tex="coach_green", scale=1.2)


def godot_xform(lst):
    """Godot Transform3D (basis columns + origin) -> function mapping local points to car space."""
    bx, by, bz = Vector(lst[0:3]), Vector(lst[3:6]), Vector(lst[6:9])
    o = Vector(lst[9:12])
    return lambda p: tuple(o + bx * p[0] + by * p[1] + bz * p[2])


def rounded_rect_path(w, h, r, seg=6):
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 1), (-w / 2 + r, -h / 2 + r, 2), (w / 2 - r, -h / 2 + r, 3)]
    for cx, cy, k in corners:
        for i in range(seg + 1):
            a = math.pi / 2 * (k + i / seg)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    pts.append(pts[0])
    return pts


def build_mouldings(L):
    seed(110)
    half = L["length"] / 2
    w = L["width"] / 2
    sill = L["window_sill"]
    eave = L["eave_y"]
    tumble = L["tumblehome"]
    t = L["wall_thickness"]

    def wall_z(y):
        if y <= sill:
            return w
        return w - tumble * min(max((y - sill) / max(eave - sill, 0.01), 0.0), 1.0)

    # Window surrounds: a half-round bead round every aperture, in the leaning wall plane.
    for win in L["windows"]:
        f = godot_xform(win["xform"])
        ww, hh = win["size"]
        path = rounded_rect_path(ww + 0.05, hh + 0.05, 0.06)
        tube("WindowBead", [f((x, y, t / 2)) for x, y in path], 0.013, BEAD, 10)
        # Drip moulding over the window.
        tube("DripBead", [f((-ww / 2 - 0.06, hh / 2 + 0.07, t / 2)), f((ww / 2 + 0.06, hh / 2 + 0.07, t / 2))], 0.011, BEAD, 8)

    # Long mouldings on each side: waist (both edges of the stripe), cant rail over the windows.
    dx, dw = L["side_door_x"], L["side_door_width"]
    gaps = [(dx - dw / 2 - 0.06, dx + dw / 2 + 0.06)]
    if L.get("loading_door_x") is not None:
        lx, lw = L["loading_door_x"], L["loading_door_width"]
        gaps.append((lx - lw - 0.15, lx + lw + 0.15))

    def runs(x0, x1):
        out, cur = [], x0
        for g0, g1 in sorted(gaps):
            if g1 < cur or g0 > x1:
                continue
            if g0 > cur:
                out.append((cur, g0))
            cur = max(cur, g1)
        if cur < x1:
            out.append((cur, x1))
        return out

    cant_y = sill + L["window_height"] + 0.13
    for zs in (-1, 1):
        for a, b in runs(-half + 0.08, half - 0.08):
            for y, r, zoff in ((sill - 0.13, 0.012, 0.01), (sill - 0.27, 0.012, 0.01), (cant_y, 0.014, 0.0), (0.05, 0.016, 0.0)):
                z = zs * (wall_z(y) + zoff)
                tube("SideBead", [(a, y, z), (b, y, z)], r, BEAD, 10)
        # Door surround for the boarding door: posts (leaning above the sill) and a header.
        for sx in (-1, 1):
            x = dx + sx * (dw / 2 + 0.045)
            pts = [(x, 0.05, zs * w), (x, sill, zs * w), (x, L["door_height"] + 0.04, zs * wall_z(L["door_height"] + 0.04))]
            tube("DoorPost", pts, 0.016, BEAD, 10)
        hy = L["door_height"] + 0.05
        tube("DoorHeader", [(dx - dw / 2 - 0.06, hy, zs * wall_z(hy)), (dx + dw / 2 + 0.06, hy, zs * wall_z(hy))], 0.018, BEAD, 10)
        # Corner pillars: rounded vertical strips at the four body corners.
        for s in (-1, 1):
            x = s * (half - 0.012)
            pts = [(x, 0.03, zs * (w - 0.012)), (x, sill, zs * (w - 0.012)), (x, eave, zs * (w - tumble - 0.012))]
            tube("CornerPillar", pts, 0.032, BEAD, 16)
        # Roof gutter (rain strip) along the eave, and a drip strip higher on the roof.
        rx = w - tumble
        for k, (zf, rr) in enumerate(((0.985, 0.016), (0.8, 0.009))):
            z = rx * zf
            y = eave + L["roof_rise"] * math.sqrt(max(1 - zf * zf, 0.0)) + 0.004
            tube("RoofStrip", [(-half + 0.06, y, zs * z), (half - 0.06, y, zs * z)], rr, "underframe" if k == 0 else BEAD, 10)

    # End panels: gangway door surround, waist and cant beads across each end.
    ew = L["end_door_width"]
    for s in (-1, 1):
        x = s * (half + 0.004)
        path = [(x, 0.02, -ew / 2 - 0.05), (x, L["door_height"] + 0.05, -ew / 2 - 0.05), (x, L["door_height"] + 0.05, ew / 2 + 0.05), (x, 0.02, ew / 2 + 0.05)]
        tube("EndDoorSurround", path, 0.018, BEAD, 10, bend=0.04)
        for y in (sill - 0.13, cant_y):
            for z0, z1 in ((-w + 0.05, -ew / 2 - 0.09), (ew / 2 + 0.09, w - 0.05)):
                tube("EndBead", [(x, y, z0 * wall_z(y) / w), (x, y, z1 * wall_z(y) / w)], 0.012, BEAD, 8)
        # Roof end drip over the end.
        arc = []
        for i in range(25):
            a = math.pi * i / 24
            arc.append((s * (half + 0.01), eave + L["roof_rise"] * math.sin(a) + 0.01, (w - tumble) * math.cos(a)))
        tube("EndRoofDrip", arc, 0.014, "underframe", 8)


for _ty in ("passenger_car", "sleeper_car", "crew_car", "mail_van"):
    def _mk(ty=_ty):
        build_mouldings(json.load(open(os.path.join(LAYOUTS, ty + ".json"))))
    _mk.__name__ = "body_mouldings_" + _ty
    A[_mk.__name__] = _mk
    VIEWS[_mk.__name__] = (-0.6, 0.35, -1.0)


# ————— coach bogie —————

GAUGE_HALF = 0.7175
WHEEL_R = 0.46
WHEELBASE = 2.5


@asset
def coach_wheelset():
    """Mansell wheels (teak segments in a steel tyre) on an axle; origin at the axle centre, axle along X."""
    seed(120)
    tube("Axle", [(-GAUGE_HALF - 0.12, 0, 0), (GAUGE_HALF + 0.12, 0, 0)], 0.075, "steel_dark", 20)
    for xs in (-1, 1):
        x = xs * GAUGE_HALF
        inward = -xs
        r = WHEEL_R
        prof = [(r - 0.05, -0.07), (r - 0.004, -0.07), (r, -0.064), (r, 0.035), (r + 0.028, 0.05), (r + 0.028, 0.064), (r + 0.012, 0.07), (r - 0.05, 0.07)]
        if inward < 0:
            prof = [(a, -b) for a, b in prof]
        lathe("Tyre", prof, (x, 0, 0), "steel_dark", axis=(1, 0, 0), segs=96, cap_bottom=False, cap_top=False)
        # Teak centre in 16 segments with retaining rings and bolts.
        for k in range(16):
            a0 = math.tau * k / 16 + 0.01
            a1 = math.tau * (k + 1) / 16 - 0.01
            pts = []
            for i in range(5):
                a = a0 + (a1 - a0) * i / 4
                pts.append((math.cos(a) * (r - 0.05), math.sin(a) * (r - 0.05)))
            for i in range(5):
                a = a1 - (a1 - a0) * i / 4
                pts.append((math.cos(a) * 0.14, math.sin(a) * 0.14))
            extrude("Segment", pts, 0.09, "wood_dark", (x, 0, 0), rot=(0, math.pi / 2, 0), bevel=0.006, grain="y")
        for rr in (r - 0.075, 0.16):
            lathe("Ring", [(rr - 0.02, -0.05), (rr + 0.02, -0.05), (rr + 0.02, 0.05), (rr - 0.02, 0.05)], (x, 0, 0), "steel_dark", axis=(1, 0, 0),
                  segs=64, cap_bottom=False, cap_top=False)
            for k in range(16):
                a = math.tau * (k + 0.5) / 16
                for sx in (-1, 1):
                    screw("Bolt", x + sx * 0.05, math.sin(a) * rr, math.cos(a) * rr, 0.012, axis=(sx, 0, 0), key="steel_dark")
        lathe("Boss", [(0, -0.08), (0.14, -0.08), (0.15, -0.05), (0.15, 0.05), (0.14, 0.08), (0, 0.08)], (x, 0, 0), "steel_dark", axis=(1, 0, 0), segs=40)


VIEWS["coach_wheelset"] = (1.0, 0.3, -0.8)


@asset
def coach_bogie():
    """Plate-frame bogie without its wheelsets (they sit at z = +-WHEELBASE/2, y = WHEEL_R)."""
    seed(121)
    fx = GAUGE_HALF + 0.22
    # Side frames: plate with arched lower edge between the horn gaps, flanged top.
    for xs in (-1, 1):
        x = xs * fx
        outline = [(-1.75, 0.82), (1.75, 0.82), (1.75, 0.5), (1.5, 0.42), (1.45, 0.25), (1.05, 0.25), (1.0, 0.45), (0.6, 0.38)]
        outline += [(0.3, 0.34), (0.0, 0.33), (-0.3, 0.34), (-0.6, 0.38), (-1.0, 0.45), (-1.05, 0.25), (-1.45, 0.25), (-1.5, 0.42), (-1.75, 0.5)]
        extrude("SideFrame", [(-z, y) for z, y in outline], 0.016, "underframe", (x, 0, 0), rot=(0, math.pi / 2, 0), bevel=0.004, grain="x")
        box("TopFlange", (0.1, 0.014, 3.5), (x, 0.815, 0), "underframe", 0.003, grain="z")
        for zz in [-1.6 + i * 0.16 for i in range(21)]:
            sphere("Rivet", 0.008, (x + xs * 0.009, 0.79, zz), "underframe", (1, 1, 1), 8, 4)
        for az in (-WHEELBASE / 2, WHEELBASE / 2):
            # Horn guides, axlebox with lid and oil box, leaf spring over it with hangers.
            for k in (-1, 1):
                box("HornGuide", (0.05, 0.4, 0.05), (x + xs * 0.01, 0.5, az + k * 0.17), "steel_dark", 0.005)
            box("Axlebox", (0.16, 0.24, 0.26), (x + xs * 0.03, WHEEL_R, az), "steel_dark", 0.015, 3)
            lathe("AxleboxLid", [(0, 0), (0.09, 0), (0.09, 0.02), (0.06, 0.03), (0, 0.03)], (x + xs * 0.11, WHEEL_R, az), "steel_dark", axis=(xs, 0, 0), segs=24)
            for k in range(6):
                box("SpringLeaf", (0.09, 0.018, 1.0 - k * 0.12), (x + xs * 0.03, 0.62 + k * 0.02, az), "steel_dark", 0.004, grain="z")
            box("SpringBuckle", (0.11, 0.12, 0.1), (x + xs * 0.03, 0.66, az), "steel_dark", 0.008)
            for k in (-1, 1):
                tube("SpringHanger", [(x + xs * 0.03, 0.62, az + k * 0.5), (x + xs * 0.03, 0.76, az + k * 0.56)], 0.014, "steel_dark", 8)
            # Brake block and hanger on the inside of each wheel.
            box("BrakeBlock", (0.08, 0.3, 0.09), (xs * GAUGE_HALF, WHEEL_R, az - math.copysign(WHEEL_R + 0.06, az)), "rust", 0.01)
            tube("BrakeHanger", [(xs * GAUGE_HALF, WHEEL_R, az - math.copysign(WHEEL_R + 0.06, az)), (xs * (GAUGE_HALF + 0.1), 0.78, az - math.copysign(WHEEL_R + 0.12, az))],
                 0.016, "rust", 8)
        # Step on the bogie side.
        box("Step", (0.2, 0.025, 0.4), (x + xs * 0.16, 0.3, 0), "steel_dark", 0.004)
        box("StepBracket", (0.03, 0.5, 0.03), (x + xs * 0.07, 0.55, 0), "underframe", 0.004)
    # Transoms and the bolster riding on coil spring nests.
    for zz in (-0.4, 0.4):
        box("Transom", (2 * fx, 0.22, 0.14), (0, 0.66, zz), "underframe", 0.01, grain="x")
    box("Bolster", (2 * fx - 0.25, 0.16, 0.42), (0, 0.86, 0), "underframe", 0.012, grain="x")
    lathe("CentrePivot", [(0, 0), (0.22, 0), (0.22, 0.05), (0.15, 0.08), (0, 0.08)], (0, 0.93, 0), "steel_dark", segs=40)
    for xs in (-1, 1):
        for zz in (-0.12, 0.12):
            pts = [(xs * (fx - 0.28) + math.cos(i * 0.5) * 0.07, 0.62 + i * 0.006, zz + math.sin(i * 0.5) * 0.07) for i in range(48)]
            tube("CoilSpring", pts, 0.012, "steel_dark", 6)
        box("SideBearer", (0.14, 0.05, 0.2), (xs * (fx - 0.28), 0.95, 0), "steel_dark", 0.006)
    # Brake beams between the blocks and the pull rods to the car.
    for az in (-WHEELBASE / 2, WHEELBASE / 2):
        zz = az - math.copysign(WHEEL_R + 0.06, az)
        tube("BrakeBeam", [(-GAUGE_HALF, WHEEL_R - 0.05, zz), (GAUGE_HALF, WHEEL_R - 0.05, zz)], 0.025, "rust", 10)
    tube("PullRod", [(0.0, WHEEL_R - 0.05, -WHEELBASE / 2 + WHEEL_R + 0.06), (0.0, WHEEL_R - 0.05, WHEELBASE / 2 - WHEEL_R - 0.06)], 0.018, "rust", 8)


VIEWS["coach_bogie"] = (1.0, 0.5, -0.8)
