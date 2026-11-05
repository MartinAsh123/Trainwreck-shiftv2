class_name AnomalyFrenzy
extends Node3D
## Most anomalies, found out, sit tight and let the guard take them. Some do not. Each has one roll,
## `violent_chance`, the first time it counts: when the player first has something on it (anything in
## PassengerTalk.evidence: an odd answer, a ticket that cannot be) or the guard comes for it. Of the
## violent ones, `wait_for_guard` keep quiet till his hand is on them; the rest go at once.
## Then, while the train runs, one at a time:
##   tell    the talk breaks off, it stares, the smile widens past where a smile stops, the lamps stutter
##   hunt    (the player farther off than LUNGE_FROM: it has shrieked and comes for him on all fours,
##           belly up, doors flung open before it, through the cars if need be)
##   lunge   full in his face, a shriek: his eye is ours from here on (MonsterFace, TalkingCharacter.grab)
##   hold    a blink of stopped time, then its hands on him and that face against his, closer, the head
##           snapping from angle to angle, the eyes darting over him, the tunnel closing in
##   drop    a second shriek, it throws him back and flips over onto its hands and feet
##   flee    away feet first and staring at him, in bursts, very fast, leaving ashen hand prints, doors
##           flung open on the way; the player's eye follows it (he has his body back when it is gone
##           or after FLEE_HOLD)
##   leap    the outside door flung open on the moving train (TrainDoor.force), snow blowing in, and
##           out; it falls away along the side of the train
##   after   the doors shut, the guard back at his work, the record written. It is off the train: not
##           caught and not left at large, so no score either way.
## The people about it shrink back, freeze, and jump out of its way (FrenzyPanic).
## Ghosts are not anomalies: they are left alone. It works from outside the others: Passengers'
## escort state keeps the rider out of their routine, MikeDuty is held in a phase of its own.
## Tests and story beats: trigger(rider, "exposed" | "arrest").
## Pacing: an exposed one found out naturally waits, armed and sitting tight, for the night's peak
## (HorrorDirector.big_ready) before it goes - whenever the player is next close to it. One the guard
## has his hand on, or a forced one, goes at once. Either is the night's big scare while it lasts.

signal finished(pid: int)

@export var enabled := true
@export var violent_chance := 0.18        # of any anomaly, its one roll
@export var wait_for_guard := 0.5         # of the violent ones, those that keep quiet till he comes
@export var crawl_speed := 6.5            # m/s, to the door
@export var hunt_speed := 7.5             # m/s, after the player
@export var hunt_seconds := 16.0          # gives up and makes for a door after this long

const FREE := [Passengers.State.SEATED, Passengers.State.ERRAND, Passengers.State.PREPARING]
const LUNGE_FROM := 3.2                   # nearer than this it lunges; farther, it hunts him down
const GRAB_AT := 1.9                      # a hunt ends in a lunge this near
const TELL := 1.25
const LUNGE := 0.16
const HOLD := 1.55
const DROP := 0.42
const FLEE_HOLD := 3.4                    # his eye follows it this long at most
const FACE_FAR := 0.24                    # its face from his eye as it lands, and at its closest
const FACE_NEAR := 0.155
const DOOR_NEAR := 2.3                    # doors go open at this distance
const FLOOR_Y := 1.4
const CRIES := ["God in heaven!", "What is that? What IS that?", "Holy Mother...", "Get it away! Get it away from me!"]

const S_SCREAM := ["res://assets/audio/frenzy_scream_1.mp3", "res://assets/audio/frenzy_scream_2.mp3"]
const S_INHALE := ["res://assets/audio/frenzy_inhale_1.mp3", "res://assets/audio/frenzy_inhale_2.mp3"]
const S_SCRABBLE := ["res://assets/audio/frenzy_scrabble_1.mp3", "res://assets/audio/frenzy_scrabble_2.mp3"]
const S_DOOR := ["res://assets/audio/frenzy_door_1.mp3", "res://assets/audio/frenzy_door_2.mp3"]
const SCREEN := preload("res://shaders/ui/frenzy_screen.gdshader")
const PRINT := preload("res://assets/textures/frenzy/hand_print.png")
const CLAWS := preload("res://assets/textures/frenzy/claw_marks.png")
const STOP := 0.09                        # the instant its hands land, time stands still for it
const FOV_TELL := 52.0                    # his eye drawn in to that face, as it starts to smile
const FOV_WIDE := 92.0                    # ... as it lands
const FOV_NEAR := 74.0                    # ... and as that face comes in
const PRINT_EVERY := 0.6                  # m crawled to a hand print
const PRINTS_LAST := 170.0                # seconds
# What the screen does at each turn (frenzy_screen.gdshader), and how fast it gets there.
const FX_TELL := {"warp": 0.14, "fringe": 0.14, "soft": 0.25, "tunnel": 0.3, "vessels": 0.14, "drain": 0.34, "grain": 0.05}
const FX_HUNT := {"fringe": 0.25, "tunnel": 0.25, "vessels": 0.25, "drain": 0.36, "grain": 0.06, "tear": 0.12}
const FX_LUNGE := {"warp": 1.0, "fringe": 1.0, "soft": 0.7, "tunnel": 0.6, "vessels": 0.6, "drain": 0.6, "grain": 0.08, "tear": 0.4}
const FX_HOLD := {"warp": 0.72, "fringe": 0.42, "soft": 0.32, "tunnel": 0.8, "vessels": 1.0, "drain": 0.72, "grain": 0.09, "tear": 0.05}
const FX_DROP := {"warp": 0.5, "fringe": 1.0, "soft": 0.5, "tunnel": 0.5, "vessels": 0.7, "drain": 0.6, "grain": 0.08, "tear": 0.6}
const FX_FLEE := {"fringe": 0.3, "soft": 0.2, "tunnel": 0.36, "vessels": 0.36, "drain": 0.42, "grain": 0.06, "tear": 0.07}

