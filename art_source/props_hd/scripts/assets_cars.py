"""HD parked cars: 1930s Czechoslovak road vehicles, built smooth (lofted bodies under a
subdivision surface), with real glass set into the greenhouse, chrome frames, grille, bumpers and
lamps, door seams and handles, number plates, pressed-steel wheels with treaded tyres, seats,
dashboard and steering wheel inside, and snow on the roof, bonnet and wings.
    car_sedan_hd     - four-door saloon (Tatra 57 / Praga Piccolo type), separate wings, running boards
    car_streamline_hd - fastback streamliner with the dorsal fin and three headlamps (Tatra 77 type)
    car_small_hd     - small two-door (Aero 30 / Škoda Popular type)
    van_hd           - delivery van with a box body lettered for the dairy
GODOT space: forward is -Z, up +Y, origin on the ground under the middle of the wheelbase.
The body paint is material "car_paint": the game recolours it per car. Right-hand drive (the
country drove on the left until 1939).
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
    "car_paint": dict(color=(0.05, 0.05, 0.055), rough=0.22, coat=True),
    "car_paint_b": dict(color=(0.75, 0.68, 0.5), rough=0.3, coat=True),
    "chrome": dict(color=(0.86, 0.86, 0.86), rough=0.06, metal=1.0),
    "car_glass": dict(color=(0.04, 0.05, 0.06), rough=0.03, alpha=0.5),
    "lamp_glass": dict(color=(0.9, 0.9, 0.85), rough=0.05),
    "tail_glass": dict(color=(0.5, 0.03, 0.02), rough=0.1),
    "lamp_lit": dict(color=(1.0, 0.95, 0.82), rough=0.05, emit=(1.0, 0.88, 0.62), emit_k=6.0),
    "tail_lit": dict(color=(0.6, 0.04, 0.02), rough=0.1, emit=(1.0, 0.06, 0.02), emit_k=3.0),
    "seam": dict(color=(0.01, 0.01, 0.01), rough=0.6),
    "tyre": dict(tex="rubber", scale=0.3),
    "wheel_paint": dict(color=(0.6, 0.55, 0.42), rough=0.35, coat=True),
    "plate_white": dict(color=(0.9, 0.9, 0.86), rough=0.4),
    "plate_ink": dict(color=(0.02, 0.02, 0.02), rough=0.5),
    "car_snow": dict(tex="snow", scale=1.0),
    "upholstery": dict(tex="leather_brown", scale=0.4),
    "dash_wood": dict(tex="wood_furniture", scale=0.5),
    "van_letter": dict(color=(0.92, 0.88, 0.75), rough=0.5),
})


# ————— lofted bodies —————

def _catmull(p0, p1, p2, p3, t):
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def smooth_stations(st, steps=3):
    out = []
    n = len(st)
    for i in range(n - 1):
        a, b = st[max(i - 1, 0)], st[i]
        c, d = st[i + 1], st[min(i + 2, n - 1)]
        for k in range(steps):
            t = k / steps
            out.append(tuple(_catmull(a[j], b[j], c[j], d[j], t) for j in range(4)))
    out.append(st[-1])
    return out


def section(hw, yb, yt, belt, n, power=4.0, tumble=0.16, flat=1.6):
    """(x, y) round a car body: a superellipse, flatter at the bottom, drawn in above the belt."""
    mid = (yb + yt) * 0.5
    hh = (yt - yb) * 0.5
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        p = power if s >= 0 else power * flat
        x = hw * math.copysign(abs(c) ** (2 / p), c)
        y = mid + hh * math.copysign(abs(s) ** (2 / p), s)
        if y > belt:
            k = min(1.0, (y - belt) / max(yt - belt, 1e-3))
            x *= 1.0 - tumble * k * k
        pts.append((x, y))
    return pts


def loft(name, stations, key, belt, n=28, power=4.0, tumble=0.16, sub=1):
    """Body through stations (z, hw, yb, yt) - smoothed - with fan caps at both ends, under a
    subdivision surface (applied here, so details can be projected onto the final shape)."""
    st = smooth_stations(stations, 4)
    bm = bmesh.new()
    rings = []
    for (z, hw, yb, yt) in st:
        rings.append([bm.verts.new(G(x, y, z)) for (x, y) in section(hw, yb, yt, belt, n, power, tumble)])
    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    for ring in (rings[0], rings[-1]):
        c = bm.verts.new(sum((v.co for v in ring), Vector()) / len(ring))
        for i in range(n):
            bm.faces.new((ring[i], ring[(i + 1) % n], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, key, "z", hdlib._rng)
    o = hdlib._new_obj(name, bm, key, 0.0, smooth=True, angle=180.0)
    md = o.modifiers.new("Sub", "SUBSURF")
    md.levels = sub
    md.render_levels = sub
    hdlib._apply_modifiers([o])
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def _hit(body, p, d):
    """Ray from Godot point p along Godot direction d onto `body`: (point, outward normal) in Godot."""
    gp, gd = G(*p), G(*d)
    ok, loc, nrm, _ = body.ray_cast(gp, gd)
    if not ok:
        return None, None
    if nrm.dot(gd) > 0:
        nrm = -nrm
    return Vector((loc.x, loc.z, -loc.y)), Vector((nrm.x, nrm.z, -nrm.y)).normalized()


def pane(name, body, corners, d, key="car_glass", frame="chrome", lift=0.004, nu=10, nv=5, frame_r=0.008):
    """A window set into the body: the quad `corners` (4 Godot points outside the body, in order)
    is subdivided and each point cast along d onto the body; the glass lies `lift` proud of the
    paint (on the curve), the chrome frame runs round its edge."""
    bm = bmesh.new()
    grid = []
    for j in range(nv + 1):
        row = []
        v = j / nv
        for i in range(nu + 1):
            u = i / nu
            a = corners[0].lerp(corners[1], u)
            b = corners[3].lerp(corners[2], u)
            p = a.lerp(b, v)
            loc, nrm = _hit(body, p, d)
            if loc is None:
                row.append(None)
                continue
            q = loc + nrm * lift
            row.append(bm.verts.new(G(*q)))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            q = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
            if all(q):
                bm.faces.new(q)
    border = [grid[0][i] for i in range(nu + 1)] + [grid[j][nu] for j in range(1, nv + 1)] + \
             [grid[nv][i] for i in range(nu - 1, -1, -1)] + [grid[j][0] for j in range(nv - 1, -1, -1)]
    pts = [Vector((v.co.x, v.co.z, -v.co.y)) for v in border if v is not None]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, key, "z", hdlib._rng)
    g = hdlib._new_obj(name, bm, key, 0.0, smooth=True, angle=180.0)
    if frame:
        if len(pts) > 3:
            tube(name + "Frame", [tuple(p) for p in pts], frame_r, frame, 6, caps=False)
    return g


def line_on(name, body, pts, d, key="seam", r=0.0025, lift=0.0015):
    """A seam or trim strip following the body: points cast along d."""
    out = []
    for p in pts:
        loc, nrm = _hit(body, Vector(p), d)
        if loc is not None:
            out.append(tuple(loc + nrm * lift))
    if len(out) > 1:
        tube(name, out, r, key, 5, caps=False)


def handle(body, p, d):
    loc, nrm = _hit(body, Vector(p), d)
    if loc is None:
        return
    c = loc + nrm * 0.02
    box("Handle", (0.012, 0.018, 0.11), tuple(c), "chrome", 0.006)
    for dz in (-0.045, 0.045):
        tube("HandlePost", [tuple(loc + Vector((0, 0, dz))), tuple(c + Vector((0, 0, dz)))], 0.006, "chrome", 6)


def snow_on(body, min_up=0.72, thick=0.03, name="Snow"):
    """A soft layer of snow on the upward faces of `body`, thinning out to its edges."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    keep = []
    for f in bm.faces:
        n = f.normal
        up = n.z                                    # Blender z = Godot up
        if up > min_up:
            keep.append(f)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    if not bm.faces:
        bm.free()
        return None
    for v in bm.verts:
        edge = any(len(e.link_faces) < 2 for e in v.link_edges)
        v.co += v.normal * (thick * (0.25 if edge else 1.0) * (0.75 + 0.5 * ((math.sin(v.co.x * 31) * math.sin(v.co.y * 17) + 1) * 0.5)))
    bm.normal_update()
    hdlib._box_uv(bm, "car_snow", "x", hdlib._rng)
    return hdlib._new_obj(name, bm, "car_snow", 0.0, smooth=True, angle=180.0)


