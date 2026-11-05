class_name Journey
extends Node
## Runs the train along RouteData and writes TrainState every physics frame:
##   stopped (dwell at a station) -> departing (doors shut, whistle, a few seconds) -> running
##   (accelerate to line speed) -> braking (a steady stop with the train's middle at the platform
##   centre) -> stopped … until the terminus.
## Also keeps the clock (TrainState.clock, hours) that the sky and the timetable use.
##
## Kevin is crew: the train never leaves a station without him. If he is off the train when it is
## due out, it waits (a short toot and a word from the guard) and leaves a few seconds after he is
## back aboard; if he steps off while the doors are closing, the departure is called off until he
## returns. Should he ever fall through the world, he is put back aboard.

signal whistle(long: bool)

@export var line_speed: float = 30.0            # m/s (about 108 km/h, an express)
@export var accel: float = 0.6                  # m/s²
@export var brake: float = 0.7                  # m/s², service braking
@export var dwell: float = 25.0                 # seconds standing at each station
@export var first_dwell: float = 20.0
@export var depart_warning: float = 5.0         # doors shut + whistle before the train moves
## Where the train's middle is relative to TrainState.distance (the Train node's origin is car 2;
## the train runs from the sleeper's tail at +26 to the buffers at -84).
@export var stop_offset: float = -29.0
@export var start_clock: float = 19.0 + 7.33 / 60.0
## Game time per real time: the run from Královec (19.10) to Kamenný Most (21.15) takes about 20 real
## minutes (the shift), so the night passes 6.4 times faster and keeps to RouteData's timetable.
@export var clock_scale: float = 6.4
@export var autostart: bool = true
@export var reboard_delay: float = 4.0          # seconds after the player is back aboard before leaving

## Inside the train, in the train's space (the same box GameAudio uses for "indoors").
const TRAIN_INSIDE := AABB(Vector3(-84.0, -1.0, -1.45), Vector3(110.2, 6.0, 2.9))
const RESCUE_Y := -25.0                          # below this the player has fallen out of the world
const ABOARD_SPOT := Vector3(-7.2, 1.45, 0.0)    # where the player starts (train space)

var _stop_idx := 0               # index into RouteData.stops() of the station we are at / heading to
var _timer := 0.0
var _ts: Node
var _player: Node3D
var _train: Node3D
var _held := false               # departure held for the player
## The emergency brake is pulled (HauntDirector): stop where we are and stand till it is reset.
var emergency := false
var _nag := 0.0

func _ready() -> void:
	_ts = get_node("/root/TrainState")
	var stops := RouteData.stops()
	_ts.set("distance", stops[0].s + stop_offset)
	_ts.set("speed", 0.0)
	_ts.set("clock", start_clock)
	_arrive(0)
	_timer = first_dwell
	if not autostart:
		set_physics_process(false)

func _arrive(i: int) -> void:
	var stops := RouteData.stops()
	_stop_idx = i
	_ts.set("station", stops[i].name)
	_ts.call("set_phase", "stopped")
	_timer = dwell
	_ts.emit_signal("arrived", stops[i].name)
	_update_next()

func _update_next() -> void:
	var stops := RouteData.stops()
	var phase: String = _ts.get("phase")
	var ni := _stop_idx if phase in ["running", "braking"] else _stop_idx + 1
	if ni < stops.size():
		_ts.set("next_stop", stops[ni].name)
		_ts.set("to_next_stop", stops[ni].s + stop_offset - float(_ts.get("distance")))
	else:
		_ts.set("next_stop", "")
		_ts.set("to_next_stop", 0.0)