var stage := ""                           # "" | armed | tell | hunt | lunge | hold | drop | flee | leap | after
var variant := ""                         # exposed | arrest
var log_lines: Array[String] = []         # (for tests) what happened, in order

var _r                                    # the rider
var _fate := {}                           # pid -> "exposed" | "arrest" | "": its one roll, spent or not
var _rng := RandomNumberGenerator.new()
var _ts: Node
var _pax: Passengers
var _player: CharacterBody3D
var _monster: MonsterFace
var _t := 0.0
var _poll := 0.0
var _quiet := 0.0
# his eye
var _held := false
var _eye := Vector3.ZERO
var _look := Quaternion.IDENTITY
var _shake := 0.0
var _kick := 0.0
var _time := 0.0
# the body
var _dir := Vector3.FORWARD               # from his eye to it, level
var _face_c := Vector3(0, 1.5, 0.08)      # the middle of its face, in the model's space
var _roll_sign := 1.0
var _by_trigger := false                 # set off by trigger(): no waiting for the night's peak
var _big_on := false                      # it is the night's big scare (HorrorDirector)
var _from := Vector3.ZERO
var _from_b := Basis.IDENTITY
var _spot := Vector3.ZERO
var _yaw := 0.0
var _v := Vector3.ZERO
# the way
var _path := PackedVector3Array()
var _i := 0
var _doors: Array = []
var _forced: Array = []                   # doors it flung open, shut again afterwards
var _exit: TrainDoor
var _exit_side := 1.0
var _exit_open := false
var _replan := 0.0
var _exits: Array = []
var _scrabble: AudioStreamPlayer3D
# the screen
var _ui: CanvasLayer
var _warm_fx: ShaderMaterial              # (held so its shader is compiled ahead of need)
var _fx: ShaderMaterial
var _fx_now := {}
var _fx_to := {}
var _fx_rate := 3.0
var _flash_a := 0.0
var _beat_t := 0.0
var _heart := 2.0                         # beats a second
var _fov0 := 75.0
var _fov_to := 75.0
var _lamps: Array[OmniLight3D] = []
# the choreography
var _stop := 0.0
var _snap_t := 0.0
var _twist_to := Vector3.ZERO
var _burst := 0.0
var _pause := 0.0
var _walked := 0.0
var _print_side := 1.0
var _wind: Array[Node3D] = []
var _panic: FrenzyPanic

static func of(n: Node) -> AnomalyFrenzy:
	return n.get_tree().get_first_node_in_group("anomaly_frenzy") as AnomalyFrenzy

func _ready() -> void:
	add_to_group("anomaly_frenzy")
	_rng.randomize()
	_ts = get_node_or_null("/root/TrainState")
	MonsterFace.warm()
	_warm_fx = ShaderMaterial.new()
	_warm_fx.shader = SCREEN
	_panic = FrenzyPanic.new()
	_panic.name = "Panic"
	_panic.frenzy = self
	add_child(_panic)

func _exit_tree() -> void:
	_free_player()

## Sets it off now (tests, story beats): `how` is "exposed" or "arrest".
func trigger(r, how := "exposed") -> bool:
	if stage != "" or r == null or r.ghost or r.state == Passengers.State.VANISHING:
		return false
	_arm(r, how)
	_by_trigger = true
	return true

# ————— who, and when —————

func _pax_() -> Passengers:
	if _pax == null:
		_pax = get_tree().root.find_child("Passengers", true, false) as Passengers
	return _pax

func _player_() -> CharacterBody3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().root.find_child("Player", true, false) as CharacterBody3D
	return _player

func _moving() -> bool:
	return _ts != null and str(_ts.get("phase")) in ["running", "braking"] and float(_ts.get("speed")) > 4.0

func _note(s: String) -> void:
	log_lines.append("%s %s" % [TerminalData.clock_text(), s])

func _watch() -> void:
	var pax := _pax_()
	if pax == null:
		return
	var duty := MikeDuty.of(self)
	for r in pax.riders():
		if r.anomaly == "" or r.ghost or not (r.state in FREE):
			continue
		if duty and duty.job == "escort" and duty.phase == "to_suspect" and duty._rider == r \
				and duty.mike.global_position.distance_to(r.body.global_position) < 2.6:
			if _moving() and _fate_of(r.pid) != "":
				_fate[r.pid] = ""
				_arm(r, "arrest")
				return
			continue
		var t := PassengerTalk.of(r.body)
		if t != null and not t.evidence().is_empty() and _fate_of(r.pid) == "exposed":
			_fate[r.pid] = ""
			_arm(r, "exposed")
			return

