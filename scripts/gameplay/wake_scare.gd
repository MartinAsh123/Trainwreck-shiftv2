class_name WakeScare
extends Node
## Now and then (`chance` a day) one of the sleepers in the berths is not what it seems, and waking it
## is a mistake. Kevin shakes it (E, Passengers.wake_by_player): nothing for a breath; then it rolls
## over to face him in one jerk - an anomaly baring a mouthful of teeth (MonsterFace), or a ghost gone
## pale with its mouth stretched open - and the scream starts at full volume from the first frame; it
## stares, sits bolt upright at him with its hands coming up at his head, the car's lamps blink, and the
## berth is empty, its blanket thrown back. Nobody talks meanwhile, and nothing is on the screen. It
## costs nothing: it was never a passenger.
## Pacing: the one chosen rides to a stop late in the shift (`late_stops`, timetable indices), and
## Chores gives it a wake-up call like any other, so the scare comes when Kevin does his job, in the
## last third of the night; its order is cancelled when it springs. It always goes (he set it off)
## and counts as the night's peak (HorrorDirector.begin_big).

@export var chance := 0.35                 # a day
@export var late_stops := [4, 5]           # the stops it should ride to (RouteData.stops() indices), first choice first
@export var calm := 0.55                   # seconds of nothing after he shakes it
@export var roll := 0.12                   # seconds to roll over and face him
@export var stare := 0.45                  # seconds of the face, screaming
@export var rise := 0.14                   # seconds to sit bolt upright at him
@export var reach := 0.38                  # seconds its hands are at his head before the lamps blink
@export var dark := 0.2                    # seconds the lamps are out

const SCREAM := {"anomaly": "res://assets/audio/frenzy_scream_2.mp3", "ghost": "res://assets/audio/horror_scream.mp3"}

var rider                                  # the one in the berth (Passengers.Rider)
var kind := ""                             # anomaly | ghost
var sprung := false
var _pax: Passengers
var _hd: HorrorDirector
var _rng := RandomNumberGenerator.new()
var _t := -1.0
var _begun := false
var _face: MonsterFace
var _fade: GhostFade
var _lights: Array = []                    # [Light3D, energy]
var _switches: Array = []

static func of(n: Node) -> WakeScare:
	return n.get_tree().get_first_node_in_group("wake_scare") as WakeScare

func _ready() -> void:
	add_to_group("wake_scare")
	_rng.randomize()
	_setup.call_deferred()

func _setup() -> void:
	for i in 2:
		await get_tree().process_frame
	_pax = get_tree().root.find_child("Passengers", true, false) as Passengers
	_hd = HorrorDirector.of(self)
	if _pax == null or _rng.randf() >= chance:
		return
	var can: Array = _pax.riders().filter(func(r): return r.state == Passengers.State.SLEEPING and not r.body.has_meta("wake_call"))
	if can.is_empty():
		return
	# One riding to a stop late in the night, if there is one: its wake-up call falls there.
	var names: Array = RouteData.stops().map(func(s): return str(s.name))
	for i: int in late_stops:
		var late: Array = can.filter(func(r): return names.find(r.dest) == i)
		if not late.is_empty():
			can = late
			break
	pick(can[_rng.randi_range(0, can.size() - 1)], "anomaly" if _rng.randf() < 0.5 else "ghost")

## Makes `r` the one (tests choose it themselves).
func pick(r, k: String) -> void:
	rider = r
	kind = k
	r.body.set_meta("wake_scare", k)
	if k == "anomaly":
		MonsterFace.warm()

## Kevin has shaken it (Passengers.wake_by_player).
func spring(r) -> void:
	if sprung or r != rider:
		return
	sprung = true
	_begun = false
	_t = 0.0
	r.body.set_meta("scaring", true)
	if _hd:
		_hd.hold = true
		_hd.begin_big("wake scare", true)
	var ch := Chores.of(self)
	if ch:
		ch.sprung_call(r)
	_pax.hush = 8.0
	r.blanket.disturbed = maxf(r.blanket.disturbed, 0.25)

# Lying on its side in the berth's space, facing `s` (the wall is -side, the room +side).
func _lie(s: float) -> Transform3D:
	var head: float = rider.body._head_h - 0.1
	return Transform3D(Basis(Vector3(0, s, 0), Vector3(0, 0, 1), Vector3(s, 0, 0)),
			Vector3(-s * 0.03, SleepBlanket.MATTRESS + 0.17, 0.70 - head))

