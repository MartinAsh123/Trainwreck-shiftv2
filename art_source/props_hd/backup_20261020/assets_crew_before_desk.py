"""Crew car props (guard's room and Kevin's room). Godot-space coordinates; see hdlib."""
import math
from hdlib import *

A = {}


def asset(fn):
    A[fn.__name__] = fn
    return fn


# ————— shared details —————

def bail_pull(name, x, y, z, w=0.07):
    """Brass bail (drop) handle on a drawer front at z (front face), facing -Z."""
    extrude(name + "Plate", [(-w / 2 - 0.012, -0.012), (w / 2 + 0.012, -0.012), (w / 2 + 0.012, 0.012), (-w / 2 - 0.012, 0.012)],
            0.003, "brass", (x, y + 0.005, z - 0.0015), bevel=0.0012)
    for sx in (-1, 1):
        cyl(name + "Post", 0.005, 0.012, (x + sx * w / 2, y + 0.006, z - 0.006), "brass", axis=(0, 0, 1), segs=16)
    tube(name + "Bail", [(x - w / 2, y + 0.006, z - 0.012), (x - w / 2, y - 0.014, z - 0.016),
                         (x + w / 2, y - 0.014, z - 0.016), (x + w / 2, y + 0.006, z - 0.012)], 0.0035, "brass", 12, bend=0.012)


def knob(name, x, y, z, r=0.013, key="brass"):
    lathe(name, [(0.0, 0.0), (r * 0.55, 0.0), (r * 0.4, r * 0.6), (r * 0.9, r * 1.1), (r, r * 1.6), (r * 0.7, r * 2.1), (0.0, r * 2.2)],
          (x, y, z), key, axis=(0, 0, -1), segs=32)


def escutcheon(name, x, y, z, s=1.0):
    pts = []
    for i in range(14):
        a = math.pi * 0.25 + i / 13 * math.pi * 1.5
        pts.append((math.cos(a) * 0.006 * s, 0.004 * s + math.sin(a) * 0.006 * s))
    pts += [(-0.0025 * s, -0.008 * s), (0.0025 * s, -0.008 * s)]
    extrude(name + "Plate", [(-0.012 * s, -0.016 * s), (0.012 * s, -0.016 * s), (0.012 * s, 0.016 * s), (-0.012 * s, 0.016 * s)],
            0.002, "brass", (x, y, z - 0.001), bevel=0.002)
    extrude(name + "Hole", pts, 0.0012, "bakelite", (x, y, z - 0.0026), bevel=0.0)


def screw(name, x, y, z, r=0.003, axis=(0, 0, -1), key="brass"):
    lathe(name, [(0, 0), (r, 0), (r * 0.95, r * 0.35), (r * 0.6, r * 0.6), (0, r * 0.65)], (x, y, z), key, axis=axis, segs=12)


def raised_panel(name, cx, cy, z, w, h, key, depth=0.012, frame=0.055):
    """Door/drawer panel on a front plane at z (front face) facing -Z: frame + raised field."""
    box(name + "Stile", (frame, h, depth), (cx - w / 2 + frame / 2, cy, z - depth / 2), key, 0.003, grain="y")
    box(name + "Stile", (frame, h, depth), (cx + w / 2 - frame / 2, cy, z - depth / 2), key, 0.003, grain="y")
    box(name + "Rail", (w - frame * 2, frame, depth), (cx, cy + h / 2 - frame / 2, z - depth / 2), key, 0.003)
    box(name + "Rail", (w - frame * 2, frame, depth), (cx, cy - h / 2 + frame / 2, z - depth / 2), key, 0.003)
    box(name + "Field", (w - frame * 2 + 0.004, h - frame * 2 + 0.004, depth * 0.6), (cx, cy, z - depth * 0.3), key, 0.0, grain="y")
    box(name + "Raise", (w - frame * 2 - 0.03, h - frame * 2 - 0.03, depth * 0.55), (cx, cy, z - depth * 0.55), key, 0.012, 4, grain="y")


def turned_leg(name, foot, top, r=0.02, key="wood"):
    a = Vector(foot)
    b = Vector(top)
    L = (b - a).length
    prof = [(0.0, 0.0), (r * 0.7, 0.0), (r * 0.75, 0.01), (r * 0.8, L * 0.15), (r * 1.05, L * 0.55),
            (r * 0.95, L * 0.62), (r * 1.2, L * 0.66), (r * 1.15, L * 0.72), (r * 1.25, L * 0.85), (r * 1.25, L), (0.0, L)]
    lathe(name, prof, tuple(a), key, axis=tuple((b - a).normalized()), segs=24)


# ————— furniture —————

