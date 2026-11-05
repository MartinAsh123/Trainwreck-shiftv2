"""Shared by eye_overflow.py and fix_eyes.py: where a Tripo character's eyes are sculpted and where
they are painted, and the mapping between the two.

Tripo sculpts each eye as an opening (a socket floor under a jutting upper lid, down to the lower lid's
rim) and paints the eye (sclera, iris, lashes) on the texture, but the two do not line up: the paint
sits higher and wider, much of it on the upper lid. Face toward -Y, Z up, metres."""
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform


def lum(c):
    return float(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])


def min_filter(A, footprint):
    """Minimum over a footprint (odd-sized bool array) round each cell; edges repeat."""
    fi, fj = footprint.shape
    P = np.pad(A, ((fi // 2, fi // 2), (fj // 2, fj // 2)), mode="edge")
    out = np.full(A.shape, np.inf)
    for a, b in zip(*np.nonzero(footprint)):
        out = np.minimum(out, P[a:a + A.shape[0], b:b + A.shape[1]])
    return out


def label(M):
    """4-connected regions of a bool grid: (labels, count)."""
    lab = np.zeros(M.shape, int)
    n = 0
    for i0, j0 in zip(*np.nonzero(M)):
        if lab[i0, j0]:
            continue
        n += 1
        stack = [(i0, j0)]
        lab[i0, j0] = n
        while stack:
            i, j = stack.pop()
            for a, b in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)):
                if 0 <= a < M.shape[0] and 0 <= b < M.shape[1] and M[a, b] and not lab[a, b]:
                    lab[a, b] = n
                    stack.append((a, b))
    return lab, n


def fill_holes(M):
    """M with the regions of ~M that do not touch the border filled in."""
    lab, n = label(~M)
    edge = set(lab[0]) | set(lab[-1]) | set(lab[:, 0]) | set(lab[:, -1])
    return M | ((lab > 0) & ~np.isin(lab, list(edge)))


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


class Face:
    """Ray casts straight at the face (from -Y): the front surface point at (x, z), its texture
    coordinate and colour."""

    def __init__(self, body, mouth_y, image=None):
        me = body.data
        mw = body.matrix_world
        me.calc_loop_triangles()
        self.tris = list(me.loop_triangles)
        self.uvl = me.uv_layers.active
        self.wv = [mw @ v.co for v in me.vertices]
        self.bvh = BVHTree.FromPolygons(self.wv, [t.vertices[:] for t in self.tris])
        img = image or [n.image for n in me.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and n.image][0]
        self.TW, self.TH = img.size
        self.px = np.array(img.pixels[:], dtype=np.float32).reshape(self.TH, self.TW, 4)
        self.front_y = mouth_y - 0.25

    def hit(self, x, z):
        h = self.bvh.ray_cast(Vector((x, self.front_y, z)), Vector((0, 1, 0)))
        if h[0] is None:
            return None, None
        t = self.tris[h[2]]
        a, b, c = (self.wv[i] for i in t.vertices)
        ua, ub, uc = (Vector((*self.uvl.data[li].uv, 0.0)) for li in t.loops)
        uv = barycentric_transform(h[0], a, b, c, ua, ub, uc)
        return h[0], (uv.x, uv.y)

    def normal_z(self, x, z):
        """Up-component of the front surface's (face) normal at (x, z)."""
        h = self.bvh.ray_cast(Vector((x, self.front_y, z)), Vector((0, 1, 0)))
        return None if h[0] is None else h[1].z * (1.0 if h[1].y < 0 else -1.0)

    def color(self, uv, bilinear=False):
        if not bilinear:
            return self.px[min(max(int(uv[1] * self.TH), 0), self.TH - 1), min(max(int(uv[0] * self.TW), 0), self.TW - 1)]
        fx, fy = uv[0] * self.TW - 0.5, uv[1] * self.TH - 0.5
        x0, y0 = int(np.floor(fx)), int(np.floor(fy))
        tx, ty = fx - x0, fy - y0
        x0, x1 = min(max(x0, 0), self.TW - 1), min(max(x0 + 1, 0), self.TW - 1)
        y0, y1 = min(max(y0, 0), self.TH - 1), min(max(y0 + 1, 0), self.TH - 1)
        p = self.px
        return (p[y0, x0] * (1 - tx) + p[y0, x1] * tx) * (1 - ty) + (p[y1, x0] * (1 - tx) + p[y1, x1] * tx) * ty


def fit_eye(face, ex, frames=None):
    """Measures one eye. Returns a dict:
    gx, gz, D      the depth (y) of the front surface on a grid round the eye
    open_xs, open_top, open_bot   the sculpted opening, per column
    paint_xs, paint_top, paint_bot the painted eye, per column
    oc, ow, oh / pc, pw, ph        centre (x, z), width, height of each
    painted        [(x, y, z) of painted texels], skin  the skin colour round the eye
    frames: {"open": [x0, x1, top, bottom], "paint": [...]} in mm from the pupil on the character's right
    eye (x toward the nose positive), measured by eye on scripts/eye_grid.py's views; mirrored for the
    left eye. They replace the detected frames (the outlines become their ellipses)."""
    gx = np.arange(ex.x - 0.05, ex.x + 0.0501, 0.0004)
    gz = np.arange(ex.z - 0.03, ex.z + 0.0281, 0.00025)
    D = np.full((len(gx), len(gz)), np.nan)
    NZ = np.full((len(gx), len(gz)), np.nan)                   # which way the surface faces: up (+) / down (-)
    C = {}
    for i, x in enumerate(gx):
        for j, z in enumerate(gz):
            p, uv = face.hit(x, z)
            if p is not None:
                D[i, j] = p.y
                NZ[i, j] = face.normal_z(x, z)
                C[(i, j)] = face.color(uv)[:3]
    ref = [C[(i, j)] for (i, j) in C if abs(gz[j] - (ex.z - 0.0145)) < 0.0004 and abs(gx[i] - ex.x) < 0.01]
    skin = np.median(np.array(ref), axis=0)
    s_sat, s_lum = float(skin.max() - skin.min()), lum(skin)

    def painted(c):
        skinlike = c[0] >= c[1] >= c[2] - 0.02 and float(c.max() - c.min()) > 0.55 * s_sat and lum(c) > 0.45 * s_lum
        return not skinlike

    # The sculpted opening, per column, read from which way the surface faces, going down: the upper
    # lid faces down (its slope, and the shelf it ends in), the socket floor faces forward, the lower
    # lid's rim faces up. The opening runs from the last of the lid's down-facing surface (once 2 mm of
    # floor follow it) down to the first up-facing rim. (A guess: eye_frames.json, measured by eye,
    # overrides it - see fit_eye's `frames`.)
    top, bot = {}, {}
    j_start = int(np.searchsorted(gz, ex.z + 0.009))
    j_stop = int(np.searchsorted(gz, ex.z - 0.017))
    for i in range(len(gx)):
        if abs(gx[i] - ex.x) > 0.02:
            continue
        col = NZ[i]
        last_down, flat, jt = None, 0, None
        for j in range(min(j_start, len(gz) - 1), j_stop, -1):
            n = col[j]
            if np.isnan(n):
                break
            if n < -0.5:
                last_down, flat = j, 0
            elif n > -0.35 and last_down is not None:
                flat += 1
                if flat >= 8:
                    jt = last_down
                    break
        if jt is None:
            continue
        jb = next((j for j in range(jt - 1, max(int(np.searchsorted(gz, gz[jt] - 0.014)), 0), -1)
                   if not np.isnan(col[j]) and col[j] > 0.4), None)
        if jb is not None and 0.003 <= gz[jt] - gz[jb] <= 0.013:
            top[i], bot[i] = gz[jt], gz[jb]
    if not top:
        top[int(np.argmin(np.abs(gx - ex.x)))] = ex.z                  # (only a placeholder; frames decide)
        bot[int(np.argmin(np.abs(gx - ex.x)))] = ex.z - 0.005

    def best_run(cols):
        ks = sorted(cols)
        runs, run = [], [ks[0]]
        for k in ks[1:]:
            if k - run[-1] <= 6:                                # a few odd columns do not split it
                run.append(k)
            else:
                runs.append(run)
                run = [k]
        runs.append(run)
        return min(runs, key=lambda r: min(abs(gx[k] - ex.x) for k in r))

    def smooth(v):
        return np.convolve(np.pad(v, 3, mode="edge"), [1 / 7] * 7, "valid")

    run = best_run(top)
    open_xs = gx[run]
    open_top, open_bot = smooth([top[k] for k in run]), smooth([bot[k] for k in run])
    # The painted eye, per column: the run of painted texels through the pupil's height.
    ptop, pbot = {}, {}
    j0 = int(np.argmin(np.abs(gz - ex.z)))
    for i in range(len(gx)):
        if abs(gx[i] - ex.x) > 0.024:
            continue
        js = [j for j in range(j0 - 16, j0 + 17) if (i, j) in C and painted(C[(i, j)])]
        if not js:
            continue
        jc = min(js, key=lambda j: abs(j - j0))
        j1 = j2 = jc
        while (i, j1 - 1) in C and (painted(C[(i, j1 - 1)]) or ((i, j1 - 2) in C and painted(C[(i, j1 - 2)]))):
            j1 -= 1
        while (i, j2 + 1) in C and (painted(C[(i, j2 + 1)]) or ((i, j2 + 2) in C and painted(C[(i, j2 + 2)]))):
            j2 += 1
        if gz[j2] - gz[j1] >= 0.001:
            ptop[i], pbot[i] = gz[j2], gz[j1]
    prun = best_run(ptop)
    paint_xs = gx[prun]
    paint_top, paint_bot = smooth([ptop[k] for k in prun]), smooth([pbot[k] for k in prun])

    def frame(xs, t, b):
        return (np.array([float(xs.mean()), float(((t + b) / 2).mean())]), float(np.ptp(xs)), float(np.max(t - b)))

    oc, ow, oh = frame(open_xs, open_top, open_bot)
    pc, pw, ph = frame(paint_xs, paint_top, paint_bot)
    if frames:
        side = 1.0 if ex.x < 0 else -1.0                         # toward the nose: +x on the right eye

        def box(b):
            x0, x1 = ex.x + side * b[0] / 1000.0, ex.x + side * b[1] / 1000.0
            return (np.array([(x0 + x1) / 2, ex.z + (b[2] + b[3]) / 2000.0]), abs(x1 - x0), (b[2] - b[3]) / 1000.0)

        def ellipse(c, w, h):
            xs = np.linspace(c[0] - w / 2, c[0] + w / 2, 41)
            half = h / 2 * np.sqrt(np.clip(1 - ((xs - c[0]) / (w / 2)) ** 2, 0, 1))
            return xs, c[1] + half, c[1] - half

        oc, ow, oh = box(frames["open"])
        pc, pw, ph = box(frames["paint"])
        open_xs, open_top, open_bot = ellipse(oc, ow, oh)
        paint_xs, paint_top, paint_bot = ellipse(pc, pw, ph)
    painted_pts = [(gx[i], D[i, j], gz[j]) for (i, j), c in C.items()
                   if abs(gx[i] - ex.x) <= 0.024 and abs(gz[j] - ex.z) <= 0.012 and painted(c)]
    return dict(gx=gx, gz=gz, D=D, open_xs=open_xs, open_top=open_top, open_bot=open_bot,
                paint_xs=paint_xs, paint_top=paint_top, paint_bot=paint_bot,
                oc=oc, ow=ow, oh=oh, pc=pc, pw=pw, ph=ph, painted=painted_pts, skin=skin, painted_fn=painted)


def inside(xs, top, bot, x, z):
    k = np.searchsorted(xs, x)
    if not 0 < k < len(xs):
        return False
    k = min(k, len(xs) - 1)
    return bot[k] <= z <= top[k]


def region_weight(e, x, z, fade=1.6):
    """1 over both the opening and the painted eye (and a margin), fading to 0 further out (at `fade`
    times its size: a mesh that moves needs a long fade, or it folds over itself where it stops)."""
    c = (e["oc"] + e["pc"]) / 2
    a = max(e["ow"], e["pw"]) / 2 + 0.004
    b = (abs(e["pc"][1] - e["oc"][1]) + max(e["oh"], e["ph"])) / 2 + 0.003
    r = np.sqrt(((x - c[0]) / a) ** 2 + ((z - c[1]) / b) ** 2)
    w = 1.0 - smoothstep(0.85, fade, r)
    # Upward it stops short of the brow (the brow ridge moved, its painted hairs would slide off it):
    # gone 4 mm above the higher of the two frames' tops.
    top = max(e["oc"][1] + e["oh"] / 2, e["pc"][1] + e["ph"] / 2)
    return w * (1.0 - smoothstep(top, top + 0.004, z))


def core_point(e, x, z):
    """(x, z) pulled in onto the region's core (the ellipse round both eyes' frames), if outside it."""
    c = (e["oc"] + e["pc"]) / 2
    a = max(e["ow"], e["pw"]) / 2 + 0.004
    b = (abs(e["pc"][1] - e["oc"][1]) + max(e["oh"], e["ph"])) / 2 + 0.003
    r = float(np.sqrt(((x - c[0]) / a) ** 2 + ((z - c[1]) / b) ** 2))
    return (x, z) if r <= 1.0 else (c[0] + (x - c[0]) / r, c[1] + (z - c[1]) / r)


def paint_to_open(e, x, z):
    return (e["oc"][0] + (x - e["pc"][0]) * e["ow"] / e["pw"], e["oc"][1] + (z - e["pc"][1]) * e["oh"] / e["ph"])


def open_to_paint(e, x, z):
    return (e["pc"][0] + (x - e["oc"][0]) * e["pw"] / e["ow"], e["pc"][1] + (z - e["oc"][1]) * e["ph"] / e["oh"])


def bilerp(e, G, x, z):
    """Grid value at (x, z) (bilinear; nan where the grid has none)."""
    gx, gz = e["gx"], e["gz"]
    fi = (x - gx[0]) / (gx[1] - gx[0])
    fj = (z - gz[0]) / (gz[1] - gz[0])
    i0, j0 = int(np.floor(fi)), int(np.floor(fj))
    if i0 < 0 or j0 < 0 or i0 + 1 >= len(gx) or j0 + 1 >= len(gz):
        return np.nan
    ti, tj = fi - i0, fj - j0
    return ((G[i0, j0] * (1 - ti) + G[i0 + 1, j0] * ti) * (1 - tj) + (G[i0, j0 + 1] * (1 - ti) + G[i0 + 1, j0 + 1] * ti) * tj)
