"""Measure a character's sculpted vs painted mouth (mouth_fit.py), print it, and draw it:
    blender -b <slug>/<slug>.blend -P scripts/measure_mouths.py -- <slug>
-> MOUTH line, previews/<slug>_mouthfit.png: the front texture (top) and depth shading (bottom),
   geometry groove in green, painted lip line in red, corners as ticks."""
import bpy, os, sys, json
import numpy as np

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import eye_fit, mouth_fit

slug = sys.argv[sys.argv.index("--") + 1:][0]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
body = bpy.data.objects[slug + "_body"]
face = eye_fit.Face(body, F["mouth"][1])
m = mouth_fit.fit_mouth(face, F)
gx, gz, geo, paint = m["gx"], m["gz"], m["geo"], m["paint"]
both = ~np.isnan(geo) & ~np.isnan(paint)
off = (paint - geo)[both] * 1000
print("MOUTH %s: groove %.1f..%.1f mm wide (corners at %+.1f, %+.1f), paint corners %+.1f, %+.1f; paint line minus groove: middle %+.1f mm, mean %+.1f, max |%.1f|" % (
    slug, (m["gcorn"][1] - m["gcorn"][0]) * 1000, 0, (m["gcorn"][0] - m["cx"]) * 1000, (m["gcorn"][1] - m["cx"]) * 1000,
    (m["pcorn"][0] - m["cx"]) * 1000, (m["pcorn"][1] - m["cx"]) * 1000,
    float(off[np.argmin(np.abs(gx[both] - m["cx"]))]) if both.any() else float("nan"),
    float(off.mean()) if both.any() else float("nan"), float(np.abs(off).max()) if both.any() else float("nan")))
# drawing
C = m["C"]
D = np.nan_to_num(m["D"], nan=float(np.nanmax(m["D"])))
gy = np.gradient(D, axis=0) / 0.0002
gxx = np.gradient(D, axis=1) / 0.0002
shade = np.clip(0.6 - 0.35 * gy + 0.15 * gxx, 0, 1)
S = np.repeat(shade[..., None], 3, axis=2)
for img in (C, S):
    for i in range(len(gx)):
        for arr, col in ((geo, (0.1, 0.9, 0.1)), (paint, (0.95, 0.1, 0.1))):
            if not np.isnan(arr[i]):
                j = int(np.argmin(np.abs(gz - arr[i])))
                img[max(j - 1, 0):j + 2, i] = col
    for xc, col in ((m["gcorn"][0], (0.1, 0.9, 0.1)), (m["gcorn"][1], (0.1, 0.9, 0.1)), (m["pcorn"][0], (0.95, 0.1, 0.1)), (m["pcorn"][1], (0.95, 0.1, 0.1))):
        i = int(np.argmin(np.abs(gx - xc)))
        img[:, max(i - 1, 0):i + 2] = img[:, max(i - 1, 0):i + 2] * 0.5 + np.array(col) * 0.5
A = np.concatenate([S, C], axis=0)                               # rows bottom-up: texture on top
A = np.repeat(np.repeat(A, 2, axis=0), 2, axis=1)
im = bpy.data.images.new("mf", A.shape[1], A.shape[0])
im.pixels[:] = np.concatenate([A, np.ones(A.shape[:2] + (1,), np.float32)], axis=2).ravel()
im.filepath_raw = os.path.join(ROOT, "previews", slug + "_mouthfit.png")
im.file_format = "PNG"
im.save()