@asset
def writing_desk():
    w, d, h = 1.0, 0.58, 0.76
    seed(11)
    top_t = 0.032
    # Top with a moulded edge and a green leather writing inset.
    box("Top", (w, top_t, d), (0, h - top_t / 2, -d / 2), "wood", 0.008, 4)
    box("TopMould", (w - 0.02, 0.012, d - 0.02), (0, h - top_t - 0.006, -d / 2 + 0.005), "wood_darkstain", 0.004)
    box("Inset", (w - 0.14, 0.003, d - 0.16), (0, h + 0.0005, -d / 2 + 0.01), "leather_green", 0.001)
    for sx in (-1, 1):
        box("InsetLine", (0.004, 0.0035, d - 0.155), (sx * (w - 0.14) / 2, h + 0.0006, -d / 2 + 0.01), "gold", 0.0)
    for sz in (-1, 1):
        box("InsetLine", (w - 0.135, 0.0035, 0.004), (0, h + 0.0006, -d / 2 + 0.01 + sz * (d - 0.16) / 2), "gold", 0.0)
    # Pedestal of three drawers on the right.
    pw = 0.38
    px = w / 2 - pw / 2 - 0.01
    ph = h - top_t - 0.07
    pd = d - 0.035
    box("PedestalPlinth", (pw - 0.02, 0.07, pd - 0.02), (px, 0.035, -pd / 2 - 0.005), "wood_darkstain", 0.004)
    box("Pedestal", (pw, ph, pd), (px, 0.07 + ph / 2, -pd / 2), "wood", 0.004, grain="y")
    for sx in (-1, 1):
        raised_panel("PedSide%d" % sx, 0, 0, 0, pd - 0.02, ph - 0.02, "wood", 0.008, 0.045)
        move_last(6, (px + sx * (pw / 2 + 0.004), 0.07 + ph / 2, -pd / 2), (0, -sx * math.pi / 2, 0))
    dh = (ph - 0.03) / 3
    for i in range(3):
        y = 0.085 + dh * (i + 0.5)
        box("Drawer", (pw - 0.035, dh - 0.012, 0.022), (px, y, -pd - 0.011), "wood", 0.004, 3)
        box("DrawerBead", (pw - 0.06, dh - 0.04, 0.006), (px, y, -pd - 0.024), "wood", 0.003)
        bail_pull("Pull%d" % i, px, y + dh * 0.08, -pd - 0.027)
    # Left legs (square tapered with a collar), side stretcher and modesty panel.
    lx = -w / 2 + 0.045
    for lz in (-0.045, -d + 0.06):
        extrude("Leg", [(-0.021, 0), (0.021, 0), (0.016, h - top_t - 0.002), (-0.016, h - top_t - 0.002)], 0.04, "wood",
                (lx, 0, lz), bevel=0.004, grain="y")
        box("LegCollar", (0.046, 0.012, 0.046), (lx, 0.1, lz), "wood_darkstain", 0.003)
    box("Stretcher", (0.026, 0.04, d - 0.12), (lx, 0.16, -d / 2 - 0.008), "wood", 0.004, grain="z")
    box("Modesty", (w - pw - 0.08, 0.34, 0.018), (-pw / 2 + 0.005, h - top_t - 0.17, -0.03), "wood", 0.004)
    box("Apron", (w - pw - 0.06, 0.09, 0.022), (-pw / 2 + 0.0, h - top_t - 0.045, -d + 0.035), "wood", 0.004)
    box("CentreDrawer", (w - pw - 0.14, 0.07, 0.006), (-pw / 2, h - top_t - 0.045, -d + 0.021), "wood", 0.002)
    knob("CentreKnob", -pw / 2, h - top_t - 0.045, -d + 0.018, 0.012)
    escutcheon("CentreLock", -pw / 2 + 0.07, h - top_t - 0.045, -d + 0.018, 0.8)


@asset
def bentwood_chair():
    """Thonet-style bentwood cafe chair; origin = seat centre on the floor, sitter faces -Z."""
    seed(12)
    sy = 0.46
    # Round seat with a rolled rim and a buttoned leather pad.
    lathe("Seat", [(0, sy - 0.03), (0.2, sy - 0.03), (0.212, sy - 0.022), (0.215, sy - 0.008), (0.205, sy), (0, sy)],
          (0, 0, 0), "wood", segs=64, uv_rot=0.3)
    lathe("Pad", [(0, sy - 0.001), (0.19, sy - 0.001), (0.193, sy + 0.008), (0.17, sy + 0.022), (0.08, sy + 0.03), (0, sy + 0.031)],
          (0, 0, 0), "leather", segs=64)
    sphere("Button", 0.008, (0, sy + 0.031, 0), "leather", (1, 0.5, 1), 16, 8)
    torus("SeatRing", 0.185, 0.011, (0, sy - 0.05, 0), "wood", segs=64, rsegs=12)
    # Four splayed legs, the back two continuing up into the bentwood back loop.
    feet = []
    for i, (sx, sz) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        top = Vector((sx * 0.13, sy - 0.04, sz * 0.13))
        foot = Vector((sx * 0.2, 0.0, sz * 0.21))
        feet.append(foot)
        if sz < 0:
            tube("Leg", [tuple(foot), tuple(top)], 0.015, "wood", 16, radii=[0.0125, 0.016])
            cyl("Ferrule", 0.0128, 0.012, tuple(foot + Vector((0, 0.006, 0))), "steel_dark", segs=16)
    torus("LegRing", 0.168, 0.009, (0, 0.2, 0), "wood", segs=64, rsegs=12)
    for sx in (-1, 1):
        # Back leg: up from the floor, curving back at the seat into the back post.
        tube("BackLeg", [(sx * 0.2, 0.0, 0.21), (sx * 0.15, sy - 0.04, 0.15), (sx * 0.16, sy + 0.1, 0.17),
                         (sx * 0.15, 0.82, 0.24), (sx * 0.1, 0.9, 0.26)], 0.015, "wood", 16, bend=0.06)
        cyl("Ferrule", 0.0128, 0.012, (sx * 0.2, 0.006, 0.21), "steel_dark", segs=16)
    tube("BackTop", [(-0.1, 0.9, 0.26), (0.0, 0.925, 0.27), (0.1, 0.9, 0.26)], 0.015, "wood", 16, bend=0.08)
    # Inner loop of the back.
    tube("BackLoop", [(-0.13, sy + 0.08, 0.17), (-0.12, 0.74, 0.22), (0.0, 0.79, 0.235), (0.12, 0.74, 0.22),
                      (0.13, sy + 0.08, 0.17)], 0.011, "wood", 14, bend=0.07)
    for sx in (-1, 1):
        screw("BackScrew", sx * 0.155, sy + 0.05, 0.16, 0.004, axis=(sx, 0, 0), key="steel_dark")


