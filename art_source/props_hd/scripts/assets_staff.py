"""The car's STAFF ONLY cabinet fittings: the electrical switchboard and the heating control.

Only the fixed parts are modelled here; the moving and lit parts (toggle levers, lamp lenses, gauge
dials and needles, the thermostat knob, buttons and display) are added in Godot by
scripts/train/staff_panel.gd at the positions in SB_* / TH_* below, so the two must stay in step.

Frames: back on the cabinet's back board at z = 0, the face toward -Z (the room), origin at the
centre of the board. Positions are given as seen from the room (u to the right, v up); in Godot
space x = -u.
"""
import math
import hdlib
from hdlib import *
from assets_crew import screw

A = {}


def asset(fn):
    A[fn.__name__] = fn
    return fn


hdlib.MATS.update({
    "engrave": dict(color=(0.03, 0.025, 0.02), rough=0.6),
})

# ————— switchboard —————
SB_W, SB_H, SB_T = 0.56, 0.46, 0.012
SB_GAUGES = [(-0.175, 0.105, 0.06), (0.0, 0.105, 0.06), (0.175, 0.105, 0.06), (-0.09, -0.02, 0.05), (0.09, -0.02, 0.05)]
SB_LAMP_V = -0.1
SB_TOGGLE_V = -0.163
SB_COLS = [-0.2 + 0.08 * i for i in range(6)]
SB_NAMES = ["MAIN", "VESTIBULE", "W.C.", "NIGHT", "HEATING", "FANS"]


def P(u, v, z):
    """View coordinates (u right, v up as seen from the room) -> Godot."""
    return (-u, v, z)


def plate_with_text(name, text, u, v, w, h, z, size, key="brass"):
    """A small engraved plate standing on the board at depth z (its back), lettered in black."""
    pl = box(name, (w, h, 0.0016), P(u, v, z - 0.0008), key, 0.0004)
    text_on(name + "Text", text, pl, P(u, v, z - 0.0016), size, "engrave", lift=0.0003)
    for su in (-1, 1):
        cyl(name + "Pin", 0.0012, 0.0008, P(u + su * (w / 2 - 0.004), v, z - 0.0018), "brass", axis=(0, 0, -1), segs=8)


@asset
def staff_switchboard():
    seed(90)
    zf = -SB_T
    box("Board", (SB_W, SB_H, SB_T), (0, 0, -SB_T / 2), "black_paint_gloss", 0.004, 3)
    # Brass edge beading and corner screws.
    for sv in (-1, 1):
        box("Bead", (SB_W + 0.008, 0.008, 0.006), (0, sv * (SB_H / 2 + 0.002), zf + 0.002), "brass", 0.002)
    for su in (-1, 1):
        box("Bead", (0.008, SB_H + 0.008, 0.006), (su * (SB_W / 2 + 0.002), 0, zf + 0.002), "brass", 0.002)
    for su in (-1, 1):
        for sv in (-1, 1):
            screw("CornerScrew", su * (SB_W / 2 - 0.016), sv * (SB_H / 2 - 0.016), zf, 0.005, axis=(0, 0, -1), key="brass")
    plate_with_text("Title", "CAR ELECTRICAL SUPPLY", 0.0, 0.2, 0.3, 0.026, zf, 0.016)
    # (The gauges are the shared HD gauge_case, placed in Godot at SB_GAUGES.)
    # Indicator lamp holders: a knurled brass bezel round a hole for the lens.
    for i, u in enumerate(SB_COLS):
        lathe("LampBezel", [(0.008, 0.0), (0.0145, 0.0), (0.0155, 0.004), (0.014, 0.008), (0.0105, 0.009), (0.0095, 0.004)],
              P(u, SB_LAMP_V, zf), "brass", axis=(0, 0, -1), segs=24)
        # Toggle: a brass plate with a threaded bushing and a hex nut; the lever is added in Godot.
        box("TogglePlate", (0.026, 0.036, 0.002), P(u, SB_TOGGLE_V, zf - 0.001), "brass", 0.0006)
        cyl("ToggleNut", 0.0075, 0.004, P(u, SB_TOGGLE_V, zf - 0.004), "steel", axis=(0, 0, -1), segs=6)
        cyl("ToggleBush", 0.0045, 0.006, P(u, SB_TOGGLE_V, zf - 0.009), "steel", axis=(0, 0, -1), segs=16)
        for sv in (-1, 1):
            cyl("ToggleScrew", 0.0016, 0.001, P(u, SB_TOGGLE_V + sv * 0.0135, zf - 0.0025), "steel", axis=(0, 0, -1), segs=8)
        plate_with_text("Label", SB_NAMES[i], u, -0.2, 0.066, 0.016, zf, 0.0105)
        # "ON" engraved above the lever's up position.
        plate_with_text("OnPlate", "ON", u, SB_TOGGLE_V + 0.027, 0.02, 0.009, zf, 0.0065)


