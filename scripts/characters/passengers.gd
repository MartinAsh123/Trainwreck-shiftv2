class_name Passengers
extends Node3D
## The people who ride the train (the characters of assets/characters, each a TalkingCharacter, no
## two the same at once):
##   - seated in the two saloons from the start (two to a double seat, facing the way the seat faces)
##   - some of them anomalies (assets/anomalies: a copy of one of the characters with something wrong -
##     a third eye, a tail, six fingers...): one aboard from the start, and each new passenger may be
##     one (anomaly_chance); an anomaly and its normal twin are never aboard together. Their bodies are
##     in the "anomaly" group with meta "anomaly" = the kind
##   - asleep in the sleeping car's berths, on their side under a blanket that shows the body under it
##     (SleepBlanket); each has a stop of their own, and there they wake: the blanket is thrown back,
##     they sit up on the edge of the berth, stand, and go out along the corridor to the platform
##   - waiting on the platform of each stop as the train runs in, standing by where the doors will be
##   - at the stop: the exterior doors on the platform's side open by themselves (the Train shuts them
##     again before departure); some passengers get up and leave - out of the saloon, down the step and
##     away along the platform - and then the waiting ones board, walk to a free seat and sit down
## Anyone still on the way when the train is due out is put in place at once: a boarder in the seat,
## an alighter on the platform. People left on a platform stay there as the train pulls away and are
## dropped once well behind it.
##   - between stops, now and then (never more than `max_wandering` at once) a seated passenger gets
##     up for a short errand - the W.C. at the end of its saloon (one at a time: the W.C. is reserved,
##     its door shut and locked while in use) or a few minutes at the vestibule window - and goes back
##     to its own seat (kept for it meanwhile). Nobody sets off with its own stop coming up, and when
##     the train brakes for a stop everyone out returns to the seat
##   - a passenger gets off at its own destination (PassengerTalk.dest): as the train brakes for it
##     it stands up and waits by its seat; a destination not on the line means riding to the end
##   - the guard can take a passenger away (Detention): from then it is UNDER_ESCORT and then
##     DETAINED - its own routine (trips, getting off) leaves it alone until it is released
## Train space: the Train node stands at the origin and never moves; a platform point at route
## position s is drawn at x = TrainState.distance - s, as Scenery draws the stations.

const DIR := "res://assets/characters/"
const ANOM_DIR := "res://assets/anomalies/"
const NOT_PASSENGERS := ["mike", "police_officer", "military_officer"]   # crew and guards (placed elsewhere)
const SALOONS := ["PassengerCar", "PassengerCar3"]
const DOOR_CARS := ["PassengerCar", "PassengerCar3", "SleeperCar1"]   # their side doors open at stops
const SLEEPER := "SleeperCar1"
const PLAT_Y := 0.55               # platform top (StationYard.PLAT_Y)
const PLAT_EDGE := 1.62            # platform edge from the track's middle
const SEAT_LAT := 0.275            # the two places of a double seat, either side of its middle
const WALK := 1.05                 # m/s on the platform
const WALK_IN := 0.8               # m/s inside the car
const FAR := 160.0                 # people left on a platform are dropped this far behind the train
const CHAT_RANGE := 8.0            # passengers talk only with the player this near
const LINES := [
	"Snowing again. We'll be late into Kamenný Most, mark my words.",
	"My sister lives past Sněžná. She won't believe I came all this way.",
	"Has the guard been round for the tickets yet?",
	"Cold in here, isn't it? They never heat the second coach.",
	"I used to take this line every winter as a boy.",
	"Hm. Another stop already?",
	"The conductor said twenty minutes. That was an hour ago.",
	"Excuse me, is this seat free? Ah, never mind.",
	"I can never sleep on trains. Too much rattling.",
	"Look at that, the lamps in the village are all out.",
]

@export var start_seated := 7      # per saloon at the start
@export var max_riders := 26
@export var sleepers := 5          # berths taken at the start
@export var door_delay := 1.2      # seconds after the stop before the doors open
@export var anomaly_chance := 0.25 # each passenger who boards or waits may be an anomaly
@export_group("Errands")
@export var trips_enabled := true
@export var max_wandering := 2     # passengers away from their seats at once (errands)
@export var trip_check := 9.0      # seconds between looks for someone to send on an errand
@export var trip_chance := 0.45    # chance per look that someone goes
@export var trip_gap_min := 25.0   # game minutes a passenger stays seated between errands, at least
@export var trip_gap_max := 70.0
@export var wc_seconds := Vector2(18.0, 35.0)       # real seconds in the W.C.
@export var window_seconds := Vector2(12.0, 25.0)   # real seconds at the vestibule window
@export var calm_before_stop := 2600.0  # no errands this close to the next stop (metres)

enum State { WAITING, BOARDING, SEATED, ALIGHTING, LEFT, SLEEPING, WAKING, ERRAND, PREPARING, UNDER_ESCORT, DETAINED, VANISHING }

class Rider:
	var slug := ""                 # a character's folder, or an anomaly's
	var base := ""                 # the character it is (an anomaly's normal twin)
	var anomaly := ""              # the anomaly's kind ("" for a normal passenger)
	var body: TalkingCharacter
	var state := State.WAITING
	var seat := {}                 # the seat place (see _seats)
	var car: Node3D
	var path: Array = []           # [Vector3 (train space), speed] still to walk
	var start := 0.0               # seconds after the stop when it sets off
	var s_route := 0.0             # on a platform: route position of its spot (it scrolls with the land)
	var z := 0.0
	var face := Vector3.ZERO       # on a platform: the way it faces when standing
	var sitting_down := false
	var bed: Node3D                # asleep: the berth's marker (x across, z along, the pillow at +z)
	var blanket: SleepBlanket
	var dest := ""                 # the stop where a sleeper gets off
	var side := 1.0                # which way off the berth (toward the compartment's door)
	var lie_h := 0.0               # the sit height that keeps a lying body's hips in place
	var t := 0.0                   # seconds into waking
	var pid := 0                   # stable number for this journey
	var mover: NpcMover            # while walking inside on an errand (or escorted)
	var errand := ""               # "wc" | "window"
	var errand_phase := ""         # "out" | "there" | "back" | "sit"
	var errand_t := 0.0
	var back_tries := 0            # ways back to the seat planned in vain (see BACK_TRIES)
	var next_errand := 0.0         # game clock (hours) before which it stays seated
	var wc_car: Node3D             # the W.C. it holds
	var ghost := false             # not a living passenger

