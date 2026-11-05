"""Station-yard and town props (outdoors, so most carry a cap of snow).

GODOT space, real metres, origin on the ground under the middle, the front toward -Z.
    station_bell     - k.u.k. "Läutewerk": fluted cast-iron column, the clockwork housing on top and
                       its two bells mounted above the housing on a cross bar, with their hammers
    vending_machine  - drinks automat: red enamelled cabinet, a lit glass front with rows of bottles,
                       coin plate, pull knobs and a delivery hatch
    substation       - village transformer tower ("trafačka"): brick, sheet-metal pyramid roof, steel
                       doors with the high-voltage warning, louvres, line insulators under the eaves
    phone_booth      - green steel-and-glass telephone box with the TELEFON lantern and the phone
    poster_pillar    - advertising column with posters and a domed cap
    waste_bin        - platform litter bin on a cast-iron post
    gate_pier        - brick gate pier with a stone cap and a lantern
    iron_gate        - Poly Haven large_iron_gate (CC0), 3 m
    power_box, utility_box_a/b - Poly Haven electrical cabinets (CC0)
    statue_horse, statue_gothic - Poly Haven statues (CC0) on brick-and-stone plinths
    fire_hydrant, covered_car, picnic_table - Poly Haven (CC0)
    swing_set, slide, seesaw, roundabout, sandbox, climbing_frame - a town playground
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
    "brick": dict(tex="brick", scale=1.2),
    "snow": dict(tex="snow", scale=1.4),
    "stone_cap": dict(tex="paint_cream", scale=0.9),
    "panel_lit": dict(color=(1.0, 0.9, 0.72), rough=0.4, emit=(1.0, 0.86, 0.6), emit_k=1.4),
    "glass_green": dict(color=(0.1, 0.42, 0.15), rough=0.08),
    "glass_brown": dict(color=(0.42, 0.18, 0.05), rough=0.08),
    "lemonade": dict(color=(0.95, 0.75, 0.2), rough=0.1),
    "yellow_enamel": dict(color=(0.88, 0.66, 0.08), rough=0.3),
    "red_enamel": dict(color=(0.55, 0.05, 0.04), rough=0.3),
    "insulator": dict(color=(0.55, 0.32, 0.18), rough=0.12),
    "poster_a": dict(color=(0.86, 0.78, 0.6), rough=0.8),
    "poster_b": dict(color=(0.62, 0.12, 0.1), rough=0.8),
    "poster_c": dict(color=(0.2, 0.3, 0.45), rough=0.8),
    "poster_ink": dict(color=(0.05, 0.04, 0.035), rough=0.8),
    "poster_cream": dict(color=(0.93, 0.88, 0.75), rough=0.8),
    "play_red": dict(color=(0.6, 0.08, 0.05), rough=0.45),
    "play_blue": dict(color=(0.08, 0.2, 0.5), rough=0.45),
    "play_yellow": dict(color=(0.85, 0.62, 0.08), rough=0.45),
    "sand": dict(color=(0.6, 0.52, 0.38), rough=0.95),
})


def snow_box(name, size, center, rot=(0, 0, 0)):
    """A soft cap of snow: a box with well-rounded edges, slightly irregular."""
    return box(name, size, center, "snow", min(size[1] * 0.45, 0.04), 3, rot=rot)


def decimate(objs, ratio):
    for o in objs:
        md = o.modifiers.new("Dec", "DECIMATE")
        md.ratio = ratio


# ————— station bell —————

@asset
def station_bell():
    seed(100)
    # Stone footing and the fluted cast-iron column.
    box("Footing", (0.5, 0.18, 0.5), (0, 0.09, 0), "stone_cap", 0.02)
    snow_box("FootSnow", (0.46, 0.04, 0.46), (0, 0.19, 0))
    lathe("Base", [(0.0, 0.18), (0.17, 0.18), (0.17, 0.24), (0.14, 0.3), (0.12, 0.42), (0.095, 0.5)], (0, 0, 0), "paint_green", segs=24)
    lathe("Column", [(0.095, 0.5), (0.085, 1.2), (0.075, 1.86), (0.09, 1.9), (0.09, 1.95)], (0, 0, 0), "paint_green", segs=24,
          cap_bottom=False)
    for k in range(10):
        a = math.tau * k / 10
        tube("Flute", [(math.cos(a) * 0.088, 0.55, math.sin(a) * 0.088), (math.cos(a) * 0.076, 1.82, math.sin(a) * 0.076)],
             0.008, "paint_green", 6)
    # Clockwork housing: a cast box with a door, a round inspection window and a crank boss.
    box("Housing", (0.46, 0.52, 0.34), (0, 2.21, 0), "paint_green", 0.015, 3, grain="y")
    box("HousingPlinth", (0.5, 0.05, 0.38), (0, 1.97, 0), "paint_green", 0.01)
    box("Door", (0.34, 0.38, 0.012), (0, 2.21, -0.176), "paint_green", 0.006, grain="y")
    lathe("Window", [(0.0, 0.0), (0.06, 0.0), (0.065, 0.008), (0.06, 0.014), (0.0, 0.014)], (0, 2.27, -0.182), "brass", axis=(0, 0, -1), segs=24)
    disc("WindowGlass", 0.05, (0, 2.27, -0.197), "glass")
    cyl("CrankBoss", 0.03, 0.03, (0.17, 2.1, -0.19), "brass", axis=(0, 0, 1), segs=16)
    for sx in (-1, 1):
        cyl("Hinge", 0.012, 0.08, (sx * 0.17, 2.1 + (0.15 if sx > 0 else 0.0), -0.182), "steel_dark", segs=10)
    # Pyramid cap over the housing.
    lathe("Cap", [(0.36, 2.48), (0.34, 2.5), (0.0, 2.68)], (0, 0, 0), "paint_green", segs=4)
    snow_box("CapSnow", (0.38, 0.05, 0.28), (0, 2.6, 0.0), rot=(0, math.pi / 4, 0))
    # Cross bar standing on the cap's peak, with the two bells hung below its ends (well clear of
    # the housing and the cap), each with its hammer.
    cyl("Stem", 0.025, 0.24, (0, 2.78, 0), "paint_green", segs=12)
    tube("CrossBar", [(-0.42, 2.9, 0), (0.42, 2.9, 0)], 0.022, "paint_green", 10)
    for sx in (-1, 1):
        x = sx * 0.38
        tube("BellHanger", [(x, 2.9, 0), (x, 2.84, 0)], 0.016, "paint_green", 8)
        # Bell: mouth down, rim at y 2.58.
        lathe("Bell", [(0.0, 2.84), (0.07, 2.835), (0.1, 2.8), (0.11, 2.72), (0.13, 2.64), (0.155, 2.6), (0.158, 2.585),
                       (0.148, 2.58), (0.135, 2.6), (0.105, 2.66), (0.09, 2.75), (0.06, 2.81), (0.0, 2.815)],
              (x, 0, 0), "brass", segs=40, cap_bottom=False, cap_top=False)
        sphere("Clapper", 0.025, (x, 2.62, 0), "steel_dark", segs=12, rings=6)
        snow_box("BellSnow", (0.11, 0.03, 0.11), (x, 2.85, 0))
        # Hammer: an arm from the cross bar, its head against the bell's lip.
        tube("HammerArm", [(sx * 0.12, 2.9, -0.03), (sx * 0.2, 2.78, -0.12), (x - sx * 0.02, 2.64, -0.17)], 0.008, "steel_dark", 6,
             bend=0.03)
        sphere("HammerHead", 0.028, (x - sx * 0.02, 2.63, -0.18), "steel_dark", (1, 1, 1.3), 12, 6)
    snow_box("BarSnow", (0.84, 0.025, 0.05), (0, 2.93, 0))
    sphere("Finial", 0.035, (0, 2.95, 0), "brass", segs=12, rings=6)


# ————— vending machine —————

@asset
def vending_machine():
    seed(101)
    W, H, D = 0.78, 1.82, 0.6
    zc = 0.0
    zf = -D / 2
    box("Plinth", (W - 0.04, 0.08, D - 0.04), (0, 0.04, zc), "paint_black", 0.01)
    # Cabinet: the back part solid, the front a frame round the bottle recess (0.2 m deep).
    rd = 0.2
    box("Body", (W, H - 0.08, D - rd), (0, 0.08 + (H - 0.08) / 2, zc + rd / 2), "paint_red", 0.025, 3, grain="y")
    # Header with the name, lit from inside.
    box("Header", (W - 0.06, 0.24, 0.03), (0, H - 0.17, zf - 0.012), "panel_lit", 0.01)
    hd = box("HeaderFace", (W - 0.1, 0.2, 0.004), (0, H - 0.17, zf - 0.03), "poster_cream", 0.0)
    text_on("Name", "LEMONADE", hd, (0, H - 0.15, zf - 0.04), 0.085, "red_enamel", lift=0.0015)
    text_on("Price", "50 h", hd, (0, H - 0.235, zf - 0.04), 0.04, "poster_ink", lift=0.0015)
    # Glazed front: chrome frame, a lit back panel and four shelves of bottles.
    gx, gy0, gy1 = W - 0.18, 0.62, H - 0.34
    gh = gy1 - gy0
    gcy = (gy0 + gy1) / 2
    gl, gr = -0.04 - gx / 2, -0.04 + gx / 2
    fz = zf + rd / 2
    box("FrontL", (gl + W / 2, H - 0.08, rd), ((gl - W / 2) / 2, 0.08 + (H - 0.08) / 2, fz), "paint_red", 0.02, grain="y")
    box("FrontR", (W / 2 - gr, H - 0.08, rd), ((gr + W / 2) / 2, 0.08 + (H - 0.08) / 2, fz), "paint_red", 0.02, grain="y")
    box("FrontTop", (gx, H - gy1, rd), (-0.04, (gy1 + H) / 2, fz), "paint_red", 0.02)
    box("FrontBottom", (gx, gy0 - 0.08, rd), (-0.04, (gy0 + 0.08) / 2, fz), "paint_red", 0.02)
    for sv in (-1, 1):
        box("Frame", (gx + 0.05, 0.03, 0.03), (-0.04, gcy + sv * (gh / 2 + 0.01), zf - 0.012), "steel", 0.006)
    for su in (-1, 1):
        box("Frame", (0.03, gh + 0.05, 0.03), (-0.04 + su * (gx / 2 + 0.01), gcy, zf - 0.012), "steel", 0.006)
    box("BackPanel", (gx, gh, 0.01), (-0.04, gcy, zf + rd - 0.005), "panel_lit", 0.0)
    rows = 4
    for r in range(rows):
        y = gy0 + 0.04 + r * gh / rows
        box("Shelf", (gx, 0.01, rd - 0.02), (-0.04, y, zf + rd / 2), "steel", 0.002)
        n = 6
        for i in range(n):
            x = -0.04 - gx / 2 + (i + 0.5) * gx / n
            g = "glass_green" if (i + r) % 3 else "glass_brown"
            lathe("Bottle", [(0.0, 0.0), (0.028, 0.0), (0.03, 0.01), (0.03, 0.13), (0.014, 0.17), (0.011, 0.21), (0.012, 0.215), (0.0, 0.217)],
                  (x, y + 0.005, zf + 0.1), g, segs=12)
            cyl("Cap", 0.013, 0.012, (x, y + 0.226, zf + 0.1), "red_enamel" if r % 2 else "steel", segs=10)
    box("Glass", (gx, gh, 0.006), (-0.04, gcy, zf - 0.006), "glass", 0.0)
    # Coin plate, return button and four pull knobs (one per row) at the right.
    cx = W / 2 - 0.065
    box("CoinPlate", (0.07, 0.2, 0.01), (cx, 1.25, zf - 0.006), "brass", 0.004)
    box("CoinSlot", (0.008, 0.035, 0.004), (cx, 1.31, zf - 0.012), "paint_black", 0.0)
    cyl("Return", 0.012, 0.012, (cx, 1.2, zf - 0.016), "steel", axis=(0, 0, 1), segs=12)
    for r in range(rows):
        y = gy0 + 0.12 + r * gh / rows
        cyl("Knob", 0.022, 0.03, (cx, y, zf - 0.02), "steel", axis=(0, 0, 1), segs=16)
        sphere("KnobHead", 0.026, (cx, y, zf - 0.04), "steel", (1, 1, 0.6), 16, 8)
    # Delivery hatch at the bottom with a flap.
    box("HatchFrame", (0.42, 0.18, 0.02), (-0.04, 0.33, zf - 0.006), "steel", 0.006)
    box("Hatch", (0.38, 0.14, 0.012), (-0.04, 0.33, zf - 0.02), "paint_black", 0.004, rot=(0.25, 0, 0))
    # Snow on the top.
    snow_box("Snow", (W - 0.02, 0.06, D - 0.04), (0, H + 0.02, zc))


# ————— transformer tower —————

@asset
def substation():
    seed(102)
    S, Hb = 2.6, 7.2
    box("Plinth", (S + 0.2, 0.5, S + 0.2), (0, 0.25, 0), "stone_cap", 0.02)
    box("Walls", (S, Hb - 0.5, S), (0, 0.5 + (Hb - 0.5) / 2, 0), "brick", 0.01, 2, grain="x")
    # Brick bands and the cornice.
    for y in (2.9, Hb - 0.15):
        box("Band", (S + 0.08, 0.16, S + 0.08), (0, y, 0), "brick", 0.01)
    box("Cornice", (S + 0.3, 0.12, S + 0.3), (0, Hb + 0.06, 0), "stone_cap", 0.015)
    # Sheet-metal pyramid roof with a ventilator on the peak, and its snow.
    lathe("Roof", [(0.0, Hb + 0.12), (S * 0.78, Hb + 0.12), (S * 0.78, Hb + 0.16), (0.0, Hb + 1.35)], (0, 0, 0), "steel_dark", segs=4)
    for o in hdlib._parts[-1:]:
        o.data.transform(g_matrix((0, 0, 0), (0, math.pi / 4, 0)))
    lathe("RoofSnow", [(0.0, Hb + 0.16), (S * 0.74, Hb + 0.19), (S * 0.72, Hb + 0.24), (0.0, Hb + 1.4)], (0, 0, 0), "snow", segs=4)
    for o in hdlib._parts[-1:]:
        o.data.transform(g_matrix((0, 0, 0), (0, math.pi / 4, 0)))
    cyl("Vent", 0.12, 0.3, (0, Hb + 1.45, 0), "steel_dark", segs=12)
    lathe("VentCap", [(0.0, Hb + 1.6), (0.22, Hb + 1.6), (0.0, Hb + 1.75)], (0, 0, 0), "steel_dark", segs=12)
    # Steel double door (front), the warning plate and a number plate.
    zf = -S / 2
    box("DoorFrame", (1.3, 2.25, 0.04), (0, 0.5 + 1.12, zf - 0.01), "steel_dark", 0.008)
    for sx in (-1, 1):
        box("Door", (0.6, 2.15, 0.03), (sx * 0.31, 0.5 + 1.1, zf - 0.03), "paint_green", 0.006, grain="y")
        for y in (0.9, 2.3):
            box("Hinge", (0.05, 0.12, 0.04), (sx * 0.62, 0.5 + y - 0.5, zf - 0.04), "steel_dark", 0.005)
        for k in range(5):
            box("Louvre", (0.42, 0.03, 0.03), (sx * 0.31, 0.75 + k * 0.06, zf - 0.05), "paint_green", 0.004, rot=(-0.6, 0, 0))
    box("Handle", (0.03, 0.18, 0.04), (0.07, 1.65, zf - 0.065), "steel", 0.008)
    plate = box("Warning", (0.34, 0.3, 0.006), (-0.31, 2.05, zf - 0.05), "yellow_enamel", 0.004)
    bolt = [(0.02, 0.1), (-0.03, 0.0), (0.005, 0.0), (-0.025, -0.1), (0.04, 0.02), (0.005, 0.02), (0.03, 0.1)]
    extrude("Bolt", bolt, 0.002, "red_enamel", (-0.31, 2.08, zf - 0.054), bevel=0.0)
    text_on("WarnText", "DANGER!\nHIGH VOLTAGE", plate, (-0.31, 1.95, zf - 0.06), 0.03, "poster_ink", lift=0.0012)
    box("NumberPlate", (0.22, 0.1, 0.006), (0, 2.9, zf - 0.02), "enamel_blue", 0.003)
    # Louvred vents high on every side.
    for k in range(4):
        a = k * math.pi / 2
        ca, sa = math.cos(a), math.sin(a)
        c = (sa * (S / 2 + 0.02), Hb - 1.1, -ca * (S / 2 + 0.02))
        box("VentFrame", (0.7, 0.7, 0.05), c, "stone_cap", 0.01, rot=(0, a, 0))
        for j in range(6):
            y = Hb - 1.35 + j * 0.1
            box("VentSlat", (0.6, 0.02, 0.07), (sa * (S / 2 + 0.04), y, -ca * (S / 2 + 0.04)), "steel_dark", 0.004, rot=(-0.6, a, 0))
    # Line insulators on a steel bracket under the eaves (the side away from the door, +Z) and the
    # three wires running off toward the pole line.
    zb = S / 2 + 0.05
    tube("Bracket", [(-0.9, Hb - 0.55, zb), (0.9, Hb - 0.55, zb)], 0.03, "steel_dark", 8)
    for sx in (-1, 1):
        tube("BracketStay", [(sx * 0.85, Hb - 0.55, zb), (sx * 0.85, Hb - 0.95, S / 2)], 0.02, "steel_dark", 8)
    for i, x in enumerate((-0.6, 0.0, 0.6)):
        cyl("InsPin", 0.012, 0.18, (x, Hb - 0.45, zb), "steel_dark", segs=8)
        lathe("Insulator", [(0.0, 0.0), (0.06, 0.0), (0.055, 0.04), (0.04, 0.06), (0.045, 0.09), (0.025, 0.12), (0.0, 0.125)],
              (x, Hb - 0.4, zb), "insulator", segs=16)
        tube("Line", [(x, Hb - 0.27, zb), (x * 1.1, Hb - 0.25, zb + 1.5), (x * 1.2, Hb - 0.15, zb + 3.5)], 0.006, "steel_dark", 6, bend=0.6)
        tube("Drop", [(x, Hb - 0.33, zb), (x * 0.5, Hb - 0.8, S / 2 + 0.01)], 0.008, "steel_dark", 6)


# ————— phone booth —————

@asset
def phone_booth():
    seed(103)
    S, H = 1.0, 2.35
    box("Base", (S + 0.06, 0.1, S + 0.06), (0, 0.05, 0), "stone_cap", 0.015)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box("Post", (0.07, H - 0.1, 0.07), (sx * (S / 2 - 0.035), 0.1 + (H - 0.1) / 2, sz * (S / 2 - 0.035)), "paint_green", 0.01, grain="y")
    for y in (0.1 + 0.85, H - 0.25):
        for k in range(4):
            a = k * math.pi / 2
            box("Rail", (S - 0.08, 0.06, 0.05), (math.sin(a) * (S / 2 - 0.03), y, -math.cos(a) * (S / 2 - 0.03)), "paint_green", 0.008,
                rot=(0, a, 0))
    # Lower panels, glazed upper panes (with glazing bars) on three sides and the door (front).
    for k in range(4):
        a = k * math.pi / 2
        ca, sa = math.cos(a), math.sin(a)
        p = (sa * (S / 2 - 0.03), 0.1 + 0.42, -ca * (S / 2 - 0.03))
        box("Panel", (S - 0.1, 0.8, 0.025), p, "paint_green", 0.006, rot=(0, a, 0))
        gp = (sa * (S / 2 - 0.03), 0.95 + (H - 0.25 - 0.95) / 2, -ca * (S / 2 - 0.03))
        box("Pane", (S - 0.12, H - 1.25, 0.008), gp, "glass", 0.0, rot=(0, a, 0))
        for j in range(1, 4):
            y = 0.95 + j * (H - 1.2) / 4
            box("Bar", (S - 0.1, 0.025, 0.03), (sa * (S / 2 - 0.03), y, -ca * (S / 2 - 0.03)), "paint_green", 0.004, rot=(0, a, 0))
    box("DoorHandle", (0.03, 0.22, 0.04), (S / 2 - 0.12, 1.15, -S / 2 - 0.02), "brass", 0.008)
    # Roof with the lit TELEFON signs on all four sides, and snow.
    box("Roof", (S + 0.12, 0.12, S + 0.12), (0, H + 0.06, 0), "paint_green", 0.02)
    lathe("Dome", [(0.0, H + 0.12), (S * 0.62, H + 0.12), (S * 0.5, H + 0.2), (0.0, H + 0.28)], (0, 0, 0), "paint_green", segs=4)
    for o in hdlib._parts[-1:]:
        o.data.transform(g_matrix((0, 0, 0), (0, math.pi / 4, 0)))
    for k in range(4):
        a = k * math.pi / 2
        ca, sa = math.cos(a), math.sin(a)
        sign = box("Sign", (S * 0.7, 0.13, 0.01), (sa * (S / 2 + 0.065), H - 0.08, -ca * (S / 2 + 0.065)), "panel_lit", 0.0, rot=(0, a, 0))
        text_on("SignText", "TELEFON", sign, (sa * (S / 2 + 0.075), H - 0.08, -ca * (S / 2 + 0.075)), 0.075, "poster_ink",
                lift=0.0012, inward=(-sa, 0, ca))
    snow_box("Snow", (S + 0.06, 0.06, S + 0.06), (0, H + 0.14, 0))
    snow_box("DomeSnow", (S * 0.6, 0.05, S * 0.6), (0, H + 0.22, 0))
    # Inside: the telephone on the back wall, its handset on the hook, a directory shelf.
    box("PhoneBox", (0.22, 0.3, 0.12), (0, 1.45, S / 2 - 0.1), "paint_black", 0.01)
    tube("Handset", [(-0.13, 1.45, S / 2 - 0.13), (-0.13, 1.6, S / 2 - 0.13)], 0.018, "bakelite", 8)
    tube("Cord", [(-0.1, 1.38, S / 2 - 0.08), (-0.14, 1.3, S / 2 - 0.12), (-0.13, 1.43, S / 2 - 0.13)], 0.005, "bakelite", 5, bend=0.03)
    box("Coins", (0.06, 0.1, 0.03), (0.06, 1.53, S / 2 - 0.175), "brass", 0.004)
    box("Shelf", (0.5, 0.025, 0.22), (0, 1.05, S / 2 - 0.14), "wood_dark", 0.004)
    box("Directory", (0.22, 0.05, 0.16), (0.08, 1.09, S / 2 - 0.14), "poster_c", 0.006)


# ————— advertising column —————

POSTERS = [("CINEMA\nTONIGHT", "poster_b", "poster_cream"), ("RAILWAY\nTIMETABLE\n1936", "poster_cream", "poster_ink"),
           ("THEATRE", "poster_c", "poster_cream"), ("FIREMEN'S\nBALL", "poster_a", "poster_ink"),
           ("SHOES", "poster_b", "poster_cream"), ("WINTER\nSPORTS", "poster_c", "poster_cream")]


@asset
def poster_pillar():
    seed(104)
    R, H = 0.55, 2.7
    lathe("Base", [(0.0, 0.0), (R + 0.1, 0.0), (R + 0.1, 0.12), (R + 0.04, 0.18), (R, 0.22)], (0, 0, 0), "paint_green", segs=48)
    col = lathe("Column", [(R, 0.22), (R, H)], (0, 0, 0), "poster_cream", segs=48, cap_bottom=False, cap_top=False)
    lathe("Cornice", [(R, H), (R + 0.08, H + 0.04), (R + 0.12, H + 0.12), (R + 0.1, H + 0.16), (R + 0.02, H + 0.18)],
          (0, 0, 0), "paint_green", segs=48, cap_bottom=False)
    lathe("Dome", [(R + 0.02, H + 0.18), (R * 0.85, H + 0.36), (R * 0.45, H + 0.55), (0.1, H + 0.66), (0.0, H + 0.68)], (0, 0, 0),
          "paint_green", segs=32)
    sphere("Finial", 0.07, (0, H + 0.76, 0), "paint_green", segs=16, rings=8)
    lathe("DomeSnow", [(R * 0.95, H + 0.24), (R * 0.75, H + 0.42), (R * 0.35, H + 0.6), (0.0, H + 0.7)], (0, 0, 0), "snow", segs=24)
    lathe("RimSnow", [(R + 0.02, H + 0.17), (R + 0.11, H + 0.165), (R + 0.1, H + 0.2), (R * 0.95, H + 0.25)], (0, 0, 0), "snow", segs=32,
          cap_bottom=False, cap_top=False)
    # Posters: curved sheets round the column, each with its big lettering.
    n = len(POSTERS)
    for i, (txt, paper, ink) in enumerate(POSTERS):
        a0 = math.tau * i / n + 0.06
        a1 = math.tau * (i + 1) / n - 0.06
        y0 = 0.45 + (i % 2) * 0.25
        y1 = y0 + 1.5
        bm = bmesh.new()
        rows = []
        segs = 8
        for j in range(segs + 1):
            a = a0 + (a1 - a0) * j / segs
            rr = R + 0.004
            rows.append((bm.verts.new(G(math.sin(a) * rr, y0, -math.cos(a) * rr)), bm.verts.new(G(math.sin(a) * rr, y1, -math.cos(a) * rr))))
        for j in range(segs):
            bm.faces.new((rows[j][0], rows[j + 1][0], rows[j + 1][1], rows[j][1]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.normal_update()
        hdlib._box_uv(bm, paper, "x", hdlib._rng)
        sheet = hdlib._new_obj("Poster", bm, paper, 0.0, smooth=True)
        am = (a0 + a1) / 2
        text_on("PosterText", txt, sheet, (math.sin(am) * (R + 0.2), (y0 + y1) / 2 + 0.2, -math.cos(am) * (R + 0.2)), 0.13, ink,
                lift=0.0015, inward=(-math.sin(am), 0, math.cos(am)))


# ————— litter bin —————

@asset
def waste_bin():
    seed(105)
    lathe("Foot", [(0.0, 0.0), (0.12, 0.0), (0.12, 0.03), (0.05, 0.08), (0.04, 0.1)], (0, 0, 0), "paint_green", segs=16)
    cyl("Post", 0.035, 1.05, (0, 0.6, 0), "paint_green", segs=12)
    sphere("PostTop", 0.045, (0, 1.14, 0), "paint_green", segs=12, rings=6)
    tube("Hoop", [(0, 0.95, 0), (0, 0.95, -0.08)], 0.015, "paint_green", 8)
    torus("Ring", 0.17, 0.012, (0, 0.95, -0.25), "paint_green", segs=32, rsegs=6)
    lathe("Bin", [(0.0, 0.42), (0.14, 0.42), (0.16, 0.5), (0.165, 0.95), (0.155, 0.95), (0.15, 0.5), (0.0, 0.44)], (0, 0.0, -0.25),
          "galvanized", segs=32, cap_top=False)
    torus("Rim", 0.163, 0.008, (0, 0.95, -0.25), "galvanized", segs=32, rsegs=6)
    lathe("Snow", [(0.15, 0.9), (0.12, 0.96), (0.0, 0.98)], (0, 0, -0.25), "snow", segs=24, cap_bottom=False)


# ————— yard gate —————

@asset
def gate_pier():
    seed(106)
    box("Footing", (0.72, 0.2, 0.72), (0, 0.1, 0), "stone_cap", 0.02)
    box("Pier", (0.6, 2.3, 0.6), (0, 0.2 + 1.15, 0), "brick", 0.01, 2, grain="x")
    box("Band", (0.66, 0.12, 0.66), (0, 1.6, 0), "stone_cap", 0.01)
    box("Cap", (0.76, 0.12, 0.76), (0, 2.56, 0), "stone_cap", 0.02)
    lathe("CapTop", [(0.0, 2.62), (0.34, 2.62), (0.0, 2.8)], (0, 0, 0), "stone_cap", segs=4)
    for o in hdlib._parts[-1:]:
        o.data.transform(g_matrix((0, 0, 0), (0, math.pi / 4, 0)))
    snow_box("CapSnow", (0.7, 0.06, 0.7), (0, 2.66, 0))
    # Lantern on a short column.
    cyl("LampColumn", 0.05, 0.25, (0, 2.9, 0), "paint_black", segs=12)
    box("LampSeat", (0.2, 0.03, 0.2), (0, 3.03, 0), "paint_black", 0.005)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        tube("LampFrame", [(math.cos(a) * 0.09, 3.04, math.sin(a) * 0.09), (math.cos(a) * 0.13, 3.34, math.sin(a) * 0.13)], 0.008,
             "paint_black", 6)
    lathe("LampGlass", [(0.08, 3.05), (0.115, 3.34)], (0, 0, 0), "panel_lit", segs=4)
    lathe("LampRoof", [(0.17, 3.34), (0.0, 3.46)], (0, 0, 0), "paint_black", segs=4)
    snow_box("LampSnow", (0.16, 0.03, 0.16), (0, 3.42, 0))


@asset
def iron_gate():
    meshes, k = import_ph("large_iron_gate", (3.0, 0, 0.12))
    decimate(meshes, 0.4)


@asset
def power_box():
    meshes, k = import_ph("power_box_01", (0.42, 0, 0.42), origin="back")
    decimate(meshes, 0.35)


@asset
def utility_box_a():
    meshes, k = import_ph("utility_box_01", (0.52, 1.12, 0))
    snow_box("Snow", (0.5, 0.04, 0.42), (0, 1.14, 0))


@asset
def utility_box_b():
    meshes, k = import_ph("utility_box_02", (0.92, 1.12, 0))
    snow_box("Snow", (0.9, 0.04, 0.42), (0, 1.14, 0))


@asset
def fire_hydrant():
    meshes, k = import_ph("fire_hydrant", (0, 0.8, 0), drop=["aged"])
    decimate(meshes, 0.08)


@asset
def covered_car():
    meshes, k = import_ph("covered_car", (1.8, 0, 4.4))


@asset
def picnic_table():
    meshes, k = import_ph("wooden_picnic_table", (0, 0.75, 2.2), yaw=math.pi / 2)
    decimate(meshes, 0.5)
    snow_box("Snow", (1.6, 0.03, 0.7), (0, 0.765, 0))


# ————— statues on plinths —————

def plinth(w, h, d, text):
    box("PlinthFoot", (w + 0.3, 0.25, d + 0.3), (0, 0.125, 0), "stone_cap", 0.02)
    box("PlinthStep", (w + 0.15, 0.2, d + 0.15), (0, 0.35, 0), "stone_cap", 0.02)
    die = box("PlinthDie", (w, h - 0.75, d), (0, 0.45 + (h - 0.75) / 2, 0), "stone_cap", 0.02)
    box("PlinthCap", (w + 0.16, 0.3, d + 0.16), (0, h - 0.15, 0), "stone_cap", 0.03)
    snow_box("StepSnow", (w + 0.25, 0.04, d + 0.25), (0, 0.27, 0))
    snow_box("CapSnow", (w + 0.1, 0.05, d + 0.1), (0, h + 0.01, 0))
    tab = box("Tablet", (w * 0.6, 0.4, 0.02), (0, 0.45 + (h - 0.75) / 2, -d / 2 - 0.01), "brass", 0.005)
    text_on("Inscription", text, tab, (0, 0.45 + (h - 0.75) / 2, -d / 2 - 0.05), 0.12, "poster_ink", lift=0.0015)


@asset
def statue_horse():
    seed(107)
    plinth(1.2, 2.0, 0.9, "1918")
    meshes, k = import_ph("horse_statue_01", (0, 2.4, 0), yaw=math.pi / 2)
    decimate(meshes, 0.5)
    for o in meshes:
        o.data.transform(g_matrix((0, 2.0, 0)))


@asset
def statue_gothic():
    seed(108)
    plinth(0.9, 1.6, 0.9, "ST. WENCESLAS")
    meshes, k = import_ph("gothic_statue", (0, 1.9, 0))
    decimate(meshes, 0.5)
    for o in meshes:
        o.data.transform(g_matrix((0, 1.6, 0)))


# ————— playground —————

@asset
def swing_set():
    seed(110)
    L, H = 3.2, 2.3
    for sx in (-1, 1):
        x = sx * L / 2
        for sz in (-1, 1):
            tube("Leg", [(x, 0.0, sz * 0.75), (x, H, 0.0)], 0.04, "play_blue", 10)
        tube("Brace", [(x, 0.8, -0.5), (x, 0.8, 0.5)], 0.025, "play_blue", 8)
    tube("Beam", [(-L / 2 - 0.1, H, 0), (L / 2 + 0.1, H, 0)], 0.05, "play_blue", 12)
    snow_box("BeamSnow", (L + 0.1, 0.03, 0.07), (0, H + 0.05, 0))
    for sx in (-1, 1):
        x = sx * L / 4
        for dx in (-0.2, 0.2):
            tube("Chain", [(x + dx, H - 0.02, 0), (x + dx, 0.48, 0)], 0.008, "steel", 6)
        box("Seat", (0.48, 0.04, 0.2), (x, 0.46, 0), "pine", 0.008)
        snow_box("SeatSnow", (0.44, 0.03, 0.16), (x, 0.495, 0))


@asset
def slide():
    seed(111)
    H = 1.8
    # Ladder at +Z, platform, chute running down toward -Z.
    for sx in (-1, 1):
        tube("Rail", [(sx * 0.28, 0.0, 1.2), (sx * 0.28, H + 0.9, 0.45)], 0.03, "play_red", 8)
        tube("Post", [(sx * 0.28, 0.0, 0.3), (sx * 0.28, H + 0.9, 0.3)], 0.03, "play_red", 8)
        tube("Guard", [(sx * 0.28, H + 0.6, 0.45), (sx * 0.28, H + 0.6, 0.0), (sx * 0.24, H + 0.35, -0.2)], 0.022, "play_red", 8, bend=0.1)
    for k in range(7):
        t = (k + 0.5) / 7
        z = 1.2 - 0.75 * t
        y = (H + 0.9) * t * 0.95
        tube("Rung", [(-0.28, y, z), (0.28, y, z)], 0.018, "steel", 6)
    box("Platform", (0.6, 0.05, 0.5), (0, H, 0.5), "pine", 0.008)
    snow_box("PlatformSnow", (0.55, 0.04, 0.45), (0, H + 0.04, 0.5))
    # Chute: a trough from the platform down to the ground.
    bm = bmesh.new()
    rows = []
    n = 14
    for i in range(n + 1):
        t = i / n
        z = 0.25 - 2.6 * t
        y = H - (H - 0.3) * (t * t * (3 - 2 * t)) + (0.0 if t < 0.9 else 0.0)
        ring = []
        for j in range(7):
            a = math.pi * j / 6
            ring.append(bm.verts.new(G(-math.cos(a) * 0.27, y - math.sin(a) * 0.08 + (0.12 if j in (0, 6) else 0.0), z)))
        rows.append(ring)
    for i in range(n):
        for j in range(6):
            bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.015)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, "galvanized", "z", hdlib._rng)
    hdlib._new_obj("Chute", bm, "galvanized", 0.0, smooth=True, angle=50.0)
    for sx in (-1, 1):
        tube("ChuteLeg", [(sx * 0.25, 0.0, -1.9), (sx * 0.25, 0.42, -1.9)], 0.025, "play_red", 8)
        tube("ChuteLeg", [(sx * 0.25, 0.0, -0.9), (sx * 0.25, 1.1, -0.9)], 0.025, "play_red", 8)


@asset
def seesaw():
    seed(112)
    box("PivotBase", (0.3, 0.45, 0.4), (0, 0.225, 0), "play_yellow", 0.03)
    cyl("Pivot", 0.05, 0.5, (0, 0.5, 0), "steel_dark", axis=(0, 0, 1), segs=16)
    n0 = count()
    box("Board", (3.0, 0.06, 0.26), (0, 0.0, 0), "pine", 0.01)
    for sx in (-1, 1):
        tube("Handle", [(sx * 1.2, 0.03, -0.1), (sx * 1.2, 0.3, -0.1), (sx * 1.2, 0.3, 0.1), (sx * 1.2, 0.03, 0.1)], 0.02, "play_red", 8,
             bend=0.05)
        box("Seat", (0.35, 0.04, 0.26), (sx * 1.35, 0.05, 0), "play_red", 0.01)
    snow_box("BoardSnow", (2.9, 0.03, 0.22), (0, 0.045, 0))
    transform_since(n0, (0, 0.55, 0), (0, 0, 0.16))


@asset
def roundabout():
    seed(113)
    cyl("Hub", 0.15, 0.3, (0, 0.15, 0), "steel_dark", segs=16)
    lathe("Deck", [(0.0, 0.3), (1.0, 0.3), (1.0, 0.36), (0.0, 0.36)], (0, 0, 0), "play_yellow", segs=48)
    for k in range(6):
        a = math.tau * k / 6
        tube("Bar", [(math.cos(a) * 0.95, 0.36, math.sin(a) * 0.95), (math.cos(a) * 0.95, 0.85, math.sin(a) * 0.95),
                     (math.cos(a) * 0.2, 0.95, math.sin(a) * 0.2)], 0.022, "play_red", 8, bend=0.15)
    torus("HandRing", 0.2, 0.025, (0, 0.95, 0), "play_red", segs=24, rsegs=8)
    lathe("DeckSnow", [(0.0, 0.36), (0.95, 0.36), (0.9, 0.4), (0.0, 0.41)], (0, 0, 0), "snow", segs=32)


@asset
def sandbox():
    seed(114)
    L = 2.4
    for k in range(4):
        a = k * math.pi / 2
        box("Edge", (L, 0.3, 0.12), (math.sin(a) * (L / 2 - 0.06), 0.15, -math.cos(a) * (L / 2 - 0.06)), "pine", 0.01, rot=(0, a, 0))
        box("Seat", (L - 0.05, 0.04, 0.22), (math.sin(a) * (L / 2 - 0.08), 0.32, -math.cos(a) * (L / 2 - 0.08)), "pine", 0.008,
            rot=(0, a, 0))
    box("Sand", (L - 0.24, 0.16, L - 0.24), (0, 0.1, 0), "sand", 0.0)
    snow_box("Snow", (L - 0.26, 0.08, L - 0.26), (0, 0.2, 0))
    # A forgotten bucket and spade.
    lathe("Bucket", [(0.0, 0.0), (0.07, 0.0), (0.09, 0.14), (0.085, 0.14), (0.065, 0.01), (0.0, 0.01)], (0.4, 0.22, -0.3), "play_red", segs=16)
    tube("Spade", [(0.55, 0.25, -0.1), (0.75, 0.3, 0.1)], 0.01, "play_blue", 6)


@asset
def climbing_frame():
    seed(115)
    S, H = 1.8, 1.8
    n = 3
    step = S / n
    for i in range(n + 1):
        for j in range(n + 1):
            x, z = -S / 2 + i * step, -S / 2 + j * step
            if i in (0, n) or j in (0, n):
                tube("Upright", [(x, 0.0, z), (x, H, z)], 0.025, "play_red" if (i + j) % 2 else "play_blue", 8)
    for level in range(1, 4):
        y = level * H / 3
        for i in range(n + 1):
            x = -S / 2 + i * step
            tube("BarX", [(x, y, -S / 2), (x, y, S / 2)], 0.02, "steel", 6)
            tube("BarZ", [(-S / 2, y, x), (S / 2, y, x)], 0.02, "steel", 6)
    snow_box("TopSnow", (S * 0.9, 0.03, S * 0.9), (0, H + 0.03, 0))


# ————— station back entrance —————

FLOOR = 0.92          # building floor above the yard


@asset
def station_entrance():
    """The town-side entrance of a station building: stone steps and landing up to the floor
    (FLOOR above the ground), handrails, a stone door surround with a glazed double door and a lit
    transom, the name plate, a lantern and a glass canopy on tie rods. Origin on the ground at the
    wall below the door, the wall at z = 0, the steps toward -Z."""
    seed(116)
    W = 2.6
    land = 1.2
    n = 5
    rise = FLOOR / n
    box("Landing", (W, FLOOR, land), (0, FLOOR / 2, -land / 2), "stone_cap", 0.02)
    for k in range(1, n):
        h = FLOOR - k * rise
        box("Step", (W, h, 0.32), (0, h / 2, -land - (k - 0.5) * 0.3), "stone_cap", 0.015)
        snow_box("StepSnow", (W - 0.5, 0.02, 0.12), (0, h + 0.01, -land - (k - 0.5) * 0.3 - 0.08))
    snow_box("LandingSnow", (W - 0.3, 0.025, 0.4), (0, FLOOR + 0.01, -land + 0.25))
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.08)
        z_foot = -land - (n - 1) * 0.3
        tube("Handrail", [(x, 0.9, z_foot), (x, FLOOR + 0.9, -land + 0.05), (x, FLOOR + 0.9, -0.15)], 0.022, "paint_black", 8, bend=0.1)
        for zz, yy in ((z_foot, 0.0), (-land - 0.6, FLOOR - 2 * rise), (-land + 0.05, FLOOR), (-0.15, FLOOR)):
            tube("Baluster", [(x, yy, zz), (x, yy + 0.9 + (FLOOR - yy) * 0.0, zz)], 0.016, "paint_black", 6)
    # Door surround, double door and transom.
    y0 = FLOOR
    dw, dh = 1.5, 2.3
    for sx in (-1, 1):
        box("Jamb", (0.25, dh + 0.55, 0.12), (sx * (dw / 2 + 0.125), y0 + (dh + 0.55) / 2, -0.06), "stone_cap", 0.01, grain="y")
    box("Lintel", (dw + 0.7, 0.3, 0.16), (0, y0 + dh + 0.6, -0.08), "stone_cap", 0.015)
    box("Transom", (dw, 0.5, 0.03), (0, y0 + dh + 0.25, -0.03), "panel_lit", 0.0)
    box("TransomBar", (dw, 0.05, 0.05), (0, y0 + dh, -0.05), "wood_dark", 0.005)
    # Both leaves stand open (swung out against the stone jambs), so the way into the hall is clear.
    for sx in (-1, 1):
        n0 = count()
        cx = sx * dw / 4 - sx * dw / 2                   # built round the hinge at x = sx * dw / 2
        box("Leaf", (dw / 2 - 0.01, dh, 0.05), (cx, y0 + dh / 2, -0.05), "wood_dark", 0.008, grain="y")
        box("LeafGlass", (dw / 2 - 0.2, dh * 0.42, 0.01), (cx, y0 + dh * 0.68, -0.078), "glass", 0.0)
        for k in range(1, 3):
            box("GlazingBar", (dw / 2 - 0.2, 0.025, 0.02), (cx, y0 + dh * 0.47 + k * dh * 0.14, -0.085), "wood_dark", 0.004)
        box("LowerPanel", (dw / 2 - 0.2, dh * 0.3, 0.012), (cx, y0 + dh * 0.22, -0.08), "wood_dark", 0.006, grain="y")
        px = sx * 0.07 - sx * dw / 2
        tube("Pull", [(px, y0 + 1.0, -0.075), (px, y0 + 1.0, -0.11), (px, y0 + 1.25, -0.11), (px, y0 + 1.25, -0.075)],
             0.012, "brass", 8, bend=0.02)
        transform_since(n0, (sx * dw / 2, 0, -0.03), (0, -sx * math.pi / 2, 0))
    # Name plate over the door.
    pl = box("NamePlate", (1.6, 0.32, 0.02), (0, y0 + dh + 0.98, -0.07), "enamel_blue", 0.006)
    text_on("NameText", "STATION", pl, (0, y0 + dh + 0.98, -0.12), 0.2, "poster_cream", lift=0.0015)
    # Glass canopy on two tie rods, and its snow.
    cy = y0 + dh + 1.3
    for sx in (-1, 1):
        tube("CanopyArm", [(sx * 1.2, cy, -0.02), (sx * 1.2, cy - 0.05, -1.5)], 0.03, "steel_dark", 8)
        tube("TieRod", [(sx * 1.2, cy + 0.9, -0.02), (sx * 1.2, cy, -1.45)], 0.012, "steel_dark", 6)
        box("RodPlate", (0.14, 0.14, 0.02), (sx * 1.2, cy + 0.9, -0.01), "steel_dark", 0.004)
    tube("CanopyFront", [(-1.25, cy - 0.05, -1.5), (1.25, cy - 0.05, -1.5)], 0.03, "steel_dark", 8)
    box("CanopyGlass", (2.4, 0.015, 1.45), (0, cy - 0.01, -0.76), "glass", 0.0, rot=(-0.035, 0, 0))
    snow_box("CanopySnow", (2.3, 0.05, 1.35), (0, cy + 0.03, -0.76), rot=(-0.035, 0, 0))
    # Lantern on a bracket beside the door.
    tube("LampBracket", [(1.25, y0 + 2.3, -0.02), (1.25, y0 + 2.3, -0.35), (1.25, y0 + 2.2, -0.4)], 0.015, "paint_black", 6, bend=0.05)
    lathe("LampGlass", [(0.07, y0 + 1.9), (0.1, y0 + 2.15)], (1.25, 0, -0.4), "panel_lit", segs=4)
    lathe("LampRoof", [(0.14, y0 + 2.15), (0.0, y0 + 2.25)], (1.25, 0, -0.4), "paint_black", segs=4)


VIEWS = {"station_entrance": (0.8, 0.5, -1.0), "substation": (1.0, 0.6, -1.0), "phone_booth": (0.7, 0.4, -1.0), "statue_horse": (0.9, 0.4, -1.0),
         "statue_gothic": (0.6, 0.3, -1.0), "slide": (1.0, 0.5, 0.6), "iron_gate": (0.3, 0.2, -1.0)}
