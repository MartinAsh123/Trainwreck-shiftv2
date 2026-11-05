"""The booking hall inside the stone country station (tools/blender/make_stations.py builds the
building walk-in: its walls 0.4 m thick with real door and window openings, a plaster ceiling).
This model fills the room: floor, wall finishes, ceiling, the ticket office with its cashier's
room, the waiting room and the security check at the town door.

Frame: the station building's own - origin on the floor at the middle of the main block, x along
the platform, the platform side toward -z, the town side +z. The room inside the walls runs
x -XI..XI, z -ZI..ZI, up to H. Door and window openings (from the building):
    platform doors  x = -3.2, 0.0 (1.3 wide, 2.35 high)   platform windows x = -6.4, 3.2, 6.4
    town door       x = 0.0 (1.5 wide, 2.3 high)          town windows     x = -6.4, 6.4
    end window      x = -XI side, z = 0 (1.0 wide)        windows sill 1.0, head 2.8
The spots for the staff (scripts/world/station_hall.gd places markers there for the cashier and
the guards) are given in CASHIER and GUARDS.
"""
import math
import bmesh
from mathutils import Vector
import hdlib
from hdlib import *

A = {}


def asset(fn):
    A[fn.__name__] = fn
    return fn


hdlib.MATS.update({
    "plaster": dict(tex="plaster_warm", scale=1.8),
    "wainscot": dict(tex="wood_furniture_dark", scale=1.2),
    "floor_checker": dict(tex="floor_checker", scale=2.0),
    "marble": dict(tex="marble", scale=0.8),
    "stove_tile": dict(color=(0.16, 0.3, 0.22), rough=0.15, coat=True),
    "hall_lamp": dict(color=(1.0, 0.95, 0.85), rough=0.2, emit=(1.0, 0.86, 0.62), emit_k=2.5),
    "board_black": dict(color=(0.03, 0.035, 0.04), rough=0.6),
    "board_letter": dict(color=(0.93, 0.92, 0.85), rough=0.6),
    "sign_blue": dict(color=(0.08, 0.16, 0.4), rough=0.3),
    "sign_cream": dict(color=(0.93, 0.9, 0.8), rough=0.4),
    "sign_red_h": dict(color=(0.65, 0.05, 0.04), rough=0.35),
    "floor_yellow": dict(color=(0.85, 0.65, 0.05), rough=0.6),
    "detector_grey": dict(color=(0.55, 0.57, 0.6), rough=0.35),
    "tray_grey": dict(color=(0.3, 0.32, 0.35), rough=0.5),
    "radiator": dict(color=(0.82, 0.8, 0.74), rough=0.4),
    "rope_red": dict(color=(0.45, 0.04, 0.05), rough=0.8),
    "ticket_card": dict(color=(0.75, 0.68, 0.45), rough=0.8),
    "glass_screen": dict(color=(0.8, 0.85, 0.85), rough=0.03, alpha=0.18),
})

# The two buildings the hall is made for (scripts/world/station_hall.gd keeps the same table):
#   stone - the country station of make_stations.py (16 x 9 m, walls 0.4, one storey 4.6 high)
#   town  - the big towns' two-storey building of Buildings.station() (16 x 10 m, the ground floor
#           under the first-floor cornice at 3.54; its own platform doorways are part of this model)
CONFIGS = {
    "stone": dict(XI=7.6, ZI=4.1, H=4.6, FRONT_DOORS=[-3.2, 0.0], BACK_DOOR=0.0, FRONT_WINDOWS=[-6.4, 3.2, 6.4],
                  BACK_WINDOWS=[-6.4, 6.4], WIN_HW=0.5, WIN_Y0=1.0, WIN_Y1=2.8, END_WINDOW=True, PART_X=3.0,
                  TICKET_Z=[-1.7, 0.0, 1.7], OFFICE_DOOR_Z=3.35, DROP=0.9,
                  LAMPS=[(-5.6, 0.0), (-1.6, 0.0), (1.5, -1.3), (1.5, 2.6), (5.3, 0.0)],
                  PALMS=[(-0.95, -0.45), (-2.35, -0.45)], FRONT_BENCH=None, BOARD=("x", -3.6), TIMETABLE_X=-5.0,
                  SCALE_X=-5.3, OWN_DOORS=False),
    "town": dict(XI=7.6, ZI=4.6, H=3.5, FRONT_DOORS=[-2.92, 0.0], BACK_DOOR=0.0, FRONT_WINDOWS=[-5.84, 2.92, 5.84],
                 BACK_WINDOWS=[-5.84, -2.92, 2.92, 5.84], WIN_HW=0.43, WIN_Y0=1.18, WIN_Y1=2.78, END_WINDOW=False, PART_X=4.3,
                 TICKET_Z=[-2.0, 0.0, 2.0], OFFICE_DOOR_Z=3.85, DROP=0.6,
                 LAMPS=[(-5.0, 0.0), (-1.5, -1.6), (-1.5, 1.6), (1.9, 0.0), (6.0, 0.0)],
                 PALMS=[(-1.46, -0.45)], FRONT_BENCH=None, BOARD=("z", 0.0), TIMETABLE_X=-4.4,
                 SCALE_X=-4.4, OWN_DOORS=True),
}


