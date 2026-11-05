# Performance baseline, 2026-11-03

Measured after the economy / HUD / inventory work and the 30 m/s route. Windowed D3D12, Forward+,
NVIDIA RTX 5060 Ti, 20-core CPU, 1920x1080 window (viewport reported 1954x1080), vsync off, no fps
cap, editor build of Godot 4.7.2 (no export templates, see "Release export"). Other Claude
sessions had Godot processes open on the same machine during some runs, so treat ±1 ms as noise.

**Headline: 53-67 FPS, down from 105-115.** The GPU is idle half the frame (4.6-6.6 ms); the
main thread is the bottleneck. Memory and orphan nodes are clean over a full shift. Four
~0.45-0.58 s freezes per shift happen when a stopping station streams in.

## 1. Four fixed spots (`tools/_perf_baseline.gd`)

600 measured frames per spot after 240 warm-up frames; horror director off; camera at the saloon
window except "town" (outside, over STŘÍBRNÁ HORA). 1% low = mean of the slowest 1% of frames.

| spot | avg fps | 1% low | frame ms | p99 ms | max ms | gpu ms | cpu render ms | draws | prims k | objects | shadowed lights | static MB | vram MB | orphans | nodes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| open line (s=4100, 30 m/s) | 67 | 51 | 14.84 | 19.02 | 20.6 | 6.57 | 3.47 | 3075 | 21 576 | 4469 | 3 + sun | 554 | 6671 | 1 | 18 550 |
| station stop (DOBŘANY) | 62 | 46 | 16.12 | 20.45 | 25.6 | 5.47 | 4.50 | 3788 | 19 377 | 5581 | 3 + sun | 566 | 6783 | 1 | 18 516 |
| town (STŘÍBRNÁ HORA, outside) | 56 | 36 | 17.86 | 24.46 | 39.5 | 4.58 | 3.74 | 3101 | 10 472 | 4864 | 3 + sun | 562 | 6737 | 1 | 18 464 |
| night storm (blizzard, s=16000) | 53 | 39 | 18.77 | 24.27 | 28.5 | 5.25 | 3.28 | 2677 | 19 065 | 4125 | 3 + sun | 553 | 6580 | 8 | 16 777 |

Notes
- `Performance.TIME_PROCESS` read 17-23 ms, above the wall-clock frame; in 4.7 it is not a
  script-only number and it drifts (21.7 -> 26.0 ms over one run with nothing changed), so it is
  left out. Use the frame ms and the A/B savings below.
- 3 shadowed omni/spot lights at all times = `shadow_budget.gd` doing its job.
- 6.6 GB of VRAM is high for this scene but steady; not a leak (see soak).

### Streaming at 30 m/s, 90 s from s=800 (KRÁLOVEC -> DOBŘANY)

5052 frames, 2143 m: avg 17.82 ms (56 fps), 1%-low 36 fps, p99 24.1 ms, max 39.7 ms.
7 frames over 33 ms (35-40 ms, two at the point 670 nodes entered, near s=1960 and on arrival at
DOBŘANY), 3495 of 5052 frames over 16.7 ms. Orphans 1 -> 1, static memory 566 -> 563 MB.
No big freeze on this stretch because DOBŘANY's station was already built during boot.

## 2. Soak: the whole shift (`tools/_soak.gd`)

`--fixed-fps 60`, windowed, POV in the saloon, Kevin left in his room, horror seed 7, then
EndOfDay.turn_in() at the end of the line (no save is written). 1242 s of game time in 1320 s wall.

| measure | value |
|---|---|
| boot to nav ready | 61 frames, 13.3 s wall |
| first 30 s (sampled every second) | 67-73 fps, no errors, **no crash** |
| baseline frame (60-180 s) | 17.07 ms |
| median / worst 10-s window | 17.32 ms / 26.39 ms (840 s, s≈15000, near VYSOKÉ POLE) |
| static memory | 564 MB baseline -> 550 MB at the end, slope **-0.57 MB/min** (no leak) |
| orphan nodes | 1 throughout (transient 8 at boot); 1 at the end |
| events | 19: 9 flickers / giggles, 1 haunting (stayed in "signs" for 1054 s: nobody resolved it), passing train at 693 s, ghost story stage change, stops |
| after every event (20 s settle) | orphans +0, static memory within ±17 MB (GC noise both ways) |
| frames > 250 ms | **4**: 426 ms (s=3901), 494 ms (s=9151), 440 ms (s=12901), 443 ms (s=16901) |
| turn-in at the end | frame max 46 ms, then 81-85 fps on the summary screen |
| soak verdict | 1 flag (the 26 ms window); nothing failed to return to baseline |