# ————— wings, wheels, lamps, bumpers —————

def wing(name, zc, yc, R, x_in, x_out, t0, t1, tail=None, key="car_paint", crown=0.07):
    """A wing over a wheel: a crowned shell swept round the arc (angle from the front, in the
    side view) from t0 to t1, optionally running on along `tail` (Godot (z, y) points)."""
    path = []
    m = 18
    for k in range(m + 1):
        t = t0 + (t1 - t0) * k / m
        path.append((zc - R * math.cos(t), yc + R * math.sin(t), (math.cos(t), -math.sin(t))))
    for (z, y) in (tail or []):
        pz, py, _ = path[-1]
        dz, dy = z - pz, y - py
        ln = math.hypot(dz, dy) or 1.0
        path.append((z, y, (dy / ln, -dz / ln)))       # outward normal ~ perpendicular to the run
    w = x_out - x_in
    xc = (x_in + x_out) / 2
    acr = 9
    bm = bmesh.new()
    rings = []
    for (z, y, (nz, ny)) in path:
        ring = []
        for i in range(acr + 1):
            u = -1 + 2 * i / acr
            x = xc + u * w / 2
            h = 0.012 + crown * max(0.0, 1 - u * u) ** 0.5
            ring.append(bm.verts.new(G(x, y - ny * h, z - nz * h)))
        for i in range(acr, -1, -1):
            u = -1 + 2 * i / acr
            x = xc + u * w / 2
            ring.append(bm.verts.new(G(x, y + ny * 0.006, z + nz * 0.006)))
        rings.append(ring)
    nr = len(rings[0])
    for r in range(len(rings) - 1):
        for i in range(nr):
            bm.faces.new((rings[r][i], rings[r][(i + 1) % nr], rings[r + 1][(i + 1) % nr], rings[r + 1][i]))
    for ring in (rings[0], rings[-1]):
        bm.faces.new(ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, key, "z", hdlib._rng)
    o = hdlib._new_obj(name, bm, key, 0.0, smooth=True, angle=60.0)
    md = o.modifiers.new("Sub", "SUBSURF")
    md.levels = 1
    hdlib._apply_modifiers([o])
    return o