def configure(kind):
    """Set the module's measurements (XI, ZI, H, door and window lists...) for building `kind`."""
    g = globals()
    for k, v in CONFIGS[kind].items():
        g[k] = v


configure("stone")


def _decimate(objs, ratio):
    for o in objs:
        md = o.modifiers.new("Dec", "DECIMATE")
        md.ratio = ratio


def sign(name, text, c, size, w, h, key="sign_blue", ink="sign_cream", face=(0, 0, -1), depth=0.02):
    """An enamel sign facing `face` (a unit axis), its lettering on it."""
    fx, fy, fz = face
    rot = (0, 0, 0)
    if fx > 0.5:
        rot = (0, -math.pi / 2, 0)
    elif fx < -0.5:
        rot = (0, math.pi / 2, 0)
    elif fz > 0.5:
        rot = (0, math.pi, 0)
    p = box(name, (w, h, depth), c, key, 0.004, rot=rot)
    tc = (c[0] + fx * 0.05, c[1], c[2] + fz * 0.05)
    text_on(name + "Text", text, p, tc, size, ink, lift=0.0015, inward=(-fx, 0, -fz), flat=True)
    return p


def wall_strip(along, c, side, a0, a1, gaps, y0, y1, key, depth=0.03, bevel=0.004):
    """A strip on a wall (wainscot, dado rail...) from a0 to a1 along the wall, skipping `gaps`;
    along "x": a wall at z = c whose room side faces `side` (+1: +z); "z": a wall at x = c."""
    a = a0
    for (g0, g1) in sorted(gaps) + [(a1, a1)]:
        if g0 - a > 0.02:
            if along == "x":
                box("Strip", (g0 - a, y1 - y0, depth), ((a + g0) / 2, (y0 + y1) / 2, c + side * depth / 2), key, bevel)
            else:
                box("Strip", (depth, y1 - y0, g0 - a), (c + side * depth / 2, (y0 + y1) / 2, (a + g0) / 2), key, bevel)
        a = max(a, g1)


def bench(x, z, yaw, length=2.2):
    """Station bench: oak slats on cast-iron ends, front toward -Z before turning by yaw."""
    n0 = count()
    for sx in (-1, 1):
        ex = sx * (length / 2 - 0.12)
        tube("BenchEnd", [(ex, 0.0, -0.22), (ex, 0.42, -0.2), (ex, 0.44, 0.18), (ex, 0.9, 0.26)], 0.022, "iron", 8, bend=0.06)
        tube("BenchLeg", [(ex, 0.0, 0.2), (ex, 0.44, 0.15)], 0.022, "iron", 8)
        tube("BenchArm", [(ex, 0.44, -0.22), (ex, 0.65, -0.2), (ex, 0.66, 0.15)], 0.02, "iron", 8, bend=0.05)
    for k in range(5):
        box("Slat", (length, 0.03, 0.075), (0, 0.46, -0.18 + k * 0.085), "wood_dark", 0.006)
    for k in range(3):
        box("BackSlat", (length, 0.08, 0.025), (0, 0.58 + k * 0.11, 0.2 + k * 0.025), "wood_dark", 0.006, rot=(-0.25, 0, 0))
    transform_since(n0, (x, 0, z), (0, yaw, 0))


def pendant(x, z):
    tube("LampRod", [(x, H - 0.01, z), (x, H - DROP, z)], 0.01, "brass", 6)
    lathe("LampCanopy", [(0.0, 0.0), (0.08, 0.0), (0.06, -0.04), (0.0, -0.05)], (x, H - 0.01, z), "brass", segs=16)
    lathe("LampGallery", [(0.0, 0.0), (0.09, 0.0), (0.1, -0.06), (0.06, -0.08)], (x, H - DROP, z), "brass", segs=16, cap_bottom=False)
    sphere("LampGlobe", 0.2, (x, H - DROP - 0.25, z), "hall_lamp", segs=20, rings=10)


def radiator(x, z, side):
    n0 = count()
    for k in range(10):
        box("RadFin", (0.06, 0.6, 0.12), (-0.33 + k * 0.073, 0.45, 0), "radiator", 0.02, 1)
    tube("RadPipe", [(-0.4, 0.2, 0), (0.4, 0.2, 0)], 0.015, "radiator", 6)
    transform_since(n0, (x, 0, z), (0, 0 if side > 0 else math.pi, 0))