# Its one roll, the first time it counts.
func _fate_of(pid: int) -> String:
	if not _fate.has(pid):
		var violent := _rng.randf() < violent_chance
		_fate[pid] = ("arrest" if _rng.randf() < wait_for_guard else "exposed") if violent else ""
	return _fate[pid]

func _arm(r, how: String) -> void:
	_r = r
	variant = how
	_by_trigger = false
	_set_stage("armed")
	_quiet = 0.0
	# (built now, while nothing is happening: it takes a moment)
	_monster = MonsterFace.attach(r.body, r.base, r.anomaly)
	_make_ui()
	if how == "arrest":
		_hold_mike()
		var duty := MikeDuty.of(self)
		if duty and not duty.mike.is_speaking():
			duty.mike.say("Come with me, please. Just a few-", 1.3)

func _set_stage(s: String) -> void:
	stage = s
	_t = 0.0
	_note(s)

# Waiting for its moment: the answer finished, the train moving, the player near enough.
func _armed(delta: float) -> void:
	var b: TalkingCharacter = _r.body
	if not (_r.state in FREE):
		_monster.detach()
		_reset()
		return
	if not _moving():
		return
	var d := _player_().global_position.distance_to(b.global_position)
	if variant == "arrest":
		if _t > 0.5:
			_set_off(d)
		return
	if _t < 1.1 or b.is_speaking():
		_quiet = 0.0
		return
	_quiet += delta
	if _quiet > 0.75 and d < 4.5:
		var hd := HorrorDirector.of(self)
		if _by_trigger or hd == null or hd.big_ready("frenzy"):
			_set_off(d)

func _set_off(d: float) -> void:
	var hd := HorrorDirector.of(self)
	if hd and hd.big == "":
		hd.begin_big("frenzy", variant == "arrest" or _by_trigger)
		_big_on = true
	_begin()
	if d < LUNGE_FROM:
		_grab_player()
		_set_stage("tell")
		_play2d(S_INHALE, -3.0)
		_r.body.look_at_target = _player._cam
		_monster.stare_at = _player._cam
		_fx_set(FX_TELL, 0.6)
		_fov_to = FOV_TELL
		_flicker()
	else:
		var b: TalkingCharacter = _r.body
		b.sit_target = 0.0
		b._sit = 0.0
		b.sit_height = 0.42
		b.global_rotation = Vector3(0, b.global_rotation.y, 0)
		b.crawl_back = false
		_monster.amount = 1.0
		_monster.gape = 0.8
		_monster.stare_at = _player_()._cam
		_play3d(S_SCREAM, b.global_position + Vector3(0, 1.0, 0), 9.0, 90.0, 0.0)
		_scrabble = _loop3d(S_SCRABBLE, b)
		_fx_set(FX_HUNT, 1.2)
		_heart = 2.6
		_flicker()
		_replan = 0.0
		_panic.threat = b
		_set_stage("hunt")

# Out of everyone's hands: the talk over, off the report, a thing of ours from here.
func _begin() -> void:
	var r = _r
	var b: TalkingCharacter = r.body
	var rec := ShiftRecord.of(self)
	if rec:
		rec.entry_for(r)                       # (made while it can still say who it was)
	var t := PassengerTalk.of(b)
	if t:
		t._end()
		t.queue_free()
	_pax_().take_for_escort(r)
	_hold_mike()
	b.solid = false
	b.look_range = 0.0
	b.look_at_target = null
	_face_c = Vector3(0, 1.5, 0.08)
	var f: Dictionary = FaceMarks.MARKS.get(r.base, {})
	if not f.is_empty():
		var e0 := MonsterFace._v(f.eyes[0])
		var e1 := MonsterFace._v(f.eyes[1])
		_face_c = ((e0 + e1) * 0.5).lerp(MonsterFace._v(f.mouth), 0.72)     # (the dropped jaw in the picture too)
		if r.anomaly == "long_neck":
			_face_c.y += MonsterFace.LONG_NECK
	_roll_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_hush()

# Nobody passes the time of day through this.
func _hush() -> void:
	_pax_()._chat_t = maxf(_pax_()._chat_t, 30.0)

# The guard stands where he is: a phase of his escort's own that does nothing.
func _hold_mike() -> void:
	var det := Detention.of(self)
	if det and det.pending_pid == _r.pid:
		det.pending_pid = -1
	var duty := MikeDuty.of(self)
	if duty and duty.job == "escort" and duty._rider == _r and duty.mover and duty.phase != "frenzy":
		duty.mover.stop()
		duty.phase = "frenzy"

func _mike_near(d := 14.0) -> TalkingCharacter:
	var duty := MikeDuty.of(self)
	if duty and duty.mike and duty.mike.global_position.distance_to(_player_().global_position) < d:
		return duty.mike
	return null

