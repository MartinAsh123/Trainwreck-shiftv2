class_name ShadowBudget
extends Node
## Keeps shadow-casting point and spot lights to a budget: only the few lamps nearest the camera
## cast shadows; the others still light the scene, without shadows. Every shadowed omni light
## re-renders the geometry around it six times (once per cube face), which is what made the cars
## expensive. Nearby shadows look exactly as before; far ones were never visible anyway.
## Only lights that were set up to cast shadows are managed.

@export var max_shadowed: int = 3
@export var max_distance: float = 8.0
@export var refresh: float = 0.15            # seconds between re-checks

var _lights: Array[Light3D] = []
var _t := 0.0

func _ready() -> void:
	# Let the train, the stations and RenderTuning finish first.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_collect()
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if n is Light3D and not (n is DirectionalLight3D):
		_adopt.call_deferred(n)

# (deferred: the builder sets shadow_enabled after adding the light)
func _adopt(n: Node) -> void:
	if is_instance_valid(n) and (n as Light3D).shadow_enabled and not n.has_meta("_shadow_budget"):
		n.set_meta("_shadow_budget", true)
		_lights.append(n as Light3D)
		(n as Light3D).shadow_enabled = false

func _collect() -> void:
	_lights.clear()
	for n: Node in get_tree().root.find_children("*", "Light3D", true, false):
		if n is DirectionalLight3D:
			continue
		var l := n as Light3D
		if l.shadow_enabled or l.has_meta("_shadow_budget"):
			l.set_meta("_shadow_budget", true)
			_lights.append(l)

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = refresh
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var near: Array = []
	var i := 0
	while i < _lights.size():
		var l := _lights[i]
		if not is_instance_valid(l):
			_lights.remove_at(i)
			continue
		var d := cp.distance_to(l.global_position)
		if d <= max_distance and l.is_visible_in_tree():
			near.append([d, l])
		i += 1
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var keep := {}
	for k in mini(max_shadowed, near.size()):
		keep[near[k][1]] = true
	for l in _lights:
		var on := keep.has(l)
		if l.shadow_enabled != on:
			l.shadow_enabled = on

## New lights with shadows (stations streaming in) join the budget.
func rescan() -> void:
	_collect()
