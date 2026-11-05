"""Before / after sheets of the whole cast from Godot captures (capture_compare.gd, tags <t>top and <t>soft):
one row per character - top light before | after, soft light from below before | after; 4 rows a sheet.
    blender -b -P scripts/cast_sheet.py -- <capture dir> <t> slug slug ...
-> previews/_cast_<t>_<k>.png"""
import bpy, os, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[sys.argv.index("--") + 1:]
cap, t, slugs = args[0], args[1], args[2:]
PER, SC = 4, 2


def load(path):
    im = bpy.data.images.load(path)
    a = np.array(im.pixels[:], np.float32).reshape(im.size[1], im.size[0], 4)[::SC, ::SC]
    bpy.data.images.remove(im)
    return a


for k in range(0, len(slugs), PER):
    rows = []
    for s in slugs[k:k + PER]:
        tiles = []
        for light, shot in (("top", "tele"), ("soft", "low")):
            for name in (s + "__before", s):
                tiles.append(load(os.path.join(cap, "compare_%s%s_%s_%s.jpg" % (t, light, name, shot))))
                tiles.append(np.ones((tiles[-1].shape[0], 4 if name != s else 14, 4), np.float32))
        row = np.concatenate(tiles[:-1], axis=1)
        row[:5] = 1.0
        rows.append(row)
    sheet = np.concatenate(rows[::-1], axis=0)
    out = bpy.data.images.new("cs", sheet.shape[1], sheet.shape[0])
    out.pixels[:] = sheet.ravel()
    out.filepath_raw = os.path.join(ROOT, "previews", "_cast_%s_%d.png" % (t, k // PER))
    out.file_format = "PNG"
    out.save()
    print("SHEET", k // PER, slugs[k:k + PER])
