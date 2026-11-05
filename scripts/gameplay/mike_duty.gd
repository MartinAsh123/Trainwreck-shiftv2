class_name MikeDuty
extends Node
## Mike, the train's guard, at work. One job at a time, chosen by priority:
##   escort / release (a passenger Kevin reported, or one to let out) - never interrupted
##   station duty   - at every stop he stands in the crew car's vestibule until the train is away
##   a report       - taken on as soon as no station needs him
##   patrol         - every `patrol_every` game minutes: through the corridor of his own car, both
##                    saloons and the sleeping car's corridor, pausing to look round in each, and back
##   rest           - once a night, a short nap on his bunk (facing the wall: the figures have no
##                    eyelids), only when nothing else is due and the next stop is far enough off
##   his room       - otherwise at his desk over the ledger
## Kevin talking to him stops him where he is (not during an escort). Kevin wakes him with E (or a
## report, a station or a release does); he sits up on the bunk and gets to his feet, never jumps.
## Escort: he walks to the passenger, has a word, it stands and follows him a step behind through
## the real doors and gangways to the mail van; he opens the cage, it goes in and sits on the bench,
## he shuts and locks the gate (always - whatever happens) and goes back to duty.

const MIKE_SPEED := 1.0
const ESCORT_SPEED := 0.75
const BLOCKED_GIVE_UP := 45.0        # seconds stuck in an escort before calling it off

@export var patrol_first := 19.0 + 25.0 / 60.0
@export var patrol_every := 30.0     # game minutes between patrols
@export var observe_seconds := 5.0
@export var rest_enabled := true
@export var rest_start := 20.0 + 20.0 / 60.0    # not before (game clock)
@export var rest_latest := 20.0 + 55.0 / 60.0   # not after
@export var rest_minutes := 10.0     # game minutes asleep
@export var station_near := 450.0    # metres before a stop when he goes to the vestibule

var mike: TalkingCharacter
var mover: NpcMover
var job := ""                         # room | patrol | station | rest | escort | release
var phase := ""
var asleep := false
var rested := false
var next_patrol := 0.0
var log_lines: Array[String] = []     # (for tests) what he did, in order

var _ts: Node
var _nav: TrainNav
var _det: Detention
var _cage: HoldingCage
var _pax: Passengers
var _room_spot := Vector3.ZERO
var _room_face := Vector3.ZERO
var _bed: Node3D
var _bed_side := 1.0
var _look: Node3D                      # what he looks at (the head follows look_at_target)
var _t := 0.0
var _patrol_pts: Array = []
var _patrol_i := 0
var _rider                            # the passenger of the current escort / release
var _place := -1
var _steps: Array = []                # the passenger's own scripted steps (into / out of the cage)
var _stuck := 0.0
var _wake_requested := false
var _said := {}
var _blanket: SleepBlanket

static func of(n: Node) -> MikeDuty:
	return n.get_tree().get_first_node_in_group("mike_duty") as MikeDuty

func _ready() -> void:
	add_to_group("mike_duty")
	_ts = get_node_or_null("/root/TrainState")
	_setup.call_deferred()

func _setup() -> void:
	var train := get_tree().root.find_child("Train", true, false)
	mike = train.find_child("Mike", true, false) as TalkingCharacter if train else null
	if mike == null:
		push_warning("MikeDuty: Mike is not aboard")
		set_process(false)
		return
	# He walks now: the fixed capsule that stood in for him goes (his own solid follows him).
	var fixed := mike.get_parent().get_node_or_null("MikeBody")
	if fixed:
		fixed.queue_free()
	_room_spot = mike.global_position
	_room_face = mike.global_position + Vector3(0, 0, 1.0)
	var room := mike.get_parent() as Node3D
	var desk := room.get_node_or_null("Desk") as Node3D
	if desk:
		_room_face = desk.global_position + Vector3(0, 0.8, 0)
	_bed = room.get_node_or_null("Bed") as Node3D
	if _bed:
		_bed_side = signf(_room_spot.x - _bed.global_position.x)
		if _bed_side == 0.0:
			_bed_side = 1.0
	_look = Node3D.new()
	_look.name = "MikeLook"
	add_child(_look)
	next_patrol = patrol_first
	job = "room"
	phase = ""

