#!/bin/bash
# The whole chain for one character of cast.json (after batch_extract.py), from art_source/characters:
#   bash scripts/run_character.sh <slug> <height>
# prep -> face_landmarks -> repaint_face (eyes where eye_frames.json has them, hair, moustache, lips)
#   -> face_rig (talking face) -> export (assets/characters/<slug>/<slug>.glb) + an untouched "before" GLB
# -> <slug>/pipeline.log; last line: the summary.
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
slug=$1
h=$2
log="$slug/pipeline.log"
: > "$log"
step() {
    echo "== $1" >> "$log"
    shift
    "$B" -b "$@" >> "$log" 2>&1
}
[ -f "$slug/$slug.blend" ] || step prep "$slug/${slug}_src.blend" -P scripts/prep_character.py -- "$(python -I -c "import json,sys; print([c['src'] for c in json.load(open('cast.json'))['cast'] if c.get('slug') == sys.argv[1]][0])" "$slug")" "$slug" "$h"
step landmarks "$slug/$slug.blend" -P scripts/face_landmarks.py -- "$slug"
step repaint "$slug/$slug.blend" -P scripts/repaint_face.py -- "$slug"
step rig "$slug/${slug}_eyefix_paint.blend" -P scripts/face_rig.py -- "$slug"
step export "$slug/${slug}_face.blend" -P scripts/export_character.py -- "$slug"
step before "$slug/$slug.blend" -P scripts/export_character.py -- "$slug" _before
echo "$slug: $(grep -cE 'Traceback' "$log") errors | $(grep -E '^(LIPS|HAIR|EXPORTED|SEAM)' "$log" | sed 's/A:.*assets/assets/' | tr '\n' ' ')" >> "$log"
tail -1 "$log"