# ————— his eye —————

func _grab_player() -> void:
	var p := _player_()
	var menu := get_tree().root.get_node_or_null("DialogueMenu") as DialogueMenu
	if menu and menu.visible:
		menu.close()
	if p.is_focused() and p._focus != self and p._focus.has_method("release"):
		p._focus.call("release")               # (off a terminal)
	var cam: Camera3D = p._cam
	_eye = cam.global_position
	_look = cam.global_basis.get_rotation_quaternion()
	_fov0 = cam.fov
	_fov_to = cam.fov
	p.focus_on(self, cam.global_transform)
	if p._focus_tween:
		p._focus_tween.kill()
	p._focus_settled = true
	_held = true

func _free_player() -> void:
	if not _held or _player == null or not is_instance_valid(_player):
		return
	_held = false
	_player._cam.fov = _fov0
	_lights(0.0)
	# He goes on looking where he was made to look.
	var f := Basis(_look) * Vector3.FORWARD
	_player.rotation.y = atan2(-f.x, -f.z)
	_player._head.rotation.x = clampf(asin(clampf(f.y, -1.0, 1.0)), -1.4, 1.4)
	_player.release_focus()

func _aim(at: Vector3, rate: float, delta: float) -> void:
	var v := at - _eye
	if v.length() < 0.05 or absf(v.normalized().y) > 0.98:
		return
	_look = _look.slerp(Basis.looking_at(v, Vector3.UP).get_rotation_quaternion(), clampf(rate * delta, 0.0, 1.0))

func _view(delta: float) -> void:
	if not _held:
		return
	_time += delta
	_shake = move_toward(_shake, 0.0, delta * 0.55)
	_kick = move_toward(_kick, 0.0, delta * 1.5)
	var cam: Camera3D = _player._cam
	cam.fov = lerpf(cam.fov, _fov_to, 1.0 - exp(-(1.7 if stage == "tell" else 11.0) * delta))
	var s := _shake * _shake
	var j := Vector3(sin(_time * 71.0) + sin(_time * 113.0), sin(_time * 89.0) + sin(_time * 131.0), sin(_time * 97.0))
	var b := Basis(_look) * Basis(Vector3.RIGHT, 0.34 * _kick + j.x * 0.012 * s) * Basis(Vector3.UP, j.y * 0.012 * s) \
			* Basis(Vector3.BACK, _roll_sign * 0.26 * _kick + j.z * 0.02 * s)
	var xf := Transform3D(b, _eye + Basis(_look) * Vector3(j.y * 0.003 * s, j.x * 0.003 * s, 0.14 * _kick))
	_player._focus_view = xf
	_player._cam.global_transform = xf

# ————— at him —————

func _head_pos(b: TalkingCharacter) -> Vector3:
	if b._skel and b._bones.has("Head"):
		return b._skel.global_transform * b._skel.get_bone_global_pose(b._bones["Head"]).origin
	return b.global_position + Vector3(0, 1.5, 0)

func _tell(delta: float) -> void:
	var b: TalkingCharacter = _r.body
	var long := 0.8 if variant == "arrest" else TELL
	var k := smoothstep(0.0, long, _t)
	_monster.amount = 0.6 * k
	_monster.smile = smoothstep(0.1, 0.85, k)          # (wider, and wider)
	_monster.pupil = lerpf(0.2, 0.07, k)
	b.head_twist = Vector3(0, 0, _roll_sign * 0.34 * smoothstep(0.25, 1.0, k))
	_heart = lerpf(1.6, 3.2, k)
	_aim(_head_pos(b), 7.0, delta)
	_view(delta)
	if _t >= long:
		_to_lunge()

func _to_lunge() -> void:
	var b: TalkingCharacter = _r.body
	_set_stage("lunge")
	_play2d(S_SCREAM, 0.0, 0)
	b.sit_target = 0.0
	b._sit = 0.0
	b.sit_height = 0.42
	b.crawl = 0.0
	b.walk_speed = 0.0
	b.look_at_target = null
	b._head_yaw = 0.0                       # (square to him, whatever it was looking at)
	b._head_pitch = 0.0
	b.head_twist = Vector3.ZERO
	b.global_rotation = Vector3(0, b.global_rotation.y, 0)
	_monster.amount = 1.0
	_monster.smile = 0.0
	_monster.stare_at = _player_()._cam
	_monster.pupil = 0.08
	_from = b.global_position
	_dir = _head_pos(b) - _eye
	_dir.y = 0.0
	_dir = _dir.normalized() if _dir.length() > 0.05 else Basis(_look) * Vector3.FORWARD
	_dir.y = 0.0
	_dir = _dir.normalized()
	_fx_set(FX_LUNGE, 14.0)
	_fov_to = FOV_WIDE
	_heart = 4.0
	_lights(1.0)
	_panic.threat = b
	if _scrabble:
		_scrabble.queue_free()
		_scrabble = null
	var m := _mike_near()
	if m:
		m.say("Hey! HEY!", 1.2)

