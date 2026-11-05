"""Writes scripts/gameplay/face_marks.gd from every <slug>/<slug>_face.json (the landmarks of the cast), in
the game's model space (x, z, -y): where MonsterFace finds each character's eyes and mouth. Run it from
art_source/characters after adding a character:    python scripts/export_face_marks.py"""
import glob, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "..", "..", "scripts", "gameplay", "face_marks.gd")


def g(p):
    return [round(p[0], 4), round(p[2], 4), round(-p[1], 4)]


marks = {}
for f in sorted(glob.glob(os.path.join(ROOT, "*", "*_face.json"))):
    d = json.load(open(f))
    marks[d["slug"]] = {"eyes": [g(e) for e in d["eyes"]], "mouth": g(d["mouth"]), "corners": [g(c) for c in d["mouth_corners"]],
                        "chin": g(d["chin"]), "nose": g(d["nose"])}
lines = ["class_name FaceMarks", "extends RefCounted",
         "## Where each character's face is, in its model's rest space (metres, facing +Z): from the",
         "## landmarks art_source/characters/<slug>/<slug>_face.json (scripts/export_face_marks.py writes this",
         "## file). For MonsterFace: the eyes are painted on the skin, so nothing in the model says where they are.",
         "", "const MARKS := {"]
for k, v in marks.items():
    lines.append('\t"%s": %s,' % (k, json.dumps(v, separators=(", ", ": "))))
lines.append("}")
open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print(len(marks), "characters")
