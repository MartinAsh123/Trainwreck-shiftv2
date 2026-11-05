"""Where a Tripo character's mouth is sculpted and where it is painted (shared by measure_mouths.py and
repaint_face.py). Face toward -Y, Z up, metres.
geometry: the lips' slit is a sharp groove in the depth seen from the front; followed column by column
          out from the middle until it fades: its height per column, and its ends (the corners).
paint:    the dark line between the painted lips (darkest, reddish) per column near it, and where the
          lips' red ends at the sides."""
import numpy as np
from mathutils import Vector

MM = 0.001


def sample(face, x0, x1, z0, z1, step):
    gx, gz = np.arange(x0, x1, step), np.arange(z0, z1, step)
    D = np.full((len(gz), len(gx)), np.nan, np.float32)
    C = np.zeros((len(gz), len(gx), 3), np.float32)
    for j, z in enumerate(gz):
        for i, x in enumerate(gx):
            h = face.bvh.ray_cast(Vector((x, face.front_y, z)), Vector((0, 1, 0)))
            if h[0] is not None:
                D[j, i] = h[0].y
                _, uv = face.hit(x, z)
                C[j, i] = face.color(uv, bilinear=True)[:3]
    return gx, gz, D, C


def fit_mouth(face, F):
    """-> dict: gx, gz, D, C (front samples, 0.2 mm), geo_z(x) and paint_z(x) per column (nan where
    none), geo corners (x0, x1), paint corners (x0, x1), centre x."""
    cx = F["center_x"]
    nz = F["nose"][2]
    step = 0.0002
    gx, gz, D, C = sample(face, cx - 0.045, cx + 0.045, nz - 0.07, nz - 0.004, step)
    Dn = np.where(np.isnan(D), np.nanmax(D), D)
    k = int(1.5 * MM / step)
    up, dn = np.roll(Dn, -k, axis=0), np.roll(Dn, k, axis=0)
    sharp = np.minimum(Dn - up, Dn - dn)                         # deeper than 1.5 mm above and below
    sharp[:k], sharp[-k:] = -1, -1
    sharp[gz > nz - 0.008] = -1                                  # (not under the nose)
    sharp[gz < nz - 0.05] = -1                                   # (nor the chin)
    i0 = int(np.argmin(np.abs(gx - cx)))
    sharp[:, np.abs(gx - cx) > 0.036] = -1                       # (nor the cheeks)
    # the middle: the sharpest groove of the central 4 mm
    mid = sharp[:, i0 - 10:i0 + 11].mean(axis=1)
    jm = int(np.argmax(mid))
    for thresh in (0.00025, 0.00012, 0.00006):                   # (a shallow slit: try a fainter groove)
        geo = np.full(len(gx), np.nan)
        for direction in (1, -1):
            j = jm
            i = i0
            while 0 <= i < len(gx):
                lo, hi = max(j - 6, 0), min(j + 7, len(gz))          # follow it within 1.2 mm a step
                jj = lo + int(np.argmax(sharp[lo:hi, i]))
                if sharp[jj, i] < thresh:
                    break
                geo[i] = gz[jj]
                j = jm if i == i0 else jj
                i += direction
        if (~np.isnan(geo)).sum() * step > 0.03:
            break
    ok = ~np.isnan(geo)
    gcorn = (float(gx[ok].min()), float(gx[ok].max())) if ok.any() else (cx - 0.02, cx + 0.02)
    # paint: per column, the darkest reddish pixel within 8 mm of the groove's height in the middle
    L = C @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    red = C[..., 0] - 0.5 * (C[..., 1] + C[..., 2])
    near = np.abs(gz - gz[jm]) < 0.008
    skin_red = float(np.median(red[np.abs(gz - (gz[jm] + 0.012)) < 0.002]))
    lip_red = float(np.percentile(red[near][:, i0 - 25:i0 + 26], 95)) if near.any() else skin_red
    score = -L + 0.8 * red
    paint = np.full(len(gx), np.nan)
    for i in range(len(gx)):
        col = np.where(near, score[:, i], -9)
        jj = int(np.argmax(col))
        lipish = red[max(jj - 10, 0):jj + 11, i].max() > skin_red + 0.4 * (lip_red - skin_red)
        if lipish:
            paint[i] = gz[jj]
    okp = ~np.isnan(paint)
    # the painted lips' ends: the outermost columns, connected to the middle, still lip-red
    pc = [cx - 0.02, cx + 0.02]
    for direction, idx in ((-1, 0), (1, 1)):
        i = i0
        while 0 <= i + direction < len(gx) and okp[i + direction]:
            i += direction
        pc[idx] = float(gx[i])
    return dict(gx=gx, gz=gz, D=D, C=C, geo=geo, paint=paint, gcorn=gcorn, pcorn=tuple(pc), cx=cx, mid_z=float(gz[jm]))
