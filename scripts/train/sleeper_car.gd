@tool
class_name SleeperCar
extends PassengerCar
## Sleeping car: the PassengerCar body (shell, exterior, vestibule, W.C. end, doors, windows) with a
## side corridor along the -Z wall in place of the seating saloon. From the boarding end: the
## service room (linen, toilet supplies, cleaning things; set linen_length > 0 for a separate
## linen store behind it) and the passenger
## compartments, each with two single beds across the car (2 berths) and a sliding door.

@export_group("Sleeper")
## Clear width of the side corridor (along the -Z wall).
@export var corridor_width: float = 0.85:
	set(v): corridor_width = v; _queue_rebuild()
@export var compartments: int = 4:
	set(v): compartments = v; _queue_rebuild()
@export var attendant_length: float = 2.38:
	set(v): attendant_length = v; _queue_rebuild()
@export var linen_length: float = 0.0:
	set(v): linen_length = v; _queue_rebuild()
## Thickness of the corridor wall and the walls between rooms.
@export var room_wall: float = 0.08:
	set(v): room_wall = v; _queue_rebuild()
## Bed width after fitting (two beds + a clear middle for the door).
@export var bed_width: float = 0.8:
	set(v): bed_width = v; _queue_rebuild()
@export var compartment_door_scene: PackedScene = preload("res://assets/props/sleeper/door_compartment_hd.tscn"):
	set(v): compartment_door_scene = v if v != null else preload("res://assets/props/sleeper/door_compartment_hd.tscn"); _queue_rebuild()
const DEFAULT_BED_SCENE := preload("res://assets/props/sleeper/bed_single.tscn")
## Bed model (falls back to the single bed when empty: the editor can blank exported scene slots
## when it saves a scene while this script is being reloaded).
@export var bed_scene: PackedScene = DEFAULT_BED_SCENE:
	set(v): bed_scene = v if v != null else DEFAULT_BED_SCENE; _queue_rebuild()

## Ceiling light in the compartments.
@export var compartment_lamp_scene: PackedScene = preload("res://assets/props/lamps/lamp_ceiling.tscn"):
	set(v): compartment_lamp_scene = v if v != null else preload("res://assets/props/lamps/lamp_ceiling.tscn"); _queue_rebuild()
## Small table under each compartment window.
@export var compartment_table_scene: PackedScene = preload("res://assets/props/tables/table_steampunk.tscn"):
	set(v): compartment_table_scene = v if v != null else preload("res://assets/props/tables/table_steampunk.tscn"); _queue_rebuild()
## Wall card/ticket holder above each bed head.
@export var card_holder_scene: PackedScene = preload("res://assets/props/sleeper/card_holder.tscn"):
	set(v): card_holder_scene = v if v != null else preload("res://assets/props/sleeper/card_holder.tscn"); _queue_rebuild()
## Coat hook board (walnut board with brass double hooks), one either side of each compartment door.
@export var coat_hook_scene: PackedScene = preload("res://assets/props/sleeper/coat_hook.tscn"):
	set(v): coat_hook_scene = v if v != null else preload("res://assets/props/sleeper/coat_hook.tscn"); _queue_rebuild()
## Switch panel beside each compartment door (room side).
@export var switch_panel_scene: PackedScene = preload("res://assets/props/sleeper/switch_panel.tscn"):
	set(v): switch_panel_scene = v if v != null else preload("res://assets/props/sleeper/switch_panel.tscn"); _queue_rebuild()

const BERTHS_PER_COMPARTMENT := 2
const VENT_Y := 2.12          # centre height of the vents above the room doors
const HOOK_Y := 1.66          # coat hook rail height

var _door_info := {}

# ————— layout —————

func _has_center_aisle() -> bool:
	return false

# Bins between the corridor door and the fire extinguisher / toilet wall.
func _bin_z() -> float:
	return 0.25

func _aisle_z() -> float:
	return -_inner_half_width() + corridor_width * 0.5

# The corridor's outer wall leans in above the sill, so the saloon doors (with their architrave)
# are centred on the clear width at the top of the door frame, not on the floor.
func _partition_door_z(_end_sign: float) -> float:
	var wall := -(_outer_wall_z(door_height + 0.08) - wall_thickness)
	return (wall + _corridor_face()) * 0.5

func _door_trim_width() -> float:
	return 0.04

func _door_head_overhang() -> float:
	return 0.0

# Saloon doors slide into the partition on the compartment side (+Z), away from the outer wall.
func _inner_door_pocket(_end_sign: float) -> float:
	return -1.0

func _corridor_wall_z() -> float:
	return -_inner_half_width() + corridor_width + room_wall * 0.5

# Corridor-side and room-side faces of the corridor wall.
func _corridor_face() -> float:
	return _corridor_wall_z() - room_wall * 0.5

func _room_face() -> float:
	return _corridor_wall_z() + room_wall * 0.5

# Rooms from the boarding end: {kind, n, x0, x1} with x0 < x1 (inner faces of the room walls).
func _rooms() -> Array:
	var bs := _boarding_sign()
	var span := _saloon_end() - _saloon_start()
	var lengths: Array = [["attendant", 0, attendant_length]]
	if linen_length > 0.01:
		lengths.append(["linen", 0, linen_length])
	var walls := lengths.size() + compartments - 1
	var comp := (span - attendant_length - (linen_length if linen_length > 0.01 else 0.0) - walls * room_wall) / maxf(compartments, 1)
	for i in compartments:
		lengths.append(["compartment", i + 1, comp])
	var rooms: Array = []
	var x := _saloon_start() if bs < 0.0 else _saloon_end()
	var dir := -bs
	for r in lengths:
		var x_far: float = x + dir * r[2]
		rooms.append({"kind": r[0], "n": r[1], "x0": minf(x, x_far), "x1": maxf(x, x_far)})
		x = x_far + dir * room_wall
	return rooms

func _room_center(r: Dictionary) -> float:
	return (r.x0 + r.x1) * 0.5

# Door centre along X for a room with a corridor door (none for the linen store).
func _room_door_x(r: Dictionary) -> float:
	if r.kind == "attendant":
		# Away from the partition, leaving wall space there for notices and shelving.
		var away := -_boarding_sign()
		if linen_length > 0.01:
			return (r.x1 if away > 0.0 else r.x0) - away * (_door_leaf().w * 0.5 + 0.12)
		return (r.x0 if away > 0.0 else r.x1) + away * (r.x1 - r.x0) * 0.62
	return _room_center(r)

# Windows: the attendant's room and every compartment, the same X on both sides.
func _window_xs() -> Array[float]:
	var xs: Array[float] = []
	for r in _rooms():
		if r.kind != "linen":
			xs.append(_room_center(r))
	xs.sort()
	return xs

# Runner along the corridor.
func _carpet_size() -> Vector2:
	# Narrower than the corridor so it stays clear of the doors' floor tracks.
	return Vector2(_saloon_end() - _saloon_start() - 2.0 * (DOOR_TRACK_RAMP + 0.028), corridor_width - 0.32)

# ————— compartment door prefab measurements —————

# Leaf of the surface-mounted sliding door: x range and top (below the overhead track), and on
# which side (prefab X sign) the track runs on beyond the leaf.
func _door_leaf() -> Dictionary:
	if not _door_info.is_empty():
		return _door_info
	var info := {"x0": -0.3, "x1": 0.3, "top": 1.9, "rail_side": 1.0, "w": 0.6, "c": 0.0,
			"back": 0.04, "front": -0.04, "rail_x0": -0.6, "rail_x1": 0.6, "foot_z0": -0.05, "foot_z1": 0.05}
	if compartment_door_scene == null:
		_door_info = info
		return info
	# Measured on a temporary instance inside the tree (freeing an unparented instance with
	# meshes makes the renderer complain about missing materials).
	var d := compartment_door_scene.instantiate() as Node3D
	add_child(d)
	var pts: Array[Vector3] = []
	for mi: MeshInstance3D in d.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != d:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		# Every surface's vertices (Mesh.get_faces() leaves surfaces out on multi-material meshes).
		for si in mi.mesh.get_surface_count():
			for p: Vector3 in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				pts.append(xf * p)
	remove_child(d)
	d.queue_free()
	var lo := INF
	var hi := -INF
	var ymax := 0.0
	for p in pts:
		ymax = maxf(ymax, p.y)
		if p.y > 0.3 and p.y < 1.6:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	# The overhead track runs on past one edge of the leaf; its underside is the leaf's top.
	var rail_lo := INF
	var rail_sum := 0.0
	var rail_n := 0
	for p in pts:
		if (p.x < lo - 0.05 or p.x > hi + 0.05) and p.y > 1.0:
			rail_lo = minf(rail_lo, p.y)
			rail_sum += p.x
			rail_n += 1
	# Leaf body faces (above the handles), the track's length and the leaf's foot.
	var back := -INF
	var front := INF
	var rx0 := INF
	var rx1 := -INF
	var fz0 := INF
	var fz1 := -INF
	for p in pts:
		if p.y > 1.05 and p.y < 1.6:
			back = maxf(back, p.z)
			front = minf(front, p.z)
		if p.y > 1.92:
			rx0 = minf(rx0, p.x)
			rx1 = maxf(rx1, p.x)
		if p.y < 0.05:
			fz0 = minf(fz0, p.z)
			fz1 = maxf(fz1, p.z)
	if back > front:
		info.back = back
		info.front = front
	if rx1 > rx0:
		info.rail_x0 = rx0
		info.rail_x1 = rx1
	if fz1 > fz0:
		info.foot_z0 = fz0
		info.foot_z1 = fz1
	info.x0 = lo
	info.x1 = hi
	info.w = hi - lo
	info.c = (lo + hi) * 0.5
	info.top = rail_lo if rail_n > 0 else ymax - 0.08
	info.rail_side = signf(rail_sum / rail_n - info.c) if rail_n > 0 else 1.0
	_door_info = info
	return info

