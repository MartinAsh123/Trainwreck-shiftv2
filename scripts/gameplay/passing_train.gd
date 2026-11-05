class_name PassingTrain
extends Node3D
## Double-track stretches of the line, and what happens on them. On a few open stretches a second
## track runs beside the main line (z = +4.2, the side away from the telegraph poles), joining it by a
## curve at each end; each is a mesh like the station loops (StationYard's rails, ballast, sleepers),
## scrolled with the land. On such a stretch, when nobody is busy, a goods train comes the other way:
## a whistle, its lamp, and as it draws level with Kevin every lamp in our train dies for four seconds
## (a modifier, as HorrorDirector's flicker: switches keep their state). When the lamps stutter back,
## apparitions are there that were not there before: standing in front of him, or sitting in seats
## nobody sat in. They look at him, and fade after a few seconds or as he comes close; they are
## separate figures (faces nobody wears at that moment, no collision, their own pale materials).

const HDProps := preload("res://scripts/train/hd_props.gd")
const TRACK_Z := 4.2
const HALF := 700.0                    # half a stretch, metres
const CURVE := 90.0                    # the curve joining the main line at each end
# One passenger, once it is all over, quietly, talking himself out of it.
const REACT := ["...Did anyone else see that? No. I must have imagined it.",
	"I thought there was someone standing there... My eyes. I must have imagined it."]
const LUNGE_AT := 0.6                  # seconds of the lamps back before the one on its feet comes at him
const LUNGE := 0.26                    # seconds it takes to reach his face
const IN_FACE := 0.14                  # seconds it stays there before the lamps blink
const GIGGLE := "res://assets/audio/horror_giggle.mp3"   # a little girl, close by, in the dark
const SCARE := "res://assets/audio/pass_scare.mp3"       # her shriek as the lamps come back

@export var enabled := true
@export var max_events := 3
@export var spacing := 3500.0          # metres between two stretches at least
@export var their_speed := 18.0        # m/s over the ground
@export var wagons := 15
@export var dark_seconds := 4.0        # how long every lamp is out
@export var ghosts_min := 1
@export var ghosts_max := 3
@export var show_seconds := 7.0        # how long the apparitions stay, at most
@export var vanish_near := 0.8         # metres (on the floor): come this close and it is gone

var sections := PackedFloat32Array()   # middle of each stretch (route position)
var state := "idle"                    # idle | coming | dark | show
var history: Array = []                # what happened (tests, the log)
var count := 0

var _ts: Node
var _pax: Passengers
var _hd: HorrorDirector
var _nav: TrainNav
var _rng := RandomNumberGenerator.new()
var _loops: Array = []                 # one node per stretch
var _next := 0                         # the next stretch to use
var _train: Node3D
var _blink := 0.0                      # seconds until the lamps come back after the lunge
var _head_x := 0.0                     # the goods train's nose (world x)
var _length := 170.0
var _whistled := false
var _t := 0.0
var _lights: Array = []                # [Light3D, energy]
var _switches: Array = []
var _lit := true
var _faces: Array = []                 # character folders being loaded for this event
var _figures: Array = []               # [{body, fade, seat, slug}]
var _rumble: AudioStreamPlayer3D
var _rumbles: Array = []               # rolling noise along the whole goods train (front, middle, tail)
var _roared := false
var _chuff_t := 0.0
var _audio: Node                       # GameAudio (its one-shot pool, for the engine's chuffs)

static func of(n: Node) -> PassingTrain:
	return n.get_tree().get_first_node_in_group("passing_train") as PassingTrain

func _ready() -> void:
	add_to_group("passing_train")
	_rng.randomize()
	_ts = get_node_or_null("/root/TrainState")
	_pick_sections()
	_setup.call_deferred()

func _setup() -> void:
	await get_tree().process_frame
	_pax = get_tree().root.find_child("Passengers", true, false) as Passengers
	_hd = HorrorDirector.of(self)
	StationYard.warm()
	_build_loops()
	_build_train()

