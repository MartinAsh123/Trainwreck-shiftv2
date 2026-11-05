"""Download the CC0 source material for the HD landscape (Poly Haven).

Poly Haven publishes everything under CC0 1.0 (public domain, commercial use allowed, no
attribution required). Only image files (jpg/png), glTF json and binary buffers are fetched;
every file is checked by its magic bytes after download and anything else is refused.
"""
import json, os, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DL = os.path.join(ROOT, "downloads")
UA = {"User-Agent": "TrainwreckShift-asset-fetch/1.0"}

# Poly Haven textures (2k jpg): key -> (asset id, maps)
PBR = ("Diffuse", "nor_gl", "arm")
PH_TEX = {
    "snow_powder": ("snow_02", PBR), "snow_trodden": ("snow_01", PBR), "snow_trampled": ("snow_03", PBR),
    "ballast": ("rock_ground", PBR), "ballast_b": ("gravel_stones", PBR),
    "wood_weathered": ("rough_wood", PBR), "planks": ("planks_brown_10", PBR),
    "planks_green": ("green_rough_planks", PBR), "door_pine": ("rough_pine_door", PBR),
    "roof_clay": ("clay_roof_tiles_02", PBR), "roof_slate": ("roof_slates_02", PBR),
    "plaster": ("painted_plaster_wall", PBR), "plaster_smooth": ("beige_wall_001", PBR),
    "stone_wall": ("rustic_stone_wall", PBR), "platform": ("stone_tiles_03", PBR),
    "rock_face": ("rock_face_03", PBR), "rock_aerial": ("aerial_rocks_02", PBR),
    "rail_rust": ("rusty_metal_02", PBR), "pine_bark": ("pine_bark", PBR),
    # Tree cards: the scanned twig (with alpha) and bark of Poly Haven's fir and pine.
    "fir": ("fir_tree_01", ("twig_diff", "twig_alpha", "twig_nor_gl", "twig_arm", "bark_diff", "bark_nor_gl", "bark_arm")),
    "pine": ("pine_tree_01", ("twig_diff", "twig_alpha", "twig_nor_gl", "twig_arm")),
}
# Poly Haven models (glTF 2k)
PH_MODELS = ["rock_moss_set_01", "rock_07", "rock_09", "boulder_01", "tree_stump_01", "painted_wooden_bench"]

MAGIC = {b"\xff\xd8\xff": "jpg", b"\x89PNG": "png", b"{": "json", b"glTF": "glb"}

def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:
        return r.read()

def kind(data, name):
    for m, k in MAGIC.items():
        if data.startswith(m):
            return k
    return "bin" if name.endswith(".bin") else None

def save(path, data):
    if kind(data, path) is None:
        raise RuntimeError("unexpected file type: " + path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)

def ph_tex(key, aid, maps):
    out = os.path.join(DL, "ph", key)
    files = json.loads(get(f"https://api.polyhaven.com/files/{aid}"))
    for mp in maps:
        dst = os.path.join(out, f"{aid}_{mp}.jpg")
        if os.path.exists(dst):
            continue
        res = files[mp]["2k"]
        fmt = "jpg" if "jpg" in res else "png"
        u = res[fmt]["url"]
        save(dst if fmt == "jpg" else dst[:-4] + ".png", get(u))
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
    only = sys.argv[1:]
    for k, (a, maps) in PH_TEX.items():
        if not only or k in only:
            ph_tex(k, a, maps)
    for a in PH_MODELS:
        if not only or a in only:
            ph_model(a)
    print("done")
