# Gameplay first pass: passengers, Mike, detention, ghost pilot, horror events

Everything is under the **Gameplay** node in `scenes/game/journey.tscn` (`scripts/gameplay/gameplay.gd`), which creates the parts below. Each part finds the others through groups, and each can be disabled through `with_*` on the Gameplay node.

## Files

| File | Role |
|---|---|
| `scripts/gameplay/train_nav.gd` | 10 cm walking grid over the floors, built from the real collision. Doors are recorded as "open first". There are two grids: staff and passengers. Cache: `train_nav_cache.res` (rebuilt automatically if the doors change). |
| `scripts/gameplay/npc_mover.gd` | Walking for a single character: stands up from the seat, opens and closes doors, waits outside a hinged door's swing, yields in narrow corridors, waits for the player ("Excuse me"). It never passes through a wall and reports failure if there is no route. |
| `scripts/gameplay/holding_cage.gd` | Turns the cage gate into a real locked door (TrainDoor). Places on the bench, which set the capacity: 3. |
| `scripts/gameplay/detention.gd` | Reports, statuses (reported → under escort → held → papers checked → confirmed or released), missed stops. |
| `scripts/gameplay/mike_duty.gd` | Mike's routine and priorities. Escort and release. |
| `scripts/gameplay/shift_record.gd` + `scripts/ui/shift_summary.gd` | Shift record, each outcome paid or charged once into the wallet, the end-of-day summary with the pay slip. |
| `scripts/gameplay/economy.gd` | The wallet and today's account (lines with stable ids), the next day, the save. |
| `scripts/gameplay/task_board.gd` + `chores.gd` | Work orders with deadlines on the train's clock: the daily routine and the special requests. |
| `scripts/gameplay/inventory.gd` + `chore_item.gd` | What Kevin carries: four slots. |
| `scripts/gameplay/berth_job.gd` | A berth to make up in the sleeping car. |
| `scripts/gameplay/wake_scare.gd` | The sleeper who should not have been woken. |
| `scripts/gameplay/end_of_day.gd` + `scripts/ui/shift_hud.gd` | Kevin's bed ends the day; the HUD (toolbar, clock, money, ghost timer, work orders). |
| `scripts/gameplay/horror_director.gd` | The night's pacing (tension curve, slots for the big scares) and the minor signs: flicker / giggle / scream. |
| `scripts/gameplay/anomaly_frenzy.gd` + `monster_face.gd` | An anomaly that turns on the player: lunge, monster face in first person, crawl on all fours belly up, out of a door of the moving train. |
| `scripts/gameplay/ghost_story.gd` | Ghost pilot (provisional) on a single model (`vintage_woman`). |

Changes to existing files:
- `passengers.gd`: errands, getting off at the real destination, escort/detention states, stand/sit steps.
- `talking_character.gd`: a physical capsule while standing.
- `passenger_talk.gd`: what the player has seen, and evidence.
- `staff_talk.gd`: report a passenger, wake Mike, report a sighting.
- `terminal_data.gd` / `xp_apps.gd`: status in the manifest, log lines.

## How to play
- **Investigation:** talk to a passenger (E) and ask for their ticket, how they are, and who they are. Inconsistencies are recorded as evidence.
- **Report:** talk to Mike, choose "I want to report a passenger.", then pick from the list (by name, or by car and seat). Mike walks to the passenger, arrests them, and escorts them to the cage in the mail van. He locks the cage, and about 12 game minutes later checks their papers.
- **Wrongful report:** Mike lets the passenger out, apologises, walks them back to their seat, and the shift record takes −8.
- **Waking Mike:** while he naps on his bunk the prompt is "E — Wake Mike". A report, a station stop or a release also wakes him.
- **Ghost:** at 19:32 a telegram arrives about berth 6. After reading it (or at 20:10 at the latest), look down the sleeping car corridor. After you see her, Mike's dialogue offers to report it; a follow-up telegram arrives later.