def hall_shell():
    """Floor, skirting, wainscot to the window sills, dado rail, plaster, cornice and the
    coffered ceiling, the reveals of the doors and windows lined in plaster."""
    box("Floor", (2 * XI, 0.04, 2 * ZI), (0, -0.02, 0), "floor_checker", 0.0)
    fgaps = [(x - 0.65, x + 0.65) for x in FRONT_DOORS]
    bgaps = [(BACK_DOOR - 0.75, BACK_DOOR + 0.75)]
    for (along, c, side, a0, a1, gaps) in (("x", -ZI, 1, -XI, XI, fgaps), ("x", ZI, -1, -XI, XI, bgaps),
                                           ("z", -XI, 1, -ZI, ZI, []), ("z", XI, -1, -ZI, ZI, [])):
        wall_strip(along, c, side, a0, a1, gaps, 0.0, 0.15, "wood_dark", 0.025)                 # skirting
        wall_strip(along, c, side, a0, a1, gaps, 0.15, 0.98, "wainscot", 0.02, 0.003)            # panelling
        wall_strip(along, c, side, a0, a1, gaps, 0.98, 1.03, "wood_dark", 0.04)                  # dado rail
        wall_strip(along, c, side, a0, a1, [], H - 0.2, H, "plaster", 0.12, 0.02)               # cornice
    # Warm plaster over the building's lining, above the dado to the cornice, round the openings.
    win = lambda a: (a - WIN_HW, a + WIN_HW, WIN_Y0, WIN_Y1)
    linings = (("x", -ZI, 1, [win(x) for x in FRONT_WINDOWS] + [(x - 0.65, x + 0.65, 0.0, 2.35) for x in FRONT_DOORS]),
               ("x", ZI, -1, [win(x) for x in BACK_WINDOWS] + [(BACK_DOOR - 0.75, BACK_DOOR + 0.75, 0.0, 2.3)]),
               ("z", -XI, 1, [(-0.5, 0.5, 1.0, 2.6)] if END_WINDOW else []), ("z", XI, -1, []))
    for (along, c, side, holes) in linings:
        lo, hi = 1.03, H - 0.2
        a0, a1 = (-XI, XI) if along == "x" else (-ZI, ZI)
        a = a0
        for (h0, h1, y0, y1) in sorted(holes) + [(a1, a1, lo, lo)]:
            for (p0, p1, q0, q1) in ((a, h0, lo, hi), (h0, h1, lo, max(lo, y0)), (h0, h1, min(hi, y1), hi)):
                if p1 - p0 > 0.01 and q1 - q0 > 0.01:
                    d = 0.012
                    if along == "x":
                        box("Plaster", (p1 - p0, q1 - q0, d), ((p0 + p1) / 2, (q0 + q1) / 2, c + side * d / 2), "plaster", 0.0)
                    else:
                        box("Plaster", (d, q1 - q0, p1 - p0), (c + side * d / 2, (q0 + q1) / 2, (p0 + p1) / 2), "plaster", 0.0)
            a = max(a, h1)
    box("CeilingPlaster", (2 * XI, 0.012, 2 * ZI), (0, H - 0.008, 0), "plaster", 0.0)
    # Raised panels on the wainscot (a frame every 0.8 m).
    for (along, c, side, gaps) in (("x", -ZI, 1, fgaps), ("x", ZI, -1, bgaps)):
        x = -XI + 0.4
        while x < XI - 0.3:
            if not any(g0 - 0.3 < x < g1 + 0.3 for (g0, g1) in gaps) and not (along == "x" and PART_X - 0.4 < x < PART_X + 0.6):
                box("Panel", (0.62, 0.6, 0.012), (x, 0.57, c + side * 0.026), "wainscot", 0.004)
            x += 0.8
    # Ceiling beams (coffers) and a deep cornice round the room.
    for k in range(1, 5):
        x = -XI + k * 2 * XI / 5
        box("Beam", (0.25, 0.3, 2 * ZI), (x, H - 0.15, 0), "plaster", 0.02)
    box("BeamLong", (2 * XI, 0.22, 0.22), (0, H - 0.11, 0), "plaster", 0.02)


