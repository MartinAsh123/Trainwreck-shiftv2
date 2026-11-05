class_name HorrorDirector
extends Node3D
## The night's pacing, and the small scares that fill it.
## The tension curve: a saw-tooth over the shift, build -> peak -> rest, over and over.
##   build    `tension` climbs from 0 to 1 over `build_seconds`; our minor signs (below) come more
##            often as it climbs (`minor_gap`), and a haunting's own signs stand in for them
##   peak     the slot for one big scare. The big ones (PassingTrain, WakeScare, AnomalyFrenzy, a
##            haunting's breakdown) ask big_ready(kind) before they start and report begin_big(kind) /
##            end_big(kind). Tied ones (a goods train on its stretch, a breakdown due) may come before
##            the slot opens, never within `tied_gap` of the last; free ones (a violent anomaly) wait for
##            the slot. A big one the player sets off himself (a sleeper he shakes) always goes and
##            counts as the peak. If nothing takes the slot within `peak_wait`, we make the peak
##            ourselves ("dread": the lamps falter long and deep while something screams in the dark) -
##            unless a goods train is due soon (PassingTrain.seconds_to_next): then the build holds at
##            its height, the signs coming fast, and the slot is left to it.
##   rest     `rest_seconds` of nothing of ours after every peak, then the next build.
## `hold` stays: something bigger is on (PassingTrain, WakeScare) and nothing else starts.
## Hooks, called only if there: GameAudio.dread(level) follows the tension; the player's add_trauma on
## the hits (trauma()).
## The minor signs, never two at once, never during a conversation, an escort or a stop:
##   flicker  the lamps around the player dim and stutter for a couple of seconds and recover: a
##            modifier on Light3D.light_energy only (switches turn lamps on and off through their
##            visibility, which this never touches), restored to exactly what each lamp had - or
##            left alone if something else changed it meanwhile. flicker_mode: FULL, REDUCED (a
##            gentle dip, no stutter) or OFF.
##   giggle   a little girl's giggle from somewhere inside the train 7-16 m away (a corridor end, a
##            vestibule, the next car), positional, never at the player's ear
##   scream   a scream from far off in the dark outside (50-80 m), muffled by distance, drifting
##            back as the train runs on (only once the tension is past `scream_from`)
## Natural events come from the curve (`seed` makes it repeatable); trigger(kind) runs one now
## (tests and story beats: forced events still wait for a conversation or an escort to end, and are
## reported as forced). enabled = false stops ours and lets every big one through unasked.

signal event_started(kind: String, forced: bool)
signal event_finished(kind: String)
signal phase_changed(phase: String)

enum FlickerMode { FULL, REDUCED, OFF }

@export var enabled := true
@export var flicker_mode: FlickerMode = FlickerMode.FULL
@export var seed_value := 0                       # 0: a different night each time
@export var first_after := 75.0                   # real seconds of calm at the start (the first rest)
@export var build_seconds := Vector2(130.0, 170.0)
@export var rest_seconds := Vector2(40.0, 60.0)
@export var peak_wait := 40.0                     # seconds the slot stays open before we take it
@export var big_gap := 150.0                      # real seconds from the end of one big scare to the next
@export var tied_gap := 75.0                      # the same for one tied to the line or a deadline
@export var early_peak := 0.75                    # tension from which a free big one may come early
@export var minor_gap := Vector2(55.0, 30.0)      # real seconds between our signs, at tension 0 / 1
@export var scream_from := 0.5
@export var cooldown := {"flicker": 80.0, "giggle": 110.0, "scream": 240.0}
@export var weight := {"flicker": 3.0, "giggle": 2.0, "scream": 1.0}
@export var flicker_radius := 9.0
@export var flicker_max_lamps := 6
@export var log_skips := false                    # (tests) a sign due that could not start goes on the timeline

const GIGGLE := "res://assets/audio/horror_giggle.mp3"
const SCREAM := "res://assets/audio/horror_scream.mp3"
const BIG_TIMEOUT := 90.0                         # a big one never reported over ends itself after this