func _physics_process(delta: float) -> void:
	var stops := RouteData.stops()
	_rescue()
	_ts.set("clock", fmod(float(_ts.get("clock")) + delta * clock_scale / 3600.0, 24.0))
	var phase: String = _ts.get("phase")
	var v: float = _ts.get("speed")
	var d: float = _ts.get("distance")
	match phase:
		"stopped":
			if _stop_idx >= stops.size() - 1:
				return        # terminus
			_timer -= delta
			if _timer <= 0.0 and not _player_aboard():
				_hold(delta)
				return
			if _held:
				# Back aboard: a few more seconds, then away.
				_held = false
				_timer = maxf(_timer, reboard_delay)
				return
			if _timer <= 0.0:
				_ts.call("set_phase", "departing")
				_ts.emit_signal("departing", stops[_stop_idx].name)
				whistle.emit(true)
				_timer = depart_warning
		"departing":
			if not _player_aboard():
				# Stepped off while the doors were closing: wait for him.
				_ts.call("set_phase", "stopped")
				_timer = 0.0
				_hold(delta)
				return
			_timer -= delta
			if _timer <= 0.0:
				_stop_idx += 1          # now heading for the next stop
				_ts.set("station", "")
				_ts.call("set_phase", "running")
		"running", "braking":
			var target: float = stops[_stop_idx].s + stop_offset
			var left := target - d
			var need := v * v / (2.0 * maxf(left, 0.01))
			if phase == "running" and need >= brake * 0.97:
				_ts.call("set_phase", "braking")
				phase = "braking"
			if phase == "braking":
				# Exactly the deceleration that stops at the mark (never more than emergency).
				v = maxf(v - minf(need, brake * 1.6) * delta, 0.0)
				if left < 0.03 or v < 0.05:
					d = target
					v = 0.0
					_ts.set("speed", 0.0)
					_ts.set("distance", d)
					_arrive(_stop_idx)
					return
			elif emergency:
				v = move_toward(v, 0.0, brake * 3.2 * delta)   # (emergency: about 2.2 m/s²)
			else:
				v = move_toward(v, line_speed, accel * delta)
			d += v * delta
	_ts.set("speed", v)
	_ts.set("distance", d)
	_update_next()

# ————— the player and the train —————

func _find_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			_player = get_tree().root.find_child("Player", true, false) as Node3D
	if _train == null or not is_instance_valid(_train):
		_train = get_tree().root.find_child("Train", true, false) as Node3D

## True when the player is inside the train (or there is no player, e.g. in tests).
func player_aboard() -> bool:
	return _player_aboard()

func _player_aboard() -> bool:
	_find_player()
	if _player == null or _train == null:
		return true
	return TRAIN_INSIDE.has_point(_train.global_transform.affine_inverse() * _player.global_position)

func _hold(delta: float) -> void:
	if not _held:
		_held = true
		_nag = 0.0
		whistle.emit(false)
	_nag -= delta
	if _nag <= 0.0:
		_nag = 12.0
		if _player and _player.has_method("show_message"):
			_player.call("show_message", "The train is waiting for you — get back aboard", 4.0)

# Fallen through the world (off the edge of a yard, or left behind): back aboard.
func _rescue() -> void:
	_find_player()
	if _player == null or _train == null or _player.global_position.y > RESCUE_Y:
		return
	_player.global_position = _train.global_transform * ABOARD_SPOT
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	if _player.has_method("show_message"):
		_player.call("show_message", "You climb back aboard", 3.0)

## Jump straight to standing at stop `i` (debugging and tests).
func warp_to_stop(i: int) -> void:
	var stops := RouteData.stops()
	i = clampi(i, 0, stops.size() - 1)
	_ts.set("distance", stops[i].s + stop_offset)
	_ts.set("speed", 0.0)
	_arrive(i)

## Jump to running at line speed `metres` before the next stop's braking point.
func warp_running(s: float) -> void:
	var stops := RouteData.stops()
	var i := 0
	while i < stops.size() - 1 and stops[i].s + stop_offset <= s:
		i += 1
	_stop_idx = i
	_ts.set("distance", s)
	_ts.set("speed", line_speed)
	_ts.set("station", "")
	_ts.call("set_phase", "running")
	_update_next()
