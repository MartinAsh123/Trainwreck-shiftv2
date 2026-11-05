"""Mail & parcels van props. Godot-space coordinates matching mail_van.gd's frames."""
import math
import hdlib
from hdlib import *
from assets_crew import bail_pull, knob, screw, raised_panel, escutcheon

hdlib.MATS.update({"stencil_ink": dict(color=(0.05, 0.03, 0.015), rough=0.95)})

A = {}


def asset(fn):
    A[fn.__name__] = fn
    return fn


def h01(k, salt):
    return (math.sin(k * 12.9898 + salt * 78.233) * 43758.5453) % 1.0


DESK_D = 0.62
DESK_H = 0.82


def letter(name, cx, cy, cz, w, h, key, tilt=0.0, yaw=0.0):
    """An envelope standing on edge: thin paper slab with a darker flap line."""
    box(name, (w, h, 0.003), (cx, cy + h / 2, cz), key, 0.0008, 1, rot=(tilt, yaw, 0))


@asset
def sorting_desk():
    """Sorting desk with the pigeonhole frame (default sorting office: 3.3 m long, 16 x 7 cells)."""
    seed(31)
    w, cols, rows = 3.3, 16, 7
    # Desk: plinth, carcass, sloped top with a lip, cupboard doors.
    box("Plinth", (w - 0.04, 0.08, DESK_D - 0.06), (0, 0.04, -(DESK_D - 0.06) / 2 - 0.02), "wood_darkstain", 0.004)
    box("Carcass", (w, DESK_H - 0.1, DESK_D - 0.04), (0, 0.08 + (DESK_H - 0.12) / 2, -(DESK_D - 0.04) / 2), "wood", 0.004)
    box("Top", (w + 0.04, 0.035, DESK_D), (0, DESK_H - 0.0175, -DESK_D / 2), "wood", 0.006, 3, rot=(math.radians(-3.0), 0, 0))
    box("TopLip", (w + 0.04, 0.03, 0.022), (0, DESK_H + 0.005, -DESK_D + 0.011), "wood", 0.006)
    doors = int(w / 0.6)
    for i in range(doors):
        x = -w / 2 + (i + 0.5) * w / doors
        raised_panel("DeskDoor%d" % i, x, 0.09 + (DESK_H - 0.22) / 2 + 0.02, -DESK_D + 0.02, w / doors - 0.03, DESK_H - 0.24, "wood", 0.014, 0.05)
        knob("DeskKnob%d" % i, x + w / doors * 0.36, 0.5, -DESK_D + 0.005, 0.011)
    # Pigeonholes.
    y0, h, d, zb = DESK_H + 0.02, 1.06, 0.3, -0.085
    box("PigeonBack", (w, h, 0.012), (0, y0 + h / 2, zb - 0.006), "wood_darkstain", 0.002, grain="y")
    cw, ch = w / cols, h / rows
    for i in range(cols + 1):
        x = -w / 2 + i * cw
        box("Upright", (0.012 if i % 4 else 0.024, h, d), (x, y0 + h / 2, zb - d / 2), "wood", 0.002, grain="y")
    for j in range(rows + 1):
        y = y0 + j * ch
        box("Shelf", (w, 0.01 if 0 < j < rows else 0.024, d), (0, y, zb - d / 2), "wood", 0.002)
    for k, (dw, hh) in enumerate(((0.02, 0.025), (0.04, 0.02), (0.06, 0.03))):
        box("Cornice", (w + dw, hh, d + dw * 0.6), (0, y0 + h + 0.012 + k * 0.024, zb - d / 2 - dw * 0.15), "wood" if k != 1 else "wood_darkstain", 0.004)
    for j in range(rows):
        for i in range(cols):
            x = -w / 2 + (i + 0.5) * cw
            y = y0 + j * ch
            box("LabelStrip", (cw * 0.55, 0.016, 0.0025), (x, y + 0.013, zb - d - 0.0015), "brass", 0.0006)
            box("LabelCard", (cw * 0.45, 0.01, 0.001), (x, y + 0.013, zb - d - 0.0032), "paper", 0.0)
            hs = h01(i * 31 + j * 7, 3.7)
            if hs > 0.45:
                for k in range(1 + int(hs * 4.0)):
                    lw = cw * (0.68 + 0.1 * h01(k, hs))
                    lh = ch * (0.55 + 0.2 * h01(k + 2, hs))
                    letter("Letter", x + (h01(k, i) - 0.5) * 0.01, y + 0.006, zb - 0.03 - k * 0.012, lw, lh,
                           "paper" if (k + i) % 3 else "paper_aged", math.radians(-12.0 - 4.0 * k), (h01(k + 5, j) - 0.5) * 0.08)