# Driving versions (the town traffic): the body without its four road wheels (the game turns
# separate wheel models) and with the lamps lit.
DRIVE = False


def lamp_key():
    return "lamp_lit" if DRIVE else "lamp_glass"


def tail_key():
    return "tail_lit" if DRIVE else "tail_glass"


def wheel(name, x, z, r, w, side, disc_key="wheel_paint"):
    """Treaded tyre, pressed-steel disc wheel, chrome hubcap and trim ring; axle along x, the
    outer face toward `side`. Left out of the driving bodies (all but the spare)."""
    if DRIVE and not name.startswith("Spare"):
        return
    c = (x, r, z)
    prof = [(r * 0.66, -w / 2), (r * 0.9, -w / 2 - 0.006), (r * 0.97, -w * 0.38)]
    for k in range(7):
        h = -w * 0.3 + k * w * 0.6 / 6
        prof.append((r if k % 2 == 0 else r - 0.008, h))
    prof += [(r * 0.97, w * 0.38), (r * 0.9, w / 2 + 0.006), (r * 0.66, w / 2)]
    lathe(name + "Tyre", prof, c, "tyre", axis=(1, 0, 0), segs=28, cap_bottom=False, cap_top=False)
    s = side
    disc = [(r * 0.66, -w * 0.45 * s), (r * 0.6, -w * 0.2 * s), (r * 0.45, w * 0.05 * s), (r * 0.3, w * 0.12 * s), (0.0, w * 0.12 * s)]
    lathe(name + "Disc", disc, c, disc_key, axis=(1, 0, 0), segs=32, cap_bottom=False, cap_top=False)
    torus(name + "Trim", r * 0.63, 0.008, (x + s * w * 0.42, r, z), "chrome", axis=(1, 0, 0), segs=36, rsegs=6)
    lathe(name + "Hubcap", [(r * 0.24, 0.0), (r * 0.22, 0.03 * s), (r * 0.12, 0.055 * s), (0.0, 0.062 * s)],
          (x + s * w * 0.12, r, z), "chrome", axis=(1, 0, 0), segs=24, cap_bottom=False)
    for k in range(5):
        a = math.tau * k / 5
        sphere(name + "Nut", 0.009, (x + s * w * 0.15, r + math.cos(a) * r * 0.32, z + math.sin(a) * r * 0.32), "chrome", segs=8, rings=4)


def headlamp(x, y, z, r=0.115, d=(0, 0, -1)):
    """Chrome bucket, glass lens with a rim, facing d."""
    lathe("LampBucket", [(0.0, -0.06), (r * 0.6, -0.05), (r * 0.95, 0.02), (r, 0.07), (r * 1.03, 0.085)], (x, y, z), "chrome",
          axis=d, segs=28, cap_top=False)
    lathe("LampLens", [(0.0, 0.1), (r * 0.6, 0.095), (r * 0.95, 0.08)], (x, y, z), lamp_key(), axis=d, segs=28, cap_bottom=False)
    torus("LampRim", r * 0.98, 0.008, (x + d[0] * 0.082, y, z + d[2] * 0.082), "chrome", axis=d, segs=28, rsegs=6)