# ————— shell: corridor wall, room walls and door openings —————

func _add_interior_walls(shell: CSGCombiner3D) -> void:
	_door_info = {}
	var mat := interior_material
	var x0 := _saloon_start()
	var x1 := _saloon_end()
	var wi := _inner_half_width()
	var zc := _corridor_wall_z()
	_add_clipped_wall(shell, "CorridorWall", Vector3(x1 - x0, interior_height, room_wall),
			Vector3((x0 + x1) * 0.5, interior_height * 0.5, zc), mat)
	var rooms := _rooms()
	var depth := wi + 0.05 - zc
	for i in range(rooms.size() - 1):
		var a: Dictionary = rooms[i]
		var b: Dictionary = rooms[i + 1]
		var wx := (maxf(a.x0, b.x0) + minf(a.x1, b.x1)) * 0.5   # gap between the two rooms
		if a.x1 <= b.x0:
			wx = (a.x1 + b.x0) * 0.5
		else:
			wx = (b.x1 + a.x0) * 0.5
		_add_clipped_wall(shell, "RoomWall", Vector3(room_wall, interior_height, depth),
				Vector3(wx, interior_height * 0.5, zc + depth * 0.5), mat)
	var sub := CSGShape3D.OPERATION_SUBTRACTION
	var leaf := _door_leaf()
	var open_w: float = leaf.w - 0.05
	var open_h: float = minf(leaf.top - 0.03, door_height)
	for r in rooms:
		if r.kind == "linen":
			continue
		_add_box(shell, "RoomDoorCut", Vector3(open_w, open_h, room_wall * 3.0),
				Vector3(_room_door_x(r), open_h * 0.5, zc), trim_material, sub)
	# Doorway from the attendant's room into the linen store, by the corridor wall.
	if linen_length <= 0.01:
		return
	var lw := _linen_wall_x()
	_add_box(shell, "LinenDoorCut", Vector3(room_wall * 3.0, 1.9, 0.56),
			Vector3(lw, 0.95, _room_face() + 0.06 + 0.28), trim_material, sub)

# X of the wall between the attendant's room and the linen store.
func _linen_wall_x() -> float:
	var rooms := _rooms()
	var a: Dictionary = rooms[0]
	var b: Dictionary = rooms[1]
	return (a.x1 + b.x0) * 0.5 if a.x1 <= b.x0 else (b.x1 + a.x0) * 0.5

# ————— interior —————

func _build_seats(_anchors: Node3D) -> void:
	pass

func _build_tables(_anchors: Node3D) -> void:
	pass

func _build_racks(_anchors: Node3D) -> void:
	pass

func _build_extra(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Sleeper")
	var rooms := _rooms()
	var leaf := _door_leaf()
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	var berth := 1
	for r in rooms:
		var rx := _room_center(r)
		var room_z := (_room_face() + _inner_half_width()) * 0.5
		var tag: String = ("Compartment_%d" % r.n) if r.kind == "compartment" else r.kind.capitalize()
		# Ceiling lamp in every room (the compartments get their own fitting).
		var lamp := _room_lamp(group, "Lamp_" + tag, Vector3(rx, 0, room_z), 3.0 if r.kind == "compartment" else 2.4,
				0.7 if r.kind == "compartment" else 0.55, r.kind != "linen",
				compartment_lamp_scene if r.kind == "compartment" else lamp_scene)
		if r.kind == "linen":
			_doorway_lining(group, Vector3(_linen_wall_x(), 0, _room_face() + 0.06 + 0.28), 0.56, 1.9, true)
			_furnish_linen_store(group, r)
			continue
		var dx := _room_door_x(r)
		_hang_room_door(group, "Door_" + tag, dx, leaf)
		_door_vents(group, tag, dx)
		# Number plate and berth numbers on the corridor side, on the side away from the track.
		var px: float = dx - leaf.rail_side * (leaf.w * 0.5 + 0.16)
		var face := _corridor_face() - 0.004
		if r.kind == "compartment":
			_add_plate(group, "%d" % r.n, Vector3(px, 1.66, face), Vector3(0, 0, -1), "brass", false, 0.06)
			_add_plate(group, "BERTHS %d-%d" % [berth, berth + BERTHS_PER_COMPARTMENT - 1],
					Vector3(px, 1.5, face), Vector3(0, 0, -1), "brass", false, 0.017)
			_place_beds(group, r, berth)
			_compartment_fittings(group, r, dx, leaf, lamp)
			berth += BERTHS_PER_COMPARTMENT
		else:
			_add_plate(group, "SERVICE ROOM\nSTAFF ONLY", Vector3(px, 1.62, face), Vector3(0, 0, -1), "brass", false, 0.02)
			_furnish_service_room(group, r)
	_build_corridor(group, rooms)
	_build_ac_duct(group, rooms)

# Surface-mounted sliding door on the corridor face, its leaf centred on the opening, plus a
# walnut lining through the wall and an architrave on the room side.
func _hang_room_door(parent: Node3D, door_name: String, dx: float, leaf: Dictionary) -> void:
	var m := _add_marker(parent, door_name, Vector3(dx, 0, _corridor_face()))
	var d := _instance(m, compartment_door_scene)
	if d:
		# The leaf body (not the handles, which stand proud on both faces) runs DOOR_WALL_GAP off
		# the wall; the inner handle sits in the opening. Lifted to clear the floor track.
		d.position = Vector3(-leaf.c, DOOR_LIFT, -(leaf.back + DOOR_WALL_GAP))
		# The overhead track stays on the wall; only the leaf slides along it.
		_split_off_track(m, d, leaf)
		var door := _door_body(m, "SlidingDoor", d, Vector3.ZERO)
		door.kind = TrainDoor.Kind.SLIDE
		door.travel = Vector3(leaf.rail_side * leaf.w * 0.92, 0, 0)
		door.door_name = "door"
		var th: float = leaf.back - leaf.front
		_door_collision(door, Vector3(leaf.w - 0.02, leaf.top - DOOR_LIFT, th),
				Vector3(0, DOOR_LIFT + (leaf.top - DOOR_LIFT) * 0.5, -(leaf.back + DOOR_WALL_GAP) + (leaf.back + leaf.front) * 0.5))
	var open_w: float = leaf.w - 0.05
	var open_h: float = minf(leaf.top - 0.03, door_height)
	_doorway_lining(parent, Vector3(dx, 0, _corridor_wall_z()), open_w, open_h, false)
	_floor_track(parent, dx, leaf)

# Moves the door model's overhead track (everything above the leaf, or beside it) into a static
# mesh on `marker`, so that only the leaf moves when the door slides.
func _split_off_track(marker: Node3D, d: Node3D, leaf: Dictionary) -> void:
	for mi: MeshInstance3D in d.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != d:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var src: Mesh = mi.mesh
		var keep := ArrayMesh.new()
		var track := ArrayMesh.new()
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				idx = arr[Mesh.ARRAY_INDEX]
			else:
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var ki := PackedInt32Array()
			var ti := PackedInt32Array()
			for tri in range(0, idx.size(), 3):
				var c: Vector3 = xf * ((verts[idx[tri]] + verts[idx[tri + 1]] + verts[idx[tri + 2]]) / 3.0)
				var on_track: bool = c.y > leaf.top - 0.01 or c.x < leaf.x0 - 0.03 or c.x > leaf.x1 + 0.03
				if on_track:
					ti.append(idx[tri]); ti.append(idx[tri + 1]); ti.append(idx[tri + 2])
				else:
					ki.append(idx[tri]); ki.append(idx[tri + 1]); ki.append(idx[tri + 2])
			var mat := mi.get_active_material(si)
			if not ki.is_empty():
				var a := arr.duplicate()
				a[Mesh.ARRAY_INDEX] = ki
				keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
				keep.surface_set_material(keep.get_surface_count() - 1, mat)
			if not ti.is_empty():
				var b := arr.duplicate()
				b[Mesh.ARRAY_INDEX] = ti
				track.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b)
				track.surface_set_material(track.get_surface_count() - 1, mat)
		if track.get_surface_count() == 0:
			continue
		mi.mesh = keep
		var tm := MeshInstance3D.new()
		tm.name = "DoorTrack"
		tm.mesh = track
		tm.transform = d.transform * xf
		marker.add_child(tm)

