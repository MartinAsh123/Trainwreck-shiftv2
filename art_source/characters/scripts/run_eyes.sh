#!/bin/bash
# The eye check and fix for one character of cast.json (after batch_extract.py):
#   prep_character -> face_landmarks -> eye_overflow (before) -> fix_eyes geo -> eye_overflow (after)
#   bash scripts/run_eyes.sh <slug> <height>          (from art_source/characters)
# -> <slug>/pipeline.log, previews/<slug>_eye_overflow.png and _eye_overflow_geo.png
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
step before "$slug/$slug.blend" -P scripts/eye_overflow.py -- "$slug"
step fix "$slug/$slug.blend" -P scripts/fix_eyes.py -- "$slug" geo
step after "$slug/${slug}_eyefix_geo.blend" -P scripts/eye_overflow.py -- "$slug" geo
echo "$slug: $(grep -cE 'Traceback' "$log") errors; $(grep -E '^EYE at' "$log" | sed 's/.*mm; //' | tr '\n' ' ')" >> "$log"
tail -1 "$log"