func _wire() -> bool:
	if _nav == null:
		_nav = TrainNav.of(self)
	if _nav == null or not _nav.ready_:
		return false
	if mover == null:
		mover = NpcMover.new(mike, _nav, false)
		mover.priority = 10
		mover.speed = MIKE_SPEED
		_patrol_pts = [
			[Vector3(-35.3, 1.4, -1.0), 0.0],
			[Vector3(-17.5, 1.4, 0.0), observe_seconds],
			[Vector3(0.0, 1.4, 0.0), observe_seconds],
			[Vector3(17.4, 1.4, -1.0), observe_seconds],
			[Vector3(0.6, 1.4, 0.0), 0.0],
			[Vector3(-18.0, 1.4, 0.0), 0.0],
		]
	if _det == null:
		_det = Detention.of(self)
	if _cage == null:
		_cage = HoldingCage.of(self)
	if _pax == null:
		_pax = get_tree().root.find_child("Passengers", true, false) as Passengers
	return true

func _note(s: String) -> void:
	log_lines.append("%s %s" % [TerminalData.clock_text(), s])

# ————— what to do —————

func _station_needed() -> bool:
	var ph := str(_ts.get("phase"))
	return ph in ["stopped", "departing"] or (ph == "braking" and float(_ts.get("to_next_stop")) < station_near)

func _rest_due() -> bool:
	if not rest_enabled or rested or str(_ts.get("phase")) != "running":
		return false
	var c := float(_ts.get("clock"))
	if c < rest_start or c > rest_latest:
		return false
	# Long enough to the next stop for the whole nap (and a little to wake up in).
	var v := maxf(float(_ts.get("speed")), 5.0)
	var game_min_left := float(_ts.get("to_next_stop")) / v * TaskBoard.hours_per_second(self) * 60.0
	return game_min_left > rest_minutes + 3.0

func _decide() -> String:
	if job in ["escort", "release"]:
		return job
	if _station_needed():
		return "station"
	if _det and _det.next_release() >= 0:
		return "release"
	if _det and _det.pending_pid >= 0:
		return "escort"
	if job == "rest" and asleep and not _wake_requested:
		return "rest"
	if job == "patrol":
		return "patrol"
	if float(_ts.get("clock")) >= next_patrol:
		return "patrol"
	if _rest_due() or job == "rest":
		return "rest"
	return "room"

func _process(delta: float) -> void:
	if mike == null or not _wire():
		return
	# Asleep or getting up: the bunk sequence runs to its end first.
	if job == "rest" and phase in ["turn", "lie_down", "sleep", "wake"]:
		_update_rest(delta)
		return
	var want := _decide()
	if want != job:
		_switch(want)
	# Kevin talking to him: he stops and turns to him (an escort carries on).
	if mike.has_meta("in_talk") and not (job in ["escort", "release"]):
		mover.stop()
		mike.walk_speed = 0.0
		mike.look_at_target = null
		_face(mike._find_player().global_position, delta)
		return
	match job:
		"room":
			_update_room(delta)
		"patrol":
			_update_patrol(delta)
		"station":
			_update_station(delta)
		"rest":
			_update_rest(delta)
		"escort":
			_update_escort(delta)
		"release":
			_update_release(delta)

func _switch(to: String) -> void:
	if job == "patrol" and to != "patrol":
		next_patrol = float(_ts.get("clock")) + 8.0 / 60.0          # interrupted: again soon
	_note("%s -> %s" % [job, to])
	job = to
	phase = ""
	_t = 0.0
	mover.stop()
	mike.look_at_target = null
	match to:
		"escort":
			_start_escort()
		"release":
			_start_release()

# ————— room, patrol, station —————

func _update_room(delta: float) -> void:
	if phase == "":
		phase = "go"
		mover.speed = MIKE_SPEED
		if not mover.go(_room_spot):
			phase = "there"
	if phase == "go":
		if mover.update(delta) in ["arrived", "failed"]:
			phase = "there"
		return
	_face(_room_face, delta)
	_look.global_position = _room_face
	mike.look_at_target = _look

