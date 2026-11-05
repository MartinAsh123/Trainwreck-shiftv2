class_name GameAudio
extends Node
## All of the journey's sound, driven by what the world already reports:
##   rails      — a rolling loop under every car, louder and higher with speed
##   locomotive — the idle hiss when standing, a chuff on every exhaust beat (LocoSmoke.beat),
##                the whistle before departure (Journey.whistle), brakes coming into a station
##   stations   — the platform bell when the train is about to leave
##   weather    — wind outside, its strength from Weather.wind_strength, muffled inside the train
##   doors      — sliding / hinged open and close (TrainDoor.moved), a rattle when locked
##   curtains, the toilet lock, the staff terminal (clicks, keys, chime, notifications, the
##   tube's hum), and the player's footsteps by surface (FPController.footstep / landed)
## One-shots play from a pool of 3D players at the source.
## Mix (default_bus_layout.tres): Master (hard limiter, -1 dB ceiling) <- Music, SFX, Ambience (ducked
## under Voice), Voice, UI, Outside (-> Ambience, muffled indoors). The players' sliders own each bus's
## volume, so the mix never sets bus gain except Outside's. Players made by other scripts land on
## Master; they are routed here when they enter the tree (_route), and the talking characters' own
## lip-sync buses are sent to Voice. GameAudio.dread(level, seconds) drives the horror bed (DreadBed).

const DIR := "res://assets/audio/"
const RAIL_SPOTS := [17.5, 0.0, -17.5, -35.0, -52.6]       # under each car (train space x)
const LOCO_X := -82.0                                        # the chimney end of the engine
const BUSES := ["Music", "SFX", "Ambience", "Voice", "UI", "Outside"]
const AMBIENCE := ["rail_loop", "loco_idle", "crt_hum", "wind_loop", "dread_low", "dread_high"]

static var _inst: GameAudio

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _rails: Array[AudioStreamPlayer3D] = []
var _idle: AudioStreamPlayer3D
var _wind: AudioStreamPlayer
var _ts: Node
var _player: Node3D
var _train: Node3D
var _braked := false
var _rng := RandomNumberGenerator.new()
var _outside_bus := -1
var _step_sets := {}                 # surface -> Array of streams
var _dread: DreadBed

func _ready() -> void:
	_rng.randomize()
	_inst = self
	_ts = get_node_or_null("/root/TrainState")
	_setup_buses()
	for i in 12:
		var p := AudioStreamPlayer3D.new()
		p.name = "OneShot%d" % i
		p.unit_size = 4.0
		p.max_distance = 60.0
		p.attenuation_filter_cutoff_hz = 9000.0
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	_dread = DreadBed.new()
	_dread.name = "Dread"
	add_child(_dread)
	get_tree().node_added.connect(_on_node_added)
	AudioServer.bus_layout_changed.connect(_route_voices, CONNECT_DEFERRED)
	_hook.call_deferred()

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

func _setup_buses() -> void:
	# The layout normally brings these; a bare project (or an old test) gets them made here.
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	# "Outside" bus: weather and lineside sounds, muffled while the player is indoors.
	_outside_bus = AudioServer.get_bus_index("Outside")
	if AudioServer.get_bus_effect_count(_outside_bus) == 0:
		AudioServer.set_bus_send(_outside_bus, "Ambience")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 900.0
		AudioServer.add_bus_effect(_outside_bus, lp)

## The horror bed: 0 = silent, 1 = full dread. Rises or falls over `seconds`; 0 seconds cuts at once.
## Swell before an event (dread(0.8, 6.0)), then cut on the hit (dread(0.0, 0.0)).
static func dread(level: float, seconds := 3.0) -> void:
	if _inst and _inst._dread:
		_inst._dread.set_level(level, seconds)

static func dread_level() -> float:
	return _inst._dread.level if _inst and _inst._dread else 0.0

# ————— routing —————

func _on_node_added(n: Node) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D:
		_route.call_deferred(n)

# Gives a player still on Master the bus its sound belongs to (deferred: most scripts set the
# stream after add_child).
func _route(n: Node) -> void:
	if not is_instance_valid(n) or n.get("bus") != &"Master":
		return
	var st := n.get("stream") as AudioStream
	var key := st.resource_path.get_file().get_basename() if st else ""
	var path := st.resource_path if st else ""
	var bus := &"SFX"
	if key in AMBIENCE and key != "rail_loop":            # another script's rail_loop is a passing train
		bus = &"Ambience"
	elif "/music/" in path or key.begins_with("music"):
		bus = &"Music"
	elif "/voice" in path or key.begins_with("voice"):
		bus = &"Voice"
	elif key.begins_with("ui_") or (n is AudioStreamPlayer and _in_ui(n)):
		bus = &"UI"
	n.set("bus", bus)