def ticket_office():
    """The partition at PART_X with three ticket windows (marble counter, glass screen with a
    speaking grille and a money slot, brass number, the POKLADNY sign over them), the office door
    with its notice; behind it the cashiers' room."""
    t = 0.14
    x0, x1 = PART_X, PART_X + t
    xc = (x0 + x1) / 2
    holes = [(z - 0.55, z + 0.55, 1.0, 2.15) for z in TICKET_Z] + [(OFFICE_DOOR_Z - 0.45, OFFICE_DOOR_Z + 0.45, 0.0, 2.1)]
    a = -ZI
    for (h0, h1, y0, y1) in sorted(holes) + [(ZI, ZI, 0, 0)]:
        if h0 - a > 0.01:
            box("Partition", (t, H, h0 - a), (xc, H / 2, (a + h0) / 2), "plaster", 0.01)
        if h1 > h0:
            box("Partition", (t, y0, h1 - h0), (xc, y0 / 2, (h0 + h1) / 2), "wainscot", 0.01) if y0 > 0 else None
            box("Partition", (t, H - y1, h1 - h0), (xc, (y1 + H) / 2, (h0 + h1) / 2), "plaster", 0.01)
        a = h1
    # Wainscot on the hall face of the partition and the counter windows.
    wall_strip("z", x0, -1, -ZI, ZI, [(h[0], h[1]) for h in holes], 0.15, 0.98, "wainscot", 0.02, 0.003)
    wall_strip("z", x0, -1, -ZI, ZI, [(OFFICE_DOOR_Z - 0.45, OFFICE_DOOR_Z + 0.45)], 0.0, 0.15, "wood_dark", 0.025)
    for i, z in enumerate(TICKET_Z):
        box("Counter", (0.75, 0.05, 1.2), (xc, 1.0, z), "marble", 0.01)
        box("CounterFront", (0.04, 0.95, 1.25), (x0 - 0.2, 0.5, z), "wainscot", 0.006)
        for sz in (-1, 1):
            box("WindowPost", (t + 0.06, 1.15, 0.08), (xc, 1.6, z + sz * 0.55), "wood_dark", 0.008)
        box("WindowHead", (t + 0.06, 0.12, 1.18), (xc, 2.2, z), "wood_dark", 0.008)
        box("Screen", (0.008, 1.0, 1.02), (xc, 1.62, z), "glass_screen", 0.0)
        box("ScreenRail", (0.03, 0.03, 1.02), (xc, 1.12, z), "brass", 0.004)
        lathe("SpeakGrille", [(0.0, 0.0), (0.07, 0.0), (0.072, 0.006), (0.0, 0.008)], (xc - 0.006, 1.5, z), "brass", axis=(-1, 0, 0), segs=24)
        for k in range(6):
            torus("GrilleRing", 0.012 + k * 0.01, 0.0015, (xc - 0.016, 1.5, z), "brass", axis=(1, 0, 0), segs=20, rsegs=4)
        box("MoneyTray", (0.4, 0.02, 0.3), (xc, 1.035, z), "brass", 0.004)
        sign("Number%d" % i, str(i + 1), (x0 - 0.02, min(2.35, H - 1.05), z), 0.14, 0.22, 0.22, "sign_cream", "sign_blue", face=(-1, 0, 0))
        # Inside: the cashier's stool, the ticket dating press and the cash drawer.
        cyl("CashierStool", 0.18, 0.04, (PART_X + 0.7, 0.7, z), "wood_dark", segs=16)
        for k in range(3):
            a = math.tau * k / 3
            tube("StoolLeg", [(PART_X + 0.7 + math.cos(a) * 0.12, 0.68, z + math.sin(a) * 0.12),
                              (PART_X + 0.7 + math.cos(a) * 0.2, 0.0, z + math.sin(a) * 0.2)], 0.015, "steel_dark", 6)
        box("Press", (0.16, 0.16, 0.12), (PART_X + 0.35, 1.11, z + 0.35), "paint_green", 0.01)
        tube("PressLever", [(PART_X + 0.35, 1.2, z + 0.35), (PART_X + 0.5, 1.35, z + 0.35)], 0.008, "steel", 6)
        box("CashDrawer", (0.4, 0.12, 0.6), (PART_X + 0.4, 0.88, z - 0.1), "wood_dark", 0.006)
    sign("Pokladny", "TICKETS", (x0 - 0.02, min(2.75, H - 0.6), 0.0), 0.2, 2.6, 0.36, face=(-1, 0, 0))
    # Office door (closed) and its notice.
    box("OfficeDoor", (0.05, 2.05, 0.86), (xc, 1.025, OFFICE_DOOR_Z), "wainscot", 0.006, grain="y")
    for k in range(2):
        box("DoorPanel", (0.012, 0.7, 0.6), (x0 - 0.01, 0.55 + k * 0.85, OFFICE_DOOR_Z), "wood_dark", 0.004)
    sphere("DoorKnob", 0.03, (x0 - 0.05, 1.0, OFFICE_DOOR_Z - 0.32), "brass", segs=12, rings=6)
    sign("Sluzebna", "STAFF ONLY\nNO ENTRY", (x0 - 0.03, 2.3, OFFICE_DOOR_Z), 0.06, 0.6, 0.2, "sign_red_h", "sign_cream", face=(-1, 0, 0))
    # The cashiers' room: the Edmondson ticket cabinet on the end wall, a desk, the safe, files.
    cx = XI - 0.22
    box("TicketCabinet", (0.4, min(1.2, H - 2.1), 2.4), (cx, 1.0 + min(1.2, H - 2.1) / 2, -0.5), "wood_dark", 0.01)
    for r in range(8 if H > 4 else 5):
        for c in range(14):
            box("TicketTube", (0.02, 0.1, 0.12), (cx - 0.2, 1.05 + r * 0.14, -1.6 + c * 0.16), "ticket_card", 0.0)
    dz = ZI - 1.7
    box("Desk", (0.75, 0.05, 1.5), (XI - 0.6, 0.76, dz), "wood_dark", 0.008)
    for sz in (-1, 1):
        box("DeskPed", (0.7, 0.74, 0.45), (XI - 0.6, 0.37, dz + sz * 0.5), "wood_dark", 0.008)
    box("Ledger", (0.3, 0.04, 0.42), (XI - 0.65, 0.8, dz - 0.1), "leather_green", 0.004)
    box("Safe", (0.6, 0.8, 0.6), (PART_X + 0.6, 0.4, -ZI + 0.6), "paint_green", 0.02)
    cyl("SafeDial", 0.06, 0.03, (PART_X + 0.6, 0.55, -ZI + 0.91), "brass", axis=(0, 0, 1), segs=20)
    for k in range(3):
        box("FileBox", (0.35, 0.3, 0.12), (XI - 0.25, 2.2, ZI - 2.5 + k * 0.14), "kraft", 0.004)


