# HD props and bodies (all cars, locomotive)

62 props that replace the procedural stand-ins built in `crew_car.gd`, `mail_van.gd` and
`locomotive.gd`, plus the HD locomotive body (`assets_locobody.py`: boiler, frames, cab, tender,
8 wheel models, coupling rod, crosshead, connecting rod) and the coach exterior shared by every car
(`assets_carbody.py`: underframe, end gear, boarding steps, torpedo vent). The coach shell shaders
(`car_exterior.gdshader`, `car_interior.gdshader`) take scanned detail maps from the same set
(paint surface, painted-canvas roof, wood/floor/paper detail).
Body mouldings per car type (`assets_shell.py`, from the layouts `scripts/export_layouts.gd` writes
to `layouts/` and the index `assets/models/hd_props/body_layouts.json`) and the coach bogie with a
separate Mansell wheelset replace the Tripo bogie. Re-run export_layouts.gd and rebuild the `shell`
group after changing a car's window or door layout; a car whose layout has no export keeps the
plain body. The game loads them from `assets/models/hd_props/<name>.gltf` through
`scripts/train/hd_props.gd`. Every builder keeps its procedural code as a fallback; setting
`HDProps.enabled = false` restores the old look for comparison.

## Licences and provenance

Every downloaded asset is **CC0 1.0** (public domain): commercial use is allowed and no attribution
is required. Only images (JPG/PNG), glTF JSON and binary buffers were downloaded, and each file was
checked by its magic bytes (`scripts/download.py`).

| Source | Assets | Used for |
|---|---|---|
| ambientCG (https://ambientcg.com, CC0) | Wood066, Wood067, Wood049, Wood063, Metal007, Metal009, Metal038, Metal027, Metal032, Metal035, Metal034, Leather037, Leather026, Cardboard004, Paper005, Paper002, Carpet012, Carpet016, Rubber004, Rock030, Paint004, Metal024, Metal021, Fabric036, Rust007, Fabric020, Fabric019, Fabric031 | woods, brass, steel, cast iron, paints, galvanised tin, copper, gold leaf, leathers, kraft paper, paper, felt, rug pile, rubber, coal (and its matt recolour), firebrick (rust recolour), towels (Fabric020), sheets and toilet tissue (Fabric019), wool blankets (Fabric031) |
| Poly Haven (https://polyhaven.com, CC0) textures | brown_leather, hessian_380, green_metal_rust, red_brick_03, snow_02, checkered_pavement_tiles, marble_01, painted_plaster_wall | leather, mail-bag canvas, painted steel (and its red/livery/cream recolours), brick (transformer tower, gate piers), snow caps on outdoor props, station hall floor, counter tops and plaster |
| Generated in textures.py (no source image) | wicker | basket weave of the laundry hamper |
| Fonts (SIL OFL, assets/fonts) | Oswald | lettering modelled onto props (stencils, plates, posters) |
| Poly Haven models (CC0) | alarm_clock_01, Lantern_01, small_oil_can_01, wooden_crate_01, wooden_crate_02, wooden_stool_01, ClassicNightstand_01, horse_statue_01, gothic_statue, power_box_01, utility_box_01, utility_box_02, large_iron_gate, fire_hydrant, covered_car, wooden_picnic_table, potted_plant_02, metal_trash_can, wall_clock | alarm clock, guard's hand lamp, oil can, crates, sorting stool, nightstand, town statues, electrical cabinets, yard gate, hydrant, covered car, picnic table, station hall palms, bin and clock |

Downloaded but not used in the game: binder_notebook, vintage_suitcase, treasure_chest.

Generated in this project (no third-party content): rug pattern, clock dials, ledger page, parcel
label (fonts: the project's Oswald and Playfair Display, both SIL OFL).

Tooling only (not shipped): Pillow, installed locally in `.pydeps/` to draw text into textures.

## Rebuilding

```
# 1. (once) fetch the CC0 sources into downloads/
python scripts/download.py
# 2. game texture set -> tex_build/ (Blender's bundled Python: OpenImageIO + numpy)
"C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" scripts/textures.py
# 3. build / export / preview (all, a group crew|van|loco, or asset names)
blender -b --factory-startup -P scripts/build_props.py -- all
# 4. import in Godot (or focus the editor)
godot --headless --path ../.. --import
```

- `scripts/hdlib.py`: primitives (bevelled boxes, lathes, swept tubes, tori, discs), UVs, PBR materials and export.
- `scripts/assets_crew.py`, `assets_van.py`, `assets_loco.py`: one function per prop, in Godot coordinates that match the GDScript frames.
- `blend/`: editable .blend for every prop. `previews/`: studio renders. `build_report.json`: triangle counts.
- `backup_20261020/`: the three car scripts before the HD hookups.