The four freezes are exactly 2600 m (`Scenery.feature_ahead`) before VRCHOVINA (6500),
SNĚŽNÁ (11750), VYSOKÉ POLE (15500) and STŘÍBRNÁ HORA (19500): the moment each stopping
station is added to the tree. See suspect 1.

### The "crash about 14 s in"

Not reproduced. 0 crashes in: 5 windowed boots of journey.tscn for 2700 frames each
(all exit 0), the 22-minute soak, 4 baseline/blame/A-B runs and 6 tool runs (all windowed).
The only error at every exit is "3 resources still in use at exit" (harmless, known).
14 s into a boot is when nav is ready and the first station's life (hall, staff, yard) is
being built, so if it comes back, run `_soak.gd`: its log is flushed per line and sampled every
second for the first 30 s, so the last line says where it died.

## 3. Where the frame goes (`tools/_perf_process_blame.gd`, `tools/_perf_ab.gd`)

Blame switches processing off for one kind of node at a time; A/B then switches the top
suspects off and on 4 times each (300 frames per measurement) at the open-line spot.

| kind | nodes | frame on -> off (ms) | saves | confidence |
|---|---|---|---|---|
| `shift_hud.gd` (_process) | 1 | 15.14 -> 11.22 | **3.9 ms** | high (all 4 rounds) |
| ShiftHUD hidden (drawing only) | 1 | 14.01 -> 13.57 | 0.4 ms | high |
| `passengers.gd` | 1 | 14.28 -> 12.08 | **2.2 ms** | medium |
| `haunt.gd` | 1 | 16.23 -> 13.99 | 2.2 ms | low (rounds 12.3-16.5 off) |
| `talking_character.gd` | 23 | 17.71 -> 16.08 | **1.6 ms** | medium |
| `[Skeleton3D]` | 144 | 21.35 -> 20.10 | 1.3 ms | low |
| `world_life.gd` | 1 | 14.76 -> 13.96 | 0.8 ms | medium |
| `train.gd` | 1 | 18.86 -> 18.12 | 0.7 ms | low |
| `[CPUParticles3D]`, `passing_train.gd` | | | ~0 | |

(Absolute frame ms differ between rows because the train keeps running through the line during
the A/B; compare within a row.)

## 4. ShiftHUD item pictures: cached? (read only)

Yes, per item kind. `ShiftHUD._icon()` (`scripts/ui/shift_hud.gd:262`) returns
`_icons[it.item]` when present; otherwise `_making[it.item]` makes sure only one `_shoot` per
kind is ever queued (`:265-267`). `_shoot` renders the item once in its own 160x160 SubViewport
(own_world_3d, two frames), stores an ImageTexture in `_icons` (`:324`) and frees the viewport.
Setting the same texture on the slot every frame is a no-op. Gaps, all minor:
- The cache lives on the HUD instance, so every new day (journey reload) re-photographs each kind
  once (2 frames each). A `static var` dictionary of textures would keep them across days.
- If the image comes back empty, `_making` stays set and that kind never gets a picture (letter
  fallback for the rest of the night). Clear `_making[id]` when the image is empty.
- `_shoot.call_deferred(it)` does not check that `it` still exists when the call runs.
- The real HUD cost is elsewhere in the same file (suspect 2).

## 5. Top 5 suspects

1. **Station streaming freeze, 430-580 ms, 4x per shift** — `scripts/life/world_life.gd:253-268`
   (`_on_feature`, called from `Scenery.child_entered_tree`) runs on the main thread:
   `StationHall.build()` **370 ms** (`scripts/world/station_hall.gd:149-158`: `load()` of each staff
   GLB, ~120 ms each, then `TalkingCharacter._ready` -> `_fit_mouth_weights`
   `scripts/characters/talking_character.gd:105,159`, 40-80 ms per character, a GDScript pass over
   every face vertex) + `StationYard.attach` 40 ms + the next frame 30 ms. Measured with
   `tools/_perf_station_add.gd` and `tools/_perf_hitch.gd` (582 ms, 555 ms of it before drawing).
   The staff models are freed with the previous station, so every station pays again.