@asset
def letter_table():
    seed(32)
    w, h, d = 2.9, 0.74, 0.5
    box("TableTop", (w, 0.035, d), (0, h - 0.0175, -d / 2), "wood", 0.006, 3)
    for sx in (-1, 1):
        for sz in (0.06, d - 0.06):
            turned = [(0, 0), (0.024, 0), (0.026, 0.02), (0.02, 0.06), (0.024, 0.3), (0.028, 0.5), (0.026, 0.62), (0.03, h - 0.08),
                      (0.03, h - 0.035), (0, h - 0.035)]
            lathe("Leg", turned, (sx * (w / 2 - 0.06), 0, -sz), "wood", segs=24)
    box("Rail", (w - 0.12, 0.08, 0.022), (0, h - 0.075, -d + 0.07), "wood", 0.004)
    box("RailBack", (w - 0.12, 0.08, 0.022), (0, h - 0.075, -0.07), "wood", 0.004)
    for sx in (-1, 1):
        box("RailEnd", (0.022, 0.08, d - 0.14), (sx * (w / 2 - 0.06), h - 0.075, -d / 2), "wood", 0.004, grain="z")
    trays = int(w / 0.42)
    for i in range(trays):
        x = -w / 2 + (i + 0.5) * w / trays
        n0 = count()
        box("TrayBase", (0.34, 0.01, 0.26), (0, 0.005, 0), "wood_dark", 0.002)
        for sx in (-1, 1):
            box("TraySide", (0.012, 0.07, 0.26), (sx * 0.164, 0.035, 0), "wood_dark", 0.003, grain="z")
        for sz in (-1, 1):
            box("TrayEnd", (0.34, 0.07, 0.012), (0, 0.035, sz * 0.124), "wood_dark", 0.003)
        cnt = 10 + i * 3
        for k in range(cnt):
            letter("Letter", (h01(k, i) - 0.5) * 0.02, 0.01, -0.11 + k * (0.22 / cnt), 0.29 + 0.02 * h01(k, 2.0), 0.09 + 0.03 * h01(k, 4.0),
                   "paper" if (k + i) % 4 else "paper_aged", math.radians(-8.0 - 6 * h01(k, 9.0)), 0.0)
        transform_since(n0, (x, h, -d / 2), (0, (h01(i, 1.1) - 0.5) * 0.1, 0))


@asset
def letter_scale():
    seed(33)
    box("Base", (0.22, 0.03, 0.12), (0, 0.015, 0), "wood", 0.006, 3)
    cyl("Column", 0.008, 0.17, (0.06, 0.115, 0), "brass", segs=20)
    lathe("Pan", [(0, 0), (0.05, 0), (0.06, 0.012), (0.058, 0.014), (0, 0.004)], (-0.05, 0.075, 0), "brass", segs=48)
    tube("Arm", [(0.06, 0.17, 0), (0.0, 0.15, 0), (-0.05, 0.09, 0), (-0.05, 0.075, 0)], 0.004, "brass", 10, bend=0.02)
    lathe("DialCase", [(0, 0), (0.05, 0), (0.05, 0.012), (0.046, 0.014), (0, 0.014)], (0.06, 0.21, 0.004), "brass", axis=(0, 0, -1), segs=48)
    disc("Dial", 0.044, (0.06, 0.21, -0.0105), "dial_station")
    box("Needle", (0.002, 0.034, 0.001), (0.06, 0.222, -0.012), "black_paint_gloss", 0.0, rot=(0, 0, -0.5))


@asset
def date_stamp():
    seed(34)
    box("InkPadTin", (0.12, 0.018, 0.08), (0.09, 0.009, 0), "galvanized", 0.004)
    box("InkPad", (0.104, 0.002, 0.064), (0.09, 0.0185, 0), "felt_navy", 0.0)
    box("StampFoot", (0.06, 0.022, 0.04), (0, 0.011, 0), "iron", 0.003)
    box("StampRubber", (0.056, 0.006, 0.036), (0, 0.003, 0), "rubber", 0.001)
    lathe("Handle", [(0, 0.022), (0.016, 0.022), (0.013, 0.04), (0.012, 0.08), (0.02, 0.1), (0.024, 0.115), (0.02, 0.13),
                     (0.01, 0.14), (0, 0.142)], (0, 0, 0), "wood_dark", segs=32)