# Its face `dist` from his eye (turned `roll` about its own middle), its hands on his shoulders.
func _press(dist: float, roll: float, jitter: float) -> void:
	var b: TalkingCharacter = _r.body
	var basis := Basis(Vector3.UP, atan2(-_dir.x, -_dir.z)) * Basis(Vector3.BACK, roll)
	b.global_basis = basis
	var j := Vector3(sin(_time * 83.0), sin(_time * 61.0), sin(_time * 107.0)) * jitter
	b.global_position = _eye + _dir * dist + Vector3(0, -0.022, 0) + j - basis * _face_c
	var r := Basis(_look)
	b.grab_l = _eye + r * Vector3(0.255, -0.1, -0.235)       # (at the sides of his head, the fingers in the picture)
	b.grab_r = _eye + r * Vector3(-0.255, -0.1, -0.235)

func _lunge(delta: float) -> void:
	var b: TalkingCharacter = _r.body
	var k := clampf(_t / LUNGE, 0.0, 1.0)
	k *= k
	_aim(_eye + _dir + Vector3(0, -0.02, 0), 26.0, delta)
	_press(FACE_FAR, 0.0, 0.0)
	b.global_position = _from.lerp(b.global_position, k)
	b.grab = k
	_monster.gape = clampf(_t / (LUNGE * 0.7), 0.0, 1.0)
	_view(delta)
	if _t >= LUNGE:
		_set_stage("hold")
		_stop = STOP
		_flash_a = 0.5
		_shake = 1.0
		_kick = 0.45
		_fx_set(FX_HOLD, 2.6)
		_fov_to = FOV_NEAR
		_snap_t = 0.0

func _hold(delta: float) -> void:
	var k := clampf(_t / HOLD, 0.0, 1.0)
	var b: TalkingCharacter = _r.body
	var tremble := sin(_t * 64.0) * 0.016
	# The head wrenched from one angle to the next, as if it were looking for the way in.
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = _rng.randf_range(0.17, 0.4)
		_twist_to = Vector3(_rng.randf_range(-0.1, 0.12), _rng.randf_range(-0.16, 0.16), _rng.randf_range(-0.34, 0.34))
		_monster.pupil = _rng.randf_range(0.06, 0.1)
		_tear_kick(0.36)
	b.head_twist = b.head_twist.lerp(_twist_to, clampf(delta * 40.0, 0.0, 1.0))
	_press(lerpf(FACE_FAR, FACE_NEAR, smoothstep(0.0, 0.55, k)), _roll_sign * (0.3 * smoothstep(0.05, 0.9, k)) + tremble, 0.0032)
	_aim(_eye + _dir + Vector3(0, -0.02, 0), 26.0, delta)
	_view(delta)
	if _t >= HOLD:
		_to_drop()

func _to_drop() -> void:
	var b: TalkingCharacter = _r.body
	_set_stage("drop")
	_play2d(S_SCREAM, 0.0, 1)
	_kick = 1.0
	_shake = 1.0
	_flash_a = 0.3
	_fx_set(FX_DROP, 14.0)
	_fov_to = _fov0
	_heart = 3.2
	_lights(0.35)
	b.head_twist = Vector3.ZERO
	var p := _player_().global_position
	if not _plan_exit(Vector3(p.x, FLOOR_Y, p.z)):
		_note("no way to a door")
		_vanish()
		return
	# Thrown off a stride along its way out.
	var left := 1.15
	_spot = _path[0]
	_i = 1
	while _i < _path.size():
		var seg := _spot.distance_to(_path[_i])
		if seg >= left:
			_spot = _spot.lerp(_path[_i], left / maxf(seg, 0.001))
			break
		left -= seg
		_spot = _path[_i]
		_i += 1
	var next: Vector3 = _path[mini(_i, _path.size() - 1)]
	var v := next - _spot
	# Away feet first: it does not take its eyes off him.
	_yaw = atan2(v.x, v.z) + PI if Vector2(v.x, v.z).length() > 0.05 else b.global_rotation.y
	b.crawl_back = true
	_mark(CLAWS, _spot, _yaw, 0.62)
	_from = b.global_position
	_from_b = b.global_basis.orthonormalized()
	_scrabble = _loop3d(S_SCRABBLE, b)
	if _r.car:
		_pax_().complain(_r.car, CRIES[_rng.randi_range(0, CRIES.size() - 1)])

func _drop(delta: float) -> void:
	var b: TalkingCharacter = _r.body
	var k := clampf(_t / DROP, 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, k)
	b.grab = 1.0 - smoothstep(0.0, 0.5, k)
	b.crawl = smoothstep(0.15, 0.85, k)
	b.global_basis = _from_b.slerp(Basis(Vector3.UP, _yaw), e)
	b.global_position = _from.lerp(_spot, e) + Vector3(0, sin(k * PI) * 0.16, 0)
	_aim(_head_pos(b), 11.0, delta)
	_view(delta)
	if k >= 1.0:
		b.grab = 0.0
		b.crawl = 1.0
		_fx_set(FX_FLEE, 2.0)
		_burst = _rng.randf_range(0.5, 0.8)
		_set_stage("flee")

# ————— the way out —————