# Open stretches only: clear of every station, halt and level crossing, spread along the line (the
# middle of each clear run, `spacing` apart at least). The halved line has room for two: about 12.7 km
# (half-way through the shift) and 20.5 km (three minutes before the end).
func _pick_sections() -> void:
	var margin := HALF + 180.0
	var run_from := -1.0
	var s := 3000.0
	while s < RouteData.end_s() - 1500.0 + 100.0:
		var ok := s < RouteData.end_s() - 1500.0
		for st: Dictionary in RouteData.STATIONS:
			if absf(float(st.s) - s) < margin:
				ok = false
		for cr: Dictionary in RoadNetwork.crossings():
			if absf(float(cr.s) - s) < HALF + 40.0:
				ok = false
		if ok and run_from < 0.0:
			run_from = s
		elif not ok and run_from >= 0.0:
			var mid := snappedf((run_from + s - 100.0) * 0.5, 50.0)
			if sections.size() < 5 and (sections.is_empty() or mid - sections[sections.size() - 1] > spacing):
				sections.append(mid)
			run_from = -1.0
		s += 100.0

# ————— the second track —————

func _track_path() -> PackedVector2Array:
	var out := PackedVector2Array()
	var x := HALF
	while x >= -HALF - 0.01:
		var ax := absf(x)
		var edge := HALF - ax                          # metres in from the end of the stretch
		var k := 1.0 if edge >= CURVE else 0.5 - 0.5 * cos(PI * edge / CURVE)
		out.append(Vector2(x, TRACK_Z * k))
		x -= 3.0 if edge < CURVE + 3.0 else 40.0
	return out

func _build_loops() -> void:
	var p := _track_path()
	var rails := StationYard._rails(p)
	var ballast := StationYard._ballast(p, -0.012)
	var xfs: Array = StationYard._sleeper_xfs(p)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = SceneryMeshes.get_mesh("sleeper")
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	for s in sections:
		var n := Node3D.new()
		n.name = "Loop_%d" % int(s)
		n.set_meta("s", s)
		n.visible = false
		var r := MeshInstance3D.new()
		r.mesh = rails
		n.add_child(r)
		var b := MeshInstance3D.new()
		b.mesh = ballast
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(b)
		var sl := MultiMeshInstance3D.new()
		sl.multimesh = mm
		sl.visibility_range_end = 450.0
		sl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(sl)
		add_child(n)
		_loops.append(n)

# ————— the goods train —————

func _build_train() -> void:
	_train = Node3D.new()
	_train.name = "GoodsTrain"
	_train.visible = false
	add_child(_train)
	# The same engine as ours, nose first along +x.
	var loco := Node3D.new()
	loco.name = "Loco"
	loco.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.4, 0))
	_train.add_child(loco)
	for part in ["loco_frames", "loco_boiler", "loco_cab", "loco_tender"]:
		HDProps.place(loco, part)
	# Its boxcars behind it.
	var x := -5.5
	for i in wagons:
		if StationModels.mesh("boxcar") != null:
			StationModels.place(_train, "boxcar", Transform3D(Basis.IDENTITY, Vector3(x, 0.15, 0)), 900.0)
		x -= 8.9
	_length = -x + 22.4
	# The headlamp, and a red lamp on the last wagon.
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.6)
	lamp.light_energy = 9.0
	lamp.spot_range = 90.0
	lamp.spot_angle = 22.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(22.6, 3.0, 0)
	lamp.rotation.y = -PI * 0.5                        # looks along +x
	_train.add_child(lamp)
	var tail := OmniLight3D.new()
	tail.light_color = Color(1.0, 0.1, 0.05)
	tail.light_energy = 1.6
	tail.omni_range = 7.0
	tail.position = Vector3(x + 3.0, 2.6, 0)
	_train.add_child(tail)
	var st: AudioStream = (load("res://assets/audio/rail_loop.mp3") as AudioStream).duplicate()
	if "loop" in st:
		st.set("loop", true)
	for k in 3:                                        # wheels rolling at the front, middle and tail
		var r := AudioStreamPlayer3D.new()
		r.stream = st
		r.unit_size = 22.0
		r.max_distance = 420.0
		r.volume_db = 12.0
		r.pitch_scale = 0.82 + k * 0.05
		r.position = Vector3(lerpf(15.0, x + 4.0, k / 2.0), 1.0, 0)
		_train.add_child(r)
		_rumbles.append(r)
	_rumble = _rumbles[0]
	_train.position = Vector3(0, 0, TRACK_Z)

func _player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p if p else get_tree().root.find_child("Player", true, false) as Node3D

# ————— every frame —————

func _process(delta: float) -> void:
	if _ts == null or _loops.is_empty():
		return
	var d := float(_ts.get("distance"))
	for n: Node3D in _loops:
		var x := d - float(n.get_meta("s"))
		n.position.x = x
		n.visible = absf(x) < 1500.0
	_move_train(delta)
	match state:
		"idle":
			_look_for_stretch(d)
		"coming":
			_update_coming()
		"dark":
			_update_dark(delta)
		"show":
			_update_show(delta)