func _update_patrol(delta: float) -> void:
	if phase == "":
		_patrol_i = 0
		phase = "go"
		mover.speed = MIKE_SPEED
		mover.go(_patrol_pts[0][0])
		_note("patrol starts")
	match phase:
		"go":
			var st := mover.update(delta)
			# Someone (Kevin) standing in the way: a word, and in the end that leg is let go.
			_stuck = _stuck + delta if st == "waiting" else 0.0
			if _stuck > 12.0:
				_say_once("patrol_way", "Excuse me, Kevin.")
			if _stuck > 30.0:
				st = "failed"
				mover.reason = "the way was blocked"
			if st == "arrived" or st == "failed":
				if st == "failed":
					push_warning("MikeDuty: patrol leg %d skipped (%s)" % [_patrol_i, mover.reason])
					mover.stop()
				_said.erase("patrol_way")
				_stuck = 0.0
				phase = "observe"
				_t = 0.0
		"observe":
			_t += delta
			var hold: float = _patrol_pts[_patrol_i][1]
			if hold > 0.0:
				# A slow look round: down one side, then the other.
				var s := sin(_t / hold * TAU)
				_look.global_position = mike.global_position + mike.global_basis * Vector3(s * 1.5, 1.4, 2.0)
				mike.look_at_target = _look
			if _t >= hold:
				mike.look_at_target = null
				_patrol_i += 1
				if _patrol_i >= _patrol_pts.size():
					next_patrol = float(_ts.get("clock")) + patrol_every / 60.0
					_note("patrol done")
					job = "room"
					phase = ""
					return
				phase = "go"
				mover.go(_patrol_pts[_patrol_i][0])

func _vestibule_spot() -> Vector3:
	var side := 1.0
	for st: Dictionary in RouteData.stops():
		if st.name == str(_ts.get("station")) or st.name == str(_ts.get("next_stop")):
			side = float(st.side)
			if st.name == str(_ts.get("station")):
				break
	var c := _nav.nearest_free(Vector3(-41.9, 1.4, side * 0.55), false, 0.6)
	return _nav.cell_pos(c) if c.x >= 0 else _room_spot

func _update_station(delta: float) -> void:
	if phase == "":
		phase = "go"
		mover.speed = MIKE_SPEED * 1.1
		mover.go(_vestibule_spot())
	if phase == "go":
		if mover.update(delta) in ["arrived", "failed"]:
			phase = "there"
			_note("station duty")
		return
	var side := signf(mike.global_position.z) if absf(mike.global_position.z) > 0.05 else 1.0
	_face(mike.global_position + Vector3(0, 0, side), delta)

# ————— rest on the bunk —————

# ————— the bunk: poses and the way between them —————
# Each pose is the body's turn (in the bed's frame: x across, z along with the pillow at +z), where
# its hips are, and the sitting/lying values TalkingCharacter needs. Going from one to the next turns
# about one axis only and about the hips (never the feet), so lying down reads as a person doing it:
# sit on the edge -> down onto the side facing the room -> over onto the back -> over to the wall
# (the figures have no eyelids: asleep, they face the wall). Getting up is the same backwards.

const STAND := 0
const SIT := 1
const SIDE := 2
const BACK := 3
const WALL := 4

var _poses: Array = []

func _bunk_poses() -> Array:
	if not _poses.is_empty():
		return _poses
	var s := _bed_side
	var m := SleepBlanket.MATTRESS
	var hip := mike._hip_h
	var sit_b := Basis(Vector3(0, 0, -s), Vector3(0, 1, 0), Vector3(s, 0, 0))     # facing the room
	var side_b := _turned(sit_b, Vector3(s, 0, 0), func(b: Basis): return b.y.dot(Vector3(0, 0, 1)))
	var back_b := _turned(side_b, Vector3(0, 0, 1), func(b: Basis): return b.z.dot(Vector3.UP))
	var wall_b := _turned(back_b, Vector3(0, 0, 1), func(b: Basis): return b.z.dot(Vector3(-s, 0, 0)))
	var lie_o := Vector3(s * 0.03, m + 0.17, 0.70 - (mike._head_h - 0.1))
	var lie_hip := lie_o + wall_b * Vector3(0, hip, 0)
	var lie_sh := hip - 0.1
	_poses = [
		{"b": sit_b, "hip": Vector3(s * 0.68, hip, 0.1), "sh": 0.42, "sit": 0.0, "lie": 0.0, "tuck": 0.0, "legs": 0.0, "lside": 0.0},
		{"b": sit_b, "hip": Vector3(s * 0.22, m + 0.1, 0.1), "sh": m, "sit": 1.0, "lie": 0.0, "tuck": 0.0, "legs": 0.0, "lside": 0.0},
		{"b": side_b, "hip": lie_hip + Vector3(-s * 0.06, -0.01, 0), "sh": lie_sh, "sit": 0.4, "lie": 0.0, "tuck": 1.0, "legs": 1.0, "lside": -s},
		# (on the back: legs straight and arms by the sides - drawn-up knees and folded arms suit
		# lying on the side, but on the back they would point at the ceiling)
		{"b": back_b, "hip": lie_hip + Vector3(0, -0.05, 0), "sh": lie_sh, "sit": 0.0, "lie": 0.0, "tuck": 1.0, "legs": 0.0, "lside": 0.0},
		{"b": wall_b, "hip": lie_hip, "sh": lie_sh, "sit": 0.5, "lie": 1.0, "tuck": 1.0, "legs": 1.0, "lside": s},
	]
	return _poses