func _exit_doors() -> Array:
	if _exits.is_empty():
		var train := get_tree().root.find_child("Train", true, false)
		for d: Node in train.find_children("*", "TrainDoor", true, false):
			if (d as TrainDoor).lock_while_moving:
				_exits.append(d)
	return _exits

# The outside door the shortest way from `from`; false if there is none to reach.
func _plan_exit(from: Vector3) -> bool:
	var nav := TrainNav.of(self)
	if nav == null:
		return false
	var best := INF
	_exit = null
	# (the nearest few as the crow flies: a search for each is the one slow thing here)
	var near := _exit_doors().duplicate()
	near.sort_custom(func(a: Node3D, b: Node3D): return from.distance_squared_to(a.global_position) < from.distance_squared_to(b.global_position))
	var tried := 0
	for d: TrainDoor in near:
		if tried >= 3:
			break
		var mouth := (d.get_parent() as Node3D).global_position
		var side := signf(d.global_position.z)
		var p := nav.path(from, Vector3(mouth.x, FLOOR_Y, side * 0.95), false)
		if p.size() < 2:
			continue
		tried += 1
		var l := 0.0
		for k in p.size() - 1:
			l += p[k].distance_to(p[k + 1])
		if l < best:
			best = l
			_exit = d
			_exit_side = side
			_path = p
	if _exit == null:
		return false
	_doors = nav.doors_on(_path)
	_exit_open = false
	_i = 1
	return true

