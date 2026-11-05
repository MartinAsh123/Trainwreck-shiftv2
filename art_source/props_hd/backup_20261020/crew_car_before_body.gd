@tool
class_name CrewCar
extends SleeperCar

const HDProps := preload("res://scripts/train/hd_props.gd")
## Crew car: the PassengerCar body (shell, exterior, vestibule, W.C. end, doors, windows) with the
## sleeping car's side corridor along the -Z wall and two staff rooms off it. From the boarding end:
## the train guard's room (bunk, desk, steel locker, safe, key cabinet, duty roster) and the
## carriage inspector's own room - Kevin's (bed, wardrobe, washstand, writing desk, telephone,
## shift calendar). Each room has a door in the middle of its corridor wall, a sleeping end and a
## working end, two windows and two ceiling lamps.
## Kevin's room carries empty Marker3D slots (meta "item_slot") for the items he can order between
## shifts: "refrigerator", "plant" and "bed" (the bed marker, for the better bed).

@export_group("Crew")
## Length of the guard's room along the car (0 = half the space; the inspector's room takes the rest).
@export var guard_room_length: float = 0.0:
	set(v): guard_room_length = v; _queue_rebuild()
## Plate on the guard's door (corridor side) and the line under it.
@export var guard_door_title: String = "GUARD":
	set(v): guard_door_title = v; _queue_rebuild()
@export var guard_door_note: String = "TRAIN SECURITY\nSTAFF ONLY":
	set(v): guard_door_note = v; _queue_rebuild()
## Plate on the inspector's (Kevin's) door and the line under it.
@export var inspector_door_title: String = "INSPECTOR":
	set(v): inspector_door_title = v; _queue_rebuild()
@export var inspector_door_note: String = "CARRIAGE INSPECTOR\nPRIVATE":
	set(v): inspector_door_note = v; _queue_rebuild()

const MIN_ROOM := 2.6           # shortest room that still fits a bed end and a desk end
const DESK_W := 1.0
const DESK_D := 0.58
const DESK_H := 0.76

# ————— layout —————

# Rooms from the boarding end: {kind, n, x0, x1} with x0 < x1 (inner faces of the walls).
func _rooms() -> Array:
	var bs := _boarding_sign()
	var span := _saloon_end() - _saloon_start() - room_wall
	var g := guard_room_length if guard_room_length > 0.0 else span * 0.5
	g = clampf(g, MIN_ROOM, maxf(span - MIN_ROOM, MIN_ROOM))
	var lengths: Array = [["guard", 1, g], ["inspector", 2, span - g]]
	var rooms: Array = []
	var x := _saloon_start() if bs < 0.0 else _saloon_end()
	var dir := -bs
	for r in lengths:
		var x_far: float = x + dir * r[2]
		rooms.append({"kind": r[0], "n": r[1], "x0": minf(x, x_far), "x1": maxf(x, x_far)})
		x = x_far + dir * room_wall
	return rooms

# Both room doors sit in the middle of their corridor wall.
func _room_door_x(r: Dictionary) -> float:
	return _room_center(r)

# X of the wall between the two rooms.
func _middle_wall_x() -> float:
	var rooms := _rooms()
	var a: Dictionary = rooms[0]
	var b: Dictionary = rooms[1]
	return (a.x1 + b.x0) * 0.5 if a.x1 <= b.x0 else (b.x1 + a.x0) * 0.5

# Distance of a room's window centres from its end walls (a quarter of the room).
func _win_inset(r: Dictionary) -> float:
	var l: float = r.x1 - r.x0
	return clampf(l * 0.25, window_width * 0.5 + 0.35, 1.6)

# Two windows per room (one in a short room), the same X on both sides of the car.
func _window_xs() -> Array[float]:
	var xs: Array[float] = []
	for r in _rooms():
		var x0: float = r.x0
		var x1: float = r.x1
		if x1 - x0 < 2.0 * (window_width + 0.6):
			xs.append((x0 + x1) * 0.5)
			continue
		var inset := _win_inset(r)
		xs.append(x0 + inset)
		xs.append(x1 - inset)
	xs.sort()
	return xs

# ————— shell: corridor wall, the wall between the rooms, door openings —————

func _add_interior_walls(shell: CSGCombiner3D) -> void:
	_door_info = {}
	var mat := interior_material
	var x0 := _saloon_start()
	var x1 := _saloon_end()
	var zc := _corridor_wall_z()
	_add_clipped_wall(shell, "CorridorWall", Vector3(x1 - x0, interior_height, room_wall),
			Vector3((x0 + x1) * 0.5, interior_height * 0.5, zc), mat)
	var depth := _inner_half_width() + 0.05 - zc
	_add_clipped_wall(shell, "RoomWall", Vector3(room_wall, interior_height, depth),
			Vector3(_middle_wall_x(), interior_height * 0.5, zc + depth * 0.5), mat)
	var leaf := _door_leaf()
	var open_w: float = leaf.w - 0.05
	var open_h: float = minf(leaf.top - 0.03, door_height)
	for r in _rooms():
		_add_box(shell, "RoomDoorCut", Vector3(open_w, open_h, room_wall * 3.0),
				Vector3(_room_door_x(r), open_h * 0.5, zc), trim_material, CSGShape3D.OPERATION_SUBTRACTION)

# ————— interior —————