def bumper(z, y, half, wrap, d):
    """Chrome bar bumper at z (front d = -1, rear +1), the ends wrapping back by `wrap`, overriders."""
    pts = [(-half, y, z - d * wrap), (-half + 0.08, y, z - d * 0.02), (0.0, y, z), (half - 0.08, y, z - d * 0.02), (half, y, z - d * wrap)]
    tube("Bumper", pts, 0.035, "chrome", 12, bend=0.08, radii=None)
    tube("Bumper2", [(p[0], p[1] - 0.06, p[2]) for p in pts], 0.022, "chrome", 10, bend=0.08)
    for sx in (-1, 1):
        box("Overrider", (0.05, 0.16, 0.06), (sx * half * 0.45, y - 0.02, z + d * 0.02), "chrome", 0.02)
        tube("BumperIron", [(sx * half * 0.6, y - 0.02, z - d * 0.01), (sx * half * 0.6, y - 0.02, z - d * 0.35)], 0.018, "seam", 6)


def plate(text, x, y, z, d):
    box("PlateBack", (0.37, 0.12, 0.012), (x, y, z), "plate_ink", 0.003)
    p = box("Plate", (0.35, 0.1, 0.006), (x, y, z + d * 0.006), "plate_white", 0.002)
    text_on("PlateText", text, p, (x, y, z + d * 0.06), 0.055, "plate_ink", lift=0.0008, inward=(0, 0, -d))


def interior(seat_rows, belt, x_half, dash_z, wheel_x, floor_y=0.48):
    for (z, bench) in seat_rows:
        box("Seat", (x_half * 2 - 0.12, 0.16, 0.5), (0, floor_y + 0.32, z), "upholstery", 0.05, 3)
        box("SeatBack", (x_half * 2 - 0.12, 0.55, 0.12), (0, floor_y + 0.62, z + 0.28), "upholstery", 0.05, 3, rot=(0.15, 0, 0))
    box("Dash", (x_half * 2 - 0.1, 0.2, 0.12), (0, belt + 0.02, dash_z), "dash_wood", 0.02)
    for k in range(3):
        cyl("Dial", 0.035, 0.01, (wheel_x - 0.12 + k * 0.1, belt + 0.06, dash_z + 0.065), "lamp_glass", axis=(0, 0, 1), segs=16)
    tube("Column", [(wheel_x, belt - 0.15, dash_z + 0.05), (wheel_x, belt + 0.1, dash_z + 0.3)], 0.02, "seam", 8)
    torus("SteeringWheel", 0.2, 0.014, (wheel_x, belt + 0.12, dash_z + 0.32), "bakelite",
          axis=(0, math.sin(0.9), math.cos(0.9)), segs=32, rsegs=8)
    for k in range(3):
        a = math.tau * k / 3
        tube("Spoke", [(wheel_x, belt + 0.12, dash_z + 0.32),
                       (wheel_x + math.cos(a) * 0.19, belt + 0.12 + math.sin(a) * 0.19 * math.cos(0.9), dash_z + 0.32 - math.sin(a) * 0.19 * math.sin(0.9))],
             0.008, "chrome", 5)


# ————— the cars —————

