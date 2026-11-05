"""Download the CC0 source material for the HD props (ambientCG + Poly Haven).

Both libraries publish everything under CC0 1.0 (public domain, commercial use allowed, no
attribution required). Only image files (jpg/png), glTF json and binary buffers are fetched;
every file is checked by its magic bytes after download and anything else is deleted.
"""
import json, os, sys, urllib.request, zipfile, io

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DL = os.path.join(ROOT, "downloads")
UA = {"User-Agent": "TrainwreckShift-asset-fetch/1.0"}

# ambientCG materials (2K JPG): key -> assetId
ACG = {
    "wood_furniture": "Wood066", "wood_dark": "Wood067", "wood_pine": "Wood049", "wood_handle": "Wood063",
    "brass": "Metal007", "steel": "Metal009", "iron": "Metal038", "paint_black": "Metal027",
    "galvanized": "Metal032", "copper": "Metal035", "gold": "Metal034",
    "leather_red": "Leather037", "leather_black": "Leather026",
    "kraft": "Cardboard004", "kraft_crumpled": "Paper005", "paper": "Paper002",
    "felt_navy": "Carpet012", "rug_pile": "Carpet016", "rubber": "Rubber004", "coal": "Rock030",
    "paint_clean": "Paint004", "underframe": "Metal024", "underframe_rust": "Metal021", "roof_canvas": "Fabric036", "rust": "Rust007",
    # Service room textiles (towels, sheets, wool blankets).
    "towel": "Fabric020", "linen": "Fabric019", "wool": "Fabric031",
}
# Poly Haven textures (2k): key -> asset id
PH_TEX = {"leather_brown": "brown_leather", "canvas": "hessian_380", "paint_green": "green_metal_rust",
          # Station and town props: brick (transformer tower, gate piers), snow caps.
          "brick": "red_brick_03", "snow": "snow_02",
          # Station hall interior: chequered floor tiles, marble counter tops.
          "floor_checker": "checkered_pavement_tiles", "marble": "marble_01"}
# Poly Haven models (glTF 2k)
PH_MODELS = ["alarm_clock_01", "Lantern_01", "binder_notebook", "small_oil_can_01", "wooden_crate_01",
             "wooden_crate_02", "vintage_suitcase", "treasure_chest", "wooden_stool_01", "ClassicNightstand_01",
             # Station yards and towns.
             "horse_statue_01", "gothic_statue", "power_box_01", "utility_box_01", "utility_box_02",
             "large_iron_gate", "fire_hydrant", "covered_car", "wooden_picnic_table",
             # Station hall.
             "potted_plant_02", "metal_trash_can", "wall_clock"]

MAGIC = {b"\xff\xd8\xff": "jpg", b"\x89PNG": "png", b"PK\x03\x04": "zip", b"{": "json", b"glTF": "glb"}

def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()

def kind(data, name):
    for m, k in MAGIC.items():
        if data.startswith(m):
            return k
    return "bin" if name.endswith(".bin") else None

def save(path, data):
    k = kind(data, path)
    if k is None:
        raise RuntimeError("unexpected file type: " + path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return k

def acg(key, aid):
    out = os.path.join(DL, "acg", key)
    if os.path.isdir(out) and os.listdir(out):
        return
    data = get(f"https://ambientcg.com/get?file={aid}_2K-JPG.zip")
    assert kind(data, "x.zip") == "zip", aid
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for n in z.namelist():
            low = n.lower()
            if not low.endswith((".jpg", ".png")):
                continue                       # skip previews' .usda/.mtlx etc.
            if any(s in low for s in ("normaldx", "displacement", "_preview")):
                continue
            save(os.path.join(out, os.path.basename(n)), z.read(n))
    print("acg", key, aid, sorted(os.listdir(out)))

def ph_tex(key, aid):
    out = os.path.join(DL, "ph", key)
    if os.path.isdir(out) and os.listdir(out):
        return
    files = json.loads(get(f"https://api.polyhaven.com/files/{aid}"))
    for mp in ("Diffuse", "nor_gl", "arm", "Rough", "AO"):
        if mp in files and "2k" in files[mp]:
            u = files[mp]["2k"]["jpg"]["url"]
            save(os.path.join(out, f"{aid}_{mp}.jpg"), get(u))
    print("ph tex", key, sorted(os.listdir(out)))

def ph_model(aid):
    out = os.path.join(DL, "ph_models", aid)
    if os.path.isdir(out) and os.listdir(out):
        return
    files = json.loads(get(f"https://api.polyhaven.com/files/{aid}"))
    g = files["gltf"]["2k"]["gltf"]
    save(os.path.join(out, aid + ".gltf"), get(g["url"]))
    for rel, info in g.get("include", {}).items():
        save(os.path.join(out, rel), get(info["url"]))
    print("ph model", aid, sum(len(fs) for _, _, fs in os.walk(out)), "files")

if __name__ == "__main__":
    for k, a in ACG.items():
        acg(k, a)
    for k, a in PH_TEX.items():
        ph_tex(k, a)
    for a in PH_MODELS:
        ph_model(a)
    print("done")