def waiting_room():
    """Benches back to back and along the end wall, the tiled stove in the corner, the scale,
    a palm, a litter bin."""
    bench(-5.3, -0.6, -math.pi / 2, 2.6)
    bench(-5.9, -0.6, math.pi / 2, 2.6)
    bench(-XI + 0.35, -2.6, -math.pi / 2, 2.0)
    bench(-XI + 0.35, 2.4, -math.pi / 2, 2.0)
    if FRONT_BENCH is not None:
        bench(FRONT_BENCH, -ZI + 0.35, math.pi, 2.0)
    # Tiled stove: plinth, two tiers of green glazed tiles with a cornice, crown.
    sx, sz = -XI + 0.45, ZI - 0.45
    box("StovePlinth", (0.9, 0.2, 0.9), (sx, 0.1, sz), "stone_cap", 0.01)
    for (y0, h, w) in ((0.2, 1.0, 0.8), (1.25, 0.8, 0.7)):
        box("StoveBody", (w, h, w), (sx, y0 + h / 2, sz), "stove_tile", 0.01)
        for r in range(1, int(h / 0.2)):
            box("TileJoint", (w + 0.006, 0.01, w + 0.006), (sx, y0 + 0.2 * r, sz), "plaster", 0.0)
        box("StoveCornice", (w + 0.1, 0.06, w + 0.1), (sx, y0 + h + 0.03, sz), "stove_tile", 0.02)
    lathe("StoveCrown", [(0.0, 2.11), (0.33, 2.11), (0.25, 2.25), (0.1, 2.32), (0.0, 2.34)], (sx, 0, sz), "stove_tile", segs=16)
    box("StoveDoor", (0.3, 0.25, 0.02), (sx + 0.41, 0.6, sz), "brass", 0.004, rot=(0, math.pi / 2, 0))
    tube("Flue", [(sx, 2.3, sz), (sx, H - 0.25, sz + 0.2), (sx, H - 0.25, ZI)], 0.06, "steel_dark", 10, bend=0.2)
    # The coin-operated weighing machine against the town wall.
    weighing_machine(SCALE_X, ZI)
    # Palms.
    for (x, dz) in PALMS:
        z = -ZI - dz
        n0 = count()
        ms, k = import_ph("potted_plant_02", (0, 1.3, 0))
        _decimate(ms, 0.04)
        transform_since(n0, (x, 0, z))
    sign("Cekarna", "WAITING ROOM", (-XI + 0.03, min(2.75, H - 0.45), 0.0), 0.2, 2.0, 0.34, face=(1, 0, 0))


