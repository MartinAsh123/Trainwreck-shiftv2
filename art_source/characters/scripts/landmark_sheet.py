"""All characters' landmark close-ups (previews/<slug>_landmarks.png) on sheets of 4 x 3, numbered in the
order given, for checking face_landmarks.py by eye.
    blender -b -P scripts/landmark_sheet.py -- slug slug ...
-> previews/_landmarks_sheet_<k>.png"""
import bpy, os, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
slugs = sys.argv[sys.argv.index("--") + 1:]
COLS, ROWS, S = 4, 3, 450
PER = COLS * ROWS
for k in range(0, len(slugs), PER):
    sheet = np.zeros((ROWS * S, COLS * S, 4), np.float32)
    sheet[..., 3] = 1.0
    for n, s in enumerate(slugs[k:k + PER]):
        path = os.path.join(ROOT, "previews", s + "_landmarks.png")
        if not os.path.exists(path):
            continue
        im = bpy.data.images.load(path)
        a = np.array(im.pixels[:], dtype=np.float32).reshape(im.size[1], im.size[0], 4)[::2, ::2][:S, :S]
        bpy.data.images.remove(im)
        r, c = ROWS - 1 - n // COLS, n % COLS                   # rows go bottom-up
        sheet[r * S:r * S + a.shape[0], c * S:c * S + a.shape[1]] = a
    out = bpy.data.images.new("lm", COLS * S, ROWS * S)
    out.pixels[:] = sheet.ravel()
    out.filepath_raw = os.path.join(ROOT, "previews", "_landmarks_sheet_%d.png" % (k // PER))
    out.file_format = "PNG"
    out.save()
    print("SHEET", k // PER, slugs[k:k + PER])
