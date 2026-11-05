# HD landscape (trees, track, lineside, buildings, ground, weather)

The exterior world of the journey, upgraded from flat procedural shapes to scanned CC0 materials and
Blender-built models. Everything keeps its procedural fallback: `SceneryMeshes.hd_enabled = false`
and `Buildings.textured = false` restore the old look.

| What | Where |
|---|---|
| Spruce / fir / Scots pine (twig cards, snow pillows) + LODs, bare birch | `scripts/assets_trees.py` → `assets/models/hd_world/*.gltf` |
| Sleeper with baseplates, telegraph pole with glass insulators, platform lamp post, rocks, stump, bench | `scripts/assets_track.py` |
| Game textures (snow, ballast, timber, roof tiles, plaster, stone, rock, rail rust, bark, twig atlases) | `scripts/world_textures.py` → `assets/models/hd_world/textures/` |
| Shaders | `shaders/world/`: foliage, bark, needles_far, snow_lump, world_pbr, rail, ballast, snow_ground, building, window_lit, spindrift, world_common.gdshaderinc |
| Game code | `scripts/world/scenery.gd` (tree cells, LOD, shadows), `scenery_meshes.gd` (HD models and materials), `buildings.gd` (textured buildings, lit-room windows, HD lamps and benches), `weather.gd` (volumetric fog, spindrift, two shadow cascades) |

## Licences and provenance

All downloaded assets are **CC0 1.0** (public domain): commercial use allowed, no attribution
required. Only images (JPG/PNG), glTF JSON and binary buffers were downloaded, each checked by its
magic bytes (`scripts/download_world.py`).

| Source | Assets |
|---|---|
| Poly Haven textures (https://polyhaven.com, CC0) | snow_01, snow_02, snow_03, rock_ground, gravel_stones, rough_wood, planks_brown_10, green_rough_planks, rough_pine_door, clay_roof_tiles_02, roof_slates_02, painted_plaster_wall, beige_wall_001, rustic_stone_wall, stone_tiles_03, rock_face_03, aerial_rocks_02, rusty_metal_02, pine_bark; the twig and bark maps of fir_tree_01 and pine_tree_01 (textures only, the 8–17 M triangle models were not used) |
| Poly Haven models (CC0) | rock_07, rock_09, tree_stump_01, painted_wooden_bench (decimated where needed); rock_moss_set_01 and boulder_01 downloaded, not used |

Generated in this project (no third-party content): the tree geometry, needle-canopy texture
(stamped from the fir twig scan), birch bark and birch twigs, sleeper, pole and lamp-post models.

## Rebuilding

```
python scripts/download_world.py                       # once
"<blender>/5.2/python/bin/python.exe" scripts/world_textures.py [surfaces|trees]
blender -b --factory-startup -P scripts/build_world.py -- all|trees|track|<names>
godot --headless --path ../.. --import                 # then set meshes/generate_lods=false in the new .gltf.import files
```

## Performance (perf_probe, 1080p, RTX 5060 Ti; frame / GPU ms)

| view | before | after |
|---|---|---|
| running_out | 12.49 / 10.08 (41.7 M prims) | ~14 / 9.9 (21 M prims) |
| cab_fwd | 6.57 / 5.79 (7.2 M) | ~7.8 / 6.3 (6.6 M) |
| platform | 11.35 / 4.73 | ~10.4 / 5.8 |

How: trees in 50 m cells with visibility ranges (HD cards within 120 m, opaque LOD to 1.7 km, a
168-triangle LOD2 in the far band), shadows from shadow-only copies of the LOD model, moon with
two cascades, ground not casting shadows, branching in the ground shader, visibility ranges on
sleepers, poles, lamps, benches and rocks.
