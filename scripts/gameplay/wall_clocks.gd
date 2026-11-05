class_name WallClocks
extends Node3D
## A red-on-black digital clock on the end walls of every car: in the saloons beside the door at
## either end (on the side away from the emergency brake), in the corridor cars over the corridor's
## end doors. They show the train's clock (TrainState.clock) and only change their text when the
## minute does.

const FONT := preload("res://assets/fonts/DSEG7Classic-Bold.ttf")
const CARS := ["PassengerCar", "SleeperCar", "CrewCar", "MailVan"]
const RED := Color(1.0, 0.09, 0.04)
const WALL := 0.1                        # the end partition's face, out from its door cut
const SALOON_Y := 3.335                  # world height of a saloon clock (floor at 1.4): under the vent, over the signs
const CORRIDOR_Y := 3.5

var _digits: Array = []                  # Label3D on every clock
var _shown := ""
var _ts: Node

func _ready() -> void:
	add_to_group("wall_clocks")
	_ts = get_node_or_null("/root/TrainState")
	_build.call_deferred()

func _build() -> void:
	await get_tree().process_frame
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	if train == null:
		return
	for c: Node in train.get_children():
		var car := c as Node3D
		if car == null or not CARS.any(func(p): return String(car.name).begins_with(p)):
			continue
		var brake_z := 0.8
		var brakes := car.find_children("EmergencyBrake_*", "", true, false)
		if not brakes.is_empty():
			brake_z = (brakes[0] as Node3D).global_position.z
		for cut_name in ["InnerDoorCut", "InnerDoorCut2"]:
			var cut := car.find_child(cut_name, true, false) as Node3D
			if cut == null:
				continue
			var inward := signf(car.global_position.x - cut.global_position.x)
			var p := cut.global_position
			var at: Vector3
			if absf(p.z) < 0.3:
				# A saloon end: beside the door, away from the brake (the mail van: away from its own clock).
				var side := -signf(brake_z) if not brakes.is_empty() or not String(car.name).begins_with("MailVan") else 1.0
				at = Vector3(p.x + inward * WALL, SALOON_Y, side * 0.78)
			else:
				at = Vector3(p.x + inward * WALL, CORRIDOR_Y, p.z)
			_clock(at, inward)
	_update(true)

func _clock(at: Vector3, inward: float) -> void:
	var n := Node3D.new()
	n.name = "WallClock"
	add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, atan2(inward, 0.0)), at + Vector3(inward * 0.02, 0, 0))
	var body := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.3, 0.11, 0.04)
	body.mesh = bx
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.025, 0.025, 0.028)
	black.roughness = 0.35
	body.material_override = black
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(body)
	# The unlit segments, faint, behind the lit ones: it reads as a real display.
	var off := _label("88:88", Color(RED, 0.09))
	n.add_child(off)
	var lit := _label("", RED)
	lit.position.z += 0.0005
	n.add_child(lit)
	_digits.append(lit)
	var glow := OmniLight3D.new()
	glow.light_color = RED
	glow.light_energy = 0.07
	glow.omni_range = 0.55
	glow.shadow_enabled = false
	glow.position = Vector3(0, 0, 0.12)
	n.add_child(glow)

func _label(text: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.font = FONT
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.0011
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = Vector3(0, 0, 0.0205)
	return l

func _process(_delta: float) -> void:
	_update(false)

func _update(force: bool) -> void:
	var t := TaskBoard.hhmm(float(_ts.get("clock"))) if _ts else "00:00"
	if t == _shown and not force:
		return
	_shown = t
	for l: Label3D in _digits:
		l.text = t
