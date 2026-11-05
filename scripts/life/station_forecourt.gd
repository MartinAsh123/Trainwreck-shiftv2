class_name StationForecourt
extends RefCounted
## The town side of a stopping station, added with its yard (StationYard.attach): the entrance at
## the back of the station building (steps, glazed doors, canopy), a paved forecourt with benches,
## a phone box, an advertising column and litter bins, the approach road out to the yard gate
## where the town's street meets the fence (brick piers with lanterns, the iron gate slid open
## beside them), a car park off the road with cars standing in their bays, street lamps, and the
## village transformer tower with its cabinets. On the platform: a drinks automat against the
## building and litter bins by the benches.
## HD models from art_source/props_hd/scripts/assets_station.py. Frame: the yard's canonical one
## (track at z = 0, platform and building toward +z, the town beyond the fence at FENCE_Z).

const HDProps := preload("res://scripts/train/hd_props.gd")
const ROAD_W := 6.0
const GATE_GAP := 3.7          # half the opening in the fence for the gate
const VIS := 320.0

# Only while build() runs (the helpers below read them).
static var _yard: Node3D
static var _st_s := 0.0
static var _ground: Callable

## `car_fn(kind) -> Node3D` builds a parked car (WorldLife's painted, lamps-out cars);
## `ground_fn(s, z) -> float` is the drawn ground's height at a route point.
## Returns the x of the yard gate (yard frame), NAN without a station building.
static func build(yard: Node3D, n: Node3D, st: Dictionary, car_fn: Callable, ground_fn: Callable) -> float:
	_yard = yard
	_st_s = float(st.s)
	_ground = ground_fn
	var gate_x := _build(yard, n, st, car_fn)
	# Let go of the caller's lambda: one still held in a static var when the game quits is freed
	# after GDScript has shut down, and the engine crashes on the way out.
	_ground = Callable()
	_yard = null
	return gate_x