def security_check():
    """At the town door: a walk-through detector arch with its control box, a table with trays,
    rope barriers leading to it, the guard's lectern, floor markings and the notice."""
    z = ZI - 1.75
    for sx in (-1, 1):
        box("ArchSide", (0.12, 2.15, 0.55), (sx * 0.5, 1.075, z), "detector_grey", 0.03)
        for k in range(8):
            box("ArchLed", (0.01, 0.06, 0.04), (sx * 0.44, 0.3 + k * 0.22, z - 0.2), "hall_lamp", 0.0)
    box("ArchTop", (1.12, 0.2, 0.55), (0, 2.25, z), "detector_grey", 0.03)
    box("ArchPanel", (0.5, 0.12, 0.02), (0, 2.25, z - 0.285), "board_black", 0.004)
    box("ArchLampG", (0.08, 0.05, 0.01), (-0.12, 2.25, z - 0.297), "hall_lamp", 0.0)
    box("ArchLampR", (0.08, 0.05, 0.01), (0.12, 2.25, z - 0.297), "sign_red_h", 0.0)
    # Inspection table with trays, on the right going in.
    box("TableTop", (1.6, 0.04, 0.7), (1.45, 0.86, z - 0.2), "steel", 0.01)
    for sx in (-1, 1):
        for sz in (-1, 1):
            tube("TableLeg", [(1.45 + sx * 0.72, 0.0, z - 0.2 + sz * 0.3), (1.45 + sx * 0.72, 0.84, z - 0.2 + sz * 0.3)], 0.02, "steel", 6)
    for k in range(3):
        box("Tray", (0.45, 0.07, 0.34), (0.95 + k * 0.48, 0.92, z - 0.2), "tray_grey", 0.02)
    # Rope barriers: brass posts with red ropes from the door to the arch.
    posts = [(-0.75, ZI - 0.4), (-0.75, z + 0.45), (0.75, ZI - 0.4), (0.75, z + 0.45)]
    for (x, zz) in posts:
        lathe("Stanchion", [(0.0, 0.0), (0.16, 0.0), (0.15, 0.03), (0.03, 0.06), (0.025, 0.95), (0.04, 0.98), (0.0, 1.0)],
              (x, 0, zz), "brass", segs=16)
    for x in (-0.75, 0.75):
        pts = [(x, 0.93, ZI - 0.4)] + [(x, 0.93 - 0.12 * math.sin(math.pi * k / 6), ZI - 0.4 + (z + 0.45 - ZI + 0.4) * k / 6) for k in range(1, 6)] + \
              [(x, 0.93, z + 0.45)]
        tube("Rope", pts, 0.018, "rope_red", 8, bend=0.05)
    # The guard's lectern by the arch.
    gx, gz = -1.4, z + 0.1
    box("LecternBase", (0.5, 1.0, 0.45), (gx, 0.5, gz), "wood_dark", 0.01)
    box("LecternTop", (0.6, 0.04, 0.5), (gx, 1.05, gz), "wood_dark", 0.01, rot=(0.25, 0, 0))
    box("LogBook", (0.3, 0.03, 0.22), (gx, 1.09, gz), "leather_black", 0.004, rot=(0.25, 0, 0))
    # Floor: a yellow line to wait at, and the notice on a stand.
    box("WaitLine", (1.5, 0.004, 0.08), (0, 0.003, z + 0.75), "floor_yellow", 0.0)
    box("StandPost", (0.04, 1.4, 0.04), (0.95, 0.7, ZI - 0.55), "steel", 0.006)
    sign("SecSign", "SECURITY\nCHECK", (0.95, 1.55, ZI - 0.55), 0.07, 0.6, 0.32, "sign_blue", "sign_cream", face=(0, 0, 1))
    sign("SecSign2", "SECURITY\nCHECK", (0.95, 1.55, ZI - 0.57), 0.07, 0.6, 0.32, "sign_blue", "sign_cream", face=(0, 0, -1))


