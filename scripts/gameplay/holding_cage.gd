class_name HoldingCage
extends Node
## Makes the mail van's holding cage work: its gate (built by MailVan as part of the fixed mesh wall)
## becomes a real hinged TrainDoor that swings out into the aisle, locked unless the guard has it
## open (the player finds it "Locked - the guard has the key"). The cage's places are the slatted
## bench's: as many as fit along it a person's width apart (the cage's capacity). Nobody but Mike
## opens it; whoever opened it is answerable for shutting and locking it again (secure()).
##   cage.capacity(), cage.free_place() -> int (-1 when full), cage.place_xf(i)
##   cage.unlock_and_open(), cage.is_open_wide(), cage.close_and_lock() -> true once shut and locked
##   cage.approach_point() - where the guard stands in the aisle, clear of the gate's swing
##   cage.inside_point(i) / cage.gateway_point() - the steps of a walk in or out
## Kevin can open it too, with the cage key from Mike's room (on the safe) in his toolbar: E at the
## gate unlocks and opens it, E again shuts and locks it. Left unlocked (open, or only pulled to) while
## he is away from it for `escape_after` seconds, a held anomaly slips out and rides on in another
## face (Passengers.respawn_as, ShiftRecord.anomaly_escaped).

signal secured

@export var escape_after := 8.0          # seconds unlocked with Kevin more than `away` metres off
@export var away := 5.0

const GATE_W := 0.8
const PLACE_GAP := 0.7
const SIT_H := 0.45              # bench top

var gate: TrainDoor
var _group: Node3D
var _bench: Node3D
var _gx := 0.0                   # the gate's middle along the car (HoldingCage space)
var _z0 := 0.5                   # the mesh wall's face (aisle side)
var _wi := 1.3
var _places: Array = []          # local positions on the bench
var _held := {}                  # place index -> pid
var _pending_close := false
var kevin_opened := false        # Kevin unlocked it and has not locked it again
var _closing := false
var _away_t := 0.0
var _key_spot: HauntSpot

static func of(n: Node) -> HoldingCage:
	return n.get_tree().get_first_node_in_group("holding_cage") as HoldingCage

func _ready() -> void:
	add_to_group("holding_cage")
	_setup()

func _setup() -> void:
	var van := get_tree().root.find_child("MailVan5", true, false) as Node3D
	_group = van.find_child("HoldingCage", true, false) as Node3D if van else null
	if _group == null:
		push_warning("HoldingCage: no holding cage in the mail van")
		return
	var vis := _group.get_node_or_null("Gate") as Node3D
	var body := _group.get_node_or_null("CageCollision") as StaticBody3D
	_bench = _group.get_node_or_null("Bench") as Node3D
	if vis == null or body == null:
		push_warning("HoldingCage: gate or collision missing")
		return
	_gx = vis.position.x
	_z0 = vis.position.z
	if _bench:
		_wi = _bench.position.z
	# The aisle-side collision wall: split around the gate's opening.
	for cs in body.get_children():
		var c := cs as CollisionShape3D
		if c == null or not (c.shape is BoxShape3D):
			continue
		var size := (c.shape as BoxShape3D).size
		if size.x > size.z:                      # the long wall along the aisle
			var xa := c.position.x - size.x * 0.5
			var xb := c.position.x + size.x * 0.5
			var left := _gx - GATE_W * 0.5
			var right := _gx + GATE_W * 0.5
			c.queue_free()
			for seg in [[xa, left], [right, xb]]:
				var n := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(seg[1] - seg[0], size.y, size.z)
				n.shape = bx
				n.position = Vector3((seg[0] + seg[1]) * 0.5, c.position.y, c.position.z)
				body.add_child(n)
	# The gate: hinged at its -X post, swinging out into the aisle.
	gate = TrainDoor.new()
	gate.name = "CageGate"
	gate.kind = TrainDoor.Kind.HINGE
	gate.hinge_angle = 1.65
	gate.duration = 1.3
	gate.always_locked = true
	gate.locked_text = "Locked — the guard has the key"
	gate.door_name = "cage gate"
	gate.upright_open = false
	gate.add_to_group("nav_door_always")      # the nav keeps its doorway (locked or not)
	gate.position = Vector3(_gx - GATE_W * 0.5, 0, _z0)
	_group.add_child(gate)
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(GATE_W - 0.04, 2.0, 0.05)
	shape.shape = bx
	shape.position = Vector3(GATE_W * 0.5, 1.0, 0)
	gate.add_child(shape)
	var xf := vis.global_transform
	_group.remove_child(vis)
	gate.add_child(vis)
	vis.global_transform = xf
	# Places along the bench (its usable length is the cage's inside, less the corners).
	var cage_len := float(van.get("cage_length")) if van.get("cage_length") != null else 2.8
	var n_places := maxi(int(floor((cage_len - 0.6) / PLACE_GAP)), 1)
	for i in n_places:
		var off := (i - (n_places - 1) * 0.5) * PLACE_GAP
		_places.append(Vector3(_gx + off, 0, _wi - 0.26))
	# Kevin's way in: the key's spot over the gate (only while he carries the key), and the key itself.
	_key_spot = HauntSpot.make("CageKeySpot", Vector3(GATE_W, 1.9, 0.12), _key_prompt, _key_use)
	_group.add_child(_key_spot)
	_key_spot.position = Vector3(_gx, 1.0, _z0 - 0.09)
	_place_key.call_deferred()