static func _build(yard: Node3D, n: Node3D, st: Dictionary, car_fn: Callable) -> float:
	var bldg := n.find_child("StationBuilding", false, false) as Node3D
	if bldg == null:
		return NAN
	# The walk-in station's main block is known (StationHall: the town door at its middle).
	var hs := bldg.find_child("HallSpot", false, false)
	var box := _footprint(bldg)
	if hs:
		var hc: Dictionary = StationHall.CONFIGS[hs.get_meta("kind", "stone")]
		box = AABB(Vector3(-hc.L * 0.5, 0, -hc.D * 0.5), Vector3(hc.L, hc.H, hc.D))
	if box.size == Vector3.ZERO:
		return NAN
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(st.name)) + 911
	var fc := Node3D.new()
	fc.name = "Forecourt"
	yard.add_child(fc)
	# The building in the yard frame; its back (town side) face is its local +Z.
	var bx := yard.transform.affine_inverse() * StationYard._rel(n, bldg)
	var back_c := bx * Vector3(box.get_center().x, 0.0, box.end.z)
	var back_z := back_c.z
	var door_x := back_c.x
	var floor_y := bx.origin.y
	# Entrance: steps from the yard up to the floor, the wall at back_z, facing the town (+z).
	_place(fc, "station_entrance", Transform3D(Basis(Vector3.UP, PI), Vector3(door_x, floor_y - 0.92, back_z + 0.02)), VIS,
			Vector3(2.6, 0.9, 2.4), Vector3(0, 0.45, -1.2))
	var lamp := OmniLight3D.new()
	lamp.name = "EntranceLight"
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	lamp.shadow_enabled = true
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 90.0
	lamp.distance_fade_length = 20.0
	lamp.position = Vector3(door_x - 1.25, floor_y + 2.0, back_z + 0.6)
	fc.add_child(lamp)
	# The gate where the town's street meets the yard fence (else straight behind the building).
	var fz := StationYard.FENCE_Z
	var gate_x := _street_gate_x(door_x)
	# Paved forecourt and the approach road from it to the gate.
	var court_z0 := back_z
	var court_z1 := back_z + 14.0
	_paving(fc, Vector3(door_x, 0, (court_z0 + court_z1) * 0.5), Vector2(30.0, court_z1 - court_z0), 0.0)
	var r0 := Vector3(door_x, 0, court_z1 - 1.0)
	var r1 := Vector3(gate_x, 0, fz + 4.0)
	var rd := r1 - r0
	_paving(fc, (r0 + r1) * 0.5, Vector2(ROAD_W, rd.length()), atan2(rd.x, rd.z))
	# Benches, phone box, advertising column, litter bins on the forecourt.
	for k in 3:
		var bp := _on_ground(Vector3(door_x - 11.0 + k * 3.0, 0, court_z0 + 1.2), 0.05)
		Buildings._bench(fc, bp)
		_rot_last_at(fc, bp, PI)
	_place(fc, "phone_booth", Transform3D(Basis(Vector3.UP, PI * 0.5), _on_ground(Vector3(door_x + 12.5, 0, court_z0 + 3.0), 0.05)), VIS,
			Vector3(1.06, 2.4, 1.06), Vector3(0, 1.2, 0))
	_place(fc, "poster_pillar", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _on_ground(Vector3(door_x - 9.0, 0, court_z1 - 2.5), 0.05)),
			VIS, Vector3(1.3, 3.4, 1.3), Vector3(0, 1.7, 0), true)
	for x: float in [door_x - 3.2, door_x + 3.2, door_x + 10.0]:
		_place(fc, "waste_bin", Transform3D(Basis(Vector3.UP, PI), _on_ground(Vector3(x, 0, court_z0 + 0.6), 0.05)), 160.0)
	# Street lamps along the road (every other one lit), a hydrant by it.
	var rdir := rd.normalized()
	var rside := Vector3(rdir.z, 0, -rdir.x)
	var nl := int(rd.length() / 13.0)
	for i in nl:
		var lp := r0 + rdir * (6.0 + i * 13.0) + rside * (ROAD_W * 0.5 + 0.8) * (1.0 if i % 2 == 0 else -1.0)
		Buildings._lamp_post(fc, _on_ground(lp), i % 2 == 0)
	_place(fc, "fire_hydrant", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _on_ground(r0 + rdir * 9.0 + rside * (ROAD_W * 0.5 + 1.2))), 160.0)
	# The car park lies near the gate on the side the road doesn't turn to; the gatehouse, the
	# transformer tower on the other.
	var ps := -signf(door_x - gate_x) if absf(door_x - gate_x) > 4.0 else (1.0 if rng.randf() < 0.5 else -1.0)
	# Gate: a double chain-link gate on its posts, both leaves swung open into the yard; the
	# gatehouse beside the road just inside, the barrier across the road (raised) by it.
	for sx: float in [-1.0, 1.0]:
		var hp := _on_ground(Vector3(gate_x + sx * (GATE_GAP - 0.1), 0, fz))
		_place(fc, "gate_chainlink", Transform3D(Basis(Vector3.UP, PI * 0.5 + (0.12 if sx < 0.0 else -0.12)), hp),
				VIS, Vector3(3.2, 2.1, 0.08), Vector3(1.65, 1.05, 0))
		var gl := OmniLight3D.new()
		gl.light_color = Color(1.0, 0.86, 0.65)
		gl.light_energy = 1.1
		gl.omni_range = 10.0
		gl.distance_fade_enabled = true
		gl.distance_fade_begin = 120.0
		gl.distance_fade_length = 30.0
		gl.position = hp + Vector3(0, 3.0, -0.5)
		fc.add_child(gl)
	var booth_x := gate_x - ps * (ROAD_W * 0.5 + 1.8)
	_place(fc, "guard_booth", Transform3D(Basis(Vector3.UP, -ps * PI * 0.5), _on_ground(Vector3(booth_x, 0, fz - 5.0))), VIS,
			Vector3(2.0, 2.6, 2.0), Vector3(0, 1.3, 0))
	var bl := OmniLight3D.new()
	bl.name = "BoothLight"
	bl.light_color = Color(1.0, 0.85, 0.6)
	bl.light_energy = 0.8
	bl.omni_range = 5.0
	bl.position = _on_ground(Vector3(booth_x, 0, fz - 5.0)) + Vector3(0, 2.1, 0)
	fc.add_child(bl)
	_place(fc, "boom_barrier", Transform3D(Basis(Vector3.UP, 0.0 if ps > 0.0 else PI),
			_on_ground(Vector3(gate_x - ps * (ROAD_W * 0.5 + 0.45), 0, fz - 8.0))), VIS, Vector3(0.34, 1.0, 0.34), Vector3(0, 0.5, 0))
	var lx0 := gate_x + ps * (ROAD_W * 0.5 + 3.0)
	var lot := Rect2(minf(lx0, lx0 + ps * 26.0), fz - 22.0, 26.0, 15.0)
	_paving(fc, Vector3(lot.get_center().x, 0, lot.get_center().y), lot.size, 0.0)
	_car_park(fc, lot, rng, car_fn)
	for cx: float in [lot.position.x - 0.8, lot.end.x + 0.8]:
		for cz: float in [lot.position.y + 0.6, lot.end.y - 0.6, lot.get_center().y]:
			if cz == lot.get_center().y and cx != lot.position.x - 0.8:
				continue
			Buildings._lamp_post(fc, _on_ground(Vector3(cx, 0, cz)), true)
	var tx := gate_x - ps * 18.0
	_place(fc, "substation", Transform3D(Basis(Vector3.UP, PI), _on_ground(Vector3(tx, 0, fz - 6.0))), 700.0,
			Vector3(2.8, 7.5, 2.8), Vector3(0, 3.75, 0))
	_place(fc, "utility_box_b", Transform3D(Basis(Vector3.UP, PI), _on_ground(Vector3(tx + 3.0, 0, fz - 5.0))), 220.0,
			Vector3(0.92, 1.12, 0.43), Vector3(0, 0.56, 0))
	_place(fc, "utility_box_a", Transform3D(Basis(Vector3.UP, PI), _on_ground(Vector3(tx - 2.6, 0, fz - 5.2))), 220.0,
			Vector3(0.52, 1.12, 0.43), Vector3(0, 0.56, 0))
	# Railway staff houses along the fence beyond the transformer, their fronts to the yard.
	for k in 2:
		var hx := gate_x - ps * (34.0 + k * 17.0)
		if absf(hx) > StationYard.FENCE_X - 8.0:
			continue
		var house := Buildings.house(rng, 0.6)
		house.name = "StaffHouse"
		var sz: Vector3 = house.get_meta("size", Vector3(10, 6, 7))
		house.position = _on_ground(Vector3(hx, 0, fz - 3.0 - sz.z * 0.5), -0.05)
		fc.add_child(house)
		for mi: MeshInstance3D in house.find_children("*", "MeshInstance3D", true, false):
			mi.visibility_range_end = 900.0
	# On the platform: a drinks automat against the building front, bins by the platform benches.
	var front := box.position.z
	var vm_x := box.position.x + 1.4
	_place(bldg, "vending_machine", Transform3D(Basis.IDENTITY, Vector3(vm_x, 0.0, front - 0.32)), 200.0,
			Vector3(0.78, 1.82, 0.6), Vector3(0, 0.91, 0))
	var vl := OmniLight3D.new()
	vl.name = "AutomatGlow"
	vl.light_color = Color(1.0, 0.85, 0.6)
	vl.light_energy = 0.35
	vl.omni_range = 2.5
	vl.position = Vector3(vm_x, 1.2, front - 1.0)
	bldg.add_child(vl)
	for bnode: Node in bldg.get_children():
		if bnode is MeshInstance3D and String(bnode.name).begins_with("Bench"):
			var p := (bnode as Node3D).position
			_place(bldg, "waste_bin", Transform3D(Basis.IDENTITY, Vector3(p.x + 1.3, 0.0, p.z + 0.1)), 160.0)
	return gate_x