2. **ShiftHUD rebuilds its look every frame, 3.9 ms** — `scripts/ui/shift_hud.gd:176` creates 4
   new StyleBoxFlat per frame and sets them as overrides; `:195/:199`, `:221`, `:248` set colour
   overrides on labels every frame. Each override is a theme change: the labels re-shape their
   text and the containers re-sort every frame. Hiding the HUD saves only 0.4 ms, so it is the
   script, not the drawing.
3. **Passengers, 2.2 ms** — `scripts/characters/passengers.gd:492-528`: `_riders.duplicate()`
   and `_pending.duplicate()` every frame (`:506`, `:463`), `_place_on_platform` for every waiting
   rider every frame, and errand movers; a rider stuck at the W.C. door re-plans its path every
   3 s for the rest of the night (`:991-996`, warning "cannot get back to its seat yet").
4. **TalkingCharacter has no distance/visibility LOD, 1.6 ms for 23** —
   `scripts/characters/talking_character.gd:324-330`: every character, seen or not (other car,
   far platform), allocates a PackedFloat32Array (`:331`), writes ~20 blend shapes
   (`_update_face`) and sets spine/neck/head bones (`:506-539`) every frame; each also owns an
   audio bus with a spectrum analyzer (`:236-243`).
5. **Smaller per-frame work in scenery/life streaming** — `world_life.gd:130-145` (0.8 ms),
   and the station-stop / storm spots being 1-4 ms slower than the open line with fewer draw calls
   (CPU side: townsfolk, yard cars, particles). Not split further today.

## 6. Proposed fixes, ranked (owners in brackets; nothing was changed)

1. **Take station life off the frame** [world fork: world_life.gd, station_hall.gd]. Preload the 4
   staff GLBs once and keep them referenced (a `static var` of PackedScenes, never a lambda), so
   `load()` and the mouth fit happen once per run; or load them with
   `ResourceLoader.load_threaded_request` when the station is 2.6 km out and build the hall when
   it finishes; and/or spread `_on_feature` over several frames (hall, then bell, then yard).
   Expected: 4 freezes of ~0.5 s -> under ~50 ms.
2. **ShiftHUD: set things only when they change** [economy fork: shift_hud.gd]. Make the two
   slot styleboxes once (`_box_sel`, `_box_dim`) and assign only when `sel` changes; keep the last
   colour per label and call `add_theme_color_override` only on change; update the corner and the
   task list ~10 times a second instead of every frame. Expected: ~3.5 ms -> ~0.3 ms, i.e.
   67 -> ~85 fps on the open line.
3. **Fit the mouth weights once per model, not per load** [characters: talking_character.gd].
   Bake `_fit_mouth_weights` into the import (or cache the fitted ArrayMesh by resource path in a
   static dictionary). Also helps every boarding passenger.
4. **TalkingCharacter LOD** [characters]. Skip `_update_face` and most of `_update_body` when not
   visible or > ~15 m from the camera (update at 5-10 Hz there); reuse one target array instead of
   allocating per frame; give the spectrum-analyzer bus only to characters that are speaking.
5. **Passengers: no per-frame copies** [gameplay: passengers.gd]. Iterate by index (or copy only
   when the list changed), place waiting riders only when the platform moves noticeably, and give
   a stuck errand up after a few retries (back to the seat by teleport-on-unseen, or wait for the
   door) instead of re-planning every 3 s.

With 1-2 done the open line should be back near 85-90 fps; 3-5 should close most of the rest
of the gap to the old 105-115.

## 7. Release export

Not measured: there is **no `export_presets.cfg`** in the project and **no export templates**
installed (`%APPDATA%\Godot\export_templates` is empty). Needed: Editor > Manage Export
Templates > download 4.7.2, then Project > Export > add "Windows Desktop" (release, embed PCK).
After that, `godot_console.exe --path . --export-release "Windows Desktop" exports/TrainwreckShift.exe`.
To measure it, include `tools/_perf_baseline.gd` in the export filter and run
`TrainwreckShift.exe -s res://tools/_perf_baseline.gd -- out.md` (or add a small in-game FPS
logger). Expect the GDScript-heavy costs (suspects 2-5) to drop somewhat in release; the station
freeze will not go away by itself.

## 8. Test runner (`tools/run_all_tests.ps1`)

