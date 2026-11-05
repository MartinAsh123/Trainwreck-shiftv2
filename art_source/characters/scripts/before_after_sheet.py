"""Before / after pairs of Godot captures (capture_compare.gd) on sheets: one row per character, before on
the left, after on the right, 4 rows a sheet.
    blender -b -P scripts/before_after_sheet.py -- <capture dir> <tag> <shot> slug slug ...
-> previews/_before_after_<tag>_<k>.png"""
import bpy, os, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[sys.argv.index("--") + 1:]
cap, tag, shot, slugs = args[0], args[1], args[2], args[3:]
PER, SCALE = 4, 2


def load(path):
    im = bpy.data.images.load(path)
    a = np.array(im.pixels[:], dtype=np.float32).reshape(im.size[1], im.size[0], 4)[::SCALE, ::SCALE]
    bpy.data.images.remove(im)
    return a


for k in range(0, len(slugs), PER):
    rows = []
    for s in slugs[k:k + PER]:
        names = [s + "__before", s] if os.path.exists(os.path.join(cap, "compare_%s_%s__before_%s.jpg" % (tag, s, shot))) else [s + "__eyes_before", s + "__eyes_after"]
        pair = [load(os.path.join(cap, "compare_%s_%s_%s.jpg" % (tag, n, shot))) for n in names]
        row = np.concatenate([pair[0], np.ones((pair[0].shape[0], 6, 4), np.float32), pair[1]], axis=1)
        row[:4] = (1, 1, 1, 1)
        rows.append(row)
    sheet = np.concatenate(rows[::-1], axis=0)
    out = bpy.data.images.new("ba", sheet.shape[1], sheet.shape[0])
    out.pixels[:] = sheet.ravel()
    out.filepath_raw = os.path.join(ROOT, "previews", "_before_after_%s_%d.png" % (tag, k // PER))
    out.file_format = "PNG"
    out.save()
    print("SHEET", k // PER, slugs[k:k + PER])