@asset
def string_ball():
    seed(35)
    sphere("Core", 0.04, (0, 0.042, 0), "string", segs=24, rings=12)
    for k in range(26):
        a = k * 2.4
        b = k * 0.71
        pts = []
        for i in range(25):
            t = math.tau * i / 24
            v = Vector((math.cos(t), math.sin(t) * math.cos(a), math.sin(t) * math.sin(a)))
            v.rotate(Euler((b, a * 0.3, 0)))
            pts.append(tuple(v * 0.0425 + Vector((0, 0.042, 0))))
        tube("Wrap", pts, 0.0016, "string", 4, caps=False)
    tube("LooseEnd", [(0.035, 0.03, 0.02), (0.07, 0.006, 0.04), (0.11, 0.002, 0.03)], 0.0016, "string", 5, bend=0.02)


def bundle(h, key):
    box("Bundle", (0.16, h, 0.1), (0, h / 2, 0), key, 0.002)
    for k in range(int(h / 0.004)):
        box("Edge", (0.161, 0.0008, 0.101), (0, 0.002 + k * 0.004, 0), "paper_aged", 0.0)
    box("TwineA", (0.164, h + 0.004, 0.004), (0, h / 2, 0), "string", 0.0015)
    box("TwineB", (0.004, h + 0.004, 0.104), (0.02, h / 2, 0), "string", 0.0015)
    sphere("Knot", 0.006, (0.02, h + 0.002, 0), "string")


@asset
def letter_bundle_a():
    seed(36)
    bundle(0.03, "paper")


@asset
def letter_bundle_b():
    seed(37)
    bundle(0.045, "paper_aged")


@asset
def letter_bundle_c():
    seed(38)
    bundle(0.06, "paper")


def hanging_bag(cx, cy, cz, k):
    """Canvas mail bag hanging open from a hook at (cx, cy, cz): a leather-bound mouth pulled up at
    the back where the hook takes it, slack canvas falling in folds from the mouth, the bottom
    filled out (and lumpy) with the letters and packets in it, a side seam, and a few envelopes
    standing up out of the mouth."""
    seed(80 + k)
    rng = hdlib._rng
    key = "canvas" if k % 2 == 0 else "canvas_dark"
    hgt = 0.75
    prof = [(0.0, -hgt - 0.045), (0.09, -hgt - 0.04), (0.16, -hgt - 0.01), (0.205, -hgt + 0.06), (0.212, -hgt + 0.2),
            (0.2, -0.42), (0.175, -0.26), (0.155, -0.14), (0.15, -0.05), (0.15, 0.0)]
    obj = lathe("Bag", prof, (0, 0, 0), key, segs=64, cap_top=False)
    ph = [rng.uniform(0, 6.3) for _ in range(4)]
    for v in obj.data.vertices:
        gx, gy, gz = v.co.x, v.co.z, -v.co.y
        ang = math.atan2(gz, gx)
        d = -gy / hgt                                          # 0 at the mouth, 1 at the bottom
        slack = max(0.0, 1.0 - d * 1.6)                        # folds where the canvas hangs empty
        full = max(0.0, (d - 0.5) * 2.0)                       # lumps where it's filled
        f = 1.0 + 0.2 * slack * (0.5 - abs(math.sin(ang * 3.5 + ph[0] + d * 2.5)))             + 0.05 * slack * math.sin(ang * 8 + ph[1])             + 0.07 * full * math.sin(ang * 3 + ph[2] + gy * 6) * math.sin(gy * 11 + ph[3])
        gx, gz = gx * f * 0.86, gz * f * 0.85
        gz -= 0.03 * min(1.0, d * 2.0)                         # sags away from the wall
        gy += 0.035 * (1.0 - min(1.0, d * 5.0)) * (math.sin(ang) + 1.0) * 0.5   # mouth higher at the back
        v.co.x, v.co.y, v.co.z = gx, -gz, gy
    n0 = count()
    # The leather-bound mouth, oval and lifted at the back like the canvas.
    m = lathe("Mouth", [(0.15, -0.035), (0.162, -0.03), (0.165, 0.0), (0.16, 0.012), (0.146, 0.012), (0.142, -0.035)], (0, 0, 0),
              "leather", segs=48)
    if m is not None:
        for v in m.data.vertices:
            gx, gy, gz = v.co.x, v.co.z, -v.co.y
            ang = math.atan2(gz, gx)
            gx *= 0.86
            gz *= 0.85
            gy += 0.035 * (math.sin(ang) + 1.0) * 0.5
            v.co.x, v.co.y, v.co.z = gx, -gz, gy
    for a in range(6):
        t = math.tau * a / 6
        lathe("Eyelet", [(0.006, -0.003), (0.0075, 0), (0.006, 0.003)],
              (math.cos(t) * 0.168 * 0.86, -0.015 + 0.035 * (math.sin(t) + 1.0) * 0.5, math.sin(t) * 0.168 * 0.85),
              "brass", axis=(math.cos(t), 0, math.sin(t)), segs=12, cap_bottom=False, cap_top=False)
    # Side seam down the canvas.
    tube("Seam", [(0.131, -0.02, 0.0), (0.14, -0.25, 0.0), (0.173, -0.45, -0.02), (0.177, -0.68, -0.03)], 0.003, key, 6, bend=0.02)
    # Envelopes standing up out of the mouth.
    for e in range(3 + k % 3):
        x = rng.uniform(-0.06, 0.06)
        z = rng.uniform(-0.05, 0.03)
        box("Envelope", (0.16, 0.1, 0.002), (x, -0.02 + rng.uniform(0, 0.03), z), "paper" if e % 3 else "paper_aged", 0.0005,
            rot=(rng.uniform(-0.35, 0.35), rng.uniform(-0.6, 0.6), rng.uniform(-0.25, 0.25)))
    # The stencilled owner's mark, painted on the canvas.
    text_on("Stencil", "G.C.R.\nMAILS\n%d" % (k + 1), obj, (0.0, -0.36, 0.0), 0.058, "stencil_ink")
    transform_since(n0 - 1, (cx, cy, cz), (0, 0, 0))