`powershell -ExecutionPolicy Bypass -File tools\run_all_tests.ps1 [-Filter x] [-IncludeChecks] [-Windowed]`.
Each test runs with its own flags (picture tests windowed, `_check_passengers` and
`_test_pacing` with `--fixed-fps 30`, per-test args and timeouts); new `_test_*.gd` files are
picked up automatically (headless, no args). FAIL = crash / non-zero exit / timeout /
SCRIPT ERROR / a line starting FAIL or TIMEOUT / "NOT DONE" / "FAILS n>0" / missing expected line.
WARN = engine errors that are not known headless dummy-renderer noise. Logs + `summary.md` go
to `%TEMP%\trainwreck_tests\<time>` (or `-OutDir`).

Full run 2026-11-03 (25 runs, ~45 min), failures re-run once with the final runner:

| test | status | mode | s | note |
|---|---|---|---|---|
| _test_bunk | PASS | window | 30 | |
| _test_economy | PASS | headless | 115 | |
| _test_edges | PASS | headless | 226 | |
| _test_errands | PASS | headless | 16 | |
| _test_escort anomaly | PASS | headless | 105 | |
| _test_escort normal | PASS | headless | 219 | |
| _test_frenzy exposed | **FLAKY** | headless | 26 / 300+ | passed with `elderly_man_third_eye`; with `elderly_woman_4_grey_marks` the frenzy ended by 69 s and the test never quit (timeout) |
| _test_frenzy arrest / hunt / abort | PASS | headless | 46 / 69 / 12 | |
| _test_frontend | PASS | window | 23 | |
| _test_haunt calm coffee | PASS | headless | 86 | |
| _test_haunt break ebrake | **FAIL** | headless | 138 | `TIMEOUT waiting for breakdown`: the e-brake breakdown never happened (`incident=''`), both runs |
| _test_haunt_mike | PASS | headless | 58 | |
| _test_horror | PASS | headless | 40 | |
| _test_mike | **FAIL** | headless | 445 | `PATROL NOT DONE in 200 s` (patrol -> room -> station -> rest without finishing the patrol), both runs |
| _test_pacing | PASS | headless fps30 | 100 | max gap 122 s, `PACING OK` |
| _test_passing | PASS | window | 47 | |
| _check_audio | PASS | headless | 16 | |
| _check_boarding | PASS | headless | 29 | |
| _check_journey | PASS | headless | 0 | |
| _check_mech | PASS | window | 24 | stalls headless (waits for frame_post_draw); saves its pictures to another session's old scratchpad path |
| _check_passengers | PASS | headless fps30 | 42 | |
| _check_townfolk | PASS | window | 37 | |
| _check_train | PASS | headless | 62 | |

**PASS 22, FLAKY 1, FAIL 2 of 25.** Owners: haunt/frenzy -> pacing-director; Mike -> gameplay.

## Tools added today (all new, nothing existing was edited)

| file | what |
|---|---|
| `tools/_perf_baseline.gd` | the 4 spots + streaming hitches -> markdown table |
| `tools/_soak.gd` | the whole shift, 10-s samples, event markers, orphan/memory checks, crash trail |
| `tools/_perf_process_blame.gd` | frame saving per kind of processing node |
| `tools/_perf_ab.gd` | on/off A/B of named kinds, several rounds |
| `tools/_perf_hitch.gd` | what entered the tree in each long frame, before-draw vs draw split |
| `tools/_perf_station_add.gd` | one station's add, and WorldLife's part of it, piece by piece |
| `tools/_perf_char_spawn.gd` | load / _ready / mouth-fit cost of a TalkingCharacter |
| `tools/run_all_tests.ps1` | runs every `tools/_test_*.gd` (and `-IncludeChecks` the root `_check_*.gd`) |

Commands:

```
godot_console.exe --path . --resolution 1920x1080 -s tools/_perf_baseline.gd -- out.md 90
godot_console.exe --path . --resolution 1920x1080 --fixed-fps 60 -s tools/_soak.gd -- <out_dir> saloon 26
godot_console.exe --path . --resolution 1920x1080 -s tools/_perf_hitch.gd -- 3750 4050 60
powershell -ExecutionPolicy Bypass -File tools\run_all_tests.ps1 -IncludeChecks
```

## 9. Fix 1 applied (2026-11-04): station streaming freeze