## The night's pacing (`scripts/gameplay/horror_director.gd`)
One director shapes the 20 minutes as a saw-tooth: **build → peak → rest**, over and over (2026-11-03; before, each scare ran its own timer and `hold` only stopped overlaps, and the last third of the shift was empty).
- **Rest** at the start (`first_after`, 75 s: the routine is learnt first) and `rest_seconds` (40-60 s) after every peak: nothing of the director's own.
- **Build** (`build_seconds`, 130-170 s): `tension` climbs 0 → 1, and the minor signs (flicker, giggle, from tension 0.5 a far scream) come more often as it climbs (`minor_gap` 55 → 30 s). While a haunting is giving its own signs, they stand in for the director's; they keep out of the rest.
- **Peak**: the slot for one big scare. The big ones ask `big_ready(kind, free)` and report `begin_big` / `end_big`:
  - tied to a place or a deadline (`free = false`): the goods train on its stretch, a haunting's breakdown due (waits up to `break_wait`). They may come before the slot opens, never in a rest and never within `tied_gap` (75 s) of the end of the last big one; a goods train refused is skipped for that stretch. A breakdown due also gives way to a goods train due soon (the train cannot wait).
  - free (`free = true`): a violent anomaly found out sits tight, armed, until the slot opens (or tension ≥ `early_peak` 0.75), then goes the next time the player is close.
  - set off by the player: the wrong sleeper he shakes, the guard's hand on an anomaly, a forced `trigger()`: always goes, and counts as the peak.
  - nobody takes the slot within `peak_wait` (40 s): the director's own peak, **dread** - a far scream while the lamps around Kevin falter twice, long and nearly out. Not when a goods train is due within `big_gap` + 40 s (`PassingTrain.seconds_to_next()`): then the build holds at its top, signs coming fast, and the slot is left to the train.
- A haunting never starts in a rest after a big scare or with the slot open; special requests never over a big scare; the director is no longer switched off during a haunting.
- Spread over the night: the goods trains at minutes ~10.5 and ~17.5; the wake-up calls one a stop (`Chores.call_stops`: Sněžná, Stříbrná Hora, Vysoké Pole first); the wrong sleeper rides to Vysoké Pole or Stříbrná Hora (`WakeScare.late_stops`) and gets a wake-up call like the others, so the scare comes with the job late in the night (its order is called off when it springs, no money either way); berths due 20.20; requests every 140-200 s until 1.5 km before the end.
- Hooks, called only if there: `GameAudio.dread(level)` follows the tension (0.05 in a rest, 0.12 → 0.6 in a build, 0.7 with the slot open, cut to 0 on a big hit); the player's `add_trauma` through `HorrorDirector.trauma()` on the hits (the wake scare 0.55, the e-brake jolt 0.4).
- `HorrorDirector.timeline` records every sign, big scare, haunting, fault and work order: `[real s, clock, what, tier]`. `enabled = false` (tests) stops the director's own events and lets every big one through unasked.
- Test: `tools/_test_pacing.gd -- [seed] [speed]` (headless, `--fixed-fps 30`): the real journey at `speed`× with a stand-in Kevin; prints the timeline minute by minute and the longest gap (`PACING OK` under 190 s, no two big ones within 2 minutes unless the player set one off).