func _move_train(delta: float) -> void:
	if _train == null or not _train.visible:
		return
	_head_x += (float(_ts.get("speed")) + their_speed) * delta
	_train.position.x = _head_x
	# The engine working: a chuff on each beat, heard as it comes near.
	_chuff_t -= delta
	var p := _player()
	if _chuff_t <= 0.0 and p and absf(p.global_position.x - _head_x) < 320.0:
		_chuff_t = 0.19
		if _audio == null:
			_audio = get_tree().root.find_child("Audio", true, false)
		if _audio and _audio.has_method("play_at"):
			_audio.call("play_at", "loco_chuff", Vector3(_head_x + 14.0, 4.2, TRACK_Z), 2.0, 0.1)
	if _head_x - _length > 300.0:                      # well behind us: gone
		_train.visible = false
		for r: AudioStreamPlayer3D in _rumbles:
			r.stop()

func _look_for_stretch(d: float) -> void:
	if not enabled or count >= max_events or _next >= sections.size() or _train == null or _train.visible:
		return
	var s := sections[_next]
	if d > s + 150.0:                                  # gone by with no chance
		_next += 1
		return
	if d < s - 320.0:
		return
	if str(_ts.get("phase")) != "running" or float(_ts.get("speed")) < 15.0:
		return
	if _hd and (not _hd.big_ready("goods_train", false) or not _hd.calm()):
		return                                         # (the night's curve says not now: maybe further on)
	_next += 1
	_start()

## Roughly how long until the next stretch it could use (INF: none left). For the night's pacing.
func seconds_to_next() -> float:
	if not enabled or count >= max_events or _next >= sections.size() or _ts == null:
		return INF
	return maxf(0.0, sections[_next] - 320.0 - float(_ts.get("distance"))) / 25.0   # (stops on the way: well under line speed)

## Sends the goods train now (a stretch must be under us; tests and the like).
func start_now() -> void:
	_start()

func _start() -> void:
	state = "coming"
	count += 1
	_whistled = false
	_head_x = -84.0 - 40.0 * 13.0
	_train.position.x = _head_x
	_train.visible = true
	for r: AudioStreamPlayer3D in _rumbles:
		r.play(_rng.randf() * 3.0)
	_roared = false
	if _hd:
		_hd.hold = true                                # (no other scare over this one)
		_hd.begin_big("goods train")
	_load_faces()
	history.append([TerminalData.clock_text(), "goods train"])

func _update_coming() -> void:
	var p := _player()
	var px: float = p.global_position.x if p else 0.0
	var v := float(_ts.get("speed")) + their_speed
	if not _whistled and (px - _head_x) / maxf(v, 1.0) < 6.0:
		_whistled = true
		var w := AudioStreamPlayer3D.new()
		w.stream = load("res://assets/audio/loco_whistle.wav")
		w.unit_size = 70.0
		w.max_distance = 900.0
		w.volume_db = 8.0
		w.pitch_scale = 0.86
		_train.add_child(w)
		w.position = Vector3(10.0, 4.0, 0)
		w.play()
		w.finished.connect(w.queue_free)
	# The roar of it going by, timed to peak as the engine draws level.
	if not _roared and _head_x >= px - 0.9 * v:
		_roared = true
		var roar := AudioStreamPlayer3D.new()
		roar.stream = load("res://assets/audio/train_passing.mp3")
		roar.unit_size = 24.0
		roar.max_distance = 300.0
		roar.volume_db = 8.0
		add_child(roar)
		roar.global_position = Vector3(px, 2.0, TRACK_Z)
		roar.play()
		roar.finished.connect(roar.queue_free)
	if _head_x >= px - 8.0:
		_go_dark()

# ————— the blackout —————

func _collect_lamps() -> void:
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	_lights.clear()
	_switches = train.find_children("*", "LightSwitch", true, false)
	for l: Light3D in train.find_children("*", "Light3D", true, false):
		if not l is DirectionalLight3D:
			_lights.append([l, l.light_energy])

func _go_dark() -> void:
	state = "dark"
	if _pax:
		_pax.hush = dark_seconds + 2.0
	_t = 0.0
	_collect_lamps()
	_set_lit(false)
	history.append([TerminalData.clock_text(), "blackout"])