Changed: `scripts/world/station_hall.gd` (static `_staff_scenes` cache of the staff PackedScenes,
`warm()` starts `ResourceLoader.load_threaded_request` for them, `_staff_scene()` replaces `load()`),
`scripts/life/world_life.gd` (`StationHall.warm()` in `_ready`; `_on_feature` -> new `_station_life()`:
a station further than `STATION_SPREAD_FROM` = 800 m from the train waits `STATION_SPREAD_DELAY`
= 1.5 s, past Scenery's own burst, then builds the hall, then bell + yard on later frames; a
station near the train (start, warps) is built at once as before),
`scripts/life/station_yard.gd` (`attach(..., spread := false)`: with `spread` it waits a frame
between tracks / island platform / benches+ramps / forecourt / fence). Names, metas and the
`has_node("Yard")` guard are unchanged. The staff stay loaded (and their mouths fitted) for the
whole run.

| `_perf_hitch.gd` (1080p, worst frame as a station streams in) | before | cache only | + spread + delay |
|---|---|---|---|
| DOBŘANY (s 300-700) | 582 ms | 129 ms | 37 ms |
| VRCHOVINA (s 3700-4100) | ~555 ms | 122 ms | 33 ms |

Per step (`tools/_perf_yard_split.gd`, train held, background 9-11 ms/frame): hall 6-8 ms,
yard steps 5-18 ms each. Other sessions' Godot runs were on the machine during some measurements
(GPU 120 ms frames in one run, discarded).

Still there, not station life (follow-ups): runs of 35-55 ms "nothing added" frames at s ≈ 1955-1963
and 3905-3915 as a town/halt comes in (Scenery's own main-thread work), a 226 ms frame at
s ≈ 1181 (nothing added; LHOTA halt ahead), and 153 ms at s ≈ 2381 (passengers boarding: two
Passenger_* subtrees added).

Tests: new `tools/_test_station_life.gd` (hall, staff, bell, yard, fence at the start station, a
streamed one and after `warp_to_stop`): RESULT ok. Runner, station tests: `_test_edges`,
`_test_escort` anomaly + normal, `_check_boarding`, `_check_journey`, `_check_passengers`,
`_check_townfolk`: 7/7 PASS.

## 10. Re-measure after fixes 1-5 (2026-11-04 evening)

`_perf_baseline.gd`, 1080p, three runs. The first run (21:03) started 30 s after the Godot editor
was opened (import / shader work alongside) and gave station 51 / town 48 fps; the two later runs
agree with each other and are the numbers below.

| spot | avg fps before | avg fps now | 1% low now | frame ms now |
|---|---|---|---|---|
| open line | 67 | 108-110 | 53-65 | 9.1-9.3 |
| station stop (DOBŘANY) | 62 | 64 | 45-46 | 15.5-15.6 |
| town (STŘÍBRNÁ HORA) | 56 | 66-67 | 43-47 | 14.9-15.2 |
| night storm | 53 | 65-67 | 40-41 | 15.0-15.4 |

Streaming at 30 m/s, 90 s (first run): 80 fps avg, 6 hitches > 33 ms, worst 72 ms (s ≈ 2375-2380,
11 passenger nodes added: boarding at the next stop's approach), none from stations.
Memory 550 -> 555 MB, orphans 1 -> 1.

The station stop stays ~6 ms above the open line while passengers board (the 25 s stop); after
departure the same spot runs at ~8.7 ms. A/B during the stop (`_perf_ab.gd ... stop`, 3 rounds):
passengers.gd 1.5 ms, talking_character.gd ×24 1.1 ms, Skeleton3D ×148 none; the rest is spread.

Full runner (`run_all_tests.ps1 -IncludeChecks`, 26 runs): **PASS 25, FAIL 1.**
`_test_frenzy exposed` and `_test_haunt break ebrake` now pass. `_test_mike` still fails:
"PATROL NOT DONE in 200 s" — its first patrol is cut short by station duty ("19.09 patrol ->
station"), the second patrol completes ("19.30 patrol done"); with the halved timetable the test's
200 s window no longer fits before the first stop (test or Mike's duty timing, gameplay owner).

Fixed afterwards: `tools/_test_mike.gd` starts its patrol just past the stop with the longest run to
the next one (VRCHOVINA, s=6800) instead of s=2000, 20 s before DOBŘANY's station duty. Patrol
done in 141 s; runner `_test_mike` PASS (387 s). Full suite is now 26/26.