var _ts: Node
var _journey: Node
var _train: Node3D
var _riders: Array = []
var _seats: Array = []             # {car, marker, lat, taken}
var _slugs: PackedStringArray = []
var _anomalies := {}               # anomaly folder -> [base slug, kind]
var _in_use := {}                  # slug -> true while someone wears that face
var _loading := {}                 # slug -> true while loading on a thread
var _rng := RandomNumberGenerator.new()
var _stop_t := -1.0                # seconds since the train stopped (-1 while it runs)
var _stop_side := 1
var _doors_open := false
var _prepared_for := ""            # the stop whose waiting passengers are out on the platform
var _opened: Array = []            # inner doors opened for the passengers
var _pid := 0
var _nav: TrainNav
var _wc := {}                      # saloon car -> {door: TrainDoor, lock: ToiletLock, spot: Vector3, user: Rider}
var _trip_t := 5.0

func _ready() -> void:
	_rng.randomize()
	_ts = get_node_or_null("/root/TrainState")
	_journey = get_tree().root.find_child("Journey", true, false)
	_train = get_tree().root.find_child("Train", true, false) as Node3D
	for d in DirAccess.get_directories_at(DIR):
		if ResourceLoader.exists(DIR + "%s/%s.glb" % [d, d]) and not d in NOT_PASSENGERS:
			_slugs.append(d)
	for d in DirAccess.get_directories_at(ANOM_DIR):
		if not ResourceLoader.exists(ANOM_DIR + "%s/%s.glb" % [d, d]):
			continue
		var base := ""
		for s in _slugs:                                     # the longest character name it starts with
			if d.begins_with(s + "_") and s.length() > base.length():
				base = s
		if base != "":
			_anomalies[d] = [base, d.substr(base.length() + 1)]
	if _ts:
		_ts.connect("arrived", _on_arrived)
		_ts.connect("departing", _on_departing)
	_setup.call_deferred()

func _setup() -> void:
	if _train == null:
		return
	for cn in SALOONS:
		var car := _train.get_node_or_null(cn) as Node3D
		if car == null:
			continue
		for m: Node in car.find_children("Seat_*", "Marker3D", true, false):
			for lat in [-SEAT_LAT, SEAT_LAT]:
				_seats.append({"car": car, "marker": m, "lat": lat, "taken": false})
	# The first passengers are in their seats when the journey begins (loaded here, while the scene
	# itself is still loading).
	var anom_at := _rng.randi_range(0, SALOONS.size() * start_seated - 1)     # (one anomaly aboard)
	var n_start := 0
	for cn in SALOONS:
		for i in start_seated:
			var seat := _free_seat(cn)
			var slug := _pick_slug(1.0 if n_start == anom_at else 0.0)
			n_start += 1
			if seat.is_empty() or slug == "":
				break
			var r := _spawn(slug, load(_glb(slug)) as PackedScene)
			if r == null:
				continue
			_take_seat(r, seat)
			r.state = State.SEATED
			r.body.global_transform = _seat_xf(seat)
			r.body.sit_now()
	_setup_sleepers()
	# Already standing at the first station: its passengers are out and its doors open.
	if _ts and str(_ts.get("phase")) == "stopped":
		_on_arrived(str(_ts.get("station")))

# ————— the characters —————

# A character no one aboard or waiting already wears - an anomaly with chance `anomaly` (its normal
# twin must be free too).
func _pick_slug(anomaly: float = -1.0) -> String:
	if anomaly < 0.0:
		anomaly = anomaly_chance
	var free: Array = []
	if _rng.randf() < anomaly:
		for a in _anomalies:
			if not _in_use.has(_base(a)) and not _loading.has(_base(a)):
				free.append(a)
	if free.is_empty():
		for s in _slugs:
			if not _in_use.has(s) and not _loading.has(s):
				free.append(s)
	if free.is_empty():
		return ""
	return free[_rng.randi_range(0, free.size() - 1)]

func _base(slug: String) -> String:
	return _anomalies[slug][0] if _anomalies.has(slug) else slug

func _dir(slug: String) -> String:
	return (ANOM_DIR if _anomalies.has(slug) else DIR) + slug + "/"

func _glb(slug: String) -> String:
	return _dir(slug) + slug + ".glb"

func _spawn(slug: String, scene: PackedScene) -> Rider:
	if scene == null:
		return null
	var r := Rider.new()
	r.slug = slug
	r.base = _base(slug)
	r.anomaly = _anomalies[slug][1] if _anomalies.has(slug) else ""
	_pid += 1
	r.pid = _pid
	r.next_errand = (float(_ts.get("clock")) if _ts else 19.0) + _rng.randf_range(trip_gap_min * 0.3, trip_gap_max) / 60.0
	r.body = TalkingCharacter.new()
	r.body.name = "Passenger_" + slug
	r.body.set_meta("pid", _pid)
	r.body.model = scene
	r.body.mumbles = _mumbles(slug)
	if r.anomaly != "":
		r.body.set_meta("anomaly", r.anomaly)
		r.body.add_to_group("anomaly")
	add_child(r.body)
	_in_use[r.base] = true
	_riders.append(r)
	PassengerTalk.attach(r.body, r.slug, r.base, r.anomaly)   # E: ticket, how are you, who are you
	return r

# The character's own murmured takes (assets/characters/<slug>/mumble_N.mp3).
func _mumbles(slug: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for k in range(1, 6):
		var p := _dir(slug) + "mumble_%d.mp3" % k
		if ResourceLoader.exists(p):
			out.append(load(p) as AudioStream)
	return out

func _drop(r: Rider) -> void:
	_end_errand(r)
	if not r.seat.is_empty():
		r.seat.taken = false
	_in_use.erase(r.base)
	r.body.queue_free()
	_riders.erase(r)

# ————— seats —————

func _free_seat(car_name: String = "") -> Dictionary:
	var free: Array = []
	for s: Dictionary in _seats:
		if not s.taken and (car_name == "" or (s.car as Node).name == car_name):
			free.append(s)
	if free.is_empty():
		return {}
	return free[_rng.randi_range(0, free.size() - 1)]

func _take_seat(r: Rider, seat: Dictionary) -> void:
	seat.taken = true
	r.seat = seat
	r.car = seat.car

# Where a seated passenger is: on the cushion, facing the way the seat faces (the marker's -Z).
func _seat_xf(seat: Dictionary) -> Transform3D:
	var m := seat.marker as Node3D
	return m.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(seat.lat, 0, 0.02))

# The spot just in front of the seat where one stands up to (and sits down from).
func _seat_front(seat: Dictionary) -> Vector3:
	return (seat.marker as Node3D).global_transform * Vector3(seat.lat, 0, -0.28)

# The aisle end of the leg room in front of the seat: from a window seat one slides along to here
# (clear of the table) before stepping into the aisle.
func _seat_exit(seat: Dictionary) -> Vector3:
	var f := _seat_front(seat)
	return Vector3(f.x, f.y, signf(f.z) * 0.36)