@asset
def bag_rack():
    """Rack on the partition (frame: wall at z = 0, -Z out), 0.925 m wide, three bags hanging."""
    seed(39)
    w, rail_y = 0.925, 1.6
    for sx in (-1, 1):
        lathe("Foot", [(0, 0), (0.04, 0), (0.04, 0.01), (0.02, 0.025), (0, 0.025)], (sx * w / 2, 0, -0.28), "iron", segs=24)
        cyl("Post", 0.014, rail_y + 0.05, (sx * w / 2, (rail_y + 0.05) / 2, -0.28), "steel_dark", segs=20)
        sphere("Finial", 0.022, (sx * w / 2, rail_y + 0.07, -0.28), "brass")
        tube("Stay", [(sx * w / 2, rail_y, -0.28), (sx * w / 2, rail_y, -0.01)], 0.01, "steel_dark", 12)
        lathe("Rose", [(0, 0), (0.03, 0), (0.028, 0.006), (0, 0.008)], (sx * w / 2, rail_y, 0), "brass", axis=(0, 0, -1), segs=24)
    tube("Rail", [(-w / 2, rail_y, -0.28), (w / 2, rail_y, -0.28)], 0.012, "steel_dark", 16)
    for i in range(3):
        x = -w / 2 + (i + 0.5) * w / 3
        tube("Hook", [(x, rail_y + 0.012, -0.28), (x, rail_y - 0.04, -0.28), (x, rail_y - 0.07, -0.3)], 0.004, "brass", 10, bend=0.015)
        hanging_bag(x, rail_y - 0.07, -0.3, i)


@asset
def mail_sack():
    """Closed, tied mail sack lying down; origin at its centre (as the GDScript places it)."""
    seed(40)
    obj = sphere("Sack", 0.5, (0, 0, 0), "canvas", (0.6, 0.32, 0.4), 40, 20)
    for v in obj.data.vertices:
        gx, gy, gz = v.co.x, v.co.z, -v.co.y
        # Flatten the underside, gather the neck end (+X) and add lumpy folds.
        if gy < -0.07:
            gy = -0.07 - (gy + 0.07) * 0.25
        t = max(0.0, gx / 0.3)
        k = 1.0 - 0.55 * t ** 3
        gy *= k
        gz *= k
        n = 1.0 + 0.04 * math.sin(gx * 23 + gz * 17) * math.sin(gy * 19)
        v.co.x, v.co.y, v.co.z = gx * n, -gz * n, gy * n
    lathe("Neck", [(0.0, 0.0), (0.05, 0.0), (0.035, 0.05), (0.045, 0.1), (0.06, 0.14), (0.04, 0.16), (0.0, 0.16)], (0.27, 0.0, 0), "canvas",
          axis=(1, 0, 0), segs=24)
    torus("Tie", 0.036, 0.006, (0.31, 0.0, 0), "string", axis=(1, 0, 0), segs=24, rsegs=8)
    box("Seal", (0.004, 0.03, 0.03), (0.32, -0.04, 0), "paint_red", 0.002)
    box("Tag", (0.002, 0.07, 0.045), (0.33, -0.09, 0.0), "paper_aged", 0.001)


