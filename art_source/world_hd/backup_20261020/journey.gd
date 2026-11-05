class_name Journey
extends Node
## Runs the train along RouteData and writes TrainState every physics frame:
##   stopped (dwell at a station) -> departing (doors shut, whistle, a few seconds) -> running
##   (accelerate to line speed) -> braking (a steady stop with the train's middle at the platform
##   centre) -> stopped … until the terminus.
## Also keeps the clock (TrainState.clock, hours) that the sky and the timetable use.

signal whistle(long: bool)

@export var line_speed: float = 22.0            # m/s (about 80 km/h)
@export var accel: float = 0.42                 # m/s²
@export var brake: float = 0.55                 # m/s², service braking
@export var dwell: float = 35.0                 # seconds standing at each station
@export var first_dwell: float = 25.0
@export var depart_warning: float = 5.0         # doors shut + whistle before the train moves
## Where the train's middle is relative to TrainState.distance (the Train node's origin is car 2;
## the train runs from the sleeper's tail at +26 to the buffers at -84).
@export var stop_offset: float = -29.0
@export var start_clock: float = 19.0 + 5.0 / 60.0
## Game time per real time: the night passes about three times faster than real time, so the run
## from Královec (19.10) to Kamenný Most (21.15) keeps roughly to the timetable.
@export var clock_scale: float = 3.0
@export var autostart: bool = true

var _stop_idx := 0               # index into RouteData.stops() of the station we are at / heading to
var _timer := 0.0
var _ts: Node

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
	_ts.set("clock", fmod(float(_ts.get("clock")) + delta * clock_scale / 3600.0, 24.0))
	var phase: String = _ts.get("phase")
	var v: float = _ts.get("speed")
	var d: float = _ts.get("distance")
	match phase:
		"stopped":
			if _stop_idx >= stops.size() - 1:
				return        # terminus
			_timer -= delta
			if _timer <= 0.0:
				_ts.call("set_phase", "departing")
				_ts.emit_signal("departing", stops[_stop_idx].name)
				whistle.emit(true)
				_timer = depart_warning
		"departing":
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
			else:
				v = move_toward(v, line_speed, accel * delta)
			d += v * delta
	_ts.set("speed", v)
	_ts.set("distance", d)
	_update_next()

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