def weighing_machine(x, zwall):
    """A station weighing machine (penny scale) standing against the wall at z = zwall, facing -z:
    a low cast-iron platform with a ribbed rubber mat to step on, a fluted column, and at eye
    height a big white dial (0-150 kg, numbered every 10, a red needle) in a brass bezel under a
    crown, the coin slot and the instruction plate on the column."""
    n0 = count()
    zc = -0.45                                       # built round its own origin, the wall at z = 0
    # Platform: a cast-iron tray with a rubber mat, a nose plate at the front.
    box("ScalePlatform", (0.56, 0.11, 0.62), (0, 0.055, zc), "paint_black", 0.02)
    box("ScaleMat", (0.46, 0.012, 0.5), (0, 0.116, zc - 0.02), "rubber", 0.004)
    for k in range(9):
        box("MatRib", (0.44, 0.006, 0.012), (0, 0.124, zc - 0.24 + k * 0.055), "rubber", 0.0)
    box("ScaleNose", (0.56, 0.04, 0.03), (0, 0.09, zc - 0.31), "brass", 0.006)
    # Column at the back of the platform, fluted, gold lines.
    lathe("ScaleColumn", [(0.0, 0.11), (0.11, 0.11), (0.1, 0.18), (0.075, 0.24), (0.065, 1.2), (0.08, 1.24), (0.09, 1.28), (0.0, 1.28)],
          (0, 0, -0.13), "paint_green", segs=24)
    for k in range(8):
        a = math.tau * k / 8
        tube("Flute", [(math.cos(a) * 0.066, 0.3, -0.13 + math.sin(a) * 0.066), (math.cos(a) * 0.062, 1.18, -0.13 + math.sin(a) * 0.062)],
             0.006, "brass", 4)
    # Dial head: a deep drum facing -z, white enamel face, numbers and ticks, brass bezel, needle.
    dy, dz, R = 1.55, -0.16, 0.25
    cyl("DialDrum", R + 0.03, 0.14, (0, dy, dz), "paint_green", axis=(0, 0, 1), segs=40)
    face_z = dz - 0.071
    disc("DialFace", R, (0, dy, face_z), "sign_cream", segs=48)
    torus("Bezel", R + 0.012, 0.016, (0, dy, face_z - 0.004), "brass", axis=(0, 0, 1), segs=48, rsegs=8)
    for k in range(31):
        a = math.radians(-135 + 270 * k / 30)
        big = k % 2 == 0
        r1 = R * 0.9
        r0 = r1 - (0.045 if big else 0.025)
        rc = (r0 + r1) / 2
        box("Tick", (0.006 if big else 0.004, r1 - r0, 0.002), (math.sin(a) * rc, dy + math.cos(a) * rc, face_z - 0.002),
            "plate_ink" if "plate_ink" in hdlib.MATS else "ink", 0.0, rot=(0, 0, -a))
    for k in range(0, 16, 3):
        a = math.radians(-135 + 270 * k / 15)
        rc = R * 0.62
        plate = box("NumPad", (0.07, 0.05, 0.001), (math.sin(a) * rc, dy + math.cos(a) * rc, face_z + 0.0005), "sign_cream", 0.0)
        text_on("Num", str(k * 10), plate, (math.sin(a) * rc, dy + math.cos(a) * rc, face_z - 0.05), 0.038, "board_black",
                lift=0.0012, flat=True)
    lbl = box("KgPad", (0.08, 0.03, 0.001), (0, dy - R * 0.45, face_z + 0.0005), "sign_cream", 0.0)
    text_on("Kg", "KG", lbl, (0, dy - R * 0.45, face_z - 0.05), 0.03, "board_black", lift=0.0012, flat=True)
    na = math.radians(-135 + 270 * 72 / 150)
    box("Needle", (0.008, R * 0.82, 0.003), (math.sin(na) * R * 0.36, dy + math.cos(na) * R * 0.36, face_z - 0.008), "sign_red_h", 0.0,
        rot=(0, 0, -na))
    cyl("NeedleHub", 0.018, 0.012, (0, dy, face_z - 0.01), "brass", axis=(0, 0, 1), segs=16)
    # Crown and lamp-like finial over the drum.
    lathe("Crown", [(0.0, 0.0), (0.2, 0.0), (0.16, 0.05), (0.06, 0.1), (0.04, 0.16), (0.07, 0.19), (0.0, 0.21)], (0, dy + R + 0.03, dz),
          "paint_green", segs=24)
    sphere("Finial", 0.035, (0, dy + R + 0.27, dz), "brass", segs=12, rings=6)
    # The instruction plate and coin slot on the column, big and readable.
    box("CoinBox", (0.18, 0.22, 0.1), (0, 1.12, -0.2), "paint_green", 0.02)
    box("CoinSlot", (0.05, 0.008, 0.004), (0, 1.17, -0.252), "board_black", 0.0)
    box("ReturnCup", (0.07, 0.04, 0.05), (0, 1.04, -0.255), "brass", 0.008)
    pl = box("Instructions", (0.42, 0.22, 0.01), (0, 0.8, -0.2), "sign_cream", 0.004)
    box("InstructionsRim", (0.44, 0.24, 0.006), (0, 0.8, -0.193), "brass", 0.002)
    text_on("InstructionsText", "WEIGH YOURSELF\n10 HELLER", pl, (0, 0.8, -0.25), 0.05, "sign_red_h", lift=0.0012, flat=True)
    transform_since(n0, (x, 0, zwall))