@asset
def car_sedan_hd():
    seed(200)
    belt = 1.1
    st = [(2.08, 0.5, 0.5, 0.78), (1.98, 0.7, 0.45, 0.98), (1.72, 0.77, 0.42, 1.12), (1.4, 0.79, 0.42, 1.24),
          (1.05, 0.8, 0.42, 1.46), (0.6, 0.8, 0.42, 1.58), (-0.2, 0.8, 0.42, 1.6), (-0.55, 0.79, 0.43, 1.55),
          (-0.78, 0.72, 0.45, 1.22), (-0.95, 0.46, 0.5, 1.1), (-1.6, 0.42, 0.52, 1.06), (-2.0, 0.4, 0.55, 1.02),
          (-2.05, 0.32, 0.6, 0.96)]
    body = loft("Body", st, "car_paint", belt)
    # Windows: two side panes a side with the pillar between, the quarter light, screen, back light.
    for s in (-1, 1):
        for (z0, z1, y0, y1) in ((-0.62, -0.06, 1.16, 1.5), (0.03, 0.66, 1.16, 1.52), (0.76, 1.12, 1.18, 1.42)):
            c = [Vector((s * 1.5, y0, z0)), Vector((s * 1.5, y0, z1)), Vector((s * 1.5, y1, z1)), Vector((s * 1.5, y1, z0))]
            pane("SideGlass", body, c, (-s, 0, 0))
    pane("Windscreen", body, [Vector((-0.62, 1.18, -3)), Vector((0.62, 1.18, -3)), Vector((0.62, 1.5, -3)), Vector((-0.62, 1.5, -3))],
         (0, 0, 1))
    pane("BackLight", body, [Vector((0.42, 1.28, 3)), Vector((-0.42, 1.28, 3)), Vector((-0.42, 1.46, 3)), Vector((0.42, 1.46, 3))],
         (0, 0, -1))
    # Door seams, handles, the belt moulding.
    for s in (-1, 1):
        for z in (-0.66, -0.02, 0.72):
            line_on("DoorSeam", body, [(s * 1.5, y, z) for y in (0.46, 0.7, 0.95, 1.15, 1.45, 1.55)], (-s, 0, 0))
        line_on("BeltTrim", body, [(s * 1.5, belt, z) for z in (-1.9, -1.2, -0.7, 0.0, 0.8, 1.6, 1.95)], (-s, 0, 0), "chrome", 0.006, 0.003)
        handle(body, (s * 1.5, 1.08, -0.16), (-s, 0, 0))
        handle(body, (s * 1.5, 1.08, 0.6), (-s, 0, 0))
    # Bonnet louvres.
    for s in (-1, 1):
        for k in range(6):
            line_on("Louvre", body, [(s * 1.0, y, -1.15 - k * 0.07) for y in (0.75, 0.88, 0.98)], (-s, 0, 0), "chrome", 0.004)
    # Wings and running boards.
    fz, rz, R = -1.35, 1.55, 0.36
    for s in (-1, 1):
        xi, xo = sorted((s * 0.4, s * 0.88))
        wing("FrontWing", fz, R, R + 0.07, xi, xo, -0.35, math.pi - 0.15, tail=[(-0.75, 0.56), (-0.6, 0.5)])
        xi, xo = sorted((s * 0.62, s * 0.9))
        wing("RearWing", rz, R, R + 0.07, xi, xo, 0.25, math.pi + 0.3)
        box("RunningBoard", (0.26, 0.035, 1.75), (s * 0.79, 0.5, 0.1), "seam", 0.01)
        for k in range(5):
            box("BoardRib", (0.2, 0.006, 0.01), (s * 0.79, 0.52, -0.6 + k * 0.3), "chrome", 0.0)
        wheel("Front%d" % (s + 1), s * 0.68, fz, R, 0.16, s)
        wheel("Rear%d" % (s + 1), s * 0.68, rz, R, 0.16, s)
        headlamp(s * 0.52, 1.0, -1.82)
        tube("LampBar", [(s * 0.18, 0.92, -1.95), (s * 0.48, 0.95, -1.82)], 0.012, "chrome", 6)
        box("TailLamp", (0.07, 0.1, 0.05), (s * 0.82, 0.75, 1.75), tail_key(), 0.02)
    # Grille: a chrome shield with vertical bars, the badge and the radiator cap.
    tube("GrilleSurround", [(-0.3, 0.6, -2.04), (-0.32, 0.9, -2.03), (0.0, 1.0, -2.04), (0.32, 0.9, -2.03), (0.3, 0.6, -2.04), (-0.3, 0.6, -2.04)],
         0.018, "chrome", 8, bend=0.06)
    for k in range(11):
        x = -0.25 + k * 0.05
        tube("GrilleBar", [(x, 0.62, -2.04), (x, 0.93 - abs(x) * 0.25, -2.04)], 0.006, "chrome", 5)
    sphere("Badge", 0.03, (0, 0.99, -2.05), "chrome", (1, 1, 0.4), 12, 6)
    lathe("RadCap", [(0.0, 0.0), (0.025, 0.0), (0.022, 0.03), (0.0, 0.04)], (0, 1.06, -1.97), "chrome", segs=12)
    bumper(-2.2, 0.5, 0.82, 0.12, -1)
    bumper(2.18, 0.5, 0.8, 0.1, 1)
    plate("P-24.501", 0.0, 0.62, -2.24, -1)
    plate("P-24.501", 0.0, 0.82, 2.07, 1)
    # Spare wheel on the boot.
    n0 = count()
    wheel("Spare", 0.0, 0.0, 0.33, 0.14, 1)
    transform_since(n0, (0.0, 0.5, 2.12), (0, math.pi / 2, 0))
    interior([(-0.05, True), (0.75, True)], belt, 0.72, -0.62, 0.35)
    snow_on(body)


