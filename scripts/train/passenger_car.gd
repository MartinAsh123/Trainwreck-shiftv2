# passenger_car.gd
# Greybox builder for a modular passenger car: CSG shell + anchor points.
# Axes: X = length (direction of travel), Y = up, Z = width. Floor top is at y = 0.
# Layout, end to end: gangway door | boarding vestibule | door | seating saloon | door | WC + corridor | gangway door
# Assign prefabs to the *_scene slots to replace the placeholder shapes.
# Prefab convention: front faces -Z; each anchor marker's -Z is where that front should point.
@tool
class_name PassengerCar
extends Node3D

const HDProps := preload("res://scripts/train/hd_props.gd")

const GENERATED_NAME := "Generated"
const ROOF_SEGMENTS := 24
const RAIL_GAUGE := 1.435
## Front-to-back depth of a double seat (cushion front to backrest), used to place bays.
const SEAT_DEPTH := 0.65

# ————— body —————

@export_group("Body")
@export var length: float = 16.8:
	set(v): length = v; _queue_rebuild()
@export var width: float = 3.15:
	set(v): width = v; _queue_rebuild()
@export var interior_height: float = 2.3:
	set(v): interior_height = v; _queue_rebuild()
@export var wall_thickness: float = 0.1:
	set(v): wall_thickness = v; _queue_rebuild()
@export var floor_thickness: float = 0.2:
	set(v): floor_thickness = v; _queue_rebuild()
@export var roof_thickness: float = 0.15:
	set(v): roof_thickness = v; _queue_rebuild()
## Height of the roof arc above the eave line (outer surface).
@export var roof_rise: float = 0.45:
	set(v): roof_rise = v; _queue_rebuild()
## How far the side walls lean inward between window sill and eave.
@export var tumblehome: float = 0.08:
	set(v): tumblehome = v; _queue_rebuild()

# ————— running gear —————

@export_group("Running Gear")
## Floor top above rail top — the car root sits this high above the rails.
@export var floor_height_above_rail: float = 1.25:
	set(v): floor_height_above_rail = v; _queue_rebuild()
## Distance from each car end to its bogie center.
@export var bogie_inset: float = 3.5:
	set(v): bogie_inset = v; _queue_rebuild()

# ————— end sections —————

@export_group("Layout")
## Boarding vestibule at the +X (front) end instead of the -X end. The WC takes the other end.
@export var boarding_at_front: bool = false:
	set(v): boarding_at_front = v; _queue_rebuild()
@export var vestibule_length: float = 2.2:
	set(v): vestibule_length = v; _queue_rebuild()
## Length of the WC end section (toilet room + corridor + space by the gangway door).
@export var toilet_section_length: float = 2.6:
	set(v): toilet_section_length = v; _queue_rebuild()
## Toilet room size across the car (Z) and along it (X). It sits on the +Z side.
@export var toilet_width: float = 0.95:
	set(v): toilet_width = v; _queue_rebuild()
@export var toilet_length: float = 1.6:
	set(v): toilet_length = v; _queue_rebuild()

# ————— doors —————

@export_group("Doors")
## Hinged 1970s slam door opening.
@export var side_door_width: float = 0.8:
	set(v): side_door_width = v; _queue_rebuild()
## Saloon doors continue the aisle, so keep this â‰¤ aisle_width or the end seats cover the opening.
@export var inner_door_width: float = 0.7:
	set(v): inner_door_width = v; _queue_rebuild()
## Gangway doors to the next car.
@export var end_door_width: float = 0.9:
	set(v): end_door_width = v; _queue_rebuild()
@export var toilet_door_width: float = 0.7:
	set(v): toilet_door_width = v; _queue_rebuild()
@export var door_height: float = 2.0:
	set(v): door_height = v; _queue_rebuild()
## Sliding door models (saloon and gangway): open = pushed into the wall, closed = in the opening.
@export var doors_open: bool = false:
	set(v): doors_open = v; _queue_rebuild()

# ————— windows (one per seat bay) —————

@export_group("Windows")
## Clear opening (glass) of each saloon window. The frame model is stretched to fit it.
@export var window_width: float = 1.02:
	set(v): window_width = v; _queue_rebuild()
@export var window_height: float = 0.8:
	set(v): window_height = v; _queue_rebuild()
## Window unit fitted into every window aperture (null = simple procedural frames).
# Scene slots with a default fall back to it when set to null: the editor can write null into
# them when it saves a scene while this @tool script is being reloaded (null-proof slots).
@export var window_frame_scene: PackedScene = preload("res://assets/props/windows/window_frame.tscn"):
	set(v): window_frame_scene = v if v != null else preload("res://assets/props/windows/window_frame.tscn"); _queue_rebuild()
@export var window_sill: float = 0.8:
	set(v): window_sill = v; _queue_rebuild()
## Corner radius of the window openings, frames and glass.
@export var window_corner_radius: float = 0.09:
	set(v): window_corner_radius = v; _queue_rebuild()
## Also put a window midway between neighbouring bays (skipped where the gap is too narrow).
@export var windows_between_bays: bool = true:
	set(v): windows_between_bays = v; _queue_rebuild()

# ————— interior layout —————

@export_group("Interior")
## Facing-seat bays per side; each bay is two double seats facing each other (4 passengers).
@export var seat_bays: int = 5:
	set(v): seat_bays = v; _queue_rebuild()
## Backrest-to-backrest length of one bay.
@export var bay_length: float = 2.1:
	set(v): bay_length = v; _queue_rebuild()
## Distance between bay centers. 0 = spread the bays evenly along the saloon.
@export var bay_pitch: float = 0.0:
	set(v): bay_pitch = v; _queue_rebuild()
@export var aisle_width: float = 0.75:
	set(v): aisle_width = v; _queue_rebuild()
## Small wall-mounted table in each bay, under the window between the facing seats.
@export var bay_tables: bool = true:
	set(v): bay_tables = v; _queue_rebuild()
## Table size along the car (X), out from the wall (Z), and top height.
@export var table_width: float = 0.67:
	set(v): table_width = v; _queue_rebuild()
@export var table_depth: float = 0.53:
	set(v): table_depth = v; _queue_rebuild()
@export var table_height: float = 0.68:
	set(v): table_height = v; _queue_rebuild()
@export var lamp_spacing: float = 2.0:
	set(v): lamp_spacing = v; _queue_rebuild()
## Luggage rack center height and depth (out from the wall). The rack must clear the
## window top below and the curve of the ceiling above.
@export var rack_height: float = 1.86:
	set(v): rack_height = v; _queue_rebuild()
@export var rack_depth: float = 0.36:
	set(v): rack_depth = v; _queue_rebuild()

# ————— shell materials —————

@export_group("Materials")
## Outer skin: paint, lining, roof and skirt (procedural; heights are set from this car's layout).
@export var exterior_material: Material = preload("res://materials/train/car_exterior.tres"):
	set(v): exterior_material = v; _queue_rebuild()
## Every inner surface: floorboards, walnut panelling below the sill, cream paint above.
@export var interior_material: Material = preload("res://materials/train/car_interior.tres"):
	set(v): interior_material = v; _queue_rebuild()
## Window and door reveals.
@export var trim_material: Material = preload("res://materials/train/car_trim_wood.tres"):
	set(v): trim_material = v; _queue_rebuild()
@export var stripe_material: Material = preload("res://materials/train/car_stripe.tres"):
	set(v): stripe_material = v; _queue_rebuild()
@export var carpet_material: Material = preload("res://materials/train/carpet.tres"):
	set(v): carpet_material = v; _queue_rebuild()
## Open damask curtains (tied back at both sides) with a scalloped valance on every saloon window.
@export var window_curtains: bool = true:
	set(v): window_curtains = v; _queue_rebuild()
## Saloon window glass (clear, with grime at the edges) and the frosted toilet window.
@export var window_glass_material: Material = preload("res://materials/train/window_glass.tres"):
	set(v): window_glass_material = v; _queue_rebuild()
@export var frosted_glass_material: Material = preload("res://materials/train/window_glass_frosted.tres"):
	set(v): frosted_glass_material = v; _queue_rebuild()
## Underframe, buffers, footboards, grab handles and roof fittings (visual only).
@export var exterior_details: bool = true:
	set(v): exterior_details = v; _queue_rebuild()
## Air-conditioning housing on the roof above the WC end (replaces the ridge vent there).
@export var roof_ac_unit: bool = true:
	set(v): roof_ac_unit = v; _queue_rebuild()

@export_group("Lettering")
## Company name, car number, class numerals and interior signs (Playfair Display).
@export var lettering: bool = true:
	set(v): lettering = v; _queue_rebuild()
@export var company_name: String = "GRAND CONTINENTAL RAILWAY":
	set(v): company_name = v; _queue_rebuild()
@export var car_number: String = "No 1937":
	set(v): car_number = v; _queue_rebuild()
@export var class_numeral: String = "1":
	set(v): class_numeral = v; _queue_rebuild()
@export var lettering_color: Color = Color(0.83, 0.68, 0.34):
	set(v): lettering_color = v; _queue_rebuild()
## This car's position in the train, counted from the locomotive (car 1 is right behind it).
## The plates above the saloon and gangway doors point to the neighbouring cars.
@export var car_index: int = 2:
	set(v): car_index = v; _queue_rebuild()
## The locomotive end of the train is toward +X.
@export var front_is_positive_x: bool = true:
	set(v): front_is_positive_x = v; _queue_rebuild()
## Override the plate text toward the front / rear (empty = "CAR n" from car_index).
@export var front_door_label: String = "":
	set(v): front_door_label = v; _queue_rebuild()
@export var rear_door_label: String = "":
	set(v): rear_door_label = v; _queue_rebuild()

# ————— prefab slots (null = placeholder) —————

@export_group("Prefabs")
@export var seat_scene: PackedScene:
	set(v): seat_scene = v; _queue_rebuild()
@export var lamp_scene: PackedScene:
	set(v): lamp_scene = v; _queue_rebuild()
## Round PA speaker grille in the saloon ceiling, at the middle of the car.
@export var speaker_scene: PackedScene = preload("res://assets/props/lamps/speaker.tscn"):
	set(v): speaker_scene = v if v != null else preload("res://assets/props/lamps/speaker.tscn"); _queue_rebuild()
@export var rack_scene: PackedScene:
	set(v): rack_scene = v; _queue_rebuild()
@export var table_scene: PackedScene:
	set(v): table_scene = v; _queue_rebuild()
@export var side_door_scene: PackedScene:
	set(v): side_door_scene = v; _queue_rebuild()
## Doors between the saloon and the end sections.
@export var inner_door_scene: PackedScene:
	set(v): inner_door_scene = v; _queue_rebuild()
## Gangway doors to the next car.
@export var end_door_scene: PackedScene:
	set(v): end_door_scene = v; _queue_rebuild()
@export var toilet_door_scene: PackedScene:
	set(v): toilet_door_scene = v; _queue_rebuild()
## Lavatory lock state: thumb-turn inside, VACANT (green) / ENGAGED (red) indicator outside.
## At runtime, call toilet_lock().toggle() instead (no rebuild needed).
@export var toilet_occupied: bool = false:
	set(v):
		toilet_occupied = v
		var l := toilet_lock()
		if l:
			l.locked = v
@export var toilet_scene: PackedScene:
	set(v): toilet_scene = v; _queue_rebuild()
@export var sink_scene: PackedScene:
	set(v): sink_scene = v; _queue_rebuild()
## Mirror on the partition above the sink.
@export var mirror_scene: PackedScene:
	set(v): mirror_scene = v; _queue_rebuild()
## Fire extinguisher on the vestibule side of the boarding-end partition.
@export var extinguisher_scene: PackedScene:
	set(v): extinguisher_scene = v; _queue_rebuild()
## Emergency brake handle on the saloon side of both partitions (origin = bottom of the housing).
@export var emergency_brake_scene: PackedScene = preload("res://assets/props/safety/ebrake.tscn"):
	set(v): emergency_brake_scene = v if v != null else preload("res://assets/props/safety/ebrake.tscn"); _queue_rebuild()
## Control panel inside the glass-fronted staff cabinet in the WC-end passage.
@export var staff_panel_scene: PackedScene = preload("res://assets/props/staff/control_panel.tscn"):
	set(v): staff_panel_scene = v if v != null else preload("res://assets/props/staff/control_panel.tscn"); _queue_rebuild()
## Gauge panel beside the control panel in the staff cabinet.
@export var staff_gauges_scene: PackedScene = preload("res://assets/props/staff/gauge_panel.tscn"):
	set(v): staff_gauges_scene = v if v != null else preload("res://assets/props/staff/gauge_panel.tscn"); _queue_rebuild()
## Wall telephone in the computer niche (on the toilet room's end wall, beside the screen).
@export var phone_scene: PackedScene = preload("res://assets/props/station/phone.tscn"):
	set(v): phone_scene = v if v != null else preload("res://assets/props/station/phone.tscn"); _queue_rebuild()
## Toilet roll holder on the outer wall beside the WC bowl.
@export var roll_holder_scene: PackedScene = preload("res://assets/props/toilet/roll_holder.tscn"):
	set(v): roll_holder_scene = v if v != null else preload("res://assets/props/toilet/roll_holder.tscn"); _queue_rebuild()
## Wall-mounted litter bins: one in the vestibule, one in the WC-end passage.
@export var bin_scene: PackedScene = preload("res://assets/props/safety/bin.tscn"):
	set(v): bin_scene = v if v != null else preload("res://assets/props/safety/bin.tscn"); _queue_rebuild()
## Pedal bin on the WC floor, beside the bowl.
@export var pedal_bin_scene: PackedScene = preload("res://assets/props/toilet/pedal_bin.tscn"):
	set(v): pedal_bin_scene = v if v != null else preload("res://assets/props/toilet/pedal_bin.tscn"); _queue_rebuild()
## Glass-fronted staff cabinet on the passage wall opposite the toilet door.
@export var staff_cabinet: bool = true:
	set(v): staff_cabinet = v; _queue_rebuild()
## Wall air vent: right and left above both saloon doors, and one opposite the toilet door.
@export var vent_scene: PackedScene = preload("res://assets/props/vents/air_vent.tscn"):
	set(v): vent_scene = v if v != null else preload("res://assets/props/vents/air_vent.tscn"); _queue_rebuild()
## Screen set into the wall of the station niche (origin = screen center, -Z faces the room).
@export var terminal_scene: PackedScene = preload("res://assets/props/station/monitor.tscn"):
	set(v): terminal_scene = v if v != null else preload("res://assets/props/station/monitor.tscn"); _queue_rebuild()

@export_group("Station")
## Computer station in the niche beside the toilet: screen set into the wall, a wall shelf
## under it, keyboard on the shelf.
@export var computer_station: bool = true:
	set(v): computer_station = v; _queue_rebuild()
## Shelf top height (a standing terminal).
@export var station_shelf_height: float = 0.98:
	set(v): station_shelf_height = v; _queue_rebuild()
## Placeholder shelf size when no shelf model is set (width, thickness, depth).
@export var station_cabinet_size: Vector3 = Vector3(0.72, 0.04, 0.33):
	set(v): station_cabinet_size = v; _queue_rebuild()
## Screen outline (the monitor's bezel) and the height of its center.
@export var station_screen_size: Vector2 = Vector2(0.56, 0.458):
	set(v): station_screen_size = v; _queue_rebuild()
@export var station_screen_height: float = 1.36:
	set(v): station_screen_height = v; _queue_rebuild()
@export var cabinet_scene: PackedScene = preload("res://assets/props/station/station_shelf.tscn"):
	set(v): cabinet_scene = v if v != null else preload("res://assets/props/station/station_shelf.tscn"); _queue_rebuild()
@export var keyboard_scene: PackedScene = preload("res://assets/props/station/keyboard.tscn"):
	set(v): keyboard_scene = v if v != null else preload("res://assets/props/station/keyboard.tscn"); _queue_rebuild()

@export_group("Prefabs")
@export var bogie_scene: PackedScene:
	set(v): bogie_scene = v; _queue_rebuild()

# ————— placeholder palette —————

var _c_fabric := Color(0.17, 0.26, 0.46)
var _c_frame := Color(0.22, 0.22, 0.24)
var _c_metal := Color(0.62, 0.63, 0.66)
var _c_door := Color(0.72, 0.28, 0.18)
var _c_steel := Color(0.12, 0.12, 0.13)
var _c_porcelain := Color(0.93, 0.93, 0.95)
var _c_livery := Color(0.122, 0.231, 0.153)      # body green, for placeholders on the outside
var _c_underframe := Color(0.169, 0.169, 0.149)
var _c_frame_pale := Color(0.61, 0.60, 0.53)     # window bars and roof rails
var _c_brass := Color(0.79, 0.64, 0.29)

var _rebuild_queued := false

# ————— lifecycle —————

func _ready() -> void:
	rebuild()

func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()

# ————— pub api —————

func rebuild() -> void:
	_curtain_cache = {}
	_curtain_steps = {}
	_rebuild_queued = false
	_frame_meta = _read_frame_meta()
	var old := get_node_or_null(GENERATED_NAME)
	if old:
		remove_child(old)
		old.queue_free()

	var root := Node3D.new()
	root.name = GENERATED_NAME
	add_child(root)

	root.add_child(_build_shell())
	root.add_child(_build_decor())
	root.add_child(_build_windows())
	if exterior_details:
		root.add_child(_build_exterior())
	if lettering:
		root.add_child(_build_lettering())

	var anchors := Node3D.new()
	anchors.name = "Anchors"
	root.add_child(anchors)
	_build_seats(anchors)
	_build_tables(anchors)
	_build_lamps(anchors)
	_build_speaker(anchors)
	if roof_ac_unit:
		_build_ac_hatch(anchors)
	_build_racks(anchors)
	_build_doors(anchors)
	_build_toilet(anchors)
	_build_bogies(anchors)
	_build_extra(anchors)

## Width available to one double-seat unit (wall to aisle, minus a small gap).
func seat_unit_width() -> float:
	return _inner_half_width() - aisle_width * 0.5 - 0.05

# ————— hooks for other car types (SleeperCar overrides these) —————

# True when the saloon is a center-aisle seating saloon: saloon-face signs, brakes, route boards,
# vents, seat-bay lamps and the aisle runner are placed for that layout.
func _has_center_aisle() -> bool:
	return true

# Z of the walkway through the saloon (carpet runner, speaker).
func _aisle_z() -> float:
	return 0.0

# Sides of the car (-1 / +1 along Z) that get a window at `x` (both by default).
func _window_sides(_x: float) -> Array:
	return [-1.0, 1.0]

# Extra CSG for the shell (interior walls, door cuts), added after everything else.
func _add_interior_walls(_shell: CSGCombiner3D) -> void:
	pass

# Extra content for other car types, built last.
func _build_extra(_anchors: Node3D) -> void:
	pass

# Z of the litter bins on the end-section faces of the partitions (clear of the saloon door).
func _bin_z() -> float:
	return -0.95

# Width of the architrave jambs around sliding doors, and how far the head runs past them.
func _door_trim_width() -> float:
	return 0.06

func _door_head_overhang() -> float:
	return 0.04

