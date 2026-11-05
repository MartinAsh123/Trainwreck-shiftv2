class_name StationHall
extends RefCounted
## The booking halls of the stations one can walk into: the stone country station (built hollow by
## tools/blender/make_stations.py) and the big towns' two-storey building (Buildings.station()
## leaves its ground floor hollow). The fittings are art_source/props_hd/scripts/assets_hall.py;
## CONFIGS mirrors that script's table. The building's frame: origin on the floor at the middle,
## the platform toward -z, the town +z.
##   wall_boxes()  the building's walls as collision boxes, the doorways left open (worker thread)
##   build()       the hall model, its lamps, solid furniture and the staff's places (main thread)
## Staff: a Marker3D for each place (CashierSpot_1..3 behind the ticket windows, GuardSpot_1..2 at
## the security check), facing the way they work. A model dropped at one of the STAFF paths is
## stood there by itself (the cashier at window 1, the guards at the check).

const HDProps := preload("res://scripts/train/hd_props.gd")
const WALL_T := 0.4
const CONFIGS := {
	"stone": {"model": "station_hall", "L": 16.0, "D": 9.0, "H": 4.6, "XI": 7.6, "ZI": 4.1,
		"front_doors": [-3.2, 0.0], "back_door": 0.0, "door_h": 2.35, "part_x": 3.0, "ticket_z": [-1.7, 0.0, 1.7],
		"drop": 0.9, "lamps": [Vector2(-5.6, 0.0), Vector2(-1.6, 0.0), Vector2(1.5, -1.3), Vector2(1.5, 2.6), Vector2(5.3, 0.0)],
		"palms": [Vector2(-0.95, -0.45), Vector2(-2.35, -0.45)], "scale_x": -5.3},
	"town": {"model": "station_hall_town", "L": 16.0, "D": 10.0, "H": 3.5, "XI": 7.6, "ZI": 4.6,
		"front_doors": [-2.92, 0.0], "back_door": 0.0, "door_h": 2.35, "part_x": 4.3, "ticket_z": [-2.0, 0.0, 2.0],
		"drop": 0.6, "lamps": [Vector2(-5.0, 0.0), Vector2(-1.5, -1.6), Vector2(-1.5, 1.6), Vector2(1.9, 0.0), Vector2(6.0, 0.0)],
		"palms": [Vector2(-1.46, -0.45)], "scale_x": -4.4},
}
const STAFF := {
	"CashierSpot_1": "res://assets/characters/station/cashier.glb",
	"GuardSpot_1": "res://assets/characters/police_officer/police_officer.glb",
	"PlatformGuardSpot": "res://assets/characters/military_officer/military_officer.glb",
	"GuardSpot_2": "res://assets/characters/station/guard_female.glb",
}
const TALK := {"GuardSpot_1": "police", "PlatformGuardSpot": "military"}   # StaffTalk roles

## The staff models, loaded once (on worker threads, from warm()) and kept for the whole run: when
## the halls held the only references, every station that streamed in loaded them again and
## TalkingCharacter fitted their mouths again, a half-second freeze on the main thread each time.
static var _staff_scenes := {}      # path -> PackedScene (null while its threaded load runs)

## Starts loading the staff models in the background (WorldLife calls it before any station).
static func warm() -> void:
	for nm: String in STAFF:
		var p: String = STAFF[nm]
		if _staff_scenes.has(p) or not ResourceLoader.exists(p):
			continue
		_staff_scenes[p] = null
		if ResourceLoader.load_threaded_request(p) != OK:
			_staff_scenes.erase(p)

static func _staff_scene(path: String) -> PackedScene:
	var ps: PackedScene = _staff_scenes.get(path)
	if ps:
		return ps
	if _staff_scenes.has(path) and ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ps = ResourceLoader.load_threaded_get(path) as PackedScene      # waits if it is still loading
	if ps == null:
		ps = load(path) as PackedScene
	_staff_scenes[path] = ps
	return ps

