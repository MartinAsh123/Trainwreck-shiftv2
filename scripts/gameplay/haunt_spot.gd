class_name HauntSpot
extends Node3D
## A place to work on a breakdown (the blocked W.C., a puddle, the ceiling hatch, a loose cable): a
## pick box whose prompt and action come from HauntDirector, so one spot can change as the job goes on.

var prompt: Callable
var action: Callable

static func make(spot_name: String, size: Vector3, p: Callable, a: Callable) -> HauntSpot:
	var s := HauntSpot.new()
	s.name = spot_name
	s.prompt = p
	s.action = a
	var area := Area3D.new()
	area.name = "Pick"
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	area.add_child(cs)
	s.add_child(area)
	return s

func get_prompt() -> String:
	return str(prompt.call())

func interact(_by: Node = null) -> String:
	return str(action.call())