## Hauntings (`scripts/gameplay/haunt.gd`, `haunt_item.gd`, `haunt_spot.gd`, `ghost_fade.gd`)
One seated passenger at a time turns out to be a ghost (up to 3 per shift).
1. **Signs in its car:** a child's giggle, flickering lamps, then the heating cuts out and the passengers around complain (the cold, the heat, a strange smell). A complaint also arrives in Dispatch Messages. The ghost shows itself for an instant now and then (it pales and comes back), and it casts no shadow. Where it sits, it gives itself away: frost spreads over its seat, table and the floor around it over about 90 seconds; its breath smokes in small puffs; its eyes follow Kevin down the car; and if he comes within about 1.7 m it giggles under its breath (at most every 30 s). Passengers also mention the frost and the one that "hasn't blinked once".
2. **Identify:** its ticket is dated 14.01.1931 and it answers oddly. Ask its name ("who are you").
3. **Jim:** on any staff terminal, open Private Line, pick the name and send it. The answer arrives in Dispatch Messages after 1-2 minutes. A wrong name gets a "not in my register".
4. **Laying it to rest:** Jim says what it needs, one of four. Bring coffee (Kevin's desk), bring the evening paper (Mike's chair), say a set sentence, or answer its riddle (a wrong answer takes 45 seconds off the clock). The new line appears in conversation with the ghost. It turns the apparition's colour and vanishes (+6).
5. **Breakdown:** if it isn't dealt with within 7-8 minutes of the first sign (random per haunting), something breaks in its car (-3), then the clock restarts. The fault is announced in Dispatch Messages. The four faults are used in turn:
   - **Emergency brake:** it pulls the e-brake in its car. The train makes an emergency stop on the line and stands; the handle hangs out on its chain under a blinking red lamp. Once stopped, "E — Reset the emergency brake", the line recharges (about 4 s) and the train moves off. Only out on the line at speed.
   - **Heating unit:** the ceiling hatch is screwed shut. Take the screwdriver from the sleeping car's service room (on the chest of drawers), unscrew the hatch, reconnect the 3 cables, close it.
   - **W.C. blocked:** take the plunger from the sleeping car's service room (by the broom) and plunge 3 times; the water drains away.
   - **Terminal:** take the USB stick from the nightstand in Kevin's compartment, plug it in, and wait for the 8 s reinstall.

Reporting a ghost to Mike does not work: his hand goes through it and he sends Kevin to his friend.

