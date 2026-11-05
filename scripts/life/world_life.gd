class_name WorldLife
extends Node3D
## The life of the valley beside the line: roads, streets, fields and their props (streamed in
## LifeBuilder chunks on worker threads, like Scenery), shops in the villages and towns, level
## crossing barriers that drop as the train comes, and motor cars and lorries driving the roads
## with their lamps lit (keeping left; they wait at closed barriers and queue behind each other).
## Route space as everywhere: a point (s, z) is drawn at world x = TrainState.distance - s.

const HDProps := preload("res://scripts/train/hd_props.gd")
const TRAIN_FRONT := 84.0          # route s of the locomotive buffers, relative to distance
const TRAIN_REAR := -26.0
const CLOSE_AHEAD := 420.0         # barriers drop when the train is this close
const ARM_UP := 1.45
const ARM_SPEED := 0.3             # rad/s
const STATION_SPREAD_FROM := 800.0 # a station further than this from the train is fitted out over a few frames
const STATION_SPREAD_DELAY := 1.5  # s after it streams in (it is ~2.6 km ahead: ~85 s at line speed)

@export var ahead: float = 2400.0
@export var behind: float = 450.0
@export var threaded: bool = true
@export var car_count: int = 9
@export var car_lights: int = 2     # cars near the camera that get real headlight beams
@export var street_car_count: int = 8   # cars driving the streets of the towns and villages near the train

const SHOPS := [["INN", "BEER"], ["GROCER", "COFFEE"], ["BAKERY", "BREAD"], ["BUTCHER", "MEAT"],
		["TOBACCONIST", "TOBACCO"], ["BARBER", "SHAVE"], ["CONFECTIONER", "SWEETS"], ["IRONMONGER", "TOOLS"],
		["SHOEMAKER", "SHOES"], ["PHARMACY", "MEDICINE"], ["GENERAL STORE", "GOODS"]]
const OWNERS := ["J. NOVÁK", "F. DVOŘÁK", "V. SVOBODA", "K. ČERNÝ", "A. PROCHÁZKA", "J. KUČERA",
		"M. VESELÝ", "B. HORÁK", "L. POKORNÝ", "E. MAREK", "W. FISCHER", "R. POSPÍŠIL"]
const PAINTS := [Color(0.025, 0.025, 0.028), Color(0.03, 0.08, 0.05), Color(0.2, 0.03, 0.03), Color(0.03, 0.05, 0.13),
		Color(0.16, 0.14, 0.11), Color(0.5, 0.46, 0.36), Color(0.06, 0.06, 0.065)]

var _ts: Node
var _live := {}
var _pending := {}
var _built_mutex := Mutex.new()
var _built: Array = []
var _arms := {}             # crossing index -> [MeshInstance3D]
var _arm_angle := {}        # crossing index -> current angle
var _probe: GroundProbe
var _cars: Array = []       # Car
var _street_cars: Array = []   # Car (street traffic)
var _folk: Townfolk
var _slot_timer := 0.0
var _beams: Array = []      # [SpotLight3D, SpotLight3D] pairs
var _rng := RandomNumberGenerator.new()

class Car:
	var node: Node3D
	var wheels: Array[Node3D] = []
	var wheel_sign: Array[float] = []
	var wheel_r := 0.37
	var road := -1
	var t := 0.0
	var dir := 1.0
	var v := 0.0
	var vmax := 11.0
	var parked := 0.0           # seconds left standing at a road's end
	var pos := Vector2.ZERO     # route (s, z) of its middle
	# Town traffic (street cars): which street, its slot, and a U-turn in progress at a street's end.
	var street := -1
	var slot := ""
	var turning := -1.0         # 0..1 through the U-turn, -1 when driving
	var turn_e := Vector2.ZERO  # the street's centre line where the turn began
	var turn_dir := Vector2.ZERO

func _ready() -> void:
	_ts = get_node_or_null("/root/TrainState")
	_rng.seed = 1931
	LifeProps.warm()
	StationModels.warm()        # before Scenery builds its first station on a worker thread
	StationYard.warm()
	StationHall.warm()          # the staff models load in the background, kept for the whole run
	SceneryMeshes.warm()
	Buildings._font()           # loaded here, never first on a worker thread
	RoadNetwork.ensure()
	FarmLand.ensure()
	_probe = GroundProbe.new()
	_folk = Townfolk.new(GroundProbe.new())
	var scenery := get_parent().get_node_or_null("Scenery")
	if scenery:
		scenery.child_entered_tree.connect(_on_feature)
		for ch in scenery.get_children():
			_on_feature(ch)
	for i in car_count:
		_cars.append(_make_car(i))
	for i in street_car_count:
		var sc := _make_car(i + 3)
		sc.node.name = "StreetCar%d" % i
		sc.vmax = _rng.randf_range(4.5, 5.6)          # 20 km/h in the towns
		_street_cars.append(sc)
	for i in car_lights:
		var pair: Array = []
		for side: float in [-0.42, 0.42]:
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.86, 0.62)
			sp.light_energy = 5.0
			sp.spot_range = 38.0
			sp.spot_angle = 26.0
			sp.spot_attenuation = 1.2
			sp.shadow_enabled = false
			sp.visible = false
			sp.set_meta("x", side)
			add_child(sp)
			pair.append(sp)
		_beams.append(pair)
	_place_cars_initially()

func distance() -> float:
	return float(_ts.get("distance")) if _ts else 0.0

var _halls: Array = []             # the walk-in station halls (HallSpot markers) now built