func _build_extra(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Crew")
	var rooms := _rooms()
	var leaf := _door_leaf()
	var face := _corridor_face() - 0.004
	var room_z := (_room_face() + _inner_half_width()) * 0.5
	for r in rooms:
		var guard: bool = r.kind == "guard"
		var tag := "GuardRoom" if guard else "InspectorRoom"
		var g := _add_group(group, tag)
		var dx := _room_door_x(r)
		_hang_room_door(g, "Door", dx, leaf)
		_door_vents(g, tag, dx)
		# A lamp over each end of the room.
		var inset := _win_inset(r)
		_room_lamp(g, "Lamp_A", Vector3(r.x0 + inset, 0, room_z), 3.2, 0.85, true, compartment_lamp_scene)
		_room_lamp(g, "Lamp_B", Vector3(r.x1 - inset, 0, room_z), 3.2, 0.85, true, compartment_lamp_scene)
		# Door plates on the corridor side, on the side away from the door track.
		var px: float = dx - leaf.rail_side * (leaf.w * 0.5 + 0.16)
		_add_plate(g, guard_door_title if guard else inspector_door_title, Vector3(px, 1.66, face),
				Vector3(0, 0, -1), "brass", false, 0.03)
		_add_plate(g, guard_door_note if guard else inspector_door_note, Vector3(px, 1.5, face),
				Vector3(0, 0, -1), "brass", false, 0.016)
		_room_light_switch(g, dx, leaf)
		if guard:
			_furnish_guard_room(g, r)
		else:
			_furnish_inspector_room(g, r)
	_build_crew_corridor(group, rooms)
	_build_ac_duct(group, rooms)

# Light switch inside the room, beside the door's pull.
func _room_light_switch(parent: Node3D, dx: float, leaf: Dictionary) -> void:
	var open_half: float = (leaf.w - 0.05) * 0.5 + 0.05
	var ls := Node3D.new()
	ls.name = "LightSwitch"
	ls.position = Vector3(dx + open_half + 0.09, 1.15, _room_face() + 0.002)
	ls.rotation.y = PI
	parent.add_child(ls)
	_light_switch(ls)

# Ends of a room: the boarding-end wall ("near") and the other ("far"), with the direction from
# each into the room along X.
func _room_ends(r: Dictionary) -> Dictionary:
	var bs := _boarding_sign()
	return {
		"near": r.x0 if bs < 0.0 else r.x1, "near_in": -bs,
		"far": r.x1 if bs < 0.0 else r.x0, "far_in": bs,
	}

# ————— the guard's room: bunk by the boarding end, office by the middle wall —————

func _furnish_guard_room(g: Node3D, r: Dictionary) -> void:
	var e := _room_ends(r)
	var near_x: float = e.near
	var near_in: float = e.near_in
	var far_x: float = e.far
	var far_in: float = e.far_in
	var rf := _room_face()
	var wi := _inner_half_width()
	var inset := _win_inset(r)

	# Bunk along the boarding-end wall, its head under the window side; nightstand with a hand lamp.
	var bed := _crew_bed(g, "Bed", near_x, -near_in)
	var bed_w := _bed_span(bed)
	var ns := _wall_frame(g, "Nightstand", Vector3(near_x + near_in * (bed_w + 0.3), 0, wi), Vector3(0, 0, -1))
	_nightstand(ns, 0.42, 0.4, 0.58)
	_hand_lamp(ns, Vector3(0.06, 0.58, -0.2))
	# Coat hooks over the foot of the bunk: uniform cap and truncheon hanging on them.
	var hooks := _coat_hooks(g, "CoatHooks", Vector3(near_x + near_in * 0.42, HOOK_Y, rf + 0.002))
	_guard_cap(hooks, Vector3(0.0, 0.0, -0.11))
	# Truncheon on its own hook beside the board.
	var th := _coat_hooks(g, "TruncheonHook", Vector3(near_x + near_in * 0.82, HOOK_Y - 0.12, rf + 0.002))
	_truncheon(th, Vector3(0.0, 0.02, -0.04))

	# Office at the middle wall: desk under the window with a chair, the safe beside it.
	var desk := _wall_frame(g, "Desk", Vector3(far_x + far_in * inset, 0, wi), Vector3(0, 0, -1))
	_writing_desk(desk, DESK_W, DESK_D, DESK_H)
	_ledger(desk, Vector3(-0.08, DESK_H, -0.3), 0.15)
	_handcuffs(desk, Vector3(0.3, DESK_H, -0.36))
	_ink_stand(desk, Vector3(0.36, DESK_H, -0.12))
	_paper_stack(desk, Vector3(-0.36, DESK_H, -0.16), 0.35)
	var chair := _wall_frame(g, "Chair", Vector3(far_x + far_in * (inset + 0.06), 0, wi - DESK_D - 0.12), Vector3(0, 0, 1))
	chair.rotation.y += 0.12
	_chair(chair)
	var safe := _wall_frame(g, "Safe", Vector3(far_x + far_in * 0.4, 0, wi), Vector3(0, 0, -1))
	_strongbox(safe, 0.5, 0.48, 0.62)
	# Steel equipment locker against the middle wall, by the corridor wall.
	var lw := 0.76
	var locker := _wall_frame(g, "Locker", Vector3(far_x, 0, rf + 0.08 + lw * 0.5), Vector3(far_in, 0, 0))
	_steel_locker(locker, lw, 0.5, 1.9)
	# Wall telephone and clock on the middle wall between the locker and the window.
	_wall_phone(g, "Telephone", Vector3(far_x, 1.42, rf + 0.08 + lw + 0.3), Vector3(far_in, 0, 0))
	_wall_clock(g, Vector3(far_x, 1.9, rf + 0.08 + lw + 0.3), Vector3(far_in, 0, 0))
	# Key cabinet and duty roster on the corridor wall, between the locker and the door.
	var kc := _wall_frame(g, "KeyCabinet", Vector3(far_x + far_in * 1.12, 1.44, rf), Vector3(0, 0, 1))
	_key_cabinet(kc, 0.44, 0.5)
	var roster := _notice_board(g, "DutyRoster", Vector3(far_x + far_in * 1.82, 1.46, rf + 0.004), Vector3(0, 0, 1), 0.46, 0.6)
	_draw_duty_roster(roster, 0.46, 0.6)

# ————— the inspector's room (Kevin's): writing end by the middle wall, bed at the far end —————

func _furnish_inspector_room(g: Node3D, r: Dictionary) -> void:
	var e := _room_ends(r)
	# The middle wall is this room's boarding-side wall; the bed goes at the other end.
	var near_x: float = e.near
	var near_in: float = e.near_in
	var far_x: float = e.far
	var far_in: float = e.far_in
	var rf := _room_face()
	var wi := _inner_half_width()
	var inset := _win_inset(r)

	# Bed against the far wall (an item slot: the better bed replaces it).
	var bed := _crew_bed(g, "Bed", far_x, -far_in)
	bed.set_meta("item_slot", "bed")
	var bed_w := _bed_span(bed)
	var ns := _wall_frame(g, "Nightstand", Vector3(far_x + far_in * (bed_w + 0.3), 0, wi), Vector3(0, 0, -1))
	_nightstand(ns, 0.42, 0.4, 0.58)
	_alarm_clock(ns, Vector3(-0.08, 0.58, -0.22))
	_mug(ns, Vector3(0.1, 0.58, -0.14))
	_coat_hooks(g, "CoatHooks", Vector3(far_x + far_in * 0.42, HOOK_Y, rf + 0.002))
	# Empty slots for the items ordered at shift end (they arrive at the start of the next shift).
	var plant := _add_marker(g, "ItemSlot_Plant", Vector3(far_x + far_in * (bed_w + 0.95), 0, wi - 0.22))
	plant.set_meta("item_slot", "plant")
	var fridge := _add_marker(g, "ItemSlot_Refrigerator", Vector3(far_x + far_in * (bed_w + 0.75), 0, rf + 0.33))
	fridge.rotation.y = PI          # marker -Z (the fridge's front) faces into the room
	fridge.set_meta("item_slot", "refrigerator")
	# Rug in the middle of the floor.
	_rug(g, Vector3(_room_center(r), 0, (rf + wi) * 0.5 - 0.05), Vector2(1.8, 0.95))

	# Writing end: wardrobe and washstand on the middle wall, desk under the window.
	var ww := 0.8
	var wd := _wall_frame(g, "Wardrobe", Vector3(near_x, 0, wi - 0.1 - ww * 0.5), Vector3(near_in, 0, 0))
	_wardrobe(wd, ww, 0.55, 1.95)
	_washstand(g, Vector3(near_x, 0, rf + 0.42), Vector3(near_in, 0, 0), r)
	var desk := _wall_frame(g, "Desk", Vector3(near_x + near_in * inset, 0, wi), Vector3(0, 0, -1))
	_writing_desk(desk, DESK_W, DESK_D, DESK_H)
	_journal(desk, Vector3(-0.06, DESK_H, -0.3))
	_pager(desk, Vector3(0.24, DESK_H, -0.4))
	_ticket_punch(desk, Vector3(0.14, DESK_H, -0.2))
	_mug(desk, Vector3(-0.38, DESK_H, -0.42))
	_desk_lamp(desk, Vector3(0.36, DESK_H, -0.14))
	var chair := _wall_frame(g, "Chair", Vector3(near_x + near_in * (inset - 0.05), 0, wi - DESK_D - 0.12), Vector3(0, 0, 1))
	chair.rotation.y -= 0.1
	_chair(chair)
	# Telephone (the friend's calls come in here) and the shift calendar on the corridor wall.
	_wall_phone(g, "Telephone", Vector3(near_x + near_in * 0.98, 1.42, rf), Vector3(0, 0, 1))
	var cal := _notice_board(g, "ShiftCalendar", Vector3(near_x + near_in * 1.72, 1.46, rf + 0.004), Vector3(0, 0, 1), 0.44, 0.56)
	_draw_shift_calendar(cal, 0.44, 0.56)

# ————— corridor —————

func _build_crew_corridor(parent: Node3D, rooms: Array) -> void:
	var group := _add_group(parent, "Corridor")
	var x0 := _saloon_start()
	var x1 := _saloon_end()
	var az := _aisle_z()
	# Ceiling lamps (no shadows: light only), tilted with the ceiling's curve.
	var n_lamps := 3
	for i in n_lamps:
		var lx := lerpf(x0, x1, (i + 0.5) / n_lamps)
		var m := _add_marker(group, "Lamp_Corridor_%d" % (i + 1), Vector3(lx, _ceiling_y(az), az))
		m.basis = _ceiling_basis(az)
		if not _instance(m, lamp_scene):
			m.add_child(_lamp_placeholder())
		var light := OmniLight3D.new()
		light.name = "Light"
		light.position.y = -0.3
		light.omni_range = 4.6
		light.light_energy = 0.95
		light.light_color = Color(1.0, 0.94, 0.82)
		light.shadow_enabled = false
		m.add_child(light)

	var brass := _brass()

	var face := _corridor_face() - 0.004
	var leaf := _door_leaf()
	# NO SMOKING with its pictogram near both ends of the corridor wall.
	for cx in [x0 + 0.42, x1 - 0.62]:
		var w := _add_plate(group, "NO SMOKING", Vector3(cx, 1.84, face), Vector3(0, 0, -1), "brass", false, 0.024)
		_add_symbol_plate(group, "NoSmokingSymbol", Vector3(cx + w * 0.5 + 0.06, 1.84, face),
				Vector3(0, 0, -1), 0.09, NO_SMOKING_SHADER)
	# Route board on the guard's corridor wall, on the side of the door away from its track.
	var gr: Dictionary = rooms[0]
	var rx: float = _room_door_x(gr) - leaf.rail_side * 1.45
	var board := _notice_board(group, "RouteBoard", Vector3(rx, 1.41, face), Vector3(0, 0, -1), 0.7, 0.42)
	_draw_route(board, 0.7, 0.42)
	# Emergency brake on the outer wall's pier opposite the wall between the rooms.
	_corridor_brake(group, "EmergencyBrake_1", _middle_wall_x())

# ————— placement helpers —————

func _brass() -> StandardMaterial3D:
	var m := _mat(_c_brass)
	m.metallic = 0.85
	m.roughness = 0.3
	return m

# Wall-mounted marker: on the wall at `pos`, local -Z along `facing` (into the room).
func _wall_marker(parent: Node3D, marker_name: String, pos: Vector3, facing: Vector3) -> Marker3D:
	var m := _add_marker(parent, marker_name, pos)
	m.rotation.y = atan2(-facing.x, -facing.z)
	return m

# Single bed across the room against an end wall, head toward the window (the bed prefab's long
# axis is its Z, head at +Z), fitted between the corridor wall and the leaning outer wall.
# `side` = -1 for a wall at the room's x0 (the bed extends toward +X), +1 at x1.
func _crew_bed(parent: Node3D, bed_name: String, wall_x: float, side: float) -> Marker3D:
	var scene: PackedScene = bed_scene if bed_scene != null else DEFAULT_BED_SCENE
	var zr := _room_face() + 0.015
	var m := _add_marker(parent, bed_name, Vector3(wall_x, 0, 0))
	var b := _instance(m, scene)
	if b == null:
		return m
	var e := _local_extent(b)
	var avail := (_outer_wall_z(e.end.y) - wall_thickness) - zr - 0.01
	var len_scale := minf(1.0, avail / e.size.z)
	var w_scale := minf(1.0, bed_width / e.size.x)
	b.scale = Vector3(w_scale, 1.0, len_scale)
	b.position = Vector3(-(e.position.x + e.size.x * 0.5) * w_scale, 0, -(e.position.z + e.size.z * 0.5) * len_scale)
	var half_w := e.size.x * w_scale * 0.5
	m.position = Vector3(wall_x - side * (half_w + 0.01), 0, zr + e.size.z * len_scale * 0.5)
	m.set_meta("span", half_w * 2.0 + 0.01)
	# Mattress-height collision so the bed can't be walked through.
	var h := minf(e.size.y, 0.55)
	_furniture_body(m, Vector3(half_w * 2.0, h, e.size.z * len_scale), Vector3(0, h * 0.5, 0))
	return m

# How far a bed reaches out from its wall (bed_width when it has no model).
func _bed_span(bed: Marker3D) -> float:
	return bed.get_meta("span", bed_width + 0.01)

func _coat_hooks(parent: Node3D, hooks_name: String, pos: Vector3) -> Marker3D:
	var hm := _add_marker(parent, hooks_name, pos)
	hm.rotation.y = PI      # marker -Z = into the room
	var h := _instance(hm, coat_hook_scene)
	if h:
		_back_to_wall(h)
		for mi: MeshInstance3D in h.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_double_hook(hm)
	return hm

func _wall_phone(parent: Node3D, phone_name: String, pos: Vector3, facing: Vector3) -> void:
	var m := _wall_marker(parent, phone_name, pos, facing)
	var p := _instance(m, phone_scene)
	if p:
		_back_to_wall(p)
		# Walnut backboard behind the set.
		var body := _back_outline(p, 0.015)
		var board_t := 0.016
		p.position.z -= board_t
		var bc := body.get_center()
		_add_mesh(m, "Backboard", Vector3(body.size.x + 0.07, body.size.y + 0.08, board_t), Vector3(bc.x, bc.y, -board_t * 0.5), trim_material)

# Washstand prefab against a wall with the mirror above it, narrowed if wider than 0.62 m.
func _washstand(parent: Node3D, pos: Vector3, facing: Vector3, r: Dictionary) -> void:
	var m := _wall_marker(parent, "Washstand", pos, facing)
	var s := _instance(m, sink_scene)
	if s:
		var e := _local_extent(s)
		if e.size.x > 0.62:
			var k := 0.62 / e.size.x
			s.scale = Vector3(k, 1.0, k)
		_back_to_wall(s)
		s.position.z *= s.scale.z
	else:
		m.add_child(_sink_placeholder())
	var mm := _wall_marker(parent, "Mirror", pos + Vector3(facing.x * 0.005, 1.45, facing.z * 0.005), facing)
	var mirror := _instance(mm, mirror_scene)
	if mirror:
		_back_to_wall(mirror)
		var probe := ReflectionProbe.new()
		probe.name = "MirrorProbe"
		var x0: float = r.x0
		var x1: float = r.x1
		probe.size = Vector3(x1 - x0, interior_height, _inner_half_width() - _room_face())
		probe.position = Vector3((x0 + x1) * 0.5, interior_height * 0.5, (_inner_half_width() + _room_face()) * 0.5)
		probe.box_projection = true
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		parent.add_child(probe)

# ————— furniture (frames from _wall_frame: origin on the wall at floor level, -Z into the room) —————

var _crew_mats := {}

func _crew_mat(key: String) -> StandardMaterial3D:
	if _crew_mats.has(key):
		return _crew_mats[key]
	var m: StandardMaterial3D
	match key:
		"locker": m = _mat(Color(0.2, 0.26, 0.2)); m.metallic = 0.4; m.roughness = 0.55
		"iron": m = _mat(Color(0.07, 0.08, 0.07)); m.metallic = 0.5; m.roughness = 0.45
		"gold_line": m = _mat(Color(0.75, 0.6, 0.28)); m.metallic = 0.8; m.roughness = 0.35
		"steel": m = _mat(Color(0.55, 0.56, 0.58)); m.metallic = 0.9; m.roughness = 0.3
		"leather": m = _mat(Color(0.3, 0.13, 0.07)); m.roughness = 0.55
		"cloth_navy": m = _mat(Color(0.08, 0.1, 0.18)); m.roughness = 0.95
		"black": m = _mat(Color(0.03, 0.03, 0.03)); m.roughness = 0.4
		"lens_red": m = _mat(Color(0.5, 0.04, 0.03)); m.roughness = 0.1; m.emission_enabled = true; m.emission = Color(0.6, 0.05, 0.02); m.emission_energy_multiplier = 0.3
		"shade_green": m = _mat(Color(0.05, 0.3, 0.14)); m.roughness = 0.1; m.metallic_specular = 0.8
		"bulb": m = _mat(Color(1.0, 0.93, 0.75)); m.emission_enabled = true; m.emission = Color(1.0, 0.85, 0.6); m.emission_energy_multiplier = 2.0
		"lcd": m = _mat(Color(0.32, 0.4, 0.22)); m.emission_enabled = true; m.emission = Color(0.25, 0.35, 0.12); m.emission_energy_multiplier = 0.4
		"ink": m = _mat(Color(0.03, 0.03, 0.08)); m.roughness = 0.1
		"rug": m = _mat(Color(0.42, 0.1, 0.08)); m.roughness = 1.0
		"rug_border": m = _mat(Color(0.12, 0.18, 0.13)); m.roughness = 1.0
		"rug_fringe": m = _mat(Color(0.86, 0.8, 0.66)); m.roughness = 1.0
		"enamel_white": m = _mat(Color(0.93, 0.91, 0.86)); m.roughness = 0.2
		"clock_face": m = _mat(Color(0.95, 0.92, 0.82)); m.roughness = 0.5
		"book_red": m = _mat(Color(0.4, 0.07, 0.06)); m.roughness = 0.7
		"book_brown": m = _mat(Color(0.28, 0.17, 0.09)); m.roughness = 0.7
		_: return _svc_mat(key)
	_crew_mats[key] = m
	return m

func _writing_desk(n: Node3D, w: float, d: float, h: float) -> void:
	if HDProps.place(n, "writing_desk", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 1.0, h / 0.76, d / 0.58))):
		_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))
		return
	var wood := trim_material
	var dark := _svc_mat("dark")
	var brass := _brass()
	var top_t := 0.03
	_add_mesh(n, "Top", Vector3(w, top_t, d), Vector3(0, h - top_t * 0.5, -d * 0.5), wood)
	_add_mesh(n, "TopEdge", Vector3(w + 0.006, 0.008, d + 0.006), Vector3(0, h - top_t - 0.004, -d * 0.5), dark)
	# Drawer pedestal on the right (local +X), a single leg pair and a modesty panel on the left.
	var pw := 0.36
	var px := w * 0.5 - pw * 0.5 - 0.01
	var ph := h - top_t
	_add_mesh(n, "Pedestal", Vector3(pw, ph - 0.05, d - 0.04), Vector3(px, 0.05 + (ph - 0.05) * 0.5, -d * 0.5), wood)
	_add_mesh(n, "PedestalPlinth", Vector3(pw - 0.02, 0.05, d - 0.06), Vector3(px, 0.025, -d * 0.5), dark)
	var dh := (ph - 0.07) / 3.0
	for i in 3:
		var y := 0.06 + dh * (i + 0.5)
		_add_mesh(n, "Drawer", Vector3(pw - 0.03, dh - 0.012, 0.016), Vector3(px, y, -d + 0.012), wood)
		_add_rod(n, "Pull", Vector3(px - 0.05, y + dh * 0.15, -d - 0.008), Vector3(px + 0.05, y + dh * 0.15, -d - 0.008), 0.004, brass)
	for sz in [-0.04, -d + 0.04]:
		_add_mesh(n, "Leg", Vector3(0.04, ph, 0.04), Vector3(-w * 0.5 + 0.04, ph * 0.5, sz), wood)
	_add_mesh(n, "Stretcher", Vector3(0.025, 0.04, d - 0.1), Vector3(-w * 0.5 + 0.04, 0.12, -d * 0.5), wood)
	_add_mesh(n, "ModestyPanel", Vector3(w - pw - 0.08, 0.3, 0.018), Vector3(-pw * 0.5 + 0.0, ph - 0.15, -0.03), wood)
	# Centre drawer under the top.
	_add_mesh(n, "CentreDrawer", Vector3(w - pw - 0.12, 0.08, 0.016), Vector3(-pw * 0.5, ph - 0.05, -d + 0.012), wood)
	_add_ball(n, "CentreKnob", Vector3(-pw * 0.5, ph - 0.05, -d - 0.006), 0.011, brass)
	# Green leather writing inset.
	_add_mesh(n, "Inset", Vector3(w - 0.12, 0.002, d - 0.12), Vector3(0, h + 0.001, -d * 0.5), _mat(Color(0.12, 0.22, 0.14)))
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