# Two rows of bays (painted lines) with cars standing in most of them.
static func _car_park(fc: Node3D, lot: Rect2, rng: RandomNumberGenerator, car_fn: Callable) -> void:
	var bay_w := 2.8
	var nb := int(lot.size.x / bay_w)
	for row in 2:
		var rz := lot.position.y + (2.6 if row == 0 else lot.size.y - 2.6)
		var face := 1.0 if row == 0 else -1.0
		for b in nb + 1:
			_line(fc, _on_ground(Vector3(lot.position.x + 0.3 + b * bay_w, 0, rz), 0.055), 5.0)
		for b in nb:
			if rng.randf() > 0.7:
				continue
			var cx := lot.position.x + 0.3 + (b + 0.5) * bay_w
			var car: Node3D = null
			if rng.randf() < 0.18:
				car = HDProps.place(fc, "covered_car", Transform3D.IDENTITY, "CoveredCar")
				if car:
					_vis(car, 400.0)
			elif car_fn.is_valid():
				car = car_fn.call(["car_sedan", "car_small", "car_sedan", "truck"][rng.randi() % 4])
				if car:
					fc.add_child(car)
			if car == null:
				continue
			car.transform = Transform3D(Basis(Vector3.UP, (0.0 if face > 0.0 else PI) + rng.randf_range(-0.05, 0.05)),
					_on_ground(Vector3(cx + rng.randf_range(-0.15, 0.15), 0, rz), 0.05))
			StationYard._box_body(car, Vector3(1.8, 1.5, 4.4), Vector3(0, 0.75, 0))

# Route point <-> yard frame (the station node sits at its route s, x running back along the line).
static func _yard_of(r: Vector2) -> Vector3:
	return _yard.transform.affine_inverse() * Vector3(-(r.x - _st_s), 0.0, r.y)