@asset
def wardrobe():
    w, d, h = 0.8, 0.55, 1.95
    seed(13)
    # Bun feet, plinth, carcass with framed sides, stepped cornice.
    for sx in (-1, 1):
        for sz in (-0.06, -d + 0.07):
            lathe("Foot", [(0, 0), (0.028, 0), (0.035, 0.015), (0.03, 0.035), (0.022, 0.045), (0, 0.045)],
                  (sx * (w / 2 - 0.06), 0, sz), "wood_darkstain", segs=24)
    box("Plinth", (w, 0.09, d - 0.01), (0, 0.045 + 0.04, -d / 2), "wood_darkstain", 0.005)
    box("Carcass", (w - 0.02, h - 0.24, d - 0.04), (0, 0.13 + (h - 0.24) / 2, -d / 2 + 0.005), "wood", 0.004, grain="y")
    for sx in (-1, 1):
        raised_panel("Side%d" % sx, 0, 0, 0, d - 0.08, h - 0.32, "wood", 0.012, 0.06)
        move_last(6, (sx * (w / 2 - 0.004), 0.13 + (h - 0.24) / 2, -d / 2), (0, -sx * math.pi / 2, 0))
    y = h - 0.11
    for k, (dw, dd, hh) in enumerate(((0.0, 0.0, 0.03), (0.02, 0.015, 0.025), (0.045, 0.03, 0.02), (0.06, 0.04, 0.035))):
        box("Cornice", (w + dw, hh, d + dd - 0.02), (0, y + hh / 2, -(d + dd - 0.02) / 2 + 0.0), "wood" if k != 1 else "wood_darkstain", 0.004)
        y += hh
    # Bottom drawer with two bail pulls.
    box("Drawer", (w - 0.06, 0.17, 0.024), (0, 0.22, -d + 0.02 - 0.012), "wood", 0.005)
    box("DrawerBead", (w - 0.1, 0.13, 0.006), (0, 0.22, -d + 0.02 - 0.027), "wood", 0.003)
    for sx in (-1, 1):
        bail_pull("DrawerPull%d" % sx, sx * w * 0.24, 0.23, -d + 0.02 - 0.03, 0.08)
    # Two panelled doors with knobs, a lock and hinges.
    y0 = 0.33
    dh = h - 0.12 - 0.13 - y0 + 0.06
    dwid = w / 2 - 0.03
    for sx in (-1, 1):
        cx = sx * (dwid / 2 + 0.004)
        box("DoorBack", (dwid, dh, 0.012), (cx, y0 + dh / 2, -d + 0.02 - 0.006), "wood", 0.002, grain="y")
        raised_panel("Door%d" % sx, cx, y0 + dh * 0.34, -d + 0.02 - 0.012, dwid, dh * 0.62, "wood", 0.016, 0.065)
        raised_panel("DoorTop%d" % sx, cx, y0 + dh * 0.82, -d + 0.02 - 0.012, dwid, dh * 0.34, "wood", 0.016, 0.065)
        knob("Knob%d" % sx, sx * 0.035, y0 + dh * 0.52, -d + 0.02 - 0.03, 0.014)
        for hy in (y0 + 0.12, y0 + dh - 0.12):
            cyl("Hinge", 0.006, 0.07, (sx * (w / 2 - 0.022), hy, -d + 0.008), "brass", segs=16)
    escutcheon("Lock", 0.035, y0 + dh * 0.45, -d + 0.02 - 0.03)