# Bentwood-style chair; origin at the seat's centre on the floor, -Z = the sitter's front.
func _chair(n: Node3D) -> void:
	if HDProps.place(n, "bentwood_chair"):
		_furniture_body(n, Vector3(0.42, 0.48, 0.4), Vector3(0, 0.24, 0))
		return
	var wood := trim_material
	var leather := _crew_mat("leather")
	var sw := 0.42
	var sd := 0.4
	var sy := 0.46
	_add_mesh(n, "Seat", Vector3(sw, 0.03, sd), Vector3(0, sy - 0.015, 0), wood)
	_add_mesh(n, "Cushion", Vector3(sw - 0.05, 0.03, sd - 0.05), Vector3(0, sy + 0.012, 0.0), leather)
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			var top := Vector3(lx * (sw * 0.5 - 0.03), sy - 0.03, lz * (sd * 0.5 - 0.03))
			var foot := top + Vector3(lx * 0.015, -(sy - 0.03), lz * 0.02)
			_add_rod(n, "Leg", foot, top, 0.016, wood)
		# Back posts rising from the rear legs, raked back a little.
		var p0 := Vector3(lx * (sw * 0.5 - 0.03), sy, sd * 0.5 - 0.03)
		_add_rod(n, "BackPost", p0, p0 + Vector3(0, 0.44, 0.06), 0.015, wood)
	_add_mesh(n, "BackRail", Vector3(sw - 0.04, 0.09, 0.022), Vector3(0, sy + 0.38, sd * 0.5 + 0.022), wood)
	_add_mesh(n, "BackSplat", Vector3(0.1, 0.26, 0.016), Vector3(0, sy + 0.18, sd * 0.5 - 0.0), wood)
	_add_mesh(n, "Stretcher", Vector3(sw - 0.06, 0.02, 0.02), Vector3(0, 0.16, 0), wood)
	_furniture_body(n, Vector3(sw, sy + 0.02, sd), Vector3(0, (sy + 0.02) * 0.5, 0))

