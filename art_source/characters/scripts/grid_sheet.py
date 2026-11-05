"""Grid views (eye_grid.py) of several characters side by side, shrunk, for reading by eye:
    blender -b -P scripts/grid_sheet.py -- <tag> <per sheet> slug slug ...
-> previews/_grid_<tag>_<k>.png (each tile titled by its place in the order printed)"""
import bpy, os, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[sys.argv.index("--") + 1:]
tag, per, slugs = args[0], int(args[1]), args[2:]
SC = 2
for k in range(0, len(slugs), per):
    tiles = []
    for s in slugs[k:k + per]:
        im = bpy.data.images.load(os.path.join(ROOT, "previews", "%s_eye_grid_%s.png" % (s, tag)))
        a = np.array(im.pixels[:], np.float32).reshape(im.size[1], im.size[0], 4)[::SC, ::SC]
        bpy.data.images.remove(im)
        a[:, :3, :3] = 1.0
        tiles.append(a)
    while len(tiles) < per:
        tiles.append(np.zeros_like(tiles[0]))
    sheet = np.concatenate(tiles, axis=1)
    out = bpy.data.images.new("gs", sheet.shape[1], sheet.shape[0])
    out.pixels[:] = sheet.ravel()
    out.filepath_raw = os.path.join(ROOT, "previews", "_grid_%s_%d.png" % (tag, k // per))
    out.file_format = "PNG"
    out.save()
    print("SHEET", k // per, slugs[k:k + per])