# No snow falls inside the nearest station hall (it moves with the world, so every frame).
func _hall_shelter(cam: Camera3D) -> void:
	var weather := get_parent().get_node_or_null("Weather")
	if weather == null or not weather.has_method("set_shelter_2"):
		return
	var best: Node3D = null
	var best_d := 120.0
	for h in _halls:
		if is_instance_valid(h) and cam:
			var dd := (h as Node3D).global_position.distance_to(cam.global_position)
			if dd < best_d:
				best_d = dd
				best = h
	if best == null:
		weather.set_shelter_2(AABB())
		return
	var box := best.global_transform * StationHall.room(best.get_meta("kind", "stone"))
	weather.set_shelter_2(box)

func _process(delta: float) -> void:
	var d := distance()
	_take_built()
	_stream(d)
	_barriers(d, delta)
	_drive(d, delta)
	_drive_streets(d, delta)
	var cam := get_viewport().get_camera_3d()
	_hall_shelter(cam)
	if cam:
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if pl == null:
			pl = get_parent().get_node_or_null("Player") as Node3D
		_folk.update(cam.global_position, delta, pl.global_position if pl else Vector3(INF, INF, INF))
	for key in _live:
		var e: Dictionary = _live[key]
		(e.node as Node3D).position.x = d - float(e.s)

# ————— streaming —————

func _stream(d: float) -> void:
	var want := {}
	var c0 := int(floor((d - behind) / LifeBuilder.CHUNK))
	var c1 := int(floor((d + ahead) / LifeBuilder.CHUNK))
	for c in range(c0, c1 + 1):
		want["l%d" % c] = c * LifeBuilder.CHUNK
	for key in _live.keys():
		if not want.has(key):
			_drop_arms(_live[key].node)
			(_live[key].node as Node).queue_free()
			_live.erase(key)
	var missing: Array = []
	for key in want:
		if not _live.has(key) and not _pending.has(key):
			missing.append([absf(float(want[key]) - d), key])
	missing.sort()
	for m: Array in missing:
		if _pending.size() >= 2:
			break
		var key: String = m[1]
		var job := _build.bind(key, float(want[key]))
		if threaded:
			_pending[key] = WorkerThreadPool.add_task(job, false, "life " + key)
		else:
			_pending[key] = -1
			job.call()

# Going (the game quitting): the chunks still being worked out on worker threads are waited for,
# or they run on into a freed node.
func _exit_tree() -> void:
	for tid in _pending.values():
		if tid is int and tid >= 0:
			WorkerThreadPool.wait_for_task_completion(tid)
	_pending.clear()
	_built_mutex.lock()
	_built.clear()
	_built_mutex.unlock()

func _build(key: String, s0: float) -> void:
	var spec := LifeBuilder.new(s0).build()
	_built_mutex.lock()
	_built.append([key, spec, s0])
	_built_mutex.unlock()

func _take_built() -> void:
	_built_mutex.lock()
	var items := _built.duplicate()
	_built.clear()
	_built_mutex.unlock()
	var made := 0
	for it: Array in items:
		var key: String = it[0]
		# One chunk's nodes per frame (the rest wait their turn).
		if made >= 1:
			_built_mutex.lock()
			_built.append(it)
			_built_mutex.unlock()
			continue
		var tid: int = _pending.get(key, -1)
		if tid >= 0:
			WorkerThreadPool.wait_for_task_completion(tid)
		_pending.erase(key)
		if _live.has(key):
			continue
		var node := LifeBuilder.instantiate(it[1])
		node.name = key
		made += 1
		add_child(node)
		node.position.x = distance() - float(it[2])
		_live[key] = {"node": node, "s": it[2]}
		for a: Array in node.get_meta("arms", []):
			var ci: int = a[0]
			if not _arms.has(ci):
				_arms[ci] = []
			_arms[ci].append(a[1])
			(a[1] as Node3D).rotation.z = _arm_angle.get(ci, ARM_UP)

func _drop_arms(node: Node) -> void:
	for a: Array in node.get_meta("arms", []):
		var list: Array = _arms.get(a[0], [])
		list.erase(a[1])

# ————— level crossings —————

func _closed(ci: int, d: float) -> bool:
	var sx: float = RoadNetwork.crossings()[ci].s
	return sx > d + TRAIN_REAR - 25.0 and sx < d + TRAIN_FRONT + CLOSE_AHEAD

func _barriers(d: float, delta: float) -> void:
	for ci in RoadNetwork.crossings().size():
		var target := 0.0 if _closed(ci, d) else ARM_UP
		var a: float = _arm_angle.get(ci, ARM_UP)
		a = move_toward(a, target, ARM_SPEED * delta)
		_arm_angle[ci] = a
		for arm: Node3D in _arms.get(ci, []):
			arm.rotation.z = a

## True when traffic must not enter crossing `ci` (closed, closing, or not fully up yet).
func _blocked(ci: int, d: float) -> bool:
	return _closed(ci, d) or float(_arm_angle.get(ci, ARM_UP)) < ARM_UP - 0.05

# ————— shops —————