# `b` turned a quarter about `axis`, whichever way `score` likes better.
static func _turned(b: Basis, axis: Vector3, score: Callable) -> Basis:
	var p := Basis(axis.normalized(), PI * 0.5) * b
	var n := Basis(axis.normalized(), -PI * 0.5) * b
	return (p if float(score.call(p)) >= float(score.call(n)) else n).orthonormalized()

# Places Mike between poses a and b (w 0..1).
func _bunk_pose(a: int, b: int, w: float) -> void:
	var P := _bunk_poses()
	var pa: Dictionary = P[a]
	var pb: Dictionary = P[b]
	var e := smoothstep(0.0, 1.0, w)
	var basis: Basis = (pa.b as Basis).slerp(pb.b, e).orthonormalized()
	var hip: Vector3 = (pa.hip as Vector3).lerp(pb.hip, e)
	var sh := lerpf(pa.sh, pb.sh, e)
	# Knees and arms: straightened early on the way onto the back, drawn up / folded late on the way
	# off it - so they never point at the ceiling half-way through a roll.
	var ek := e
	if a == BACK or b == BACK:
		ek = smoothstep(0.0, 0.45, w) if b == BACK else smoothstep(0.55, 1.0, w)
	var sit := lerpf(pa.sit, pb.sit, ek)
	mike.sit_height = sh
	mike.sit_target = sit
	mike._sit = sit
	mike.lie = lerpf(pa.lie, pb.lie, ek)
	mike.lie_legs = lerpf(pa.legs, pb.legs, ek)
	mike.lie_side = pb.lside if pb.legs > 0.0 else pa.lside
	# (arms kept to the body from the moment he leans back, all the way through the rolls)
	mike.tuck = lerpf(pa.tuck, pb.tuck, smoothstep(0.0, 0.5, w) if pb.tuck > pa.tuck else smoothstep(0.5, 1.0, w))
	# The hips' height over the body's own origin for that sitting value (as TalkingCharacter poses it).
	var k := sit * sit * (3.0 - 2.0 * sit)
	var h := mike._hip_h + (sh + 0.1 - mike._hip_h) * k
	mike.global_transform = _bed.global_transform * Transform3D(basis, hip - basis * Vector3(0, h, 0))
	# Head still while lying down; "asleep" (no looking round, slow breaths) once turning to the wall.
	mike.asleep = (a >= BACK and b >= BACK and e > 0.3) or (a == WALL or b == WALL and e > 0.5)

# A run of poses over time: [[from, to, t0, t1], ...] - before a step, its start pose holds.
func _bunk_run(steps: Array, t: float) -> void:
	for st: Array in steps:
		if t < float(st[3]):
			_bunk_pose(st[0], st[1], clampf((t - float(st[2])) / (float(st[3]) - float(st[2])), 0.0, 1.0))
			return
	var last: Array = steps.back()
	_bunk_pose(last[0], last[1], 1.0)

const LIE_DOWN := [[STAND, SIT, 0.0, 1.3], [SIT, SIDE, 1.5, 3.1], [SIDE, BACK, 3.3, 4.3], [BACK, WALL, 4.4, 5.4]]
const GET_UP := [[WALL, BACK, 0.2, 1.2], [BACK, SIDE, 2.5, 3.5], [SIDE, SIT, 3.7, 5.3], [SIT, STAND, 5.5, 6.7]]