func _nightstand(n: Node3D, w: float, d: float, h: float) -> void:
	if HDProps.place(n, "nightstand"):
		_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))
		return
	var wood := trim_material
	var dark := _svc_mat("dark")
	var brass := _brass()
	_add_mesh(n, "Carcass", Vector3(w, h - 0.06, d), Vector3(0, 0.06 + (h - 0.06) * 0.5, -d * 0.5), wood)
	_add_mesh(n, "Plinth", Vector3(w - 0.02, 0.06, d - 0.02), Vector3(0, 0.03, -d * 0.5), dark)
	_add_mesh(n, "Top", Vector3(w + 0.02, 0.025, d + 0.015), Vector3(0, h - 0.0125, -(d + 0.015) * 0.5), wood)
	_add_mesh(n, "Drawer", Vector3(w - 0.04, 0.12, 0.016), Vector3(0, h - 0.1, -d - 0.008), wood)
	_add_ball(n, "Knob", Vector3(0, h - 0.1, -d - 0.022), 0.012, brass)
	_add_mesh(n, "Shelf", Vector3(w - 0.04, 0.2, 0.004), Vector3(0, 0.26, -d - 0.001), dark)
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

# Wardrobe: walnut carcass, two panelled doors with brass knobs, a drawer below, cornice on top.
func _wardrobe(n: Node3D, w: float, d: float, h: float) -> void:
	if HDProps.place(n, "wardrobe", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 0.8, h / 1.95, d / 0.55))):
		_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))
		return
	var wood := trim_material
	var dark := _svc_mat("dark")
	var brass := _brass()
	_add_mesh(n, "Plinth", Vector3(w - 0.03, 0.08, d - 0.03), Vector3(0, 0.04, -d * 0.5 + 0.005), dark)
	_add_mesh(n, "Carcass", Vector3(w, h - 0.13, d), Vector3(0, 0.08 + (h - 0.13) * 0.5, -d * 0.5), wood)
	_add_mesh(n, "Cornice", Vector3(w + 0.05, 0.035, d + 0.035), Vector3(0, h - 0.0325, -(d + 0.035) * 0.5), wood)
	_add_mesh(n, "CorniceBead", Vector3(w + 0.03, 0.015, d + 0.02), Vector3(0, h - 0.058, -(d + 0.02) * 0.5), dark)
	# Drawer across the bottom.
	_add_mesh(n, "Drawer", Vector3(w - 0.04, 0.2, 0.018), Vector3(0, 0.2, -d - 0.009), wood)
	for sx in [-1.0, 1.0]:
		_add_ball(n, "DrawerKnob", Vector3(sx * w * 0.25, 0.2, -d - 0.026), 0.012, brass)
	var dw := w * 0.5 - 0.02
	var y0 := 0.32
	var dh := h - 0.12 - y0
	for sx in [-1.0, 1.0]:
		var x: float = sx * (dw * 0.5 + 0.006)
		_add_mesh(n, "Door", Vector3(dw, dh, 0.02), Vector3(x, y0 + dh * 0.5, -d - 0.01), wood)
		_add_mesh(n, "DoorPanel", Vector3(dw - 0.09, dh - 0.12, 0.012), Vector3(x, y0 + dh * 0.5, -d - 0.024), wood)
		_add_mesh(n, "PanelShadow", Vector3(dw - 0.075, dh - 0.105, 0.004), Vector3(x, y0 + dh * 0.5, -d - 0.021), dark)
		_add_ball(n, "Knob", Vector3(sx * 0.035, y0 + dh * 0.5, -d - 0.03), 0.013, brass)
	_add_mesh(n, "Escutcheon", Vector3(0.016, 0.03, 0.003), Vector3(0.035, y0 + dh * 0.44, -d - 0.021), brass)
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