var active := ""                                  # the minor event running now ("" for none)
var hold := false                                 # something bigger is on (PassingTrain): nothing starts
var history: Array = []                           # [clock text, kind, forced] (tests, the log)
var phase := "rest"                               # build | peak | rest
var tension := 0.0                                # 0..1, the curve
var big := ""                                     # the big scare running now ("" for none)
var timeline: Array = []                          # [real seconds, clock text, kind, tier] (tests, the log)
var _rng := RandomNumberGenerator.new()
var _next := 0.0                                  # when our next minor sign is due
var _last := {}                                    # kind -> time it last ran (real seconds)
var _time := 0.0
var _queued: Array = []                            # forced events waiting for a quiet moment
var _phase_t := 0.0
var _phase_len := 0.0
var _big_t := 0.0
var _big_end := -1e9                               # when the last big one ended
var _dread_sent := -1.0
var _dread_t := 0.0
var _first := true                                 # the calm at the start (first_after) still on
var _audio: Node
# flicker
var _lamps: Array = []                             # [Light3D, base energy, last set]
var _ft := 0.0
var _keys: PackedVector2Array
# sound
var _player3d: AudioStreamPlayer3D
var _drift := false

static func of(n: Node) -> HorrorDirector:
	return n.get_tree().get_first_node_in_group("horror") as HorrorDirector

func _ready() -> void:
	add_to_group("horror")
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_phase_len = first_after
	_next = first_after

func _exit_tree() -> void:
	_end_flicker()
	_stop_sound()

## Runs an event as soon as it is safe (a forced, test or story, event); false if unknown.
func trigger(kind: String, at: Variant = null) -> bool:
	if not kind in ["flicker", "giggle", "scream", "dread"]:
		return false
	_queued.append([kind, at])
	return true

## No conversation or escort under way.
func calm() -> bool:
	var menu := get_tree().root.get_node_or_null("DialogueMenu") as CanvasItem
	if menu and menu.visible:
		return false
	var duty := MikeDuty.of(self)
	if duty and duty.job in ["escort", "release"] and duty.phase in ["arrest", "open", "enter", "close", "out", "lock"]:
		return false
	return true

# ————— the curve —————

## May a big scare start now? `free`: it can wait for the slot (a violent anomaly); otherwise it is
## tied to a place or a deadline (a goods train, a breakdown) and only needs the gap since the last.
func big_ready(kind: String, free := true) -> bool:
	if hold or big != "" or active != "":
		return false
	if not enabled:
		return true
	if phase == "rest" or _time - _big_end < (big_gap if free else tied_gap):
		return false
	return not free or phase == "peak" or tension >= early_peak

## A big scare has started (asked for, or set off by the player).
func begin_big(kind: String, forced := false) -> void:
	big = kind
	_big_t = 0.0
	_set_phase("peak")
	_dread(0.0, 0.0)                               # (silence before the hit: the scare has its own sound)
	mark(kind, "big" if not forced else "big (player)")

## It is over: the rest starts.
func end_big(kind: String) -> void:
	if big == "" or (kind != big and kind != ""):
		return
	big = ""
	_big_end = _time
	_set_phase("rest")

## A big scare is on, or the rest after one (not the calm at the start): the others keep quiet.
func resting() -> bool:
	return big != "" or (phase == "rest" and not _first)

## Something on the night's timeline (other systems' work and signs too: tests, the log).
func mark(kind: String, tier: String) -> void:
	timeline.append([_time, TerminalData.clock_text(), kind, tier])

## Shakes the player's camera (FPController.add_trauma, if it has it).
func trauma(amount: float) -> void:
	var p := _player()
	if p and p.has_method("add_trauma"):
		p.call("add_trauma", amount)

func _set_phase(p: String) -> void:
	phase = p
	_phase_t = 0.0
	match p:
		"build":
			tension = 0.0
			_phase_len = _rng.randf_range(build_seconds.x, build_seconds.y)
			_next = _time + _minor_wait()
		"peak":
			tension = 1.0
			_phase_len = peak_wait
		"rest":
			tension = 0.0
			_phase_len = _rng.randf_range(rest_seconds.x, rest_seconds.y)
	phase_changed.emit(p)