## Its way ahead while it is running (FrenzyPanic): from where it is, `reach` metres along its path;
## empty while it is not on its way anywhere.
func way_ahead(reach: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _r == null or not (stage in ["hunt", "drop", "flee"]) or _path.is_empty():
		return out
	var at: Vector3 = _r.body.global_position
	out.append(Vector3(at.x, FLOOR_Y, at.z))
	var left := reach
	var k := _i
	while k < _path.size() and left > 0.0:
		left -= out[out.size() - 1].distance_to(_path[k])
		out.append(_path[k])
		k += 1
	return out

func _follow(speed: float, delta: float) -> bool:
	var b: TalkingCharacter = _r.body
	var left := speed * delta
	var at := b.global_position
	var dir := Vector3.ZERO
	while left > 0.0 and _i < _path.size():
		var v := _path[_i] - at
		v.y = 0.0
		var l := v.length()
		if l > 0.02:
			dir = v / l
		if l <= left:
			at = Vector3(_path[_i].x, at.y, _path[_i].z)
			left -= l
			_i += 1
		else:
			at += dir * left
			left = 0.0
	at.y = move_toward(at.y, FLOOR_Y, delta * 2.0)
	_walked += b.global_position.distance_to(at)
	b.global_position = at
	if dir != Vector3.ZERO:
		var yaw := atan2(dir.x, dir.z) + (PI if b.crawl_back else 0.0)
		b.rotation.y = lerp_angle(b.rotation.y, yaw, clampf(delta * 16.0, 0.0, 1.0))
		if _walked >= PRINT_EVERY:
			_walked = 0.0
			_print_side = -_print_side
			var aside := Vector3(dir.z, 0, -dir.x) * _print_side * 0.3
			_mark(PRINT, at + aside + dir * 0.2, atan2(dir.x, dir.z) + _rng.randf_range(-0.5, 0.5) + _print_side * 0.5, 0.28)
	b.walk_speed = speed
	return _i >= _path.size()

# Something of it stays on the floor of the train for a while: a Decal, in the train's own frame.
func _mark(tex: Texture2D, at: Vector3, yaw: float, size: float) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(size, 0.24, size)
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	add_child(d)
	d.global_position = Vector3(at.x, FLOOR_Y + 0.02, at.z)
	d.rotation.y = yaw
	var tw := d.create_tween()
	tw.tween_interval(PRINTS_LAST)
	tw.tween_property(d, "albedo_mix", 0.0, 12.0)
	tw.tween_callback(d.queue_free)

func _fling_doors() -> void:
	var at: Vector3 = _r.body.global_position
	for e: Array in _doors:
		var d: TrainDoor = e[1]
		if not is_instance_valid(d) or _forced.has(d) or d.is_open():
			continue
		var p := (d.get_parent() as Node3D).global_position
		if Vector2(p.x - at.x, p.z - at.z).length() < DOOR_NEAR:
			d.force(true, 0.16)
			_forced.append(d)

func _flee(delta: float) -> void:
	var b: TalkingCharacter = _r.body
	# In bursts: a dart, a dead stop and a look at him, a dart.
	var speed := crawl_speed * 1.22
	_burst -= delta
	if _pause > 0.0:
		_pause -= delta
		speed = 0.0
		if _pause <= 0.0:
			_burst = _rng.randf_range(0.5, 0.85)
	elif _burst <= 0.0:
		_pause = _rng.randf_range(0.11, 0.19)
		_tear_kick(0.4)
	var done := _follow(speed, delta)
	_fling_doors()
	if _held:
		_aim(_head_pos(b), 9.0, delta)
		_view(delta)
		if _t > FLEE_HOLD:
			_free_player()
	var mouth := (_exit.get_parent() as Node3D).global_position
	if not _exit_open and Vector2(mouth.x - b.global_position.x, mouth.z - b.global_position.z).length() < DOOR_NEAR:
		_exit_open = true
		_exit.force(true, 0.14)
		_forced.append(_exit)
		_play3d(S_DOOR, mouth + Vector3(0, 1.0, 0), 6.0, 60.0, 2.0)
		_door_wind(mouth)
		_note("door flung open")
	if done:
		b.crawl_back = false
		b.rotation.y = atan2(0.0, _exit_side)
		_v = Vector3(0, 5.2, _exit_side * 3.4)
		if _scrabble:
			_scrabble.queue_free()
			_scrabble = null
		_set_stage("leap")

func _leap(delta: float) -> void:
	var b: TalkingCharacter = _r.body
	var speed := float(_ts.get("speed")) if _ts else 20.0
	_v.y -= 9.8 * delta
	if absf(b.global_position.z) > 1.9:
		_v.x = move_toward(_v.x, speed, 16.0 * delta)
	b.global_position += _v * delta
	b.rotate_object_local(Vector3.RIGHT, 8.0 * delta)
	if _held:
		_aim(_head_pos(b), 9.0, delta)
		_view(delta)
		if _t > 1.15:
			_free_player()
	if _t > 1.9 or b.global_position.y < -0.4:
		_vanish()

# ————— hunting him down —————

func _hunt(delta: float) -> void:
	var b: TalkingCharacter = _r.body
	b.crawl = move_toward(b.crawl, 1.0, delta * 4.0)
	var nav := TrainNav.of(self)
	var p := _player_()
	_replan -= delta
	if _replan <= 0.0 and nav:
		_replan = 0.4
		var way := nav.path(b.global_position, Vector3(p.global_position.x, FLOOR_Y, p.global_position.z), false)
		if way.size() >= 2:
			_path = way
			_i = 1
			_doors = nav.doors_on(way)
		elif _path.is_empty():
			_t = hunt_seconds
	if not _path.is_empty():
		_follow(hunt_speed, delta)
		_fling_doors()
	if b.global_position.distance_to(p.global_position) < GRAB_AT:
		_grab_player()
		_look = Basis.looking_at(b.global_position + Vector3(0, 0.4, 0) - _eye, Vector3.UP).get_rotation_quaternion().slerp(_look, 0.5)
		_to_lunge()
	elif _t > hunt_seconds:
		_note("gave up the hunt")
		if _plan_exit(b.global_position):
			_set_stage("flee")
		else:
			_vanish()

# ————— afterwards —————

func _vanish() -> void:
	var r = _r
	var b: TalkingCharacter = r.body
	b.visible = false
	_panic.threat = null
	var m := _mike_near()
	if m:
		m.say("It's gone. Out of the door, at this speed... Are you hurt, Kevin?")
	var rec := ShiftRecord.of(self)
	if rec:
		rec.anomaly_fled(r)
	var det := Detention.of(self)
	var duty := MikeDuty.of(self)
	if duty and duty.job == "escort" and duty.phase == "frenzy":
		duty._note("the reported passenger jumped")
		duty._end_job()
	if det and det.active_pid == r.pid:
		det.active_pid = -1
	var pid: int = r.pid
	_free_player()
	_pax_()._drop(r)
	_r = null
	_fx_set({}, 1.1)
	_heart = 1.6
	_set_stage("after")
	finished.emit(pid)

func _after(_delta: float) -> void:
	if _t > 2.6:
		for d in _forced:
			if is_instance_valid(d):
				(d as TrainDoor).request(false)
		_forced.clear()
		for n in _wind:
			if is_instance_valid(n):
				n.queue_free()
		_wind.clear()
		_reset()

func _reset() -> void:
	if _big_on:
		_big_on = false
		var hd := HorrorDirector.of(self)
		if hd:
			hd.end_big("frenzy")
	_free_player()
	_panic.threat = null
	if _ui:
		_ui.queue_free()
	_ui = null
	_fx = null
	_fx_now.clear()
	_fx_to = {}
	_flash_a = 0.0
	if _scrabble:
		_scrabble.queue_free()
	_scrabble = null
	_r = null
	_monster = null
	_path = PackedVector3Array()
	_doors = []
	_exit = null
	stage = ""
	variant = ""

func _process(delta: float) -> void:
	if stage == "":
		_poll -= delta
		if enabled and _poll <= 0.0:
			_poll = 0.25
			_watch()
		return
	if stage != "after" and (_r == null or not is_instance_valid(_r.body)):
		_reset()
		return
	if _stop > 0.0:
		_stop -= delta
		_screen(delta)
		return
	_t += delta
	match stage:
		"armed":
			_armed(delta)
		"tell":
			_tell(delta)
		"hunt":
			_hunt(delta)
		"lunge":
			_lunge(delta)
		"hold":
			_hold(delta)
		"drop":
			_drop(delta)
		"flee":
			_flee(delta)
		"leap":
			_leap(delta)
		"after":
			_after(delta)
	_screen(delta)
	if _r != null:
		var duty := MikeDuty.of(self)
		if duty and duty.job == "escort" and duty.phase == "frenzy" and is_instance_valid(_r.body):
			duty._face(_r.body.global_position, delta)

# ————— lamps, sound, the screen —————

func _flicker() -> void:
	var h := HorrorDirector.of(self)
	if h and h.active == "":
		h.trigger("flicker", _r.body.global_position)

func _clip(paths: Array, which := -1) -> AudioStream:
	var p: String = paths[which if which >= 0 else _rng.randi_range(0, paths.size() - 1)]
	return load(p) as AudioStream if ResourceLoader.exists(p) else null

func _play2d(paths: Array, db: float, which := -1) -> void:
	var s := _clip(paths, which)
	if s == null:
		return
	var a := AudioStreamPlayer.new()
	a.stream = s
	a.volume_db = db
	add_child(a)
	a.finished.connect(a.queue_free)
	a.play()

func _play3d(paths: Array, at: Vector3, unit: float, reach: float, db: float) -> void:
	var s := _clip(paths)
	if s == null:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = s
	a.unit_size = unit
	a.max_distance = reach
	a.volume_db = db
	add_child(a)
	a.global_position = at
	a.finished.connect(a.queue_free)
	a.play()

func _loop3d(paths: Array, on: Node3D) -> AudioStreamPlayer3D:
	var s := _clip(paths)
	if s == null:
		return null
	if "loop" in s:
		s.set("loop", true)
	var a := AudioStreamPlayer3D.new()
	a.stream = s
	a.unit_size = 6.0
	a.max_distance = 45.0
	a.volume_db = 10.0
	a.position.y = 0.3
	on.add_child(a)
	a.play()
	return a

func _make_ui() -> void:
	if _ui:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 40
	add_child(_ui)
	var r := ColorRect.new()
	_fx = ShaderMaterial.new()
	_fx.shader = SCREEN
	r.material = _fx
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(r)

func _fx_set(to: Dictionary, rate: float) -> void:
	_fx_to = to
	_fx_rate = rate

# A jolt of the tearing, on the moment something snaps.
func _tear_kick(a: float) -> void:
	_fx_now["tear"] = maxf(float(_fx_now.get("tear", 0.0)), a)

func _screen(delta: float) -> void:
	if _ui == null:
		return
	for k: String in ["warp", "fringe", "soft", "tear", "tunnel", "vessels", "drain", "grain"]:
		var v := move_toward(float(_fx_now.get(k, 0.0)), float(_fx_to.get(k, 0.0)), delta * _fx_rate)
		_fx_now[k] = v
		_fx.set_shader_parameter(k, v)
	_flash_a = move_toward(_flash_a, 0.0, delta * 6.5)
	_fx.set_shader_parameter("flash", _flash_a)
	_beat_t = fposmod(_beat_t + delta * _heart, 1.0)
	_fx.set_shader_parameter("beat", maxf(exp(-_beat_t * 9.0), 0.7 * exp(-absf(_beat_t - 0.22) * 14.0)))

# The light that thing is seen by, from under it, on his own head: `a` 0 is none.
func _lights(a: float) -> void:
	if a <= 0.0:
		for l in _lamps:
			if is_instance_valid(l):
				l.queue_free()
		_lamps.clear()
		return
	var cam: Camera3D = _player_()._cam
	if _lamps.is_empty():
		for e: Array in [[Vector3(0.03, -0.3, -0.1), Color(1.0, 0.5, 0.36), 0.075], [Vector3(-0.26, 0.22, -0.08), Color(0.62, 0.74, 1.0), 0.1]]:
			var l := OmniLight3D.new()
			l.position = e[0]
			l.light_color = e[1]
			l.light_energy = e[2]
			l.set_meta("energy", e[2])
			l.omni_range = 1.5
			l.omni_attenuation = 1.4
			l.light_specular = 1.2
			cam.add_child(l)
			_lamps.append(l)
	for l in _lamps:
		l.light_energy = float(l.get_meta("energy")) * a

# The moving night comes in by the open door: snow on the wind, and its cold light.
func _door_wind(mouth: Vector3) -> void:
	var at := mouth + Vector3(0, 1.05, _exit_side * 0.7)
	var p := CPUParticles3D.new()
	p.amount = 110
	p.lifetime = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.45, 0.8, 0.1)
	p.direction = Vector3(0.25, 0.05, -_exit_side)
	p.spread = 24.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0, -1.2, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	var flake := StandardMaterial3D.new()
	flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake.albedo_color = Color(0.86, 0.9, 1.0, 0.75)
	q.material = flake
	p.mesh = q
	add_child(p)
	p.global_position = at
	_wind.append(p)
	var cold := OmniLight3D.new()
	cold.light_color = Color(0.55, 0.7, 1.0)
	cold.light_energy = 2.2
	cold.omni_range = 7.0
	add_child(cold)
	cold.global_position = at
	_wind.append(cold)
	cold.create_tween().tween_property(cold, "light_energy", 0.0, 3.2).set_trans(Tween.TRANS_SINE)