# Painted steel locker: two doors with louvres, a hasp and padlock, stencilled plate.
func _steel_locker(n: Node3D, w: float, d: float, h: float) -> void:
	if HDProps.place(n, "steel_locker", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 0.76, h / 1.9, d / 0.5))):
		var dwl := w * 0.5 - 0.014
		_add_plate(n, "SECURITY\nEQUIPMENT", Vector3(-dwl * 0.5 - 0.005, h * 0.6, -d - 0.021), Vector3(0, 0, -1), "red", false, 0.016)
		_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))
		return
	var paint := _crew_mat("locker")
	var dark := _crew_mat("iron")
	var steel := _crew_mat("steel")
	_add_mesh(n, "Body", Vector3(w, h - 0.06, d), Vector3(0, 0.06 + (h - 0.06) * 0.5, -d * 0.5), paint)
	_add_mesh(n, "Base", Vector3(w - 0.02, 0.06, d - 0.02), Vector3(0, 0.03, -d * 0.5), dark)
	var dw := w * 0.5 - 0.012
	for sx in [-1.0, 1.0]:
		var x: float = sx * (dw * 0.5 + 0.004)
		_add_mesh(n, "Door", Vector3(dw, h - 0.14, 0.012), Vector3(x, 0.06 + (h - 0.14) * 0.5 + 0.04, -d - 0.006), paint)
		for k in 5:
			_add_mesh(n, "Louvre", Vector3(dw - 0.1, 0.008, 0.004), Vector3(x, h - 0.2 - k * 0.028, -d - 0.013), dark)
			_add_mesh(n, "Louvre", Vector3(dw - 0.1, 0.008, 0.004), Vector3(x, 0.24 - k * 0.028 + 0.08, -d - 0.013), dark)
	_add_mesh(n, "DoorGap", Vector3(0.004, h - 0.14, 0.002), Vector3(0, 0.06 + (h - 0.14) * 0.5 + 0.04, -d - 0.013), dark)
	# Handle, hasp and padlock on the right-hand door.
	var hy := h * 0.52
	_add_rod(n, "Handle", Vector3(0.05, hy - 0.08, -d - 0.03), Vector3(0.05, hy + 0.08, -d - 0.03), 0.008, steel)
	for ey in [-0.08, 0.08]:
		_add_rod(n, "HandlePost", Vector3(0.05, hy + ey, -d - 0.012), Vector3(0.05, hy + ey, -d - 0.03), 0.006, steel)
	_add_mesh(n, "Hasp", Vector3(0.08, 0.025, 0.006), Vector3(0.0, hy - 0.16, -d - 0.016), steel)
	_add_mesh(n, "Padlock", Vector3(0.045, 0.05, 0.02), Vector3(0.0, hy - 0.2, -d - 0.024), _brass())
	var shackle := MeshInstance3D.new()
	shackle.name = "Shackle"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.012
	tm.outer_radius = 0.017
	shackle.mesh = tm
	shackle.material_override = steel
	shackle.rotation.x = PI * 0.5
	shackle.position = Vector3(0.0, hy - 0.17, -d - 0.024)
	n.add_child(shackle)
	_add_plate(n, "SECURITY\nEQUIPMENT", Vector3(-dw * 0.5 - 0.004, h - 0.42, -d - 0.013), Vector3(0, 0, -1), "red", false, 0.016)
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

# Cast-iron safe: dark green-black with gold lining, brass dial and lever handle.
func _strongbox(n: Node3D, w: float, d: float, h: float) -> void:
	if HDProps.place(n, "strongbox", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 0.5, h / 0.62, d / 0.48))):
		_add_plate(n, "GRAND CONTINENTAL", Vector3(0, 0.05 + (h - 0.05) * 0.5 - 0.17, -d - 0.037), Vector3(0, 0, -1), "brass", false, 0.012)
		_furniture_body(n, Vector3(w, h, d + 0.03), Vector3(0, h * 0.5, -(d + 0.03) * 0.5))
		return
	var iron := _crew_mat("iron")
	var gold := _crew_mat("gold_line")
	var brass := _brass()
	_add_mesh(n, "Body", Vector3(w, h - 0.05, d), Vector3(0, 0.05 + (h - 0.05) * 0.5, -d * 0.5), iron)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_mesh(n, "Foot", Vector3(0.06, 0.05, 0.06), Vector3(sx * (w * 0.5 - 0.05), 0.025, -d * 0.5 + sz * (d * 0.5 - 0.05)), iron)
	_add_mesh(n, "Door", Vector3(w - 0.06, h - 0.13, 0.03), Vector3(0, 0.05 + (h - 0.05) * 0.5, -d - 0.015), iron)
	# Gold pinstripe border on the door.
	var dw := w - 0.12
	var dh := h - 0.19
	var cy := 0.05 + (h - 0.05) * 0.5
	for sy in [-1.0, 1.0]:
		_add_mesh(n, "Pinstripe", Vector3(dw, 0.006, 0.002), Vector3(0, cy + sy * dh * 0.5, -d - 0.031), gold)
	for sx in [-1.0, 1.0]:
		_add_mesh(n, "Pinstripe", Vector3(0.006, dh, 0.002), Vector3(sx * dw * 0.5, cy, -d - 0.031), gold)
	var dial := _add_cylinder(n, "Dial", 0.045, 0.02, Vector3(0, cy + 0.1, -d - 0.04), brass)
	dial.rotation = Vector3(PI * 0.5, 0, 0)
	var knob := _add_cylinder(n, "DialKnob", 0.018, 0.03, Vector3(0, cy + 0.1, -d - 0.055), iron)
	knob.rotation = Vector3(PI * 0.5, 0, 0)
	_add_rod(n, "Lever", Vector3(0, cy - 0.06, -d - 0.035), Vector3(0.11, cy - 0.06, -d - 0.035), 0.009, brass)
	_add_ball(n, "LeverBoss", Vector3(0, cy - 0.06, -d - 0.035), 0.02, brass)
	_add_plate(n, "GRAND CONTINENTAL", Vector3(0, cy - 0.17, -d - 0.032), Vector3(0, 0, -1), "brass", false, 0.012)
	_furniture_body(n, Vector3(w, h, d + 0.03), Vector3(0, h * 0.5, -(d + 0.03) * 0.5))

