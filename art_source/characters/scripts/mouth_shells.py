"""Which separate surfaces (shells) of a character's mesh lie in front of its mouth, and a front view
of the mouth with each shell tinted, to tell lips from a moustache or beard over them:
    blender -b <slug>/<slug>.blend -P scripts/mouth_shells.py -- <slug>
-> SHELLS lines; previews/<slug>_shells.png (texture, then shells tinted: the skin shell grey)"""
import bpy, bmesh, os, sys, json
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

slug = sys.argv[sys.argv.index("--") + 1:][0]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = json.load(open(os.path.join(ROOT, slug, slug + "_face.json")))
body = bpy.data.objects[slug + "_body"]
me = body.data
mw = body.matrix_world
bm = bmesh.new()
bm.from_mesh(me)
bm.faces.ensure_lookup_table()
# shells: faces connected through shared vertices
shell = [-1] * len(bm.faces)
n = 0
for f0 in bm.faces:
    if shell[f0.index] >= 0:
        continue
    stack = [f0]
    shell[f0.index] = n
    while stack:
        f = stack.pop()
        for v in f.verts:
            for g in v.link_faces:
                if shell[g.index] < 0:
                    shell[g.index] = n
                    stack.append(g)
    n += 1
wv = [mw @ v.co for v in bm.verts]
tris = []
tri_shell = []
for f in bm.faces:
    vs = [v.index for v in f.verts]
    for k in range(1, len(vs) - 1):
        tris.append((vs[0], vs[k], vs[k + 1]))
        tri_shell.append(shell[f.index])
bvh = BVHTree.FromPolygons(wv, tris)
M = Vector(F["mouth"])
CX = F["center_x"]
nose = Vector(F["nose"])
# front view of the mouth region: which shell is seen first
S = 0.0004
gx = np.arange(CX - 0.04, CX + 0.0401, S)
gz = np.arange(nose.z - 0.065, nose.z - 0.002, S)
seen = np.full((len(gz), len(gx)), -1)
for j, z in enumerate(gz):
    for i, x in enumerate(gx):
        h = bvh.ray_cast(Vector((x, M.y - 0.25, z)), Vector((0, 1, 0)))
        if h[0] is not None:
            seen[j, i] = tri_shell[h[2]]
ids, cnt = np.unique(seen[seen >= 0], return_counts=True)
order = np.argsort(-cnt)
skin_shell = int(ids[order[0]])
for k in order:
    s_ = int(ids[k])
    mask = seen == s_
    jj, ii = np.nonzero(mask)
    print("SHELLS %s: shell %d covers %.0f mm2 in front of the mouth, z %.1f..%.1f mm from the nose, x %.1f..%.1f mm%s" % (
        slug, s_, cnt[k] * S * S * 1e6, (gz[jj.min()] - nose.z) * 1000, (gz[jj.max()] - nose.z) * 1000,
        (gx[ii.min()] - CX) * 1000, (gx[ii.max()] - CX) * 1000, "  (skin)" if s_ == skin_shell else ""))
print("SHELLS %s: %d shells in all" % (slug, n))