@asset
def steel_locker():
    w, d, h = 0.76, 0.5, 1.9
    seed(14)
    box("Base", (w - 0.02, 0.06, d - 0.02), (0, 0.03, -d / 2), "iron", 0.004)
    box("Body", (w, h - 0.06, d - 0.01), (0, 0.06 + (h - 0.06) / 2, -d / 2 - 0.005), "paint_green", 0.008, 3, grain="y")
    box("TopLip", (w + 0.01, 0.02, d + 0.005), (0, h - 0.01, -d / 2), "paint_green", 0.006)
    dw = w / 2 - 0.014
    dy0 = 0.1
    dhh = h - 0.18
    for sx in (-1, 1):
        cx = sx * (dw / 2 + 0.005)
        box("Door", (dw, dhh, 0.016), (cx, dy0 + dhh / 2, -d - 0.008), "paint_green", 0.006, 3, grain="y")
        # Swaged stiffening ribs and louvre hoods top and bottom.
        box("Swage", (dw - 0.1, dhh * 0.32, 0.004), (cx, dy0 + dhh * 0.5, -d - 0.018), "paint_green", 0.004)
        for k in range(6):
            for yb in (dy0 + dhh - 0.12, dy0 + 0.22):
                yy = yb - k * 0.026
                box("LouvreSlot", (dw - 0.14, 0.012, 0.002), (cx, yy, -d - 0.0165), "bakelite", 0.0)
                box("LouvreHood", (dw - 0.13, 0.016, 0.012), (cx, yy + 0.004, -d - 0.021), "paint_green", 0.004, rot=(-0.5, 0, 0))
        for hy in (dy0 + 0.15, dy0 + dhh / 2, dy0 + dhh - 0.15):
            cyl("Hinge", 0.008, 0.07, (sx * (w / 2 + 0.002), hy, -d - 0.006), "steel_dark", segs=16)
        # Card frame.
        box("CardFrame", (0.09, 0.05, 0.003), (cx, dy0 + dhh - 0.05, -d - 0.0175), "steel", 0.001)
        box("Card", (0.08, 0.04, 0.001), (cx, dy0 + dhh - 0.05, -d - 0.019), "paper_aged", 0.0)
    # Handle, hasp and padlock on the right-hand door.
    hy = h * 0.52
    tube("Handle", [(0.05, hy - 0.09, -d - 0.016), (0.05, hy - 0.09, -d - 0.045), (0.05, hy + 0.09, -d - 0.045),
                    (0.05, hy + 0.09, -d - 0.016)], 0.009, "steel", 16, bend=0.02)
    extrude("Hasp", [(-0.05, -0.014), (0.05, -0.014), (0.05, 0.014), (-0.05, 0.014)], 0.005, "steel_dark",
            (0.0, hy - 0.16, -d - 0.019), bevel=0.0015)
    cyl("Staple", 0.006, 0.03, (0.0, hy - 0.16, -d - 0.03), "steel_dark", axis=(0, 0, 1), segs=16)
    box("Padlock", (0.05, 0.055, 0.024), (0.0, hy - 0.21, -d - 0.036), "brass", 0.006, 3)
    torus("Shackle", 0.016, 0.0045, (0.0, hy - 0.18, -d - 0.036), "steel", axis=(0, 0, 1), segs=24, rsegs=8, arc=math.pi)
    escutcheon("Keyhole", 0.0, hy - 0.215, -d - 0.0485, 0.6)


@asset
def strongbox():
    w, d, h = 0.5, 0.48, 0.62
    seed(15)
    for sx in (-1, 1):
        for sz in (-0.06, -d + 0.06):
            lathe("Foot", [(0, 0), (0.03, 0), (0.035, 0.02), (0.026, 0.04), (0.03, 0.05), (0, 0.05)],
                  (sx * (w / 2 - 0.06), 0, sz), "iron", segs=24)
    box("Body", (w, h - 0.05, d), (0, 0.05 + (h - 0.05) / 2, -d / 2), "iron_green", 0.014, 4)
    box("Door", (w - 0.07, h - 0.13, 0.035), (0, 0.05 + (h - 0.05) / 2, -d - 0.0175), "iron_green", 0.01, 4)
    cy = 0.05 + (h - 0.05) / 2
    dw, dhh = w - 0.13, h - 0.19
    for sy in (-1, 1):
        box("Pinstripe", (dw, 0.005, 0.0015), (0, cy + sy * dhh / 2, -d - 0.0355), "gold", 0.0)
    for sx in (-1, 1):
        box("Pinstripe", (0.005, dhh, 0.0015), (sx * dw / 2, cy, -d - 0.0355), "gold", 0.0)
        for sy in (-1, 1):
            torus("Corner", 0.012, 0.0022, (sx * (dw / 2 - 0.014), cy + sy * (dhh / 2 - 0.014), -d - 0.0355), "gold",
                  axis=(0, 0, 1), segs=16, rsegs=6)
    # Combination dial with a knurled rim, index mark, lever handle and keyhole.
    lathe("Dial", [(0, 0), (0.055, 0), (0.056, 0.006), (0.05, 0.012), (0.03, 0.016), (0.03, 0.03), (0.022, 0.034), (0, 0.035)],
          (0, cy + 0.1, -d - 0.035), "brass", axis=(0, 0, -1), segs=60)
    for k in range(40):
        a = math.tau * k / 40
        box("Knurl", (0.003, 0.004, 0.009), (math.cos(a) * 0.055, cy + 0.1 + math.sin(a) * 0.055, -d - 0.039), "brass", 0.0,
            rot=(0, 0, a))
    box("Index", (0.004, 0.012, 0.004), (0, cy + 0.1 + 0.068, -d - 0.037), "brass", 0.001)
    lathe("LeverBoss", [(0, 0), (0.026, 0), (0.024, 0.012), (0.016, 0.02), (0, 0.022)], (0, cy - 0.07, -d - 0.035), "brass",
          axis=(0, 0, -1), segs=40)
    tube("Lever", [(0, cy - 0.07, -d - 0.05), (0.11, cy - 0.07, -d - 0.05)], 0.008, "brass", 16)
    sphere("LeverBall", 0.014, (0.115, cy - 0.07, -d - 0.05), "brass")
    escutcheon("Keyhole", -0.13, cy - 0.07, -d - 0.035, 1.2)
    for sy in (-1, 1):
        cyl("Hinge", 0.012, 0.09, (w / 2 - 0.02, cy + sy * 0.17, -d - 0.022), "iron", segs=20)