def parcel(w, h, d, key, label=True):
    box("Parcel", (w, h, d), (0, h / 2, 0), key, 0.012, 3)
    # Folded paper ends and string both ways with a knot on top.
    box("FoldEnd", (0.003, h * 0.7, d * 0.55), (w / 2 + 0.0005, h * 0.45, 0), key, 0.0)
    box("FoldEnd", (0.003, h * 0.7, d * 0.55), (-w / 2 - 0.0005, h * 0.45, 0), key, 0.0)
    for s in (-1, 1):
        box("StringA", (w + 0.006, 0.004, 0.004), (0, h + 0.001, 0), "string", 0.0015)
        box("StringA", (0.004, h + 0.004, 0.004), (s * (w / 2 + 0.0015), h / 2, 0), "string", 0.0015)
        box("StringB", (0.004, 0.004, d + 0.006), (0.0, h + 0.001, 0), "string", 0.0015)
        box("StringB", (0.004, h + 0.004, 0.004), (0, h / 2, s * (d / 2 + 0.0015)), "string", 0.0015)
    sphere("Knot", 0.008, (0, h + 0.004, 0), "string")
    if label:
        plane("Label", (w * 0.42, d * 0.36), (w * 0.2, h + 0.0035, -d * 0.18), "parcel_label", normal="y")
        box("Seal", (0.018, 0.003, 0.018), (-w * 0.25, h + 0.002, d * 0.2), "paint_red", 0.001)


@asset
def parcel_a():
    seed(41)
    parcel(0.42, 0.3, 0.32, "kraft")


@asset
def parcel_b():
    seed(42)
    parcel(0.3, 0.2, 0.24, "kraft_dark")


@asset
def parcel_c():
    seed(43)
    parcel(0.36, 0.18, 0.26, "kraft")


@asset
def parcel_rack():
    """Slatted parcel rack, 1.2 m wide (frame: wall at z = 0, -Z out), loaded with parcels."""
    seed(44)
    w, d, h = 1.2, 0.55, 1.75
    for sx in (-1, 1):
        for sz in (0.03, d - 0.03):
            box("Post", (0.05, h, 0.05), (sx * (w / 2 - 0.025), h / 2, -sz), "pine_dark", 0.004, grain="y")
        for y in (0.3, 1.25):
            box("SideRail", (0.03, 0.05, d - 0.05), (sx * (w / 2 - 0.025), y, -d / 2), "pine_dark", 0.004, grain="z")
    for y in (0.08, 0.62, 1.16, 1.7):
        for k in range(5):
            box("Slat", (w, 0.022, d / 5 - 0.02), (0, y, -0.02 - (k + 0.5) * d / 5), "pine", 0.003)
        box("Bearer", (w - 0.08, 0.04, 0.03), (0, y - 0.03, -0.04), "pine_dark", 0.003)
        box("Bearer", (w - 0.08, 0.04, 0.03), (0, y - 0.03, -d + 0.04), "pine_dark", 0.003)
        for sx in (-1, 1):
            for sz in (0.03, d - 0.03):
                screw("Bolt", sx * (w / 2 - 0.025), y - 0.03, -sz - 0.026, 0.006, key="steel_dark")
    for si, y in enumerate((0.08, 0.62, 1.16)):
        x = -w / 2 + 0.12
        idx = si * 5
        while x < w / 2 - 0.12:
            sz = Vector((0.18 + 0.2 * h01(idx, 2.0), 0.12 + 0.24 * h01(idx, 5.0), 0.2 + 0.25 * h01(idx, 7.0)))
            sz.x = min(sz.x, w / 2 - 0.06 - x)
            if sz.x < 0.12:
                break
            n0 = count()
            parcel(sz.x, sz.y, sz.z, "kraft" if idx % 3 != 1 else "kraft_dark", idx % 2 == 0)
            transform_since(n0, (x + sz.x / 2, y + 0.011, -0.05 - sz.z / 2), (0, (h01(idx, 9.1) - 0.5) * 0.12, 0))
            x += sz.x + 0.03
            idx += 1