func _set_lit(on: bool) -> void:
	_lit = on
	for e: Array in _lights:
		var l: Light3D = e[0]
		if is_instance_valid(l):
			l.light_energy = float(e[1]) if on else 0.0
	for sw: LightSwitch in _switches:
		if not is_instance_valid(sw):
			continue
		if on:
			sw._apply()                                # (whatever the switch is set to now)
		else:
			for lamp in sw.lamps:
				if is_instance_valid(lamp):
					sw._set_lamp(lamp, false)

func _update_dark(delta: float) -> void:
	_t += delta
	# A switch thrown in the dark must not bring a lamp back early.
	if not _lit:
		for e: Array in _lights:
			if is_instance_valid(e[0]):
				(e[0] as Light3D).light_energy = 0.0
	if _t >= 1.3 and _t - delta < 1.3:
		_giggle()
	if _t >= dark_seconds - 0.7 and _figures.is_empty():
		_place_figures()
	if _t >= dark_seconds:
		# They come back in a stutter, and it is then that they are seen.
		_set_lit(true)
		for f: Dictionary in _figures:
			(f.body as Node3D).visible = true
		state = "show"
		_t = 0.0
		history.append([TerminalData.clock_text(), "lights back: %d apparitions" % _figures.size()])
		TerminalData.log_line("All lamps out for some seconds as a goods train passed. Cause unknown.")

func _update_show(delta: float) -> void:
	_t += delta
	if _t > 0.14 and _t - delta <= 0.14:
		_set_lit(false)
	if _t > 0.26 and _t - delta <= 0.26:
		_set_lit(true)
	var p := _player()
	var left := 0
	for f: Dictionary in _figures:
		if f.get("gone", false):
			continue
		left += 1
		var b: Node3D = f.body
		if f.get("lunger", false):
			_update_lunge(f, delta)
			continue
		var gap := Vector2(p.global_position.x - b.global_position.x, p.global_position.z - b.global_position.z).length() if p else INF
		if _t > show_seconds or (_t > 1.5 and gap < vanish_near):
			_dismiss(f)
	if _blink > 0.0:
		_blink -= delta
		if _blink <= 0.0:
			_set_lit(true)
	if _pax:
		_pax.hush = 2.0
	if left == 0 and _blink <= 0.0 and _figures.all(func(f): return not is_instance_valid(f.body)):
		_figures.clear()
		_faces.clear()
		state = "idle"
		if _hd:
			_hd.hold = false
			_hd.end_big("goods train")
		get_tree().create_timer(3.0).timeout.connect(_react)

# It stands there a breath, then comes at his face; at his face the lamps blink and it is gone.
func _update_lunge(f: Dictionary, delta: float) -> void:
	var b: TalkingCharacter = f.body
	var cam := get_viewport().get_camera_3d()
	if _t < LUNGE_AT or cam == null:
		return
	if not f.has("from"):
		f["from"] = b.global_position
		f["lt"] = 0.0
		_scare()
	f.lt += delta
	var u := clampf(float(f.lt) / LUNGE, 0.0, 1.0)
	var eye := cam.global_position
	var from: Vector3 = f.from
	var dir := Vector3(eye.x - from.x, 0, eye.z - from.z).normalized()
	var to := Vector3(eye.x, from.y, eye.z) - dir * 0.42
	var k := 1.0 - (1.0 - u) * (1.0 - u)                              # (off like a shot)
	# A short one rises off the floor as it comes, so it is face to face with him.
	var rise := clampf(eye.y - 0.08 - (from.y + b._head_h), 0.0, 0.9)
	b.global_position = from.lerp(to, k) + Vector3(0, rise * k, 0)
	b.global_basis = Basis(Vector3.UP, atan2(dir.x, dir.z))
	# Hands up at his head as it comes.
	var side := dir.cross(Vector3.UP).normalized()
	b.grab = minf(u * 2.0, 1.0)
	b.grab_l = eye - dir * 0.2 + side * 0.28 - Vector3(0, 0.08, 0)
	b.grab_r = eye - dir * 0.2 - side * 0.28 - Vector3(0, 0.08, 0)
	if float(f.lt) >= LUNGE + IN_FACE:
		f["gone"] = true
		_set_lit(false)
		_blink = 0.16
		if not (f.seat as Dictionary).is_empty():
			f.seat.taken = false
		_pax.release_slug(f.slug)
		b.queue_free()

func _react() -> void:
	var p := _player()
	if p == null or _pax == null:
		return
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	for cn in ["PassengerCar", "PassengerCar3"]:
		var car := train.get_node_or_null(cn) as Node3D
		if car and absf(p.global_position.x - car.global_position.x) < 8.9:
			_pax.complain(car, REACT[_rng.randi_range(0, REACT.size() - 1)])
			return