@asset
def key_cabinet():
    """Open key cabinet; origin = centre of its back on the wall, -Z out of the wall."""
    w, h, d = 0.44, 0.5, 0.075
    seed(16)
    box("Back", (w - 0.02, h - 0.02, 0.012), (0, 0, -0.006), "wood_dark", 0.002, grain="y")
    for sx in (-1, 1):
        box("Side", (0.022, h, d), (sx * (w / 2 - 0.011), 0, -d / 2), "wood", 0.004, grain="y")
    for sy in (-1, 1):
        box("Rail", (w, 0.022, d), (0, sy * (h / 2 - 0.011), -d / 2), "wood", 0.004)
    box("Crown", (w + 0.03, 0.025, d + 0.02), (0, h / 2 + 0.0125, -(d + 0.02) / 2), "wood", 0.005)
    box("CrownBead", (w + 0.015, 0.01, d + 0.01), (0, h / 2 + 0.03, -(d + 0.01) / 2), "wood_darkstain", 0.003)
    rows, cols = 3, 5
    k = 0
    for row in range(rows):
        y = h / 2 - 0.085 - row * (h - 0.12) / rows
        box("HookBar", (w - 0.05, 0.022, 0.012), (0, y, -0.018), "wood", 0.003)
        for c in range(cols):
            x = -w / 2 + 0.065 + c * (w - 0.13) / (cols - 1)
            tube("Hook", [(x, y, -0.024), (x, y, -0.05), (x, y + 0.012, -0.056)], 0.0028, "brass", 10, bend=0.008)
            k += 1
            if (row * 7 + c * 3) % 5 == 4:
                continue                                    # an empty hook
            sw = ((row * 13 + c * 7) % 9 - 4) * 0.035
            n0 = count()
            torus("KeyRing", 0.011, 0.0018, (0, -0.012, 0), "brass", axis=(0, 0, 1), segs=20, rsegs=6)
            torus("Bow", 0.008, 0.0025, (0, -0.03, 0), "brass", axis=(0, 0, 1), segs=20, rsegs=6)
            cyl("Shank", 0.0028, 0.045, (0, -0.06, 0), "brass", segs=12)
            box("Bit", (0.012, 0.009, 0.003), (0.006, -0.077, 0), "brass", 0.0007)
            box("Bit2", (0.006, 0.005, 0.003), (0.012, -0.071, 0), "brass", 0.0005)
            box("Tag", (0.024, 0.034, 0.0015), (-0.018, -0.035, -0.003), "paper_aged", 0.001)
            torus("TagRing", 0.0035, 0.0008, (-0.018, -0.02, -0.003), "steel", axis=(0, 0, 1), segs=12, rsegs=4)
            transform_since(n0, (x, y + 0.008, -0.055), (0, 0.15 * ((c % 2) * 2 - 1), sw))


def clock_case(r, depth, dial, hour, minute, rim_key="wood"):
    """Wall clock: origin on the wall, face toward -Z. Times in hours/minutes."""
    lathe("Case", [(0, 0), (r + 0.02, 0), (r + 0.024, -0.01), (r + 0.022, -depth * 0.7), (r + 0.012, -depth), (r - 0.004, -depth),
                   (r - 0.006, -depth + 0.006), (0, -depth + 0.006)], (0, 0, 0), rim_key, axis=(0, 0, 1), segs=72)
    torus("Bezel", r + 0.002, 0.007, (0, 0, -depth - 0.002), "brass", axis=(0, 0, 1), segs=72, rsegs=12)
    disc("Dial", r, (0, 0, -depth + 0.0055), dial)
    for nm, frac, ln, wd in (("HourHand", (hour % 12 + minute / 60) / 12, r * 0.55, r * 0.07),
                             ("MinuteHand", minute / 60, r * 0.82, r * 0.05)):
        a = math.tau * frac
        # Spade hand pointing up (+Y), turned clockwise as seen from the front.
        poly = [(-wd * 0.25, -ln * 0.18), (wd * 0.25, -ln * 0.18), (wd * 0.3, ln * 0.6), (wd * 0.9, ln * 0.72),
                (0.0, ln), (-wd * 0.9, ln * 0.72), (-wd * 0.3, ln * 0.6)]
        extrude(nm, poly, 0.0015, "black_paint_gloss", (0, 0, -depth + 0.0035 - (0.0018 if nm == "MinuteHand" else 0)),
                (0, 0, a), bevel=0.0004)
    lathe("Boss", [(0, 0), (r * 0.06, 0), (r * 0.05, 0.004), (0, 0.006)], (0, 0, -depth + 0.0012), "brass", axis=(0, 0, -1), segs=24)


@asset
def wall_clock_guard():
    seed(17)
    clock_case(0.13, 0.05, "dial_guard", 4, 50)


@asset
def wall_clock_station():
    seed(18)
    clock_case(0.135, 0.065, "dial_station", 2, 37)


