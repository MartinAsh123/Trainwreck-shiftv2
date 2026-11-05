class_name LightSwitch
extends Node3D
## A working wall switch: E flips its lever (a child named "Rocker" or "Toggle", tilted by
## `throw_deg`) and turns the lamps in `lamps` on or off — each lamp is a marker holding an
## OmniLight3D and the fitting's meshes, whose glowing glass is dimmed with the light.
## The car builders fill `lamps` and mark those markers "dynamic" so StaticMerge leaves them alone.
## The switch adds its own small pick area (layer 2) so the player's ray finds it.

signal switched(on: bool)

@export var on: bool = true:
	set(v):
		on = v
		_apply()
## Lever tilt about local X (degrees) when on; off is the opposite tilt.
@export var throw_deg: float = 8.0
## Pick box (local), centred on the plate face.
@export var pick_size: Vector3 = Vector3(0.09, 0.11, 0.04)
@export var pick_offset: Vector3 = Vector3(0, 0, -0.01)
## What the prompt calls it ("lights", "corridor lights"…).
@export var label: String = "lights"

var lamps: Array[Node3D] = []
var _dimmed := {}          # MeshInstance3D -> {surface: original material}

func _ready() -> void:
	setup()

## Adds the pick area and shows the state. Called from _ready, and by the car builders, who attach
## this script to a switch already in the tree (whose _ready then never runs).
func setup() -> void:
	if has_node("Pick"):
		_apply()
		return
	var area := Area3D.new()
	area.name = "Pick"
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = pick_size
	shape.shape = box
	shape.position = pick_offset
	area.add_child(shape)
	add_child(area)
	_apply()

func get_prompt() -> String:
	return "E — Switch %s %s" % [label, "off" if on else "on"]

func interact(_by: Node = null) -> String:
	on = not on
	switched.emit(on)
	return ""

func _apply() -> void:
	if not is_inside_tree():
		return
	var lever := get_node_or_null("Rocker") as Node3D
	if lever == null:
		lever = get_node_or_null("Toggle") as Node3D
	if lever:
		lever.rotation.x = deg_to_rad(throw_deg if on else -throw_deg)
	for lamp in lamps:
		if is_instance_valid(lamp):
			_set_lamp(lamp, on)

func _set_lamp(lamp: Node3D, lit: bool) -> void:
	for l: Light3D in lamp.find_children("*", "Light3D", true, false):
		l.visible = lit
	for mi: MeshInstance3D in lamp.find_children("*", "MeshInstance3D", true, false):
		if lit:
			if _dimmed.has(mi):
				var saved: Dictionary = _dimmed[mi]
				for s: int in saved:
					mi.set_surface_override_material(s, saved[s])
				_dimmed.erase(mi)
			continue
		if _dimmed.has(mi):
			continue
		var saved := {}
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			var dark := _unlit(m)
			if dark != null:
				saved[s] = mi.get_surface_override_material(s)
				mi.set_surface_override_material(s, dark)
		if not saved.is_empty():
			_dimmed[mi] = saved

static var _unlit_cache := {}

# The same material with its glow taken out (null if it doesn't glow).
static func _unlit(m: Material) -> Material:
	if m == null:
		return null
	if _unlit_cache.has(m):
		return _unlit_cache[m]
	var out: Material = null
	if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
		var d := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
		d.emission_enabled = false
		out = d
	elif m is ShaderMaterial:
		var sm := m as ShaderMaterial
		if sm.get_shader_parameter("glow_energy") != null and int(sm.get_shader_parameter("mode")) == 2:
			var d := sm.duplicate() as ShaderMaterial
			d.set_shader_parameter("glow_energy", 0.0)
			out = d
	_unlit_cache[m] = out
	return out
