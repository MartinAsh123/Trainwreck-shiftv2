class_name Inventory
extends Node
## What Kevin carries: four slots (the toolbar at the bottom of the screen, ShiftHUD). E on a
## HauntItem puts it in the first free slot; 1-4 or the mouse wheel pick the slot in hand; Q puts the
## thing in hand down on the floor in front of him (it can be picked up again there). Whatever a job
## uses up goes back where it came from (`use`), or is gone for good (`consume`, the waste he throws
## away).

signal changed

const SLOTS := 4

var slots: Array = []                      # HauntItem or null, one per slot
var selected := 0

static func of(n: Node) -> Inventory:
	return n.get_tree().get_first_node_in_group("inventory") as Inventory

## True when Kevin carries `id` (in any slot).
static func carries(n: Node, id: String) -> bool:
	var inv := of(n)
	return inv != null and inv.has_item(id)

func _ready() -> void:
	add_to_group("inventory")
	slots.resize(SLOTS)

func has_item(id: String) -> bool:
	return find(id) != null

func find(id: String) -> HauntItem:
	for it in slots:
		if it != null and is_instance_valid(it) and (it as HauntItem).item == id:
			return it
	return null

func count() -> int:
	return slots.filter(func(it): return it != null).size()

func in_hand() -> HauntItem:
	var it = slots[selected]
	return it if it != null and is_instance_valid(it) else null

## Picks `it` up; returns what to tell the player ("" when it went in).
func take(it: HauntItem) -> String:
	var i := slots.find(null)
	if i < 0:
		return "Your hands are full - Q puts the one in hand down"
	if not it.has_meta("home"):
		it.set_meta("home", it.global_transform)
	slots[i] = it
	selected = i
	_hide(it, true)
	changed.emit()
	return ""

## Used for a job: out of the slot and back to where it came from.
func use(id: String) -> void:
	var it := _remove(id)
	if it:
		if it.has_meta("home"):
			it.global_transform = it.get_meta("home")
		_hide(it, false)

## Used up for good (the waste thrown away): out of the slot and gone.
func consume(id: String) -> void:
	var it := _remove(id)
	if it:
		it.queue_free()

func _remove(id: String) -> HauntItem:
	var it := find(id)
	if it:
		slots[slots.find(it)] = null
		changed.emit()
	return it

## The thing in hand, down on the floor a step in front of him.
func drop() -> void:
	var it := in_hand()
	var p := _player()
	if it == null or p == null:
		return
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	var from := p.global_position + fwd.normalized() * 0.55 + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -2.5, 0), 1, [(p as CollisionObject3D).get_rid()] if p is CollisionObject3D else [])
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if not hit.is_empty() else p.global_position
	slots[selected] = null
	it.global_transform = Transform3D(Basis(Vector3.UP, p.global_rotation.y), at)
	_hide(it, false)
	changed.emit()

func _hide(it: HauntItem, held: bool) -> void:
	it.visible = not held
	var pick := it.get_node_or_null("Pick") as Area3D
	if pick:
		pick.collision_layer = 0 if held else 2

func _player() -> Node3D:
	return get_tree().root.find_child("Player", true, false) as Node3D

func _unhandled_input(event: InputEvent) -> void:
	var p := _player()
	if p == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if p.has_method("is_focused") and bool(p.call("is_focused")):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k < KEY_1 + SLOTS:
			selected = k - KEY_1
			changed.emit()
		elif k == KEY_Q:
			drop()
	elif event is InputEventMouseButton and event.pressed:
		var b := (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN:
			selected = posmod(selected + (-1 if b == MOUSE_BUTTON_WHEEL_UP else 1), SLOTS)
			changed.emit()