| HauntDirector | Default |
|---|---|
| `first_start` | 100 s |
| `deadline` | 420 s |
| `reply_min/max` | 60-120 s |
| `gap_min/max` | 120-200 s |
| `max_hauntings` | 3 |
| `break_wait` | 150 s (a breakdown due waits this long at most for the night's curve) |
| `points_incident` | -3 |
| `sign_gap`, `moan_gap`, `flash_gap` | 55-95, 8-15, 14-26 s |

All times are real seconds. Jim and his instructions are provisional. Tests: `tools/_test_haunt.gd -- calm <kind>` / `-- break <kind>`, `tools/_test_haunt_mike.gd`, `tools/_haunt_shots.gd`.

## Anomaly frenzy (`scripts/gameplay/anomaly_frenzy.gd`)
Each anomaly has one roll, `violent_chance` (18% in all), the first time it counts: when `PassengerTalk.evidence()` first has anything on it, or when Mike reaches it, whichever comes first. Of the violent ones, `wait_for_guard` (half):
- **The rest, found out**: when its answer ends it turns on the player and is off the train before Mike can come.
- **Waiting for the guard**: it does nothing until Mike reaches it. Closer than 3.2 m to the player it lunges at once; farther away it shrieks and hunts him down on all fours through the cars, doors flung open, at 7.5 m/s (gives up after `hunt_seconds`). If the player never reports it, it never goes off.

It only happens while the train is moving; if the train is standing it waits (a guard arriving at a standing train takes it quietly). Ghosts are left alone.

The sequence: tell (a stare, the smile widening too far, his eye drawn in to it, lamps flicker) → lunge → hold (a blink of stopped time for it alone, then its hands at the sides of his head, MonsterFace against his eye, the head snapping from angle to angle) → drop (a second shriek, he is thrown back, it flips over) → flee (`crawl_speed`, feet first, staring at him, in bursts, doors flung open with `TrainDoor.force`) → leap (the outside door flung open, snow and cold light blowing in; it falls away past the windows) → after (doors shut, Mike back to duty, status FLED). Claw marks stay where it dropped and hand prints along its way, for about three minutes. No score either way; the end-of-shift report lists it apart.

- `MonsterFace`: built when the anomaly is armed. `shaders/characters/monster_skin.gdshader` takes the place of the skin material (detail, veins, hollows, the mouth cut open; hands too); real eyes (`monster_eye.gdshader`) that follow `stare_at`; the jaw and mouth shape keys driven well past 1; a bowl of flesh (`monster_maw.gdshader`), gums, teeth, strings of spit and claws built at runtime on the bones. `detach()` puts the passenger back. Works on any character through `scripts/gameplay/face_marks.gd` (written by `art_source/characters/scripts/export_face_marks.py`: run it after adding a character).
- The people standing in its way (`scripts/gameplay/frenzy_panic.gd`, while it runs): nobody sees it coming; when it is on them (2.5 m, coming their way, or 1.3 m at all) they start all at once - a jolt back from it (`TalkingCharacter.fear`: hands up, knees bent, eyes on it) - and whoever is in its way leaps aside to the nearest free spot off its way. Under a second after it has gone by they walk on (the walker plans again from where they ended up). Seated passengers are left alone (the user wants it seen in first person, from the ones in the aisle only). Mike does it too, less frightened.
- The screen: `shaders/ui/frenzy_screen.gdshader`, one full-screen pass with its levels set per stage (`FX_*` in anomaly_frenzy.gd).
- `TalkingCharacter`: `crawl`, `crawl_back`, `grab`, `grab_l/r`, `face_weights`, `head_twist`, `fear`, `fear_at`, posed after everything else.
- Textures and their sources: `art_source/frenzy/README.md`.
- Sounds: `assets/audio/frenzy_*.mp3` (ElevenLabs, raw takes in `art_source/audio_raw/frenzy/`).
- Tests: `tools/_test_frenzy.gd -- <out_dir> exposed|arrest|hunt|abort [slug,slug...]` plays it in the real scene with the chance at 100%, `-- - fate` counts the rolls; `exposed+crowd` (any mode with `+crowd`) first sends three of its car on errands, to be in its way, and reports the jumps aside and how near it came to anyone standing. `FILM_MIKE=1` with `arrest`: the anomaly whose nearest way out is on the guard's side, the player beyond it looking up the aisle at his way in (he walks into view, and it runs out past him). Add `--write-movie <file>.avi --fixed-fps 30` and use `-` for the out dir to film it. `tools/_look_monster.gd -- <out_dir> face|side|smile|crawl|hand [slug ...]`: stills of each anomaly in a dark room; `tools/_look_fear.gd -- <out_dir> stand|seat [slug ...]`: a passenger calm and frightened.

## Double-track stretches (`scripts/gameplay/passing_train.gd`)
Open stretches of the line, clear of stations and level crossings by 180 m / 40 m and `spacing` (3500 m) apart, have a second track at z = +4.2. The halved line has room for two: about 12.7 km (half-way through the shift, minute ~10.5) and 20.5 km (minute ~17.5). (Before 2026-11-03 the 7 km spacing and the 2 km end margin left only one, at 12.7 km, and `_test_passing` failed on it.) On up to 3 of them per journey a goods train comes the other way: a whistle, its headlamp, then as it draws level with Kevin every lamp in the train goes out for 4 seconds. The lamps stutter back and 1-3 apparitions are there: one standing in front of Kevin, the others in seats that were empty. They stay up to 7 seconds, or vanish if he comes within 1.5 m, and nearby passengers react in subtitles. The event waits if a conversation or an escort is on. Switches keep their state.

Settings on PassingTrain: `max_events` 3, `their_speed` 18 m/s, `wagons` 15, `dark_seconds` 4, `ghosts_min/max` 1-3, `show_seconds` 7, `vanish_near` 1.5. Test: `tools/_test_passing.gd -- <out_dir> saloon|window|outside`.

## Money, work and the day
The shift is 20 real minutes: the line is 22.25 km (RouteData halved on 2026-11-03), the train runs at 30 m/s with 25 s at each stop, and the timetable (19.10 Královec to 21.15 Kamenný Most) is kept by the clock at 6.4 game minutes a real minute.

**Money** (`Economy`, dollars, each line booked once by its id; the wallet carries over to the next day):

| What | $ |
|---|---|
| Base pay for the shift (when he turns in) | +120 |
| A work order done by its deadline / missed (finishing it late earns nothing more) | +15 / −10 |
| Jim's fee, on a day he was asked | −10 |
| An anomaly held | +15 |
| An anomaly questioned and left free / never checked | −15 / −10 |
| An anomaly out of a cage left open, not caught again in its new face | −15 |
| An anomaly that attacked him and leapt from the train (a jumpscare, not his fault) | 0 |
| An ordinary passenger wrongly held | −20 |
| A ghost laid to rest before it broke anything | +15 |
| Each breakdown a ghost caused (the repair is a work order of its own) | −10 |
| A ghost still riding at the end of the day | −20 |

**Work orders** (`TaskBoard`, made by `Chores`; in the HUD's list with their deadline and the time left):
- Every day: heating on in both coaches (it starts the night off) by 19.30; the sleeping car put to night lights (MAIN off, NIGHT on) by 19.50; every ticket checked in coach two by 19.40 and coach three by 19.55 (those seated as the train leaves the first station; anyone who gets off unchecked doesn't count, but at least half the list must have shown a ticket); two wake-up calls in the sleeping car (by the sleeper's stop, one stop each, the middle and the end of the night first); two berths to make up by 20.20.
- Now and then: a passenger wants a coffee (the cup on Kevin's desk, "Your coffee." in conversation, within 200 s), or whoever is in the holding cage wants a drink (Mike's message: his key is on the safe in his room).
- Making up a berth (`BerthJob`, E on the berth): pick up the waste if there is any (dried excrement - down any W.C. with E), strip the dirty bedding (a bundle for the hamper in the service room), scrub the stain with the brush (on the service room's chest of drawers, twice), lay clean linen from the service room shelves.

**Waking a passenger:** E on a sleeper. Its stop next: it sits up on the berth's edge and waits for it (a wake-up call made). Not yet: a grumble and back to sleep. A sleeper with a wake-up call nobody made sleeps through its stop and gets off at the next one (the order is missed). `WakeScare` (35% a day): one sleeper is not a passenger. Woken, it lies still a breath, rolls over to face him - an anomaly baring its teeth (MonsterFace) or a pale ghost with its mouth wide - screaming from the first frame, sits bolt upright at him with its hands at his head, the lamps of the car blink and the berth is empty. No HUD, no prompts, no chatter meanwhile; no money either way.

**The cage key** lies on the safe in Mike's room. In the toolbar, E at the cage gate unlocks and opens it, E again shuts and locks it. Left unlocked (open, or only pulled to) with Kevin more than 5 m off for 8 s, a held anomaly slips out: gone from the bench, and seated somewhere aboard in another anomaly's face (`Passengers.respawn_as`). Mike sends a message. Caught again, it counts as held; not, −15.

**Toolbar** (`Inventory`): four slots, E takes, 1-4 or the wheel picks the one in hand, Q puts it down in front of him. Things used up go back where they came from (the coffee cup to the desk) or are gone (the waste, the dirty bedding, the linen).

**HUD** (`ShiftHUD`): the toolbar with pictures of the things (made at run time by photographing each model), the clock and the time left in the shift, the wallet and today's money, the ghost's timer once he knows of the haunting (`HauntDirector.ghost_timer()`), and the work orders. Hidden at a terminal, in a conversation and over a big scare (`HorrorDirector.hold`).

**End of the day** (`EndOfDay`): at Kamenný Most the shift is over (a message says so). The bed in Kevin's room: "E — Turn in" - the screen goes dark, open orders are called off, the record counts what is left, the base pay goes in, and the summary shows what happened and the pay slip. "Sleep" starts the next day: the wallet carried over (`Economy.carry`), saved to `user://campaign.json` (`--continue` on the command line starts from it), yesterday's terminal records cleared.

Film of a whole shift: `tools/_film_shift.gd` (with `--write-movie <file>.avi --fixed-fps 30`, about 70 minutes to render 20): Kevin played by a script in first person - he walks with W toward the way ahead on the staff grid, opens doors as he comes to them (shuts W.C. doors left open across the vestibules), steps aside for people in the aisle, and talks, uses the terminal and the cabinets through their real interactions; prints `MARK <frame> <clock> <what>`. The AVI is 1920x1080: scale it in Blender's VSE (`strip.transform.scale_x/y = 2/3` for 1280x720), a smaller render size crops the middle.

Test: `tools/_test_economy.gd -- <out_dir|-> [tasks,berth,wake,coffee,cage,scare,scare_ghost,day,nextday]` (windowed for the pictures; add `--write-movie <file>.avi --fixed-fps 30` with `scare,scare_ghost` to film the scare).

## Audio mix (`default_bus_layout.tres`, `scripts/audio/game_audio.gd`, `dread_bed.gd`)

Buses: **Master** (HardLimiter, ceiling −1 dB) ← **Music**, **SFX**, **Ambience** (a compressor keyed by Voice ducks it a few dB while someone talks nearby), **Voice**, **UI**, **Outside** (→ Ambience; a low-pass that GameAudio closes to 700 Hz and −6 dB while Kevin is indoors). The Settings sliders own the volume of Master/Music/SFX/Ambience/Voice/UI, so the mix itself never sets those gains.

Routing, with no edits in gameplay scripts: GameAudio's own players are set directly (rails, engine idle, terminal hum → Ambience; wind → Outside; the one-shot pool → SFX). Every other AudioStreamPlayer/3D that enters the tree still on Master is routed by `GameAudio._route` one frame later: Ambience for wind/idle/hum/dread clips, Music for `/music/` or `music*`, Voice for `/voice*` or `voice*`, UI for `ui_*` or a non-positional player under a Control/CanvasLayer, else SFX (scares, the goods train, the cage lock…). A player that names its own bus keeps it (the whistle on Outside). The talking characters' lip-sync buses (`Voice_<id>`) are re-sent to Voice whenever the bus layout changes. The main menu has no GameAudio, so its UI players should set `bus = "UI"` themselves.

Headroom: every clip in `assets/audio` peaks at −1.3 dBFS or lower. The 12 ElevenLabs MP3s that went over −1 dB (up to +1.5) were re-normalized in place to about −1.7 dB; the originals are in `art_source/audio_peak_backup/`.

**Dread bed** (P2 horror layer): two baked seamless loops (`assets/audio/dread_low.wav`, `dread_high.wav`, from `tools/bake_dread.py`) on Music. One level drives both:
- `GameAudio.dread(level, seconds := 3.0)`: 0 = silent, 1 = full. It glides there over `seconds`; 0 seconds jumps at once. It is a static function, so call it from anywhere.
- `GameAudio.dread_level()` reads the current level.
- 0.1–0.5 brings the sub drone out of the rails, a little darker as it grows; from 0.4 a wavering minor-second cluster joins and creeps sharp toward 1.
- Use: swell before an event (`dread(0.7, 6.0)`), then cut it on the hit (`dread(0.0, 0.0)`), so the sudden silence is part of the scare. Let it decay slowly afterwards (`dread(0.0, 4.0)`) when nothing hits. It is not wired into any scare yet: the pacing director decides when.

Test: `tools/_check_mix.gd -- [seconds=150]` (windowed, real time) captures Master before and after its limiter and fails on clipping.

## Front end, pause and settings (`scripts/ui/main_menu.gd`, `pause_menu.gd`, `settings.gd`, `settings_panel.gd`, `menu_style.gd`)

The game opens on `scenes/ui/main_menu.tscn` (the `run/main_scene`): Start shift (a fresh day 1), Continue (the day and wallet saved in `user://campaign.json`, put into `Economy.carry`), Settings, Quit. The journey loads on a thread behind "Boarding… n%". Before it, yesterday's manifest and names are cleared as for a new day.

**Pause:** Esc during the journey (`PauseMenu`, added to the root by `FPController._ready`, so journey.tscn has no line for it). It pauses the tree and frees the mouse, and on resume the mouse goes back to how it was. It offers Resume, Settings and Back to the main menu (the day's progress is dropped, and the save stays as it was). Esc that a terminal or a dialogue menu takes for itself never reaches it.

**Settings** (autoload `Settings`, saved to `user://settings.cfg`): plain properties. Change one with `Settings.set_value(key, v)`, which applies and saves it and emits `Settings.changed(key)`.

| Property | Range | Used by |
|---|---|---|
| `master/music/sfx/ambience/voice/ui_volume` | 0–1 (bus gain v², muted at 0; a missing bus is skipped) | the buses of the same name |
| `mouse_sensitivity`, `invert_y` | 0.2–3 × the controller's base, bool | FPController |
| `fov` | 70–100 | FPController (live) |
| `head_bob` | bool | FPController (walking bob only) |
| `camera_shake` | 0–1 | FPController: the train's sway and rail knocks, and scare trauma |
| `reduced_flashes` | bool; read `Settings.flash_scale()` (1, or 0.25) | **not wired yet**: the scare scripts |
| `jumpscare` | `Settings.Jumpscare.FULL/SOFT/OFF`; `stinger_db()` (0 / −9 / −80), `lunges_allowed()` | **not wired yet**: the scare scripts |
| `subtitle_size` | 20 / 24 / 32 / 40 px | Subtitles (live) |
| `resolution`, `fullscreen`, `vsync` | 4 sizes | the window, only once the player has changed one, so test command lines keep their size |

**Camera shake:** `FPController.add_trauma(amount)` (use 0.2 for a knock, 0.5 for a slam, 1.0 for a lunge). The shake is trauma², decays by `trauma_decay`/s, is scaled by `Settings.camera_shake`, and moves only the camera, never the body. It is off while the player is focused (terminal, dialogue, frenzy hold), because those own the camera.

Test: `tools/_test_frontend.gd -- <shot dir>` (windowed): menu → Start → Esc pause → FOV, volume and subtitle size change live → Esc back → resume → trauma → back to menu.

## Settings (exports)

| Where | Value | Default |
|---|---|---|
| Passengers | `trips_enabled`, `max_wandering` (at most out of their seats) | true, 2 |
| Passengers | `trip_check` / `trip_chance` | 9 s / 0.45 |
| Passengers | `trip_gap_min/max` (game minutes between errands for each passenger) | 25 / 70 |
| Passengers | `wc_seconds`, `window_seconds` (real time) | 18–35, 12–25 |
| Passengers | `calm_before_stop` (no errands this many metres before a stop) | 2600 |
| NpcMover | walking speed: passengers 0.8 m/s, Mike 1.0, escort 0.75 (real time; the 3× clock does not speed them up) | |
| MikeDuty | `patrol_first`, `patrol_every` (game minutes), `observe_seconds` | 19:25, 30, 5 |
| MikeDuty | `rest_enabled`, `rest_start`, `rest_latest`, `rest_minutes` | true, 20:20, 20:55, 10 |
| MikeDuty | `station_near` (metres before a stop when he goes to the vestibule) | 450 |
| Detention | `verify_minutes` (game minutes until the papers check) | 12 |
| Economy | `base_wage`, `task_bonus`, `task_fine`, `medium_fee` | 120, +15, −10, −10 |
| Economy | `anomaly_held`, `anomaly_left_free`, `anomaly_not_checked`, `wrongly_held` | +15, −15, −10, −20 |
| Economy | `ghost_rested`, `ghost_breakdown`, `ghost_left` | +15, −10, −20 |
| Chores | `heating_due`, `night_due`, `ticket_due`, `berths_due`, `wake_calls`, `berths_to_make` | 19.30, 19.50, 19.40/19.55, 20.20, 2, 2 |
| Chores | `special_first`, `special_gap`, `coffee_window` (real s) | 150, 140-200, 200 |
| WakeScare | `chance`, `calm`, `roll`, `stare`, `rise`, `reach`, `dark` | 0.35, 0.55, 0.12, 0.45, 0.14, 0.38, 0.2 |
| HoldingCage | `escape_after`, `away` | 8 s, 5 m |
| HorrorDirector | `enabled`, `flicker_mode` (FULL / REDUCED / OFF), `seed_value` | true, FULL, 0 |
| HorrorDirector | `first_after`, `build_seconds`, `rest_seconds`, `peak_wait`, `big_gap` (real seconds) | 75, 130–170, 40–60, 40, 150 (`tied_gap` 75) |
| HorrorDirector | `early_peak`, `minor_gap` (at tension 0 / 1), `scream_from`, `cooldown`, `weight` | 0.75, 55 / 30 s, 0.5, flicker 80 / giggle 110 / scream 240 s |
| PassingTrain | `max_events`, `spacing` | 3, 3500 m |
| WakeScare | `late_stops` | [4, 5] (Vysoké Pole, Stříbrná Hora) |
| Chores | `call_stops`, `special_last` | [3, 5, 4, 2, 6], 1500 m |
| AnomalyFrenzy | `enabled`, `violent_chance`, `wait_for_guard` | true, 0.18, 0.5 |
| AnomalyFrenzy | `crawl_speed`, `hunt_speed`, `hunt_seconds` | 6.5, 7.5, 16 |
| GhostStory | `intro_at`, `escalate_latest`, `follow_up_after`, `visible_max`, `vanish_near` | 19:32, 20:10, 8 min, 6 s, 4 m |

Sounds: `assets/audio/horror_giggle.mp3` and `horror_scream.mp3` (ElevenLabs, raw copies in `art_source/audio_raw/horror/`). If a file is missing, its event is skipped with a warning.

## Tests (tools/)
`_test_errands.gd`, `_test_escort.gd -- anomaly|normal`, `_test_mike.gd`, `_test_edges.gd`, `_test_horror.gd`, `_test_pacing.gd -- [seed] [speed]` (the night's timeline), `_playtest.gd -- <speed> <minutes>` (full journey, all natural), `_film.gd -- errand|escort|ghost|mike_rest` (demo clips).

## Kevin's clipboard, wristwatch and the car clocks (`clipboard.gd`, `wristwatch.gd`, `wall_clocks.gd`)
The screen no longer shows the time or the work orders: only the toolbar and the money stay on the HUD.
- **Clipboard (Tab):** a sheet in Kevin's own hand (Caveat font) on a clipboard he holds up. It lists tonight's jobs from the TaskBoard with their times; a done job gets its box ticked and its line struck through, a missed one "missed". When he notices a haunting he writes in, in red: "I need to investigate this strange incident soon" at the time it was found + 5 minutes, and under it "* call Jim he is an expert when it comes to these strange things". The note is struck through once the haunting is over.
- **Wristwatch (T):** his left forearm comes up with a digital watch (DSEG7 font, faintly lit), showing the train's clock; it goes down again on T, after 5 s, or when the clipboard comes up.
- **Wall clocks:** a red-on-black digital clock at both ends of every car: in the saloons beside the door (under the vent, over the signs), in the corridor cars over the corridor's end doors.
- Models: `assets/viewmodels/clipboard.glb` (art_source/viewmodels/make_clipboard.py: rounded hardboard, riveted clip with spring jaw, hinge roll and wire lever, sheets under the top one, a pencil under the clip) and `kevin_arm.glb` (make_kevin_arm.py: the forearm and gloved hand cut from the Mike model, the same uniform sleeve, the fingers loosely curled) and the watch from `make_watch.py`: `watch_head.glb` (a cushion-shaped steel case with barrel sides, a polished chamfered bezel, a black dial plate with its print, a recessed LCD, four pushers on collars, curved lugs and pins; `-- render <png>` gives a Cycles beauty shot) and `watch_link.glb` (a three-piece bracelet link). The watch is worn over the coat cuff, as with gloves: the bracelet's links are laid at runtime along the sleeve's own outline, the first ones rising to the pins. The crystal is in the model but hidden in game (a transparent dome mirrors the whole car); the watch has its own small lamp (render layer 19) so the steel shows a highlight.
- Fonts: Caveat and DSEG7 Classic, both SIL OFL 1.1 (licence files next to them in assets/fonts).
- Kevin's friend on the private line is now **Jim** (was Viktor).