@asset
def rug():
    seed(19)
    w, d = 1.8, 0.95
    box("Body", (w, 0.007, d), (0, 0.0035, 0), "rug", 0.003, 2)
    plane("Face", (w, d), (0, 0.0072, 0), "rug", normal="y")
    for sx in (-1, 1):
        for i in range(70):
            z = -d / 2 + 0.01 + i * (d - 0.02) / 69
            ln = 0.045 + 0.012 * math.sin(i * 2.7)
            x0 = sx * w / 2
            tube("Fringe", [(x0, 0.004, z), (x0 + sx * ln * 0.5, 0.003, z + 0.002 * math.sin(i)), (x0 + sx * ln, 0.002, z + 0.004 * math.sin(i * 1.3))],
                 0.0018, "string", 5, caps=False)


# ————— small items —————

@asset
def guard_cap():
    """Peaked cap: crown axis +Y, visor toward -Z, origin at the crown's centre (as built in Godot)."""
    seed(20)
    lathe("Crown", [(0.0, 0.034), (0.08, 0.036), (0.112, 0.03), (0.118, 0.022), (0.112, 0.008), (0.1, -0.01), (0.096, -0.03)],
          (0, 0, 0), "felt_navy", segs=64, cap_bottom=False)
    lathe("CrownInner", [(0.094, -0.03), (0.09, 0.02), (0.0, 0.026)], (0, 0, 0), "felt_navy", segs=48, cap_bottom=False)
    lathe("Band", [(0.0975, -0.06), (0.0985, -0.058), (0.0985, -0.032), (0.0975, -0.03), (0.094, -0.03), (0.094, -0.06)],
          (0, 0, 0), "leather_black", segs=64, cap_bottom=False, cap_top=False)
    pts = []
    for i in range(17):
        a = math.pi + i / 16 * math.pi
        pts.append((math.cos(a) * 0.095, math.sin(a) * 0.08))
    extrude("Visor", pts, 0.004, "leather_black", (0, -0.062, 0), rot=(math.pi / 2 - 0.35, 0, 0), bevel=0.0015)
    tube("ChinStrap", [(-0.096, -0.04, -0.01), (-0.06, -0.046, -0.085), (0.06, -0.046, -0.085), (0.096, -0.04, -0.01)],
         0.003, "leather_black", 8, bend=0.04)
    for sx in (-1, 1):
        sphere("StrapButton", 0.0055, (sx * 0.097, -0.04, -0.01), "brass", (1, 1, 0.6), 16, 8)
    # Winged-wheel cap badge.
    wing = [(0.0, 0.0), (0.03, 0.012), (0.024, 0.004), (0.033, 0.002), (0.02, -0.004), (0.026, -0.009), (0.0, -0.004)]
    for sx in (-1, 1):
        extrude("BadgeWing", [(sx * x, y) for x, y in wing] if sx > 0 else [(sx * x, y) for x, y in reversed(wing)],
                0.002, "brass", (0, -0.016, -0.1), rot=(0.18, 0, 0), bevel=0.0005)
    torus("BadgeWheel", 0.009, 0.0022, (0, -0.016, -0.1), "brass", axis=(0, math.sin(0.18), -math.cos(0.18)), segs=24, rsegs=6)


@asset
def truncheon():
    seed(21)
    tube("Strap", [(0, 0, 0), (-0.012, -0.03, -0.01), (0, -0.06, -0.012), (0.012, -0.03, -0.01), (0, 0, 0)], 0.003, "leather", 8, bend=0.01)
    prof = [(0, 0)]
    for k in range(13):
        prof.append((0.0165 if k % 2 == 0 else 0.0148, 0.008 * k))
    prof += [(0.016, 0.1), (0.0195, 0.104), (0.019, 0.115), (0.0175, 0.12)]
    prof += [(0.019, 0.13), (0.0205, 0.3), (0.019, 0.36), (0.012, 0.37), (0, 0.371)]
    lathe("Baton", prof, (0, -0.07, -0.012), "wood_dark", axis=(0, -1, -0.05), segs=32)


@asset
def ledger_open():
    """Open occurrence book with a fountain pen; origin = bottom centre, spine along Z."""
    seed(22)
    for sx in (-1, 1):
        box("Cover", (0.205, 0.004, 0.29), (sx * 0.1025, 0.002, 0), "leather_red", 0.0015)
        # Page block, slightly domed toward the spine.
        n0 = count()
        box("Pages", (0.19, 0.012, 0.275), (0, 0.0, 0), "paper_aged", 0.002)
        transform_since(n0, (sx * 0.098, 0.011, 0), (0, 0, -sx * 0.035))
        plane("Page", (0.19, 0.275), (sx * 0.098, 0.0172 + sx * 0.0, 0), "ledger_page", normal="y", rot=(0, 0, -sx * 0.035))
    cyl("Spine", 0.007, 0.29, (0, 0.006, 0), "leather_red", axis=(0, 0, 1), segs=16)
    box("Ribbon", (0.006, 0.0008, 0.16), (0.03, 0.019, 0.08), "paint_red", 0.0)
    lathe("Pen", [(0, 0), (0.0035, 0.004), (0.006, 0.03), (0.0065, 0.09), (0.0068, 0.13), (0.0058, 0.145), (0, 0.15)],
          (0.05, 0.026, 0.02), "bakelite", axis=(1, 0, -0.65), segs=24)
    cyl("PenBand", 0.0067, 0.006, (0.05 + 0.09 * 0.838, 0.026, 0.02 - 0.09 * 0.545), "gold", axis=(1, 0, -0.65), segs=24)