func _on_feature(n: Node) -> void:
	if n is Node3D and String(n.name).begins_with("st_"):
		_station_life(n as Node3D)
		return
	if not (n is Node3D) or not n.has_meta("life_center"):
		return
	var town := String(n.name).begins_with("town_")
	var plan: Dictionary = n.get_meta("life_plan", {})
	if plan.is_empty():
		# Villages carry no plan of their own: the road network's (the same TownPlan) by the centre.
		var c0: Vector2 = n.get_meta("life_center")
		for pl: Dictionary in RoadNetwork.places():
			if Vector2(pl.s, pl.z).distance_to(c0) < 1.0 and pl.has("plan"):
				plan = pl.plan
	var square_town := bool(plan.get("town", false))
	var center: Vector2 = n.get_meta("life_center")
	var houses: Array = []
	for h in n.get_children():
		if h.has_meta("front") and h.has_meta("size"):
			houses.append([(h.get_meta("route_pos") as Vector2).distance_to(center), h])
	houses.sort_custom(func(a, b): return a[0] < b[0])
	_house_numbers(n, houses)
	if square_town:
		_street_names(n, plan, houses)
		_town_signs(n, plan)
	if not plan.is_empty():
		_parked_cars(n, plan, square_town)
	# Shops: on the houses built for one (townhouses with shop windows) first, nearest the centre.
	var shop_houses: Array = []
	for e: Array in houses:
		if (e[1] as Node).get_meta("shop_ok", false):
			shop_houses.append(e)
	for e: Array in houses:
		if not (e[1] as Node).get_meta("shop_ok", false):
			shop_houses.append(e)
	houses = shop_houses
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(n.name)) + 5
	var want := rng.randi_range(1, 2)
	if square_town:
		want = 9
	elif town:
		want = rng.randi_range(3, 5)
	var count := mini(houses.size(), want)
	var kinds := range(1, SHOPS.size())
	for i in range(kinds.size() - 1, 0, -1):         # the same shops every journey
		var j := rng.randi() % (i + 1)
		var tmp = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	for i in count:
		# Every village has its inn; the rest at random.
		var kind: Array = SHOPS[0] if i == 0 else SHOPS[kinds[i % kinds.size()]]
		_shop(houses[i][1], kind, OWNERS[rng.randi() % OWNERS.size()], rng)
	# Playground and statue, then the people of the place (after the shops: some stand at their
	# windows), a physics frame on so the houses' solids can be tested for free ground.
	if not plan.is_empty():
		_extras_and_people(n, plan, town, square_town, houses, rng)

## A station's hall, bell and yard. A station streaming in far ahead gets them over the next few
## frames (each piece is 20-40 ms of node building on the main thread; all at once they froze the
## game for half a second); one that is already near the train (the first station, or a warp) gets
## them all at once, so nothing stands on a platform that is not there yet.
func _station_life(n: Node3D) -> void:
	var stn: Dictionary = {}
	for st: Dictionary in RouteData.STATIONS:
		if "st_" + str(st.name) == String(n.name):
			stn = st
	var spread := not stn.is_empty() and absf(float(stn.s) - distance()) > STATION_SPREAD_FROM
	if spread:
		# Past the burst of Scenery's own work as a station and its town come in.
		await get_tree().create_timer(STATION_SPREAD_DELAY, false).timeout
		if not is_instance_valid(n) or not n.is_inside_tree():
			return
	for hs: Node in n.find_children("HallSpot", "Marker3D", true, false):
		StationHall.build(hs as Node3D)
		_halls = _halls.filter(func(x): return is_instance_valid(x))
		_halls.append(hs)
	if spread:
		await get_tree().process_frame
		if not is_instance_valid(n) or not n.is_inside_tree():
			return
	for spot: Node in n.find_children("BellSpot", "Marker3D", true, false):
		var bell := HDProps.place(spot, "station_bell", Transform3D.IDENTITY, "StationBell")
		if bell:
			StationForecourt._vis(bell, 260.0)
			StationYard._box_body(spot as Node3D, Vector3(0.5, 2.0, 0.5), Vector3(0, 1.0, 0))
	if not stn.is_empty() and stn.stop:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(stn.name)) + 5
		StationYard.attach(n, stn, func(kind: String) -> Node3D: return _car_node(kind, rng, false),
				func(s: float, z: float) -> float: return _probe.height(s, z), spread)

func _extras_and_people(n: Node3D, plan: Dictionary, town: bool, square_town: bool, houses: Array,
		rng: RandomNumberGenerator) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(n) or not n.is_inside_tree():
		return
	var extras := TownExtras.build(n, plan, square_town, _probe, rng)
	_folk.populate(n, plan, town, square_town, houses, extras)

func _shop(h: Node3D, kind: Array, owner: String, rng: RandomNumberGenerator) -> void:
	var size: Vector3 = h.get_meta("size")
	var w := size.x
	var dd := size.z
	var fz := -dd * 0.5 - 0.05
	# Townhouses: 2.6 m doors and shop windows up to 2.5 m, so everything sits 0.37 m higher.
	var up := 0.37 if h.has_meta("storeys") else 0.0
	var mat_key: String = ["fascia_green", "fascia_red", "fascia_blue", "fascia_brown"][rng.randi() % 4]
	var board := MeshInstance3D.new()
	board.name = "Fascia"
	var bm := BoxMesh.new()
	var bw := minf(w * 0.62, 6.5)
	bm.size = Vector3(bw, 0.56, 0.07)
	board.mesh = bm
	board.material_override = LifeProps.material(mat_key)
	board.position = Vector3(0, 2.53 + up, fz)     # just over the door, under the eaves
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.visibility_range_end = 260.0
	h.add_child(board)
	var gold := Color(0.95, 0.84, 0.55)
	var title: String = kind[0]
	_text(board, title, Vector3(0, 0.07, -0.04), 0.0046 * minf(1.0, 10.0 / title.length()) * minf(1.0, bw / 4.0), gold)
	_text(board, owner, Vector3(0, -0.17, -0.04), 0.0022, gold)
	# A little lamp over the fascia and the warm light of the shop on the snow.
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	lamp.mesh = sm
	lamp.material_override = LifeProps.material("glow")
	lamp.position = Vector3(0, 2.95 + up, fz - 0.35)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.visibility_range_end = 400.0
	h.add_child(lamp)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.52)
	l.light_energy = 1.4
	l.omni_range = 8.0
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 90.0
	l.distance_fade_length = 25.0
	l.position = Vector3(0, 2.75 + up, fz - 1.4)
	h.add_child(l)
	# Hanging sign on a bracket at one front corner, its board across the street's line.
	var hs := LifeProps.mesh("hanging_sign")
	if hs:
		var mi := MeshInstance3D.new()
		mi.name = "HangingSign"
		mi.mesh = hs
		var cx := (w * 0.5 - 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
		mi.position = Vector3(cx, 2.95 + up, -dd * 0.5 - 0.02)
		mi.rotation.y = PI * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 180.0
		h.add_child(mi)
		var word: String = kind[1]
		var px := 0.0028 * minf(1.0, 6.0 / word.length())
		_text(mi, word, Vector3(0.55, -0.18, 0.026), px, Color(0.1, 0.07, 0.05))
		var back := _text(mi, word, Vector3(0.55, -0.18, -0.026), px, Color(0.1, 0.07, 0.05))
		back.rotation.y = PI

# ————— house numbers, street names, town traffic signs —————

const SQUARE_NAMES := ["MASARYK SQUARE", "REPUBLIC SQUARE", "PEACE SQUARE", "MARKET SQUARE", "TOWN SQUARE"]
const OUT_NAMES := ["PRAGUE ROAD", "VIENNA ROAD", "BRNO ROAD", "PILSEN ROAD", "TABOR ROAD", "CRACOW ROAD"]
const CROSS_NAMES := ["CHURCH ST", "SCHOOL ST", "MILL ST", "BRIDGE ST", "HIGH ST", "GARDEN ST", "MARKET ST"]
const PLATE_RED := Color(0.55, 0.06, 0.05)

## Route point -> the feature root's local space (its origin is at the plan's centre s, z = 0).
func _rlocal(root: Node3D, p: Vector2, y_off := 0.0) -> Vector3:
	var c: Vector2 = root.get_meta("life_center")
	return Vector3(-(p.x - c.x), _probe.height(p.x, p.y) + y_off, p.y)

func _plate(parent: Node3D, text: String, pos: Vector3, w: float, h: float, px: float, vis: float) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, 0.025)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLATE_RED
	mat.roughness = 0.3
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visibility_range_end = vis + 20.0
	parent.add_child(m)
	var l := _text(parent, text, pos + Vector3(0, 0, -0.016), px, Color(0.96, 0.95, 0.9))
	l.rotation.y = PI          # read from the street (-Z of the house)
	l.visibility_range_end = vis