# Open walnut key cabinet on the wall (origin = centre of its back), rows of hooks with keys and tags.
func _key_cabinet(n: Node3D, w: float, h: float) -> void:
	if HDProps.place(n, "key_cabinet", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 0.44, h / 0.5, 1.0))):
		_add_plate(n, "KEYS", Vector3(0, h * 0.5 + 0.065, -0.004), Vector3(0, 0, -1), "brass", false, 0.014)
		return
	var wood := trim_material
	var dark := _svc_mat("dark")
	var brass := _brass()
	var d := 0.07
	_add_mesh(n, "Back", Vector3(w, h, 0.012), Vector3(0, 0, -0.006), dark)
	for sx in [-1.0, 1.0]:
		_add_mesh(n, "Side", Vector3(0.02, h, d), Vector3(sx * (w * 0.5 - 0.01), 0, -d * 0.5), wood)
	for sy in [-1.0, 1.0]:
		_add_mesh(n, "Rail", Vector3(w, 0.02, d), Vector3(0, sy * (h * 0.5 - 0.01), -d * 0.5), wood)
	_add_plate(n, "KEYS", Vector3(0, h * 0.5 + 0.03, -0.004), Vector3(0, 0, -1), "brass", false, 0.014)
	var rows := 3
	var cols := 5
	for row in rows:
		var y := h * 0.5 - 0.08 - row * (h - 0.12) / rows
		_add_mesh(n, "HookBar", Vector3(w - 0.06, 0.018, 0.008), Vector3(0, y, -0.016), wood)
		for c in cols:
			var x := -w * 0.5 + 0.06 + c * (w - 0.12) / (cols - 1)
			_add_rod(n, "Hook", Vector3(x, y, -0.02), Vector3(x, y + 0.008, -0.045), 0.0025, brass)
			if hash_f(row * cols + c, 3.1) < 0.2:
				continue        # an empty hook
			var swing := (hash_f(row * cols + c, 7.7) - 0.5) * 0.3
			var key := Node3D.new()
			key.name = "Key"
			key.position = Vector3(x, y, -0.04)
			key.rotation.z = swing
			n.add_child(key)
			_add_mesh(key, "Bow", Vector3(0.016, 0.016, 0.003), Vector3(0, -0.012, 0), brass)
			_add_mesh(key, "Shank", Vector3(0.005, 0.045, 0.003), Vector3(0, -0.04, 0), brass)
			_add_mesh(key, "Bit", Vector3(0.01, 0.008, 0.003), Vector3(0.006, -0.058, 0), brass)
			_add_mesh(key, "Tag", Vector3(0.022, 0.032, 0.002), Vector3(-0.016, -0.03, -0.003), _svc_mat("paper"))

# ————— small items —————

func _ledger(n: Node3D, base: Vector3, rot: float) -> void:
	if HDProps.place(n, "ledger_open", HDProps.xf(base, Vector3(0, rot, 0)), "Ledger"):
		return
	var book := Node3D.new()
	book.name = "Ledger"
	book.position = base
	book.rotation.y = rot
	n.add_child(book)
	for sx in [-1.0, 1.0]:
		var page := _add_mesh(book, "Page", Vector3(0.2, 0.012, 0.28), Vector3(sx * 0.1, 0.008, 0), _svc_mat("paper"))
		page.rotation.z = -sx * 0.04
		_add_mesh(book, "Cover", Vector3(0.205, 0.004, 0.285), Vector3(sx * 0.1, 0.002, 0), _crew_mat("book_brown"))
		for k in 7:
			_add_mesh(book, "Line", Vector3(0.16, 0.0005, 0.002), Vector3(sx * 0.1, 0.0145 + 0.0003, -0.1 + k * 0.032), _ink_mat(INK))
	_add_rod(book, "Pen", Vector3(0.05, 0.02, 0.1), Vector3(0.16, 0.02, -0.02), 0.004, _crew_mat("black"))

func _journal(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "journal", HDProps.xf(base, Vector3(0, -0.18, 0)), "Journal"):
		return
	var book := Node3D.new()
	book.name = "Journal"
	book.position = base
	book.rotation.y = -0.18
	n.add_child(book)
	_add_mesh(book, "Cover", Vector3(0.16, 0.022, 0.22), Vector3(0, 0.011, 0), _crew_mat("book_red"))
	_add_mesh(book, "Pages", Vector3(0.15, 0.018, 0.212), Vector3(0.006, 0.011, 0), _svc_mat("paper"))
	_add_mesh(book, "Band", Vector3(0.004, 0.0225, 0.222), Vector3(0.05, 0.011, 0), _crew_mat("black"))
	_add_rod(book, "Pencil", Vector3(-0.1, 0.004, -0.08), Vector3(-0.08, 0.004, 0.09), 0.0035, _mat(Color(0.75, 0.6, 0.1)))

func _pager(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "pager", HDProps.xf(base, Vector3(0, 0.35, 0)), "Pager"):
		return
	var p := Node3D.new()
	p.name = "Pager"
	p.position = base
	p.rotation.y = 0.35
	n.add_child(p)
	_add_mesh(p, "Body", Vector3(0.075, 0.02, 0.05), Vector3(0, 0.01, 0), _crew_mat("black"))
	_add_mesh(p, "Screen", Vector3(0.05, 0.002, 0.018), Vector3(-0.004, 0.0205, -0.006), _crew_mat("lcd"))
	for k in 3:
		_add_mesh(p, "Button", Vector3(0.01, 0.003, 0.008), Vector3(-0.02 + k * 0.016, 0.021, 0.014), _crew_mat("steel"))
	_add_mesh(p, "Clip", Vector3(0.05, 0.004, 0.035), Vector3(0, -0.0, 0.0), _crew_mat("steel"))

func _ticket_punch(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "ticket_punch", HDProps.xf(base, Vector3(0, 0.7, 0)), "TicketPunch"):
		return
	var t := Node3D.new()
	t.name = "TicketPunch"
	t.position = base
	t.rotation.y = 0.7
	n.add_child(t)
	var steel := _crew_mat("steel")
	_add_rod(t, "JawA", Vector3(-0.06, 0.008, 0.0), Vector3(0.05, 0.008, -0.01), 0.006, steel)
	_add_rod(t, "JawB", Vector3(-0.06, 0.008, 0.0), Vector3(0.05, 0.008, 0.012), 0.006, steel)
	_add_ball(t, "Pivot", Vector3(-0.04, 0.009, 0.0), 0.009, steel)
	var die := _add_cylinder(t, "Die", 0.012, 0.016, Vector3(-0.07, 0.012, 0.0), steel)
	die.rotation = Vector3.ZERO