@asset
def milk_churn():
    seed(45)
    prof = [(0, 0), (0.165, 0), (0.182, 0.008), (0.184, 0.035), (0.17, 0.045), (0.166, 0.06), (0.166, 0.095), (0.174, 0.1),
            (0.174, 0.12), (0.166, 0.125), (0.166, 0.48), (0.174, 0.485), (0.174, 0.51), (0.166, 0.515), (0.165, 0.54),
            (0.14, 0.6), (0.1, 0.66), (0.09, 0.69), (0.09, 0.77), (0.1, 0.78), (0.1, 0.8), (0.09, 0.8)]
    lathe("Body", prof, (0, 0, 0), "galvanized", segs=72, cap_top=False)
    lathe("Inside", [(0.088, 0.8), (0.085, 0.72), (0, 0.72)], (0, 0, 0), "galvanized", segs=48, cap_bottom=False)
    lathe("Lid", [(0, 0.79), (0.104, 0.79), (0.108, 0.8), (0.106, 0.818), (0.07, 0.83), (0.03, 0.835), (0.028, 0.85),
                  (0.022, 0.87), (0, 0.872)], (0, 0, 0), "galvanized", segs=48, cap_bottom=False)
    for sx in (-1, 1):
        tube("Handle", [(sx * 0.12, 0.6, 0), (sx * 0.17, 0.66, 0), (sx * 0.17, 0.74, 0), (sx * 0.1, 0.76, 0)], 0.009, "galvanized", 12, bend=0.03)
    box("NamePlate", (0.08, 0.04, 0.004), (0, 0.3, -0.166), "brass", 0.0015)


@asset
def steamer_trunk():
    """Green canvas steamer trunk with wood slats, leather edges, brass corners and a lock."""
    seed(46)
    w, h, d = 0.9, 0.5, 0.5
    box("Body", (w, h, d), (0, h / 2, 0), "canvas_green", 0.01, 3)
    for x in (-0.3, 0.0, 0.3):
        box("Slat", (0.05, h + 0.008, d + 0.008), (x, h / 2, 0), "wood", 0.004, grain="y")
        box("SlatTop", (0.05, 0.008, d + 0.008), (x, h + 0.004, 0), "wood", 0.003)
    box("LidEdge", (w + 0.008, 0.035, d + 0.008), (0, 0.38, 0), "leather", 0.006)
    box("BaseEdge", (w + 0.008, 0.035, d + 0.008), (0, 0.02, 0), "leather", 0.006)
    for sx in (-1, 1):
        for sy in (0, 1):
            for sz in (-1, 1):
                box("Corner", (0.07, 0.07, 0.07), (sx * (w / 2 - 0.03), (h - 0.03) if sy else 0.03, sz * (d / 2 - 0.03)), "brass", 0.014, 3)
                screw("CornerRivet", sx * (w / 2 - 0.03), (h - 0.03) if sy else 0.03, sz * (d / 2 + 0.006) - sz * 0.0, 0.005, axis=(0, 0, sz))
    box("LockPlate", (0.07, 0.08, 0.006), (0, 0.38, -d / 2 - 0.004), "brass", 0.002)
    escutcheon("Lock", 0, 0.37, -d / 2 - 0.007, 0.9)
    for sx in (-1, 1):
        box("ClaspPlate", (0.04, 0.06, 0.005), (sx * 0.25, 0.39, -d / 2 - 0.004), "brass", 0.0015)
        tube("Handle", [(sx * (w / 2 + 0.005), 0.27, -0.08), (sx * (w / 2 + 0.03), 0.27, -0.06), (sx * (w / 2 + 0.03), 0.27, 0.06),
                        (sx * (w / 2 + 0.005), 0.27, 0.08)], 0.008, "leather", 10, bend=0.02)


