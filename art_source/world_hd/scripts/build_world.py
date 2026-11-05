"""Build the HD landscape models (Blender 5.2, headless):
    blender -b --factory-startup -P build_world.py -- <names|trees|track|all>
Exports glTF (materials as named placeholders; the game's shaders replace them) into
assets/models/hd_world/, editable .blend files into blend/, and a triangle report."""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "props_hd", "scripts"))
import bpy
import hdlib as H

ROOT = os.path.dirname(HERE)
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))
H.ROOT = ROOT
H.TEX = os.path.join(PROJ, "assets", "models", "hd_world", "textures")
H.OUT = os.path.join(PROJ, "assets", "models", "hd_world")
H.BLEND = os.path.join(ROOT, "blend")
H.PREVIEW = os.path.join(ROOT, "previews")
H.DL = os.path.join(ROOT, "downloads")

import assets_trees as T
GROUPS = {"trees": list(T.BUILDERS)}
BUILDERS = dict(T.BUILDERS)
try:
    import assets_track as K
    GROUPS["track"] = list(K.BUILDERS)
    BUILDERS.update(K.BUILDERS)
except ImportError as e:
    print("no track module", e)

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
names = []
for a in args:
    if a == "all":
        names += list(BUILDERS)
    elif a in GROUPS:
        names += GROUPS[a]
    elif a in BUILDERS:
        names.append(a)
rep_path = os.path.join(ROOT, "build_report.json")
report = json.load(open(rep_path)) if os.path.exists(rep_path) else {}
for n in names:
    H.reset()
    T._mats.clear()
    obj = BUILDERS[n]()
    if isinstance(obj, tuple):
        obj = obj[0]
    tris = H.tri_count(obj)
    if n in getattr(K, "MODELS", {}):
        K.export_model(obj, n, K.MODELS[n][1])
    else:
        T.export_mesh(obj, n)
    report[n] = tris
    print("BUILT", n, tris)
json.dump(report, open(rep_path, "w"), indent=1, sort_keys=True)