func _minor_wait() -> float:
	return lerpf(minor_gap.x, minor_gap.y, tension) * _rng.randf_range(0.8, 1.2)

func _update_curve(delta: float) -> void:
	_phase_t += delta
	if big != "":
		_big_t += delta
		if _big_t > BIG_TIMEOUT and not hold:
			end_big(big)
		return
	match phase:
		"rest":
			if (_time >= first_after) if _first else (_phase_t >= _phase_len):
				_first = false
				_set_phase("build")
		"build":
			tension = clampf(_phase_t / _phase_len, 0.0, 1.0)
			if _phase_t >= _phase_len and not fixed_soon():
				_set_phase("peak")
		"peak":
			if fixed_soon():
				phase = "build"                        # (held at the top for the goods train coming)
				_phase_t = _phase_len
				phase_changed.emit(phase)
			# The slot stayed empty: the peak is ours.
			elif _phase_t >= _phase_len and enabled and active == "" and not hold and calm() and _running():
				if _start("dread", false):
					mark("dread", "big")
					big = "dread"
					_big_t = 0.0
				else:
					_phase_t = _phase_len - 5.0
	_dread_t -= delta
	if _dread_t <= 0.0:
		_dread_t = 1.0
		var lv := 0.05 if phase == "rest" else (lerpf(0.12, 0.6, tension) if phase == "build" else 0.7)
		if absf(lv - _dread_sent) > 0.04:
			_dread(lv, 4.0)

# GameAudio.dread(level, seconds), if the audio has it.
func _dread(level: float, seconds: float) -> void:
	_dread_sent = level
	if _audio == null or not is_instance_valid(_audio):
		_audio = get_tree().root.find_child("Audio", true, false)
	if _audio and _audio.has_method("dread"):
		_audio.call("dread", level, seconds)

## A goods train is due soon: our own peak, or a breakdown that can wait, would only shut it out.
func fixed_soon() -> bool:
	var pt := get_tree().get_first_node_in_group("passing_train")
	return pt != null and pt.has_method("seconds_to_next") and float(pt.call("seconds_to_next")) < big_gap + 40.0

func _running() -> bool:
	var ts := get_node_or_null("/root/TrainState")
	return ts == null or str(ts.get("phase")) == "running"

# A haunting is giving its own signs: ours keep out of the way.
func _haunting() -> bool:
	var h := get_tree().get_first_node_in_group("haunt")
	return h != null and str(h.get("stage")) == "signs"

func _process(delta: float) -> void:
	_time += delta
	_update_curve(delta)
	match active:
		"flicker":
			_update_flicker(delta)
			return
		"dread":
			if _drift and _player3d:
				_drift_sound(delta)
			if not _lamps.is_empty() or _ft < _keys[_keys.size() - 1].x:
				_update_flicker(delta, false)
			elif _player3d == null or not _player3d.playing:
				_finish()
			return
		"giggle", "scream":
			if _drift and _player3d:
				_drift_sound(delta)
			if _player3d == null or not _player3d.playing:
				_finish()
			return
	if hold or not calm():
		return
	if not _queued.is_empty():
		var q: Array = _queued.pop_front()
		_start(q[0], true, q[1])
		return
	if not enabled or phase != "build" or _time < _next or big != "":
		return
	if not _running():
		_next = _time + 20.0
		return
	if _haunting():
		_next = _time + 30.0
		return
	# The one picked, or another if that one has nowhere to happen (no lamp lit near him, no corner).
	var tried: Array = []
	var kind := _pick(tried)
	while kind != "" and not _start(kind, false):
		tried.append(kind)
		kind = _pick(tried)
	if kind == "":
		if log_skips:
			mark("no sign could start (tried %s)" % [tried], "debug")
		_next = _time + 20.0
		return
	_next = _time + _minor_wait()