# Width (local X) of a door leaf's meshes.
func _leaf_width(leaf: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in leaf.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != leaf:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * mi.mesh.get_aabb()
		lo = minf(lo, b.position.x)
		hi = maxf(hi, b.end.x)
	return hi - lo if hi > lo else 0.0

# Pocket side for a saloon door, in its marker's local X (0 = the default -Z pocket).
func _inner_door_pocket(_end_sign: float) -> float:
	return 0.0

# ————— derived dimensions —————

func _half_len() -> float:
	return length * 0.5

func _inner_half_width() -> float:
	return width * 0.5 - wall_thickness

# Y where the side wall meets the roof arc.
func _eave_y() -> float:
	return interior_height + roof_thickness - roof_rise

# Ceiling height at a given Z (inside the car).
func _ceiling_y(z: float) -> float:
	var rx := _inner_half_width() - tumblehome
	var az := absf(z)
	if az >= rx:
		return _eave_y()
	var ry := roof_rise - roof_thickness
	return _eave_y() + ry * sqrt(1.0 - (az / rx) * (az / rx))

# ±1: which end has the boarding vestibule / the WC.
func _boarding_sign() -> float:
	return 1.0 if boarding_at_front else -1.0

func _toilet_sign() -> float:
	return -_boarding_sign()

func _section_length(end_sign: float) -> float:
	return vestibule_length if end_sign == _boarding_sign() else toilet_section_length

# X of a point `d` meters inward from the inner face of the end wall at `end_sign`.
func _end_x(end_sign: float, d: float) -> float:
	return end_sign * (_half_len() - wall_thickness - d)

# Partition thickness. The saloon door leaf is 3.4 cm thick and its handles stay outside at the
# opening's edge, so the pocket fits inside a normal-thickness partition: the wall stays one flat,
# continuous surface with no casing bulge. (Anything thicker comes out of the end section.)
func _partition_t() -> float:
	return wall_thickness

# Inner lining of each end wall, hiding the gangway door's pocket (0 without a door model).
func _end_lining() -> float:
	return (CASING_T - wall_thickness) * 0.5 + 0.01 if end_door_scene != null else 0.0

func _partition_x(end_sign: float) -> float:
	return _end_x(end_sign, _section_length(end_sign) + wall_thickness - _partition_t() * 0.5)

# X of the partition face toward the end section (+1) or toward the saloon (-1).
func _partition_face(end_sign: float, toward_end: float) -> float:
	return _partition_x(end_sign) + end_sign * toward_end * _partition_t() * 0.5

# Passenger saloon span along X, between the two partitions.
func _saloon_start() -> float:
	return _partition_face(-1.0, -1.0)

func _saloon_end() -> float:
	return _partition_face(1.0, -1.0)

func _saloon_mid() -> float:
	return (_saloon_start() + _saloon_end()) * 0.5

# Free floor between the gangway door and the toilet room.
func _toilet_end_clear() -> float:
	return toilet_section_length - toilet_length

# Z of the toilet room's corridor-side wall, and of the corridor's center.
func _toilet_wall_z() -> float:
	return _inner_half_width() - toilet_width - wall_thickness * 0.5

func _corridor_z() -> float:
	return (-_inner_half_width() + _toilet_wall_z() - wall_thickness * 0.5) * 0.5

func _toilet_room_z() -> float:
	return _inner_half_width() - toilet_width * 0.5

# Saloon doors line up with the aisle (seats leave no room to side-step at the partition).
# On the WC side the door shifts off-center only as far as needed to clear the toilet wall.
func _partition_door_z(end_sign: float) -> float:
	if end_sign == _boarding_sign():
		return 0.0
	var wall_face := _toilet_wall_z() - wall_thickness * 0.5
	return minf(0.0, wall_face - inner_door_width * 0.5 - 0.02)

func _side_door_x() -> float:
	return _end_x(_boarding_sign(), vestibule_length * 0.5)

# X centers for items spaced evenly and centered inside the saloon.
func _saloon_slots(pitch: float, margin: float = 0.0) -> Array[float]:
	var slots: Array[float] = []
	var span := _saloon_end() - _saloon_start() - margin * 2.0
	if pitch <= 0.0 or span <= 0.0:
		return slots
	var count := int(floor(span / pitch))
	var first := _saloon_mid() - (count - 1) * pitch * 0.5
	for i in count:
		slots.append(first + i * pitch)
	return slots

# Bay windows plus, optionally, one midway between each pair of bays.
func _window_xs() -> Array[float]:
	var bays := _bay_centers()
	var xs: Array[float] = bays.duplicate()
	if windows_between_bays:
		for i in range(bays.size() - 1):
			# Needs room for a full window plus a 0.3 m pier on each side.
			if bays[i + 1] - bays[i] >= window_width * 2.0 + 0.6:
				xs.append((bays[i] + bays[i + 1]) * 0.5)
	return xs

func _bay_centers() -> Array[float]:
	var centers: Array[float] = []
	if seat_bays <= 0:
		return centers
	var span := _saloon_end() - _saloon_start()
	var pitch := bay_pitch if bay_pitch > 0.0 else span / seat_bays
	var first := _saloon_mid() - (seat_bays - 1) * pitch * 0.5
	for i in seat_bays:
		centers.append(first + i * pitch)
	return centers

# ————— cross-section profiles (x = across the car, y = up) —————

func _outer_profile() -> PackedVector2Array:
	var w := width * 0.5
	var skirt := 0.25 - floor_thickness
	var pts := PackedVector2Array([
		Vector2(-(w - 0.1), -floor_thickness),
		Vector2(w - 0.1, -floor_thickness),
		Vector2(w, skirt),
		Vector2(w, window_sill),
	])
	_append_roof_arc(pts, w - tumblehome, roof_rise)
	pts.append(Vector2(-w, window_sill))
	pts.append(Vector2(-w, skirt))
	return pts

func _inner_profile() -> PackedVector2Array:
	var wi := _inner_half_width()
	var pts := PackedVector2Array([
		Vector2(-wi, 0.0),
		Vector2(wi, 0.0),
		Vector2(wi, window_sill),
	])
	_append_roof_arc(pts, wi - tumblehome, roof_rise - roof_thickness)
	pts.append(Vector2(-wi, window_sill))
	return pts

# Half-ellipse from the right eave over the top to the left eave.
func _append_roof_arc(pts: PackedVector2Array, rx: float, ry: float) -> void:
	var eave := _eave_y()
	for i in ROOF_SEGMENTS + 1:
		var a := PI * float(i) / ROOF_SEGMENTS
		pts.append(Vector2(rx * cos(a), eave + ry * sin(a)))

# ————— shell —————

func _build_shell() -> CSGCombiner3D:
	var shell := CSGCombiner3D.new()
	shell.name = "Shell"
	shell.use_collision = true

	var t := wall_thickness
	var inner_len := length - t * 2.0
	var w := width * 0.5
	var ts := _toilet_sign()
	_apply_material_params()
	var wall_mat := interior_material

	# Unions first, subtractions after — CSG children are applied in order.
	_add_prism(shell, "Body", _outer_profile(), _half_len(), length, exterior_material)
	# Livery stripe below the windows, where the side wall is still vertical.
	_add_box(shell, "Stripe", Vector3(length - 0.3, 0.14, width + 0.02),
			Vector3(0, window_sill - 0.2, 0), stripe_material)
	_add_prism(shell, "Interior", _inner_profile(), inner_len * 0.5, inner_len,
			wall_mat, CSGShape3D.OPERATION_SUBTRACTION)

	for s in [-1.0, 1.0]:
		var pt := _partition_t()
		_add_prism(shell, "Partition", _inner_profile(), _partition_x(s) + pt * 0.5, pt, wall_mat)
		var lin := _end_lining()
		if lin > 0.0:
			var x_start: float = _half_len() - t if s > 0.0 else -_half_len() + t + lin
			_add_prism(shell, "EndLining", _inner_profile(), x_start, lin, wall_mat)

	# Toilet room: a wall facing the corridor and a wall facing the gangway end.
	var clear := _toilet_end_clear()
	_add_clipped_wall(shell, "ToiletSideWall", Vector3(toilet_length + t, interior_height, t),
			Vector3(_end_x(ts, clear - t + (toilet_length + t) * 0.5), interior_height * 0.5,
					_toilet_wall_z()), wall_mat)
	_add_clipped_wall(shell, "ToiletEndWall", Vector3(t, interior_height, toilet_width + t),
			Vector3(_end_x(ts, clear - t * 0.5), interior_height * 0.5,
					_inner_half_width() - (toilet_width + t) * 0.5), wall_mat)

	var wc_door_edge := _partition_door_z(ts) + inner_door_width * 0.5
	if _has_center_aisle() and wc_door_edge < 0.25:
		push_warning("PassengerCar: the WC-side saloon door no longer lines up with the aisle " +
				"(toilet_width too large) — the WC end may be unreachable.")
	if inner_door_width > aisle_width + 0.01:
		push_warning("PassengerCar: inner_door_width is wider than the aisle — the end seats will cover part of the saloon doors.")

	var cut_mat := trim_material
	var cut_depth := t * 2.0 + tumblehome * 2.0 + 0.2
	var sub := CSGShape3D.OPERATION_SUBTRACTION

	for s in [-1.0, 1.0]:
		_add_box(shell, "InnerDoorCut", Vector3(cut_depth, door_height, inner_door_width),
				Vector3(_partition_x(s), door_height * 0.5, _partition_door_z(s)), cut_mat, sub)
		_add_box(shell, "EndDoorCut", Vector3(cut_depth, door_height, end_door_width),
				Vector3(s * (_half_len() - t * 0.5), door_height * 0.5, 0), cut_mat, sub)

	# Boarding doors: both sides of the vestibule only.
	for z_side in [-1.0, 1.0]:
		_add_box(shell, "SideDoorCut", Vector3(side_door_width, door_height, cut_depth),
				Vector3(_side_door_x(), door_height * 0.5, z_side * (w - t * 0.5)), cut_mat, sub)

	_add_box(shell, "ToiletDoorCut", Vector3(toilet_door_width, door_height, t * 3.0),
			Vector3(_toilet_door_x(), door_height * 0.5, _toilet_wall_z()), cut_mat, sub)
	# Window openings, cut square to the leaning wall. With a frame model the aperture takes the
	# frame's outline (the unit sits in the wall); without one it is the rounded glass opening.
	_add_window_cut(shell, _window_xform(_toilet_door_x(), TOILET_WINDOW_Y, 1.0), TOILET_WINDOW_SIZE,
			window_corner_radius * 0.7, cut_depth, cut_mat)
	for x in _window_xs():
		for z_side in _window_sides(x):
			_add_window_cut(shell, _window_xform(x, window_sill + window_height * 0.5, z_side),
					Vector2(window_width, window_height), window_corner_radius, cut_depth, cut_mat)

	# Station screen recess: 9 cm deep from the inside, leaving a 3 cm outer skin.
	if computer_station:
		var sz := station_screen_size + Vector2(0.06, 0.06)
		_add_rounded_prism(shell, "ScreenRecess", _screen_xform(), sz.x - 0.04, sz.y - 0.04, 0.02, 0.115, -0.0225,
				_mat(Color(0.02, 0.02, 0.02)), sub)

	_add_interior_walls(shell)
	return shell

func _toilet_door_x() -> float:
	return _end_x(_toilet_sign(), _toilet_end_clear() + toilet_length * 0.5)

# Feed this car's layout heights to the procedural shell shaders (ignored by other material types).
func _apply_material_params() -> void:
	if exterior_material is ShaderMaterial:
		var ext := exterior_material as ShaderMaterial
		ext.set_shader_parameter("roof_start_y", _eave_y() + 0.08)
		ext.set_shader_parameter("skirt_top_y", 0.25 - floor_thickness)
		ext.set_shader_parameter("lining_y1", window_sill + window_height + 0.08)
		ext.set_shader_parameter("lining_y2", window_sill - 0.06)
		ext.set_shader_parameter("waist_y", window_sill - 0.13)
		ext.set_shader_parameter("eave_y", _eave_y())
		ext.set_shader_parameter("roof_rx", width * 0.5 - tumblehome)
		ext.set_shader_parameter("roof_ry", roof_rise)
		var wx := PackedFloat32Array()
		for x in _window_xs():
			if wx.size() < 24:
				wx.append(x)
		var count := wx.size()
		wx.resize(24)
		ext.set_shader_parameter("window_xs", wx)
		ext.set_shader_parameter("window_count", count)
		ext.set_shader_parameter("window_half_w", window_width * 0.5)
		ext.set_shader_parameter("window_bottom_y", window_sill)
		ext.set_shader_parameter("door_x", _side_door_x())
		ext.set_shader_parameter("door_half_w", side_door_width * 0.5)
	if carpet_material is ShaderMaterial:
		(carpet_material as ShaderMaterial).set_shader_parameter("half_size", _carpet_size() * 0.5)
	if window_glass_material is ShaderMaterial:
		(window_glass_material as ShaderMaterial).set_shader_parameter("half_size", Vector2(window_width, window_height) * 0.5)
	if frosted_glass_material is ShaderMaterial:
		(frosted_glass_material as ShaderMaterial).set_shader_parameter("half_size", TOILET_WINDOW_SIZE * 0.5)
	for m in [interior_material, trim_material]:
		if m is ShaderMaterial:
			var sm := m as ShaderMaterial
			sm.set_shader_parameter("sill_y", window_sill)
			sm.set_shader_parameter("eave_y", _eave_y())
			sm.set_shader_parameter("arc_rx", _inner_half_width() - tumblehome)
			sm.set_shader_parameter("arc_ry", roof_rise - roof_thickness)

# ————— decor (visual only, no collision) —————

func _build_decor() -> Node3D:
	var decor := Node3D.new()
	decor.name = "Decor"

	# The floor itself is part of the shell (floorboards come from interior_material).
	var run := _carpet_size()
	var az := _aisle_z()
	_add_mesh(decor, "Carpet", Vector3(run.x, 0.006, run.y), Vector3(_saloon_mid(), 0.003, az), carpet_material)
	# Brass binding strips along both long edges, and threshold plates at the two ends.
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.35
	for side in [-1.0, 1.0]:
		_add_mesh(decor, "CarpetRod", Vector3(run.x, 0.008, 0.016),
				Vector3(_saloon_mid(), 0.004, az + side * (run.y * 0.5 + 0.004)), brass)
		_add_mesh(decor, "CarpetThreshold", Vector3(0.03, 0.007, run.y + 0.024),
				Vector3(_saloon_mid() + side * (run.x * 0.5 + 0.012), 0.0035, az), brass)

	return decor

# ————— windows (visual only) —————

const TOILET_WINDOW_SIZE := Vector2(0.6, 0.5)
const TOILET_WINDOW_Y := 1.5

func _build_windows() -> Node3D:
	var root := Node3D.new()
	root.name = "Windows"
	_frame_meta = _read_frame_meta()
	var yc := window_sill + window_height * 0.5
	for x in _window_xs():
		for z_side in _window_sides(x):
			var xf := _window_xform(x, yc, z_side)
			if window_curtains:
				_add_curtains(root, xf)
			if not _frame_meta.is_empty():
				_build_framed_window(root, "Window", xf, Vector2(window_width, window_height), window_glass_material)
				continue
			_build_window(root, "Window", xf,
					Vector2(window_width, window_height), window_corner_radius, window_glass_material, true)
			# Varnished sill board inside, on top of the walnut dado rail.
			_add_mesh(root, "SillBoard", Vector3(window_width + 0.16, 0.025, 0.09),
					Vector3(x, window_sill + 0.0125, z_side * (_inner_half_width() - 0.045)), trim_material)
	var txf := _window_xform(_toilet_door_x(), TOILET_WINDOW_Y, 1.0)
	if not _frame_meta.is_empty():
		_build_framed_window(root, "ToiletWindow", txf, TOILET_WINDOW_SIZE, frosted_glass_material)
	else:
		_build_window(root, "ToiletWindow", txf, TOILET_WINDOW_SIZE, window_corner_radius * 0.7,
				frosted_glass_material, false)
	return root

var _frame_meta := {}

# ————— curtains —————

const CURTAIN_SHADER := preload("res://shaders/train/curtain_fabric.gdshader")
var _curtain_cache := {}
var _curtain_steps := {}         # curtain meshes by how far they are drawn (see _curtain_mesh)

# Curtains for one window (window space: X along the wall, Y up it, +Z out of the car): a brass
# rod with ball finials, a scalloped valance in front of it, and a curtain gathered at each side,
# held open by a gold cord with a tassel on a brass hook.
func _add_curtains(parent: Node3D, xform: Transform3D) -> void:
	var n := Node3D.new()
	n.name = "Curtains"
	n.transform = xform
	parent.add_child(n, true)
	if _curtain_cache.is_empty():
		_curtain_cache = _make_curtain_parts()
	var face := -wall_thickness * 0.5 - 0.005            # room-side face of the window frame
	var half_w := window_width * 0.5
	var top := window_height * 0.5 + CURTAIN_ROD_RISE      # rod height above the window centre
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	# Rod, wall brackets and finials.
	var rod_half := half_w + 0.17
	var rod_z := face - 0.05
	_add_rod(n, "CurtainRod", Vector3(-rod_half, top, rod_z), Vector3(rod_half, top, rod_z), 0.009, brass)
	for sx in [-1.0, 1.0]:
		_add_rod(n, "RodBracket", Vector3(sx * (rod_half - 0.03), top, face), Vector3(sx * (rod_half - 0.03), top, rod_z), 0.006, brass)
		_add_ball(n, "RodFinial", Vector3(sx * (rod_half + 0.016), top, rod_z), 0.019, brass)
	# Valance across the top, in front of the rod.
	var val := MeshInstance3D.new()
	val.name = "Valance"
	val.mesh = _curtain_cache.valance
	val.material_override = _curtain_cache.valance_mat
	val.position = Vector3(0, top + 0.03, rod_z - 0.025)
	n.add_child(val)
	# Side curtains (the mesh is built for the right-hand side; mirrored for the left).
	var tie: Dictionary = _curtain_cache.tie
	var set_node := CurtainSet.new()
	set_node.name = "CurtainSet"
	set_node.car = self
	n.add_child(set_node)
	for sx in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		c.name = "Curtain"
		c.mesh = _curtain_cache.curtain if sx > 0.0 else _curtain_cache.curtain_l
		c.material_override = _curtain_cache.curtain_mat
		c.position = Vector3(sx * (half_w + 0.02), top - CURTAIN_HANG, rod_z)
		n.add_child(c)
		set_node.curtains.append([c, sx])
		# Brass rings round the rod, one at each front fold of the heading, each with a pin hook
		# down into the heading tape. Each ring is a node the CurtainSet slides along the rod.
		var rings: Array = _curtain_cache.ring_xs
		for ri in rings.size():
			var rx: float = rings[ri]
			var x: float = sx * (half_w + 0.02 + rx)
			var rn := Node3D.new()
			rn.name = "Ring"
			rn.position = Vector3(x, top, rod_z)
			n.add_child(rn)
			var ring := MeshInstance3D.new()
			ring.name = "CurtainRing"
			ring.mesh = _curtain_cache.ring_mesh
			ring.material_override = brass
			ring.rotation.z = PI * 0.5
			rn.add_child(ring)
			_add_rod(rn, "RingHook", Vector3(0, -0.016, 0), Vector3(0, -CURTAIN_HANG - 0.004, -0.021), 0.0022, brass)
			set_node.rings.append([rn, sx, ri])
		# Tie-back: gold cord loop around the gathered cloth, a hook on the wall and a tassel.
		var tie_node := Node3D.new()
		tie_node.name = "TieBack"
		n.add_child(tie_node)
		set_node.ties.append(tie_node)
		var tp := Vector3(sx * (half_w + 0.02 + tie.x), top - CURTAIN_HANG + tie.y, rod_z + tie.z)
		var cord := MeshInstance3D.new()
		cord.name = "TieBack"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.8
		tm.outer_radius = 1.0
		tm.rings = 24
		tm.ring_segments = 8
		cord.mesh = tm
		cord.material_override = _curtain_cache.cord_mat
		cord.position = tp
		cord.scale = Vector3(tie.hw + 0.012, 0.05, tie.hd + 0.01)
		tie_node.add_child(cord)
		var hook := Vector3(sx * (half_w + 0.105), tp.y, face)
		_add_rod(n, "TieHook", hook, Vector3(hook.x, hook.y, tp.z), 0.005, brass)
		_add_ball(n, "TieHookKnob", Vector3(hook.x, hook.y, tp.z - 0.004), 0.011, brass)
		_add_tassel(tie_node, Vector3(sx * (half_w + 0.02 + tie.x + tie.hw + 0.012), tp.y, tp.z), _curtain_cache)
	set_node.half_w = half_w
	# What the player aims at to draw / open the curtains: the window opening.
	var area := Area3D.new()
	area.name = "CurtainArea"
	area.collision_layer = 2
	area.collision_mask = 0
	set_node.add_child(area)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(window_width + 0.45, window_height + 0.25, 0.12)
	cs.shape = bs
	cs.position = Vector3(0, 0.05, rod_z - 0.02)
	area.add_child(cs)

const CURTAIN_ROD_RISE := 0.14
const CURTAIN_HANG := 0.026     # heading tape below the rod's centre (hangs from the rings)

func _add_ball(parent: Node3D, ball_name: String, pos: Vector3, r: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = ball_name
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi, true)
	return mi

# Gold tassel hanging below `p`: a cord, a turned head and a skirt of threads.
func _add_tassel(parent: Node3D, p: Vector3, parts: Dictionary) -> void:
	_add_rod(parent, "TasselCord", p, p + Vector3(0, -0.035, 0), 0.0025, parts.cord_mat)
	var head := _add_ball(parent, "TasselHead", p + Vector3(0, -0.045, 0), 0.011, parts.cord_mat)
	head.scale = Vector3(1.0, 1.25, 1.0)
	var skirt := MeshInstance3D.new()
	skirt.name = "TasselSkirt"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.017
	cm.height = 0.07
	cm.radial_segments = 20
	cm.cap_bottom = false
	skirt.mesh = cm
	skirt.material_override = parts.tassel_mat
	skirt.position = p + Vector3(0, -0.092, 0)
	parent.add_child(skirt)

const CURTAIN_FOLDS := 7.0
const CURTAIN_STEPS := 24

# One side curtain (built for the right-hand side) drawn `close` of the way across the window:
# 0 = gathered and tied back, 1 = spread over its half of the window. Returns the mesh, the
# tie-back position and the ring positions (curtain-local X). Results are cached in steps.
func _curtain_mesh(close: float) -> Dictionary:
	var step := int(round(clampf(close, 0.0, 1.0) * CURTAIN_STEPS))
	var key := "curtain_step_%d" % step
	if _curtain_steps.has(key):
		return _curtain_steps[key]
	var c := float(step) / CURTAIN_STEPS
	var h := window_height + CURTAIN_ROD_RISE - 0.04
	var vt := 0.58                                  # tie-back height (fraction down)
	var flat_w := 0.62                              # cloth width when spread flat (m)
	var folds := CURTAIN_FOLDS
	var nu := 56
	var nv := 44
	var tie_j := int(round(vt * nv))
	# Drawn shape: a gently pleated panel from the window edge to just past the centre.
	var hw_c := (window_width * 0.5 + 0.08) * 0.5
	var cx_c := 0.03 - hw_c
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_l := SurfaceTool.new()          # the left-hand curtain: mirrored geometry, not a -1 scale
	st_l.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tie := {}
	for j in nv + 1:
		var v := float(j) / nv
		# Half width and centre of the gathered stack: pinched and pulled outward at the tie-back,
		# flaring again below it like a real tied curtain.
		var hw: float
		var cx: float
		var amp: float
		var bulge: float
		if v <= vt:
			var k := v / vt
			hw = lerpf(0.075, 0.03, pow(k, 1.6))
			cx = 0.03 * k * k
			amp = lerpf(0.022, 0.014, k)
			bulge = 0.02 * sin(PI * k)
		else:
			var k := (v - vt) / (1.0 - vt)
			hw = lerpf(0.03, 0.085, pow(k, 0.7))
			cx = lerpf(0.03, -0.005, pow(k, 0.8))
			amp = lerpf(0.014, 0.03, k)
			bulge = 0.006 * sin(PI * k)
		# The top follows the rings first; the bottom lags a little, as cloth does.
		var cv := clampf(c * (1.0 + 0.35 * (1.0 - v)), 0.0, 1.0)
		cv = cv * cv * (3.0 - 2.0 * cv)
		hw = lerpf(hw, hw_c, cv)
		cx = lerpf(cx, cx_c, cv)
		amp = lerpf(amp, 0.02, cv)
		bulge = lerpf(bulge, 0.004 * sin(PI * v), cv)
		var y := -v * h
		for i in nu + 1:
			var u := float(i) / nu
			var phase := u * folds * TAU
			var x := cx + (u - 0.5) * 2.0 * hw + sin(phase) * hw * 0.04
			var z := -(amp * (0.5 + 0.5 * cos(phase)) + bulge * (1.0 - u * 0.6))
			var yy := y + (0.008 * cos(phase * 0.5) if j == nv else 0.0)
			st.set_uv(Vector2(u * flat_w, v * h))
			st.set_uv2(Vector2(u, (1.0 - v) * h))
			st.add_vertex(Vector3(x, yy, z))
			st_l.set_uv(Vector2(u * flat_w, v * h))
			st_l.set_uv2(Vector2(u, (1.0 - v) * h))
			st_l.add_vertex(Vector3(-x, yy, z))
		if j == tie_j:
			tie = {"x": cx, "y": y, "z": -amp * 0.5 - bulge * 0.7, "hw": hw, "hd": amp * 0.5 + 0.008}
	_grid_indices(st, nu, nv)
	st.generate_normals()
	_grid_indices(st_l, nu, nv, true)
	st_l.generate_normals()
	var ring_xs: Array = []
	var top_hw := lerpf(0.075, hw_c, c)
	var top_cx := lerpf(0.0, cx_c, c)
	for k in int(folds) + 1:
		ring_xs.append(top_cx + (float(k) / folds - 0.5) * 2.0 * top_hw)
	var out := {"curtain": st.commit(), "curtain_l": st_l.commit(), "tie": tie, "ring_xs": ring_xs}
	_curtain_steps[key] = out
	return out

# Shared meshes and materials for every window's curtains.
func _make_curtain_parts() -> Dictionary:
	var parts := {}
	var cm := ShaderMaterial.new()
	cm.shader = CURTAIN_SHADER
	parts.curtain_mat = cm
	var vm := ShaderMaterial.new()
	vm.shader = CURTAIN_SHADER
	vm.set_shader_parameter("scallops", 4)
	parts.valance_mat = vm
	var gold := _mat(Color(0.74, 0.56, 0.24))
	gold.metallic = 0.4
	gold.roughness = 0.45
	parts.cord_mat = gold
	# Tassel skirt: fine vertical threads (striped albedo on the cylinder's UVs).
	var tassel := StandardMaterial3D.new()
	tassel.albedo_texture = _thread_texture()
	tassel.albedo_color = Color(0.85, 0.66, 0.3)
	tassel.metallic = 0.25
	tassel.roughness = 0.6
	tassel.cull_mode = BaseMaterial3D.CULL_DISABLED
	parts.tassel_mat = tassel

	var first := _curtain_mesh(0.0)
	parts.curtain = first.curtain
	parts.curtain_l = first.curtain_l
	parts.tie = first.tie
	parts.ring_xs = first.ring_xs
	var tm := TorusMesh.new()
	tm.inner_radius = 0.0125
	tm.outer_radius = 0.0165
	tm.rings = 20
	tm.ring_segments = 6
	parts.ring_mesh = tm

	# Valance: shallow pleated band across the rod, scalloped hem (cut in the shader).
	var vw := window_width + 0.34
	var vh := 0.15
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vu := 140
	var vv := 6
	for j in vv + 1:
		var v := float(j) / vv
		for i in vu + 1:
			var u := float(i) / vu
			var phase := u * 26.0 * TAU
			var z := -0.008 * (0.5 + 0.5 * cos(phase)) - 0.01 * v
			st2.set_uv(Vector2(u * vw * 1.6, v * vh))
			st2.set_uv2(Vector2(u, (1.0 - v) * vh))
			st2.add_vertex(Vector3((u - 0.5) * vw, -v * vh, z))
	_grid_indices(st2, vu, vv)
	st2.generate_normals()
	parts.valance = st2.commit()
	return parts

func _grid_indices(st: SurfaceTool, nu: int, nv: int, flip := false) -> void:
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			var b := a + 1
			var c := a + nu + 1
			var d := c + 1
			if flip:
				var t := b
				b = c
				c = t
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)