func _mug(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "enamel_mug", HDProps.xf(base, Vector3(0, 0.6, 0)), "Mug"):
		return
	var c := Node3D.new()
	c.name = "Mug"
	c.position = base
	n.add_child(c)
	_cyl_v(c, "Cup", 0.04, 0.036, 0.09, Vector3(0, 0.045, 0), _crew_mat("enamel_white"))
	_cyl_v(c, "Tea", 0.036, 0.036, 0.002, Vector3(0, 0.075, 0), _mat(Color(0.25, 0.12, 0.04)))
	_cyl_v(c, "Rim", 0.041, 0.041, 0.006, Vector3(0, 0.088, 0), _mat(Color(0.12, 0.2, 0.38)))
	var h := MeshInstance3D.new()
	h.name = "Handle"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.016
	tm.outer_radius = 0.024
	h.mesh = tm
	h.material_override = _crew_mat("enamel_white")
	h.rotation.x = PI * 0.5
	h.position = Vector3(0.045, 0.05, 0)
	c.add_child(h)

func _ink_stand(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "ink_stand", HDProps.xf(base), "InkStand"):
		return
	var s := Node3D.new()
	s.name = "InkStand"
	s.position = base
	n.add_child(s)
	_add_mesh(s, "Tray", Vector3(0.16, 0.015, 0.09), Vector3(0, 0.0075, 0), trim_material)
	_cyl_v(s, "InkPot", 0.022, 0.026, 0.045, Vector3(-0.035, 0.037, 0), _crew_mat("ink"))
	_cyl_v(s, "InkLid", 0.014, 0.014, 0.012, Vector3(-0.035, 0.065, 0), _brass())
	_add_rod(s, "Nib", Vector3(0.02, 0.018, 0.02), Vector3(0.06, 0.04, -0.03), 0.004, _crew_mat("black"))

func _paper_stack(n: Node3D, base: Vector3, rot: float) -> void:
	if HDProps.place(n, "paper_stack", HDProps.xf(base, Vector3(0, rot, 0)), "PaperStack"):
		return
	for k in 4:
		var sheet := _add_mesh(n, "Paper", Vector3(0.21, 0.002, 0.297), base + Vector3((hash_f(k, 1.3) - 0.5) * 0.02, 0.001 + k * 0.0022, 0), _svc_mat("paper"))
		sheet.rotation.y = rot + (hash_f(k, 4.2) - 0.5) * 0.12

# Railway hand lamp: black body, red lens toward the room, wire bail handle.
func _hand_lamp(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "hand_lamp", HDProps.xf(base, Vector3(0, 0.5, 0)), "HandLamp"):
		return
	var l := Node3D.new()
	l.name = "HandLamp"
	l.position = base
	l.rotation.y = 0.5
	n.add_child(l)
	var body := _crew_mat("iron")
	_cyl_v(l, "Body", 0.06, 0.07, 0.17, Vector3(0, 0.085, 0), body)
	_cyl_v(l, "Top", 0.035, 0.06, 0.04, Vector3(0, 0.19, 0), body)
	var lens := _add_cylinder(l, "Lens", 0.04, 0.02, Vector3(0, 0.1, -0.065), _crew_mat("lens_red"))
	lens.rotation = Vector3(PI * 0.5, 0, 0)
	var bail := MeshInstance3D.new()
	bail.name = "Bail"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.052
	tm.outer_radius = 0.058
	bail.mesh = tm
	bail.material_override = _crew_mat("steel")
	bail.rotation.z = PI * 0.5
	bail.position = Vector3(0, 0.2, 0)
	bail.scale = Vector3(1, 1, 1)
	l.add_child(bail)

# Green-shaded brass desk lamp with a little warm light.
func _desk_lamp(n: Node3D, base: Vector3) -> void:
	var hd := HDProps.place(n, "bankers_lamp", HDProps.xf(base), "DeskLamp")
	if hd:
		var hl := OmniLight3D.new()
		hl.name = "Light"
		hl.position = Vector3(-0.01, 0.27, -0.07)
		hl.omni_range = 1.3
		hl.light_energy = 0.45
		hl.light_color = Color(1.0, 0.85, 0.6)
		hl.shadow_enabled = false
		hd.add_child(hl)
		return
	var l := Node3D.new()
	l.name = "DeskLamp"
	l.position = base
	n.add_child(l)
	var brass := _brass()
	_cyl_v(l, "Base", 0.06, 0.07, 0.025, Vector3(0, 0.0125, 0), brass)
	_add_rod(l, "Stem", Vector3(0, 0.02, 0), Vector3(0, 0.33, 0), 0.008, brass)
	var shade := MeshInstance3D.new()
	shade.name = "Shade"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 0.26
	cm.radial_segments = 20
	shade.mesh = cm
	shade.material_override = _crew_mat("shade_green")
	shade.rotation.z = PI * 0.5
	shade.scale = Vector3(1.0, 1.0, 0.55)
	shade.position = Vector3(-0.02, 0.36, -0.05)
	l.add_child(shade)
	_cyl_v(l, "Bulb", 0.02, 0.02, 0.05, Vector3(-0.02, 0.33, -0.05), _crew_mat("bulb"))
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(-0.02, 0.28, -0.08)
	light.omni_range = 1.3
	light.light_energy = 0.45
	light.light_color = Color(1.0, 0.85, 0.6)
	light.shadow_enabled = false
	l.add_child(light)

func _alarm_clock(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "alarm_clock", HDProps.xf(base, Vector3(0, 0.3, 0)), "AlarmClock"):
		return
	var c := Node3D.new()
	c.name = "AlarmClock"
	c.position = base
	c.rotation.y = 0.3
	n.add_child(c)
	var brass := _brass()
	var case_ := _add_cylinder(c, "Case", 0.055, 0.04, Vector3(0, 0.075, 0), brass)
	case_.rotation = Vector3(PI * 0.5, 0, 0)
	var face := _add_cylinder(c, "Face", 0.047, 0.003, Vector3(0, 0.075, -0.021), _crew_mat("clock_face"))
	face.rotation = Vector3(PI * 0.5, 0, 0)
	var hh := _add_mesh(c, "HourHand", Vector3(0.004, 0.026, 0.001), Vector3(0.006, 0.083, -0.0235), _ink_mat(INK))
	hh.rotation.z = -0.8
	var mh := _add_mesh(c, "MinuteHand", Vector3(0.003, 0.038, 0.001), Vector3(-0.004, 0.09, -0.024), _ink_mat(INK))
	mh.rotation.z = 0.3
	for sx in [-1.0, 1.0]:
		_add_ball(c, "Bell", Vector3(sx * 0.035, 0.135, 0), 0.022, brass)
		_add_rod(c, "Foot", Vector3(sx * 0.03, 0.03, 0), Vector3(sx * 0.045, 0.0, 0), 0.005, brass)
	_add_rod(c, "Hammer", Vector3(0, 0.125, 0), Vector3(0, 0.155, 0), 0.003, brass)