## [size, centre] boxes of the walls of a `kind` station `wall_h` high, doorways open.
static func wall_boxes(kind: String, wall_h: float) -> Array:
	var c: Dictionary = CONFIGS[kind]
	var hx: float = c.L * 0.5
	var hz: float = c.D * 0.5
	var t := WALL_T
	var dh: float = c.door_h
	var out: Array = []
	var front_gaps: Array = []
	for x: float in c.front_doors:
		front_gaps.append(Vector2(x - 0.65, x + 0.65))
	_run(out, -hx, hx, front_gaps, -hz + t * 0.5, wall_h)
	var bd: float = c.back_door
	_run(out, -hx, hx, [Vector2(bd - 0.75, bd + 0.75)], hz - t * 0.5, wall_h)
	for sx: float in [-1.0, 1.0]:
		out.append([Vector3(t, wall_h, c.D), Vector3(sx * (hx - t * 0.5), wall_h * 0.5, 0)])
	# Over the doorways (so nobody climbs through the lintels).
	for g: Vector2 in front_gaps:
		out.append([Vector3(g.y - g.x, wall_h - dh, t), Vector3((g.x + g.y) * 0.5, (wall_h + dh) * 0.5, -hz + t * 0.5)])
	out.append([Vector3(1.5, wall_h - 2.3, t), Vector3(bd, (wall_h + 2.3) * 0.5, hz - t * 0.5)])
	return out

static func _run(out: Array, a0: float, a1: float, gaps: Array, z: float, h: float) -> void:
	var a := a0
	gaps.sort_custom(func(p, q): return p.x < q.x)
	for g: Vector2 in gaps + [Vector2(a1, a1)]:
		if g.x - a > 0.01:
			out.append([Vector3(g.x - a, h, WALL_T), Vector3((a + g.x) * 0.5, h * 0.5, z)])
		a = maxf(a, g.y)

## The hall's inside as an AABB in the building's frame (for the snow shelter).
static func room(kind: String) -> AABB:
	var c: Dictionary = CONFIGS[kind]
	return AABB(Vector3(-c.XI - 0.1, -0.2, -c.ZI - 0.1), Vector3(c.XI * 2.0 + 0.2, c.H + 0.3, c.ZI * 2.0 + 0.2))