# Small striped texture: gold threads for the tassel skirts.
func _thread_texture() -> ImageTexture:
	var img := Image.create(64, 8, false, Image.FORMAT_RGB8)
	for x in 64:
		var t := 0.55 + 0.45 * pow(absf(sin(x * PI / 4.0)), 0.6)
		for y in 8:
			img.set_pixel(x, y, Color(t, t, t))
	return ImageTexture.create_from_image(img)

# Fit data stored on the frame prefab's root (see assets/props/windows/window_frame.tscn).
func _read_frame_meta() -> Dictionary:
	if window_frame_scene == null:
		return {}
	var inst := window_frame_scene.instantiate()
	var meta := {}
	for key in ["opening_size", "outer_size", "outer_center_y", "frame_depth", "glass_z", "corner_radius"]:
		if not inst.has_meta(key):
			inst.free()
			return {}
		meta[key] = inst.get_meta(key)
	inst.free()
	return meta

# Scale that stretches the frame's clear opening to `size`.
func _frame_scale(size: Vector2) -> Vector2:
	var o: Vector2 = _frame_meta.opening_size
	return Vector2(size.x / o.x, size.y / o.y)

func _add_window_cut(shell: Node, xform: Transform3D, size: Vector2, r: float, depth: float,
		material: Material) -> void:
	if _frame_meta.is_empty():
		_frame_meta = _read_frame_meta()
	if _frame_meta.is_empty():
		_add_rounded_prism(shell, "WindowCut", xform, size.x, size.y, r, depth, 0.0, material,
				CSGShape3D.OPERATION_SUBTRACTION)
		return
	var s := _frame_scale(size)
	var outer: Vector2 = _frame_meta.outer_size * s - Vector2(0.004, 0.004)
	var cy: float = _frame_meta.outer_center_y * s.y
	_add_rounded_prism(shell, "WindowCut", xform.translated_local(Vector3(0, cy, 0)), outer.x, outer.y,
			0.015, depth, 0.0, material, CSGShape3D.OPERATION_SUBTRACTION)

# Frame model fitted in the wall aperture: interior face 5 mm proud of the inner wall surface,
# stretched so its clear opening matches `size`, with our glass in the sash plane.
func _build_framed_window(parent: Node3D, win_name: String, xform: Transform3D, size: Vector2,
		glass: Material) -> void:
	var n := Node3D.new()
	n.name = win_name
	n.transform = xform
	parent.add_child(n, true)
	var s := _frame_scale(size)
	var face_z: float = -wall_thickness * 0.5 - 0.005 + _frame_meta.frame_depth
	var frame := window_frame_scene.instantiate() as Node3D
	frame.position = Vector3(0, 0, face_z)
	frame.scale = Vector3(s.x, s.y, 1.0)
	n.add_child(frame)
	var r: float = _frame_meta.corner_radius * minf(s.x, s.y)
	var pane := _add_rounded_prism(n, "Glass", Transform3D.IDENTITY, size.x + 0.02, size.y + 0.02, r, 0.006,
			face_z + _frame_meta.glass_z, glass)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# One window in its wall-aligned frame: glass, sash bars, varnished frame outside with a brass
# glazing bead, and a walnut architrave inside. Local z: +t/2 is the outer wall surface.
func _build_window(parent: Node3D, win_name: String, xform: Transform3D, size: Vector2, r: float,
		glass: Material, top_light: bool) -> void:
	var n := Node3D.new()
	n.name = win_name
	n.transform = xform
	parent.add_child(n, true)
	var half_t := wall_thickness * 0.5
	var glass_z := half_t - 0.025
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3

	var pane := _add_rounded_prism(n, "Glass", Transform3D.IDENTITY, size.x, size.y, r, 0.008, glass_z, glass)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_frame_ring(n, "OuterFrame", size.x, size.y, r, 0.055, 0.022, half_t + 0.011, trim_material)
	_add_frame_ring(n, "GlazingBead", size.x - 0.012, size.y - 0.012, maxf(r - 0.006, 0.01), 0.014, 0.01, half_t + 0.02, brass)
	_add_frame_ring(n, "InnerFrame", size.x, size.y, r, 0.07, 0.016, -half_t - 0.008, trim_material)
	if top_light:
		# Droplight sash: a transom bar at 70 % height, and a mullion splitting the top-light.
		var transom_y := -size.y * 0.5 + size.y * 0.7
		_add_mesh(n, "Transom", Vector3(size.x, 0.035, 0.035), Vector3(0, transom_y, glass_z), trim_material)
		var top_h := size.y * 0.5 - transom_y
		_add_mesh(n, "Mullion", Vector3(0.03, top_h, 0.03), Vector3(0, transom_y + top_h * 0.5, glass_z), trim_material)
		_add_mesh(n, "SashLift", Vector3(0.09, 0.02, 0.02), Vector3(0, transom_y - 0.06, glass_z - 0.03), brass)

# ————— exterior details (visual only, no collision) —————

# Exterior primitives replaced by the HD models (assets/models/hd_props: car_underframe,
# car_end_gear, boarding_steps, torpedo_vent, buffer) while _build_exterior runs with them.
const HD_EXT_SKIP := {
	"Solebar": 1, "Headstock": 1, "EquipmentBox": 1, "BufferStock": 1, "BufferHead": 1, "CouplingHook": 1, "StepHanger": 1,
	"EndHandle": 1, "PipeStub": 1, "Hose": 1, "HoseCoupling": 1, "LampBracket": 1, "LampBracketTop": 1, "LadderRung": 1,
	"LadderRail": 1, "TrussRod": 1, "QueenPost": 1, "Dynamo": 1, "DynamoBracket": 1, "BatteryBox": 1, "BatteryLid": 1,
	"RoofVent": 1, "RoofVentStem": 1,
}
var _ext_skip := false
var _ext_dummies: Array[Node] = []

func _ext_dummy() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	_ext_dummies.append(mi)
	return mi

func _build_exterior() -> Node3D:
	var ext := _build_exterior_parts()
	_ext_skip = false
	for d in _ext_dummies:
		d.free()
	_ext_dummies.clear()
	return ext

func _build_exterior_parts() -> Node3D:
	var ext := Node3D.new()
	ext.name = "Exterior"
	var w := width * 0.5
	var half := _half_len()
	var bottom := -floor_thickness
	# HD underframe, end gear and buffers (modelled for the default 16.8 m x 3.15 m body).
	# HD body mouldings for this car's layout (window beading, waist/cant rails, corners, roof strips).
	var mould := HDProps.body_model(self)
	if mould != "":
		HDProps.place(ext, mould, Transform3D.IDENTITY, "BodyMouldings")
	_ext_skip = HDProps.scene("car_underframe") != null
	if _ext_skip:
		var kx := length / 16.8
		HDProps.place(ext, "car_underframe", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(kx, 1, 1)), "Underframe")
		for s in [-1.0, 1.0]:
			HDProps.place(ext, "car_end_gear", HDProps.xf(Vector3(s * (half - 8.4), 0, 0), Vector3(0, 0.0 if s > 0.0 else PI, 0)), "EndGear")
			for zb in [-0.875, 0.875]:
				HDProps.place(ext, "buffer", HDProps.xf(Vector3(s * half, bottom - 0.14, zb), Vector3(0, 0.0 if s > 0.0 else PI, 0)), "Buffer")
	var under := _mat(_c_underframe)
	under.metallic = 0.3
	under.roughness = 0.7
	var pale := _mat(_c_frame_pale)
	pale.roughness = 0.5
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3

	# Underframe: solebars along both sides (they also hide the gap above the bogies),
	# headstocks at the ends and an equipment box between the bogies.
	for z_side in [-1.0, 1.0]:
		_add_mesh(ext, "Solebar", Vector3(length - 0.3, 0.28, 0.12),
				Vector3(0, bottom - 0.14, z_side * (w - 0.16)), under)
	for s in [-1.0, 1.0]:
		_add_mesh(ext, "Headstock", Vector3(0.16, 0.32, width - 0.3),
				Vector3(s * (half - 0.08), bottom - 0.16, 0), under)
	var box_len := maxf(length - bogie_inset * 2.0 - 3.8, 1.0)
	_add_mesh(ext, "EquipmentBox", Vector3(box_len, 0.48, 1.3), Vector3(0, bottom - 0.3, 0), under)

	# Buffers (two per end) and a coupling hook.
	for s in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var z: float = z_side * 0.875
			_add_cylinder(ext, "BufferStock", 0.085, 0.32, Vector3(s * (half + 0.16), bottom - 0.14, z), under)
			_add_cylinder(ext, "BufferHead", 0.19, 0.05, Vector3(s * (half + 0.345), bottom - 0.14, z), under)
		_add_mesh(ext, "CouplingHook", Vector3(0.28, 0.1, 0.09), Vector3(s * (half + 0.14), bottom - 0.16, 0), under)

	# Footboards and grab handles at the boarding doors, following the lean of the wall.
	var dx := _side_door_x()
	for z_side in [-1.0, 1.0]:
		# Two even steps of 33 cm between the floor and the platform side of the car.
		if _ext_skip:
			HDProps.place(ext, "boarding_steps", HDProps.xf(Vector3(dx, 0, 0), Vector3(0, 0.0 if z_side > 0.0 else PI, 0)), "BoardingSteps")
		else:
			_add_boarding_step(ext, Vector3(dx, bottom - 0.13, z_side * (w + 0.1)), z_side, side_door_width + 0.4, 0.24)
		# Lower step, hung from the footboard on two straps: halves the climb from the platform.
		var low := Vector3(dx, bottom - 0.46, z_side * (w + 0.2))
		if not _ext_skip:
			_add_boarding_step(ext, low, z_side, side_door_width + 0.1, 0.2)
		_add_step_collision(ext, dx, bottom, w, z_side)
		for sx in [-1.0, 1.0]:
			var hx: float = dx + sx * (side_door_width * 0.5 - 0.02)
			_add_mesh(ext, "StepHanger", Vector3(0.04, 0.36, 0.03),
					Vector3(hx, bottom - 0.3, z_side * (w + 0.14)), under)
		# Passenger notice on the body beside the door, toward the saloon.
		var nx: float = dx - _boarding_sign() * (side_door_width * 0.5 + 0.55)
		var sign_frame := Node3D.new()
		sign_frame.name = "BoardingNotice"
		sign_frame.transform = _window_xform(nx, 1.3, z_side)
		ext.add_child(sign_frame)
		_add_plate(sign_frame, "PLEASE LET PASSENGERS\nALIGHT BEFORE BOARDING",
				Vector3(0, 0, wall_thickness * 0.5 + 0.004), Vector3(0, 0, 1), "brass", false, 0.028)
		for side in [-1.0, 1.0]:
			var x: float = dx + side * (side_door_width * 0.5 + 0.1)
			var a := Vector3(x, 0.35, z_side * (_outer_wall_z(0.35) + 0.05))
			var b := Vector3(x, 1.75, z_side * (_outer_wall_z(1.75) + 0.05))
			_add_rod(ext, "GrabHandle", a, b, 0.014, brass)

	# End grab handles beside the gangway doors.
	for s in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var z: float = z_side * (end_door_width * 0.5 + 0.18)
			_add_rod(ext, "EndHandle", Vector3(s * (half + 0.05), 0.3, z), Vector3(s * (half + 0.05), 1.8, z), 0.014, brass)

	# Roof: grab rails on posts along both sides, and torpedo vents along the ridge.
	var rail_z := (w - tumblehome) * 0.72
	var rail_y := _outer_roof_y(rail_z) + 0.08
	var rail_len := length - 1.6
	for z_side in [-1.0, 1.0]:
		var z: float = z_side * rail_z
		_add_rod(ext, "RoofRail", Vector3(-rail_len * 0.5, rail_y, z), Vector3(rail_len * 0.5, rail_y, z), 0.012, pale)
		var posts := int(rail_len / 2.0) + 1
		for i in posts:
			var px := -rail_len * 0.5 + rail_len * float(i) / float(posts - 1)
			_add_rod(ext, "RoofRailPost", Vector3(px, _outer_roof_y(rail_z) - 0.02, z), Vector3(px, rail_y, z), 0.01, pale)
	var ridge := interior_height + roof_thickness
	var ts := _toilet_sign()
	var vent_xs: Array = [-length * 0.3, 0.0, length * 0.3]
	if roof_ac_unit:
		vent_xs = [-length * 0.3, 0.0]
	for vx in vent_xs:
		if _ext_skip:
			HDProps.place(ext, "torpedo_vent", HDProps.xf(Vector3(vx, ridge, 0)), "RoofVent")
		_add_cylinder(ext, "RoofVent", 0.07, 0.34, Vector3(vx, ridge + 0.12, 0), under)
		_add_rod(ext, "RoofVentStem", Vector3(vx, ridge - 0.02, 0), Vector3(vx, ridge + 0.08, 0), 0.03, under)
	if roof_ac_unit:
		_build_roof_ac(ext, _ac_x(), ridge, under, pale)

	# Louvred vents: toilet vent low on the WC side, and two high vents on each end wall.
	_add_louvre(ext, Vector3(_toilet_door_x(), 0.34, w + 0.012), Vector3(0.0, 0.0, 1.0), 0.42, 0.24, under)
	for s in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			_add_louvre(ext, Vector3(s * (half + 0.012), 1.9, z_side * 0.95), Vector3(s, 0.0, 0.0), 0.34, 0.2, under)

	# End hardware: brake and steam-heat hoses, lamp brackets, and a step ladder.
	for s in [-1.0, 1.0]:
		var ex: float = s * half
		for z_side in [-1.0, 1.0]:
			var z: float = z_side * 0.42
			var hose_top := Vector3(ex + s * 0.04, bottom - 0.3, z)
			var hose_end := Vector3(ex + s * 0.28, bottom - 0.62, z + z_side * 0.05)
			_add_rod(ext, "PipeStub", Vector3(ex - s * 0.1, bottom - 0.3, z), hose_top, 0.03, under)
			_add_rod(ext, "Hose", hose_top, hose_end, 0.028, _mat(Color(0.06, 0.06, 0.06)))
			_add_cylinder(ext, "HoseCoupling", 0.045, 0.1, hose_end, brass)
		for z_side in [-1.0, 1.0]:
			var lz: float = z_side * (w - 0.18)
			_add_mesh(ext, "LampBracket", Vector3(0.1, 0.03, 0.08), Vector3(ex + s * 0.05, 0.9, lz), under)
			_add_mesh(ext, "LampBracketTop", Vector3(0.1, 0.03, 0.08), Vector3(ex + s * 0.05, 2.1, lz * 0.55), under)
		var ladder_z := -(end_door_width * 0.5 + 0.45)
		for y in [0.1, 0.45, 0.8, 1.15, 1.5, 1.85]:
			_add_rod(ext, "LadderRung", Vector3(ex + s * 0.06, y, ladder_z - 0.2), Vector3(ex + s * 0.06, y, ladder_z + 0.2), 0.012, under)
		for zz in [ladder_z - 0.2, ladder_z + 0.2]:
			_add_rod(ext, "LadderRail", Vector3(ex + s * 0.02, 0.1, zz), Vector3(ex + s * 0.06, 1.85, zz), 0.014, under)

	# Underframe: truss rods with queen posts, a dynamo by one bogie, and battery boxes.
	var tx: float = half - bogie_inset - 1.9
	for z_side in [-1.0, 1.0]:
		var z: float = z_side * (w - 0.4)
		var a := Vector3(-tx, bottom - 0.25, z)
		var b := Vector3(-1.4, bottom - 0.62, z)
		var c := Vector3(1.4, bottom - 0.62, z)
		var d := Vector3(tx, bottom - 0.25, z)
		_add_rod(ext, "TrussRod", a, b, 0.016, under)
		_add_rod(ext, "TrussRod", b, c, 0.016, under)
		_add_rod(ext, "TrussRod", c, d, 0.016, under)
		for qx in [-1.4, 1.4]:
			_add_rod(ext, "QueenPost", Vector3(qx, bottom - 0.28, z), Vector3(qx, bottom - 0.62, z), 0.02, under)
	var dyn_x: float = -ts * (half - bogie_inset - 2.1)
	_add_cylinder(ext, "Dynamo", 0.13, 0.42, Vector3(dyn_x, bottom - 0.36, w - 0.62), under)
	_add_mesh(ext, "DynamoBracket", Vector3(0.36, 0.1, 0.26), Vector3(dyn_x, bottom - 0.24, w - 0.62), under)
	for bx in [-0.9, 0.9]:
		for z_side in [-1.0, 1.0]:
			_add_mesh(ext, "BatteryBox", Vector3(1.0, 0.36, 0.3), Vector3(bx, bottom - 0.26, z_side * 0.85), under)
			_add_mesh(ext, "BatteryLid", Vector3(1.02, 0.03, 0.32), Vector3(bx, bottom - 0.07, z_side * 0.85), pale)
	return ext

