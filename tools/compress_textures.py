# compress_textures.py — switches 3D textures to VRAM compression with mipmaps.
#   python tools/compress_textures.py <dir> [<dir> ...]
# For every texture .import under the folders whose compress/mode is 0 (lossless, kept as raw RGBA
# in video memory): compress/mode=2 (VRAM compressed: BPTC/S3TC on desktop), mipmaps on (less
# shimmer and texture bandwidth at a distance), and normal maps flagged as such (RGTC, which keeps
# them accurate). Godot reimports changed textures on the next import/editor start.
import os
import re
import sys

NORMAL = re.compile(r"(normal|_nor_|_nrm|_nor\.|_n\.)", re.I)


def fix(path):
    s = open(path, encoding="utf-8").read()
    if 'importer="texture"' not in s or "compress/mode=0" not in s:
        return False
    s = s.replace("compress/mode=0", "compress/mode=2")
    s = s.replace("mipmaps/generate=false", "mipmaps/generate=true")
    if NORMAL.search(os.path.basename(path)):
        s = s.replace("compress/normal_map=0", "compress/normal_map=1")
    open(path, "w", encoding="utf-8").write(s)
    return True


n = 0
for d in sys.argv[1:]:
    for root, _dirs, files in os.walk(d):
        for f in files:
            if f.endswith(".import") and fix(os.path.join(root, f)):
                n += 1
print("compressed", n, "textures")