func _drift_sound(delta: float) -> void:
	var ts := get_node_or_null("/root/TrainState")
	if ts:
		_player3d.global_position.x += float(ts.get("speed")) * delta

func _pick(skip: Array = []) -> String:
	var total := 0.0
	var can := {}
	for k: String in weight:
		if k in skip or (k == "flicker" and flicker_mode == FlickerMode.OFF):
			continue
		if k == "scream" and tension < scream_from:
			continue
		if _last.has(k) and _time - float(_last[k]) < float(cooldown.get(k, 120.0)):
			continue
		can[k] = float(weight[k])
		total += float(weight[k])
	if total <= 0.0:
		return ""
	var x := _rng.randf() * total
	for k: String in can:
		x -= float(can[k])
		if x <= 0.0:
			return k
	return can.keys().back()

func _start(kind: String, forced: bool, at: Variant = null) -> bool:
	var ok := false
	match kind:
		"flicker":
			ok = _start_flicker(at)
		"giggle":
			ok = _start_sound(GIGGLE, _giggle_spot() if at == null else at, 1.6, 26.0, -4.0, 6000.0, false)
		"scream":
			ok = _start_sound(SCREAM, _scream_spot() if at == null else at, 14.0, 140.0, 2.0, 2200.0, true)
		"dread":
			# Long and deep, and the scream with it (a lamp-less corridor: the scream alone).
			ok = _start_sound(SCREAM, _scream_spot(), 14.0, 140.0, 4.0, 2600.0, true)
			if ok and flicker_mode != FlickerMode.OFF and _start_flicker(at, 2):
				pass
			elif ok:
				_keys = PackedVector2Array([Vector2(0.0, 1.0)])
				_ft = 0.0
	if not ok:
		return false
	active = kind
	_last[kind] = _time
	history.append([TerminalData.clock_text(), kind, forced])
	if kind != "dread":
		mark(kind, "sign" if not forced else "sign (forced)")
	event_started.emit(kind, forced)
	return true

func _finish() -> void:
	var k := active
	active = ""
	_stop_sound()
	if k == "dread" and big == "dread":
		end_big("dread")
	event_finished.emit(k)

# ————— the lamps —————

func _player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p if p else get_tree().root.find_child("Player", true, false) as Node3D

func _start_flicker(at: Variant, dips := 1) -> bool:
	if flicker_mode == FlickerMode.OFF:
		return false
	var centre: Vector3
	if at is Vector3:
		centre = at
	else:
		var p := _player()
		if p == null:
			return false
		centre = p.global_position
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	if train == null:
		return false
	var found: Array = []
	for l: Light3D in train.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D or not l.is_visible_in_tree() or l.light_energy <= 0.01:
			continue                               # switched off stays off
		var d := l.global_position.distance_to(centre)
		if d < flicker_radius:
			found.append([d, l])
	if found.is_empty():
		return false
	found.sort_custom(func(a, b): return a[0] < b[0])
	_lamps.clear()
	for i in mini(found.size(), flicker_max_lamps):
		var l: Light3D = found[i][1]
		_lamps.append([l, l.light_energy, l.light_energy])
	# The shape of the dip: (time, factor). Irregular, a few seconds, then back to full.
	_keys = PackedVector2Array()
	if flicker_mode == FlickerMode.REDUCED:
		_keys.append_array([Vector2(0.0, 1.0), Vector2(0.6, 0.55), Vector2(1.8, 0.6), Vector2(2.6, 1.0)])
	else:
		var t := 0.0
		_keys.append(Vector2(0.0, 1.0))
		for d in dips:
			for i in _rng.randi_range(3, 5):
				t += _rng.randf_range(0.12, 0.45)
				_keys.append(Vector2(t, _rng.randf_range(0.05, 0.35) * (0.5 if d > 0 else 1.0)))
				t += _rng.randf_range(0.1, 0.35)
				_keys.append(Vector2(t, _rng.randf_range(0.55, 0.95)))
			t += 0.4
			_keys.append(Vector2(t, 0.15 if d == 0 else 0.03))
			t += _rng.randf_range(0.5, 0.9) * (1.0 if d == dips - 1 else 2.0)
			if d < dips - 1:
				_keys.append(Vector2(t, 0.05))     # (held down there a moment, nearly out)
		_keys.append(Vector2(t + (0.0 if dips == 1 else 0.6), 1.0))
	_ft = 0.0
	return true