# Round wall clock (station style): walnut rim, cream face, hour ticks and hands.
func _wall_clock(parent: Node3D, pos: Vector3, facing: Vector3) -> void:
	if HDProps.place(parent, "wall_clock_guard", HDProps.xf(pos, Vector3(0, atan2(-facing.x, -facing.z), 0)), "WallClock"):
		return
	var m := _wall_marker(parent, "WallClock", pos, facing)
	var r := 0.13
	var rim := _add_cylinder(m, "Rim", r + 0.02, 0.05, Vector3(0, 0, -0.025), trim_material)
	rim.rotation = Vector3(PI * 0.5, 0, 0)
	var face := _add_cylinder(m, "Face", r, 0.004, Vector3(0, 0, -0.051), _crew_mat("clock_face"))
	face.rotation = Vector3(PI * 0.5, 0, 0)
	for i in 12:
		var a := TAU * i / 12.0
		var tick := _add_mesh(m, "Tick", Vector3(0.006, 0.022 if i % 3 == 0 else 0.012, 0.001),
				Vector3(sin(a) * (r - 0.02), cos(a) * (r - 0.02), -0.054), _ink_mat(INK))
		tick.rotation.z = -a
	# 4:50 - ten minutes before the end of the night shift. Seen from the room the marker's +X is
	# on the viewer's left, so clockwise angle a points along (-sin a, cos a).
	_clock_hand(m, "HourHand", TAU * (4.0 + 50.0 / 60.0) / 12.0, 0.07, 0.008, -0.056)
	_clock_hand(m, "MinuteHand", TAU * 50.0 / 60.0, 0.1, 0.005, -0.058)
	_add_ball(m, "Boss", Vector3(0, 0, -0.06), 0.008, _brass())

func _clock_hand(m: Node3D, hand_name: String, a: float, len: float, w: float, z: float) -> void:
	var hand := _add_mesh(m, hand_name, Vector3(w, len, 0.002), Vector3(-sin(a), cos(a), 0) * len * 0.4 + Vector3(0, 0, z), _ink_mat(INK))
	hand.rotation.z = a

func _handcuffs(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "handcuffs", HDProps.xf(base, Vector3(0, 0.9, 0)), "Handcuffs"):
		return
	var h := Node3D.new()
	h.name = "Handcuffs"
	h.position = base
	h.rotation.y = 0.9
	n.add_child(h)
	var steel := _crew_mat("steel")
	for sx in [-1.0, 1.0]:
		var ring := MeshInstance3D.new()
		ring.name = "Cuff"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.028
		tm.outer_radius = 0.036
		ring.mesh = tm
		ring.material_override = steel
		ring.position = Vector3(sx * 0.05, 0.004, 0)
		h.add_child(ring)
	_add_mesh(h, "Chain", Vector3(0.03, 0.006, 0.006), Vector3(0, 0.004, 0), steel)

func _guard_cap(n: Node3D, pos: Vector3) -> void:
	if HDProps.place(n, "guard_cap", HDProps.xf(pos, Vector3(-1.35, 0, 0)), "GuardCap"):
		return
	var c := Node3D.new()
	c.name = "GuardCap"
	c.position = pos
	# Hung on the hook by its band: crown toward the room, visor hanging down by the wall.
	c.rotation.x = -1.35
	n.add_child(c)
	_cyl_v(c, "Crown", 0.115, 0.095, 0.07, Vector3(0, 0.0, 0), _crew_mat("cloth_navy"))
	_cyl_v(c, "Band", 0.097, 0.097, 0.03, Vector3(0, -0.045, 0), _crew_mat("black"))
	var visor := _cyl_v(c, "Visor", 0.09, 0.09, 0.006, Vector3(0, -0.06, -0.06), _crew_mat("black"))
	visor.scale = Vector3(1.0, 1.0, 0.55)
	_add_mesh(c, "Badge", Vector3(0.03, 0.022, 0.004), Vector3(0, -0.04, -0.098), _brass())

func _truncheon(n: Node3D, pos: Vector3) -> void:
	if HDProps.place(n, "truncheon", HDProps.xf(pos), "Truncheon"):
		return
	var t := Node3D.new()
	t.name = "Truncheon"
	t.position = pos
	n.add_child(t)
	_add_rod(t, "Strap", Vector3(0, 0, 0), Vector3(0, -0.06, -0.01), 0.004, _crew_mat("leather"))
	_add_rod(t, "Grip", Vector3(0, -0.06, -0.01), Vector3(0, -0.16, -0.015), 0.016, _crew_mat("leather"))
	_add_rod(t, "Baton", Vector3(0, -0.16, -0.015), Vector3(0, -0.44, -0.03), 0.019, _crew_mat("black"))

func _rug(parent: Node3D, center: Vector3, size: Vector2) -> void:
	if HDProps.place(parent, "rug", HDProps.xf(center, Vector3.ZERO, Vector3(size.x / 1.8, 1.0, size.y / 0.95)), "Rug"):
		return
	var r := Node3D.new()
	r.name = "Rug"
	r.position = center
	parent.add_child(r)
	_add_mesh(r, "Border", Vector3(size.x, 0.008, size.y), Vector3(0, 0.004, 0), _crew_mat("rug_border"))
	_add_mesh(r, "Field", Vector3(size.x - 0.16, 0.0085, size.y - 0.16), Vector3(0, 0.0045, 0), _crew_mat("rug"))
	_add_mesh(r, "Medallion", Vector3(0.5, 0.009, 0.32), Vector3(0, 0.005, 0), _crew_mat("rug_border"))
	_add_mesh(r, "MedallionCore", Vector3(0.36, 0.0095, 0.2), Vector3(0, 0.0052, 0), _crew_mat("rug_fringe"))
	for sx in [-1.0, 1.0]:
		_add_mesh(r, "Fringe", Vector3(0.04, 0.004, size.y - 0.04), Vector3(sx * (size.x * 0.5 + 0.02), 0.002, 0), _crew_mat("rug_fringe"))

# ————— printed notices —————

func _draw_duty_roster(sh: Node3D, w: float, h: float) -> void:
	var top := h * 0.5
	_print_text(sh, "DUTY ROSTER", 0, top - 0.045, 0.02, INK, 0, true)
	_print_rect(sh, Vector2(w - 0.06, 0.0012), Vector2(0, top - 0.075), INK)
	_print_text(sh, "TRAIN SECURITY  ·  NIGHT SERVICE", 0, top - 0.095, 0.009, INK)
	var rows := ["19.00  BOARDING CHECK, ALL CARS", "21.00  PATROL CARS 1-3", "23.00  HOLDING AREA - OFFENDERS",
			"01.00  PATROL CARS 1-5", "03.00  SLEEPING CAR, QUIET ROUND", "05.00  HAND OVER AT TERMINUS"]
	for i in rows.size():
		_print_text(sh, rows[i], -w * 0.5 + 0.035, top - 0.14 - i * 0.05, 0.0105, INK, -1)
	_print_text(sh, "REPORT ALL IRREGULARITIES\nTO THE GUARD AT ONCE", 0, -h * 0.5 + 0.06, 0.011, INK_RED)

func _draw_shift_calendar(sh: Node3D, w: float, h: float) -> void:
	var top := h * 0.5
	_print_text(sh, "SHIFTS", 0, top - 0.045, 0.022, INK, 0, true)
	_print_rect(sh, Vector2(w - 0.06, 0.0012), Vector2(0, top - 0.075), INK)
	_print_text(sh, "19.00 - 05.00", 0, top - 0.095, 0.01, INK)
	# Ten shifts in rows of 3 + 4 + 3 (home visits after the 3rd, 7th and 10th).
	var groups := [3, 4, 3]
	var cell := 0.085
	var n := 0
	for gi in groups.size():
		var cnt: int = groups[gi]
		var y := top - 0.16 - gi * 0.115
		for i in cnt:
			n += 1
			var cx := (i - (cnt - 1) * 0.5) * (cell + 0.012)
			for s in [-1.0, 1.0]:
				_print_rect(sh, Vector2(cell, 0.002), Vector2(cx, y + s * cell * 0.5), INK)
				_print_rect(sh, Vector2(0.002, cell), Vector2(cx + s * cell * 0.5, y), INK)
			_print_text(sh, "%d" % n, cx, y, 0.03, INK)
		_print_text(sh, "HOME", w * 0.5 - 0.03, y - 0.05, 0.008, INK_RED, 1)