def suitcase(w, h, d, key):
    box("Shell", (w, h, d), (0, h / 2, 0), key, 0.025, 4)
    box("Seam", (w + 0.003, 0.006, d + 0.003), (0, h * 0.55, 0), "leather_black", 0.002)
    for sx in (-1, 1):
        for sz in (-1, 1):
            sphere("Corner", 0.028, (sx * (w / 2 - 0.02), h / 2, sz * (d / 2 - 0.02)), "leather_black", (1, h / 0.07, 1), 16, 8)
        box("Latch", (0.035, 0.03, 0.008), (sx * w * 0.28, h * 0.55, -d / 2 - 0.004), "brass", 0.002)
    tube("Handle", [(-0.05, h * 0.55, -d / 2 - 0.004), (-0.05, h * 0.55, -d / 2 - 0.03), (0.05, h * 0.55, -d / 2 - 0.03),
                    (0.05, h * 0.55, -d / 2 - 0.004)], 0.008, "leather", 10, bend=0.015)
    for sx in (-1, 1):
        box("Strap", (0.025, h + 0.004, d + 0.004), (sx * w * 0.3, h / 2, 0), "leather", 0.003)
        box("Buckle", (0.03, 0.035, 0.006), (sx * w * 0.3, h * 0.7, -d / 2 - 0.004), "brass", 0.0015)


@asset
def luggage():
    """Steamer trunk with two suitcases on top; origin = bottom centre of the trunk."""
    seed(47)
    steamer_trunk()
    n0 = count()
    suitcase(0.62, 0.17, 0.4, "leather")
    transform_since(n0, (0.05, 0.5, 0.0), (0, 0.12, 0))
    n0 = count()
    suitcase(0.48, 0.14, 0.32, "leather_black")
    transform_since(n0, (-0.05, 0.67, 0.02), (0, -0.2, 0))


@asset
def sack_truck():
    """Two-wheeled sack truck leaning on the wall (frame: wall at z = 0, -Z out)."""
    seed(48)
    n0 = count()
    for sx in (-1, 1):
        tube("Rail", [(sx * 0.2, 0.06, 0), (sx * 0.2, 0.12, 0), (sx * 0.17, 1.25, 0), (sx * 0.2, 1.33, 0.06)], 0.016, "handle", 14, bend=0.06)
        tube("Grip", [(sx * 0.2, 1.33, 0.06), (sx * 0.21, 1.36, 0.1)], 0.019, "leather_black", 14)
        # Spoked iron wheel with a rubber tyre.
        torus("Tyre", 0.105, 0.018, (sx * 0.27, 0.12, 0.05), "rubber", axis=(1, 0, 0), segs=48, rsegs=12)
        torus("Rim", 0.088, 0.008, (sx * 0.27, 0.12, 0.05), "iron", axis=(1, 0, 0), segs=48, rsegs=8)
        for k in range(8):
            a = math.tau * k / 8
            tube("Spoke", [(sx * 0.27, 0.12, 0.05), (sx * 0.27, 0.12 + math.sin(a) * 0.088, 0.05 + math.cos(a) * 0.088)], 0.005, "iron", 6)
        cyl("Hub", 0.022, 0.05, (sx * 0.27, 0.12, 0.05), "iron", axis=(1, 0, 0), segs=24)
    for y in (0.4, 0.75, 1.05):
        tube("Rung", [(-0.19, y, 0), (0.19, y, 0)], 0.009, "steel_dark", 12)
    extrude("Toe", [(-0.21, 0), (0.21, 0), (0.2, 0.2), (-0.2, 0.2)], 0.012, "steel_dark", (0, 0.04, -0.09), rot=(math.pi / 2, 0, 0), bevel=0.003)
    for sx in (-1, 1):
        tube("ToeStay", [(sx * 0.19, 0.04, 0.0), (sx * 0.19, 0.04, -0.19)], 0.008, "steel_dark", 10)
    tube("Axle", [(-0.27, 0.12, 0.05), (0.27, 0.12, 0.05)], 0.012, "steel_dark", 16)
    transform_since(n0, (0, 0, -0.22), (math.radians(-14.0), 0, 0))