@asset
def car_streamline_hd():
    seed(201)
    belt = 1.05
    st = [(2.55, 0.25, 0.62, 0.78), (2.45, 0.62, 0.5, 0.95), (2.1, 0.8, 0.45, 1.1), (1.5, 0.86, 0.43, 1.3),
          (0.9, 0.88, 0.42, 1.45), (0.2, 0.88, 0.42, 1.52), (-0.35, 0.86, 0.43, 1.5), (-0.7, 0.84, 0.45, 1.3),
          (-1.2, 0.8, 0.5, 1.08), (-1.75, 0.7, 0.52, 0.98), (-2.15, 0.5, 0.55, 0.88), (-2.3, 0.25, 0.6, 0.78)]
    body = loft("Body", st, "car_paint", belt, n=32, power=3.4, tumble=0.22)
    for s in (-1, 1):
        for (z0, z1, y0, y1) in ((-0.62, 0.02, 1.12, 1.42), (0.1, 0.72, 1.12, 1.44), (0.8, 1.25, 1.12, 1.34)):
            c = [Vector((s * 1.5, y0, z0)), Vector((s * 1.5, y0, z1)), Vector((s * 1.5, y1, z1)), Vector((s * 1.5, y1, z0))]
            pane("SideGlass", body, c, (-s, 0, 0))
        for z in (-0.66, 0.06, 0.76):
            line_on("DoorSeam", body, [(s * 1.5, y, z) for y in (0.5, 0.75, 1.0, 1.2, 1.42)], (-s, 0, 0))
        handle(body, (s * 1.5, 1.0, -0.12), (-s, 0, 0))
        handle(body, (s * 1.5, 1.0, 0.62), (-s, 0, 0))
        # Rear wheel spat: a skirt over the arch, its edge in chrome.
        line_on("SpatTrim", body, [(s * 1.5, 0.48 + 0.4 * math.sin(t), 1.45 - 0.42 * math.cos(t)) for t in [k * math.pi / 8 for k in range(9)]],
                (-s, 0, 0), "chrome", 0.007)
        xi, xo = sorted((s * 0.45, s * 0.9))
        wing("FrontWing", -1.45, 0.36, 0.43, xi, xo, -0.3, math.pi - 0.2, tail=[(-0.85, 0.55)], crown=0.05)
        wheel("Front%d" % (s + 1), s * 0.68, -1.45, 0.36, 0.16, s, "car_paint")
        wheel("Rear%d" % (s + 1), s * 0.7, 1.45, 0.36, 0.16, s, "car_paint")
        headlamp(s * 0.58, 0.88, -1.83, 0.1, (0, -0.2, -1))
        box("TailLamp", (0.05, 0.14, 0.05), (s * 0.55, 0.85, 2.38), tail_key(), 0.02)
        # Louvres on the engine deck.
        for k in range(8):
            line_on("Louvre", body, [(s * x, 3.0, 1.75 + k * 0.08) for x in (0.12, 0.3, 0.45)], (0, -1, 0), "seam", 0.005)
    headlamp(0.0, 0.9, -2.0, 0.09, (0, -0.15, -1))
    pane("Windscreen", body, [Vector((-0.66, 1.12, -3)), Vector((0.66, 1.12, -3)), Vector((0.66, 1.42, -3)), Vector((-0.66, 1.42, -3))],
         (0, 0, 1))
    # The dorsal fin along the tail.
    fin = [(0.9, 1.45), (1.4, 1.42), (2.1, 1.25), (2.45, 1.05), (2.5, 1.0), (2.2, 1.0), (1.4, 1.2)]
    bm = bmesh.new()
    vs = [bm.verts.new(G(0.0, y, z)) for z, y in fin]
    f = bm.faces.new(vs)
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.03)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    hdlib._box_uv(bm, "car_paint", "z", hdlib._rng)
    hdlib._new_obj("Fin", bm, "car_paint", 0.006, 2)
    line_on("NoseTrim", body, [(0, 3.0, z) for z in (-2.2, -1.9, -1.5, -1.0)], (0, -1, 0), "chrome", 0.006)
    bumper(-2.38, 0.55, 0.75, 0.15, -1)
    bumper(2.6, 0.55, 0.7, 0.15, 1)
    plate("P-31.770", 0.0, 0.66, -2.43, -1)
    plate("P-31.770", 0.0, 0.66, 2.62, 1)
    interior([(-0.1, True), (0.7, True)], belt, 0.75, -0.65, 0.38)
    snow_on(body)