## A small red number plate by every front door (the house's conscription number).
func _house_numbers(root: Node3D, houses: Array) -> void:
	var nums: Array = []
	for i in houses.size():
		nums.append(i + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(root.name)) + 11
	for i in range(nums.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = nums[i]
		nums[i] = nums[j]
		nums[j] = tmp
	for i in houses.size():
		var h: Node3D = houses[i][1]
		var size: Vector3 = h.get_meta("size")
		var dx: float = h.get_meta("door_x", 0.0)
		var tall := h.has_meta("storeys")
		var x := dx + (0.95 if dx < size.x * 0.25 else -0.95)
		_plate(h, str(nums[i]), Vector3(x, 2.85 if tall else 2.35, -size.z * 0.5 - 0.03), 0.3, 0.22, 0.0024, 25.0)

## Street-name plates on the corner houses of every row in a town with a square.
func _street_names(root: Node3D, plan: Dictionary, houses: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(root.name)) + 23
	var square_name: String = SQUARE_NAMES[rng.randi() % SQUARE_NAMES.size()]
	var out_name: String = OUT_NAMES[rng.randi() % OUT_NAMES.size()]
	var cross_name: String = CROSS_NAMES[rng.randi() % CROSS_NAMES.size()]
	var c: Vector2 = plan.center
	var lane: Vector2 = plan.lane
	var ends: Array = plan.ends
	# The half of the main street running toward the line is Nádražní (Station Street).
	var to_line := -1.0 if absf((c - lane * float(ends[0])).y) < absf((c + lane * float(ends[1])).y) else 1.0
	var sq: Array = plan.square
	var runs := {}          # "name|side" -> [[t, house, u (route dir along the street)]]
	for e: Array in houses:
		var h: Node3D = e[1]
		var p: Vector2 = h.get_meta("route_pos")
		var f: Vector2 = h.get_meta("front")
		var size: Vector3 = h.get_meta("size")
		var q := p + f * (size.z * 0.5 + 2.5)          # a point in the street in front of the door
		var name := ""
		var u := lane
		if not sq.is_empty():
			var su := Vector2.from_angle(float(sq[2]))
			var d := q - (sq[0] as Vector2)
			var hs: Vector2 = (sq[1] as Vector2) * 0.5
			if absf(d.dot(su)) < hs.x + 1.0 and absf(d.dot(Vector2(-su.y, su.x))) < hs.y + 1.0:
				name = square_name
				u = Vector2(-f.y, f.x)
		if name == "":
			var best := INF
			for si in (plan.streets as Array).size():
				var s: Array = plan.streets[si]
				var a: Vector2 = s[0]
				var b: Vector2 = s[1]
				var dist := q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b))
				if dist < best:
					best = dist
					u = (b - a).normalized()
					if si == 0:
						name = "STATION RD" if signf((q - c).dot(lane)) == to_line else out_name
					else:
						name = cross_name
			if best > 12.0:
				continue          # outskirts: no street names out there
		var key := "%s|%d" % [name, int(signf(f.dot(Vector2(-u.y, u.x))))]
		if not runs.has(key):
			runs[key] = []
		runs[key].append([p.dot(u), h, u, name])
	for key: String in runs:
		var run: Array = runs[key]
		run.sort_custom(func(a, b): return a[0] < b[0])
		for k: int in ([0, run.size() - 1] if run.size() > 1 else [0]):
			var h: Node3D = run[k][1]
			var u: Vector2 = run[k][2]
			var size: Vector3 = h.get_meta("size")
			# The facade end toward the run's end: house +X in route terms is (-b.x, b.z).
			var bx := h.transform.basis.x
			var xr := Vector2(-bx.x, bx.z)
			var sgn := signf(xr.dot(u)) * (-1.0 if k == 0 else 1.0)
			var nm: String = run[k][3]
			_plate(h, nm, Vector3(sgn * (size.x * 0.5 - 0.75), 3.45 if h.has_meta("storeys") else 2.7, -size.z * 0.5 - 0.035),
					1.25, 0.26, 0.0021 * minf(1.0, 13.0 / nm.length()), 45.0)

