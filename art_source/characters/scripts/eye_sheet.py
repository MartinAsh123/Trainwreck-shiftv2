"""Contact sheets of the eye check: one row per character - before (textured, then shape only, with the
detected opening in red), after the geometry fix (textured, then shape only) - from
previews/<slug>_eye_overflow[_geo].png, 5 characters a sheet.
    blender -b -P scripts/eye_sheet.py -- slug slug ...
-> previews/_eyes_sheet_<k>.png (+ the order, printed)"""
import bpy, os, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
slugs = sys.argv[sys.argv.index("--") + 1:]
PER = 5
W, H = 650, 280                                                 # each panel: half of a 1300 x 560 half-image


def load(path):
    if not os.path.exists(path):
        return None
    im = bpy.data.images.load(path)
    a = np.array(im.pixels[:], dtype=np.float32).reshape(im.size[1], im.size[0], 4)
    bpy.data.images.remove(im)
    return a


def panel(a, top):
    if a is None:
        return np.full((H, W, 4), (0.4, 0.0, 0.0, 1.0), np.float32)
    half = a[a.shape[0] // 2:, :, :] if top else a[:a.shape[0] // 2, :, :]   # rows go bottom-up
    return half[::2, ::2][:H, :W]


for k in range(0, len(slugs), PER):
    rows = []
    for s in slugs[k:k + PER]:
        before = load(os.path.join(ROOT, "previews", s + "_eye_overflow.png"))
        after = load(os.path.join(ROOT, "previews", s + "_eye_overflow_geo.png"))
        row = np.concatenate([panel(before, True), panel(before, False), panel(after, True), panel(after, False)], axis=1)
        row[:4] = (0.1, 0.1, 0.1, 1.0)                                  # a dark line between rows
        rows.append(row)
    sheet = np.concatenate(rows[::-1], axis=0)                          # first character at the top
    out = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0])
    out.pixels[:] = sheet.ravel()
    out.filepath_raw = os.path.join(ROOT, "previews", "_eyes_sheet_%d.png" % (k // PER))
    out.file_format = "PNG"
    out.save()
    print("SHEET", k // PER, slugs[k:k + PER])