func _stand_xf() -> Transform3D:
	var p: Dictionary = _bunk_poses()[STAND]
	return Transform3D(p.b, p.hip - (p.b as Basis) * Vector3(0, mike._hip_h, 0))

func _update_rest(delta: float) -> void:
	if _bed == null:
		rested = true
		job = "room"
		return
	match phase:
		"":
			phase = "go"
			mover.speed = MIKE_SPEED * 0.9
			mover.go((_bed.global_transform * _stand_xf()).origin)
		"go":
			var st := mover.update(delta)
			if st in ["arrived", "failed"]:
				phase = "turn"
				_t = 0.0
				mover.stop()
		"turn":
			# Square to the bed's edge before sitting (from wherever the walk ended).
			_t += delta
			var xf := _bed.global_transform * _stand_xf()
			mike.global_transform = mike.global_transform.interpolate_with(xf, clampf(delta * 4.0, 0.0, 1.0))
			if _t > 0.8:
				mike.global_transform = xf
				phase = "lie_down"
				_t = 0.0
				_note("lies down")
		"lie_down":
			# Down onto the bunk, then the blanket pulled up (the sleeping car's wool blanket).
			if _blanket == null:
				_blanket = SleepBlanket.new()
				_blanket.name = "MikeBlanket"
				_bed.add_child(_blanket)
			if _t == 0.0:
				_blanket.set_body(mike)
				_blanket.disturbed = 0.0
				_blanket.fold = 1.0
			_blanket.lively = true
			_t += delta
			_bunk_run(LIE_DOWN, _t)
			_blanket.fold = 1.0 - smoothstep(4.3, 5.6, _t)       # (up over him as he turns to the wall)
			if _t >= 6.8:
				_blanket.lively = false
				phase = "sleep"
				_t = 0.0
				asleep = true
				mike.asleep = true
				_wake_requested = false
		"sleep":
			_t += delta
			var minutes := _t * TaskBoard.hours_per_second(self) * 60.0       # (game minutes asleep)
			if _wake_requested or minutes >= rest_minutes or _station_needed() or (_det and (_det.pending_pid >= 0 or _det.next_release() >= 0)):
				phase = "wake"
				_t = 0.0
				_note("wakes" + (" (woken)" if _wake_requested else ""))
		"wake":
			# The blanket thrown back first, then over, up onto the edge and onto the feet.
			_t += delta
			_blanket.lively = true
			_blanket.fold = smoothstep(1.2, 2.4, _t)
			_blanket.disturbed = maxf(_blanket.disturbed, smoothstep(1.2, 2.4, _t))
			_bunk_run(GET_UP, _t)
			if _t >= 7.0:
				_blanket.set_body(null)
				_blanket.lively = false
				mike.sit_target = 0.0
				mike._sit = 0.0
				mike.sit_height = 0.42
				mike.lie = 0.0
				mike.tuck = 0.0
				mike.lie_legs = 0.0
				mike.asleep = false
				asleep = false
				rested = true
				_wake_requested = false
				job = "room"
				phase = ""
				if not _said.has("woke"):
					_said["woke"] = true
					mike.say("Mm. I'm up. What is it?", 2.0)

## Kevin (E) wakes him.
func wake() -> void:
	if asleep:
		_wake_requested = true

func is_asleep() -> bool:
	return job == "rest" and phase in ["lie_down", "sleep"]

# ————— the escort —————

func _start_escort() -> void:
	var pid := _det.take_pending()
	_rider = _pax.rider_by_pid(pid) if _pax else null
	_place = _cage.free_place() if _cage else -1
	_stuck = 0.0
	if _rider == null or _place < 0:
		_abort("the passenger is gone" if _rider == null else "the cage is full")
		return
	_note("escort of %s" % _rider.body.name)
	phase = "to_suspect"
	mover.speed = MIKE_SPEED
	mover.go(_beside(_rider))

# A spot in the aisle by the passenger's seat: a step toward the mail van when fetching it (so it
# follows behind him), a step past the seat when bringing it back (so it reaches the seat first).
func _beside(r, past := false) -> Vector3:
	var p: Vector3 = _pax.seat_exit(r) if not r.seat.is_empty() and r.state != Passengers.State.ERRAND else r.body.global_position
	var dx := 1.2 if past else -0.9
	var c := _nav.nearest_free(Vector3(p.x + dx, 1.4, 0.0 if r.car == null or String(r.car.name) != "SleeperCar1" else -1.0), false, 0.8)
	return _nav.cell_pos(c) if c.x >= 0 else p