static func _route_of(p: Vector3) -> Vector2:
	var q := _yard.transform * p
	return Vector2(_st_s - q.x, q.z)

# `p` (yard frame) set down on the drawn ground, `lift` above it.
static func _on_ground(p: Vector3, lift := 0.0) -> Vector3:
	var r := _route_of(p)
	var h: float = _ground.call(r.x, r.y) if _ground.is_valid() else Terrain.FORMATION_Y
	return Vector3(p.x, h + lift, p.z)

# x (yard frame) where a street of the station's town runs into the yard fence, or ends just
# outside it; `fallback` if none.
static func _street_gate_x(fallback: float) -> float:
	var best := fallback
	var best_d := INF
	var fz := StationYard.FENCE_Z
	for stt: Dictionary in RoadNetwork.streets():
		var a := _yard_of(stt.a)
		var b := _yard_of(stt.b)
		var x := NAN
		if (a.z - fz) * (b.z - fz) <= 0.0 and absf(b.z - a.z) > 0.01:
			x = lerpf(a.x, b.x, (fz - a.z) / (b.z - a.z))
		else:
			var near := a if a.z < b.z else b
			if near.z >= fz - 5.0 and near.z <= fz + 45.0:
				x = near.x
		if is_nan(x) or absf(x) > StationYard.FENCE_X - 10.0:
			continue
		if absf(x - fallback) < best_d:
			best_d = absf(x - fallback)
			best = x
	return best

# The building's main block in its own frame: its biggest solid box (the walls' collision).
static func _footprint(bldg: Node3D) -> AABB:
	var best := AABB()
	for cs: CollisionShape3D in bldg.find_children("*", "CollisionShape3D", true, false):
		var bs := cs.shape as BoxShape3D
		if bs == null:
			continue
		var a := StationYard._rel(bldg, cs) * AABB(-bs.size * 0.5, bs.size)
		if a.get_volume() > best.get_volume():
			best = a
	return best

## An HD model under `parent`; optional solid box (`size` centred at `center`, model frame).
static func _place(parent: Node3D, model: String, xf: Transform3D, vis: float, size := Vector3.ZERO, center := Vector3.ZERO,
		round_body := false) -> Node3D:
	var m := HDProps.place(parent, model, xf, model.to_pascal_case())
	if m == null:
		return null
	_vis(m, vis)
	if size != Vector3.ZERO:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		if round_body:
			var cy := CylinderShape3D.new()
			cy.radius = size.x * 0.5
			cy.height = size.y
			cs.shape = cy
		else:
			var bs := BoxShape3D.new()
			bs.size = size
			cs.shape = bs
		cs.position = center
		body.add_child(cs)
		m.add_child(body)
	return m

static func _vis(n: Node3D, vis: float) -> void:
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = vis
		if vis < 250.0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# The bench just added at `p`: turn it (its seat faces -Z; the forecourt benches face the town).
static func _rot_last_at(parent: Node3D, p: Vector3, a: float) -> void:
	for c in parent.get_children():
		if c is Node3D and (c as Node3D).position.distance_to(p) < 0.01:
			(c as Node3D).rotation.y = a

# Stone-flag paving (the platforms' snowy material) laid on the ground: `size` (x, z) round
# `c` (yard frame), turned by `yaw`; deep enough to bridge small dips in the ground.
static func _paving(parent: Node3D, c: Vector3, size: Vector2, yaw: float) -> void:
	var h := -INF
	var b := Basis(Vector3.UP, yaw)
	for k in 5:
		var o := Vector3.ZERO
		if k < 4:
			o = Vector3((size.x * 0.5 - 0.5) * (1.0 if k & 1 else -1.0), 0, (size.y * 0.5 - 0.5) * (1.0 if k & 2 else -1.0))
		h = maxf(h, _on_ground(c + b * o).y)
	var mi := MeshInstance3D.new()
	mi.name = "Paving"
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.6, size.y)
	mi.mesh = bm
	mi.material_override = Buildings.mat("platform")
	mi.transform = Transform3D(b, Vector3(c.x, h + 0.05 - 0.3, c.z))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 500.0
	parent.add_child(mi)

static var _line_mat: StandardMaterial3D

# A painted bay line along z from `p` (its near end), `len` long.
static func _line(parent: Node3D, p: Vector3, len: float) -> void:
	if _line_mat == null:
		_line_mat = StandardMaterial3D.new()
		_line_mat.albedo_color = Color(0.85, 0.84, 0.78)
		_line_mat.roughness = 0.9
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.01, len)
	mi.mesh = bm
	mi.material_override = _line_mat
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	parent.add_child(mi)