@asset
def car_small_hd():
    seed(202)
    belt = 1.0
    st = [(1.72, 0.45, 0.5, 0.82), (1.6, 0.66, 0.46, 1.1), (1.3, 0.71, 0.44, 1.32), (0.95, 0.72, 0.44, 1.46),
          (0.3, 0.72, 0.44, 1.5), (-0.2, 0.71, 0.45, 1.46), (-0.38, 0.65, 0.47, 1.12), (-0.55, 0.42, 0.5, 1.0),
          (-1.2, 0.38, 0.52, 0.96), (-1.6, 0.35, 0.55, 0.92), (-1.66, 0.28, 0.6, 0.86)]
    body = loft("Body", st, "car_paint", belt)
    for s in (-1, 1):
        for (z0, z1, y0, y1) in ((-0.28, 0.55, 1.06, 1.4), (0.62, 1.05, 1.08, 1.34)):
            c = [Vector((s * 1.5, y0, z0)), Vector((s * 1.5, y0, z1)), Vector((s * 1.5, y1, z1)), Vector((s * 1.5, y1, z0))]
            pane("SideGlass", body, c, (-s, 0, 0))
        for z in (-0.33, 0.6):
            line_on("DoorSeam", body, [(s * 1.5, y, z) for y in (0.46, 0.7, 0.95, 1.1, 1.38)], (-s, 0, 0))
        handle(body, (s * 1.5, 0.98, 0.5), (-s, 0, 0))
        xi, xo = sorted((s * 0.34, s * 0.8))
        wing("FrontWing", -1.15, 0.32, 0.39, xi, xo, -0.3, math.pi - 0.15, tail=[(-0.55, 0.53)])
        xi, xo = sorted((s * 0.55, s * 0.82))
        wing("RearWing", 1.25, 0.32, 0.39, xi, xo, 0.2, math.pi + 0.25)
        box("RunningBoard", (0.22, 0.03, 1.3), (s * 0.7, 0.48, 0.05), "seam", 0.01)
        wheel("Front%d" % (s + 1), s * 0.6, -1.15, 0.32, 0.13, s)
        wheel("Rear%d" % (s + 1), s * 0.6, 1.25, 0.32, 0.13, s)
        headlamp(s * 0.45, 0.92, -1.5, 0.1)
        box("TailLamp", (0.06, 0.08, 0.05), (s * 0.72, 0.72, 1.45), tail_key(), 0.02)
    pane("Windscreen", body, [Vector((-0.56, 1.06, -3)), Vector((0.56, 1.06, -3)), Vector((0.56, 1.38, -3)), Vector((-0.56, 1.38, -3))],
         (0, 0, 1))
    tube("GrilleSurround", [(-0.22, 0.6, -1.66), (-0.24, 0.85, -1.66), (0.0, 0.93, -1.67), (0.24, 0.85, -1.66), (0.22, 0.6, -1.66),
                            (-0.22, 0.6, -1.66)], 0.015, "chrome", 8, bend=0.05)
    for k in range(9):
        x = -0.18 + k * 0.045
        tube("GrilleBar", [(x, 0.62, -1.66), (x, 0.86 - abs(x) * 0.3, -1.66)], 0.005, "chrome", 5)
    bumper(-1.8, 0.48, 0.7, 0.08, -1)
    bumper(1.82, 0.48, 0.7, 0.08, 1)
    plate("B-07.312", 0.0, 0.6, -1.84, -1)
    plate("B-07.312", 0.0, 0.8, 1.72, 1)
    interior([(0.15, True)], belt, 0.64, -0.3, 0.3)
    snow_on(body)