@asset
def handcuffs():
    seed(23)
    for sx in (-1, 1):
        cx = sx * 0.055
        torus("Cuff", 0.033, 0.0045, (cx, 0.006, 0), "steel", segs=40, rsegs=10, arc=math.pi * 1.6)
        box("Housing", (0.03, 0.012, 0.026), (cx - sx * 0.028, 0.008, 0.0), "steel", 0.003)
        cyl("Pivot", 0.005, 0.016, (cx - sx * 0.04, 0.008, 0), "steel_dark", segs=12)
        cyl("Swivel", 0.004, 0.01, (cx - sx * 0.045 , 0.008, 0), "steel", axis=(1, 0, 0), segs=12)
    for k in range(3):
        torus("Link", 0.0055, 0.0016, (-0.01 + k * 0.01, 0.006, 0), "steel", axis=(0, 1 if k % 2 else 0, 1 if k % 2 == 0 else 0), segs=16, rsegs=6)


@asset
def ink_stand():
    seed(24)
    poly = [(-0.085, -0.05), (0.085, -0.05), (0.09, -0.044), (0.09, 0.044), (0.085, 0.05), (-0.085, 0.05), (-0.09, 0.044), (-0.09, -0.044)]
    extrude("Tray", poly, 0.016, "wood", (0, 0.008, 0), rot=(math.pi / 2, 0, 0), bevel=0.004, segs=3)
    box("PenGroove", (0.07, 0.003, 0.016), (0.035, 0.0165, 0.018), "wood_darkstain", 0.002)
    lathe("Well", [(0, 0), (0.028, 0), (0.03, 0.01), (0.028, 0.035), (0.018, 0.045), (0.012, 0.05), (0, 0.05)],
          (-0.042, 0.016, 0), "ink", segs=40)
    lathe("Lid", [(0, 0), (0.016, 0), (0.016, 0.006), (0.012, 0.012), (0.004, 0.016), (0, 0.018)], (-0.042, 0.066, 0), "brass", segs=32)
    sphere("LidFinial", 0.005, (-0.042, 0.087, 0), "brass")
    lathe("DipPen", [(0, 0), (0.002, 0.004), (0.004, 0.02), (0.0045, 0.12), (0.003, 0.13), (0, 0.135)],
          (-0.03, 0.022, 0.018), "wood_dark", axis=(1, 0.02, 0), segs=16)
    cyl("Nib", 0.0018, 0.018, (0.11, 0.022, 0.018), "brass", axis=(1, 0, 0), segs=12, r_top=0.0005)


@asset
def paper_stack():
    seed(25)
    for k in range(5):
        a = (k * 0.37 % 1.0 - 0.5) * 0.12
        box("Sheet", (0.21, 0.0012, 0.297), (((k * 0.53) % 1 - 0.5) * 0.02, 0.0006 + k * 0.0013, 0), "paper_aged" if k < 4 else "paper",
            0.0, rot=(0, a, 0))
    plane("TopPrint", (0.21, 0.297), (0, 0.0072, 0), "ledger_page", normal="y", rot=(0, (4 * 0.37 % 1.0 - 0.5) * 0.12, 0))


@asset
def journal():
    seed(26)
    w, t, d = 0.16, 0.024, 0.22
    box("CoverBottom", (w, 0.003, d), (0, 0.0015, 0), "leather_red", 0.0012)
    box("CoverTop", (w, 0.003, d), (0, t - 0.0015, 0), "leather_red", 0.0012)
    lathe("Spine", [(0, -d / 2), (t / 2, -d / 2), (t / 2, d / 2), (0, d / 2)], (-w / 2, t / 2, 0), "leather_red", axis=(0, 0, 1), segs=24)
    box("Pages", (w - 0.008, t - 0.006, d - 0.008), (0.002, t / 2, 0), "paper_aged", 0.001)
    box("Band", (0.006, t + 0.002, d + 0.002), (w * 0.32, t / 2, 0), "bakelite", 0.001)
    # Pencil alongside.
    hexagon = [(math.cos(i * math.pi / 3) * 0.0038, math.sin(i * math.pi / 3) * 0.0038) for i in range(6)]
    extrude("Pencil", hexagon, 0.16, "paint_red", (w / 2 + 0.012, 0.004, 0), rot=(0, 0, 0), bevel=0.0005)
    cyl("PencilTip", 0.0038, 0.014, (w / 2 + 0.012, 0.004, -0.087), "handle", axis=(0, 0, -1), segs=12, r_top=0.0008)
    cyl("Ferrule", 0.004, 0.008, (w / 2 + 0.012, 0.004, 0.084), "brass", axis=(0, 0, 1), segs=12)
    cyl("Eraser", 0.0036, 0.008, (w / 2 + 0.012, 0.004, 0.092), "rubber", axis=(0, 0, 1), segs=12)


@asset
def pager():
    seed(27)
    box("Body", (0.075, 0.02, 0.05), (0, 0.01, 0), "bakelite", 0.006, 4)
    box("ScreenBezel", (0.052, 0.002, 0.022), (-0.004, 0.0205, -0.007), "steel_dark", 0.001)
    box("Screen", (0.046, 0.0015, 0.016), (-0.004, 0.0212, -0.007), "lcd", 0.0)
    for k in range(3):
        lathe("Button", [(0, 0), (0.0042, 0), (0.004, 0.002), (0.003, 0.003), (0, 0.0032)], (-0.02 + k * 0.016, 0.02, 0.014), "rubber", segs=16)
    box("Clip", (0.05, 0.003, 0.04), (0, -0.0015, 0.0), "steel", 0.001)