const DOOR_WALL_GAP := 0.005
const DOOR_LIFT := 0.008

# Floor guide under a surface sliding door, as long as its overhead track: a dark channel along
# the foot of the wall that the leaf's foot runs in, with a brass lip on the corridor side.
func _floor_track(parent: Node3D, dx: float, leaf: Dictionary) -> void:
	var face := _corridor_face()
	var leaf_z: float = face - (leaf.back + DOOR_WALL_GAP)       # prefab z = 0 in the car
	var x0: float = dx + leaf.rail_x0 - leaf.c
	var x1: float = dx + leaf.rail_x1 - leaf.c
	var xm := (x0 + x1) * 0.5
	var len := x1 - x0
	var lip_z: float = leaf_z + leaf.foot_z0 - 0.006               # just clear of the leaf's foot
	var bronze := _mat(Color(0.18, 0.13, 0.08))
	bronze.metallic = 0.7
	bronze.roughness = 0.5
	_add_mesh(parent, "FloorTrackBase", Vector3(len, 0.004, face - lip_z), Vector3(xm, 0.002, (face + lip_z) * 0.5), bronze)
	_add_mesh(parent, "FloorTrackGroove", Vector3(len, 0.001, 0.008), Vector3(xm, 0.0045, leaf_z), _mat(Color(0.015, 0.012, 0.01)))
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_mesh(parent, "FloorTrackLip", Vector3(len, 0.012, 0.005), Vector3(xm, 0.006, lip_z - 0.0025), brass)
	# Rounded-off ends of the lip.
	for ex in [x0, x1]:
		_add_mesh(parent, "FloorTrackEnd", Vector3(0.006, 0.012, face - lip_z + 0.005), Vector3(ex, 0.006, (face + lip_z) * 0.5 - 0.0025), brass)

# Lining (head and jambs through the wall) and a room-side architrave for an opening.
# `across_x` = the opening is in a wall running across the car (normal along X).
func _doorway_lining(parent: Node3D, c: Vector3, w: float, h: float, across_x: bool) -> void:
	var n := Node3D.new()
	n.name = "DoorLining"
	n.position = c
	if across_x:
		n.rotation.y = PI * 0.5
	parent.add_child(n)
	var t := room_wall
	_add_mesh(n, "LiningHead", Vector3(w, 0.012, t), Vector3(0, h - 0.006, 0), trim_material)
	for sx in [-1.0, 1.0]:
		_add_mesh(n, "LiningJamb", Vector3(0.012, h, t), Vector3(sx * (w * 0.5 - 0.006), h * 0.5, 0), trim_material)
	for fz in ([t * 0.5 + 0.01, -t * 0.5 - 0.01] if across_x else [t * 0.5 + 0.01]):
		_add_mesh(n, "ArchHead", Vector3(w + 0.14, 0.06, 0.02), Vector3(0, h + 0.03, fz), trim_material)
		for sx in [-1.0, 1.0]:
			_add_mesh(n, "ArchJamb", Vector3(0.05, h, 0.02), Vector3(sx * (w * 0.5 + 0.025), h * 0.5, fz), trim_material)

# Two single beds across the compartment, one along each end wall, the head toward the window
# (the bed prefab's long axis is its Z, head at +Z). Fitted to the room and to `bed_width`.
func _place_beds(parent: Node3D, r: Dictionary, first_berth: int) -> void:
	var scene: PackedScene = bed_scene if bed_scene != null else DEFAULT_BED_SCENE
	var zr := _room_face() + 0.015
	var i := 0
	for side in [-1.0, 1.0]:
		var wall_x: float = r.x0 if side < 0.0 else r.x1
		var m := _add_marker(parent, "Bed_%d_%s" % [r.n, "A" if side < 0.0 else "B"], Vector3(wall_x, 0, 0))
		var b := _instance(m, scene)
		if b:
			var e := _local_extent(b)
			# Length: from the corridor wall to the outer wall at the headboard's height.
			var avail := (_outer_wall_z(e.end.y) - wall_thickness) - zr - 0.01
			var len_scale := minf(1.0, avail / e.size.z)
			var w_scale := minf(1.0, bed_width / e.size.x)
			b.scale = Vector3(w_scale, 1.0, len_scale)
			b.position = Vector3(-(e.position.x + e.size.x * 0.5) * w_scale, 0, -(e.position.z + e.size.z * 0.5) * len_scale)
			m.position = Vector3(wall_x - side * (e.size.x * w_scale * 0.5 + 0.01), 0, zr + e.size.z * len_scale * 0.5)
		m.set_meta("berth", first_berth + i)
		m.set_meta("compartment", r.n)
		i += 1