# ————— the scare —————

func _giggle() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not ResourceLoader.exists(GIGGLE):
		return
	# Just behind his shoulder, so it is there and not there.
	var at := cam.global_position + cam.global_basis.z * 0.9 - cam.global_basis.x * 0.6
	var g := AudioStreamPlayer3D.new()
	g.stream = load(GIGGLE)
	g.unit_size = 2.5
	g.max_distance = 30.0
	g.volume_db = 6.0
	add_child(g)
	g.global_position = at
	g.play()
	g.finished.connect(g.queue_free)

func _scare() -> void:
	if not ResourceLoader.exists(SCARE):
		return
	var s := AudioStreamPlayer.new()
	s.stream = load(SCARE)
	s.volume_db = -1.0
	add_child(s)
	s.play(0.2)                                       # (straight in, no breath before it)
	s.finished.connect(s.queue_free)

# ————— the apparitions —————

func _load_faces() -> void:
	_faces = _pax.free_faces(ghosts_max) if _pax else []
	for slug: String in _faces:
		ResourceLoader.load_threaded_request(_pax._glb(slug))

func _place_figures() -> void:
	if _nav == null:
		_nav = TrainNav.of(self)
	var cam := get_viewport().get_camera_3d()
	var n := _rng.randi_range(ghosts_min, ghosts_max)
	if cam == null or _nav == null or _pax == null:
		return
	var fwd := -cam.global_basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var at := cam.global_position
	var seats: Array = _pax.free_seats_near(at, 10.0).filter(func(s): return cam.is_position_in_frustum((s.marker as Node3D).global_position + Vector3(0, 1.0, 0)))
	seats.shuffle()
	var i := 0
	# One on its feet, right in front of him; the others wherever there is an empty seat in view.
	for k in n:
		if i >= _faces.size():
			break
		var seat: Dictionary = {}
		if k > 0 and not seats.is_empty():
			seat = seats.pop_back()
		var xf := _pax.seat_xf_of(seat) if not seat.is_empty() else _standing_spot(at, fwd, k)
		if xf == Transform3D():
			continue
		if _figure(_faces[i], xf, seat):
			i += 1

# A free spot on the floor ahead of him, in plain sight, facing him.
func _standing_spot(at: Vector3, fwd: Vector3, k: int) -> Transform3D:
	var space := get_world_3d().direct_space_state
	for d in [2.4, 2.0, 2.8, 1.7, 3.4]:
		var p: Vector3 = at + fwd * (d + k * 1.3)
		var c := _nav.nearest_free(Vector3(p.x, TrainNav.FLOOR_Y, p.z), false, 0.5)
		if c.x < 0:
			continue
		var foot := _nav.cell_pos(c)
		var q := PhysicsRayQueryParameters3D.create(at, foot + Vector3(0, 1.5, 0))
		var pl := _player()
		q.exclude = [(pl as CollisionObject3D).get_rid()] if pl is CollisionObject3D else []
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and not (hit.collider is CharacterBody3D):
			continue
		var f := Vector3(at.x - foot.x, 0, at.z - foot.z).normalized()
		return Transform3D(Basis(Vector3.UP, atan2(f.x, f.z)), foot)
	return Transform3D()

func _figure(slug: String, xf: Transform3D, seat: Dictionary) -> bool:
	var path: String = _pax._glb(slug)
	var ps := ResourceLoader.load_threaded_get(path) as PackedScene
	if ps == null:
		return false
	var b := TalkingCharacter.new()
	b.name = "Apparition_" + slug
	b.model = ps
	b.solid = false
	b.look_range = 14.0
	b.visible = false
	add_child(b)
	b.global_transform = xf
	if not seat.is_empty():
		b.sit_now()
		seat.taken = true
	_pax.reserve_slug(slug)
	for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_figures.append({"body": b, "fade": GhostFade.appear(b), "seat": seat, "slug": slug,
			"lunger": seat.is_empty() and not _figures.any(func(f): return f.get("lunger", false))})
	return true

func _dismiss(f: Dictionary) -> void:
	f["gone"] = true
	(f.fade as GhostFade).dismiss(func() -> void:
		if not (f.seat as Dictionary).is_empty():
			f.seat.taken = false
		_pax.release_slug(f.slug)
		(f.body as Node).queue_free())

func _exit_tree() -> void:
	if not _lit:
		_set_lit(true)