def wall_fittings():
    """Signs over the doors, the departures board, the clock, notices, radiators, lamps."""
    for x in FRONT_DOORS:
        sign("ToTrains", "TO THE TRAINS", (x, min(2.65, H - 0.6), -ZI + 0.03), 0.12, 1.3, 0.24, face=(0, 0, 1))
    sign("Exit", "EXIT TO TOWN", (BACK_DOOR, min(2.6, H - 0.6), ZI - 0.03), 0.1, 1.6, 0.22, face=(0, 0, -1))
    # Departures board: black, white lettering, in a wooden frame, on the town wall.
    # On the town wall (stone) or the waiting room's end wall (town), from the board's own frame.
    n_board = count()
    bx, by = 0.0, min(2.15, H - 1.25)
    box("BoardFrame", (2.6, 1.7, 0.06), (bx, by, 0.03), "wood_dark", 0.01)
    bd = box("Board", (2.45, 1.55, 0.02), (bx, by, -0.005), "board_black", 0.003)
    text_on("BoardHead", "DEPARTURES", bd, (bx, by + 0.6, -0.06), 0.16, "board_letter", lift=0.0012, inward=(0, 0, 1), flat=True)
    rows = ["19.10  EXPRESS 412   KAMENNÝ MOST", "19.42  LOCAL   1103   STŘÍBRNÁ HORA", "20.05  LOCAL   1105   KRÁLOVEC",
            "20.27  EXPRESS 412   SNĚŽNÁ", "21.15  EXPRESS 412   KAMENNÝ MOST", "22.40  LOCAL   1107   VRCHOVINA"]
    text_on("BoardRows", "\n".join(rows), bd, (bx, by - 0.15, -0.06), 0.1, "board_letter", lift=0.0012, line=1.25, inward=(0, 0, 1), flat=True)
    if BOARD[0] == "x":
        transform_since(n_board, (BOARD[1], 0, ZI - 0.06))
    else:
        transform_since(n_board, (-XI + 0.06, 0, BOARD[1]), (0, -math.pi / 2, 0))
    # Clock over the town door.
    n0 = count()
    ms, k = import_ph("wall_clock", (0.55, 0.55, 0), origin="back")
    _decimate(ms, 0.3)
    transform_since(n0, (BACK_DOOR, min(3.2, H - 0.6), ZI))
    # Notice boards and posters on the platform wall.
    box("NoticeBoard", (1.2, 0.9, 0.03), (1.6, 1.75, -ZI + 0.015), "kraft", 0.006)
    for k in range(4):
        box("Notice", (0.26, 0.36, 0.004), (1.2 + (k % 2) * 0.4 + (k // 2) * 0.35, 1.6 + (k // 2) * 0.1 + (k % 2) * 0.12, -ZI + 0.034),
            "paper" if k % 2 else "paper_aged", 0.0)
    tx = TIMETABLE_X
    sign("Timetable", "TIMETABLE", (tx, 2.4, -ZI + 0.03), 0.09, 1.1, 0.18, face=(0, 0, 1))
    box("TimetableSheet", (1.1, 1.2, 0.01), (tx, 1.65, -ZI + 0.025), "paper_aged", 0.0)
    for k in range(14):
        box("TimetableLine", (0.9, 0.008, 0.002), (tx, 2.15 - k * 0.07, -ZI + 0.031), "plate_ink" if "plate_ink" in hdlib.MATS else "ink", 0.0)
    # Radiators under the windows.
    for x in FRONT_WINDOWS:
        radiator(x, -ZI + 0.12, 1)
    for x in BACK_WINDOWS:
        radiator(x, ZI - 0.12, -1)
    # Lamps over the hall, the waiting room and the office.
    for (x, z) in LAMPS:
        pendant(x, z)
    # A litter bin by the door.
    n0 = count()
    ms, k = import_ph("metal_trash_can", (0.42, 0, 0), drop=["rust"])
    _decimate(ms, 0.3)
    transform_since(n0, (1.9, 0, ZI - 0.4))


def doorways():
    """The town building's platform doorways (its walls are procedural): a moulded stone surround,
    the glazed transom over the opening, and both leaves of each door standing open against the
    reveals inside."""
    t = 0.4
    zo = -ZI - t                           # the wall's outer face
    w, h = 1.3, 2.35
    for x in FRONT_DOORS:
        for k in (-1, 1):
            box("DoorCase", (0.22, h + 0.3, 0.1), (x + k * (w / 2 + 0.11), (h + 0.3) / 2, zo - 0.05), "stone_cap", 0.01, grain="y")
            box("DoorLeaf", (0.05, h - 0.05, w / 2 - 0.02), (x + k * (w / 2 - 0.04), h / 2, -ZI + 0.34), "wainscot", 0.006, grain="y")
            box("LeafGlass", (0.012, h * 0.38, w / 2 - 0.2), (x + k * (w / 2 - 0.07), h * 0.68, -ZI + 0.34), "glass_screen", 0.0)
            box("Reveal", (0.02, h, t), (x + k * (w / 2 - 0.01), h / 2, -ZI - t / 2), "plaster", 0.0)
        box("DoorHead", (w + 0.66, 0.22, 0.12), (x, h + 0.4, zo - 0.06), "stone_cap", 0.015)
        box("Soffit", (w, 0.02, t), (x, h - 0.01, -ZI - t / 2), "plaster", 0.0)


@asset
def station_hall():
    configure("stone")
    seed(300)
    hall_shell()
    ticket_office()
    waiting_room()
    security_check()
    wall_fittings()


@asset
def station_hall_town():
    configure("town")
    seed(301)
    hall_shell()
    ticket_office()
    waiting_room()
    security_check()
    wall_fittings()
    doorways()
    configure("stone")


VIEWS = {"station_hall": (0.55, 1.6, -0.45), "station_hall_town": (0.55, 1.6, -0.45)}