# ————— heating control —————
TH_W, TH_H, TH_D = 0.2, 0.3, 0.045
TH_DISPLAY = (0.0, 0.078, 0.13, 0.062)          # u, v, w, h
TH_KNOB = (0.0, -0.025, 0.036)                  # u, v, r
TH_BUTTONS_V = -0.105
TH_BUTTONS_U = [-0.052, 0.0, 0.052]
TH_MODES = ["HEAT", "FAN", "OFF"]


@asset
def staff_thermostat():
    seed(91)
    zf = -TH_D
    house = box("Housing", (TH_W, TH_H, TH_D), (0, 0, -TH_D / 2), "enamel_white", 0.012, 4)
    box("BackPlate", (TH_W + 0.02, TH_H + 0.02, 0.006), (0, 0, -0.003), "steel_dark", 0.002)
    for su in (-1, 1):
        for sv in (-1, 1):
            screw("PlateScrew", su * (TH_W / 2 + 0.005), sv * (TH_H / 2 + 0.005), -0.006, 0.0035, axis=(0, 0, -1), key="steel")
    # Display: a chromed bezel round a dark window (the reading is drawn in Godot).
    u, v, w, h = TH_DISPLAY
    for sv in (-1, 1):
        box("DisplayBezel", (w + 0.012, 0.006, 0.004), P(u, v + sv * (h / 2 + 0.003), zf - 0.002), "steel", 0.0015)
    for su in (-1, 1):
        box("DisplayBezel", (0.006, h + 0.012, 0.004), P(u + su * (w / 2 + 0.003), v, zf - 0.002), "steel", 0.0015)
    box("DisplayWindow", (w, h, 0.002), P(u, v, zf - 0.0005), "ink", 0.0)
    # Knob boss with a scale of ticks round it (16-26 degrees over 270 degrees of travel).
    ku, kv, kr = TH_KNOB
    lathe("KnobBoss", [(0.0, 0.0), (kr + 0.008, 0.0), (kr + 0.008, 0.002), (0.0, 0.002)], P(ku, kv, zf), "steel", axis=(0, 0, -1), segs=48)
    for k in range(11):
        a = math.radians(-135 + 27 * k)
        long = k % 5 == 0
        r0, r1 = kr + 0.011, kr + (0.019 if long else 0.015)
        c = ((r0 + r1) / 2) * math.sin(a), ((r0 + r1) / 2) * math.cos(a)
        box("Tick", (0.0016, r1 - r0, 0.0006), P(ku + c[0], kv + c[1], zf - 0.0003), "engrave", 0.0, rot=(0, 0, a))
    text_on("Cold", "16", house, P(ku - 0.044, kv - 0.04, zf), 0.011, "engrave", lift=0.0004)
    text_on("Hot", "26", house, P(ku + 0.044, kv - 0.04, zf), 0.011, "engrave", lift=0.0004)
    text_on("Title", "HEATING  CONTROL", house, P(0.0, 0.132, zf), 0.012, "engrave", lift=0.0004)
    # Push-button sockets and their names.
    for i, bu in enumerate(TH_BUTTONS_U):
        for sv in (-1, 1):
            box("ButtonBezel", (0.036, 0.004, 0.004), P(bu, TH_BUTTONS_V + sv * 0.016, zf - 0.002), "steel", 0.0012)
        for su in (-1, 1):
            box("ButtonBezel", (0.004, 0.036, 0.004), P(bu + su * 0.016, TH_BUTTONS_V, zf - 0.002), "steel", 0.0012)
        text_on("Mode", TH_MODES[i], house, P(bu, TH_BUTTONS_V - 0.03, zf), 0.0105, "engrave", lift=0.0004)


VIEWS = {"staff_switchboard": (0.0, 0.15, -1.0), "staff_thermostat": (0.25, 0.15, -1.0)}