# Getting up: the body rises and comes forward off the cushion to the seat's front together.
# True once up and there.
func _stand_step(r: Rider, delta: float) -> bool:
	var b := r.body
	b.sit_target = 0.0
	b.walk_speed = 0.0
	if r.seat.is_empty():
		return b._sit <= 0.02
	var xf := _seat_xf(r.seat)
	var up := 1.0 - b._sit
	b.global_position = xf.origin.lerp(_seat_front(r.seat), smoothstep(0.0, 1.0, up))
	return b._sit <= 0.02

# Sitting down from the seat's front: turning to face the seat's way and going back onto the
# cushion as the body lowers. True once seated.
func _sit_step(r: Rider, delta: float) -> bool:
	var b := r.body
	var xf := _seat_xf(r.seat)
	b.walk_speed = 0.0
	b.sit_target = 1.0
	b.global_basis = b.global_basis.orthonormalized().slerp(xf.basis.orthonormalized(), clampf(delta * 6.0, 0.0, 1.0))
	b.global_position = _seat_front(r.seat).lerp(xf.origin, smoothstep(0.0, 1.0, b._sit))
	if b._sit >= 0.98:
		b.global_transform = xf
		return true
	return false

# ————— doors and the way in —————

func _door_x(car: Node3D) -> float:
	var m := car.find_child("SideDoor_01", true, false) as Node3D
	return car.to_global(Vector3(car.to_local(m.global_position).x, 0, 0)).x if m else car.global_position.x

func _inner_door(car: Node3D) -> Node3D:
	return car.find_child("InnerDoor_Boarding", true, false) as Node3D

# From the platform by the door to the seat: up the step, through the vestibule and the saloon door,
# along the aisle and in to the seat. Train space, with speeds.
func _way_in(car: Node3D, seat: Dictionary, side: int) -> Array:
	var floor_y := car.global_position.y
	var dx := _door_x(car)
	var inner := _inner_door(car)
	var ix := inner.global_position.x if inner else dx + 1.0
	var front := _seat_front(seat)
	return [
		[Vector3(dx, PLAT_Y, side * (PLAT_EDGE + 0.6)), WALK],
		[Vector3(dx, PLAT_Y, side * (PLAT_EDGE + 0.12)), WALK_IN],
		[Vector3(dx, floor_y, side * 1.15), WALK_IN],
		[Vector3(dx + signf(ix - dx) * 0.2, floor_y, 0.0), WALK_IN],
		[Vector3(ix, floor_y, 0.0), WALK_IN],
		[Vector3(front.x, floor_y, 0.0), WALK_IN],
		[_seat_exit(seat), WALK_IN * 0.7],
		[Vector3(front.x, floor_y, front.z), WALK_IN * 0.7],
	]

# ————— the stop —————