func _in_ui(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is Control or p is CanvasLayer:
			return true
		p = p.get_parent()
	return false

# The talking characters each make a "Voice_<id>" bus for lip sync; they all feed Voice.
func _route_voices() -> void:
	for i in AudioServer.bus_count:
		var nm := AudioServer.get_bus_name(i)
		if nm.begins_with("Voice_") and AudioServer.get_bus_send(i) == &"Master":
			AudioServer.set_bus_send(i, "Voice")

func _bus_for(key: String) -> StringName:
	return &"Ambience" if key in AMBIENCE else &"SFX"

func s(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	var st: AudioStream = null
	for ext in [".wav", ".ogg", ".mp3"]:
		if ResourceLoader.exists(DIR + key + ext):
			st = load(DIR + key + ext)
			break
	_streams[key] = st
	return st

func _loop(st: AudioStream) -> AudioStream:
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	elif st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.get_length() * w.mix_rate)
	return st

## Plays `key` at a world position (a random variant if `key` names a set like "step_wood").
func play_at(key: String, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	var st := s(key)
	if st == null:
		var vs := _variants(key)
		if vs.is_empty():
			return
		st = s(vs[_rng.randi() % vs.size()])
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = st
	p.bus = _bus_for(key)
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()

# ————— wiring —————

func _hook() -> void:
	var tree := get_tree()
	_train = tree.root.find_child("Train", true, false) as Node3D
	_player = tree.get_first_node_in_group("player") as Node3D
	# Players made before this node was ready.
	for n in tree.root.find_children("*", "AudioStreamPlayer", true, false) + tree.root.find_children("*", "AudioStreamPlayer3D", true, false):
		_route(n)
	_route_voices()
	if _player == null:
		_player = tree.root.find_child("Player", true, false) as Node3D
	# Rails and the standing engine.
	if _train:
		for x: float in RAIL_SPOTS:
			var r := AudioStreamPlayer3D.new()
			r.stream = _loop(s("rail_loop"))
			r.position = Vector3(x, 0.4, 0)
			r.unit_size = 6.0
			r.max_distance = 45.0
			r.volume_db = -80.0
			r.bus = &"Ambience"
			_train.add_child(r)
			r.play(_rng.randf() * 5.0)
			_rails.append(r)
		_idle = AudioStreamPlayer3D.new()
		_idle.stream = _loop(s("loco_idle"))
		_idle.position = Vector3(LOCO_X + 6.0, 2.0, 0)
		_idle.unit_size = 8.0
		_idle.max_distance = 120.0
		_idle.bus = &"Ambience"
		_train.add_child(_idle)
		_idle.play()
		var smoke := _train.find_child("Smoke", true, false)
		if smoke and smoke.has_signal("beat"):
			smoke.connect("beat", func(strength: float) -> void:
				var v := _speed()
				play_at("loco_chuff", (smoke as Node3D).global_position, lerpf(-2.0, -10.0, clampf(v / 25.0, 0.0, 1.0)) + linear_to_db(strength), 0.08))
	_wind = AudioStreamPlayer.new()
	_wind.stream = _loop(s("wind_loop"))
	_wind.bus = "Outside"
	_wind.volume_db = -30.0
	add_child(_wind)
	_wind.play()
	var journey := tree.root.find_child("Journey", true, false)
	if journey and journey.has_signal("whistle"):
		journey.connect("whistle", func(_long: bool) -> void:
			play_at("loco_whistle", _loco_pos() + Vector3(0, 3, 0), 2.0, 0.0))
	if _ts:
		_ts.connect("departing", func(_st: String) -> void:
			play_at("station_bell", Vector3(-29.0, 3.0, 12.0), -3.0, 0.0))
		_ts.connect("phase_changed", func(ph: String) -> void:
			if ph == "running":
				_braked = false)
	# Doors, curtains, locks, terminals.
	for d in tree.get_nodes_in_group("train_door"):
		var door := d as Node3D
		door.connect("moved", func(opening: bool) -> void:
			var hinged := int(door.get("kind")) == 1
			var key := ("door_hinge_" if hinged else "door_slide_") + ("open" if opening else "close")
			play_at(key, door.global_position + Vector3(0, 1.2, 0), -3.0))
		door.connect("refused", func(_r: String) -> void:
			play_at("door_locked", door.global_position + Vector3(0, 1.1, 0), -4.0))
	for c in tree.get_nodes_in_group("curtains"):
		var cs := c as Node3D
		cs.connect("moved", func(_closing: bool) -> void:
			play_at("curtain", cs.global_position, -6.0))
	for l in tree.root.find_children("*", "ToiletLock", true, false):
		var lock := l as Node3D
		lock.connect("lock_changed", func(_locked: bool) -> void:
			if lock.is_inside_tree():
				play_at("lock_turn", lock.global_position, -6.0, 0.03))
	for t in tree.get_nodes_in_group("terminal"):
		var term := t as Node3D
		var hum := AudioStreamPlayer3D.new()
		hum.stream = _loop(s("crt_hum"))
		hum.unit_size = 0.6
		hum.max_distance = 4.0
		hum.volume_db = -14.0
		hum.bus = &"Ambience"
		term.add_child(hum)
		hum.play(_rng.randf() * 3.0)
		term.connect("sound", func(k: String) -> void:
			var key: String = {"startup": "pc_startup", "logon": "pc_startup", "notify": "pc_notify", "mouse": "pc_click",
					"key": "pc_key", "shutdown": "pc_notify"}.get(k, "")
			if key != "":
				play_at(key, term.global_position, -8.0 if key == "pc_key" or key == "pc_click" else -4.0, 0.08))
	# Footsteps.
	if _player:
		if _player.has_signal("footstep"):
			_player.connect("footstep", _on_step)
		if _player.has_signal("landed"):
			_player.connect("landed", func(fall: float) -> void:
				if fall > 2.0:
					play_at("land", _player.global_position, clampf(-14.0 + fall * 2.0, -14.0, 0.0)))

# Sliced variants of a sound: key_1, key_2, … (see tools/slice_sfx.py).
func _variants(key: String) -> Array:
	if _step_sets.has(key):
		return _step_sets[key]
	var out: Array = []
	for i in 12:
		var k := "%s_%d" % [key, i + 1]
		if s(k):
			out.append(k)
	_step_sets[key] = out
	return out

func _on_step(surface: String, strength: float) -> void:
	var set_name: String = {"metal": "step_metal", "snow": "step_snow", "wood": "step_wood"}.get(surface, "step_carpet")
	play_at(set_name, _player.global_position, lerpf(-22.0, -8.0, strength), 0.07)

func _speed() -> float:
	return float(_ts.get("speed")) if _ts else 0.0

func _loco_pos() -> Vector3:
	return (_train.global_transform * Vector3(LOCO_X, 0, 0)) if _train else Vector3.ZERO

func _process(_delta: float) -> void:
	var v := _speed()
	var k := clampf(v / 22.0, 0.0, 1.0)
	for r in _rails:
		r.volume_db = -80.0 if v < 0.2 else lerpf(-26.0, -4.0, sqrt(k))
		r.pitch_scale = lerpf(0.65, 1.12, k)
	if _idle:
		_idle.volume_db = lerpf(-4.0, -16.0, k)
	if _ts and str(_ts.get("phase")) == "braking" and v < 9.0 and not _braked:
		_braked = true
		play_at("brakes", (_train.global_position if _train else Vector3.ZERO) + Vector3(-29.0, 0.5, 0), -2.0, 0.0)
	var w := get_tree().get_first_node_in_group("weather")
	var ws := float(w.get("wind_strength")) if w else 0.2
	_wind.volume_db = lerpf(-30.0, -4.0, ws) + (4.0 * k)
	# Indoors the outside is muffled through the walls.
	if _outside_bus >= 0 and _player and _train:
		var local := _train.global_transform.affine_inverse() * _player.global_position
		var inside := absf(local.z) < 1.45 and local.x > -84.0 and local.x < 26.2
		var lp := AudioServer.get_bus_effect(_outside_bus, 0) as AudioEffectLowPassFilter
		lp.cutoff_hz = move_toward(lp.cutoff_hz, 700.0 if inside else 16000.0, 400.0)
		AudioServer.set_bus_volume_db(_outside_bus, -6.0 if inside else 0.0)
