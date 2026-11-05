class_name DreadBed
extends Node
## The horror underscore: two baked drone loops on the "Music" bus (tools/bake_dread.py) that follow
## one dread level, 0..1. Driven through GameAudio.dread(level, seconds); nothing here decides when.
##   0          silent (the players stop)
##   0.1 - 0.5  the low drone rises out of the rails, a little darker as it grows
##   0.4 - 1.0  the wavering cluster joins and creeps sharp: the swell before something happens
## Cut it with dread(0.0, 0.0) on the hit: the sudden silence is part of the scare.

const LOW := "res://assets/audio/dread_low.wav"
const HIGH := "res://assets/audio/dread_high.wav"
const BUS := &"Music"

var level := 0.0                     # where the bed is now
var _target := 0.0
var _rate := 1.0                     # level units per second toward the target
var _low: AudioStreamPlayer
var _high: AudioStreamPlayer

func _ready() -> void:
	_low = _make(LOW)
	_high = _make(HIGH)
	set_process(false)

func _make(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var st := load(path) as AudioStreamWAV
	if st:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = int(st.get_length() * st.mix_rate)
	p.stream = st
	p.bus = BUS
	p.volume_db = -80.0
	add_child(p)
	return p

## Moves the bed to `to` (0..1) over `seconds`; 0 seconds jumps there at once.
func set_level(to: float, seconds := 3.0) -> void:
	_target = clampf(to, 0.0, 1.0)
	if seconds <= 0.0:
		level = _target
		_apply()
		return
	_rate = maxf(absf(_target - level) / seconds, 0.001)
	set_process(true)

func _process(delta: float) -> void:
	level = move_toward(level, _target, _rate * delta)
	_apply()
	if is_equal_approx(level, _target):
		set_process(false)

func _apply() -> void:
	if level <= 0.001:
		_low.stop()
		_high.stop()
		return
	if not _low.playing:
		_low.play(randf() * 8.0)
	if not _high.playing:
		_high.play(randf() * 8.0)
	var lo := smoothstep(0.0, 0.6, level)
	var hi := smoothstep(0.35, 1.0, level)
	_low.volume_db = lerpf(-40.0, -13.0, lo) if lo > 0.0 else -80.0
	_low.pitch_scale = 1.0 - 0.04 * level
	_high.volume_db = lerpf(-46.0, -15.0, hi) if hi > 0.0 else -80.0
	_high.pitch_scale = 1.0 + 0.05 * smoothstep(0.6, 1.0, level)
