# The anomalies' monster face

Textures of `MonsterFace` and `AnomalyFrenzy`. Run `make_textures.py` with Blender's own python (it has
OpenImageIO and numpy): it writes `assets/textures/frenzy/`.

## Licences and provenance

| Source | Used | For | Licence |
| --- | --- | --- | --- |
| Poly Haven `fabric_leather_01` (https://polyhaven.com/a/fabric_leather_01): normal, roughness, displacement, 2K JPG | `raw/` → `skin_n.png`, `skin_mask.png` R, G | the creases and pores of the skin up close | CC0 |
| Poly Haven `mud_cracked_dry_03` (https://polyhaven.com/a/mud_cracked_dry_03): displacement, 2K JPG | `raw/` → `skin_mask.png` B | the cracks in the skin | CC0 |
| Grown in `make_textures.py` | `face_map.png`, `hand_print.png`, `claw_marks.png` | the veins and blotches, the prints left on the floor | ours |
| Godot Post Process by Korin (https://github.com/ItsKorin/Godot-Post-Process-Plugin): `glitch.gdshader`, `chromatic.gdshader` | adapted into `shaders/ui/frenzy_screen.gdshader` | tearing bands, colour fringing | MIT, notice in `shaders/ui/LICENSE-Godot-Post-Process-Plugin.txt` |

## How the downloads were checked

The JPGs came straight from Poly Haven's download host (no archives), were checked to be JPEGs by their
first bytes and are re-encoded by `make_textures.py`, so only their pixels reach the game. From the plugin
only the shader text was taken, read through line by line; none of its scripts or its editor plugin are in
the project.

The agent skills read for this work (`game-feel`, `shader-programming`, `camera-systems` from
gamedev-skills/awesome-gamedev-agent-skills, Apache-2.0) were read as text and not installed. They hold no
instruction to send anything anywhere. From them: trauma-squared shake, a hit-stop on the attacker alone,
at most three full-screen flashes in a second.