# ————— lettering (visual only) —————

const LETTER_FONT := "res://assets/fonts/PlayfairDisplay.ttf"
## Sign plates: a plain, sturdy sans (Oswald) that stays legible at small sizes.
const SIGN_FONT := "res://assets/fonts/Oswald.ttf"
const SIGN_CAP_RATIO := 0.81      # Oswald cap height / em (OS/2 table: 810 / 1000)
const SIGN_LINE_SPACING := -34.0  # tightens Oswald's tall 1.48 em line box (pixels at size 128)

var _sign_font_cache: Font

# Oswald Medium, rendered as a multichannel distance field so it stays crisp at any distance.
func _sign_font() -> Font:
	if _sign_font_cache:
		return _sign_font_cache
	if not ResourceLoader.exists(SIGN_FONT):
		_sign_font_cache = ThemeDB.fallback_font
		return _sign_font_cache
	var base := load(SIGN_FONT) as FontFile
	base.multichannel_signed_distance_field = true
	base.msdf_pixel_range = 16
	base.msdf_size = 128
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	fv.spacing_glyph = 4
	_sign_font_cache = fv
	return _sign_font_cache

const NO_SMOKING_SHADER := preload("res://shaders/props/no_smoking.gdshader")
const NO_SMOKING_SIZE := 0.13

func _build_lettering() -> Node3D:
	var root := Node3D.new()
	root.name = "Lettering"
	var w := width * 0.5
	var half := _half_len()
	var y_low := 0.3  # lower body, between the skirt and the waist moulding
	for z_side in [-1.0, 1.0]:
		var z: float = z_side * (w + 0.003)
		_add_text(root, "CompanyName", company_name, Vector3(0, y_low, z), z_side, 0.1, 700, 0.06)
		for s in [-1.0, 1.0]:
			_add_text(root, "CarNumber", car_number, Vector3(s * (half - 3.4), y_low, z), z_side, 0.085, 600, 0.02)
		# Class numeral on the body beside the boarding door, toward the saloon.
		var bx := _side_door_x() - _boarding_sign() * (side_door_width * 0.5 + 0.45)
		_add_text(root, "ClassNumeral", class_numeral, Vector3(bx, y_low, z), z_side, 0.22, 800, 0.0)

	var t := wall_thickness
	var bs := _boarding_sign()
	for s in [-1.0, 1.0]:
		var to_car := _car_label(s)
		# Direction plates: above the saloon door (saloon side) and above the gangway door (inside).
		var part_x: float = _partition_face(s, -1.0) - s * 0.004
		# At the end of the train the gangway door leads nowhere: no plate on it, and the saloon
		# door at that end only leads to the W.C. (or the vestibule).
		var part_label := to_car if not to_car.is_empty() else ("W.C." if s == _toilet_sign() else "EXIT")
		_add_plate(root, part_label, Vector3(part_x, door_height + 0.15, _partition_door_z(s)), Vector3(-s, 0, 0), "brass", true, 0.045)
		var end_x: float = s * (half - t - _end_lining() - 0.004)
		if not to_car.is_empty():
			_add_plate(root, to_car, Vector3(end_x, door_height + 0.15, 0), Vector3(-s, 0, 0), "brass", true, 0.045)
		if not _has_center_aisle():
			continue
		# Saloon side of the partition: NO SMOKING on one side of the door, emergency brake sign on the other.
		var ns_z := _partition_door_z(s) - (inner_door_width * 0.5 + 0.4)
		var ns_w := _add_plate(root, "NO SMOKING", Vector3(part_x, 1.75, ns_z), Vector3(-s, 0, 0))
		# Pictogram beside it, on the side away from the door.
		_add_symbol_plate(root, "NoSmokingSymbol", Vector3(part_x, 1.75, ns_z - ns_w * 0.5 - 0.02 - NO_SMOKING_SIZE * 0.5),
				Vector3(-s, 0, 0), NO_SMOKING_SIZE, NO_SMOKING_SHADER)
		_add_plate(root, "EMERGENCY\nBRAKE", Vector3(part_x, 1.8, inner_door_width * 0.5 + 0.45), Vector3(-s, 0, 0), "red")
		_add_plate(root, "WARNING\nIMPROPER USE IS PUNISHABLE\nBY A FINE AND MAY LEAD TO\nCRIMINAL PROSECUTION",
				Vector3(part_x, 1.17, inner_door_width * 0.5 + 0.45), Vector3(-s, 0, 0), "red", false, 0.025)
	# Fire extinguisher sign above the extinguisher (vestibule face of the boarding-end partition).
	var ext_x: float = _partition_face(bs, 1.0) + bs * 0.004
	_add_plate(root, "FIRE\nEXTINGUISHER", Vector3(ext_x, 1.62, inner_door_width * 0.5 + 0.35), Vector3(bs, 0, 0), "red")
	var wc_face_z := _toilet_wall_z() - t * 0.5 - 0.004
	_add_plate(root, "LAVATORY", Vector3(_toilet_door_x(), door_height + 0.12, wc_face_z), Vector3(0, 0, -1))
	return root

# Label for the car beyond the doors at end `end_sign` (car 1 is nearest the locomotive).
func _car_label(end_sign: float) -> String:
	var front := 1.0 if front_is_positive_x else -1.0
	var override := front_door_label if end_sign == front else rear_door_label
	if not override.is_empty():
		return override
	var n := car_index - 1 if end_sign == front else car_index + 1
	if n < 1 or n > train_formation.size():
		return ""
	if train_formation[n - 1].begins_with("LOCOMOTIVE"):
		return "LOCOMOTIVE"
	return "CAR %d" % n

# Painted-on text facing the wall's outward normal (+Z side: facing = 1, -Z side: facing = -1).
func _add_text(parent: Node3D, label_name: String, text: String, pos: Vector3, facing: float,
		cap_height: float, weight: int, spacing: float) -> Label3D:
	var l := Label3D.new()
	l.name = label_name
	l.text = text
	l.font = _letter_font(weight, int(spacing * 128.0 / 0.1))
	l.font_size = 128
	l.pixel_size = cap_height / 90.0
	l.outline_size = 10
	l.outline_modulate = Color(0.05, 0.08, 0.06, 0.85)
	l.modulate = lettering_color
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.position = pos
	l.rotation.y = 0.0 if facing > 0.0 else PI
	parent.add_child(l, true)
	return l

# Wall plate on a wall facing `normal` (an axis vector). Style "brass" = engraved brass with dark
# lettering, "red" = red enamel with cream lettering. Text may have several lines ("\n").
# `arrow` adds an up-pointing arrow (= "through this door") to the left of the text.
func _add_plate(parent: Node3D, text: String, pos: Vector3, normal: Vector3,
		style: String = "brass", arrow: bool = false, cap: float = 0.034) -> float:
	var n := Node3D.new()
	n.name = "Sign"
	var along := Vector3(0, 0, -normal.x) if absf(normal.x) > 0.5 else Vector3(normal.z, 0, 0)
	n.transform = Transform3D(Basis(along, Vector3.UP, normal), pos)
	parent.add_child(n, true)

	# Measure the text with the actual sign font, so the plate always fits it.
	var font := _sign_font()
	var fs := 128
	var px := cap / (fs * SIGN_CAP_RATIO)
	var lines := text.split("\n")
	var text_w := 0.0
	for line in lines:
		text_w = maxf(text_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px)
	var line_h := font.get_height(fs) * px + SIGN_LINE_SPACING * px
	var arrow_w := cap * 1.6 if arrow else 0.0
	var plate_w := text_w + arrow_w + cap * 1.6
	var plate_h := lines.size() * line_h + cap * 0.5
	var plate := _mat(_c_brass) if style == "brass" else _mat(Color(0.55, 0.07, 0.05))
	plate.metallic = 0.85 if style == "brass" else 0.1
	plate.roughness = 0.3 if style == "brass" else 0.35
	var ink := Color(0.12, 0.08, 0.04) if style == "brass" else Color(0.95, 0.9, 0.78)
	_add_mesh(n, "Plate", Vector3(plate_w, plate_h, 0.006), Vector3.ZERO, plate)
	# Thin border line inset from the plate edge.
	var border := _mat(ink)
	for yy in [plate_h * 0.5 - cap * 0.22, -(plate_h * 0.5 - cap * 0.22)]:
		_add_mesh(n, "Border", Vector3(plate_w - cap * 0.44, cap * 0.05, 0.002), Vector3(0, yy, 0.004), border)
	for xx in [plate_w * 0.5 - cap * 0.22, -(plate_w * 0.5 - cap * 0.22)]:
		_add_mesh(n, "Border", Vector3(cap * 0.05, plate_h - cap * 0.44, 0.002), Vector3(xx, 0, 0.004), border)

	var l := Label3D.new()
	l.name = "Text"
	l.text = text
	l.font = font
	l.font_size = fs
	l.pixel_size = px
	l.line_spacing = SIGN_LINE_SPACING
	l.modulate = ink
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.double_sided = false
	l.shaded = true
	# Smooth anti-aliased edges (alpha-cut breaks thin strokes up at a distance).
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.render_priority = 1
	l.position = Vector3(arrow_w * 0.5, 0, 0.007)
	n.add_child(l)

	if arrow:
		var ax := -plate_w * 0.5 + cap * 0.9 + arrow_w * 0.25
		var head := PrismMesh.new()
		head.size = Vector3(cap * 1.2, cap * 0.75, 0.003)
		var hm := MeshInstance3D.new()
		hm.name = "ArrowHead"
		hm.mesh = head
		hm.material_override = border
		hm.position = Vector3(ax, cap * 0.45, 0.005)
		n.add_child(hm)
		_add_mesh(n, "ArrowShaft", Vector3(cap * 0.32, cap * 0.95, 0.003), Vector3(ax, -cap * 0.35, 0.005), border)
	return plate_w

# Square cream-enamel plate carrying a pictogram (drawn by `shader`), with a brass rim and screws.
func _add_symbol_plate(parent: Node3D, sign_name: String, pos: Vector3, normal: Vector3, size: float, shader: Shader) -> void:
	var n := Node3D.new()
	n.name = sign_name
	var along := Vector3(0, 0, -normal.x) if absf(normal.x) > 0.5 else Vector3(normal.z, 0, 0)
	n.transform = Transform3D(Basis(along, Vector3.UP, normal), pos)
	parent.add_child(n, true)
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_mesh(n, "Rim", Vector3(size, size, 0.005), Vector3(0, 0, 0.0025), brass)
	var enamel := _mat(Color(0.95, 0.93, 0.87))
	enamel.roughness = 0.35
	_add_mesh(n, "Enamel", Vector3(size - 0.012, size - 0.012, 0.002), Vector3(0, 0, 0.006), enamel)
	var face := MeshInstance3D.new()
	face.name = "Pictogram"
	var q := QuadMesh.new()
	q.size = Vector2(size - 0.03, size - 0.03)
	face.mesh = q
	var m := ShaderMaterial.new()
	m.shader = shader
	face.material_override = m
	face.position = Vector3(0, 0, 0.0072)
	n.add_child(face)

# Playfair Display at a given weight (variable font), with extra letter spacing in font pixels.
func _letter_font(weight: int, spacing_px: int = 0) -> Font:
	if not ResourceLoader.exists(LETTER_FONT):
		return null
	var fv := FontVariation.new()
	fv.base_font = load(LETTER_FONT)
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	fv.spacing_glyph = spacing_px
	return fv

# Roof-mounted air-conditioning housing: a long low hood with louvred sides and a grille on top.
func _build_roof_ac(parent: Node3D, cx: float, ridge: float, body: Material, trim: Material) -> void:
	var ac_len := 2.0
	var ac_w := 1.1
	var h := 0.26
	var base_y := _outer_roof_y(ac_w * 0.5) - 0.01
	var top_y := ridge + h
	var hood := _mat(_c_livery.darkened(0.15))
	hood.roughness = 0.55
	_add_mesh(parent, "ACHousing", Vector3(ac_len, top_y - base_y, ac_w), Vector3(cx, (top_y + base_y) * 0.5, 0), hood)
	_add_mesh(parent, "ACCap", Vector3(ac_len + 0.04, 0.03, ac_w + 0.04), Vector3(cx, top_y + 0.015, 0), hood)
	_add_mesh(parent, "ACCapEdge", Vector3(ac_len + 0.05, 0.012, ac_w + 0.05), Vector3(cx, top_y + 0.002, 0), trim)
	_add_mesh(parent, "ACGrille", Vector3(ac_len * 0.55, 0.02, ac_w * 0.55), Vector3(cx, top_y + 0.04, 0), body)
	for z_side in [-1.0, 1.0]:
		for i in 3:
			var lx := cx + (float(i) - 1.0) * ac_len * 0.3
			_add_louvre(parent, Vector3(lx, (top_y + base_y) * 0.5 + 0.02, z_side * (ac_w * 0.5 + 0.012)),
					Vector3(0, 0, z_side), 0.5, (top_y - base_y) * 0.6, body)
	for s in [-1.0, 1.0]:
		_add_louvre(parent, Vector3(cx + s * (ac_len * 0.5 + 0.012), (top_y + base_y) * 0.5 + 0.02, 0),
				Vector3(s, 0, 0), 0.7, (top_y - base_y) * 0.6, body)

# Louvred vent on a wall: frame plus angled slats. `facing` is the wall's outward normal (X or Z axis).
func _add_louvre(parent: Node3D, center: Vector3, facing: Vector3, vw: float, vh: float,
		material: Material) -> void:
	var along := Vector3(0, 0, 1) if absf(facing.x) > 0.5 else Vector3(1, 0, 0)
	var n := Node3D.new()
	n.name = "Louvre"
	n.transform = Transform3D(Basis(along, Vector3.UP, facing), center)
	parent.add_child(n, true)
	var frame := 0.025
	_add_mesh(n, "FrameTop", Vector3(vw, frame, 0.02), Vector3(0, vh * 0.5, 0), material)
	_add_mesh(n, "FrameBottom", Vector3(vw, frame, 0.02), Vector3(0, -vh * 0.5, 0), material)
	_add_mesh(n, "FrameL", Vector3(frame, vh, 0.02), Vector3(-vw * 0.5, 0, 0), material)
	_add_mesh(n, "FrameR", Vector3(frame, vh, 0.02), Vector3(vw * 0.5, 0, 0), material)
	_add_mesh(n, "Back", Vector3(vw, vh, 0.004), Vector3(0, 0, -0.008), _mat(Color(0.03, 0.03, 0.03)))
	var slats := maxi(int(vh / 0.035), 3)
	for i in slats:
		var y := -vh * 0.5 + vh * (float(i) + 0.5) / float(slats)
		var slat := _add_mesh(n, "Slat", Vector3(vw - frame, 0.004, 0.03), Vector3(0, y, 0.004), material)
		slat.rotation.x = deg_to_rad(40.0)

# Outer surface of the side wall (|z|) at height y: vertical below the sill, leaning to the eave.
func _outer_wall_z(y: float) -> float:
	var w := width * 0.5
	if y <= window_sill:
		return w
	return w - tumblehome * clampf((y - window_sill) / maxf(_eave_y() - window_sill, 0.01), 0.0, 1.0)

# Outer roof surface height at |z|.
func _outer_roof_y(z: float) -> float:
	var rx := width * 0.5 - tumblehome
	var k := clampf(absf(z) / rx, 0.0, 1.0)
	return _eave_y() + roof_rise * sqrt(1.0 - k * k)

# ————— anchors —————