func _update_escort(delta: float) -> void:
	if phase == "ghost":
		# It was a ghost: he stands staring a moment, says his piece, and goes back to duty.
		_t += delta
		if _t > 1.2:
			_say_once("ghost", "...Mother of God. My hand went through. That's not one for the cage, Kevin. Ask that friend of yours.")
		if _t > 6.5:
			_note("the reported passenger was a ghost: left where it sat")
			_end_job()
		return
	if _rider == null or not is_instance_valid(_rider.body):
		_abort("the passenger is gone")
		return
	var b: TalkingCharacter = _rider.body
	match phase:
		"to_suspect":
			# It may have got up meanwhile (an errand): it is taken over where it stands.
			var st := mover.update(delta)
			if _blocked(st, delta):
				return
			if st == "arrived" or mover.pos().distance_to(b.global_position) < 1.3:
				mover.stop()
				if _rider.ghost:
					# Not a living passenger: his hand goes through its shoulder. No cage holds that.
					_det.on_vanished(_rider)
					GhostFade.flash(b)
					phase = "ghost"
					_t = 0.0
					return
				if not _pax.take_for_escort(_rider):
					_abort("the passenger is no longer aboard")
					return
				phase = "arrest"
				_t = 0.0
				_say_once("arrest", "Come with me, please. Just a few questions in the van.")
		"arrest":
			_t += delta
			_face(b.global_position, delta)
			if _t > 2.4 and not _said.has("reply"):
				_said["reply"] = true
				b.say(["What? Why me?", "I've done nothing wrong.", "...Very well.", "Is this about my ticket?"][_rider.pid % 4], 2.0)
			if _t < 3.0:
				return
			# Up out of the seat and into the aisle, then a step behind him.
			if not _rider.seat.is_empty() and _rider.body._sit > 0.0:
				if not _pax._stand_step(_rider, delta):
					return
				_steps = [_pax.seat_exit(_rider)]
			if not _steps.is_empty():
				if _step_rider(delta):
					_steps.pop_front()
				return
			_rider.mover = NpcMover.new(b, _nav, false)
			_rider.mover.speed = ESCORT_SPEED
			mover.trail = PackedVector3Array([b.global_position, mover.pos()])
			_rider.mover.follow(mover, 1.1)
			mover.speed = ESCORT_SPEED
			mover.go(_cage.approach_point())
			phase = "lead"
			_stuck = 0.0
		"lead":
			_rider.mover.update(delta)
			# Never lose the passenger: wait for it when it falls behind.
			if mover.pos().distance_to(b.global_position) > 2.6:
				mike.walk_speed = 0.0
				_stuck += delta
				if _stuck > BLOCKED_GIVE_UP:
					_abort("lost the passenger on the way")
				return
			var st := mover.update(delta)
			if _blocked(st, delta):
				return
			if st == "arrived":
				phase = "open"
				_t = 0.0
				_say_once("cage", "In here. Sit on the bench, and mind the step.")
		"open":
			_rider.mover.update(delta)
			_face(_cage.gate_middle(), delta)
			_cage.unlock_and_open()
			if _cage.is_open_wide() and b.global_position.distance_to(mover.pos()) < 2.2:
				_rider.mover.release()
				_rider.mover = null
				_steps = [_cage.gateway_point(false), _cage.gateway_point(true), _cage.inside_point(_place)]
				_cage.take_place(_place, _rider.pid)
				phase = "enter"
		"enter":
			_face(_cage.gate_middle(), delta)
			if not _steps.is_empty():
				if _step_rider(delta):
					_steps.pop_front()
				return
			# Down onto the bench.
			var xf := _cage.place_xf(_place)
			b.sit_height = HoldingCage.SIT_H
			b.sit_target = 1.0
			b.global_basis = b.global_basis.orthonormalized().slerp(xf.basis.orthonormalized(), clampf(delta * 5.0, 0.0, 1.0))
			b.global_position = _cage.inside_point(_place).lerp(xf.origin, smoothstep(0.0, 1.0, b._sit))
			if b._sit > 0.97:
				b.global_transform = xf
				_pax.set_detained(_rider)
				phase = "close"
				_t = 0.0
		"close":
			_face(_cage.gate_middle(), delta)
			_t += delta
			if _t > 6.0:
				_say_once("stand_back", "Stand clear of the gate, please.")
			if _cage.close_and_lock():
				_det.on_detained(_rider, _place)
				_note("locked in %s" % b.name)
				_say_once("locked", "Sit tight. Someone will look at your papers.")
				_end_job()