func _factor(t: float) -> float:
	for i in _keys.size() - 1:
		if t < _keys[i + 1].x:
			var a := _keys[i]
			var b := _keys[i + 1]
			return lerpf(a.y, b.y, smoothstep(0.0, 1.0, (t - a.x) / maxf(b.x - a.x, 0.001)))
	return 1.0

func _update_flicker(delta: float, finish := true) -> void:
	_ft += delta
	var f := _factor(_ft)
	for e: Array in _lamps:
		var l: Light3D = e[0]
		if not is_instance_valid(l):
			continue
		if not is_equal_approx(l.light_energy, float(e[2])):
			e[0] = null                            # someone else set it: leave it be from now on
			continue
		l.light_energy = float(e[1]) * f
		e[2] = l.light_energy
	_lamps = _lamps.filter(func(e): return e[0] != null)
	if _ft >= _keys[_keys.size() - 1].x:
		_end_flicker()
		if finish:
			_finish()

## Every lamp back to exactly its own energy (also on an interruption).
func _end_flicker() -> void:
	for e: Array in _lamps:
		var l: Light3D = e[0]
		if l != null and is_instance_valid(l) and is_equal_approx(l.light_energy, float(e[2])):
			l.light_energy = float(e[1])
	_lamps.clear()

# ————— the sounds —————

# Somewhere inside the train 7-16 m from the player: a corridor end, a vestibule, a gangway.
func _giggle_spot() -> Variant:
	var p := _player()
	if p == null:
		return null
	var spots := [Vector3(23.0, 2.4, -1.0), Vector3(12.0, 2.4, -1.0), Vector3(10.2, 2.4, 0.0), Vector3(7.4, 2.4, -0.6),
		Vector3(-7.2, 2.4, 0.0), Vector3(-11.0, 2.4, -0.6), Vector3(-24.7, 2.4, 0.0), Vector3(-28.0, 2.4, -0.9),
		Vector3(-42.0, 2.4, 0.0), Vector3(-46.0, 2.4, -0.4), Vector3(17.4, 2.4, -1.0)]
	var ok: Array = []
	for s: Vector3 in spots:
		var d := s.distance_to(p.global_position)
		if d > 7.0 and d < 16.0:
			ok.append(s)
	return ok[_rng.randi_range(0, ok.size() - 1)] if not ok.is_empty() else null

# Far out in the dark to one side, a little behind.
func _scream_spot() -> Variant:
	var p := _player()
	if p == null:
		return null
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	return Vector3(p.global_position.x + _rng.randf_range(10.0, 35.0), 1.0, side * _rng.randf_range(50.0, 75.0))

func _start_sound(path: String, at: Variant, unit: float, max_d: float, db: float, cutoff: float, drift: bool) -> bool:
	if at == null or not ResourceLoader.exists(path):
		if not ResourceLoader.exists(path):
			push_warning("HorrorDirector: missing sound %s - event skipped" % path)
		return false
	_stop_sound()
	_player3d = AudioStreamPlayer3D.new()
	_player3d.stream = load(path)
	_player3d.unit_size = unit
	_player3d.max_distance = max_d
	_player3d.volume_db = db
	_player3d.attenuation_filter_cutoff_hz = cutoff
	_player3d.attenuation_filter_db = -18.0
	_player3d.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(_player3d)
	_player3d.global_position = at
	_player3d.play()
	_drift = drift
	return true

func _stop_sound() -> void:
	if _player3d and is_instance_valid(_player3d):
		_player3d.stop()
		_player3d.queue_free()
	_player3d = null
	_drift = false

func sound_position() -> Vector3:
	return _player3d.global_position if _player3d else Vector3.INF