func _process(delta: float) -> void:
	if _t < 0.0 or rider == null:
		return
	_pax.hush = maxf(_pax.hush, 2.0)
	var b: TalkingCharacter = rider.body
	if not is_instance_valid(b):
		_t = -1.0
		return
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var t := _t - calm
	if t < 0.0 or cam == null:
		return
	if not _begun:
		_begun = true
		_begin(b, cam)
	var bed: Transform3D = rider.bed.global_transform
	var s: float = rider.side                    # (toward the compartment, where he stands)
	var shake := Vector3(sin(_t * 61.0), sin(_t * 47.0 + 1.0), 0) * 0.04
	if t < roll:
		# Over onto its other side in one jerk, to face him.
		var a := t / roll
		a = a * a * (3.0 - 2.0 * a)
		var from := _pax._lie_xf(rider)
		var to := _lie(s)
		b.global_transform = bed * Transform3D(from.basis.slerp(to.basis, a), from.origin.lerp(to.origin, a))
		b.lie_side = s
	elif t < roll + stare:
		# The face, the mouth wide, staring at him.
		b.global_transform = bed * _lie(s)
		b.head_twist = shake
	elif t < roll + stare + rise + reach:
		# Bolt upright on the berth's edge, at him, its hands coming up at his head.
		var u := clampf((t - roll - stare) / rise, 0.0, 1.0)
		var k := 1.0 - (1.0 - u) * (1.0 - u)
		var sit := _pax._sit_xf(rider)
		sit.origin.x += s * 0.12                 # (forward, toward him)
		b.global_transform = bed * _lie(s).interpolate_with(sit, k)
		b.lie = 1.0 - k
		b.lie_legs = 1.0 - k
		b.sit_height = lerpf(rider.lie_h, SleepBlanket.MATTRESS, k)
		b.sit_target = lerpf(0.5, 1.0, k)
		b._sit = b.sit_target
		var eye := cam.global_position
		var side := cam.global_basis.x
		b.grab = k
		b.grab_l = eye - cam.global_basis.z * 0.12 - side * 0.24 - Vector3(0, 0.1, 0)
		b.grab_r = eye - cam.global_basis.z * 0.12 + side * 0.24 - Vector3(0, 0.1, 0)
		b.head_twist = shake * 1.5
	elif t < roll + stare + rise + reach + dark:
		if b.visible:
			_set_lit(false)
			b.visible = false
	else:
		_end(b)

func _begin(b: TalkingCharacter, cam: Camera3D) -> void:
	b.asleep = false
	rider.blanket.lively = true
	rider.blanket.fold = 1.0
	rider.blanket.disturbed = 1.0
	if kind == "anomaly":
		_face = MonsterFace.attach(b, rider.base, "")
		if _face:
			_face.amount = 1.0
			_face.gape = 1.0
			_face.smile = 1.0
			_face.stare_at = cam
	else:
		_fade = GhostFade.appear(b)
		b.face_weights = {"viseme_D": 1.5, "lids_open_L": 1.3, "lids_open_R": 1.3, "surprised": 1.0}
	b.set_expression("angry" if kind == "anomaly" else "surprised", 1.0)
	var p := AudioStreamPlayer.new()
	p.stream = load(SCREAM[kind])
	p.volume_db = 2.0
	add_child(p)
	p.play(0.2 if kind == "ghost" else 0.05)
	p.finished.connect(p.queue_free)
	if _hd:
		_hd.trauma(0.55)
	_lights.clear()
	var car: Node3D = rider.car
	for l: Light3D in car.find_children("*", "Light3D", true, false):
		_lights.append([l, l.light_energy])
	_switches = car.find_children("*", "LightSwitch", true, false)
	TerminalData.log_line("Berth %s: the passenger is gone. The berth is empty." % str(rider.bed.get_meta("berth", "?")))

func _set_lit(on: bool) -> void:
	for e: Array in _lights:
		if is_instance_valid(e[0]):
			(e[0] as Light3D).light_energy = float(e[1]) if on else 0.0
	if on:
		for sw: Node in _switches:
			if is_instance_valid(sw):
				sw.call("_apply")

func _end(b: TalkingCharacter) -> void:
	_set_lit(true)
	_t = -1.0
	if _hd:
		_hd.hold = false
		_hd.end_big("wake scare")
	if rider.blanket:
		rider.blanket.lively = false
		rider.blanket.set_body(null)
	if _face:
		_face.detach()
	var r = rider
	rider = null
	_pax.vanish_rider(r)
