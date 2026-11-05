"""Build, export and preview the HD props.

    blender -b --factory-startup -P build_props.py -- <asset ...|crew|van|loco|all> [--no-preview]

Each asset is built from scratch in an empty scene, joined into one mesh, exported as glTF
(separate .gltf/.bin, textures shared in assets/models/hd_props/textures/), saved as an editable
.blend in art_source/props_hd/blend/ and rendered to art_source/props_hd/previews/.
"""
import sys, os, json, time, traceback
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hdlib
import assets_crew
GROUPS = {"crew": assets_crew.A}
try:
    import assets_van
    GROUPS["van"] = assets_van.A
except ImportError:
    pass
try:
    import assets_loco
    GROUPS["loco"] = assets_loco.A
except ImportError:
    pass
for _mod, _grp in (("assets_locobody", "locobody"), ("assets_carbody", "carbody"), ("assets_shell", "shell"), ("assets_service", "service"), ("assets_staff", "staff"), ("assets_station", "station"), ("assets_yard", "yard"), ("assets_cars", "cars"), ("assets_hall", "hall")):
    try:
        GROUPS[_grp] = __import__(_mod).A
    except ImportError as e:
        if _mod not in str(e):
            raise

ALL = {}
for g in GROUPS.values():
    ALL.update(g)
VIEWS = {}
for mod in [sys.modules[m] for m in ("assets_crew", "assets_van", "assets_loco", "assets_locobody", "assets_carbody", "assets_shell", "assets_service", "assets_staff", "assets_station", "assets_yard", "assets_cars", "assets_hall") if m in sys.modules]:
    VIEWS.update(getattr(mod, "VIEWS", {}))

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
no_preview = "--no-preview" in args
names = []
for a in [a for a in args if not a.startswith("--")]:
    if a == "all":
        names += list(ALL)
    elif a in GROUPS:
        names += list(GROUPS[a])
    else:
        names.append(a)

report_path = os.path.join(hdlib.ROOT, "build_report.json")
report = json.load(open(report_path)) if os.path.exists(report_path) else {}
failed = []
for name in names:
    t0 = time.time()
    try:
        hdlib.reset()
        ALL[name]()
        obj = hdlib.finish(name)
        tris = hdlib.tri_count(obj)
        hdlib.export(obj, name)
        if not no_preview:
            hdlib.preview(obj, name, VIEWS.get(name, (-0.55, 0.45, -1.0)))
        dims = [round(v, 3) for v in obj.dimensions]
        report[name] = {"tris": tris, "materials": [m.name for m in obj.data.materials], "dims_blender": dims}
        print(f"BUILT {name}: {tris} tris, {len(obj.data.materials)} materials, {time.time() - t0:.1f}s")
    except Exception:
        traceback.print_exc()
        failed.append(name)
        print(f"FAILED {name}")
json.dump(report, open(report_path, "w"), indent=1)
print("FAILED:", failed if failed else "none")