@asset
def platform_scale():
    """Platform weighing machine (frame: wall at z = 0, -Z out)."""
    seed(49)
    n0 = count()
    box("Platform", (0.6, 0.12, 0.5), (0, 0.06, 0), "iron_green", 0.012, 3)
    box("Deck", (0.56, 0.012, 0.46), (0, 0.125, 0), "pine_dark", 0.003)
    for k in range(9):
        box("DeckRib", (0.55, 0.004, 0.012), (0, 0.133, -0.2 + k * 0.05), "iron", 0.001)
    for sx in (-1, 1):
        for sz in (-1, 1):
            cyl("Wheel", 0.03, 0.02, (sx * 0.27, 0.03, sz * 0.2), "iron", axis=(1, 0, 0), segs=20)
    lathe("Column", [(0, 0), (0.07, 0), (0.06, 0.03), (0.045, 0.1), (0.04, 0.85), (0.05, 0.9), (0.05, 0.95), (0, 0.95)],
          (0, 0.12, 0.27), "iron_green", segs=32)
    box("Head", (0.12, 0.1, 0.1), (0, 1.07, 0.27), "iron_green", 0.01)
    box("Beam", (0.52, 0.03, 0.03), (0, 1.05, 0.22), "brass", 0.004)
    for k in range(11):
        box("BeamTick", (0.002, 0.012, 0.002), (-0.2 + k * 0.04, 1.06, 0.204), "black_paint_gloss", 0.0)
    box("Poise", (0.05, 0.06, 0.05), (0.08, 1.05, 0.22), "steel_dark", 0.006)
    tube("Hanger", [(-0.24, 1.05, 0.22), (-0.24, 0.92, 0.22)], 0.004, "brass", 8)
    for k in range(3):
        lathe("Weight", [(0, 0), (0.035 - k * 0.006, 0), (0.035 - k * 0.006, 0.02), (0.01, 0.02), (0.01, 0.026), (0, 0.026)],
              (-0.24, 0.88 - k * 0.022, 0.22), "brass", segs=32)
    box("MakerPlate", (0.14, 0.05, 0.004), (0, 0.75, 0.205), "brass", 0.0015)
    transform_since(n0, (0, 0, -0.35))


@asset
def cage_bench():
    """Slatted bench in the holding cage, 2.2 m long (frame: wall at z = 0, -Z out)."""
    seed(50)
    w, h = 2.2, 0.45
    for k in range(4):
        box("SeatSlat", (w, 0.025, 0.08), (0, h, -0.05 - k * 0.095), "pine", 0.004)
    for k in range(2):
        box("BackSlat", (w, 0.08, 0.025), (0, 0.62 + k * 0.14, -0.02), "pine", 0.004)
    for sx in (-1, 0, 1):
        x = sx * (w / 2 - 0.1)
        box("Bracket", (0.03, h, 0.03), (x, h / 2, -0.35), "iron", 0.003, grain="y")
        tube("Stay", [(x, h - 0.02, -0.38), (x, 0.15, -0.01)], 0.01, "iron", 12)
        box("SeatBearer", (0.03, 0.04, 0.38), (x, h - 0.033, -0.19), "iron", 0.003, grain="z")
        box("WallPlate", (0.06, 0.4, 0.008), (x, 0.65, -0.004), "iron", 0.002, grain="y")
        for k in range(4):
            screw("SlatBolt", x, h + 0.0125, -0.05 - k * 0.095, 0.006, axis=(0, 1, 0), key="steel_dark")


@asset
def pail():
    seed(51)
    lathe("Pail", [(0, 0), (0.105, 0), (0.11, 0.006), (0.13, 0.25), (0.136, 0.26), (0.13, 0.262), (0.124, 0.255), (0.104, 0.012), (0, 0.012)],
          (0, 0, 0), "galvanized", segs=64, cap_top=False)
    for y in (0.08, 0.17):
        torus("Rib", 0.11 + y * 0.075, 0.003, (0, y, 0), "galvanized", segs=64, rsegs=6)
    tube("Bail", [(-0.135, 0.22, 0), (-0.12, 0.38, 0.0), (0.0, 0.43, 0.0), (0.12, 0.38, 0), (0.135, 0.22, 0)], 0.004, "steel_dark", 8, bend=0.08)
    for sx in (-1, 1):
        sphere("Ear", 0.012, (sx * 0.133, 0.22, 0), "galvanized", (0.5, 1, 1), 12, 6)


@asset
def sorting_stool():
    import_ph("wooden_stool_01", (0.36, 0.66, 0.36), origin="bottom", yaw=0.0)


@asset
def crate_a():
    import_ph("wooden_crate_01", (0.55, 0.42, 0.45), origin="bottom", yaw=0.0)


@asset
def crate_b():
    import_ph("wooden_crate_02", (0.45, 0.32, 0.4), origin="bottom", yaw=0.0)