# Mesh bounds of a node in its own (unscaled) space.
func _local_extent(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != node:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

func _room_lamp(parent: Node3D, lamp_name: String, pos: Vector3, light_range: float, energy: float, shadows: bool,
		scene: PackedScene = null) -> Node3D:
	pos.y = _ceiling_y(pos.z)
	var m := _add_marker(parent, lamp_name, pos)
	m.basis = _ceiling_basis(pos.z)
	var lamp := _instance(m, scene if scene != null else lamp_scene)
	if lamp:
		# The fitting must not shadow itself from its own bulb (its rim would go black).
		for mi: MeshInstance3D in lamp.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		m.add_child(_lamp_placeholder())
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position.y = -0.3
	light.omni_range = light_range
	light.light_energy = energy
	light.light_color = Color(1.0, 0.9, 0.74)
	# Falls off faster than the default: pools of lamplight with the corners and the floor
	# between the lamps in shade.
	light.omni_attenuation = 1.8
	light.shadow_enabled = shadows
	m.add_child(light)
	return m

# Wall switch `ls` (built by _light_switch) made to work: it switches `lamps` (room lamp markers,
# kept out of the static merge so their glass can go dark).
func _wire_switch(ls: Node3D, lamps: Array) -> void:
	if Engine.is_editor_hint():         # the switch script only runs in the game
		return
	ls.set_script(preload("res://scripts/train/light_switch.gd"))
	for l: Node3D in lamps:
		if l:
			l.set_meta("dynamic", true)
			ls.lamps.append(l)
	if ls.is_inside_tree():
		ls.setup()

# ————— fittings —————

# Vents above a room door: a ceiling-coloured louvre block on the corridor side and the air-vent
# grille on the room side (the same duct through the wall).
# Room-side air vent above a door, fed by the corridor's AC duct through the wall.
func _door_vents(parent: Node3D, tag: String, dx: float) -> void:
	if vent_scene != null:
		var m := _add_marker(parent, "RoomVent_" + tag, Vector3(dx, VENT_Y, _room_face()))
		m.rotation.y = PI          # marker -Z faces into the room (+Z)
		var v := _instance(m, vent_scene)
		if v:
			_front_off_wall(v, 0.006)
			_vent_frame(m, 0.32, 0.19)

# Air-conditioning duct in the corridor: a moulded cove casing swept along the corner of the
# corridor wall and the ceiling, in the ceiling's cream enamel (shaders/train/duct_casing). Over
# every room door it dips down to the door head (the branch into that room's vent through the
# wall); under the roof AC unit it swells into the supply plenum; at its ends it fades into the
# corner like a cornice return.
const DUCT_SHADER := preload("res://shaders/train/duct_casing.gdshader")
const DUCT_DEPTH := 0.15
const DUCT_BOTTOM := 2.11
const DUCT_DROP_BOTTOM := 2.045
const DUCT_DROP_W := 0.5

func _build_ac_duct(parent: Node3D, rooms: Array) -> void:
	var g := Node3D.new()
	g.name = "ACDuct"
	parent.add_child(g)
	var cf := _corridor_face()
	var door_xs: Array[float] = []
	for r in rooms:
		if r.kind != "linen":
			door_xs.append(_room_door_x(r))
	door_xs.sort()
	var ax := _ac_x()
	var x0 := maxf(minf(door_xs[0] - DUCT_DROP_W, ax - 0.5), _saloon_start() + 0.05)
	var x1 := minf(maxf(door_xs[door_xs.size() - 1] + DUCT_DROP_W, ax + 0.5), _saloon_end() - 0.05)
	var top_wall := _ceiling_y(cf)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.015
	var rings := int(ceil((x1 - x0) / step)) + 1
	var per_ring := 0
	for i in rings:
		var x := minf(x0 + i * step, x1)
		var dip := 0.0
		for dx in door_xs:
			dip = maxf(dip, 1.0 - smoothstep(DUCT_DROP_W * 0.5, DUCT_DROP_W * 0.5 + 0.12, absf(x - dx)))
		var plen := 1.0 - smoothstep(0.22, 0.36, absf(x - ax))
		var e := smoothstep(x0, x0 + 0.3, x) * (1.0 - smoothstep(x1 - 0.3, x1, x))
		var d := lerpf(0.025, DUCT_DEPTH + 0.08 * plen, e)
		var yb := lerpf(top_wall - 0.03, lerpf(DUCT_BOTTOM, DUCT_DROP_BOTTOM, maxf(dip, plen)), e)
		var lean := 0.012 * e
		var prof := _duct_profile(cf, d, yb, lean)
		per_ring = prof.size()
		var total := 0.0
		for j in range(1, prof.size()):
			total += prof[j].distance_to(prof[j - 1])
		var sv := 0.0
		for j in prof.size():
			if j > 0:
				sv += prof[j].distance_to(prof[j - 1])
			var pz: Vector2 = prof[j]
			st.set_color(Color(dip, plen, 0.0, 1.0))
			st.set_uv(Vector2(x, sv))
			st.set_uv2(Vector2(total, pz.y - yb))
			st.add_vertex(Vector3(x, pz.y, pz.x))
	for i in rings - 1:
		for j in per_ring - 1:
			var a := i * per_ring + j
			var b := a + per_ring
			var c := a + 1
			var dd := b + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(dd)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Casing"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = DUCT_SHADER
	mi.material_override = mat
	g.add_child(mi)

	# Supply plenum fittings: maker's plate on its face and a damper lever below.
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	var pd := DUCT_DEPTH + 0.08
	var front_top := _ceiling_y(absf(cf - pd + 0.012))
	var py := (front_top + DUCT_DROP_BOTTOM + 0.05) * 0.5
	_add_plate(g, "AIR CONDITIONING", Vector3(ax, py, cf - pd + 0.003), Vector3(0, 0, -1), "brass", false, 0.013)
	var lz := cf - pd * 0.5
	var ly := DUCT_DROP_BOTTOM
	_add_cylinder(g, "DamperBoss", 0.012, 0.006, Vector3(ax + 0.12, ly - 0.003, lz), brass).rotation = Vector3(0, 0, 0)
	_add_rod(g, "DamperSpindle", Vector3(ax + 0.12, ly - 0.004, lz), Vector3(ax + 0.12, ly - 0.03, lz), 0.005, brass)
	_add_rod(g, "DamperLever", Vector3(ax + 0.12, ly - 0.03, lz), Vector3(ax + 0.05, ly - 0.03, lz - 0.03), 0.004, brass)
	_add_ball(g, "DamperKnob", Vector3(ax + 0.05, ly - 0.03, lz - 0.03), 0.009, brass)

# Cross-section of the duct casing as (z, y) points from its top (inside the ceiling) down the
# front, round the lower edge and back along the underside into the wall.
func _duct_profile(cf: float, d: float, yb: float, lean: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var zf := cf - d
	var top := _ceiling_y(absf(zf + lean)) + 0.02
	var r := minf(0.05, minf(d * 0.4, maxf(top - 0.02 - yb, 0.0) * 0.45))
	var n_front := 8
	for k in n_front:
		var t := float(k) / n_front
		pts.append(Vector2(lerpf(zf + lean, zf, t) - 0.006 * sin(PI * t), lerpf(top, yb + r, t)))
	var n_arc := 9
	for k in n_arc + 1:
		var a := PI * 0.5 * float(k) / n_arc
		pts.append(Vector2(zf + r - r * cos(a), yb + r - r * sin(a)))
	# Underside, curving up slightly into a small fillet at the wall.
	pts.append(Vector2(lerpf(zf + r, cf, 0.55), yb))
	pts.append(Vector2(cf - 0.012, yb + 0.002))
	pts.append(Vector2(cf + 0.006, yb + 0.012))
	return pts

# Compartment fittings on the corridor wall (room side) and under the window.
func _compartment_fittings(parent: Node3D, r: Dictionary, dx: float, leaf: Dictionary, lamp: Node3D = null) -> void:
	var rf := _room_face()
	var group := Node3D.new()
	group.name = "Fittings_%d" % r.n
	parent.add_child(group)
	var open_half: float = (leaf.w - 0.05) * 0.5 + 0.05      # opening plus architrave
	# Coat hook boards either side of the door, above the bed feet.
	var row_w := 0.38
	for sx in [-1.0, 1.0]:
		var hm := _add_marker(group, "CoatHooks_%s" % ("A" if sx < 0.0 else "B"),
				Vector3(dx + sx * (open_half + 0.1 + row_w * 0.5), HOOK_Y, rf + 0.002))
		hm.rotation.y = PI      # marker -Z = into the room
		var h := _instance(hm, coat_hook_scene)
		if h:
			_back_to_wall(h)
			# The thin hooks only cast a blurry smear on the wall at this lamp distance.
			for mi: MeshInstance3D in h.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_double_hook(hm)
	# Switch panel (left of the door from inside) and the light switch by the door's pull.
	var sp := _add_marker(group, "SwitchPanel", Vector3(dx - open_half - 0.2, 1.08, rf + 0.002))
	sp.rotation.y = PI
	var spn := _instance(sp, switch_panel_scene)
	if spn:
		_back_to_wall(spn)
	else:
		_switch_panel(sp)
	var ls := Node3D.new()
	ls.name = "LightSwitch"
	ls.position = Vector3(dx + open_half + 0.09, 1.15, rf + 0.002)
	ls.rotation.y = PI
	group.add_child(ls)
	_light_switch(ls)
	_wire_switch(ls, [lamp])
	# Card holders on the end walls, above the bed heads.
	if card_holder_scene != null:
		for side in [-1.0, 1.0]:
			var wall_x: float = r.x0 if side < 0.0 else r.x1
			var m := _add_marker(group, "CardHolder_%s" % ("A" if side < 0.0 else "B"),
					Vector3(wall_x - side * 0.003, 1.28, _inner_half_width() - 0.42))
			m.rotation.y = side * PI * 0.5
			var c := _instance(m, card_holder_scene)
			if c:
				_back_to_wall(c)
	# Table under the window, between the beds.
	if compartment_table_scene != null:
		var m := _add_marker(group, "Table", Vector3(_room_center(r), 0, 0))
		var t := _instance(m, compartment_table_scene)
		if t:
			var e := _local_extent(t)
			var sx_scale := minf(1.0, 0.5 / e.size.x)
			var sz_scale := minf(1.0, 0.4 / e.size.z)
			t.scale = Vector3(sx_scale, 1.0, sz_scale)
			t.position = Vector3(-(e.position.x + e.size.x * 0.5) * sx_scale, 0, -e.end.z * sz_scale)
			m.position.z = _inner_half_width() - 0.004

# Built-in brass double coat hook (local -Z = out of the wall), used until a hook model is set.
func _double_hook(n: Node3D) -> void:
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_mesh(n, "HookPlate", Vector3(0.022, 0.05, 0.004), Vector3(0, 0, -0.002), brass)
	var a := Vector3(0, 0, -0.004)
	_add_rod(n, "HookUpper", a, a + Vector3(0, 0.045, -0.055), 0.004, brass)
	_add_rod(n, "HookLower", a, a + Vector3(0, -0.03, -0.035), 0.0045, brass)
	_add_ball(n, "HookTip", a + Vector3(0, 0.045, -0.055), 0.007, brass)
	_add_ball(n, "HookTip", a + Vector3(0, -0.03, -0.035), 0.008, brass)

# Light switch in the style of the switch panel (local -Z = out of the wall): rounded ivory
# enamel plate in a brass bead, a brown bakelite rocker with brass end lines in a dark surround,
# and brass slot screws either side.
func _light_switch(n: Node3D) -> void:
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.26
	var ivory := _mat(Color(0.97, 0.94, 0.82))
	ivory.roughness = 0.12
	ivory.metallic_specular = 0.7
	ivory.clearcoat_enabled = true
	ivory.clearcoat = 0.7
	ivory.clearcoat_roughness = 0.1
	var bakelite := _mat(Color(0.2, 0.09, 0.06))
	bakelite.roughness = 0.2
	bakelite.clearcoat_enabled = true
	bakelite.clearcoat = 0.8
	bakelite.clearcoat_roughness = 0.08
	var surround := _mat(Color(0.12, 0.05, 0.035))
	surround.roughness = 0.35
	var w := 0.085
	var h := 0.105
	var r := 0.008
	# Domed enamel: a raised inner panel on the plate, like the switch panel's.
	_add_rounded_prism(n, "Plate", Transform3D.IDENTITY, w - 0.004, h - 0.004, r, 0.006, -0.003, ivory)
	_add_rounded_prism(n, "PlateDome", Transform3D.IDENTITY, w - 0.014, h - 0.014, r * 0.7, 0.003, -0.0075, ivory)
	_add_frame_ring(n, "Bead", w - 0.006, h - 0.006, r, 0.0035, 0.01, -0.005, brass)
	# Rocker: dark surround, brown rocker tilted (top pressed in = on) with brass lines at its ends.
	_add_mesh(n, "RockerSurround", Vector3(0.027, 0.047, 0.003), Vector3(0, 0, -0.0105), surround)
	var rocker := Node3D.new()
	rocker.name = "Rocker"
	rocker.position = Vector3(0, 0, -0.0135)
	rocker.rotation.x = deg_to_rad(8.0)
	n.add_child(rocker)
	_add_mesh(rocker, "Body", Vector3(0.021, 0.041, 0.007), Vector3.ZERO, bakelite)
	for sy in [-1.0, 1.0]:
		_add_mesh(rocker, "BrassLine", Vector3(0.015, 0.0022, 0.0008), Vector3(0, sy * 0.0165, -0.0037), brass)
	for sx in [-1.0, 1.0]:
		_add_screw(n, Vector3(sx * (w * 0.5 - 0.011), 0, -0.008), 0.0032, brass)

# Built-in switch panel (used until a switch panel model is assigned): walnut board with a brass
# plate, three bakelite toggles and their engraved names.
func _switch_panel(n: Node3D) -> void:
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.28
	var bakelite := _mat(Color(0.03, 0.025, 0.02))
	bakelite.roughness = 0.25
	var w := 0.2
	var h := 0.12
	_add_mesh(n, "Board", Vector3(w, h, 0.018), Vector3(0, 0, -0.009), trim_material)
	_add_mesh(n, "Plate", Vector3(w - 0.025, h - 0.025, 0.003), Vector3(0, 0, -0.0195), brass)
	var names := ["LAMP", "READING", "STEWARD"]
	for i in 3:
		var x := (i - 1) * 0.055
		var boss := _add_cylinder(n, "Boss", 0.009, 0.006, Vector3(x, 0.012, -0.024), bakelite)
		boss.rotation = Vector3(PI * 0.5, 0, 0)
		_add_rod(n, "Toggle", Vector3(x, 0.012, -0.026), Vector3(x, 0.024, -0.04), 0.004, bakelite)
		_add_ball(n, "ToggleTip", Vector3(x, 0.024, -0.04), 0.005, bakelite)
		var l := Label3D.new()
		l.name = "Caption"
		l.text = names[i]
		l.font = _sign_font()
		l.font_size = 64
		l.pixel_size = 0.0055 / (64.0 * SIGN_CAP_RATIO)
		l.modulate = Color(0.15, 0.1, 0.04)
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		l.render_priority = 1
		l.position = Vector3(x, -0.027, -0.0215)
		l.rotation.y = PI
		n.add_child(l)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_add_screw(n, Vector3(sx * (w * 0.5 - 0.022), sy * (h * 0.5 - 0.02), -0.021), 0.0028, brass)

# ————— service room and linen store —————

var _svc_mats := {}

func _svc_mat(key: String) -> StandardMaterial3D:
	if _svc_mats.has(key):
		return _svc_mats[key]
	var m: StandardMaterial3D
	match key:
		"linen": m = _mat(Color(0.95, 0.94, 0.9)); m.roughness = 0.95
		"linen2": m = _mat(Color(0.9, 0.89, 0.84)); m.roughness = 0.95
		"blanket": m = _mat(Color(0.47, 0.55, 0.36)); m.roughness = 1.0
		"towel": m = _mat(Color(0.93, 0.88, 0.76)); m.roughness = 1.0
		"stripe": m = _mat(Color(0.55, 0.12, 0.1)); m.roughness = 0.9
		"paper": m = _mat(Color(0.97, 0.96, 0.93)); m.roughness = 0.9
		"core": m = _mat(Color(0.55, 0.42, 0.27))
		"wrap": m = _mat(Color(0.86, 0.8, 0.62)); m.roughness = 0.8
		"wrap2": m = _mat(Color(0.62, 0.72, 0.8)); m.roughness = 0.8
		"tin": m = _mat(Color(0.62, 0.64, 0.66)); m.metallic = 0.8; m.roughness = 0.35
		"enamel_red": m = _mat(Color(0.6, 0.1, 0.08)); m.roughness = 0.3
		"glass_brown": m = _mat(Color(0.28, 0.14, 0.05)); m.roughness = 0.1; m.metallic_specular = 0.8
		"glass_green": m = _mat(Color(0.12, 0.3, 0.16)); m.roughness = 0.1; m.metallic_specular = 0.8
		"cap": m = _mat(Color(0.08, 0.07, 0.06)); m.roughness = 0.4
		"wicker": m = _mat(Color(0.62, 0.48, 0.28)); m.roughness = 0.95
		"mophead": m = _mat(Color(0.82, 0.79, 0.7)); m.roughness = 1.0
		"bristle": m = _mat(Color(0.18, 0.13, 0.08)); m.roughness = 1.0
		"dark": m = _mat(Color(0.12, 0.08, 0.05)); m.roughness = 0.6
		"rubber": m = _mat(Color(0.45, 0.12, 0.08)); m.roughness = 0.75
		"enamel_green": m = _mat(Color(0.1, 0.24, 0.15)); m.roughness = 0.35; m.metallic = 0.3
		_: m = _mat(Color(1, 0, 1))
	_svc_mats[key] = m
	return m

# A furniture frame on a wall: origin on the wall at floor level, local -Z out of the wall.
func _wall_frame(parent: Node3D, frame_name: String, pos: Vector3, facing: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = frame_name
	n.position = pos
	n.rotation.y = atan2(-facing.x, -facing.z)
	parent.add_child(n)
	return n

func _furniture_body(n: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	n.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	body.add_child(cs)

func _cyl_v(parent: Node3D, cname: String, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = cname
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 20
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi, true)
	return mi

func _furnish_service_room(parent: Node3D, r: Dictionary) -> void:
	var g := Node3D.new()
	g.name = "ServiceRoom"
	parent.add_child(g)
	var bs := _boarding_sign()
	var dir := -bs                                        # from the partition into the room (X)
	var part_x: float = r.x0 if bs < 0.0 else r.x1
	var far_x: float = r.x1 if bs < 0.0 else r.x0
	var rf := _room_face()
	var wi := _inner_half_width()
	# Everything stands against the walls; the middle of the room and the way in stay clear.
	# Corridor wall, between the partition and the door: open shelving with W.C. supplies.
	var sh := _wall_frame(g, "SupplyShelves", Vector3(part_x + dir * 0.5, 0, rf), Vector3(0, 0, 1))
	_shelf_unit(sh, 0.9, 0.34, 1.85, 5, "supplies")
	# Partition wall: tall linen shelves (sheets, blankets, towels, pillows).
	var ls := _wall_frame(g, "LinenShelves", Vector3(part_x, 0, 0.42), Vector3(dir, 0, 0))
	_shelf_unit(ls, 1.1, 0.38, 2.0, 6, "linen")
	# Far wall, beside the door: the tall walnut linen cupboard.
	var cup := _wall_frame(g, "LinenCupboard", Vector3(far_x, 0, 0.45), Vector3(-dir, 0, 0))
	_tall_cupboard(cup, 0.8, 0.5, 1.95)
	# Under the window: chest of drawers with supplies set out on top.
	var cx: float = (r.x0 + r.x1) * 0.5
	var ch := _wall_frame(g, "Drawers", Vector3(cx, 0, wi), Vector3(0, 0, -1))
	_chest(ch, 0.8, 0.45, 0.76)
	_chest_top(ch, 0.8, 0.45, 0.76)
	# Corners by the window: laundry hamper (far side), mop bucket and broom (partition side).
	var ham := _wall_frame(g, "Hamper", Vector3(far_x, 0, 1.2), Vector3(-dir, 0, 0))
	_hamper(ham)
	var bk := _wall_frame(g, "MopBucket", Vector3(part_x + dir * 0.6, 0, wi), Vector3(0, 0, -1))
	_mop_bucket(bk)
	var br := _wall_frame(g, "Broom", Vector3(part_x, 0, 1.36), Vector3(dir, 0, 0))
	_broom(br)
	# Toilet plunger standing by the broom, dustpan hung on the wall above it.
	var pl := _wall_frame(g, "Plunger", Vector3(part_x, 0, 1.1), Vector3(dir, 0, 0))
	_plunger(pl)
	var dp := _wall_frame(g, "Dustpan", Vector3(part_x, 0, 1.13), Vector3(dir, 0, 0))
	_dustpan(dp)

func _furnish_linen_store(parent: Node3D, r: Dictionary) -> void:
	var g := Node3D.new()
	g.name = "LinenStore"
	parent.add_child(g)
	var bs := _boarding_sign()
	var far_x: float = r.x1 if bs < 0.0 else r.x0
	var sh := _wall_frame(g, "LinenShelves", Vector3(far_x, 0, 0.72), Vector3(bs, 0, 0))
	_shelf_unit(sh, 1.22, 0.4, 2.0, 6, "linen")

# Walnut cupboard: plinth, carcass, cornice and two panelled doors with brass knobs and a lock.
func _tall_cupboard(n: Node3D, w: float, d: float, h: float) -> void:
	var wood := trim_material
	var dark := _svc_mat("dark")
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_mesh(n, "Plinth", Vector3(w - 0.03, 0.08, d - 0.03), Vector3(0, 0.04, -d * 0.5 + 0.005), dark)
	_add_mesh(n, "Carcass", Vector3(w, h - 0.13, d), Vector3(0, 0.08 + (h - 0.13) * 0.5, -d * 0.5), wood)
	_add_mesh(n, "Cornice", Vector3(w + 0.05, 0.035, d + 0.035), Vector3(0, h - 0.0325, -(d + 0.035) * 0.5), wood)
	_add_mesh(n, "CorniceBead", Vector3(w + 0.03, 0.015, d + 0.02), Vector3(0, h - 0.058, -(d + 0.02) * 0.5), dark)
	var dw := w * 0.5 - 0.02
	var dh := h - 0.24
	for sx in [-1.0, 1.0]:
		var x: float = sx * (dw * 0.5 + 0.006)
		var yc := 0.1 + dh * 0.5
		_add_mesh(n, "Door", Vector3(dw, dh, 0.02), Vector3(x, yc, -d - 0.01), wood)
		for k in 2:
			var ph := (dh - 0.12) * (0.62 if k == 0 else 0.38)
			var py := 0.1 + 0.05 + (ph * 0.5 if k == 1 else (dh - 0.12) * 0.38 + 0.02 + ph * 0.5)
			_add_mesh(n, "DoorPanel", Vector3(dw - 0.09, ph - 0.04, 0.012), Vector3(x, py, -d - 0.024), wood)
			_add_mesh(n, "PanelShadow", Vector3(dw - 0.075, ph - 0.025, 0.004), Vector3(x, py, -d - 0.021), dark)
		_add_ball(n, "Knob", Vector3(sx * 0.035, 0.1 + dh * 0.52, -d - 0.03), 0.013, brass)
	_add_mesh(n, "Escutcheon", Vector3(0.016, 0.03, 0.003), Vector3(0.035, 0.1 + dh * 0.45, -d - 0.021), brass)
	_add_plate(n, "LINEN", Vector3(0, h - 0.11, -d - 0.021), Vector3(0, 0, -1), "brass", false, 0.016)
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

# Chest of drawers: four drawers with brass cup pulls and card frames, overhanging top.
func _chest(n: Node3D, w: float, d: float, h: float) -> void:
	var wood := trim_material
	var dark := _svc_mat("dark")
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_mesh(n, "Plinth", Vector3(w - 0.02, 0.07, d - 0.02), Vector3(0, 0.035, -d * 0.5), dark)
	_add_mesh(n, "Carcass", Vector3(w, h - 0.1, d), Vector3(0, 0.07 + (h - 0.1) * 0.5, -d * 0.5), wood)
	_add_mesh(n, "Top", Vector3(w + 0.03, 0.03, d + 0.02), Vector3(0, h - 0.015, -(d + 0.02) * 0.5), wood)
	var rows := 4
	var dh := (h - 0.13) / rows
	for i in rows:
		var y := 0.08 + dh * (i + 0.5)
		_add_mesh(n, "DrawerGap", Vector3(w - 0.03, 0.004, 0.002), Vector3(0, 0.08 + dh * i, -d - 0.001), dark)
		_add_mesh(n, "Drawer", Vector3(w - 0.04, dh - 0.012, 0.016), Vector3(0, y, -d - 0.008), wood)
		for sx in [-1.0, 1.0]:
			var px: float = sx * w * 0.27
			_add_rod(n, "Pull", Vector3(px - 0.04, y, -d - 0.028), Vector3(px + 0.04, y, -d - 0.028), 0.004, brass)
			for ex in [-0.04, 0.04]:
				_add_rod(n, "PullPost", Vector3(px + ex, y, -d - 0.016), Vector3(px + ex, y, -d - 0.028), 0.003, brass)
		_add_mesh(n, "CardFrame", Vector3(0.06, 0.024, 0.003), Vector3(0, y + 0.012, -d - 0.018), brass)
		_add_mesh(n, "Card", Vector3(0.05, 0.016, 0.001), Vector3(0, y + 0.012, -d - 0.0195), _svc_mat("paper"))
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

# On the chest: a pyramid of toilet rolls, the tool box (for the AC repair) and bottles.
func _chest_top(n: Node3D, w: float, d: float, h: float) -> void:
	var y := h
	var zc := -d * 0.5
	var rows := [3, 2, 1]
	for lvl in rows.size():
		var cnt: int = rows[lvl]
		for i in cnt:
			_toilet_roll(n, Vector3(-w * 0.32 + (i - (cnt - 1) * 0.5) * 0.105, y + lvl * 0.1, zc + 0.04))
	_toolbox(n, Vector3(0.03, y, zc))
	var bx := w * 0.3
	_bottle(n, Vector3(bx, y, zc - 0.06), "glass_brown", 0.22)
	_bottle(n, Vector3(bx + 0.08, y, zc - 0.04), "glass_green", 0.18)
	_tin(n, Vector3(bx + 0.02, y, zc + 0.09), 0.045, 0.12, "enamel_red")

# Open walnut shelf unit, filled per `kind` ("supplies" or "linen").
func _shelf_unit(n: Node3D, w: float, d: float, h: float, shelves: int, kind: String) -> void:
	var wood := trim_material
	var dark := _svc_mat("dark")
	_add_mesh(n, "Back", Vector3(w, h, 0.012), Vector3(0, h * 0.5, -0.006), dark)
	for sx in [-1.0, 1.0]:
		_add_mesh(n, "Side", Vector3(0.02, h, d), Vector3(sx * (w * 0.5 - 0.01), h * 0.5, -d * 0.5), wood)
	_add_mesh(n, "Cap", Vector3(w + 0.03, 0.025, d + 0.02), Vector3(0, h - 0.0125, -(d + 0.02) * 0.5), wood)
	var gap := (h - 0.1) / shelves
	for i in shelves + 1:
		var y := 0.08 + gap * i
		if y > h - 0.03:
			break
		_add_mesh(n, "Shelf", Vector3(w - 0.04, 0.02, d - 0.01), Vector3(0, y - 0.01, -d * 0.5 - 0.005), wood)
		_add_mesh(n, "ShelfLip", Vector3(w - 0.04, 0.03, 0.012), Vector3(0, y - 0.005, -d + 0.006), wood)
		if i == shelves or y + gap > h:
			continue
		_fill_shelf(n, kind, i, y, w - 0.06, d - 0.04, gap - 0.04)
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

func _fill_shelf(n: Node3D, kind: String, i: int, y: float, w: float, d: float, room: float) -> void:
	var zc := -d * 0.5 - 0.02
	if kind == "linen":
		# Sheets, pillowcases and blankets in neat stacks, pillows on the top shelf.
		var palettes := [["linen", "linen2"], ["blanket"], ["linen"], ["towel"], ["linen2", "linen"], ["blanket"]]
		var cols := int(w / 0.3)
		for c in cols:
			var x := -w * 0.5 + (c + 0.5) * w / cols
			var cnt := int(minf(room / 0.03, 8.0)) - (c + i) % 3
			if i == 5:
				_pillow(n, Vector3(x, y, zc), Vector2(w / cols - 0.03, d - 0.04))
			else:
				_folded_stack(n, Vector3(x, y, zc), Vector2(w / cols - 0.04, d - 0.06), cnt, palettes[i % palettes.size()], i % 2 == 0)
		return
	match i:
		0:
			# Bottom: a bucket of cleaning powder tins and a crate of bottles.
			for k in 3:
				_tin(n, Vector3(-w * 0.3 + k * 0.12, y, zc), 0.05, 0.16, "tin" if k != 1 else "enamel_red")
			_bottle(n, Vector3(w * 0.3, y, zc - 0.04), "glass_brown", 0.24)
			_bottle(n, Vector3(w * 0.3 - 0.08, y, zc + 0.05), "glass_green", 0.2)
		1, 2:
			# Toilet rolls, two deep.
			for row in 2:
				for k in 4:
					if i == 2 and row == 1 and k == 3:
						continue
					_toilet_roll(n, Vector3(-w * 0.5 + 0.065 + k * 0.118, y, zc + (row - 0.5) * 0.13))
					if row == 0 and k < 3 and i == 1:
						_toilet_roll(n, Vector3(-w * 0.5 + 0.065 + k * 0.118, y + 0.102, zc - 0.065))
		3:
			# Hand towels and wrapped soap.
			_folded_stack(n, Vector3(-w * 0.22, y, zc), Vector2(0.24, 0.2), 6, ["towel"], true)
			for k in 5:
				_add_mesh(n, "Soap", Vector3(0.085, 0.03, 0.055), Vector3(w * 0.25, y + 0.015 + k * 0.031, zc),
						_svc_mat("wrap" if k % 2 == 0 else "wrap2"))
		_:
			# Spare sheets.
			_folded_stack(n, Vector3(0, y, zc), Vector2(w - 0.06, d - 0.06), 4, ["linen", "linen2"], false)

# A stack of folded textiles: slightly uneven layers, a darker fold line on each front edge,
# and an optional red stripe (railway towels).
func _folded_stack(n: Node3D, base: Vector3, size: Vector2, count: int, palette: Array, stripe: bool) -> void:
	if _folded_stack_hd(n, base, size, count, palette):
		return
	var t := 0.03
	for k in maxi(count, 1):
		var off := Vector3((hash_f(k, base.x) - 0.5) * 0.012, 0, (hash_f(k + 7, base.z) - 0.5) * 0.01)
		var m := _svc_mat(palette[k % palette.size()])
		var y := base.y + t * (k + 0.5)
		_add_mesh(n, "Fold", Vector3(size.x, t - 0.003, size.y), base + off + Vector3(0, y - base.y, 0), m)
		_add_mesh(n, "FoldEdge", Vector3(size.x - 0.006, 0.003, 0.004), base + off + Vector3(0, y - base.y + 0.008, -size.y * 0.5 - 0.001), _svc_mat("dark") if palette[0] == "blanket" else _svc_mat("linen2"))
		if stripe and palette[0] == "towel":
			_add_mesh(n, "Stripe", Vector3(0.02, t - 0.002, size.y + 0.002), base + off + Vector3(size.x * 0.3, y - base.y, 0), _svc_mat("stripe"))

# HD folded textiles (Blender, CC0 ambientCG fabrics): each layer is its own folded towel, sheet
# or blanket, scaled to the stack's footprint and stacked at its real thickness.
const _FOLDED_HD := {
	"towel": [["towel_folded", "towel_folded_cream"], Vector3(0.24, 0.032, 0.2)],
	"linen": [["sheet_folded"], Vector3(0.28, 0.026, 0.3)],
	"linen2": [["sheet_folded_ivory"], Vector3(0.28, 0.026, 0.3)],
	"blanket": [["blanket_folded", "blanket_folded_grey"], Vector3(0.3, 0.05, 0.32)],
}

func _folded_stack_hd(n: Node3D, base: Vector3, size: Vector2, count: int, palette: Array) -> bool:
	if HDProps.scene("towel_folded") == null:
		return false
	var y := base.y
	var top := base.y + maxi(count, 1) * 0.03 + 0.006    # the height the shelf leaves for this stack
	for k in maxi(count, 1):
		var spec: Array = _FOLDED_HD.get(palette[k % palette.size()], _FOLDED_HD["linen"])
		var names: Array = spec[0]
		var dim: Vector3 = spec[1]
		if k > 0 and y + dim.y > top:
			break
		var off := Vector3((hash_f(k, base.x) - 0.5) * 0.012, 0, (hash_f(k + 7, base.z) - 0.5) * 0.01)
		var rot := Vector3(0, (hash_f(k + 3, base.x) - 0.5) * 0.05, 0)
		var scl := Vector3(size.x / dim.x, 1.0, size.y / dim.z)
		HDProps.place(n, names[int(hash_f(k + 11, base.x + base.z) * names.size()) % names.size()],
				HDProps.xf(Vector3(base.x, y, base.z) + off, rot, scl), "Fold")
		y += dim.y
	return true

func hash_f(k: int, salt: float) -> float:
	return fposmod(sin(float(k) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)

func _pillow(n: Node3D, base: Vector3, size: Vector2) -> void:
	if HDProps.place(n, "pillow", HDProps.xf(base, Vector3(0, (hash_f(int(base.x * 100.0), 2.7) - 0.5) * 0.12, 0),
			Vector3(size.x / 0.36, 1.0, size.y / 0.26)), "Pillow"):
		return
	var mi := MeshInstance3D.new()
	mi.name = "Pillow"
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = _svc_mat("linen")
	mi.scale = Vector3(size.x, 0.1, size.y)
	mi.position = base + Vector3(0, 0.05, 0)
	n.add_child(mi)

func _toilet_roll(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "toilet_roll", HDProps.xf(base, Vector3(0, hash_f(int(base.x * 1000.0 + base.z * 100.0), 5.3) * TAU, 0)), "Roll"):
		return
	_cyl_v(n, "Roll", 0.052, 0.052, 0.1, base + Vector3(0, 0.05, 0), _svc_mat("paper"))
	_cyl_v(n, "RollCore", 0.019, 0.019, 0.1015, base + Vector3(0, 0.05, 0), _svc_mat("core"))

func _bottle(n: Node3D, base: Vector3, glass: String, h: float) -> void:
	var r := 0.035
	_cyl_v(n, "Bottle", r, r, h * 0.68, base + Vector3(0, h * 0.34, 0), _svc_mat(glass))
	_cyl_v(n, "Shoulder", 0.012, r, h * 0.14, base + Vector3(0, h * 0.75, 0), _svc_mat(glass))
	_cyl_v(n, "Neck", 0.012, 0.012, h * 0.12, base + Vector3(0, h * 0.88, 0), _svc_mat(glass))
	_cyl_v(n, "Cap", 0.014, 0.014, 0.025, base + Vector3(0, h * 0.95, 0), _svc_mat("cap"))
	_cyl_v(n, "Label", r + 0.001, r + 0.001, h * 0.25, base + Vector3(0, h * 0.35, 0), _svc_mat("wrap"))

func _tin(n: Node3D, base: Vector3, r: float, h: float, finish: String) -> void:
	_cyl_v(n, "Tin", r, r, h, base + Vector3(0, h * 0.5, 0), _svc_mat(finish))
	_cyl_v(n, "TinLid", r + 0.003, r + 0.003, 0.012, base + Vector3(0, h + 0.004, 0), _svc_mat("tin"))
	_cyl_v(n, "TinLabel", r + 0.001, r + 0.001, h * 0.4, base + Vector3(0, h * 0.5, 0), _svc_mat("paper"))

# Fitter's tool box: green enamelled steel, hinged lid with a raised rib, brass latches and
# corner caps, a folding bar handle and a stencilled plate.
func _toolbox(n: Node3D, base: Vector3) -> void:
	var g := Node3D.new()
	g.name = "ToolBox"
	g.position = base
	n.add_child(g)
	var body := _svc_mat("enamel_green")
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	var w := 0.36
	var d := 0.17
	_add_mesh(g, "Body", Vector3(w, 0.11, d), Vector3(0, 0.055, 0), body)
	_add_mesh(g, "Lid", Vector3(w + 0.008, 0.05, d + 0.008), Vector3(0, 0.137, 0), body)
	_add_mesh(g, "LidRib", Vector3(w - 0.06, 0.012, d - 0.07), Vector3(0, 0.166, 0), body)
	_add_mesh(g, "Seam", Vector3(w + 0.01, 0.004, d + 0.01), Vector3(0, 0.111, 0), _svc_mat("dark"))
	for sx in [-1.0, 1.0]:
		_add_mesh(g, "Latch", Vector3(0.03, 0.045, 0.006), Vector3(sx * w * 0.3, 0.108, -d * 0.5 - 0.005), brass)
		_add_mesh(g, "Hinge", Vector3(0.04, 0.02, 0.006), Vector3(sx * w * 0.3, 0.112, d * 0.5 + 0.005), brass)
		for sz in [-1.0, 1.0]:
			_add_mesh(g, "Corner", Vector3(0.022, 0.022, 0.022), Vector3(sx * (w * 0.5 - 0.008), 0.011, sz * (d * 0.5 - 0.008)), brass)
		_add_rod(g, "HandleArm", Vector3(sx * 0.07, 0.172, 0), Vector3(sx * 0.07, 0.2, 0), 0.004, brass)
	_add_rod(g, "Handle", Vector3(-0.07, 0.2, 0), Vector3(0.07, 0.2, 0), 0.007, trim_material)
	_add_plate(g, "TOOLS", Vector3(0, 0.06, -d * 0.5 - 0.004), Vector3(0, 0, -1), "brass", false, 0.012)

# Toilet plunger standing on its cup against the wall: turned wooden handle, red rubber cup.
func _plunger(n: Node3D) -> void:
	var c := Vector3(0, 0, -0.1)
	var rubber := _svc_mat("rubber")
	_cyl_v(n, "CupLip", 0.07, 0.072, 0.012, c + Vector3(0, 0.006, 0), rubber)
	_cyl_v(n, "Cup", 0.03, 0.068, 0.07, c + Vector3(0, 0.045, 0), rubber)
	_cyl_v(n, "Collar", 0.02, 0.03, 0.03, c + Vector3(0, 0.093, 0), rubber)
	_add_rod(n, "Handle", c + Vector3(0, 0.1, 0), c + Vector3(0, 0.62, 0), 0.012, trim_material)
	_add_ball(n, "HandleEnd", c + Vector3(0, 0.625, 0), 0.014, trim_material)

# Dustpan hung flat on the wall on a brass hook: galvanised tray with a raised back and sides,
# and a short wooden handle.
func _dustpan(n: Node3D) -> void:
	var galv := _svc_mat("tin")
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	var y := 1.0
	_add_mesh(n, "Tray", Vector3(0.26, 0.22, 0.004), Vector3(0, y, -0.012), galv)
	_add_mesh(n, "Back", Vector3(0.26, 0.012, 0.04), Vector3(0, y + 0.11, -0.03), galv)
	for sx in [-1.0, 1.0]:
		var side := _add_mesh(n, "Side", Vector3(0.004, 0.22, 0.03), Vector3(sx * 0.128, y, -0.025), galv)
		side.rotation.x = 0.12
	_add_rod(n, "Handle", Vector3(0, y + 0.11, -0.03), Vector3(0, y + 0.26, -0.03), 0.011, trim_material)
	_add_rod(n, "Hook", Vector3(0, y + 0.29, 0), Vector3(0, y + 0.29, -0.04), 0.004, brass)
	_add_rod(n, "HangLoop", Vector3(0, y + 0.26, -0.03), Vector3(0, y + 0.29, -0.035), 0.003, brass)

func _hamper(n: Node3D) -> void:
	var c := Vector3(0, 0, -0.22)
	if HDProps.place(n, "laundry_hamper", HDProps.xf(c), "Hamper"):
		_furniture_body(n, Vector3(0.4, 0.6, 0.4), c + Vector3(0, 0.3, 0))
		return
	_cyl_v(n, "Basket", 0.2, 0.17, 0.55, c + Vector3(0, 0.275, 0), _svc_mat("wicker"))
	for k in 5:
		_cyl_v(n, "Band", 0.172 + 0.006 * k, 0.172 + 0.006 * k, 0.012, c + Vector3(0, 0.05 + k * 0.11, 0), _svc_mat("dark"))
	var lid := _cyl_v(n, "Lid", 0.215, 0.215, 0.03, c + Vector3(0.05, 0.6, 0.03), _svc_mat("wicker"))
	lid.rotation.z = 0.35
	var sheet := _add_mesh(n, "DirtySheet", Vector3(0.3, 0.06, 0.24), c + Vector3(-0.02, 0.56, 0), _svc_mat("linen2"))
	sheet.rotation = Vector3(0.2, 0.4, -0.15)
	_furniture_body(n, Vector3(0.4, 0.6, 0.4), c + Vector3(0, 0.3, 0))

func _mop_bucket(n: Node3D) -> void:
	var c := Vector3(0, 0, -0.2)
	if HDProps.place(n, "mop_bucket", HDProps.xf(c), "MopBucket"):
		_furniture_body(n, Vector3(0.34, 0.32, 0.34), c + Vector3(0, 0.16, 0))
		return
	var galv := _svc_mat("tin")
	_cyl_v(n, "Bucket", 0.16, 0.13, 0.3, c + Vector3(0, 0.15, 0), galv)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.155
	tm.outer_radius = 0.168
	rim.mesh = tm
	rim.material_override = galv
	rim.position = c + Vector3(0, 0.3, 0)
	n.add_child(rim)
	_cyl_v(n, "Water", 0.15, 0.15, 0.01, c + Vector3(0, 0.24, 0), _svc_mat("dark"))
	# Mop standing in the bucket, leaning on the wall.
	var foot := c + Vector3(0.02, 0.2, 0.03)
	var tip := Vector3(0.05, 1.45, -0.03)
	_add_rod(n, "MopHandle", foot, tip, 0.012, trim_material)
	for k in 10:
		var a := k * TAU / 10.0
		var o := Vector3(cos(a) * 0.04, 0, sin(a) * 0.04)
		_add_rod(n, "MopStrand", foot + o * 0.4, foot + o * 2.2 + Vector3(0, -0.12, 0), 0.008, _svc_mat("mophead"))
	_furniture_body(n, Vector3(0.34, 0.32, 0.34), c + Vector3(0, 0.16, 0))

func _broom(n: Node3D) -> void:
	var head := Vector3(0.0, 0.05, -0.12)
	_add_mesh(n, "BroomStock", Vector3(0.28, 0.04, 0.05), head + Vector3(0, 0.07, 0), trim_material)
	_add_mesh(n, "Bristles", Vector3(0.27, 0.07, 0.045), head + Vector3(0, 0.02, 0), _svc_mat("bristle"))
	_add_rod(n, "BroomHandle", head + Vector3(0, 0.09, 0), Vector3(0, 1.4, -0.03), 0.012, trim_material)

# ————— corridor —————

func _build_corridor(parent: Node3D, rooms: Array) -> void:
	var group := _add_group(parent, "Corridor")
	var x0 := _saloon_start()
	var x1 := _saloon_end()
	var az := _aisle_z()
	# Ceiling lamps along the corridor (their shadows only near the camera: RenderTuning), tilted
	# with the ceiling's curve.
	var n_lamps := 2
	for i in n_lamps:
		var lx := lerpf(x0, x1, (i + 0.5) / n_lamps)
		var m := _add_marker(group, "Lamp_Corridor_%d" % (i + 1), Vector3(lx, _ceiling_y(az), az))
		m.basis = _ceiling_basis(az)
		m.set_meta("dynamic", true)          # switched from the staff cabinet: not merged
		if not _instance(m, lamp_scene):
			m.add_child(_lamp_placeholder())
		var light := OmniLight3D.new()
		light.name = "Light"
		light.position.y = -0.3
		light.omni_range = 4.6
		light.light_energy = 0.95
		light.light_color = Color(1.0, 0.9, 0.74)
		# Falls off faster than the default: pools of lamplight with the corners and the floor
		# between the lamps in shade.
		light.omni_attenuation = 1.8
		light.shadow_enabled = true
		m.add_child(light)

	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3

	var bs := _boarding_sign()
	var face := _corridor_face() - 0.004
	# NO SMOKING with its pictogram near each end, on the corridor wall.
	var att: Dictionary = rooms[0]
	var last: Dictionary = rooms[rooms.size() - 1]
	var leaf := _door_leaf()
	for k in 2:
		var r: Dictionary = att if k == 0 else last
		var cx: float
		if k == 0:
			# Attendant's room: its door sits toward the linen store; the free wall is by the partition.
			cx = (r.x0 if bs < 0.0 else r.x1) - bs * 0.24
		else:
			# Last compartment: the wall beside its door, on the side away from the door track.
			var dx := _room_door_x(r)
			var free_dir: float = -leaf.rail_side
			var free_edge: float = dx + free_dir * (leaf.w * 0.5)
			var wall_end: float = r.x0 if free_dir < 0.0 else r.x1
			cx = (free_edge + wall_end) * 0.5
		var w := _add_plate(group, "NO SMOKING", Vector3(cx - 0.07, 1.84, face), Vector3(0, 0, -1), "brass", false, 0.024)
		_add_symbol_plate(group, "NoSmokingSymbol", Vector3(cx - 0.07 + w * 0.5 + 0.015 + 0.045, 1.84, face),
				Vector3(0, 0, -1), 0.09, NO_SMOKING_SHADER)

	# Route board on the corridor wall between the partition and the service room door.
	var rbx: float = (att.x0 if bs < 0.0 else att.x1) - bs * 0.42
	var board := _notice_board(group, "RouteBoard", Vector3(rbx, 1.41, face), Vector3(0, 0, -1), 0.7, 0.42)
	_draw_route(board, 0.7, 0.42)

	# Emergency brakes on the outer wall piers: by the linen store and between the last two compartments.
	var wxs := _window_xs()
	var brake_xs: Array[float] = [(wxs[0] + wxs[1]) * 0.5 if bs < 0.0 else (wxs[wxs.size() - 1] + wxs[wxs.size() - 2]) * 0.5]
	var i := 0
	for bx in brake_xs:
		i += 1
		_corridor_brake(group, "EmergencyBrake_%d" % i, bx)

# Emergency brake with its signs on the leaning outer wall of the corridor, facing in.
func _corridor_brake(parent: Node3D, brake_name: String, bx: float) -> void:
	var wall := _window_xform(bx, 1.45, -1.0)
	var frame := Node3D.new()
	frame.name = brake_name + "_Wall"
	frame.transform = Transform3D(wall.basis, wall.origin - wall.basis.z * (wall_thickness * 0.5))
	parent.add_child(frame)
	var m := _add_marker(frame, brake_name, Vector3(0, 0, -0.004))
	var b := _instance(m, emergency_brake_scene)
	if b:
		_back_to_wall(b)
	else:
		m.add_child(_emergency_brake_placeholder())
	_add_plate(frame, "EMERGENCY\nBRAKE", Vector3(0, 0.33, -0.004), Vector3(0, 0, -1), "red", false, 0.026)
	_add_plate(frame, "WARNING\nIMPROPER USE IS PUNISHABLE\nBY A FINE AND MAY LEAD TO\nCRIMINAL PROSECUTION",
			Vector3(0, -0.27, -0.004), Vector3(0, 0, -1), "red", false, 0.016)