# One straight step of the passenger's own (a few, into or out of the cage).
func _step_rider(delta: float) -> bool:
	var b: TalkingCharacter = _rider.body
	var to: Vector3 = _steps[0]
	var at := b.global_position
	var v := to - at
	if v.length() < 0.04:
		b.global_position = to
		b.walk_speed = 0.0
		return true
	b.global_position = at + v.normalized() * minf(ESCORT_SPEED * 0.8 * delta, v.length())
	b.walk_speed = ESCORT_SPEED * 0.8
	var flat := Vector3(v.x, 0, v.z)
	if flat.length() > 0.02:
		b.rotation.y = lerp_angle(b.rotation.y, atan2(flat.x, flat.z), clampf(delta * 8.0, 0.0, 1.0))
	return false

# Stuck in the way (Kevin in the gangway, a door that will not open...): he says so, and in the end
# calls it off rather than walk through anything.
func _blocked(st: String, delta: float) -> bool:
	if st == "failed":
		_abort("no way through (%s)" % mover.reason)
		return true
	if st == "waiting":
		_stuck += delta
		if _stuck > 8.0:
			_say_once("in_way", "Kevin. You're in the way.")
		if _stuck > BLOCKED_GIVE_UP:
			_abort("the way was blocked")
			return true
	else:
		_stuck = maxf(_stuck - delta, 0.0)
	return false

## Calls the escort (or a release) off: the gate is shut and locked whatever state it is in, the
## passenger walks back to its seat on its own.
func _abort(why: String) -> void:
	_note("abort: " + why)
	push_warning("MikeDuty: escort called off - " + why)
	if _rider != null and is_instance_valid(_rider.body):
		if _rider.mover:
			_rider.mover.release()
			_rider.mover = null
		if _rider.state == Passengers.State.UNDER_ESCORT:
			_send_back(_rider)
	if job == "escort":
		_det.on_cancelled(_rider, why)
	_say_once("abort", "Never mind. We'll sort it out later.")
	_closing = true
	_end_job()

var _closing := false
var _returning: Array = []           # [rider, mover] walking back to their seats on their own

func _send_back(r) -> void:
	var m := NpcMover.new(r.body, _nav, false)
	m.speed = 0.8
	m.go(_pax.seat_exit(r))
	_returning.append([r, m, "walk"])

func _end_job() -> void:
	job = "room"
	phase = ""
	_said.erase("arrest")
	_said.erase("reply")
	_said.erase("cage")
	_said.erase("locked")
	_said.erase("in_way")
	_said.erase("abort")
	_said.erase("sorry")
	_said.erase("stand_back")
	_said.erase("ghost")
	_said.erase("out")
	_rider = null
	_steps.clear()
	mover.speed = MIKE_SPEED

func _physics_process(delta: float) -> void:
	# The gate is never left open: shut and lock it whenever no escort or release has it.
	if _cage and _closing and not (job in ["escort", "release"] and phase in ["open", "enter", "close", "out"]):
		if _cage.close_and_lock():
			_closing = false
	# Passengers walking back to their seats after an escort that fell through.
	for e: Array in _returning.duplicate():
		var r = e[0]
		var m: NpcMover = e[1]
		if r == null or not is_instance_valid(r.body):
			_returning.erase(e)
			continue
		if e[2] == "walk":
			var st := m.update(delta)
			if st == "arrived" or st == "failed":
				m.release()
				e[2] = "front"
		elif e[2] == "front":
			var to: Vector3 = _pax.seat_front(r)
			var at: Vector3 = r.body.global_position
			if at.distance_to(to) < 0.04:
				e[2] = "sit"
			else:
				r.body.global_position = at + (to - at).normalized() * minf(0.5 * delta, at.distance_to(to))
				r.body.walk_speed = 0.5
		elif _pax._sit_step(r, delta):
			_pax.returned_to_seat(r)
			_returning.erase(e)