# The key lies on the safe in Mike's room.
func _place_key() -> void:
	var safe := get_tree().root.find_child("GuardRoom", true, false)
	safe = safe.find_child("Safe", true, false) if safe else null
	if safe == null:
		return
	var key := ChoreItem.make_chore("key", "the cage key")
	add_child(key)
	key.global_transform = (safe as Node3D).global_transform * Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.05, 0.62, -0.22))

func _key_prompt() -> String:
	if gate == null or _closing:
		return ""
	return "E — Shut and lock the cage" if gate.is_open() or not gate.always_locked else "E — Unlock the cage"

func _key_use() -> String:
	if gate == null:
		return ""
	if gate.is_open() or not gate.always_locked:
		_closing = true
	else:
		unlock_and_open()
		kevin_opened = true
		_away_t = 0.0
	return ""

func _process(delta: float) -> void:
	if gate == null:
		return
	if _key_spot:
		var det := Detention.of(self)
		var mikes := det != null and det.active_pid >= 0          # (not while the guard is at it)
		(_key_spot.get_node("Pick") as Area3D).collision_layer = 2 if Inventory.carries(self, "key") and not mikes else 0
	if _closing and close_and_lock():
		_closing = false
		kevin_opened = false
	if not kevin_opened or is_secured():
		_away_t = 0.0
		if is_secured():
			kevin_opened = false
		return
	var p := get_tree().root.find_child("Player", true, false) as Node3D
	if p and p.global_position.distance_to(gate_middle()) > away:
		_away_t += delta
		if _away_t >= escape_after:
			_away_t = 0.0
			_escape()
	else:
		_away_t = 0.0

# A held anomaly takes its chance: gone from the bench, and somewhere aboard a passenger who wasn't.
func _escape() -> void:
	var det := Detention.of(self)
	var pax := get_tree().root.find_child("Passengers", true, false) as Passengers
	var rec := ShiftRecord.of(self)
	if det == null or pax == null or rec == null:
		return
	for pid in det.held.keys():
		var r = pax.rider_by_pid(pid)
		if r == null or r.anomaly == "":
			continue
		det.held.erase(pid)
		leave_place(pid)
		var new_r = pax.respawn_as(r)
		if new_r:
			rec.anomaly_escaped(r, new_r)
		TerminalData.add_message("Mike", "The cage!", "Kevin - the cage was standing open. The one I locked up is gone, and nobody saw it go. It'll be wearing another face by now. Find it, and keep that key in your pocket.")
		var p := get_tree().root.find_child("Player", true, false)
		if p and p.has_method("show_message"):
			p.call("show_message", "Message from Mike - see Dispatch Messages", 4.0)
		return

func ready_() -> bool:
	return gate != null

func capacity() -> int:
	return _places.size()

func held_count() -> int:
	return _held.size()

## A free place on the bench (-1 when the cage is full).
func free_place() -> int:
	for i in _places.size():
		if not _held.has(i):
			return i
	return -1

func take_place(i: int, pid: int) -> void:
	_held[i] = pid

func leave_place(pid: int) -> void:
	for i in _held.keys():
		if _held[i] == pid:
			_held.erase(i)

func place_of(pid: int) -> int:
	for i in _held:
		if _held[i] == pid:
			return i
	return -1

## Seated on the bench at place i, facing the aisle (the figure faces +Z).
func place_xf(i: int) -> Transform3D:
	var p: Vector3 = _places[i]
	return _group.global_transform * Transform3D(Basis(Vector3.UP, PI), p)

## Standing in front of place i, inside the cage.
func inside_point(i: int) -> Vector3:
	var p: Vector3 = _places[i]
	return _group.global_transform * Vector3(p.x, 0, _z0 + 0.3)

## Just inside the gateway, and just outside it in the aisle.
func gateway_point(inside: bool) -> Vector3:
	return _group.global_transform * Vector3(_gx + 0.1, 0, _z0 + (0.28 if inside else -0.45))

## Out of the gate's swing in the aisle (where a released passenger waits while it is shut).
func clear_point() -> Vector3:
	var p := _group.global_transform * Vector3(_gx + GATE_W * 0.5 + 0.3, 0, _z0 - 1.0)
	var nav := TrainNav.of(self)
	if nav and nav.ready_:
		var c := nav.nearest_free(p, false, 0.6)
		if c.x >= 0:
			return nav.cell_pos(c)
	return p

## Where the guard stands to work the gate: in the aisle past the gate's latch side, clear of its swing.
func approach_point() -> Vector3:
	return _group.global_transform * Vector3(_gx + GATE_W * 0.5 + 0.75, 0, _z0 - 0.55)

func gate_middle() -> Vector3:
	return _group.global_transform * Vector3(_gx, 1.1, _z0)

func unlock_and_open() -> void:
	if gate == null:
		return
	if gate.always_locked:
		gate.always_locked = false
		_click()
	gate.request(true)

func is_open_wide() -> bool:
	return gate != null and gate.is_open() and float(gate.get("_t")) > 0.97

## Shuts and locks the gate; true once it is shut and locked (call every frame until then - it waits
## while someone stands in the gateway).
func close_and_lock() -> bool:
	if gate == null:
		return true
	if gate.is_open():
		gate.request(false)
		return false
	if float(gate.get("_t")) > 0.01:
		return false
	if not gate.always_locked:
		gate.always_locked = true
		_click()
		secured.emit()
	return true

func is_secured() -> bool:
	return gate == null or (gate.always_locked and not gate.is_open() and float(gate.get("_t")) <= 0.01)

func _click() -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = load("res://assets/audio/lock_turn.wav")
	p.unit_size = 2.0
	p.max_distance = 14.0
	add_child(p)
	p.global_position = gate.global_position + Vector3(GATE_W, 1.0, 0)
	p.play()
	p.finished.connect(p.queue_free)