## Fills the hall at marker `spot` (the building's origin; its meta "kind" says which).
static func build(spot: Node3D) -> void:
	if spot.get_child_count() > 0:
		return
	var kind: String = spot.get_meta("kind", "stone")
	var c: Dictionary = CONFIGS[kind]
	var XI: float = c.XI
	var ZI: float = c.ZI
	var H: float = c.H
	# A hair above the building's footing (whose snowy top is at the floor line).
	var hall := HDProps.place(spot, c.model, Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), "BookingHall")
	if hall == null:
		return
	for mi: MeshInstance3D in hall.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = 90.0
	# Lamps under the pendant globes (assets_hall LAMPS), warm; two of them shadowed.
	var lamps: Array = c.lamps
	for i in lamps.size():
		var lp: Vector2 = lamps[i]
		var l := OmniLight3D.new()
		l.name = "HallLight_%d" % (i + 1)
		l.position = Vector3(lp.x, H - float(c.drop) - 0.45, lp.y)
		l.light_color = Color(1.0, 0.86, 0.64)
		l.light_energy = 1.3 if H > 4.0 else 1.0
		l.omni_range = 6.5
		l.omni_attenuation = 1.4
		l.shadow_enabled = i == 1 or i == 4
		l.distance_fade_enabled = true
		l.distance_fade_begin = 60.0
		l.distance_fade_length = 15.0
		l.distance_fade_shadow = 25.0
		spot.add_child(l)
	# Inside the room the night sky's ambient light is shut out (a dim warm fill instead).
	var probe := ReflectionProbe.new()
	probe.name = "HallAmbient"
	probe.size = Vector3(XI * 2.0, H, ZI * 2.0)
	probe.position = Vector3(0, H * 0.5, 0)
	probe.interior = true
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.3, 0.24, 0.18)
	probe.ambient_color_energy = 0.4
	probe.intensity = 0.35
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	spot.add_child(probe)
	# The floor: solid under the whole room and out under the doorways' thresholds (the building
	# itself is hollow; the hall model's tiles sit 3 cm up, on its top).
	var floor_body := StaticBody3D.new()
	floor_body.name = "HallFloor"
	floor_body.set_meta("surface", "stone")
	spot.add_child(floor_body)
	_box(floor_body, Vector3(float(c.L) + 0.2, 0.6, float(c.D) + 0.6), Vector3(0, 0.03 - 0.3, 0))
	# Solid furniture: the ticket partition, benches, stove, the security check, the scale, palms.
	var body := StaticBody3D.new()
	body.name = "HallBody"
	body.set_meta("surface", "wood")
	spot.add_child(body)
	var px: float = c.part_x
	var sz := ZI - 1.75                                  # the detector arch's line
	var boxes := [[Vector3(0.6, H, ZI * 2.0), Vector3(px + 0.2, H * 0.5, 0)],
			[Vector3(1.4, 0.9, 2.6), Vector3(-5.6, 0.45, -0.6)], [Vector3(0.6, 0.9, 2.0), Vector3(-XI + 0.35, 0.45, -2.6)],
			[Vector3(0.6, 0.9, 2.0), Vector3(-XI + 0.35, 0.45, 2.4)], [Vector3(0.9, 2.3, 0.9), Vector3(-XI + 0.45, 1.15, ZI - 0.45)],
			[Vector3(0.12, 2.2, 0.55), Vector3(-0.5, 1.1, sz)], [Vector3(0.12, 2.2, 0.55), Vector3(0.5, 1.1, sz)],
			[Vector3(1.6, 0.9, 0.7), Vector3(1.45, 0.45, sz - 0.2)], [Vector3(0.6, 1.1, 0.5), Vector3(-1.4, 0.55, sz + 0.1)],
			[Vector3(0.08, 1.0, 0.9), Vector3(-0.75, 0.5, ZI - 0.85)], [Vector3(0.08, 1.0, 0.9), Vector3(0.75, 0.5, ZI - 0.85)],
			[Vector3(0.6, 1.9, 0.65), Vector3(float(c.scale_x), 0.95, ZI - 0.35)]]
	for p: Vector2 in c.palms:
		boxes.append([Vector3(0.8, 1.6, 0.6), Vector3(p.x, 0.8, -ZI - p.y)])
	for b: Array in boxes:
		_box(body, b[0], b[1])
	# The staff's places.
	var tz: Array = c.ticket_z
	for i in tz.size():
		_spot(spot, "CashierSpot_%d" % (i + 1), Vector3(px + 0.65, 0, tz[i]), PI * 0.5)
	_spot(spot, "GuardSpot_1", Vector3(1.35, 0, sz - 0.35), PI)        # by the trays, facing the way in
	_spot(spot, "GuardSpot_2", Vector3(-1.4, 0, sz + 0.55), -PI * 0.5) # at the lectern
	# Out on the platform in front of the hall's doors, between the door and the benches, watching
	# the track.
	var front: float = -float(c.D) * 0.5
	_spot(spot, "PlatformGuardSpot", Vector3(1.65, 0.05, front - 1.3), 0.0)
	for nm: String in STAFF:
		var path: String = STAFF[nm]
		if not ResourceLoader.exists(path):
			continue
		var m := spot.get_node_or_null(nm) as Node3D
		var person := TalkingCharacter.new()
		person.name = nm.replace("Spot", "")
		person.model = _staff_scene(path)
		person.rotation.y = PI          # the models face +Z, a spot looks down its -Z
		m.add_child(person)
		if nm in TALK:
			StaffTalk.attach(person, TALK[nm])
		var pb := StaticBody3D.new()
		var pc := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.25
		cap.height = 1.8
		pc.shape = cap
		pc.position = Vector3(0, 0.9, 0)
		pb.add_child(pc)
		m.add_child(pb)

static func _box(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = at
	body.add_child(cs)

# A place where a member of staff stands; its -Z (Godot's forward) the way they face.
static func _spot(parent: Node3D, nm: String, at: Vector3, yaw: float) -> void:
	var m := Marker3D.new()
	m.name = nm
	m.position = at
	m.rotation.y = yaw
	parent.add_child(m)