func _on_arrived(_station: String) -> void:
	_stop_t = 0.0
	_doors_open = false
	_stop_side = _platform_side()
	# Those on board who get off here, then those waiting who get on.
	# Those whose own stop this is (at the terminus, everyone) - never one under escort or held.
	var terminus := _station == str(RouteData.stops().back().name)
	var seated: Array = []
	for r: Rider in _riders:
		if r.state in [State.SEATED, State.PREPARING] and not r.seat.is_empty() and (terminus or _dest(r) == _station):
			seated.append(r)
	for i in seated.size():
		var r: Rider = seated[i]
		r.state = State.ALIGHTING
		r.start = door_delay + 1.5 + i * 3.0 + _rng.randf() * 1.5
		r.path = _way_in(r.car, r.seat, _stop_side)
		r.path.reverse()
		var dx := _door_x(r.car)
		var away := dx + (6.0 + _rng.randf() * 10.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		r.path.append([Vector3(away, PLAT_Y, _stop_side * _rng.randf_range(2.3, 2.9)), WALK])
	for r: Rider in _riders:
		if r.state == State.SLEEPING and (r.dest == _station or terminus):
			if not terminus and r.body.has_meta("wake_call") and not r.body.has_meta("woken"):
				_oversleep(r, _station)
				continue
			r.state = State.WAKING
			r.t = -(door_delay + 1.0 + _rng.randf() * 4.0)
		elif r.state == State.WAKING and r.body.has_meta("hold_wake") and (r.dest == _station or terminus):
			r.body.remove_meta("hold_wake")          # (woken in time: up off the berth's edge and out)
	_prepare_stop(_station)
	var k := 0
	for r: Rider in _riders:
		if r.state == State.WAITING:
			var seat := _free_seat((r.car as Node).name)
			if seat.is_empty():
				continue
			_take_seat(r, seat)
			r.state = State.BOARDING
			r.start = door_delay + 6.0 + k * 2.5 + _rng.randf() * 1.5
			r.path = _way_in(r.car, seat, _stop_side)
			k += 1

func _on_departing(_station: String) -> void:
	_stop_t = -1.0
	# Anyone still on the way is put in place now (the doors are about to shut).
	for r: Rider in _riders.duplicate():
		match r.state:
			State.BOARDING:
				_settle(r)
			State.ALIGHTING:
				var last: Array = r.path.back() if not r.path.is_empty() else [r.body.global_position]
				_to_platform(r, last[0])
			State.WAITING:
				_to_platform(r, r.body.global_position)
			State.WAKING:
				if r.t > 0.0 and not r.body.has_meta("hold_wake"):
					_to_platform(r, _out_spot(r))
	for d: Node in _opened:
		if is_instance_valid(d):
			d.call("request", false)
	_opened.clear()

func _platform_side() -> int:
	for st: Dictionary in RouteData.stops():
		if st.name == str(_ts.get("station")):
			return int(st.side)
	return 1

func _open_doors() -> void:
	_doors_open = true
	for cn in DOOR_CARS:
		var car := _train.get_node_or_null(cn) as Node3D
		if car == null:
			continue
		for d: Node in car.find_children("*", "TrainDoor", true, false):
			if not bool(d.get("lock_while_moving")):
				continue
			if signf(car.to_local((d as Node3D).global_position).z) == float(_stop_side):
				d.call("request", true)
	# The saloon doors on the passengers' way, while they come and go.
	for cn in SALOONS:
		var car := _train.get_node_or_null(cn) as Node3D
		var inner := _inner_door(car) if car else null
		if inner:
			for d: Node in inner.find_children("*", "TrainDoor", true, false):
				if not bool(d.call("is_open")):
					d.call("request", true)
					_opened.append(d)

# The passengers for the next stop: out on its platform by the doors before the train runs in.
func _prepare_stop(station: String) -> void:
	if station == "" or station == _prepared_for or _train == null:
		return
	_prepared_for = station
	var st := {}
	for s: Dictionary in RouteData.stops():
		if s.name == station:
			st = s
	if st.is_empty() or st.name == RouteData.stops().back().name:
		return                         # the terminus: everyone gets off, nobody gets on
	var stopped_d: float = float(st.s) + float(_journey.get("stop_offset") if _journey else -29.0)
	var side := int(st.side)
	var room := max_riders - _riders.size()
	for cn in SALOONS:
		var car := _train.get_node_or_null(cn) as Node3D
		if car == null:
			continue
		var n := mini(_rng.randi_range(0, 2), room)
		for i in n:
			var slug := _pick_slug()
			if slug == "":
				return
			room -= 1
			var spot_x := _door_x(car) + _rng.randf_range(-3.5, 3.5)
			var z := side * _rng.randf_range(2.3, 2.9)     # (clear of the stone stations' canopy posts at 3.37)
			_load_waiting(slug, car, stopped_d - spot_x, z, side)

func _load_waiting(slug: String, car: Node3D, s_route: float, z: float, side: int) -> void:
	_loading[_base(slug)] = true
	ResourceLoader.load_threaded_request(_glb(slug))
	_pending.append({"slug": slug, "car": car, "s": s_route, "z": z, "side": side})

var _pending: Array = []

func _take_loaded() -> void:
	var i := 0
	while i < _pending.size():            # (by index: no copy of the list every frame)
		var p: Dictionary = _pending[i]
		var path := _glb(p.slug)
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			i += 1
			continue
		_pending.remove_at(i)
		_loading.erase(_base(p.slug))
		if st != ResourceLoader.THREAD_LOAD_LOADED:
			continue
		var r := _spawn(p.slug, ResourceLoader.load_threaded_get(path) as PackedScene)
		if r == null:
			continue
		r.state = State.WAITING
		r.car = p.car
		r.s_route = p.s
		r.z = p.z
		r.face = Vector3(_rng.randf_range(-0.4, 0.4), 0, -float(p.side)).normalized()   # toward the track
		_place_on_platform(r)
		# The train already standing here (the first station): they board at this stop.
		if _stop_t >= 0.0 and str(_ts.get("station")) == _prepared_for:
			var seat := _free_seat((r.car as Node).name)
			if not seat.is_empty():
				_take_seat(r, seat)
				r.state = State.BOARDING
				r.start = maxf(_stop_t, door_delay + 2.0) + _rng.randf() * 4.0
				r.path = _way_in(r.car, seat, _stop_side)

# ————— every frame —————

func _process(delta: float) -> void:
	if _ts == null or _train == null:
		return
	_take_loaded()
	var phase := str(_ts.get("phase"))
	# The waiting passengers of the next stop come out as it draws near.
	if phase in ["running", "braking"] and float(_ts.get("to_next_stop")) < 700.0:
		_prepare_stop(str(_ts.get("next_stop")))
	if _stop_t >= 0.0:
		_stop_t += delta
		if not _doors_open and _stop_t >= door_delay:
			_open_doors()
	_chatter(delta)
	_errands(delta, phase)
	# By index, no copy of the list every frame: a rider dropped on the way (itself or another)
	# leaves the one now at `i` still to do, so `i` only moves on while `r` is still there.
	var i := 0
	while i < _riders.size():
		var r: Rider = _riders[i]
		match r.state:
			State.ERRAND:
				_update_errand(r, delta)
			State.PREPARING:
				_update_preparing(r, delta)
			State.WAITING, State.LEFT:
				_place_on_platform(r)
				if r.body.walk_speed != 0.0:
					r.body.walk_speed = 0.0
				if r.state == State.LEFT and absf(r.body.global_position.x) > FAR:
					_drop(r)
			State.BOARDING, State.ALIGHTING:
				if _stop_t >= r.start:
					_walk(r, delta)
			State.WAKING:
				r.t += delta
				if r.t >= 0.0:
					_wake(r)
		if i < _riders.size() and _riders[i] == r:
			i += 1

# Now and then a seated passenger near the player says something (a murmur under a subtitle).
var _chat_t := 8.0
## Seconds of no small talk (a scare is on: a chance remark over it would spoil it).
var hush := 0.0

func _chatter(delta: float) -> void:
	_chat_t -= delta
	hush = maxf(hush - delta, 0.0)
	if _chat_t > 0.0 or hush > 0.0:
		return
	_chat_t = _rng.randf_range(14.0, 30.0)
	var near: Array = []
	for r: Rider in _riders:
		if r.state == State.SEATED and not r.body.is_speaking() and r.body._player_within(CHAT_RANGE) \
				and not r.body.has_meta("in_talk"):              # (not over a conversation with the player)
			near.append(r)
	if near.is_empty():
		return
	var r: Rider = near[_rng.randi_range(0, near.size() - 1)]
	r.body.say(LINES[_rng.randi_range(0, LINES.size() - 1)])

## The anomalies aboard or on the platforms now.
func anomalies() -> Array:
	return _riders.filter(func(r): return r.anomaly != "")

## Far down the platform (out in the dark ahead or behind) a waiting body is moved only in steps of
## this many metres; near the train every millimetre.
const PLACE_FAR := 120.0
const PLACE_STEP_FAR := 1.0

# Only when the platform has moved noticeably (standing at a stop it does not move at all) and
# while the body is still turning to face its way: each move re-places the whole skinned body.
func _place_on_platform(r: Rider) -> void:
	var d := float(_ts.get("distance"))
	var to := Vector3(d - r.s_route, PLAT_Y, r.z)
	var at := r.body.global_position
	var tol := PLACE_STEP_FAR if absf(to.x) > PLACE_FAR else 0.001
	if absf(at.x - to.x) > tol or absf(at.y - to.y) > 0.001 or absf(at.z - to.z) > 0.001:
		r.body.global_position = to
	if r.face != Vector3.ZERO:
		var want := atan2(r.face.x, r.face.z)
		if absf(angle_difference(r.body.rotation.y, want)) > 0.002:
			r.body.rotation.y = lerp_angle(r.body.rotation.y, want, 0.1)

func _walk(r: Rider, delta: float) -> void:
	var b := r.body
	if r.state == State.ALIGHTING and (b.sit_target > 0.0 or b._sit > 0.02):
		_stand_step(r, delta)          # up and forward off the seat first
		return
	if r.path.is_empty():
		_arrive(r)
		return
	var step: Array = r.path[0]
	var to: Vector3 = step[0]
	var speed: float = step[1]
	# Wait for the player standing in the way.
	var p := b._find_player()
	if p and p.global_position.distance_to(b.global_position + (to - b.global_position).normalized() * 0.45) < 0.4:
		b.walk_speed = 0.0
		return
	var at := b.global_position
	var flat := Vector3(to.x - at.x, 0, to.z - at.z)
	var left := Vector3(to.x - at.x, to.y - at.y, to.z - at.z).length()
	if left < 0.04:
		b.global_position = to
		r.path.pop_front()
		return
	var mv := minf(speed * delta, left)
	b.global_position = at + (to - at).normalized() * mv
	b.walk_speed = speed
	if flat.length() > 0.02:
		b.rotation.y = lerp_angle(b.rotation.y, atan2(flat.x, flat.z), clampf(delta * 8.0, 0.0, 1.0))

func _arrive(r: Rider) -> void:
	r.body.walk_speed = 0.0
	if r.state == State.BOARDING:
		# At the seat's front: turn round and sit (the body eases down and back onto the cushion).
		if _sit_step(r, get_process_delta_time()):
			r.state = State.SEATED
	elif r.state == State.ALIGHTING:
		_to_platform(r, r.body.global_position)

# A boarder put straight into the seat.
func _settle(r: Rider) -> void:
	r.path.clear()
	r.body.global_transform = _seat_xf(r.seat)
	r.body.sit_now()
	r.body.walk_speed = 0.0
	r.state = State.SEATED

# Someone on the platform for good: it stays where it is as the land moves on.
func _to_platform(r: Rider, at: Vector3) -> void:
	if not r.seat.is_empty():
		r.seat.taken = false
		r.seat = {}
	r.path.clear()
	r.body.sit_target = 0.0
	r.body._sit = 0.0
	r.body.asleep = false
	r.body.walk_speed = 0.0
	if r.blanket:
		r.blanket.lively = false
		r.blanket.disturbed = 1.0
		r.blanket.fold = 1.0
		r.blanket.set_body(null)
	r.state = State.LEFT
	r.s_route = float(_ts.get("distance")) - at.x
	r.z = at.z if absf(at.z) > PLAT_EDGE + 0.3 else signf(at.z) * 2.6
	r.face = Vector3.ZERO

# ————— the sleepers —————

func _setup_sleepers() -> void:
	var car := _train.get_node_or_null(SLEEPER) as Node3D
	if car == null:
		return
	var beds := car.find_children("Bed_*", "Marker3D", true, false).filter(func(b): return not b.has_meta("reserved"))
	beds.shuffle()
	var stops := RouteData.stops()
	for i in mini(sleepers, beds.size()):
		var slug := _pick_slug(0.0)
		if slug == "":
			return
		var r := _spawn(slug, load(_glb(slug)) as PackedScene)
		if r == null:
			continue
		r.car = car
		r.bed = beds[i]
		r.dest = str(stops[_rng.randi_range(1, stops.size() - 2)].name)
		PassengerTalk.of(r.body).sleeper_to(r.dest)
		_lay_down(r)

func _compartment_door(r: Rider) -> Node3D:
	return r.car.find_child("Door_Compartment_%d" % int(r.bed.get_meta("compartment", 1)), true, false) as Node3D

# On the side, facing the wall, knees drawn up, the head on the pillow; under the blanket.
func _lay_down(r: Rider) -> void:
	var door := _compartment_door(r)
	var dx := r.car.to_local(door.global_position).x if door else 0.0
	r.side = signf(dx - r.car.to_local(r.bed.global_position).x)
	if r.side == 0.0:
		r.side = 1.0
	var b := r.body
	r.lie_h = b._hip_h - 0.1
	b.sit_height = r.lie_h
	b.sit_target = 0.5
	b._sit = 0.5
	b.lie = 1.0
	b.lie_legs = 1.0
	b.lie_side = r.side
	b.asleep = true
	b.global_transform = r.bed.global_transform * _lie_xf(r)
	r.blanket = SleepBlanket.new()
	r.blanket.name = "Blanket"
	r.blanket.set_body(b)
	r.bed.add_child(r.blanket)
	r.state = State.SLEEPING

# In the berth's space: lying on the side, back to the compartment, the head on the pillow.
func _lie_xf(r: Rider) -> Transform3D:
	var s := r.side
	var basis := Basis(Vector3(0, -s, 0), Vector3(0, 0, 1), Vector3(-s, 0, 0))
	var head := r.body._head_h - 0.1
	return Transform3D(basis, Vector3(s * 0.03, SleepBlanket.MATTRESS + 0.17, 0.70 - head))

# Sitting on the berth's edge, feet on the floor, facing the gap between the berths.
func _sit_xf(r: Rider) -> Transform3D:
	var s := r.side
	return Transform3D(Basis(Vector3(0, 0, -s), Vector3(0, 1, 0), Vector3(s, 0, 0)), Vector3(s * 0.22, 0, 0.1))

func _stand_xf(r: Rider) -> Transform3D:
	var x := _sit_xf(r)
	x.origin.x = r.side * 0.68
	return x

# Waking: the blanket thrown back (1.4 s), sitting up and round onto the edge (2 s), standing (1.2 s),
# then out along the corridor.
func _wake(r: Rider) -> void:
	var b := r.body
	if r.body.has_meta("hold_wake"):
		r.t = minf(r.t, 3.5)                        # (woken before the stop: sitting up on the edge till then)
	var t := r.t
	var bl := r.blanket
	bl.lively = true
	bl.fold = smoothstep(0.0, 1.4, t)
	var a := smoothstep(1.4, 3.4, t)
	var c := smoothstep(3.6, 4.8, t)
	var xf := _lie_xf(r).interpolate_with(_sit_xf(r), a)
	if c > 0.0:
		xf = _sit_xf(r).interpolate_with(_stand_xf(r), c)
	b.global_transform = r.bed.global_transform * xf
	b.asleep = a < 0.5
	b.lie = 1.0 - a
	b.lie_legs = 1.0 - a
	b.sit_height = lerpf(r.lie_h, SleepBlanket.MATTRESS, a)
	b.sit_target = lerpf(0.5, 1.0, a) * (1.0 - c)
	b._sit = b.sit_target
	bl.disturbed = maxf(bl.disturbed, a)
	if t >= 5.0:
		b.sit_target = 0.0
		b._sit = 0.0
		r.state = State.ALIGHTING
		r.start = maxf(_stop_t, 0.0)
		r.path = _way_out_sleeper(r)
		for n in [_compartment_door(r), r.car.find_child("InnerDoor_Boarding", true, false)]:
			if n:
				for d: Node in n.find_children("*", "TrainDoor", true, false):
					if not bool(d.call("is_open")):
						d.call("request", true)
						_opened.append(d)

# From the gap between the berths out through the compartment door, along the corridor, through the
# vestibule and down onto the platform.
func _way_out_sleeper(r: Rider) -> Array:
	var car := r.car
	var door := _compartment_door(r)
	var dx := car.to_local(door.global_position).x if door else car.to_local(r.body.global_position).x
	var inner := car.find_child("InnerDoor_Boarding", true, false) as Node3D
	var ix := car.to_local(inner.global_position).x if inner else -6.05
	var sx := car.to_local(Vector3(_door_x(car), 0, 0)).x
	var side := float(_stop_side)
	var local := [Vector3(dx, 0, -0.30), Vector3(dx, 0, -1.02), Vector3(ix + 0.35, 0, -1.02),
			Vector3(ix - 0.35, 0, -1.02)]
	if side > 0.0:
		local.append(Vector3(sx + 0.15, 0, 0.0))
	local.append(Vector3(sx, 0, side * 1.15))
	var out: Array = []
	for p in local:
		out.append([car.to_global(p), WALK_IN])
	var gdx := _door_x(car)
	out.append([Vector3(gdx, PLAT_Y, side * (PLAT_EDGE + 0.12)), WALK_IN])
	out.append([Vector3(gdx, PLAT_Y, side * (PLAT_EDGE + 0.6)), WALK])
	out.append([Vector3(gdx + (6.0 + _rng.randf() * 10.0) * (1.0 if _rng.randf() < 0.5 else -1.0), PLAT_Y,
			side * _rng.randf_range(2.3, 2.9)), WALK])
	return out

func _out_spot(r: Rider) -> Vector3:
	return Vector3(_door_x(r.car) + _rng.randf_range(-4.0, 4.0), PLAT_Y, float(_stop_side) * 2.6)

## Kevin wakes a sleeper (E at the berth). Its stop next (or the train standing at it): it sits up on
## the berth's edge and waits for it (a wake-up call made). Not yet: a grumble and back to sleep. A
## berth with something else in it (WakeScare) is that scare's business. Returns what to tell him.
func wake_by_player(r: Rider) -> String:
	if r == null or r.state != State.SLEEPING:
		return ""
	if r.body.has_meta("wake_scare"):
		var ws := get_tree().get_first_node_in_group("wake_scare")
		if ws:
			ws.call("spring", r)
			return ""
	var phase := str(_ts.get("phase"))
	var here := phase in ["stopped", "departing"] and str(_ts.get("station")) == r.dest
	if here or str(_ts.get("next_stop")) == r.dest:
		r.body.set_meta("woken", true)
		r.state = State.WAKING
		r.t = 0.0
		if not here:
			r.body.set_meta("hold_wake", true)
		r.body.say("Mm? %s already? ...Thank you." % PassengerTalk.nice(r.dest), 2.4)
		return ""
	r.blanket.disturbed = maxf(r.blanket.disturbed, 0.35)
	if r.body.has_meta("wake_call"):
		r.body.say("Not yet... I said before %s. Let me sleep." % PassengerTalk.nice(r.dest), 2.6)
	else:
		r.body.say("Mmh...? Not my stop. Go away.", 2.2)
	return ""

# A wake-up call never made: it sleeps through its stop, and gets off at the next one, cross.
func _oversleep(r: Rider, station: String) -> void:
	var names: Array = RouteData.stops().map(func(s): return str(s.name))
	var i := names.find(station)
	r.dest = names[mini(i + 1, names.size() - 1)]
	r.body.remove_meta("wake_call")
	var t := PassengerTalk.of(r.body)
	if t:
		t.dest = r.dest
	TerminalData.log_line("Berth %s slept through %s: no wake-up call. Off at %s instead." % [str(r.bed.get_meta("berth", "?")), PassengerTalk.nice(station), PassengerTalk.nice(r.dest)])

## A held anomaly out of a cage left open (HoldingCage): gone from the bench, and seated somewhere
## aboard in another face - another anomaly's, with a wrong thing of its own. Returns the new rider
## (null if there is no free seat or face for it).
func respawn_as(r: Rider) -> Rider:
	var seat := _free_seat()
	var free: Array = []
	for a in _anomalies:
		if not _in_use.has(_base(a)) and not _loading.has(_base(a)) and _base(a) != r.base:
			free.append(a)
	_drop(r)
	if seat.is_empty() or free.is_empty():
		return null
	var slug: String = free[_rng.randi_range(0, free.size() - 1)]
	var n := _spawn(slug, load(_glb(slug)) as PackedScene)
	if n == null:
		return null
	_take_seat(n, seat)
	n.state = State.SEATED
	n.body.global_transform = _seat_xf(seat)
	n.body.sit_now()
	return n

## Gone from the train in an instant (WakeScare): its berth or seat free, its face free.
func vanish_rider(r: Rider) -> void:
	if r and _riders.has(r):
		_drop(r)

## Wakes a sleeper now (tests and scripted moments); returns false when nobody is asleep.
func wake_one() -> bool:
	for r: Rider in _riders:
		if r.state == State.SLEEPING:
			r.state = State.WAKING
			r.t = 0.0
			return true
	return false

# ————— errands: the W.C. or the vestibule window, and back to the seat —————

func _dest(r: Rider) -> String:
	var t := PassengerTalk.of(r.body)
	return t.dest if t else r.dest

func _nav_ready() -> bool:
	if _nav == null:
		_nav = get_tree().get_first_node_in_group("train_nav") as TrainNav
	if _nav != null and _nav.ready_ and _wc.is_empty() and not has_meta("_wc_done"):
		set_meta("_wc_done", true)
		_find_wcs()
	return _nav != null and _nav.ready_

# Each saloon's W.C.: its door, its lock and a spot inside to stand at (only if the way there goes
# through that door - otherwise that car has no W.C. errands).
func _find_wcs() -> void:
	for cn in SALOONS:
		var car := _train.get_node_or_null(cn) as Node3D
		var mk := car.find_child("ToiletDoor", true, false) as Node3D if car else null
		if mk == null:
			continue
		var door: TrainDoor = null
		for d in mk.find_children("*", "TrainDoor", true, false):
			door = d
		if door == null:
			continue
		var bowl := car.find_child("ToiletBowl", true, false) as Node3D
		var inside := mk.global_position + Vector3(0, 0, 0.42)
		if bowl:
			inside = inside.lerp(Vector3(bowl.global_position.x, inside.y, bowl.global_position.z), 0.35)
		var c := _nav.nearest_free(inside, true, 0.4)
		if c.x < 0:
			push_warning("Passengers: no standing room in the W.C. of %s - no W.C. errands there" % cn)
			continue
		var spot := _nav.cell_pos(c)
		var aisle := Vector3(car.global_position.x, spot.y, 0.0)
		var p := _nav.path(aisle, spot, true)
		var through := false
		for e: Array in _nav.doors_on(p):
			if e[1] == door:
				through = true
		if not through:
			push_warning("Passengers: no way into the W.C. of %s through its door - no W.C. errands there" % cn)
			continue
		_wc[car] = {"door": door, "lock": door.lock_node, "spot": spot, "user": null}

func _errands(delta: float, phase: String) -> void:
	if not trips_enabled or not _nav_ready():
		return
	var calling_back := phase in ["braking", "stopped", "departing"] or float(_ts.get("to_next_stop")) < calm_before_stop
	if calling_back:
		for r: Rider in _riders:
			if r.state == State.ERRAND and r.errand_phase in ["out", "there"]:
				_errand_back(r)
	# Up in good time for one's own stop.
	if phase == "braking":
		var nxt := str(_ts.get("next_stop"))
		for r: Rider in _riders:
			if r.state == State.SEATED and not r.seat.is_empty() and _dest(r) == nxt and not r.body.has_meta("in_talk"):
				r.state = State.PREPARING
	_trip_t -= delta
	if _trip_t > 0.0 or calling_back:
		return
	_trip_t = trip_check * _rng.randf_range(0.7, 1.3)
	if _rng.randf() > trip_chance:
		return
	var out := 0
	for r: Rider in _riders:
		if r.state == State.ERRAND:
			out += 1
	if out >= max_wandering:
		return
	var clock := float(_ts.get("clock"))
	var nxt := str(_ts.get("next_stop"))
	var can: Array = []
	for r: Rider in _riders:
		if r.state == State.SEATED and not r.seat.is_empty() and clock >= r.next_errand and _dest(r) != nxt and not r.ghost \
				and not r.body.has_meta("in_talk") and not r.body.is_speaking():
			can.append(r)
	if can.is_empty():
		return
	start_errand(can[_rng.randi_range(0, can.size() - 1)])

## Sends a seated passenger on an errand now ("wc", "window" or "" for either); false if it cannot.
func start_errand(r: Rider, kind := "") -> bool:
	if r.state != State.SEATED or r.seat.is_empty() or not _nav_ready():
		return false
	var wc: Dictionary = _wc.get(r.car, {})
	var go_wc := not wc.is_empty() and wc.user == null and (kind == "wc" or (kind == "" and _rng.randf() < 0.55))
	if kind == "wc" and not go_wc:
		return false
	r.mover = NpcMover.new(r.body, _nav, true)
	r.mover.speed = WALK_IN
	r.errand = "wc" if go_wc else "window"
	if go_wc:
		wc.user = r
		r.wc_car = r.car
		r.mover.goal = wc.spot
	else:
		r.mover.goal = _window_spot(r.car)
	r.errand_phase = "out"
	r.state = State.ERRAND
	# Out of the seat: up on the feet in place, then the step into the aisle.
	r.body.sit_target = 0.0
	r.path = [[_seat_exit(r.seat), WALK_IN * 0.6]]
	r.errand_t = -1.0                   # (still getting up)
	return true

# Standing room in the vestibule by the boarding-side exterior door, looking out of its window.
func _window_spot(car: Node3D) -> Vector3:
	var dx := _door_x(car)
	var c := _nav.nearest_free(Vector3(dx, TrainNav.FLOOR_Y, 0.55 * (1.0 if _rng.randf() < 0.5 else -1.0)), true, 0.6)
	return _nav.cell_pos(c) if c.x >= 0 else Vector3(dx, TrainNav.FLOOR_Y, 0.0)

func _update_errand(r: Rider, delta: float) -> void:
	var b := r.body
	# Getting up and stepping out to the seat's front (straight ahead, no nav needed).
	if r.errand_t < 0.0:
		if b._sit > 0.02 or b.sit_target > 0.0:
			_stand_step(r, delta)
			return
		if not r.path.is_empty():
			_walk_steps(r, delta)
			return
		r.errand_t = 0.0
		if r.errand_phase == "out" and not r.mover.go(r.mover.goal):
			push_warning("Passengers: %s cannot get to the %s (%s) - sits down again" % [b.name, r.errand, r.mover.reason])
			r.errand_phase = "sit"
		return
	match r.errand_phase:
		"out":
			var st := r.mover.update(delta)
			if st == "arrived":
				r.errand_phase = "there"
				r.errand_t = 0.0
				if r.errand == "wc":
					var wc: Dictionary = _wc[r.wc_car]
					(wc.door as TrainDoor).request(false)
					var face := (wc.door.get_parent() as Node3D).global_position - b.global_position
					b.rotation.y = atan2(-face.x, -face.z)       # back to the door
				else:
					var side := signf(b.global_position.z) if absf(b.global_position.z) > 0.05 else 1.0
					b.rotation.y = atan2(0.0, side)              # facing the door's window
			elif st == "failed":
				push_warning("Passengers: %s gave up on the %s (%s)" % [b.name, r.errand, r.mover.reason])
				_errand_back(r)
		"there":
			r.errand_t += delta
			if r.errand == "wc":
				var wc: Dictionary = _wc[r.wc_car]
				var lock: Node = wc.lock
				var door: TrainDoor = wc.door
				if lock and not bool(lock.get("locked")) and not door.is_open() and float(door.get("_t")) < 0.02:
					lock.call("toggle")                          # ENGAGED
			var stay := wc_seconds if r.errand == "wc" else window_seconds
			if r.errand_t > lerpf(stay.x, stay.y, float(r.pid % 7) / 6.0):
				_errand_back(r)
		"back":
			var st := r.mover.update(delta)
			if st == "arrived":
				r.errand_phase = "sit"
				r.mover.release()
				_free_wc(r)
				r.path = [[_seat_front(r.seat), WALK_IN * 0.6]]
			elif st == "failed":
				# Never through a wall: it waits where it is and tries again in a moment. After a
				# few tries in vain it stops planning: it waits for the way (tried now and then) and
				# is back in its seat the moment nobody sees it.
				r.errand_t += delta
				if r.back_tries >= BACK_TRIES and _unseen(b):
					push_warning("Passengers: %s could not get back to its seat (%s) - put back unseen" % [b.name, r.mover.reason])
					_end_errand(r)
					_settle(r)
				elif r.errand_t > (3.0 if r.back_tries < BACK_TRIES else 15.0):
					r.errand_t = 0.0
					r.back_tries += 1
					if r.back_tries <= BACK_TRIES:
						push_warning("Passengers: %s cannot get back to its seat yet (%s); retry %d" % [b.name, r.mover.reason, r.back_tries])
					r.mover.go(_seat_exit(r.seat))
		"sit":
			if not r.path.is_empty():
				_walk_steps(r, delta)
				return
			if _sit_step(r, delta):
				_end_errand(r)
				r.state = State.SEATED

func _errand_back(r: Rider) -> void:
	if r.errand_phase in ["back", "sit"]:
		return
	if r.errand == "wc" and _wc.has(r.wc_car):
		var wc: Dictionary = _wc[r.wc_car]
		if wc.lock and bool(wc.lock.get("locked")):
			wc.lock.call("toggle")                              # VACANT
	if r.errand_t < 0.0:
		r.errand_phase = "sit"                                  # never left the seat's front
		r.path = [[_seat_front(r.seat), WALK_IN * 0.6]]
		return
	r.errand_phase = "back"
	r.errand_t = 0.0
	r.back_tries = 0
	if not r.mover.go(_seat_exit(r.seat)):
		push_warning("Passengers: %s has no way back to its seat yet (%s)" % [r.body.name, r.mover.reason])

## Failed ways back to the seat before an errand gives up planning (see _update_errand "back").
const BACK_TRIES := 4

# Out of the player's sight: far off, or outside the camera's view (behind a wall in another car
# counts only by distance).
func _unseen(b: Node3D) -> bool:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var head := b.global_position + Vector3(0, 1.4, 0)
	if cam == null:
		return true
	if cam.global_position.distance_to(head) > 14.0:
		return true
	return not cam.is_position_in_frustum(head) and not cam.is_position_in_frustum(b.global_position + Vector3(0, 0.5, 0))

func _free_wc(r: Rider) -> void:
	if r.wc_car and _wc.has(r.wc_car) and _wc[r.wc_car].user == r:
		var wc: Dictionary = _wc[r.wc_car]
		if wc.lock and bool(wc.lock.get("locked")):
			wc.lock.call("toggle")
		wc.user = null
	r.wc_car = null

func _end_errand(r: Rider) -> void:
	_free_wc(r)
	if r.mover:
		r.mover.release()
		r.mover = null
	r.errand = ""
	r.errand_phase = ""
	r.path = []
	r.body.walk_speed = 0.0
	r.next_errand = float(_ts.get("clock")) + _rng.randf_range(trip_gap_min, trip_gap_max) / 60.0

# Short straight steps (r.path) without the nav (out of a seat to its front).
func _walk_steps(r: Rider, delta: float) -> void:
	var step: Array = r.path[0]
	var to: Vector3 = step[0]
	var at := r.body.global_position
	var left := at.distance_to(to)
	if left < 0.03:
		r.body.global_position = to
		r.path.pop_front()
		r.body.walk_speed = 0.0
		return
	r.body.global_position = at + (to - at).normalized() * minf(float(step[1]) * delta, left)
	r.body.walk_speed = float(step[1])

# Up and waiting by the seat as the train brakes for its own stop.
func _update_preparing(r: Rider, delta: float) -> void:
	_stand_step(r, delta)

# ————— for the guard (Detention), the ghost story and tests —————

func riders() -> Array:
	return _riders

func rider_of(body: Node) -> Rider:
	for r: Rider in _riders:
		if r.body == body:
			return r
	return null

func rider_by_pid(pid: int) -> Rider:
	for r: Rider in _riders:
		if r.pid == pid:
			return r
	return null

## Keeps a character's face off the passengers (the ghost wears it).
func reserve_slug(slug: String) -> void:
	_in_use[slug] = true

## Taken out of the passengers' own routine (Detention walks it): an errand is called off where it
## stands (the W.C. freed), it stays out of the alighting and errand lists. Its seat stays its own.
func take_for_escort(r: Rider) -> bool:
	if r == null or not (r.state in [State.SEATED, State.ERRAND, State.PREPARING]):
		return false
	_end_errand(r)
	r.state = State.UNDER_ESCORT
	return true

## In the holding cage.
func set_detained(r: Rider) -> void:
	r.state = State.DETAINED

## The guard gives a wrongly held passenger back: it walks to its own seat (or a free one in its
## car) - Detention walks it; this only gives it a seat and the state.
func seat_for_return(r: Rider) -> Dictionary:
	if r.seat.is_empty():
		var s := _free_seat((r.car as Node).name if r.car else "")
		if s.is_empty():
			s = _free_seat()
		if not s.is_empty():
			_take_seat(r, s)
	return r.seat

## Back on its seat (Detention brought it there): its own routine again.
func returned_to_seat(r: Rider) -> void:
	r.body.global_transform = _seat_xf(r.seat)
	r.body.sit_target = 1.0
	r.body.walk_speed = 0.0
	r.state = State.SEATED
	r.next_errand = float(_ts.get("clock")) + trip_gap_max / 60.0

## Gives up a held passenger's seat (it will not come back to it).
func free_seat_of(r: Rider) -> void:
	if not r.seat.is_empty():
		r.seat.taken = false
		r.seat = {}

func seat_front(r: Rider) -> Vector3:
	return _seat_front(r.seat)

func seat_exit(r: Rider) -> Vector3:
	return _seat_exit(r.seat)

func seat_xf(r: Rider) -> Transform3D:
	return _seat_xf(r.seat)

# ————— the ghost among them (HauntDirector) —————

## This passenger was never alive: its ticket becomes the 1931 one, it casts no shadow, it stays put.
func make_ghost(r: Rider) -> void:
	r.ghost = true
	r.body.set_meta("ghost_passenger", true)
	var t := PassengerTalk.of(r.body)
	if t:
		t.become_ghost()
	for mi: MeshInstance3D in r.body.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Laid to rest: it pales to the apparition's colour, wavers, and is gone, its seat empty. Once only.
func reveal_ghost(r: Rider, how := "calmed") -> void:
	if r == null or not r.ghost or r.state == State.VANISHING or not _riders.has(r):
		return
	_end_errand(r)
	r.state = State.VANISHING
	r.body.walk_speed = 0.0
	if r.body.has_node("Talk"):
		r.body.get_node("Talk").queue_free()           # (nothing left to talk to)
	if not r.seat.is_empty():
		r.seat.taken = false
		r.seat = {}
	var rec := ShiftRecord.of(self)
	if rec:
		rec.ghost_revealed(r, how)
	GhostFade.start(r.body, func() -> void:
		if _riders.has(r):
			_drop(r))

## A seated passenger of that car near the player says something (a haunted car's complaining).
## Someone seated in the car says it; returns who (null if nobody could).
func complain(car: Node3D, text: String) -> TalkingCharacter:
	var can: Array = _riders.filter(func(r): return r.car == car and r.state == State.SEATED and not r.ghost \
			and not r.body.is_speaking() and not r.body.has_meta("in_talk"))
	if can.is_empty():
		return null
	var r: Rider = can[_rng.randi_range(0, can.size() - 1)]
	r.body.subtitle_range = 18.0
	r.body.say(text)
	return r.body

## The car's W.C. out of order (nobody goes there) or back in use; false if someone is inside it.
func block_wc(car: Node3D, blocked: bool) -> bool:
	_nav_ready()
	if not _wc.has(car):
		return false
	var wc: Dictionary = _wc[car]
	if blocked:
		if wc.user != null:
			return false
		wc.user = "out of order"
	elif str(wc.user) == "out of order":
		wc.user = null
	return true

# ————— for PassingTrain's apparitions —————

## Faces nobody aboard is wearing just now.
func free_faces(n: int) -> Array:
	var free: Array = []
	for s in _slugs:
		if not _in_use.has(s) and not _loading.has(s):
			free.append(s)
	free.shuffle()
	return free.slice(0, n)

func release_slug(slug: String) -> void:
	_in_use.erase(slug)

## Empty seats within `r` metres of a point.
func free_seats_near(at: Vector3, r: float) -> Array:
	return _seats.filter(func(s): return not s.taken and (s.marker as Node3D).global_position.distance_to(at) < r)

func seat_xf_of(seat: Dictionary) -> Transform3D:
	return _seat_xf(seat)
