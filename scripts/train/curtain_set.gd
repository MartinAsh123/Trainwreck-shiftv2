class_name CurtainSet
extends Node3D
## The pair of curtains on one window. Interacting draws both curtains across the window or opens
## them back to their tie-backs: the rings slide along the rod first and the cloth follows, with
## the hem lagging a little. The car builds the meshes (PassengerCar._curtain_mesh, cached in steps)
## and the nodes; this only animates them.

signal moved(closing: bool)

const DURATION := 1.4

var car: Node = null
var curtains: Array = []        # [MeshInstance3D, side sign]
var rings: Array = []           # [ring node, side sign, ring index]
var ties: Array = []            # tie-back nodes, hidden while the curtains are drawn
var half_w: float = 0.0

var _t: float = 0.0
var _target: float = 0.0
var _shown_step: int = 0

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("curtains")
	set_process(false)

func is_closed() -> bool:
	return _target > 0.5

func get_prompt() -> String:
	return "E — Open curtains" if is_closed() else "E — Draw curtains"

func interact(_by: Node = null) -> String:
	request(not is_closed())
	return ""

func request(closed: bool) -> void:
	var t := 1.0 if closed else 0.0
	if is_equal_approx(_target, t):
		return
	_target = t
	moved.emit(closed)
	set_process(true)

func set_closed_immediate(closed: bool) -> void:
	_target = 1.0 if closed else 0.0
	_t = _target
	_apply()

func _process(delta: float) -> void:
	_t = move_toward(_t, _target, delta / DURATION)
	_apply()
	if is_equal_approx(_t, _target):
		set_process(false)

func _apply() -> void:
	if car == null or not car.has_method("_curtain_mesh"):
		return
	var e := _t * _t * (3.0 - 2.0 * _t)
	var parts: Dictionary = car.call("_curtain_mesh", e)
	for c: Array in curtains:
		(c[0] as MeshInstance3D).mesh = parts.curtain if float(c[1]) > 0.0 else parts.curtain_l
	var xs: Array = parts.ring_xs
	for r: Array in rings:
		var node: Node3D = r[0]
		var sx: float = r[1]
		node.position.x = sx * (half_w + 0.02 + float(xs[r[2]]))
	for t: Node3D in ties:
		t.visible = e < 0.04
