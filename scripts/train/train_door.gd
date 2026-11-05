class_name TrainDoor
extends AnimatableBody3D
## An openable door leaf with real collision. SLIDE doors move along `travel` (local) into their
## pocket or along their track; HINGE doors turn about their local Y axis (this body's origin is
## the hinge line) by `hinge_angle`. A door never closes onto the player: if the closing leaf
## would overlap a character, it stops and opens again. Locked doors (always_locked, a bound
## ToiletLock, or exterior doors while the train moves) refuse to open and say why.
## The car scripts create these at build time around their door models.

signal moved(opening: bool)          # started opening (true) or closing (false)
signal finished(open: bool)          # reached fully open / fully closed
signal refused(reason: String)       # tried to open a locked door

enum Kind { SLIDE, HINGE }

@export var kind: Kind = Kind.SLIDE
@export var travel: Vector3 = Vector3.ZERO
@export var hinge_angle: float = 0.0
@export var duration: float = 0.9
@export var start_open: bool = false
@export var always_locked: bool = false
@export var lock_while_moving: bool = false
@export var locked_text: String = "Locked"
@export var door_name: String = "door"
## Hinged leaves hung leaning with the bodyside: straighten up while opening (true vertical axis)
## rather than swing about the leaning hinge line.
@export var upright_open: bool = true

var lock_node: Node = null          # anything with a bool `locked` property (ToiletLock)
var _t: float = 0.0
var _target: float = 0.0
var _closed: Transform3D
var _upright: Basis                 # the closed pose with any lean (tumblehome) taken out
var _shape: CollisionShape3D

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_closed = transform
	sync_to_physics = true
	add_to_group("interactable")
	add_to_group("train_door")
	# The car builder adds the leaf's shape and sets start_open after the body enters the tree.
	_setup.call_deferred()

func _setup() -> void:
	# The closed pose is taken here, after the car builder has finished: it tilts a leaf hung on the
	# leaning bodyside only after adding it, and a pose taken in _ready would miss that tilt (the
	# leaf then jumped crooked the first time it moved).
	_closed = transform
	# A leaf hung leaning with the bodyside straightens as it opens (turning about a true vertical
	# axis), so the open door stands upright instead of looking twisted.
	var up := _closed.basis.y.normalized()
	_upright = (Basis(Quaternion(up, Vector3.UP)) * _closed.basis).orthonormalized() if up.dot(Vector3.UP) < 0.99999 else _closed.basis
	_find_shape()
	if start_open:
		set_open_immediate(true)

func _find_shape() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			_shape = c
			return

func is_open() -> bool:
	return _target > 0.5

func set_open_immediate(open: bool) -> void:
	_t = 1.0 if open else 0.0
	_target = _t
	transform = _pose(_t)

func lock_reason() -> String:
	if always_locked:
		return locked_text
	if lock_node != null and bool(lock_node.get("locked")):
		return "Engaged"
	var ts := get_node_or_null("/root/TrainState")
	if lock_while_moving and ts != null and bool(ts.call("is_moving")):
		return "Do not open while the train is moving"
	return ""

func get_prompt() -> String:
	if not is_open():
		var r := lock_reason()
		return ("%s — %s" % [door_name.left(1).to_upper() + door_name.substr(1), r]) if r != "" else "E — Open %s" % door_name
	return "E — Close %s" % door_name

func interact(_by: Node = null) -> String:
	if not is_open():
		var r := lock_reason()
		if r != "":
			refused.emit(r)
			return r
		_target = 1.0
		moved.emit(true)
	else:
		_target = 0.0
		moved.emit(false)
	return ""

# Opening or closing from code (the journey closes exterior doors before departure).
func request(open: bool) -> void:
	if (_target > 0.5) == open:
		return
	if open and lock_reason() != "":
		return
	_target = 1.0 if open else 0.0
	moved.emit(open)

## Flung open or slammed from code, whatever the locks say, in `seconds` (AnomalyFrenzy).
func force(open: bool, seconds := 0.25) -> void:
	_forced = seconds
	_target = 1.0 if open else 0.0
	moved.emit(open)

var _forced := 0.0                  # > 0: a forced swing, nothing stops it

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_equal_approx(_t, _target):
		return
	if _forced > 0.0:
		_t = move_toward(_t, _target, delta / _forced)
		transform = _pose(_t)
		if is_equal_approx(_t, _target):
			_forced = 0.0
			finished.emit(_t > 0.5)
		return
	var step := delta / maxf(duration, 0.05)
	var nt := move_toward(_t, _target, step)
	if nt < _t and _blocked_at(nt):
		# Something (the player) is in the way: back off and stay open.
		_target = 1.0
		moved.emit(true)
		return
	if nt > _t and kind == Kind.HINGE and _blocked_at(nt):
		# A swinging leaf would shove whoever stands in its arc: swing back shut instead.
		_target = 0.0
		moved.emit(false)
		refused.emit("Step back from the door")
		return
	_t = nt
	transform = _pose(_t)
	if is_equal_approx(_t, _target):
		finished.emit(_t > 0.5)

func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func _pose(t: float) -> Transform3D:
	var e := _ease(t)
	if kind == Kind.SLIDE:
		return Transform3D(_closed.basis, _closed.origin + _closed.basis * (travel * e))
	if not upright_open:
		return Transform3D(_closed.basis * Basis(Vector3.UP, hinge_angle * e), _closed.origin)
	var lean := Basis(_closed.basis.get_rotation_quaternion().slerp(_upright.get_rotation_quaternion(), e)).scaled(_closed.basis.get_scale())
	return Transform3D(Basis(Vector3.UP, hinge_angle * e) * lean, _closed.origin)

func _blocked_at(t: float) -> bool:
	if _shape == null:
		_find_shape()
	if _shape == null or _shape.shape == null:
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape.shape
	var parent_xf := (get_parent() as Node3D).global_transform if get_parent() is Node3D else Transform3D.IDENTITY
	q.transform = parent_xf * _pose(t) * _shape.transform
	q.exclude = [get_rid()]
	q.collide_with_bodies = true
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 8):
		if hit.collider is CharacterBody3D:
			return true
	return false