## Traffic signs of a town: a speed limit where the main street comes in, a crossroads warning
## before the square, and finger posts at the square's exits (the station one way, the next
## town the other).
func _town_signs(root: Node3D, plan: Dictionary) -> void:
	var c: Vector2 = plan.center
	var lane: Vector2 = plan.lane
	var ends: Array = plan.ends
	var w: float = plan.street_w
	var sqh: Vector2 = plan.get("sq", Vector2(15, 12))
	var to_line := -1.0 if absf((c - lane * float(ends[0])).y) < absf((c + lane * float(ends[1])).y) else 1.0
	var places := RoadNetwork.places()
	var me := 0
	for i in places.size():
		if Vector2(places[i].s, places[i].z).distance_to(c) < 1.0:
			me = i
	for e: int in [0, 1]:
		var sg := -1.0 if e == 0 else 1.0
		var reach := float(ends[e])
		var travel := -lane * sg                      # coming into the town along this half
		var lft := LifeBuilder.left_of(travel)
		# Speed limit just inside the town.
		var p_in := c + lane * sg * (reach - 6.0) + lft * (w * 0.5 + 0.8)
		var s1 := _sign(root, "sign_round", p_in, -travel, 160.0)
		if s1:
			var l := _text(s1, "20", Vector3(0, 2.25, 0.03), 0.0055, Color(0.05, 0.05, 0.06))
			l.rotation.y = 0.0
			l.visibility_range_end = 70.0
		# Crossroads ahead (the square).
		var p_x := c + lane * sg * (sqh.x + 24.0) + lft * (w * 0.5 + 0.8)
		if reach > sqh.x + 30.0:
			_sign(root, "sign_crossroads", p_x, -travel, 160.0)
		# Finger post at the square's exit: this way to ..., the other way to ...
		var out_dir := lane * sg
		var dest := "STATION" if sg == to_line else _neighbour(places, me, out_dir)
		var back := "STATION" if -sg == to_line else _neighbour(places, me, -out_dir)
		var pp := c + lane * sg * (sqh.x + 3.0) + LifeBuilder.left_of(out_dir) * (w * 0.5 + 0.7)
		var post := _sign(root, "signpost", pp, -LifeBuilder.left_of(out_dir), 120.0)
		if post:
			for zz: float in [0.022, -0.022]:
				var a := _text(post, dest, Vector3(0.66, 2.30, zz), 0.0016, Color(0.05, 0.05, 0.06))
				a.rotation.y = 0.0 if zz > 0.0 else PI
				var b := _text(post, back, Vector3(-0.66, 1.98, zz), 0.0016, Color(0.05, 0.05, 0.06))
				b.rotation.y = 0.0 if zz > 0.0 else PI

# ————— town traffic —————

## Cars standing at the kerb (lamps out): along the main street and round the square of a town,
## one by the lane in a village now and then. Children of the town, so they ride with it.
func _parked_cars(root: Node3D, plan: Dictionary, town: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(root.name)) + 37
	var c: Vector2 = plan.center
	var lane: Vector2 = plan.lane
	var w: float = plan.street_w
	var kerb := w * 0.5 - 1.1 if town else w * 0.5 + 0.7
	var spots: Array = []          # [route point, facing]
	if town:
		var sqh: Vector2 = plan.get("sq", Vector2(15, 12))
		for e: int in [0, 1]:
			var sg := -1.0 if e == 0 else 1.0
			var t := sqh.x + 10.0
			while t < float(plan.ends[e]) - 15.0:
				if rng.randf() < 0.45:
					var side := 1.0 if rng.randf() < 0.5 else -1.0
					var face := lane * sg * side
					spots.append([c + lane * sg * t + LifeBuilder.left_of(face) * kerb, face])
				t += rng.randf_range(16.0, 30.0)
		# Round the square, along its long sides.
		var sq: Array = plan.square
		if not sq.is_empty():
			var u := Vector2.from_angle(float(sq[2]))
			var v := Vector2(-u.y, u.x)
			var h: Vector2 = (sq[1] as Vector2) * 0.5
			for k in rng.randi_range(1, 3):
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				spots.append([c + u * rng.randf_range(-h.x + 4.0, h.x - 4.0) + v * side * (h.y - 2.2), u * (1.0 if rng.randf() < 0.5 else -1.0)])
	elif rng.randf() < 0.6:
		var t := rng.randf_range(-float(plan.ends[0]) + 8.0, float(plan.ends[1]) - 8.0)
		var face := lane * (1.0 if rng.randf() < 0.5 else -1.0)
		spots.append([c + lane * t + LifeBuilder.left_of(face) * kerb, face])
	for i in spots.size():
		var p: Vector2 = spots[i][0]
		var face: Vector2 = spots[i][1]
		var car := _car_node(["car_sedan", "car_small", "car_sedan", "truck"][rng.randi() % 4], rng, false)
		if car == null:
			continue
		car.name = "ParkedCar%d" % i
		root.add_child(car)
		car.transform = Transform3D(Basis.looking_at(LifeBuilder.wdir(face), Vector3.UP), _rlocal(root, p, 0.03))

## Parked cars (lamps out) are the detailed HD models (art_source/props_hd/scripts/assets_cars.py);
## the traffic keeps the light ones with turning wheels.
const HD_CARS := {"car_sedan": ["car_sedan_hd", "car_streamline_hd"], "car_small": ["car_small_hd"], "truck": ["van_hd"]}