@asset
def van_hd():
    seed(203)
    belt = 1.2
    # Cab and bonnet.
    st = [(-0.15, 0.82, 0.5, 1.95), (-0.55, 0.82, 0.5, 1.92), (-0.78, 0.8, 0.52, 1.6), (-0.95, 0.5, 0.56, 1.25),
          (-1.6, 0.45, 0.58, 1.2), (-2.0, 0.42, 0.6, 1.15), (-2.05, 0.34, 0.65, 1.1)]
    body = loft("Body", st, "car_paint", belt, n=28)
    for s in (-1, 1):
        c = [Vector((s * 1.5, 1.28, -0.7)), Vector((s * 1.5, 1.28, -0.2)), Vector((s * 1.5, 1.75, -0.2)), Vector((s * 1.5, 1.75, -0.7))]
        pane("SideGlass", body, c, (-s, 0, 0))
        line_on("DoorSeam", body, [(s * 1.5, y, -0.76) for y in (0.55, 0.8, 1.1, 1.4, 1.8)], (-s, 0, 0))
        handle(body, (s * 1.5, 1.15, -0.25), (-s, 0, 0))
        xi, xo = sorted((s * 0.42, s * 0.9))
        wing("FrontWing", -1.45, 0.4, 0.47, xi, xo, -0.3, math.pi - 0.2, tail=[(-0.8, 0.6)])
        wheel("Front%d" % (s + 1), s * 0.72, -1.45, 0.4, 0.18, s)
        wheel("Rear%d" % (s + 1), s * 0.75, 1.6, 0.4, 0.2, s)
        headlamp(s * 0.55, 1.08, -1.85)
    pane("Windscreen", body, [Vector((-0.66, 1.3, -3)), Vector((0.66, 1.3, -3)), Vector((0.66, 1.72, -3)), Vector((-0.66, 1.72, -3))],
         (0, 0, 1))
    tube("GrilleSurround", [(-0.3, 0.68, -2.06), (-0.3, 1.08, -2.06), (0.3, 1.08, -2.06), (0.3, 0.68, -2.06), (-0.3, 0.68, -2.06)],
         0.016, "chrome", 8)
    for k in range(10):
        x = -0.25 + k * 0.055
        tube("GrilleBar", [(x, 0.7, -2.06), (x, 1.06, -2.06)], 0.006, "chrome", 5)
    # Box body: rounded panels, the dairy's name on both sides and on the back doors.
    bx = box("BoxBody", (1.86, 1.75, 2.75), (0, 0.58 + 0.875, 1.3), "car_paint", 0.06, 4)
    box("BoxRoof", (1.92, 0.08, 2.8), (0, 2.37, 1.3), "car_paint", 0.03)
    for s in (-1, 1):
        text_on("Sign", "DOBŘANY\nDAIRY", bx, (s * 0.95, 1.55, 1.3), 0.26, "van_letter", lift=0.002, inward=(-s, 0, 0))
        box("Mudguard", (0.3, 0.05, 0.9), (s * 0.85, 0.85, 1.6), "seam", 0.02)
    line_on("BackDoorSeam", bx, [(0.0, y, 4.0) for y in (0.65, 1.2, 1.8, 2.25)], (0, 0, -1))
    handle(bx, (0.08, 1.35, 4.0), (0, 0, -1))
    for s in (-1, 1):
        box("TailLamp", (0.08, 0.1, 0.05), (s * 0.85, 0.85, 2.7), tail_key(), 0.02)
    box("Chassis", (1.1, 0.18, 4.0), (0, 0.5, 0.3), "seam", 0.02)
    bumper(-2.2, 0.55, 0.82, 0.1, -1)
    plate("D-11.046", 0.0, 0.66, -2.25, -1)
    plate("D-11.046", 0.0, 0.85, 2.69, 1)
    interior([(-0.35, True)], belt, 0.75, -0.75, 0.4, 0.55)
    snow_on(body)
    snow_box_top = box("RoofSnow", (1.8, 0.06, 2.7), (0, 2.43, 1.3), "car_snow", 0.03)


def _drive(fn):
    global DRIVE
    DRIVE = True
    try:
        fn()
    finally:
        DRIVE = False


@asset
def car_sedan_drive():
    _drive(car_sedan_hd)


@asset
def car_streamline_drive():
    _drive(car_streamline_hd)


@asset
def car_small_drive():
    _drive(car_small_hd)


@asset
def van_drive():
    _drive(van_hd)


def _wheel_asset(r, w, disc="wheel_paint"):
    """One road wheel for the driving cars: its centre at the origin, axle along x, outer face +x."""
    n0 = count()
    wheel("W", 0.0, 0.0, r, w, 1, disc)
    transform_since(n0, (0.0, -r, 0.0))


@asset
def wheel_car():
    seed(210)
    _wheel_asset(0.36, 0.16)


@asset
def wheel_car_paint():
    seed(211)
    _wheel_asset(0.36, 0.16, "car_paint")


@asset
def wheel_small():
    seed(212)
    _wheel_asset(0.32, 0.13)


@asset
def wheel_van():
    seed(213)
    _wheel_asset(0.4, 0.19)


VIEWS = {"car_sedan_hd": (0.9, 0.35, -1.0), "car_streamline_hd": (0.9, 0.35, -0.6), "car_small_hd": (0.9, 0.35, -1.0),
         "van_hd": (0.9, 0.35, -1.0)}