@asset
def ticket_punch():
    seed(28)
    for sz in (-1, 1):
        tube("Handle", [(-0.07, 0.008, sz * 0.022), (-0.02, 0.008, sz * 0.012), (0.02, 0.008, sz * 0.006), (0.04, 0.008, 0.0)],
             0.0055, "steel", 12, bend=0.03)
        tube("Grip", [(-0.072, 0.008, sz * 0.023), (-0.035, 0.008, sz * 0.016)], 0.0075, "rubber", 12)
    extrude("Jaw", [(0.035, -0.006), (0.075, -0.004), (0.078, 0.004), (0.035, 0.006)], 0.01, "steel", (0, 0.008, 0),
            rot=(math.pi / 2, 0, 0), bevel=0.0015)
    cyl("Pivot", 0.006, 0.014, (0.035, 0.008, 0), "steel_dark", segs=16)
    cyl("Die", 0.006, 0.012, (0.07, 0.008, 0), "brass", segs=16)
    pts = [(-0.035 + 0.004 * math.sin(i * 1.3), 0.008 + 0.0035 * math.cos(i * 1.3), -0.01 + i * 0.0011) for i in range(19)]
    tube("Spring", pts, 0.0009, "steel", 6)


@asset
def enamel_mug():
    seed(29)
    lathe("Mug", [(0, 0.0), (0.034, 0.0), (0.037, 0.004), (0.04, 0.085), (0.042, 0.088), (0.042, 0.09), (0.038, 0.09),
                  (0.036, 0.086), (0.033, 0.008), (0, 0.008)], (0, 0, 0), "enamel_white", segs=48, cap_top=False)
    torus("Rim", 0.04, 0.0025, (0, 0.089, 0), "enamel_blue", segs=48, rsegs=8)
    cyl("Tea", 0.0355, 0.002, (0, 0.07, 0), "tea", segs=32)
    tube("Handle", [(0.038, 0.075, 0), (0.06, 0.07, 0), (0.064, 0.045, 0), (0.05, 0.022, 0), (0.037, 0.02, 0)], 0.0045, "enamel_white", 12, bend=0.015)


@asset
def bankers_lamp():
    seed(30)
    lathe("Base", [(0, 0), (0.07, 0), (0.072, 0.006), (0.066, 0.016), (0.05, 0.022), (0.03, 0.028), (0.018, 0.04), (0, 0.042)],
          (0, 0, 0), "brass", segs=64)
    cyl("Stem", 0.008, 0.3, (0, 0.19, 0), "brass", segs=20)
    lathe("Knop", [(0, 0), (0.012, 0), (0.016, 0.008), (0.012, 0.016), (0, 0.016)], (0, 0.12, 0), "brass", segs=24)
    tube("Yoke", [(-0.09, 0.33, -0.05), (-0.09, 0.345, -0.05), (0.07, 0.345, -0.05), (0.07, 0.33, -0.05)], 0.004, "brass", 10, bend=0.008)
    tube("StemTop", [(0, 0.34, 0), (0, 0.345, -0.05)], 0.006, "brass", 12, bend=0.01)
    # Green glass shade: a half-cylinder shell along X with brass end caps.
    outer, inner = 0.066, 0.061
    arc = [(math.cos(math.pi * i / 24) * outer, math.sin(math.pi * i / 24) * outer) for i in range(25)]
    arc += [(math.cos(math.pi * i / 24) * inner, math.sin(math.pi * i / 24) * inner) for i in range(24, -1, -1)]
    extrude("Shade", [(x, y) for x, y in arc], 0.26, "shade_green", (-0.01, 0.315, -0.05), rot=(0, math.pi / 2, 0), bevel=0.0)
    half = [(math.cos(math.pi * i / 24) * (outer + 0.002), math.sin(math.pi * i / 24) * (outer + 0.002)) for i in range(25)]
    for sx in (-1, 1):
        extrude("ShadeCap", half, 0.004, "brass", (-0.01 + sx * 0.131, 0.315, -0.05), rot=(0, math.pi / 2, 0), bevel=0.001)
    lathe("Bulb", [(0, 0), (0.008, 0.0), (0.016, 0.02), (0.017, 0.035), (0.01, 0.05), (0, 0.052)], (-0.01, 0.335, -0.05), "bulb",
          axis=(0, -1, 0), segs=24)
    tube("PullChain", [(0.06, 0.315, -0.07), (0.06, 0.22, -0.075)], 0.0012, "brass", 6)
    sphere("PullBead", 0.004, (0.06, 0.216, -0.075), "brass")


MATS["shade_green"] = dict(color=(0.006, 0.06, 0.02), rough=0.06, coat=True)


# ————— Poly Haven models fitted to their slots —————

@asset
def nightstand():
    import_ph("ClassicNightstand_01", (0.42, 0.58, 0.40), origin="back", yaw=math.pi)


@asset
def alarm_clock():
    import_ph("alarm_clock_01", (0.13, 0.17, 0.08), origin="bottom", yaw=math.pi, drop_mats=("Glass",))


@asset
def hand_lamp():
    import_ph("Lantern_01", (0.2, 0.27, 0.2), origin="bottom", yaw=0.0)