func _hd_car(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var opts: Array = HD_CARS.get(kind, [])
	if opts.is_empty():
		return null
	var ps := HDProps.scene(opts[rng.randi() % opts.size()])
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	var paint: Color = PAINTS[rng.randi() % PAINTS.size()] if kind != "truck" else [Color(0.07, 0.11, 0.07), Color(0.32, 0.05, 0.04)][rng.randi() % 2]
	var pm: StandardMaterial3D = null
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = 320.0
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m and m.resource_name == "car_paint" and m is StandardMaterial3D:
				if pm == null:
					pm = (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					pm.albedo_color = paint
				mi.set_surface_override_material(si, pm)
	return n

## A car model, painted, its lamps lit or out.
func _car_node(kind: String, rng: RandomNumberGenerator, lit: bool) -> Node3D:
	if not lit:
		var hd := _hd_car(kind, rng)
		if hd:
			return hd
	var ps := LifeProps.car(kind)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	var paint: Color = PAINTS[rng.randi() % PAINTS.size()] if kind != "truck" else Color(0.07, 0.11, 0.07)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 600.0
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m == null:
				continue
			if m.resource_name == "paint" and m is StandardMaterial3D:
				var pm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				pm.albedo_color = paint
				mi.set_surface_override_material(si, pm)
			elif not lit and m.resource_name.begins_with("lamp_") and m is StandardMaterial3D:
				var off := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				off.emission_enabled = false
				off.albedo_color = off.albedo_color.darkened(0.55)
				mi.set_surface_override_material(si, off)
	return n

## The streets near the train that should have cars on them: [street index, slot key, distance].
func _street_slots(d: float) -> Array:
	var out: Array = []
	var streets := RoadNetwork.streets()
	var places := RoadNetwork.places()
	var first := {}
	for i in streets.size():
		var st: Dictionary = streets[i]
		var mid := ((st.a as Vector2).x + (st.b as Vector2).x) * 0.5
		if mid < d - 400.0 or mid > d + 1600.0:
			continue
		var main := not first.has(st.place)
		first[st.place] = true
		var n := 0
		if st.town:
			n = 2 if main else 1
		elif int(places[st.place].size) >= 8 or bool(places[st.place].town):
			n = 1
		for k in n:
			out.append([i, "%d|%d" % [i, k], absf(mid - d - 30.0)])
	out.sort_custom(func(a, b): return a[2] < b[2])
	return out.slice(0, _street_cars.size())

func _drive_streets(d: float, delta: float) -> void:
	_slot_timer -= delta
	if _slot_timer <= 0.0:
		_slot_timer = 0.5
		var want := {}
		for s: Array in _street_slots(d):
			want[s[1]] = s[0]
		var taken := {}
		for c: Car in _street_cars:
			if c.street >= 0 and want.has(c.slot):
				taken[c.slot] = true
			else:
				c.street = -1
				c.node.visible = false
		for key: String in want:
			if taken.has(key):
				continue
			for c: Car in _street_cars:
				if c.street < 0:
					_put_on_street(c, int(want[key]), key)
					break
	var streets := RoadNetwork.streets()
	for c: Car in _street_cars:
		if c.street < 0:
			continue
		var st: Dictionary = streets[c.street]
		var a: Vector2 = st.a
		var b: Vector2 = st.b
		var u := (b - a).normalized()
		var len := a.distance_to(b)
		if c.turning >= 0.0:
			# A slow U-turn round the street's end onto the other lane.
			c.turning = minf(c.turning + delta * c.vmax * 0.5 / (PI * 1.5), 1.0)
			var ang := PI * c.turning
			var l0 := LifeBuilder.left_of(c.turn_dir) * 1.5
			var p := c.turn_e + l0 * cos(ang) + c.turn_dir * 1.5 * sin(ang)
			var tan := (-l0 * sin(ang) + c.turn_dir * 1.5 * cos(ang)).normalized()
			c.v = c.vmax * 0.5
			_pose_at(c, d, p, tan, delta)
			if c.turning >= 1.0:
				c.turning = -1.0
				c.dir = -c.dir
			continue
		var to_end := (len - 3.0 - c.t) if c.dir > 0.0 else (c.t - 3.0)
		var target := minf(c.vmax, sqrt(2.0 * 1.2 * maxf(to_end, 0.0)) + 1.0)
		for o: Car in _street_cars:
			if o == c or o.street != c.street or o.dir != c.dir or o.turning >= 0.0:
				continue
			var gap := (o.t - c.t) * c.dir
			if gap > 0.0 and gap < 30.0:
				target = minf(target, sqrt(2.0 * 2.0 * maxf(gap - 8.0, 0.0)))
		c.v = move_toward(c.v, target, (1.2 if target > c.v else 3.0) * delta)
		c.t += c.dir * c.v * delta
		if to_end <= 0.2:
			c.turning = 0.0
			c.turn_e = a + u * c.t
			c.turn_dir = u * c.dir
		var travel := u * c.dir
		_pose_at(c, d, a + u * c.t + LifeBuilder.left_of(travel) * 1.5, travel, delta)

func _put_on_street(c: Car, si: int, key: String) -> void:
	var st: Dictionary = RoadNetwork.streets()[si]
	var len := (st.a as Vector2).distance_to(st.b)
	c.street = si
	c.slot = key
	c.t = _rng.randf_range(6.0, maxf(len - 6.0, 7.0))
	c.dir = 1.0 if _rng.randf() < 0.5 else -1.0
	c.v = c.vmax * 0.7
	c.turning = -1.0
	c.node.visible = true

## Puts car `c` at route point `p` heading along route direction `travel`, on the drawn ground.
func _pose_at(c: Car, d: float, p: Vector2, travel: Vector2, delta: float) -> void:
	c.pos = p
	var half := 1.5
	var hf := _probe.height(p.x + travel.x * half, p.y + travel.y * half) + 0.03
	var hb := _probe.height(p.x - travel.x * half, p.y - travel.y * half) + 0.03
	var f := LifeBuilder.wdir(travel).normalized()
	var fwd := (f * (half * 2.0) + Vector3(0, hf - hb, 0)).normalized()
	c.node.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(d - p.x, (hf + hb) * 0.5, p.y))
	var spin := c.v * delta / c.wheel_r
	for i in c.wheels.size():
		c.wheels[i].rotate_object_local(Vector3.RIGHT, -spin * c.wheel_sign[i])

func _neighbour(places: Array, me: int, dir: Vector2) -> String:
	var j := me + (1 if dir.x > 0.0 else -1)
	if j < 0 or j >= places.size():
		return "STATION"
	return str(places[j].name).to_upper()

func _sign(root: Node3D, key: String, p: Vector2, face: Vector2, vis: float) -> MeshInstance3D:
	var m := LifeProps.mesh(key)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = key
	mi.mesh = m
	mi.transform = Transform3D(LifeBuilder.facing(face), _rlocal(root, p, -0.05))
	mi.visibility_range_end = vis
	root.add_child(mi)
	return mi

func _text(parent: Node3D, text: String, pos: Vector3, px: float, col: Color) -> Label3D:
	var t := Label3D.new()
	t.text = text
	t.font = Buildings._font()
	t.font_size = 64
	t.pixel_size = px
	t.modulate = col
	t.outline_size = 0
	t.shaded = true
	t.double_sided = false
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.visibility_range_end = 70.0
	t.position = pos
	# Fascia text reads from the street (-Z of the house): turn the label round.
	if parent.name == "Fascia":
		t.rotation.y = PI
	parent.add_child(t)
	return t

# ————— traffic —————

func _make_car(i: int) -> Car:
	var c := Car.new()
	var kind: String = ["car_sedan", "car_small", "car_sedan", "truck", "car_small", "car_sedan", "truck", "car_small", "car_sedan"][i % 9]
	var n := _drive_car(kind, i)
	if n == null:
		var ps := LifeProps.car(kind)
		n = ps.instantiate() if ps else Node3D.new()
	n.name = "Car%d" % i
	add_child(n)
	c.node = n
	c.vmax = _rng.randf_range(8.5, 13.0) if kind != "truck" else _rng.randf_range(7.0, 9.5)
	c.wheel_r = 0.37 if kind != "truck" else 0.45
	var paint: Color = PAINTS[_rng.randi() % PAINTS.size()] if kind != "truck" else [Color(0.07, 0.11, 0.07), Color(0.1, 0.1, 0.1), Color(0.14, 0.1, 0.06)][_rng.randi() % 3]
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 900.0
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m and (m.resource_name == "paint" or m.resource_name == "car_paint") and m is StandardMaterial3D:
				var pm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				pm.albedo_color = paint
				mi.set_surface_override_material(si, pm)
		if mi.name.begins_with("Wheel_"):
			c.wheels.append(mi)
	for w: Node in n.find_children("Wheel_*", "Node3D", true, false):
		if not c.wheels.has(w):
			c.wheels.append(w)
	for w: Node3D in c.wheels:
		c.wheel_sign.append(signf(w.transform.basis.x.x) if absf(w.transform.basis.x.x) > 0.1 else 1.0)
	if n.has_meta("wheel_r"):
		c.wheel_r = n.get_meta("wheel_r")
	n.visible = false
	return c

## The HD driving cars (art_source/props_hd/scripts/assets_cars.py: the body with its lamps lit,
## the road wheels separate): [body, wheel, radius, front z, rear z, front x, rear x].
const DRIVE_CARS := {
	"car_sedan": [["car_sedan_drive", "wheel_car", 0.36, -1.35, 1.55, 0.68, 0.68],
			["car_streamline_drive", "wheel_car_paint", 0.36, -1.45, 1.45, 0.68, 0.7]],
	"car_small": [["car_small_drive", "wheel_small", 0.32, -1.15, 1.25, 0.6, 0.6]],
	"truck": [["van_drive", "wheel_van", 0.4, -1.45, 1.6, 0.72, 0.75]],
}

func _drive_car(kind: String, i: int) -> Node3D:
	var opts: Array = DRIVE_CARS.get(kind, [])
	if opts.is_empty():
		return null
	var spec: Array = opts[i % opts.size()]
	if HDProps.scene(spec[0]) == null or HDProps.scene(spec[1]) == null:
		return null
	var n := Node3D.new()
	HDProps.place(n, spec[0], Transform3D.IDENTITY, "Body")
	var r: float = spec[2]
	for w: Array in [["FL", -1.0, spec[3], spec[5]], ["FR", 1.0, spec[3], spec[5]], ["RL", -1.0, spec[4], spec[6]], ["RR", 1.0, spec[4], spec[6]]]:
		var side: float = w[1]
		# The wheel model's outer face is +x: the left-hand ones turned round.
		var b := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
		HDProps.place(n, spec[1], Transform3D(b, Vector3(side * float(w[3]), r, float(w[2]))), "Wheel_" + String(w[0]))
	n.set_meta("wheel_r", r)
	return n

func _place_cars_initially() -> void:
	var d := distance()
	for c: Car in _cars:
		_spawn(c, d, d - 500.0, d + 1600.0)

## Puts a car somewhere on a road whose stretch lies within [lo, hi] (route s), away from the
## other cars and the crossings. Returns false (and hides it) when there is nowhere.
func _spawn(c: Car, d: float, lo: float, hi: float) -> bool:
	var roads := RoadNetwork.roads()
	for attempt in 12:
		var ri := _rng.randi() % roads.size()
		var r: Dictionary = roads[ri]
		var a := maxf(float(r.s0) + 30.0, lo)
		var b := minf(float(r.s1) - 30.0, hi)
		if b <= a:
			continue
		var s := _rng.randf_range(a, b)
		var t := RoadNetwork._t_at(r, s)
		if r.has("cross_t") and absf(t - float(r.cross_t)) < 80.0:
			continue
		var ok := true
		for o: Car in _cars:
			if o != c and o.road == ri and absf(o.t - t) < 40.0:
				ok = false
				break
		if not ok:
			continue
		c.road = ri
		c.t = t
		c.dir = 1.0 if _rng.randf() < 0.5 else -1.0
		c.v = c.vmax * 0.8
		c.parked = 0.0
		c.node.visible = true
		_pose(c, d, 0.0)
		return true
	c.road = -1
	c.node.visible = false
	return false

func _drive(d: float, delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var cam_p := cam.global_position if cam else Vector3.ZERO
	var roads := RoadNetwork.roads()
	for c: Car in _cars:
		if c.road < 0:
			# Waiting for a road far enough from the camera to appear on.
			if _rng.randf() < delta * 0.5:
				_spawn(c, d, d + 900.0, d + 1700.0)
			continue
		var r: Dictionary = roads[c.road]
		var total := RoadNetwork.length_of(r)
		if c.parked > 0.0:
			c.parked -= delta
			c.v = 0.0
			if c.parked <= 0.0:
				if (c.node.global_position - cam_p).length() > 350.0:
					_respawn(c, d)
				else:
					c.parked = 5.0
			_pose(c, d, 0.0)
			continue
		var target := c.vmax
		# Level crossing ahead: stop short of the barrier while it is down.
		if r.has("cross_t"):
			var ct: float = r.cross_t
			var to_stop := (ct - c.t) * c.dir - 13.0
			if to_stop > -3.0 and to_stop < 120.0 and _blocked(_crossing_of(c.road), d):
				target = minf(target, sqrt(2.0 * 2.5 * maxf(to_stop, 0.0)))
				if to_stop < 0.4:
					target = 0.0
		# Keep a distance behind the car in front going the same way.
		for o: Car in _cars:
			if o == c or o.road != c.road or o.dir != c.dir:
				continue
			var gap := (o.t - c.t) * c.dir
			if gap > 0.0 and gap < 60.0:
				target = minf(target, sqrt(2.0 * 2.5 * maxf(gap - 9.0, 0.0)) + o.v * 0.5)
		var acc := 1.4 if target > c.v else 3.5
		c.v = move_toward(c.v, target, acc * delta)
		c.t += c.dir * c.v * delta
		if c.t < 3.0 or c.t > total - 3.0:
			# Reached a village street: stand there a while (or vanish if nobody is looking).
			c.t = clampf(c.t, 3.0, total - 3.0)
			if (c.node.global_position - cam_p).length() > 350.0:
				_respawn(c, d)
				continue
			c.parked = _rng.randf_range(20.0, 60.0)
		_pose(c, d, delta)
		# Left far behind (or ahead): reuse it somewhere the train is coming to.
		if c.pos.x < d - 700.0 or c.pos.x > d + 2000.0:
			_respawn(c, d)
	_headlight_beams(cam_p)

func _respawn(c: Car, d: float) -> void:
	# Somewhere ahead, beyond what is clearly seen (the land comes toward the train).
	if not _spawn(c, d, d + 900.0, d + 1700.0):
		_spawn(c, d, d - 650.0, d - 450.0)

func _crossing_of(ri: int) -> int:
	var list := RoadNetwork.crossings()
	for i in list.size():
		if int(list[i].road) == ri:
			return i
	return -1

func _pose(c: Car, d: float, delta: float) -> void:
	var r: Dictionary = RoadNetwork.roads()[c.road]
	var pd: Array = RoadNetwork.point_at(r, c.t)
	var p: Vector2 = pd[0]
	var travel: Vector2 = (pd[1] as Vector2) * c.dir
	# Keep left: the middle of the left lane.
	p += LifeBuilder.left_of(travel) * 1.5
	c.pos = p
	var f := LifeBuilder.wdir(travel).normalized()
	var half := 1.5
	var hf := _road_height(r, p + travel * half)
	var hb := _road_height(r, p - travel * half)
	var y := (hf + hb) * 0.5
	var fwd := (f * (half * 2.0) + Vector3(0, hf - hb, 0)).normalized()
	c.node.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(d - p.x, y, p.y))
	var spin := c.v * delta / c.wheel_r
	for i in c.wheels.size():
		c.wheels[i].rotate_object_local(Vector3.RIGHT, -spin * c.wheel_sign[i])

func _road_height(r: Dictionary, p: Vector2) -> float:
	var sx: float = r.cross
	if sx >= 0.0 and absf(p.y) < LifeBuilder.CROSS_CUT + 0.2 and absf(p.x - sx) < 40.0:
		if absf(p.y) <= LifeBuilder.DECK_Z:
			return LifeBuilder.DECK_Y
		var g := _probe.height(p.x, signf(p.y) * (LifeBuilder.CROSS_CUT + 0.2)) + 0.03
		return lerpf(LifeBuilder.DECK_Y, g, smoothstep(LifeBuilder.DECK_Z, LifeBuilder.CROSS_CUT + 0.2, absf(p.y)))
	return _probe.height(p.x, p.y) + 0.03

# Real light beams only for the cars nearest the camera; the rest show their lit lamps.
func _headlight_beams(cam_p: Vector3) -> void:
	var near: Array = []
	for c: Car in _cars + _street_cars:
		if (c.road < 0 and c.street < 0) or not c.node.visible:
			continue
		var dist := (c.node.global_position - cam_p).length()
		if dist < 160.0:
			near.append([dist, c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in _beams.size():
		var pair: Array = _beams[i]
		if i < near.size():
			var c: Car = near[i][1]
			var xf := c.node.global_transform
			for sp: SpotLight3D in pair:
				sp.visible = true
				var x: float = sp.get_meta("x")
				sp.global_transform = Transform3D(xf.basis * Basis(Vector3.RIGHT, -0.12), xf * Vector3(x, 0.95, -2.0))
		else:
			for sp: SpotLight3D in pair:
				sp.visible = false