func _build_seats(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Seats")
	# Anchor per double-seat unit, centered between aisle and wall. In each bay the
	# rear seat faces +X (with travel) and the front seat faces -X, knees toward the middle.
	var z := (aisle_width * 0.5 + _inner_half_width()) * 0.5
	var unit_w := seat_unit_width()
	var offset := bay_length * 0.5 - SEAT_DEPTH * 0.5
	var i := 0
	for x in _bay_centers():
		i += 1
		for z_side in [-1.0, 1.0]:
			var tag := "L" if z_side < 0.0 else "R"
			var fwd := _add_marker(group, "Seat_%s_%02d_Fwd" % [tag, i], Vector3(x - offset, 0, z_side * z))
			fwd.rotation.y = -PI * 0.5
			var back := _add_marker(group, "Seat_%s_%02d_Back" % [tag, i], Vector3(x + offset, 0, z_side * z))
			back.rotation.y = PI * 0.5
			for m in [fwd, back]:
				if not _instance(m, seat_scene):
					m.add_child(_seat_placeholder(unit_w))

func _build_tables(anchors: Node3D) -> void:
	if not bay_tables:
		return
	var group := _add_group(anchors, "Tables")
	# Centered in each bay, touching the wall; origin on the floor at the table's center.
	var z := _inner_half_width() - table_depth * 0.5
	var i := 0
	for x in _bay_centers():
		i += 1
		for z_side in [-1.0, 1.0]:
			var tag := "L" if z_side < 0.0 else "R"
			var m := _add_marker(group, "Table_%s_%02d" % [tag, i], Vector3(x, 0, z_side * z))
			# Marker -Z points toward the aisle.
			m.rotation.y = PI if z_side < 0.0 else 0.0
			if not _instance(m, table_scene):
				m.add_child(_table_placeholder())

func _build_lamps(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Lamps")
	# Saloon: one lamp over every other bay (bays 2 and 4 of 5), each lighting its neighbours too.
	# End sections: one in the WC-end passage (in front of the toilet door) and one in the toilet.
	# Vestibule: one lamp over the boarding doors.
	var spots: Array = []
	var bays := _bay_centers()
	for i in (range(1, bays.size(), 2) if _has_center_aisle() else []):
		spots.append(["Lamp_Saloon_%02d" % (spots.size() + 1), Vector3(bays[i], 0, 0), 5.2, 1.0])
	var ts := _toilet_sign()
	# Passage lamp on the line of the toilet's end wall: it lights the passage, the computer niche
	# and the staff cabinet opposite the toilet door.
	spots.append(["Lamp_Vestibule", Vector3(_end_x(_boarding_sign(), vestibule_length * 0.5), 0, 0), 3.2, 1.0])
	spots.append(["Lamp_Passage", Vector3(_end_x(ts, _toilet_end_clear() - wall_thickness), 0, 0.1), 3.4, 1.0])
	spots.append(["Lamp_Toilet", Vector3(_toilet_door_x(), 0, _toilet_room_z()), 2.2, 0.7])
	for spot in spots:
		var pos: Vector3 = spot[1]
		pos.y = _ceiling_y(pos.z)
		var m := _add_marker(group, spot[0], pos)
		m.rotation.y = -PI * 0.5
		m.set_meta("dynamic", true)          # switched from the staff cabinet: not merged
		if not _instance(m, lamp_scene):
			m.add_child(_lamp_placeholder())
		# The light belongs to the car, so it stays when a lamp model replaces the placeholder.
		var light := OmniLight3D.new()
		light.name = "Light"
		light.position.y = -0.3
		light.omni_range = spot[2]
		light.light_energy = spot[3]
		light.light_color = Color(1.0, 0.9, 0.74)
		# Falls off faster than the default: pools of lamplight with the corners and the floor
		# between the lamps in shade.
		light.omni_attenuation = 1.8
		light.shadow_enabled = true
		m.add_child(light)

const CEILING_RIB_PITCH := 1.05   # matches rib_pitch in car_interior.gdshader

# PA speaker flush on the ceiling crown over the middle bay (between the two saloon lamps).
func _build_speaker(anchors: Node3D) -> void:
	if speaker_scene == null:
		return
	# Centred between two ceiling ribs (interior shader: a rib every CEILING_RIB_PITCH along X).
	var x := (roundf(_saloon_mid() / CEILING_RIB_PITCH - 0.5) + 0.5) * CEILING_RIB_PITCH
	var m := _add_marker(anchors, "Speaker", Vector3(x, _ceiling_y(_aisle_z()) - 0.002, _aisle_z()))
	# Marker -Z (the grille's face) points down into the car, +Z (its back) up into the ceiling,
	# tilted with the ceiling's curve.
	m.basis = Basis(Quaternion(Vector3.UP, _ceiling_basis(_aisle_z()) * Vector3(0, 1, 0))) * Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var n := _instance(m, speaker_scene)
	if n:
		_back_to_wall(n)

func _build_racks(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Racks")
	# Back edge 1 cm off the wall, which leans inward by the full tumblehome at eave height.
	var z := _inner_half_width() - tumblehome - rack_depth * 0.5 - 0.01
	var i := 0
	for x in _bay_centers():
		i += 1
		for z_side in [-1.0, 1.0]:
			var tag := "L" if z_side < 0.0 else "R"
			var m := _add_marker(group, "Rack_%s_%02d" % [tag, i], Vector3(x, rack_height, z_side * z))
			# Marker -Z points toward the aisle.
			m.rotation.y = PI if z_side < 0.0 else 0.0
			if not _instance(m, rack_scene):
				m.add_child(_rack_placeholder(bay_length - 0.15))

func _build_doors(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Doors")
	var t := wall_thickness
	var bs := _boarding_sign()

	# Boarding doors. Marker -Z points out of the car.
	var i := 0
	for z_side in [-1.0, 1.0]:
		i += 1
		var m := _add_marker(group, "SideDoor_%02d" % i,
				Vector3(_side_door_x(), 0, z_side * (width * 0.5 - t * 0.5)))
		m.rotation.y = 0.0 if z_side < 0.0 else PI
		var sd := _instance(m, side_door_scene)
		if sd:
			_lean_with_wall(sd)
			var ed := _hinge_door(m, sd, side_door_width, door_height, 0.08, "exit door", _lean_at(door_height))
			ed.lock_while_moving = true
		else:
			m.add_child(_side_door_placeholder())

	for s in [-1.0, 1.0]:
		var end_name := "Boarding" if s == bs else "WC"
		# Saloon doors. Marker +Z (local) points along +X; the leaf rests on the saloon side.
		var inner := _add_marker(group, "InnerDoor_" + end_name,
				Vector3(_partition_x(s), 0, _partition_door_z(s)))
		inner.rotation.y = PI * 0.5
		var inner_leaf := _instance(inner, inner_door_scene)
		if inner_leaf:
			# Fit the leaf to the opening width (the model is made 0.7 m wide).
			var lw := _leaf_width(inner_leaf)
			if lw > 0.0 and absf(lw - inner_door_width) > 0.01:
				inner_leaf.scale.x = inner_door_width / lw
			var ph := _partition_t() * 0.5
			var idoor := _hang_sliding_door(inner, inner_leaf, inner_door_width, 0.0, -ph, ph, _inner_door_pocket(s))
			idoor.door_name = "door"
		else:
			inner.add_child(_sliding_door_placeholder(inner_door_width, -1.0, -s))
		# Gangway doors. Marker -Z points out of the car; the leaf rests inside.
		var gang := _add_marker(group, "EndDoor_" + end_name,
				Vector3(s * (_half_len() - t * 0.5), 0, 0))
		gang.rotation.y = -s * PI * 0.5
		var gang_leaf := _instance(gang, end_door_scene)
		if gang_leaf:
			# Marker local +Z points into the car; the wall runs from the outer face (-t/2) to the
			# lining's inner face. The leaf runs in the middle of that thickness.
			var inner_face := t * 0.5 + _end_lining()
			var gdoor := _hang_sliding_door(gang, gang_leaf, end_door_width, (inner_face - t * 0.5) * 0.5, -t * 0.5, inner_face)
			gdoor.door_name = "gangway door"
			if _car_label(s).is_empty():
				gdoor.always_locked = true
				gdoor.locked_text = "No access - end of train"
		else:
			gang.add_child(_sliding_door_placeholder(end_door_width, 1.0, 1.0))

	# Toilet door on the corridor wall. Marker -Z faces the corridor.
	var wc := _add_marker(group, "ToiletDoor", Vector3(_toilet_door_x(), 0, _toilet_wall_z()))
	var wc_door := _instance(wc, toilet_door_scene)
	if not wc_door:
		wc.add_child(_hinged_door_placeholder(toilet_door_width))
	else:
		var lock := wc_door.find_child("Lock", true, false)
		if lock is ToiletLock:
			(lock as ToiletLock).locked = toilet_occupied
		var wd := _hinge_door(wc, wc_door, toilet_door_width, door_height, 0.06, "W.C. door")
		wd.lock_node = lock
	# Walnut architrave on both faces and a lining across the wall thickness.
	var dw := toilet_door_width
	for face_z in [-t * 0.5 - 0.01, t * 0.5 + 0.01]:
		_add_mesh(wc, "DoorHead", Vector3(dw + 0.2, 0.08, 0.02), Vector3(0, door_height + 0.04, face_z), trim_material)
		for side in [-1.0, 1.0]:
			_add_mesh(wc, "DoorJamb", Vector3(0.06, door_height, 0.02), Vector3(side * (dw * 0.5 + 0.03), door_height * 0.5, face_z), trim_material)
	_add_mesh(wc, "OpeningHead", Vector3(dw, 0.012, t), Vector3(0, door_height - 0.006, 0), trim_material)
	for side in [-1.0, 1.0]:
		_add_mesh(wc, "OpeningJamb", Vector3(0.012, door_height, t), Vector3(side * (dw * 0.5 - 0.006), door_height * 0.5, 0), trim_material)

# The lavatory door's lock (null without a door model that has one).
func toilet_lock() -> ToiletLock:
	var g := get_node_or_null(GENERATED_NAME)
	if g == null:
		return null
	var door := g.find_child("ToiletDoor", true, false)
	return door.find_child("Lock", true, false) as ToiletLock if door else null

func _build_toilet(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Toilet")
	var ts := _toilet_sign()
	var z := _toilet_room_z()
	# Bowl backs onto the end-facing wall and faces the saloon; sink backs onto the partition.
	var bowl := _add_marker(group, "ToiletBowl", Vector3(_end_x(ts, _toilet_end_clear() + 0.35), 0, z))
	bowl.rotation.y = ts * PI * 0.5
	var bowl_node := _instance(bowl, toilet_scene)
	if bowl_node:
		# Back plate flush on the end-facing wall (5 mm off), whatever the model's depth.
		bowl.position = Vector3(_end_x(ts, _toilet_end_clear() + 0.005), 0, z)
		_back_to_wall(bowl_node)
	else:
		bowl.add_child(_toilet_placeholder())
	var sink := _add_marker(group, "Sink", Vector3(_partition_face(ts, 1.0) + ts * 0.25, 0, z))
	sink.rotation.y = -ts * PI * 0.5
	if not _instance(sink, sink_scene):
		sink.add_child(_sink_placeholder())
	# Mirror centered 1.4 m up on the partition's toilet-room face, above the sink. Marker -Z faces the room.
	var mirror := _add_marker(group, "Mirror",
			Vector3(_partition_face(ts, 1.0) + ts * 0.005, 1.4, z))
	mirror.rotation.y = -ts * PI * 0.5
	var mirror_node := _instance(mirror, mirror_scene)
	if mirror_node:
		_back_to_wall(mirror_node)
		# Box-projected probe covering the toilet room, so the mirror reflects the room itself.
		var probe := ReflectionProbe.new()
		probe.name = "MirrorProbe"
		probe.size = Vector3(toilet_length, interior_height, toilet_width)
		probe.position = Vector3(_toilet_door_x(), interior_height * 0.5, z)
		probe.box_projection = true
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		group.add_child(probe)
	elif sink_scene != null:
		mirror.add_child(_mirror_placeholder())

	# Fire extinguisher on the vestibule face of the boarding-end partition, beside the saloon door.
	var bs := _boarding_sign()
	var safety := _add_group(anchors, "Safety")
	var ext := _add_marker(safety, "Extinguisher",
			Vector3(_partition_face(bs, 1.0) + bs * 0.005, 0.85, inner_door_width * 0.5 + 0.35))
	ext.rotation.y = -bs * PI * 0.5
	var ext_node := _instance(ext, extinguisher_scene)
	if ext_node:
		_back_to_wall(ext_node)
	else:
		ext.add_child(_extinguisher_placeholder())

	# Emergency brake on the saloon face of both partitions, beside the door (under its sign).
	for s in ([-1.0, 1.0] if _has_center_aisle() else []):
		var brake := _add_marker(safety, "EmergencyBrake_" + ("Front" if s > 0 else "Rear"),
				Vector3(_partition_face(s, -1.0) - s * 0.005, 1.45, inner_door_width * 0.5 + 0.45))
		brake.rotation.y = s * PI * 0.5
		var brake_node := _instance(brake, emergency_brake_scene)
		if brake_node:
			_back_to_wall(brake_node)
		else:
			brake.add_child(_emergency_brake_placeholder())

	if computer_station:
		_build_station(anchors)
	if staff_cabinet:
		_build_staff_cabinet(anchors)
	_build_small_fittings(anchors)
	_build_interior_ambient(anchors)
	_build_notices(anchors)
	if vent_scene != null:
		_build_vents(anchors)

# Vents above the saloon doors (saloon face of each partition, right and left of the door, above
# the pocket casing), and one high on the passage wall opposite the toilet door.
func _build_vents(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Vents")
	var t := wall_thickness
	var i := 0
	for s in ([-1.0, 1.0] if _has_center_aisle() else []):
		var dz := _partition_door_z(s)
		for side in [-1.0, 1.0]:
			i += 1
			var z: float = dz + side * (inner_door_width * 0.5 + 0.27)
			var m := _add_marker(group, "Vent_%02d" % i,
					Vector3(_partition_face(s, -1.0), door_height + 0.13, z))
			m.rotation.y = s * PI * 0.5  # marker -Z faces into the saloon
			var v := _instance(m, vent_scene)
			if v:
				_front_off_wall(v, 0.006)
				_vent_frame(m, 0.32, 0.19)
	# Passage wall opposite the toilet door, beside the staff cabinet (toward the gangway end),
	# on the wallpaper below the cornice line; follows the wall's lean.
	var ts := _toilet_sign()
	var vx := _toilet_door_x() + ts * (STAFF_CAB_SIZE.x * 0.5 + 0.32)
	var wall := _window_xform(vx, STAFF_CAB_Y + STAFF_CAB_SIZE.y * 0.5 - 0.1, -1.0)
	var mw := _add_marker(group, "Vent_Passage", Vector3.ZERO)
	mw.transform = Transform3D(wall.basis, wall.origin - wall.basis.z * (t * 0.5))
	var vw := _instance(mw, vent_scene)
	if vw:
		_front_off_wall(vw, 0.006)
		_vent_frame(mw, 0.32, 0.19)

# Aisle runner size: saloon length (minus a gap for the thresholds) by the aisle plus 10 cm.
func _carpet_size() -> Vector2:
	# Ends so its brass end plate butts against the saloon doors' threshold ramps.
	return Vector2(_saloon_end() - _saloon_start() - 2.0 * (DOOR_TRACK_RAMP + 0.028), aisle_width + 0.1)

## The boarding steps as something to climb. The footboard and the hung step are a near-vertical
## ladder (8 cm between their nosings), which a walking body cannot take, so the climb is an unseen
## 48° ramp along the steps' nosings: from the door threshold (floor, y = 0) down into the ballast
## (rail heads are about 1.25 m below the floor). From the track side it is the whole climb; from a
## platform the player meets it about 0.75 m out from the car and walks up into the doorway.
func _add_step_collision(parent: Node3D, dx: float, bottom: float, w: float, z_side: float) -> void:
	var body := StaticBody3D.new()
	body.name = "BoardingStepsBody"
	body.set_meta("surface", "metal")          # footstep sounds
	parent.add_child(body)
	var dw := side_door_width
	# The ramp ends 3 cm proud of the floor just outside the doorway and a thin threshold plate
	# carries on over the shell's floor edge, so nothing catches the feet at the top.
	var top := Vector3(dx, 0.03, z_side * (w + 0.03))
	var foot := Vector3(dx, bottom - 1.6, z_side * (w + 1.6))
	_step_shape(body, Vector3(dw - 0.05, 0.06, 0.38), Transform3D(Basis.IDENTITY, Vector3(dx, 0.0, z_side * (w - 0.16))))
	var along := (foot - top).normalized()
	var basis := Basis(Vector3.RIGHT, along.cross(Vector3.RIGHT), along)
	var up := basis.y if basis.y.y > 0.0 else -basis.y
	_step_shape(body, Vector3(dw - 0.05, 0.06, top.distance_to(foot)), Transform3D(basis, (top + foot) * 0.5 - up * 0.03))

func _step_shape(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)

# Boarding step: steel tread with a brass nosing on the outer edge and anti-slip ribs.
func _add_boarding_step(parent: Node3D, center: Vector3, z_side: float, w: float, d: float) -> void:
	var steel := _mat(Color(0.16, 0.16, 0.15))
	steel.metallic = 0.5
	steel.roughness = 0.6
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.35
	var rib := _mat(Color(0.08, 0.08, 0.075))
	_add_mesh(parent, "StepTread", Vector3(w, 0.045, d), center, steel)
	_add_mesh(parent, "StepNosing", Vector3(w, 0.05, 0.03), center + Vector3(0, 0.003, z_side * (d * 0.5 - 0.015)), brass)
	var ribs := int((d - 0.05) / 0.035)
	for i in ribs:
		var rz: float = -d * 0.5 + 0.03 + i * 0.035
		_add_mesh(parent, "StepRib", Vector3(w - 0.06, 0.006, 0.012), center + Vector3(0, 0.024, z_side * rz), rib)

# X of the roof air-conditioning unit (over the WC end of the saloon).
func _ac_x() -> float:
	return _toilet_sign() * length * 0.3

# Service hatch in the ceiling under the roof AC unit: walnut frame, cream panel with a return-air
# grille, brass latch. Built flat just under the crown (the ceiling curves only ~7 mm over its width).
func _build_ac_hatch(anchors: Node3D) -> void:
	var group := _add_group(anchors, "ACHatch")
	var hw := 0.95   # along the car
	var hd := 0.6    # across the car
	var n := Node3D.new()
	n.name = "Hatch"
	# Local XY = ceiling plane, local +Z = down into the car.
	n.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)),
			Vector3(_ac_x(), _ceiling_y(hd * 0.5 + 0.04), 0))
	group.add_child(n)
	var cream := _mat(Color(0.88, 0.84, 0.74))
	cream.roughness = 0.7
	var dark := _mat(Color(0.05, 0.045, 0.04))
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_frame_ring(n, "Frame", hw, hd, 0.03, 0.045, 0.018, 0.009, trim_material)
	_add_mesh(n, "Panel", Vector3(hw, hd, 0.012), Vector3(0, 0, 0.006), cream)
	# Pressed border: a raised bead inset from the panel edge, with a shadow line inside it.
	_add_frame_ring(n, "PanelBead", hw - 0.07, hd - 0.07, 0.025, 0.008, 0.004, 0.014, cream)
	_add_frame_ring(n, "PanelGroove", hw - 0.09, hd - 0.09, 0.02, 0.002, 0.001, 0.0125, _mat(Color(0.45, 0.42, 0.36)))
	# Grille: dark plenum behind fine insect mesh, thin angled blades across the car on two
	# support bars, a raised enamel surround and a brass bead.
	var gw := hw * 0.6
	var gh := hd * 0.5
	_add_mesh(n, "GrilleBack", Vector3(gw, gh, 0.002), Vector3(0, 0, 0.0125), dark)
	var mesh_mat := _mat(Color(0.16, 0.15, 0.13))
	mesh_mat.metallic = 0.6
	mesh_mat.roughness = 0.5
	var pitch := 0.008
	var k := -gh * 0.5 + pitch * 0.5
	while k < gh * 0.5:
		_add_mesh(n, "MeshWire", Vector3(gw, 0.0008, 0.0008), Vector3(0, k, 0.0138), mesh_mat)
		k += pitch
	var enamel := _mat(Color(0.9, 0.87, 0.79))
	enamel.roughness = 0.4
	var slats := int(round(gw / 0.024))
	for i in slats:
		var x := -gw * 0.5 + gw * (float(i) + 0.5) / float(slats)
		var slat := _add_mesh(n, "Slat", Vector3(0.0025, gh - 0.004, 0.026), Vector3(x, 0, 0.022), enamel)
		slat.rotation.y = deg_to_rad(40.0)
	for sy in [-1.0 / 3.0, 1.0 / 3.0]:
		_add_mesh(n, "SlatBar", Vector3(gw, 0.006, 0.005), Vector3(0, sy * gh, 0.03), enamel)
	_add_frame_ring(n, "GrilleSurround", gw, gh, 0.012, 0.022, 0.012, 0.018, enamel)
	_add_frame_ring(n, "GrilleBead", gw + 0.044, gh + 0.044, 0.018, 0.006, 0.006, 0.02, brass)
	# Maker's plate below the grille.
	var plate_y := -(gh * 0.5 + 0.022 + (hd * 0.5 - 0.035 - gh * 0.5 - 0.022) * 0.5)
	_add_mesh(n, "NamePlate", Vector3(0.2, 0.034, 0.003), Vector3(0, plate_y, 0.0135), brass)
	var lbl := Label3D.new()
	lbl.name = "NamePlateText"
	lbl.text = "A.C. SERVICE HATCH"
	lbl.font = _sign_font()
	lbl.font_size = 128
	lbl.pixel_size = 0.012 / (128.0 * SIGN_CAP_RATIO)
	lbl.modulate = Color(0.12, 0.08, 0.04)
	lbl.double_sided = false
	lbl.shaded = true
	lbl.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	lbl.render_priority = 1
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Label3D faces its +Z; the hatch's local +Z points down into the car.
	lbl.position = Vector3(0, plate_y, 0.0152)
	n.add_child(lbl, true)
	# Brass screws holding the panel: the four corners and the middle of each long side.
	for sx in [-1.0, 0.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_add_screw(n, Vector3(sx * (hw * 0.5 - 0.035), sy * (hd * 0.5 - 0.035), 0.012), 0.0105, brass, 1.0)

# Slim walnut surround laid on the wall around a vent (marker space, -Z = room).
func _vent_frame(marker: Node3D, w: float, h: float) -> void:
	_add_frame_ring(marker, "VentFrame", w + 0.006, h + 0.006, 0.02, 0.028, 0.012, -0.006, trim_material)

# Sinks a wall fitting into the wall so only its front `proud` metres stand out (marker -Z = room).
func _front_off_wall(node: Node3D, proud: float) -> void:
	var front := INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != node:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		front = minf(front, (xf * mi.mesh.get_aabb()).position.z)
	if front < INF:
		node.position.z = -proud - front

# ————— computer station (niche between the toilet room and the WC-end wall) —————

# Middle of the niche along the car, and its outer (back) wall is the car's +Z side wall.
func _niche_x() -> float:
	return _end_x(_toilet_sign(), (_end_lining() + _toilet_end_clear() - wall_thickness) * 0.5)

func _screen_xform() -> Transform3D:
	return _window_xform(_niche_x(), station_screen_height, 1.0)

# Screen recessed into the outer wall, a cabinet below it and a keyboard on the cabinet.
func _build_station(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Station")
	var t := wall_thickness
	var xn := _niche_x()
	var sh := station_shelf_height
	# Inner wall surface at shelf height (the wall leans inward above the sill).
	var wall_z := _outer_wall_z(sh) - t
	var cd := station_cabinet_size.z

	# Wall shelf: marker on the wall at the shelf top, -Z facing the niche opening.
	# The niche wall is the car's +Z side, so an unrotated marker already has -Z toward the room.
	var cab := _add_marker(group, "Shelf", Vector3(xn, sh, wall_z - 0.003))
	var cab_node := _instance(cab, cabinet_scene)
	if cab_node:
		_back_to_wall(cab_node)
		cd = _depth_of(cab_node)
	else:
		cab.add_child(_cabinet_placeholder(station_cabinet_size.x, station_cabinet_size.y, cd))

	# Keyboard on the shelf, toward its front edge.
	var kb := _add_marker(group, "Keyboard", Vector3(xn, sh, wall_z - cd + 0.13))
	if not _instance(kb, keyboard_scene):
		kb.add_child(_keyboard_placeholder())

	# Screen in the recess cut into the wall (see _build_shell). Marker local +Z = outside.
	var scr := _add_marker(group, "Screen", Vector3.ZERO)
	scr.transform = _screen_xform()
	var sz := station_screen_size
	_add_plate(scr, "FOR STAFF USE ONLY!", Vector3(0, sz.y * 0.5 + 0.08, -t * 0.5 - 0.004), Vector3(0, 0, -1), "red", false, 0.028)
	var term := _instance(scr, terminal_scene)
	if term:
		# Bezel 15 mm proud of the inner wall face, the body inside the recess.
		var front := INF
		for mi: MeshInstance3D in term.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != term:
				xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			front = minf(front, (xf * mi.mesh.get_aabb()).position.z)
		term.position = Vector3(0, 0, -t * 0.5 - 0.015 - front)
		# The working screen: the staff desktop shown on the glass (in play only).
		if not Engine.is_editor_hint():
			var ct := ComputerTerminal.new()
			ct.name = "Terminal"
			ct.position = Vector3(0, 0.006, -t * 0.5 - 0.015 - 0.0015)
			scr.add_child(ct)
	else:
		var brass := _mat(_c_brass)
		brass.metallic = 0.85
		brass.roughness = 0.3
		_add_frame_ring(scr, "Bezel", sz.x, sz.y, 0.03, 0.045, 0.02, -t * 0.5 - 0.005, trim_material)
		_add_frame_ring(scr, "BezelBead", sz.x - 0.01, sz.y - 0.01, 0.025, 0.01, 0.01, -t * 0.5 - 0.016, brass)
		_add_mesh(scr, "RecessBack", Vector3(sz.x, sz.y, 0.005), Vector3(0, 0, 0.018), _mat(Color(0.02, 0.02, 0.02)))
		var screen := _mat(Color(0.03, 0.12, 0.05))
		screen.emission_enabled = true
		screen.emission = Color(0.12, 0.65, 0.25)
		screen.emission_energy_multiplier = 0.9
		screen.roughness = 0.15
		_add_mesh(scr, "Display", Vector3(sz.x - 0.08, sz.y - 0.08, 0.005), Vector3(0, 0, 0.01), screen)

# Depth (local Z extent) of a node's meshes.
func _depth_of(node: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != node:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * mi.mesh.get_aabb()
		lo = minf(lo, b.position.z)
		hi = maxf(hi, b.end.z)
	return hi - lo if hi > lo else 0.3

# ————— framed notices: train formation map and route board (boarding end) —————

# Framed notice on a wall facing `normal` (an axis vector): walnut frame, brass bead and a cream
# printed sheet. Returns the sheet node (local X right, Y up, +Z out of the wall, origin at centre).
func _notice_board(parent: Node3D, board_name: String, pos: Vector3, normal: Vector3, w: float, h: float) -> Node3D:
	var n := Node3D.new()
	n.name = board_name
	var along := Vector3(0, 0, -normal.x) if absf(normal.x) > 0.5 else Vector3(normal.z, 0, 0)
	n.transform = Transform3D(Basis(along, Vector3.UP, normal), pos)
	parent.add_child(n, true)
	var fw := 0.032
	var fd := 0.022
	for sy in [-1.0, 1.0]:
		_add_mesh(n, "FrameRail", Vector3(w + fw * 2.0, fw, fd), Vector3(0, sy * (h + fw) * 0.5, fd * 0.5), trim_material)
	for sx in [-1.0, 1.0]:
		_add_mesh(n, "FrameStile", Vector3(fw, h, fd), Vector3(sx * (w + fw) * 0.5, 0, fd * 0.5), trim_material)
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_frame_ring(n, "Bead", w - 0.004, h - 0.004, 0.003, 0.004, 0.003, 0.0085, brass)
	var paper := _mat(Color(0.92, 0.89, 0.79))
	paper.roughness = 0.6
	_add_mesh(n, "Backing", Vector3(w, h, 0.008), Vector3(0, 0, 0.004), paper)
	var sheet := Node3D.new()
	sheet.name = "Sheet"
	sheet.position = Vector3(0, 0, 0.0082)
	n.add_child(sheet)
	return sheet

const INK := Color(0.1, 0.09, 0.08)
const INK_GREEN := Color(0.1, 0.27, 0.16)
const INK_RED := Color(0.68, 0.1, 0.07)

# Printed text on a notice sheet. `align` < 0 = left edge at x, 0 = centred, > 0 = right edge at x.
func _print_text(sheet: Node3D, text: String, x: float, y: float, cap: float, color: Color,
		align: int = 0, title: bool = false) -> Label3D:
	var l := Label3D.new()
	l.name = "Print"
	l.text = text
	l.font = _letter_font(700) if title else _sign_font()
	l.font_size = 128
	l.pixel_size = cap / (128.0 * (0.708 if title else SIGN_CAP_RATIO))
	l.line_spacing = SIGN_LINE_SPACING * 0.5
	l.modulate = color
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if align < 0 else (HORIZONTAL_ALIGNMENT_RIGHT if align > 0 else HORIZONTAL_ALIGNMENT_CENTER)
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.position = Vector3(x, y, 0.0016)
	sheet.add_child(l)
	return l

# Printed shapes: a flat rectangle and a flat disc, just above the sheet.
func _print_rect(sheet: Node3D, size: Vector2, center: Vector2, color: Color, lift: float = 0.0006) -> void:
	_add_mesh(sheet, "PrintRect", Vector3(size.x, size.y, 0.0004), Vector3(center.x, center.y, lift), _ink_mat(color))

func _print_disc(sheet: Node3D, r: float, center: Vector2, color: Color, lift: float = 0.0008) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "PrintDisc"
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.0004
	cm.radial_segments = 24
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _ink_mat(color)
	mi.rotation.x = PI * 0.5
	mi.position = Vector3(center.x, center.y, lift)
	sheet.add_child(mi)

var _ink_cache := {}
func _ink_mat(c: Color) -> StandardMaterial3D:
	if not _ink_cache.has(c):
		var m := _mat(c)
		m.roughness = 0.7
		_ink_cache[c] = m
	return _ink_cache[c]

func _build_notices(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Notices")
	var bs := _boarding_sign()
	var t := wall_thickness
	# Train map (portrait): end wall of the vestibule, beside the gangway door.
	var end_x: float = bs * (_half_len() - t - _end_lining() - 0.004)
	var mw := 0.46
	var mh := 0.7
	var mz := bs * (end_door_width * 0.5 + 0.1 + mw * 0.5)
	var map := _notice_board(group, "TrainMap", Vector3(end_x, 1.44, mz), Vector3(-bs, 0, 0), mw, mh)
	_draw_train_map(map, mw, mh)
	# Route boards: saloon face of both partitions, under the NO SMOKING signs.
	for sgn in ([bs, -bs] if _has_center_aisle() else []):
		var part_x: float = _partition_face(sgn, -1.0) - sgn * 0.004
		var rw := 0.74
		var rh := 0.44
		var rz := _partition_door_z(sgn) - (inner_door_width * 0.5 + 0.1 + rw * 0.5)
		var route := _notice_board(group, "RouteBoard", Vector3(part_x, 1.41, rz), Vector3(-sgn, 0, 0), rw, rh)
		_draw_route(route, rw, rh)

## Vehicles of this train in order, car 1 first: "TYPE|notes". Every vehicle is numbered (the
## locomotive too); car_index marks this car on the map and names the cars beyond its doors.
@export var train_formation: PackedStringArray = PackedStringArray([
		"SLEEPING CAR|BERTHS 1-8", "SALOON|SEATS 1-40  ·  W.C.", "SALOON|SEATS 41-80  ·  W.C.",
		"CREW CAR|STAFF ONLY", "MAIL & PARCELS VAN|MAIL  ·  PARCELS  ·  LUGGAGE", "LOCOMOTIVE|"]):
	set(v): train_formation = v; _queue_rebuild()

func _draw_train_map(sh: Node3D, w: float, h: float) -> void:
	var top := h * 0.5
	var paper := Color(0.92, 0.89, 0.79)
	_print_text(sh, company_name.replace(" RAILWAY", "\nRAILWAY"), 0, top - 0.05, 0.016, INK, 0, true)
	_print_rect(sh, Vector2(w - 0.06, 0.0015), Vector2(0, top - 0.092), INK)
	_print_rect(sh, Vector2(w - 0.06, 0.0007), Vector2(0, top - 0.097), INK)
	_print_text(sh, "FORMATION OF THIS TRAIN", 0, top - 0.116, 0.0105, INK)
	var n := train_formation.size()
	if n == 0:
		return
	var rows_top := top - 0.14
	var rows_bottom := -h * 0.5 + 0.075
	var pitch := (rows_top - rows_bottom) / n
	var cw := 0.15
	var icon_x := -w * 0.5 + 0.035 + cw * 0.5
	var text_x := icon_x + cw * 0.5 + 0.025
	for i in n:
		var parts := train_formation[i].split("|")
		var kind := parts[0]
		var notes := parts[1] if parts.size() > 1 else ""
		var cy := rows_top - pitch * (i + 0.5)
		var here := i + 1 == car_index
		if here:
			_print_rect(sh, Vector2(w - 0.04, pitch - 0.008), Vector2(0, cy), INK_RED, 0.0003)
			_print_rect(sh, Vector2(w - 0.046, pitch - 0.014), Vector2(0, cy), paper, 0.0004)
		# Coupling to the next vehicle.
		if i < n - 1:
			_print_rect(sh, Vector2(0.0012, pitch - 0.05), Vector2(icon_x, cy - pitch * 0.5), INK)
		_draw_vehicle(sh, kind, icon_x, cy, cw)
		var label_col := INK_RED if here else INK
		_print_text(sh, "CAR %d" % (i + 1), text_x, cy + 0.017, 0.012, label_col, -1)
		_print_text(sh, kind, text_x, cy - 0.001, 0.0092, INK, -1)
		if not notes.is_empty():
			_print_text(sh, notes, text_x, cy - 0.018, 0.0068, Color(0.3, 0.27, 0.22), -1)
		if here:
			# Red tag: YOU ARE HERE, with a pointer toward the car.
			var tag_w := 0.098
			var tag_x := w * 0.5 - 0.03 - tag_w * 0.5
			_print_rect(sh, Vector2(tag_w, 0.022), Vector2(tag_x, cy + 0.017), INK_RED, 0.0007)
			var ptr := MeshInstance3D.new()
			ptr.name = "HerePointer"
			var pm := PrismMesh.new()
			pm.size = Vector3(0.016, 0.011, 0.0004)
			ptr.mesh = pm
			ptr.material_override = _ink_mat(INK_RED)
			ptr.rotation.z = PI * 0.5
			ptr.position = Vector3(tag_x - tag_w * 0.5 - 0.005, cy + 0.017, 0.0007)
			sh.add_child(ptr)
			_print_text(sh, "YOU ARE HERE", tag_x, cy + 0.017, 0.0105, paper)
	# Footer: direction of travel, toward the locomotive.
	var fy := -h * 0.5 + 0.04
	_print_rect(sh, Vector2(w - 0.06, 0.0007), Vector2(0, fy + 0.022), INK)
	_print_text(sh, "DIRECTION OF TRAVEL", 0.012, fy, 0.0092, INK, 0)
	for sx in [-1.0, 1.0]:
		var ax: float = sx * 0.105 + 0.012
		_print_rect(sh, Vector2(0.0025, 0.016), Vector2(ax, fy + 0.004), INK)
		var tip := MeshInstance3D.new()
		tip.name = "TravelArrow"
		var tp := PrismMesh.new()
		tp.size = Vector3(0.01, 0.009, 0.0004)
		tip.mesh = tp
		tip.material_override = _ink_mat(INK)
		tip.rotation.z = PI
		tip.position = Vector3(ax, fy - 0.007, 0.0008)
		sh.add_child(tip)

# Side-view pictogram of one vehicle, centred at (cx, cy), `cw` long (front = left).
func _draw_vehicle(sh: Node3D, kind: String, cx: float, cy: float, cw: float) -> void:
	var paper := Color(0.92, 0.89, 0.79)
	var rail_y := cy - 0.0175
	_print_rect(sh, Vector2(cw + 0.012, 0.0016), Vector2(cx, rail_y), INK)
	if kind == "LOCOMOTIVE":
		var body := Color(0.08, 0.08, 0.08)
		_print_rect(sh, Vector2(cw * 0.62, 0.02), Vector2(cx - cw * 0.12, cy - 0.002), body)
		_print_rect(sh, Vector2(cw * 0.3, 0.034), Vector2(cx + cw * 0.33, cy + 0.005), body)
		_print_rect(sh, Vector2(cw * 0.36, 0.004), Vector2(cx + cw * 0.33, cy + 0.024), body)
		_print_rect(sh, Vector2(cw * 0.12, 0.014), Vector2(cx - cw * 0.34, cy + 0.014), body)
		_print_rect(sh, Vector2(cw * 0.14, 0.008), Vector2(cx - cw * 0.05, cy + 0.011), body)
		_print_rect(sh, Vector2(cw * 0.13, 0.012), Vector2(cx + cw * 0.33, cy + 0.01), paper, 0.0009)
		_print_rect(sh, Vector2(cw * 0.06, 0.012), Vector2(cx - cw * 0.47, cy - 0.008), body)
		for k in 3:
			_print_disc(sh, 0.0072, Vector2(cx - cw * 0.3 + k * cw * 0.2, cy - 0.009), body, 0.001)
		_print_disc(sh, 0.0045, Vector2(cx + cw * 0.36, cy - 0.011), body, 0.001)
		return
	var van := kind.contains("MAIL") or kind.contains("PARCEL")
	var body := Color(0.45, 0.1, 0.07) if van else INK_GREEN
	_print_rect(sh, Vector2(cw, 0.026), Vector2(cx, cy), body)
	_print_rect(sh, Vector2(cw - 0.008, 0.005), Vector2(cx, cy + 0.0145), body)
	if van:
		# Two sliding doors (outlined panels) and a cream MAIL panel.
		for sx in [-1.0, 1.0]:
			_print_rect(sh, Vector2(cw * 0.2, 0.02), Vector2(cx + sx * cw * 0.26, cy), Color(0.3, 0.06, 0.04), 0.0009)
		_print_rect(sh, Vector2(cw * 0.22, 0.008), Vector2(cx, cy + 0.003), paper, 0.0009)
		_print_text(sh, "MAIL", cx, cy + 0.003, 0.0045, Color(0.45, 0.1, 0.07))
	else:
		var nw := 6
		var wh := 0.008
		var ww := cw / nw * 0.55
		if kind.begins_with("SLEEP"):
			nw = 9
			ww = cw / nw * 0.5
			wh = 0.006
		elif kind.begins_with("CREW"):
			nw = 4
		for k in nw:
			var wx := cx - cw * 0.5 + cw * (k + 0.5) / nw
			if kind.begins_with("CREW") and k == 1:
				_print_rect(sh, Vector2(ww * 0.8, 0.019), Vector2(wx, cy - 0.001), Color(0.06, 0.18, 0.1), 0.0009)
				continue
			_print_rect(sh, Vector2(ww, wh), Vector2(wx, cy + 0.004), paper, 0.0009)
	for sx in [-1.0, 1.0]:
		for k in [-1.0, 1.0]:
			_print_disc(sh, 0.0042, Vector2(cx + sx * cw * 0.33 + k * 0.0055, cy - 0.0125), INK, 0.001)

## Stopping stations of this train, first to last: "NAME|time" (times invented).
@export var route_stations: PackedStringArray = PackedStringArray([
		"KRÁLOVEC|19.10", "DOBŘANY|19.24", "VRCHOVINA|19.41", "SNĚŽNÁ|20.06",
		"VYSOKÉ POLE|20.27", "STŘÍBRNÁ HORA|20.52", "KAMENNÝ MOST|21.15"]):
	set(v): route_stations = v; _queue_rebuild()

func _draw_route(sh: Node3D, w: float, h: float) -> void:
	var top := h * 0.5
	_print_text(sh, "THE CONTINENTAL EXPRESS", 0, top - 0.042, 0.019, INK, 0, true)
	_print_rect(sh, Vector2(w - 0.06, 0.0015), Vector2(0, top - 0.066), INK)
	_print_rect(sh, Vector2(w - 0.06, 0.0007), Vector2(0, top - 0.071), INK)
	_print_text(sh, "ROUTE AND STOPPING STATIONS  ·  DAILY", 0, top - 0.089, 0.011, INK)
	var n := route_stations.size()
	if n < 2:
		return
	var line_y := 0.0
	var x0 := -w * 0.5 + 0.06
	var x1 := w * 0.5 - 0.06
	# Main line: thick green band with a thin cream core, like a printed railway map.
	_print_rect(sh, Vector2(x1 - x0, 0.007), Vector2((x0 + x1) * 0.5, line_y), INK_GREEN)
	_print_rect(sh, Vector2(x1 - x0, 0.0016), Vector2((x0 + x1) * 0.5, line_y), Color(0.92, 0.89, 0.79), 0.0008)
	for i in n:
		var parts := route_stations[i].split("|")
		var nm := parts[0]
		var tm := parts[1] if parts.size() > 1 else ""
		var x := lerpf(x0, x1, float(i) / (n - 1))
		var terminus := i == 0 or i == n - 1
		var r := 0.0085 if terminus else 0.006
		_print_disc(sh, r, Vector2(x, line_y), INK_GREEN, 0.001)
		_print_disc(sh, r * 0.55, Vector2(x, line_y), Color(0.92, 0.89, 0.79) if not terminus else INK, 0.0012)
		var above := i % 2 == 0
		var name_text := nm.replace(" ", "\n") if nm.length() > 11 else nm
		var lines := name_text.split("\n").size()
		var cap := 0.0105 if terminus else 0.0092
		var half_block := lines * 0.0064
		var ny := line_y + (0.02 + half_block if above else -0.02 - half_block)
		_print_text(sh, name_text, x, ny, cap, INK)
		var ty := ny + half_block + 0.011 if above else ny - half_block - 0.011
		if not tm.is_empty():
			_print_text(sh, ("dep. " if i < n - 1 else "arr. ") + tm, x, ty, 0.0078, INK_RED)
		_print_rect(sh, Vector2(0.0008, 0.012), Vector2(x, line_y + (0.012 if above else -0.012)), INK)
	# Branch to the coast at the fourth station.
	if n > 4:
		var bx := lerpf(x0, x1, 3.0 / (n - 1))
		# Dashed branch line leaving the main line below the station label, down to the right.
		var a := Vector2(bx + 0.004, line_y - 0.075)
		var dir := Vector2(1.0, -0.62).normalized()
		for k in 6:
			var c := a + dir * (0.006 + k * 0.011)
			var dash := _add_mesh(sh, "BranchDash", Vector3(0.007, 0.0035, 0.0004), Vector3(c.x, c.y, 0.0006), _ink_mat(INK_GREEN))
			dash.rotation.z = dir.angle()
		_print_text(sh, "TO THE COAST LINE", a.x + dir.x * 0.075, a.y + dir.y * 0.075 - 0.002, 0.0072, INK_GREEN, -1)
	# Footer.
	var fy := -h * 0.5 + 0.055
	_print_rect(sh, Vector2(w - 0.06, 0.0007), Vector2(0, fy + 0.02), INK)
	_print_text(sh, "REFRESHMENTS ARE SERVED AT BRAMBLEWICK AND ELDERMERE.  CHANGE AT DUNMORE CROSS FOR THE COAST LINE.\nTIMES ARE APPROXIMATE.  PASSENGERS ARE REQUESTED TO ALIGHT ON THE PLATFORM SIDE ONLY.",
			0, fy - 0.006, 0.0066, Color(0.3, 0.27, 0.22))

# ————— staff cabinet (passage wall opposite the toilet door) —————

# Telephone, toilet roll holder and litter bins.
# Inside the car the night sky's ambient light is shut out: a probe over the whole interior
# replaces it with a dim warm fill (the lamps do the rest), and keeps the sky out of reflections,
# so the corners, the floor and under the seats fall into shade as in a real lamp-lit carriage.
func _build_interior_ambient(anchors: Node3D) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "InteriorAmbient"
	probe.size = Vector3(length - 0.1, interior_height + roof_rise + 0.2, width - 2.0 * wall_thickness)
	probe.position = Vector3(0, (interior_height + roof_rise) * 0.5, 0)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.32, 0.26, 0.2)
	probe.ambient_color_energy = 0.35
	probe.intensity = 0.6
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	anchors.add_child(probe)

func _build_small_fittings(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Fittings")
	var ts := _toilet_sign()
	var bs := _boarding_sign()
	var t := wall_thickness
	var clear := _toilet_end_clear()
	# Telephone: on the end wall's lining, facing into the computer niche beside the screen,
	# hung on a walnut backboard screwed to the wall.
	if computer_station and phone_scene != null:
		var ph := _add_marker(group, "Telephone", Vector3(_end_x(ts, _end_lining()) - ts * 0.001, 1.42, _inner_half_width() - 0.24))
		ph.rotation.y = ts * PI * 0.5
		var phn := _instance(ph, phone_scene)
		if phn:
			_back_to_wall(phn)
			var body := _back_outline(phn, 0.015)
			var board_t := 0.016
			phn.position.z -= board_t
			var bw := body.size.x + 0.07
			var bh := body.size.y + 0.08
			var bc := body.get_center()
			_add_mesh(ph, "Backboard", Vector3(bw, bh, board_t * 0.6), Vector3(bc.x, bc.y, -board_t * 0.3), trim_material)
			_add_mesh(ph, "BackboardFace", Vector3(bw - 0.016, bh - 0.016, board_t * 0.4), Vector3(bc.x, bc.y, -board_t * 0.8), trim_material)
			var brass := _mat(_c_brass)
			brass.metallic = 0.85
			brass.roughness = 0.3
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					_add_screw(ph, Vector3(bc.x + sx * (bw * 0.5 - 0.02), bc.y + sy * (bh * 0.5 - 0.02), -board_t), 0.0055, brass)
	# Toilet roll holder: outer wall, beside the front half of the bowl, with a roll on it.
	if roll_holder_scene != null:
		var rh := _add_marker(group, "RollHolder", Vector3(_end_x(ts, clear + 0.36), 0.68, _inner_half_width() - 0.003))
		var rhn := _instance(rh, roll_holder_scene)
		if rhn:
			_back_to_wall(rhn)
			var depth := _depth_of(rhn)
			var paper := _mat(Color(0.96, 0.95, 0.92))
			paper.roughness = 0.9
			var roll := _add_cylinder(rh, "PaperRoll", 0.047, 0.1, Vector3(0, 0, -(depth - 0.014)), paper)
			roll.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_add_cylinder(rh, "RollCore", 0.019, 0.102, Vector3(0, 0, -(depth - 0.014)), _mat(Color(0.55, 0.42, 0.28)))
	# Pedal bin on the WC floor, backed onto the end-facing wall between the bowl and the corridor wall.
	if pedal_bin_scene != null:
		var pb := _add_marker(group, "PedalBin", Vector3(_end_x(ts, clear + 0.005), 0.0, _toilet_wall_z() + t * 0.5 + 0.14))
		pb.rotation.y = ts * PI * 0.5
		var pbn := _instance(pb, pedal_bin_scene)
		if pbn:
			_back_to_wall(pbn)
	# Litter bins on the end-section faces of both partitions, in the free -Z half.
	if bin_scene != null:
		for sgn in [bs, ts]:
			var b := _add_marker(group, "Bin_" + ("Vestibule" if sgn == bs else "Passage"),
					Vector3(_partition_face(sgn, 1.0) + sgn * 0.004, 0.62, _bin_z()))
			b.rotation.y = -sgn * PI * 0.5
			var bn := _instance(b, bin_scene)
			if bn:
				_back_to_wall(bn)

# X/Y outline, in `node`'s parent space, of the mesh within `band` of the node's back (local +Z).
func _back_outline(node: Node3D, band: float) -> Rect2:
	var pts: Array[Vector3] = []
	var back := -INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != node.get_parent():
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		for p in mi.mesh.get_faces():
			var q: Vector3 = xf * p
			pts.append(q)
			back = maxf(back, q.z)
	var r := Rect2()
	var first := true
	for q in pts:
		if q.z > back - band:
			if first:
				r = Rect2(q.x, q.y, 0.0, 0.0)
				first = false
			else:
				r = r.expand(Vector2(q.x, q.y))
	return r

# Round screw head facing -Z (out of the wall; `facing` = 1 for +Z), with a slot.
func _add_screw(parent: Node3D, pos: Vector3, r: float, material: Material, facing: float = -1.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Screw"
	var mesh := CylinderMesh.new()
	mesh.top_radius = r * 0.8
	mesh.bottom_radius = r
	mesh.height = 0.003
	mesh.radial_segments = 12
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos + Vector3(0, 0, 0.0015 * facing)
	mi.rotation.x = PI * 0.5 * facing
	parent.add_child(mi, true)
	_add_mesh(parent, "ScrewSlot", Vector3(r * 1.5, r * 0.25, 0.001), pos + Vector3(0, 0, 0.0031 * facing), _mat(Color(0.12, 0.09, 0.04)))

const STAFF_CAB_SIZE := Vector3(0.98, 0.62, 0.17)   # width, height, depth
const STAFF_CAB_Y := 1.38                           # center height (vent above at 1.95)

func _build_staff_cabinet(anchors: Node3D) -> void:
	var group := _add_group(anchors, "StaffCabinet")
	var t := wall_thickness
	var w := STAFF_CAB_SIZE.x
	var h := STAFF_CAB_SIZE.y
	var d := STAFF_CAB_SIZE.z
	# Wall frame of the -Z side wall: +Z local = out of the car, inner face at z = -t/2.
	var cab := Node3D.new()
	cab.name = "Cabinet"
	cab.transform = _window_xform(_toilet_door_x(), STAFF_CAB_Y, -1.0)
	group.add_child(cab)
	var face := -t * 0.5
	var zc := face - d * 0.5
	var wood := trim_material
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	var board := 0.022
	_add_mesh(cab, "Back", Vector3(w, h, 0.012), Vector3(0, 0, face - 0.006), _mat(Color(0.2, 0.12, 0.07)))
	for sx in [-1.0, 1.0]:
		_add_mesh(cab, "Side", Vector3(board, h, d), Vector3(sx * (w - board) * 0.5, 0, zc), wood)
	_add_mesh(cab, "Top", Vector3(w + 0.03, board + 0.01, d + 0.02), Vector3(0, (h + board) * 0.5, zc - 0.01), wood)
	_add_mesh(cab, "Bottom", Vector3(w + 0.03, board + 0.01, d + 0.02), Vector3(0, -(h + board) * 0.5, zc - 0.01), wood)
	# Glazed door: brass-beaded frame, clear glass, small brass handle and a keyhole plate, hung
	# on its left edge (the pivot) so it swings open into the car.
	var door_z := face - d + 0.012
	var hinge_x := -(w - 0.09) * 0.5
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	pivot.position = Vector3(hinge_x, 0, door_z)
	cab.add_child(pivot)
	var leaf := Node3D.new()
	leaf.name = "DoorLeaf"
	leaf.position = Vector3(-hinge_x, 0, -door_z)
	pivot.add_child(leaf)
	_add_frame_ring(leaf, "DoorFrame", w - 0.1, h - 0.1, 0.02, 0.04, 0.024, door_z, wood)
	_add_frame_ring(leaf, "DoorBead", w - 0.1, h - 0.1, 0.02, 0.008, 0.01, door_z - 0.014, brass)
	var glass := _add_rounded_prism(leaf, "Glass", Transform3D.IDENTITY, w - 0.09, h - 0.09, 0.02, 0.005, door_z, window_glass_material)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_cabinet_handle(leaf, Vector3(w * 0.5 - 0.07, 0.02, door_z - 0.012), brass)
	_add_cabinet_lock(leaf, Vector3(w * 0.5 - 0.07, -0.085, door_z - 0.012), brass)
	# Inside, on the back board: the switchboard on one side, the heating control on the other.
	var mg := _add_marker(cab, "GaugePanel", Vector3(-w * 0.5 + 0.035 + 0.275, 0.0, face - 0.012))
	var m := _add_marker(cab, "ControlPanel", Vector3(w * 0.5 - 0.05 - 0.106, 0.04, face - 0.012))
	if not Engine.is_editor_hint() and HDProps.scene("staff_switchboard") != null and HDProps.scene("staff_thermostat") != null:
		# Moving and lit parts: kept out of the static merge.
		for n: Node3D in [pivot, mg, m]:
			n.set_meta("dynamic", true)
		var panel := StaffPanel.new()
		panel.name = "StaffPanel"
		cab.add_child(panel)
		panel.build(self, mg, m, pivot, leaf, Vector3(w - 0.09, h - 0.09, 0.03), Vector3(0, 0, door_z))
	else:
		var gpn := _instance(mg, staff_gauges_scene)
		if gpn:
			_back_to_wall(gpn)
		var p := _instance(m, staff_panel_scene)
		if p:
			_back_to_wall(p)
	# Brass label on the wall just above the cabinet (under the vent).
	_add_plate(cab, "STAFF ONLY", Vector3(0, h * 0.5 + 0.065, face - 0.004), Vector3(0, 0, -1), "brass", false, 0.022)
	# Collision.
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Only the cabinet's back half: the door and the controls in front stay pickable.
	box.size = Vector3(w + 0.03, h + 0.05, d * 0.4)
	shape.shape = box
	shape.position = Vector3(0, 0, face - d * 0.2)
	body.add_child(shape)
	cab.add_child(body)

# Brass D-pull on a door face at `front` (local -Z = out of the door): a bar on two round posts,
# each post seated in a small rosette.
func _add_cabinet_handle(parent: Node3D, front: Vector3, brass: Material) -> void:
	var span := 0.09      # post centres
	var stand := 0.026    # bar axis distance from the door face
	for sy in [-1.0, 1.0]:
		var base := front + Vector3(0, sy * span * 0.5, 0)
		var rose := _add_cylinder(parent, "HandleRose", 0.009, 0.004, base + Vector3(0, 0, -0.002), brass)
		rose.rotation = Vector3(PI * 0.5, 0, 0)
		_add_rod(parent, "HandlePost", base, base + Vector3(0, 0, -stand), 0.0045, brass)
	var top := front + Vector3(0, span * 0.5 + 0.012, -stand)
	var bottom := front + Vector3(0, -span * 0.5 - 0.012, -stand)
	_add_rod(parent, "HandleBar", bottom, top, 0.006, brass)
	for end in [top, bottom]:
		var cap := MeshInstance3D.new()
		cap.name = "HandleCap"
		var sm := SphereMesh.new()
		sm.radius = 0.006
		sm.height = 0.012
		cap.mesh = sm
		cap.material_override = brass
		cap.position = end
		parent.add_child(cap, true)

# Round brass lock escutcheon with a keyhole, on a door face at `front` (local -Z = out).
func _add_cabinet_lock(parent: Node3D, front: Vector3, brass: Material) -> void:
	var plate := _add_cylinder(parent, "LockRose", 0.016, 0.004, front + Vector3(0, 0, -0.002), brass)
	plate.rotation = Vector3(PI * 0.5, 0, 0)
	var bead := _add_cylinder(parent, "LockBead", 0.012, 0.002, front + Vector3(0, 0, -0.005), brass)
	bead.rotation = Vector3(PI * 0.5, 0, 0)
	var hole := _mat(Color(0.02, 0.015, 0.01))
	var round_part := _add_cylinder(parent, "Keyhole", 0.0035, 0.001, front + Vector3(0, 0.003, -0.0062), hole)
	round_part.rotation = Vector3(PI * 0.5, 0, 0)
	var slot := MeshInstance3D.new()
	slot.name = "KeyholeSlot"
	var pm := PrismMesh.new()
	pm.size = Vector3(0.006, 0.009, 0.001)
	slot.mesh = pm
	slot.material_override = hole
	slot.position = front + Vector3(0, -0.002, -0.0062)
	parent.add_child(slot, true)

func _cabinet_placeholder(w: float, h: float, d: float) -> Node3D:
	var n := _placeholder_root()
	var wood := trim_material
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_mesh(n, "Body", Vector3(w, h - 0.03, d - 0.02), Vector3(0, (h - 0.03) * 0.5, 0.01), wood)
	_add_mesh(n, "Top", Vector3(w + 0.03, 0.03, d + 0.01), Vector3(0, h - 0.015, 0.0), wood)
	_add_mesh(n, "Plinth", Vector3(w - 0.04, 0.08, 0.01), Vector3(0, 0.04, -d * 0.5 + 0.015), _mat(Color(0.08, 0.05, 0.03)))
	for sx in [-1.0, 1.0]:
		_add_mesh(n, "DoorPanel", Vector3(w * 0.5 - 0.05, h - 0.2, 0.012), Vector3(sx * w * 0.25, h * 0.5, -d * 0.5 + 0.006), wood)
		_add_mesh(n, "Knob", Vector3(0.02, 0.06, 0.02), Vector3(sx * 0.04, h * 0.62, -d * 0.5 - 0.01), brass)
	return n

func _keyboard_placeholder() -> Node3D:
	var n := _placeholder_root()
	_add_mesh(n, "Keyboard", Vector3(0.44, 0.03, 0.16), Vector3(0, 0.015, 0), _mat(Color(0.12, 0.1, 0.08)))
	_add_mesh(n, "Keys", Vector3(0.4, 0.008, 0.12), Vector3(0, 0.034, 0.005), _mat(Color(0.8, 0.76, 0.66)))
	return n

func _emergency_brake_placeholder() -> Node3D:
	var n := _placeholder_root()
	var red := _mat(Color(0.6, 0.06, 0.04))
	red.roughness = 0.35
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.3
	_add_mesh(n, "Housing", Vector3(0.14, 0.2, 0.06), Vector3(0, 0.1, -0.03), red)
	_add_rod(n, "Chain", Vector3(0, 0.0, -0.05), Vector3(0, -0.12, -0.05), 0.006, brass)
	_add_mesh(n, "Handle", Vector3(0.13, 0.03, 0.03), Vector3(0, -0.13, -0.05), red)
	return n

func _mirror_placeholder() -> Node3D:
	var n := _placeholder_root()
	_add_mesh(n, "Frame", Vector3(0.45, 0.45, 0.03), Vector3(0, 0, -0.015), _mat(_c_door.darkened(0.4)))
	_add_mesh(n, "Glass", Vector3(0.39, 0.39, 0.005), Vector3(0, 0, -0.032), _glass_mat())
	return n

func _extinguisher_placeholder() -> Node3D:
	var n := _placeholder_root()
	var red := _mat(Color(0.7, 0.08, 0.06))
	var c := CylinderMesh.new()
	c.top_radius = 0.08
	c.bottom_radius = 0.08
	c.height = 0.5
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = c
	mi.material_override = red
	mi.position = Vector3(0, 0.25, -0.1)
	n.add_child(mi)
	return n

func _build_bogies(anchors: Node3D) -> void:
	var group := _add_group(anchors, "Bogies")
	var x := _half_len() - bogie_inset
	var i := 0
	for bx in [-x, x]:
		i += 1
		# Marker sits on the rail top, centered between the rails.
		var m := _add_marker(group, "Bogie_%02d" % i, Vector3(bx, -floor_height_above_rail, 0))
		m.rotation.y = -PI * 0.5
		# HD bogie (Blender): frame plus two wheelset nodes that can be turned about their axle (X).
		if HDProps.place(m, "coach_bogie", Transform3D.IDENTITY, "Bogie"):
			for k in 2:
				var ws := Node3D.new()
				ws.name = "Wheelset_%d" % (k + 1)
				ws.position = Vector3(0, 0.46, (k - 0.5) * 2.5)
				m.add_child(ws)
				HDProps.place(ws, "coach_wheelset", Transform3D.IDENTITY, "Model")
			continue
		if not _instance(m, bogie_scene):
			m.add_child(_bogie_placeholder())

# ————— placeholders —————

# Double seat, origin on the floor at the unit's center, sitter faces -Z.
func _seat_placeholder(unit_w: float) -> Node3D:
	var n := _placeholder_root()
	var fabric := _mat(_c_fabric)
	var frame := _mat(_c_frame)
	_add_mesh(n, "Pedestal", Vector3(unit_w * 0.5, 0.33, 0.3), Vector3(0, 0.165, 0), frame)
	_add_mesh(n, "Cushion", Vector3(unit_w, 0.12, 0.5), Vector3(0, 0.39, -0.02), fabric)
	var back := _add_mesh(n, "Backrest", Vector3(unit_w, 0.72, 0.1), Vector3(0, 0.8, 0.25), fabric)
	back.rotation.x = deg_to_rad(10.0)
	var head := _add_mesh(n, "Headrest", Vector3(unit_w - 0.06, 0.16, 0.12),
			Vector3(0, 1.12, 0.32), _mat(_c_fabric.lightened(0.25)))
	head.rotation.x = deg_to_rad(10.0)
	for s in [-1.0, 1.0]:
		_add_mesh(n, "Armrest", Vector3(0.06, 0.05, 0.42),
				Vector3(s * (unit_w * 0.5 - 0.03), 0.62, 0.0), frame)
	return n

# Wall-mounted table, origin on the floor at the table's center; -Z faces the aisle, +Z the wall.
func _table_placeholder() -> Node3D:
	var n := _placeholder_root()
	var wood := _mat(Color(0.42, 0.24, 0.13))
	wood.roughness = 0.5
	var metal := _mat(_c_frame)
	var top_t := 0.03
	_add_mesh(n, "Top", Vector3(table_width, top_t, table_depth),
			Vector3(0, table_height - top_t * 0.5, 0), wood)
	# Wall rail the top hangs from, plus one leg near the aisle end.
	_add_mesh(n, "WallRail", Vector3(table_width * 0.8, 0.06, 0.03),
			Vector3(0, table_height - top_t - 0.03, table_depth * 0.5 - 0.015), metal)
	var leg_h := table_height - top_t
	_add_mesh(n, "Leg", Vector3(0.05, leg_h, 0.05),
			Vector3(0, leg_h * 0.5, -table_depth * 0.5 + 0.1), metal)
	_add_mesh(n, "Foot", Vector3(0.25, 0.02, 0.15),
			Vector3(0, 0.01, -table_depth * 0.5 + 0.1), metal)
	return n

# Glowing ceiling strip, origin on the ceiling, long along Z (the light itself is added by _build_lamps).
func _lamp_placeholder() -> Node3D:
	var n := _placeholder_root()
	var glow := _mat(Color(1.0, 0.96, 0.85))
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.94, 0.8)
	glow.emission_energy_multiplier = 2.0
	_add_mesh(n, "Strip", Vector3(0.22, 0.04, 1.2), Vector3(0, -0.02, 0), glow)
	return n

# Luggage shelf, origin at the shelf center; -Z faces the aisle, +Z the wall.
func _rack_placeholder(span: float) -> Node3D:
	var n := _placeholder_root()
	var metal := _mat(_c_metal)
	metal.metallic = 0.6
	metal.roughness = 0.35
	var half_d := rack_depth * 0.5
	_add_mesh(n, "Shelf", Vector3(span, 0.025, rack_depth), Vector3.ZERO, metal)
	_add_mesh(n, "Rail", Vector3(span, 0.03, 0.03), Vector3(0, 0.03, -(half_d - 0.01)), metal)
	for s in [-1.0, 1.0]:
		_add_mesh(n, "Bracket", Vector3(0.03, 0.2, 0.03), Vector3(s * (span * 0.5 - 0.1), 0.1, half_d - 0.02), metal)
	return n

# Closed exterior door leaf with a window, origin at the threshold center.
func _side_door_placeholder() -> Node3D:
	var n := _placeholder_root()
	_add_mesh(n, "Leaf", Vector3(side_door_width, door_height, 0.04),
			Vector3(0, door_height * 0.5, 0), _mat(_c_livery))
	_add_mesh(n, "Window", Vector3(side_door_width * 0.5, 0.55, 0.05),
			Vector3(0, door_height * 0.72, 0), _glass_mat())
	return n

# Doorway frame (jambs + header), origin at the threshold center.
func _door_frame(n: Node3D, door_w: float) -> void:
	var m := _mat(_c_door)
	var depth := wall_thickness + 0.04
	for s in [-1.0, 1.0]:
		_add_mesh(n, "Jamb", Vector3(0.06, door_height, depth),
				Vector3(s * (door_w * 0.5 + 0.03), door_height * 0.5, 0), m)
	_add_mesh(n, "Header", Vector3(door_w + 0.12, 0.08, depth),
			Vector3(0, door_height + 0.04, 0), m)

# Sliding door shown open: leaf pushed aside along local X (slide = ±1) on the face at local Z (face = ±1).
func _sliding_door_placeholder(door_w: float, slide: float, face: float) -> Node3D:
	var n := _placeholder_root()
	_door_frame(n, door_w)
	_add_mesh(n, "Leaf", Vector3(door_w, door_height - 0.02, 0.04),
			Vector3(slide * door_w, door_height * 0.5, face * (wall_thickness * 0.5 + 0.03)),
			_mat(_c_door.darkened(0.2)))
	return n

# Hinged door shown closed (open, it would block the narrow corridor). No collision.
func _hinged_door_placeholder(door_w: float) -> Node3D:
	var n := _placeholder_root()
	_door_frame(n, door_w)
	_add_mesh(n, "Leaf", Vector3(door_w, door_height - 0.02, 0.04),
			Vector3(0, door_height * 0.5, 0), _mat(_c_door.darkened(0.2)))
	return n

# Toilet bowl with tank, origin on the floor, front faces -Z, tank toward +Z.
func _toilet_placeholder() -> Node3D:
	var n := _placeholder_root()
	var p := _mat(_c_porcelain)
	p.roughness = 0.25
	_add_mesh(n, "Bowl", Vector3(0.38, 0.4, 0.5), Vector3(0, 0.2, -0.05), p)
	_add_mesh(n, "Seat", Vector3(0.4, 0.04, 0.46), Vector3(0, 0.42, -0.05), _mat(_c_frame))
	_add_mesh(n, "Tank", Vector3(0.42, 0.42, 0.18), Vector3(0, 0.62, 0.22), p)
	return n

# Pedestal sink, origin on the floor, front faces -Z.
func _sink_placeholder() -> Node3D:
	var n := _placeholder_root()
	var p := _mat(_c_porcelain)
	p.roughness = 0.25
	_add_mesh(n, "Pedestal", Vector3(0.18, 0.75, 0.18), Vector3(0, 0.375, 0.05), p)
	_add_mesh(n, "Basin", Vector3(0.5, 0.14, 0.4), Vector3(0, 0.82, 0), p)
	_add_mesh(n, "Mirror", Vector3(0.45, 0.55, 0.02), Vector3(0, 1.45, 0.19), _glass_mat())
	return n

# Two-axle bogie, origin on the rail top between the rails; travels along Z.
func _bogie_placeholder() -> Node3D:
	var n := _placeholder_root()
	var steel := _mat(_c_steel)
	steel.metallic = 0.5
	var wheel_r := 0.46
	var wheelbase := 2.5
	var underside := floor_height_above_rail - floor_thickness
	var frame_y := wheel_r + 0.1
	# Side frames run outside the wheels; the transom ties them together.
	for s in [-1.0, 1.0]:
		_add_mesh(n, "SideFrame", Vector3(0.12, 0.28, wheelbase + 0.7),
				Vector3(s * (RAIL_GAUGE * 0.5 + 0.2), frame_y, 0), steel)
	_add_mesh(n, "Transom", Vector3(RAIL_GAUGE + 0.4, 0.24, 0.45), Vector3(0, frame_y, 0), steel)
	var bolster_h := maxf(underside - (frame_y + 0.12), 0.05)
	_add_mesh(n, "Bolster", Vector3(1.5, bolster_h, 0.5),
			Vector3(0, frame_y + 0.12 + bolster_h * 0.5, 0), steel)
	for az in [-wheelbase * 0.5, wheelbase * 0.5]:
		_add_cylinder(n, "Axle", 0.08, RAIL_GAUGE + 0.1, Vector3(0, wheel_r, az), steel)
		for s in [-1.0, 1.0]:
			_add_cylinder(n, "Wheel", wheel_r, 0.12,
					Vector3(s * RAIL_GAUGE * 0.5, wheel_r, az), steel)
	return n

# ————— helpers —————

func _add_prism(parent: Node, prism_name: String, profile: PackedVector2Array,
		x_start: float, depth: float, material: Material,
		op := CSGShape3D.OPERATION_UNION) -> CSGPolygon3D:
	# CSGPolygon3D extrudes along local -Z; rotating +90° about Y maps that to world -X,
	# so the prism runs from x_start down to x_start - depth.
	var prism := CSGPolygon3D.new()
	prism.name = prism_name
	prism.polygon = profile
	prism.depth = depth
	prism.rotation.y = PI * 0.5
	prism.position = Vector3(x_start, 0, 0)
	prism.material = material
	prism.operation = op
	parent.add_child(prism, true)
	return prism

# Interior wall box trimmed to the car's inner cross-section, so it meets the curved ceiling.
func _add_clipped_wall(parent: Node, wall_name: String, size: Vector3, pos: Vector3,
		material: Material) -> CSGCombiner3D:
	var wall := CSGCombiner3D.new()
	wall.name = wall_name
	parent.add_child(wall, true)
	_add_box(wall, "Box", size + Vector3(0, 0.5, 0), pos + Vector3(0, 0.25, 0), material)
	_add_prism(wall, "Clip", _inner_profile(), pos.x + size.x * 0.5 + 0.1, size.x + 0.2,
			material, CSGShape3D.OPERATION_INTERSECTION)
	return wall

func _add_box(parent: Node, box_name: String, size: Vector3, pos: Vector3,
		material: Material, op := CSGShape3D.OPERATION_UNION) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = box_name
	box.size = size
	box.position = pos
	box.material = material
	box.operation = op
	parent.add_child(box, true)
	return box

func _add_mesh(parent: Node, mesh_name: String, size: Vector3, pos: Vector3,
		material: Material) -> MeshInstance3D:
	if _ext_skip and HD_EXT_SKIP.has(mesh_name):
		return _ext_dummy()
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi, true)
	return mi

# Cylinder lying along X (wheels, axles).
func _add_cylinder(parent: Node, cyl_name: String, radius: float, height: float,
		pos: Vector3, material: Material) -> MeshInstance3D:
	if _ext_skip and HD_EXT_SKIP.has(cyl_name):
		return _ext_dummy()
	var mi := MeshInstance3D.new()
	mi.name = cyl_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation.z = PI * 0.5
	parent.add_child(mi, true)
	return mi

# Rounded rectangle outline centered at the origin, counter-clockwise.
func _rounded_rect(w: float, h: float, r: float, seg: int = 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = clampf(r, 0.001, minf(w, h) * 0.5 - 0.001)
	var centers := [Vector2(w * 0.5 - r, h * 0.5 - r), Vector2(-w * 0.5 + r, h * 0.5 - r),
			Vector2(-w * 0.5 + r, -h * 0.5 + r), Vector2(w * 0.5 - r, -h * 0.5 + r)]
	for c in 4:
		for i in seg + 1:
			var a := PI * 0.5 * (float(c) + float(i) / float(seg))
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * r)
	return pts

# Rounded-rectangle prism in `xform`'s space, spanning local z from zc - depth/2 to zc + depth/2.
func _add_rounded_prism(parent: Node, prism_name: String, xform: Transform3D, w: float, h: float,
		r: float, depth: float, zc: float, material: Material,
		op := CSGShape3D.OPERATION_UNION) -> CSGPolygon3D:
	var prism := CSGPolygon3D.new()
	prism.name = prism_name
	prism.polygon = _rounded_rect(w, h, r)
	prism.depth = depth
	prism.transform = xform.translated_local(Vector3(0, 0, zc + depth * 0.5))
	prism.material = material
	prism.operation = op
	parent.add_child(prism, true)
	return prism

# Flat rounded-rectangle frame (a ring) around an opening of w x h, in `parent`'s local space.
func _add_frame_ring(parent: Node, ring_name: String, w: float, h: float, r: float, frame_w: float,
		depth: float, zc: float, material: Material) -> void:
	var ring := CSGCombiner3D.new()
	ring.name = ring_name
	parent.add_child(ring, true)
	_add_rounded_prism(ring, "Outer", Transform3D.IDENTITY, w + frame_w * 2.0, h + frame_w * 2.0,
			r + frame_w, depth, zc, material)
	_add_rounded_prism(ring, "Inner", Transform3D.IDENTITY, w, h, r, depth + 0.02, zc, material,
			CSGShape3D.OPERATION_SUBTRACTION)

# Frame of a window centered at (x, yc) in the side wall at z_side: origin on the wall's mid-plane,
# local X along the wall, Y up the wall (leaning with the tumblehome), +Z out of the car.
func _window_xform(x: float, yc: float, z_side: float) -> Transform3D:
	var a := atan(tumblehome / maxf(_eave_y() - window_sill, 0.01))
	var up := Vector3(0, cos(a), -z_side * sin(a))
	var nrm := Vector3(0, sin(a), z_side * cos(a))
	var zc := z_side * (_outer_wall_z(yc) - wall_thickness * 0.5)
	return Transform3D(Basis(up.cross(nrm), up, nrm), Vector3(x, yc, zc))

# Thin cylinder from point a to point b (rails, handles, posts).
func _add_rod(parent: Node, rod_name: String, a: Vector3, b: Vector3, radius: float,
		material: Material) -> MeshInstance3D:
	if _ext_skip and HD_EXT_SKIP.has(rod_name):
		return _ext_dummy()
	var mi := MeshInstance3D.new()
	mi.name = rod_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * 0.5)
	parent.add_child(mi, true)
	return mi

func _add_group(parent: Node, group_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	parent.add_child(n)
	return n

func _add_marker(parent: Node, marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	m.gizmo_extents = 0.15
	parent.add_child(m)
	return m

func _placeholder_root() -> Node3D:
	var n := Node3D.new()
	n.name = "Placeholder"
	return n

# Instances the prefab under the marker. Returns null when no prefab is set.
func _instance(marker: Marker3D, prefab: PackedScene) -> Node3D:
	if prefab == null:
		return null
	var node := prefab.instantiate() as Node3D
	marker.add_child(node)
	return node

# Moves a wall-mounted prop along its marker's Z so its back (local +Z) sits flush on the wall.
func _back_to_wall(node: Node3D) -> void:
	var back := -INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != node:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		back = maxf(back, (xf * mi.mesh.get_aabb()).end.z)
	if back > -INF:
		node.position.z = -back

# Bends a door standing in the side wall so it follows the wall's tumblehome: straight up to the
# window sill, then leaning inward like the body (marker local +Z = into the car). Works on copies
# of the meshes, so the prefab itself is untouched.
# Inward offset of the leaned bodyside at height `y` above the floor (0 up to the sill).
func _lean_at(y: float) -> float:
	var k := tumblehome / maxf(_eave_y() - window_sill, 0.01)
	return k * maxf(0.0, y - window_sill)

func _lean_with_wall(door: Node3D) -> void:
	var k := tumblehome / maxf(_eave_y() - window_sill, 0.01)
	for mi: MeshInstance3D in door.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != door.get_parent():
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var inv := xf.affine_inverse()
		var src: Mesh = mi.mesh
		var out := ArrayMesh.new()
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				var p: Vector3 = xf * verts[i]
				p.z += k * maxf(0.0, p.y - window_sill)
				verts[i] = inv * p
			arr[Mesh.ARRAY_VERTEX] = verts
			out.add_surface_from_arrays((src as ArrayMesh).surface_get_primitive_type(si) if src is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(si, src.surface_get_material(si))
		mi.mesh = out

# Orientation for a fitting mounted on the curved ceiling at `z`: its +Y along the ceiling's
# normal (pointing up into the ceiling), turned -90° about Y like the lamp markers.
func _ceiling_basis(z: float) -> Basis:
	var rx := _inner_half_width() - tumblehome
	var ry := roof_rise - roof_thickness
	var az := clampf(absf(z), 0.0, rx * 0.98)
	var slope := ry * (az / (rx * rx)) / sqrt(1.0 - (az / rx) * (az / rx))   # d(height)/d|z|, positive = falling
	var up := Vector3(0.0, 1.0, signf(z) * slope).normalized()
	return Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, -PI * 0.5)

# ————— sliding doors —————

## Total thickness of a pocket casing (wall + a bulge on each face deep enough to hide the leaf).
const CASING_T := 0.22
## How much of the leaf stays out of the pocket when open (the handle edge).
const POCKET_LEFT_OUT := 0.12

# Along-wall direction (in the marker's local X) toward this door's pocket: every pocket is on
# the car's -Z side, which keeps the toilet side and the niche beside it clear.
func _pocket_dir(marker: Node3D) -> float:
	return signf(marker.basis.x.dot(Vector3(0, 0, -1)))

# Hangs a sliding leaf in its opening: centered on the door plane (`plane_z` in marker space),
# turned so its handle faces away from the pocket, pushed into the pocket when doors_open,
# and framed by a head and a far jamb on both faces (which hide the leaf's top rollers).
func _hang_sliding_door(marker: Node3D, leaf: Node3D, door_w: float, plane_z: float, face_a: float, face_b: float,
		pocket_override: float = 0.0) -> TrainDoor:
	var pd := pocket_override if pocket_override != 0.0 else _pocket_dir(marker)
	if _handle_side(leaf) == pd:
		leaf.rotation.y = PI
	leaf.position = Vector3(0, 0, plane_z)
	# The leaf rides on a TrainDoor body that slides it into the pocket.
	var door := _door_body(marker, "SlidingDoor", leaf, Vector3.ZERO)
	door.kind = TrainDoor.Kind.SLIDE
	door.travel = Vector3(pd * (door_w - POCKET_LEFT_OUT), 0, 0)
	door.start_open = doors_open
	_door_collision(door, Vector3(door_w, door_height, 0.045), Vector3(0, door_height * 0.5, plane_z))

	var wood := trim_material
	var trim_d := 0.02
	# Architrave (head + jambs) laid flat on both wall faces, around the opening.
	var jw := _door_trim_width()
	for face_z in [face_a - trim_d * 0.5, face_b + trim_d * 0.5]:
		_add_mesh(marker, "DoorHead", Vector3(door_w + 2.0 * (jw + _door_head_overhang()), 0.08, trim_d),
				Vector3(0, door_height + 0.04, face_z), wood)
		for side in [-1.0, 1.0]:
			_add_mesh(marker, "DoorJamb", Vector3(jw, door_height, trim_d),
					Vector3(side * (door_w + jw) * 0.5, door_height * 0.5, face_z), wood)
	# Lining of the opening (head and both sides) across the full wall thickness. The pocket-side
	# lining is split around a dark slot where the leaf runs into the wall.
	var mid := (face_a + face_b) * 0.5
	var gap := 0.025
	_add_mesh(marker, "OpeningHead", Vector3(door_w, 0.02, face_b - face_a), Vector3(0, door_height - 0.01, mid), wood)
	_add_mesh(marker, "OpeningJamb", Vector3(0.02, door_height, face_b - face_a),
			Vector3(-pd * (door_w * 0.5 - 0.01), door_height * 0.5, mid), wood)
	var d1 := plane_z - gap - face_a
	var d2 := face_b - plane_z - gap
	_add_mesh(marker, "OpeningJamb", Vector3(0.02, door_height, d1),
			Vector3(pd * (door_w * 0.5 - 0.01), door_height * 0.5, face_a + d1 * 0.5), wood)
	_add_mesh(marker, "OpeningJamb", Vector3(0.02, door_height, d2),
			Vector3(pd * (door_w * 0.5 - 0.01), door_height * 0.5, face_b - d2 * 0.5), wood)
	_add_mesh(marker, "PocketSlot", Vector3(0.01, door_height - 0.02, gap * 2.0),
			Vector3(pd * (door_w * 0.5 + 0.005), door_height * 0.5, plane_z), _mat(Color(0.02, 0.015, 0.01)))
	_add_door_track(marker, leaf, door_w, face_a, face_b)
	return door

# Floor track under a sliding leaf: a walnut threshold across the opening, ramped down to the
# floor on both faces and split by a dark guide groove (as wide as the leaf's bottom, plus play)
# that is lined with a brass rail on each side.
const DOOR_TRACK_RAMP := 0.035   # run of the threshold bevel down to the floor

func _add_door_track(marker: Node3D, leaf: Node3D, door_w: float, face_a: float, face_b: float) -> void:
	var g0 := INF
	var g1 := -INF
	for mi: MeshInstance3D in leaf.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != marker:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		for p in mi.mesh.get_faces():
			var q: Vector3 = xf * p
			if q.y < 0.05:
				g0 = minf(g0, q.z)
				g1 = maxf(g1, q.z)
	if g0 > g1:
		return
	g0 -= 0.004
	g1 += 0.004
	var h := 0.014      # threshold height
	var rail := 0.005   # brass rail width
	var ramp := DOOR_TRACK_RAMP
	var x0 := -door_w * 0.5
	var x1 := door_w * 0.5
	var xm := (x0 + x1) * 0.5
	_add_extrusion(marker, "Threshold", PackedVector2Array([Vector2(face_a - ramp, 0.0), Vector2(g0 - rail, 0.0),
			Vector2(g0 - rail, h), Vector2(face_a, h)]), x0, x1, trim_material)
	_add_extrusion(marker, "Threshold", PackedVector2Array([Vector2(g1 + rail, 0.0), Vector2(face_b + ramp, 0.0),
			Vector2(face_b, h), Vector2(g1 + rail, h)]), x0, x1, trim_material)
	var brass := _mat(_c_brass)
	brass.metallic = 0.85
	brass.roughness = 0.32
	for z in [g0 - rail * 0.5, g1 + rail * 0.5]:
		_add_mesh(marker, "TrackRail", Vector3(x1 - x0, h + 0.003, rail), Vector3(xm, (h + 0.003) * 0.5, z), brass)
	# Between the rails: a dark bronze track plate with the guide channel down its middle.
	var bronze := _mat(Color(0.2, 0.15, 0.09))
	bronze.metallic = 0.75
	bronze.roughness = 0.5
	_add_mesh(marker, "TrackPlate", Vector3(x1 - x0, 0.003, g1 - g0), Vector3(xm, 0.0015, (g0 + g1) * 0.5), bronze)
	var gc := (g0 + g1) * 0.5
	_add_mesh(marker, "TrackChannel", Vector3(x1 - x0, 0.001, 0.008), Vector3(xm, 0.0035, gc), _mat(Color(0.015, 0.012, 0.01)))
	for z in [gc - 0.0055, gc + 0.0055]:
		_add_mesh(marker, "TrackGuide", Vector3(x1 - x0, 0.005, 0.003), Vector3(xm, 0.0025, z), brass)
	_add_door_shoe(leaf)

# Brass shoe wrapping the bottom 2 cm of a sliding leaf (it runs in the floor track).
func _add_door_shoe(leaf: Node3D) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi: MeshInstance3D in leaf.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != leaf:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		for p in mi.mesh.get_faces():
			var q: Vector3 = xf * p
			if q.y < 0.05:
				lo = lo.min(q)
				hi = hi.max(q)
	if lo.x > hi.x:
		return
	var brass := _mat(Color(0.62, 0.48, 0.22))
	brass.metallic = 0.85
	brass.roughness = 0.35
	var h := 0.022
	_add_mesh(leaf, "DoorShoe", Vector3(hi.x - lo.x, h, hi.z - lo.z + 0.002), Vector3((lo.x + hi.x) * 0.5, h * 0.5, (lo.z + hi.z) * 0.5), brass)

# Convex (z, y) profile extruded along local X from x0 to x1, flat-shaded, with end caps.
func _add_extrusion(parent: Node3D, mesh_name: String, profile: PackedVector2Array, x0: float, x1: float,
		material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector2.ZERO
	for p in profile:
		c += p
	c /= profile.size()
	var n := profile.size()
	for i in n:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[(i + 1) % n]
		var d := b - a
		var nz := Vector2(d.y, -d.x).normalized()
		if nz.dot((a + b) * 0.5 - c) < 0.0:
			nz = -nz
		var nrm := Vector3(0, nz.y, nz.x)
		var qa := Vector3(x0, a.y, a.x)
		var qb := Vector3(x0, b.y, b.x)
		var qc := Vector3(x1, b.y, b.x)
		var qd := Vector3(x1, a.y, a.x)
		_ext_tri(st, qa, qb, qc, nrm)
		_ext_tri(st, qa, qc, qd, nrm)
	var idx := Geometry2D.triangulate_polygon(profile)
	for k in range(0, idx.size(), 3):
		for cap in [[x0, Vector3(-1, 0, 0)], [x1, Vector3(1, 0, 0)]]:
			var pts: Array[Vector3] = []
			for j in 3:
				var p: Vector2 = profile[idx[k + j]]
				pts.append(Vector3(cap[0], p.y, p.x))
			_ext_tri(st, pts[0], pts[1], pts[2], cap[1])
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = st.commit()
	mi.material_override = material
	parent.add_child(mi, true)
	return mi

# Adds a triangle facing `nrm` (Godot front faces wind clockwise as seen from the front).
func _ext_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3) -> void:
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v in [a, b, c]:
		st.set_normal(nrm)
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)

# Wraps a door model in a TrainDoor body placed at `body_pos` in its current parent's space,
# keeping the model where it was.
func _door_body(parent: Node3D, body_name: String, model: Node3D, body_pos: Vector3) -> TrainDoor:
	var door := TrainDoor.new()
	door.name = body_name
	door.position = body_pos
	parent.add_child(door)
	var cur := model.get_parent()
	if cur:
		cur.remove_child(model)
	door.add_child(model)
	model.position -= body_pos
	return door

func _door_collision(door: TrainDoor, size: Vector3, center: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "DoorShape"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	door.add_child(cs)

# Hinged door: the body sits on the hinge line (the side away from the handle) and swings the
# leaf by 90 degrees toward local -Z of `marker` (outward for exterior doors, into the corridor
# for the W.C.). `w` is the leaf width, `t` its thickness.
# `lean_top`: how far the top of a leaf hung on the leaning bodyside sits inward of its foot
# (see _lean_with_wall). Such a door hangs on a hinge line leaning with the wall, as on real
# tumblehome coaches, so it swings in its own plane instead of twisting.
func _hinge_door(marker: Node3D, model: Node3D, w: float, h: float, t: float, door_label: String,
		lean_top: float = 0.0) -> TrainDoor:
	var hs := _handle_side(model)
	# Hinge line on the leaf's face toward the side it opens to (marker -Z), at its hinge edge, so
	# the leaf swings clear of the frame instead of cutting into the jamb.
	var lb := _leaf_bounds(marker, model)
	var face_z: float = lb.position.z if lb.size != Vector3.ZERO else -t * 0.5
	var edge_x: float = (lb.position.x if hs > 0.0 else lb.end.x) if lb.size != Vector3.ZERO else -hs * w * 0.5
	var hinge := Vector3(edge_x, 0, face_z)
	var door := _door_body(marker, "HingedDoor", model, hinge)
	if lean_top != 0.0:
		var tilt := Basis(Vector3.RIGHT, atan2(lean_top, h))
		var model_xf := door.transform * model.transform
		door.basis = tilt
		model.transform = door.transform.affine_inverse() * model_xf
	door.kind = TrainDoor.Kind.HINGE
	door.hinge_angle = hs * PI * 0.5
	door.duration = 1.1
	door.door_name = door_label
	_door_collision(door, Vector3(w - 0.02, h - 0.02, t), Vector3(hs * w * 0.5, h * 0.5, t * 0.5))
	return door

# Bounds of a door model's lower part (below the sill, where it is not leaned) in `marker` space.
func _leaf_bounds(marker: Node3D, model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != marker:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		for si in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = xf * v
				if p.y > window_sill:
					continue
				if first:
					out = AABB(p, Vector3.ZERO)
					first = false
				else:
					out = out.expand(p)
	return out

# Which side (marker-local X sign) the leaf's handles are on: they are the parts that stick out
# furthest from the leaf's plane.
func _handle_side(leaf: Node3D) -> float:
	var pts: Array[Vector3] = []
	var zmax := 0.0
	for mi: MeshInstance3D in leaf.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != leaf:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 7):
			var p: Vector3 = xf * faces[i]
			pts.append(p)
			zmax = maxf(zmax, absf(p.z))
	var sum := 0.0
	var n := 0
	for p in pts:
		if absf(p.z) > zmax * 0.6:
			sum += p.x
			n += 1
	return signf(sum) if n > 0 else 1.0


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m

func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.68, 0.75, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.2
	return m