# ————— letting a wrongly held passenger out —————

func _start_release() -> void:
	var pid := _det.next_release()
	_rider = _pax.rider_by_pid(pid) if _pax else null
	_place = _cage.place_of(pid) if _cage else -1
	if _rider == null or _place < 0:
		_det.to_release.erase(pid)
		_end_job()
		return
	_note("release of %s" % _rider.body.name)
	phase = "to_cage"
	mover.speed = MIKE_SPEED
	mover.go(_cage.approach_point())

func _update_release(delta: float) -> void:
	if _rider == null or not is_instance_valid(_rider.body):
		_closing = true
		_end_job()
		return
	var b: TalkingCharacter = _rider.body
	match phase:
		"to_cage":
			var st := mover.update(delta)
			if st == "failed":
				_note("release: no way to the cage")
				_end_job()
				return
			if st == "arrived":
				phase = "open"
		"open":
			_face(_cage.gate_middle(), delta)
			_cage.unlock_and_open()
			if _cage.is_open_wide():
				_say_once("sorry", "Your papers are in order. My apologies - you're free to go back to your seat.")
				_rider.state = Passengers.State.UNDER_ESCORT
				phase = "out"
				_t = 0.0
		"out":
			_face(_cage.gate_middle(), delta)
			_t += delta
			if b._sit > 0.0 and _steps.is_empty():
				b.sit_target = 0.0
				var xf := _cage.place_xf(_place)
				b.global_position = xf.origin.lerp(_cage.inside_point(_place), 1.0 - b._sit)
				if b._sit <= 0.02:
					b.sit_height = 0.42
					_steps = [_cage.gateway_point(true), _cage.gateway_point(false), _cage.clear_point()]
				return
			if not _steps.is_empty():
				if _step_rider(delta):
					_steps.pop_front()
				return
			_cage.leave_place(_rider.pid)
			phase = "lock"
			_t = 0.0
		"lock":
			_face(_cage.gate_middle(), delta)
			_t += delta
			if _t > 6.0:
				_say_once("stand_back", "Stand clear of the gate, please.")
			if _cage.close_and_lock():
				var seat: Dictionary = _pax.seat_for_return(_rider)
				if seat.is_empty():
					# Nowhere to sit any more: it stays out of the cage, standing by the van door.
					_det.on_released(_rider)
					_pax.free_seat_of(_rider)
					_end_job()
					return
				_rider.mover = NpcMover.new(b, _nav, false)
				_rider.mover.speed = ESCORT_SPEED
				mover.trail = PackedVector3Array([b.global_position, mover.pos()])
				_rider.mover.follow(mover, 1.1)
				mover.speed = ESCORT_SPEED
				mover.go(_beside(_rider, true))
				phase = "lead"
		"lead":
			_rider.mover.update(delta)
			if mover.pos().distance_to(b.global_position) > 2.6:
				mike.walk_speed = 0.0
				return
			var st := mover.update(delta)
			if st in ["arrived", "failed"]:
				_rider.mover.release()
				_rider.mover = NpcMover.new(b, _nav, false)
				_rider.mover.speed = 0.7
				_rider.mover.go(_pax.seat_exit(_rider))
				phase = "seat"
		"seat":
			_face(b.global_position, delta)
			var st: String = _rider.mover.update(delta)
			if st in ["arrived", "failed"]:
				_steps = [_pax.seat_front(_rider)]
				phase = "sit"
		"sit":
			if not _steps.is_empty():
				if _step_rider(delta):
					_steps.pop_front()
				return
			if _pax._sit_step(_rider, delta):
				_rider.mover.release()
				_rider.mover = null
				_pax.returned_to_seat(_rider)
				_det.on_released(_rider)
				_note("released %s" % b.name)
				_end_job()

# ————— small things —————

func _face(p: Vector3, delta: float) -> void:
	var f := Vector3(p.x - mike.global_position.x, 0, p.z - mike.global_position.z)
	if f.length() > 0.05:
		mike.rotation.y = lerp_angle(mike.rotation.y, atan2(f.x, f.z), clampf(delta * 5.0, 0.0, 1.0))

func _say_once(key: String, text: String) -> void:
	if _said.has(key):
		return
	_said[key] = true
	mike.say(text)
