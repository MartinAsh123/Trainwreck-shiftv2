class_name StaffControl
extends Node3D
## One pickable control of a StaffPanel (a knob, a push button, the cabinet door): it adds a small
## pick area on layer 2 and hands get_prompt()/interact() to its panel under its `id`.

var panel: Node
var id: String

func setup(p: Node, control_id: String, pick_size: Vector3, pick_offset := Vector3.ZERO) -> void:
	panel = p
	id = control_id
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

func get_prompt() -> String:
	return panel.prompt_for(id) if panel else ""

func interact(_by: Node = null) -> String:
	return panel.press(id) if panel else ""
