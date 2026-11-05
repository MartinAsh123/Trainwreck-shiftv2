class_name LocoWhistle
extends Node
## The engine's chime whistle ("choo choo", generated with ElevenLabs sound effects), blown every
## `interval` seconds of play, from the chimney end of the locomotive. It plays on the "Outside" bus
## (GameAudio muffles that bus while the player is indoors) and carries the whole length of the
## train. Nothing happens in the editor.

const STREAM := "res://assets/audio/loco_whistle_choo.mp3"
const LOCO_X := -80.0            # train space: just behind the chimney, where the whistle stands
const WHISTLE_Y := 4.6

@export var interval: float = 150.0      # 2½ minutes
@export var first_delay: float = 150.0
@export var volume_db: float = 4.0

var _player: AudioStreamPlayer3D
var _timer: Timer

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_setup.call_deferred()

func _setup() -> void:
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	if train == null or not ResourceLoader.exists(STREAM):
		return
	_player = AudioStreamPlayer3D.new()
	_player.name = "LocoWhistle"
	_player.stream = load(STREAM)
	_player.position = Vector3(LOCO_X, WHISTLE_Y, 0.0)
	_player.unit_size = 22.0
	_player.max_distance = 600.0
	_player.volume_db = volume_db
	_player.attenuation_filter_cutoff_hz = 12000.0
	if AudioServer.get_bus_index("Outside") >= 0:
		_player.bus = "Outside"
	train.add_child(_player)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_blow)
	add_child(_timer)
	_timer.start(first_delay)

func _blow() -> void:
	blow()
	_timer.start(interval)

## Sounds the whistle now (also usable from other scripts and tests).
func blow() -> void:
	if _player:
		_player.pitch_scale = randf_range(0.98, 1.02)
		_player.play()
