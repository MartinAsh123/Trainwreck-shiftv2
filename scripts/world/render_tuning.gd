class_name RenderTuning
extends Node
## Rendering cost control for the journey, applied once everything is built:
##   - car lights fade out with distance, and only cast shadows near the camera
##   - text labels and tiny parts (screws, rings, pins) cast no shadows
##   - each car's static parts are merged per material and spatial cell (StaticMerge)
## None of this changes what is seen close up; it removes work for things far away or too small
## to matter.

@export var light_fade_begin: float = 20.0       # lights start fading out (m from camera)
@export var light_fade_length: float = 8.0
@export var shadow_fade: float = 9.0              # shadows only from lights this close
@export var tiny_part: float = 0.06               # parts smaller than this cast no shadow (m)
@export var merge_static: bool = true
@export var label_range: float = 18.0             # text signs fade out beyond this (m)
@export var occluders: bool = true

var report := {}

func _ready() -> void:
	_apply.call_deferred()

func _apply() -> void:
	# Let the cars and their props finish building.
	await get_tree().process_frame
	await get_tree().process_frame
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	if train == null:
		return
	var t0 := Time.get_ticks_msec()
	var lights := 0
	for l: Node in train.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D:
			continue
		var light := l as Light3D
		light.distance_fade_enabled = true
		light.distance_fade_begin = light_fade_begin
		light.distance_fade_length = light_fade_length
		light.distance_fade_shadow = shadow_fade
		lights += 1
	var labels := 0
	for lb: Node in train.find_children("*", "Label3D", true, false):
		var l3 := lb as Label3D
		l3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Signs and lettering are unreadable beyond ~15 m: fade them out there (one draw each).
		l3.visibility_range_end = label_range
		l3.visibility_range_end_margin = 3.0
		l3.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		labels += 1
	var tiny := 0
	for n: Node in train.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab := mi.global_transform * mi.get_aabb()
		if ab.size[ab.size.max_axis_index()] < tiny_part:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tiny += 1
	report = {"lights_faded": lights, "labels_no_shadow": labels, "tiny_no_shadow": tiny}
	if merge_static:
		for car: Node in train.get_children():
			if not (car is Node3D) or car is Locomotive:
				continue
			var keep: Array = []
			for cs: Node in car.find_children("*", "CurtainSet", true, false):
				for c: Array in cs.get("curtains"):
					keep.append(c[0])
				for r: Array in cs.get("rings"):
					keep.append(r[0])
				for t: Node in cs.get("ties"):
					keep.append(t)
			var r := StaticMerge.merge(car as Node3D, keep)
			report[car.name] = r
	if occluders:
		var count := 0
		for car: Node in train.get_children():
			if car is PassengerCar:
				count += _end_wall_occluders(car as PassengerCar)
		report["occluders"] = count
	report["ms"] = Time.get_ticks_msec() - t0
	print("[RenderTuning] ", report)

# Box occluders inside each solid end wall, leaving the gangway doorway open, so that from inside
# a car the other cars are culled except what shows through the door.
func _end_wall_occluders(car: PassengerCar) -> int:
	var inv := car.global_transform.affine_inverse()
	var hw: float = car.call("_inner_half_width") - 0.04
	var top: float = car.call("_eave_y") - 0.05
	var made := 0
	for d: Node in car.find_children("*", "TrainDoor", true, false):
		if str(d.get("door_name")) != "gangway door":
			continue
		var marker := (d as Node3D).get_parent() as Node3D
		var p := inv * marker.global_position
		var shape := d.get_node_or_null("DoorShape") as CollisionShape3D
		var dw: float = (shape.shape as BoxShape3D).size.x if shape else 0.9
		var dh: float = car.door_height
		var z0 := p.z - dw * 0.5 - 0.06
		var z1 := p.z + dw * 0.5 + 0.06
		var boxes := [
			[Vector3(p.x, top * 0.5, (-hw + z0) * 0.5), Vector3(0.03, top, z0 + hw)],      # beside the door
			[Vector3(p.x, top * 0.5, (z1 + hw) * 0.5), Vector3(0.03, top, hw - z1)],       # other side
			[Vector3(p.x, (dh + 0.06 + top) * 0.5, p.z), Vector3(0.03, top - dh - 0.06, z1 - z0)],   # above
		]
		for b: Array in boxes:
			var size: Vector3 = b[1]
			if size.y <= 0.05 or size.z <= 0.05:
				continue
			var oc := OccluderInstance3D.new()
			oc.name = "EndWallOccluder"
			var bo := BoxOccluder3D.new()
			bo.size = size
			oc.occluder = bo
			oc.position = b[0]
			car.add_child(oc)
			made += 1
	return made
