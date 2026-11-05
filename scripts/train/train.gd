class_name Train
extends Node3D
## The whole train: the six units and the gangways between them. It stands still in the world (the
## landscape scrolls past it, see Scenery) and answers to TrainState: before departure it shuts
## every exterior door. The locomotive turns its own wheels from TrainState.distance and gets its
## chimney smoke here; the carriages' wheelsets (Wheelset_* nodes in each bogie) are rolled here; the sway of a running train is felt through the player's camera (the cars'
## collision stays put so walking stays solid).

## The train's extent in its own space (sleeper's tail to the locomotive's buffers), where no snow
## falls.
const BODY := AABB(Vector3(-84.6, -1.5, -1.6), Vector3(111.0, 6.4, 3.2))
const CHIMNEY_FALLBACK := Vector3(-20.5, 2.45, 0.0)

## Coach wheel radius on the tread (m): the wheelsets turn by distance / radius.
const COACH_WHEEL_R := 0.46

var smoke: LocoSmoke
var _wheelsets: Array[Node3D] = []
var _wheel_phase: Array[float] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var ts := get_node_or_null("/root/TrainState")
	if ts:
		ts.connect("departing", _on_departing)
	var loco := get_node_or_null("Locomotive6") as Node3D
	if loco:
		smoke = LocoSmoke.new()
		loco.add_child(smoke)
		var lip := loco.find_child("Chimney", true, false) as Node3D
		smoke.position = (loco.to_local(lip.global_position) + Vector3(0, 0.03, 0)) if lip else CHIMNEY_FALLBACK
	# Carriage wheelsets: turned about their axle (local X) as the train rolls. Marked dynamic so
	# the static-mesh merge leaves them alone.
	for car in get_children():
		if car == loco:
			continue
		for ws: Node in car.find_children("Wheelset_*", "Node3D", true, false):
			ws.set_meta("dynamic", true)
			_wheelsets.append(ws as Node3D)
			_wheel_phase.append(randf() * TAU)
	_shelter.call_deferred()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _wheelsets.is_empty():
		return
	var ts := get_node_or_null("/root/TrainState")
	if ts == null:
		return
	var a := fposmod(float(ts.get("distance")) / COACH_WHEEL_R, TAU)
	for i in _wheelsets.size():
		_wheelsets[i].rotation.x = a + _wheel_phase[i]

func _shelter() -> void:
	var w := get_tree().get_first_node_in_group("weather")
	if w:
		w.call("set_shelter", global_transform * BODY)

## Every door that must be shut while the train moves (the exterior doors).
func exterior_doors() -> Array:
	var out: Array = []
	for d in get_tree().get_nodes_in_group("train_door"):
		if is_ancestor_of(d) and bool(d.get("lock_while_moving")):
			out.append(d)
	return out

func all_doors() -> Array:
	var out: Array = []
	for d in get_tree().get_nodes_in_group("train_door"):
		if is_ancestor_of(d):
			out.append(d)
	return out

func _on_departing(_station: String) -> void:
	for d in exterior_doors():
		d.call("request", false)
