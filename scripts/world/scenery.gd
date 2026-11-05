class_name Scenery
extends Node3D
## The landscape the train runs through. The train never moves; this node streams the world past
## it. Everything is placed in route coordinates (s = metres along the line, z = across) and drawn
## at world x = TrainState.distance - s, so the land slides toward +X as the train "advances".
##
##   near chunks (CHUNK m long): snow-covered ground out to NEAR_Z, ballast, sleepers, forests,
##       birches, rocks, telegraph poles and wires
##   far chunks (FAR_CHUNK m): the hills and mountain ranges beyond, coarse, out to FAR_Z
##   features: stations, halts and villages (RouteData), built when they come into range
## Chunks and features are built on worker threads and handed to the tree when ready.

const CHUNK := 100.0
const FAR_CHUNK := 500.0
const NEAR_Z := 700.0
const FAR_Z := 4800.0
const SLEEPER_PITCH := 0.65
const POLE_PITCH := 50.0
const POLE_Z := -6.2

@export var ahead: float = 1300.0            # how far ahead (m) near chunks are kept
@export var behind: float = 350.0
@export var far_ahead: float = 5200.0
@export var far_behind: float = 1800.0
@export var feature_ahead: float = 2600.0
@export var feature_behind: float = 700.0
@export var threaded: bool = true
@export var tree_density: float = 1.0

var _ts: Node
var _live := {}            # key -> {node: Node3D, s: float}
var _pending := {}         # key -> task id (or true when built synchronously)
var _features: Array = []  # {key, s, kind, data}
var _built_mutex := Mutex.new()
var _built: Array = []     # [key, node, s] waiting to enter the tree
var _weather: Node
var _rails: MeshInstance3D

func _ready() -> void:
	_ts = get_node_or_null("/root/TrainState")
	if _ts:
		_ts.connect("phase_changed", _on_phase)
	# HD models load here, on the main thread; the chunk builders only read the cache.
	SceneryMeshes.warm()
	StationModels.warm()         # HD station buildings (idempotent; also called by WorldLife)
	RoadNetwork.ensure()
	FarmLand.ensure()
	# The rails look the same everywhere, so they stay put under the train (centred on its middle).
	var rails := MeshInstance3D.new()
	rails.name = "Rails"
	rails.mesh = SceneryMeshes.get_mesh("rail")
	rails.position = Vector3(-29.0, 0.0, 0.0)
	add_child(rails)
	_rails = rails
	for st in RouteData.STATIONS:
		_features.append({"key": "st_%s" % st.name, "s": st.s, "kind": "station" if st.stop else "halt", "data": st})
		if st.town > 0:
			var z: float = st.side * (Terrain.STATION_FLAT_Z + 30.0 + st.town * 25.0)
			_features.append({"key": "town_%s" % st.name, "s": st.s, "kind": "village",
					"data": {"s": st.s, "z": z, "size": st.town * 8, "church": st.town >= 2, "seed": hash(st.name), "town": st.town}})
	for i in RouteData.VILLAGES.size():
		var v: Dictionary = RouteData.VILLAGES[i]
		_features.append({"key": "vil_%d" % i, "s": v.s, "kind": "village",
				"data": {"s": v.s, "z": v.side * v.off, "size": v.size, "church": v.size >= 8, "seed": 9000 + i}})

func distance() -> float:
	return float(_ts.get("distance")) if _ts else 0.0

func _process(_delta: float) -> void:
	var d := distance()
	_take_built()
	if _weather == null:
		_weather = get_tree().get_first_node_in_group("weather")
	if _weather:
		SceneryMeshes.set_wind(_weather.get("wind"), float(_weather.get("wind_strength")))
	# The rails stay put: their rust and snow scroll with the journey instead.
	var rm := SceneryMeshes.material("rail") as ShaderMaterial
	if rm and _rails:
		rm.set_shader_parameter("scroll", d - _rails.position.x)
	# Wanted near and far chunks (s increases ahead of the train; the loco is at about d + 85).
	var want := {}
	var c0 := int(floor((d - behind) / CHUNK))
	var c1 := int(floor((d + ahead) / CHUNK))
	for c in range(c0, c1 + 1):
		want["n%d" % c] = [c * CHUNK, "near", c]
	var f0 := int(floor((d - far_behind) / FAR_CHUNK))
	var f1 := int(floor((d + far_ahead) / FAR_CHUNK))
	for c in range(f0, f1 + 1):
		want["f%d" % c] = [c * FAR_CHUNK, "far", c]
	for f: Dictionary in _features:
		if f.s > d - feature_behind and f.s < d + feature_ahead:
			want[f.key] = [f.s, f.kind, f]
	# Drop what is out of range, request what is missing (nearest first).
	for key in _live.keys():
		if not want.has(key):
			(_live[key].node as Node).queue_free()
			_live.erase(key)
	var missing: Array = []
	for key in want:
		if not _live.has(key) and not _pending.has(key):
			missing.append([absf(float(want[key][0]) - d), key])
	missing.sort()
	var started := 0
	for m: Array in missing:
		if _pending.size() >= 4 or started >= 2:
			break
		var key: String = m[1]
		_request(key, want[key])
		started += 1
	# Slide everything to where it is now.
	for key in _live:
		var e: Dictionary = _live[key]
		(e.node as Node3D).position.x = d - float(e.s)

# Going (the game quitting): the chunks still being built on worker threads are waited for, or they
# run on into a freed node (its mutex gone) and can bring the engine down on the way out.
func _exit_tree() -> void:
	for tid in _pending.values():
		if tid is int and tid >= 0:
			WorkerThreadPool.wait_for_task_completion(tid)
	_pending.clear()
	_built_mutex.lock()
	for it: Array in _built:
		(it[1] as Node).free()                     # (built, never added)
	_built.clear()
	_built_mutex.unlock()

func _request(key: String, spec: Array) -> void:
	var job := _build.bind(key, spec)
	if threaded:
		_pending[key] = WorkerThreadPool.add_task(job, false, "scenery " + key)
	else:
		_pending[key] = -1
		job.call()

func _take_built() -> void:
	_built_mutex.lock()
	var items := _built.duplicate()
	_built.clear()
	_built_mutex.unlock()
	for it: Array in items:
		var key: String = it[0]
		var node: Node3D = it[1]
		var tid: int = _pending.get(key, -1)
		if tid >= 0:
			WorkerThreadPool.wait_for_task_completion(tid)
		_pending.erase(key)
		if _live.has(key):
			node.free()
			continue
		_set_yard_ends(node, _ts != null and str(_ts.get("phase")) == "stopped")
		add_child(node)
		node.position.x = distance() - float(it[2])
		_live[key] = {"node": node, "s": it[2]}

func _build(key: String, spec: Array) -> void:
	var terrain := Terrain.new()
	var node: Node3D
	match spec[1]:
		"near": node = _build_near(terrain, int(spec[2]))
		"far": node = _build_far(terrain, int(spec[2]))
		"station": node = _build_station(terrain, spec[2].data)
		"halt": node = _build_halt(terrain, spec[2].data)
		"village":
			var vd: Dictionary = spec[2].data
			node = _build_town(terrain, vd) if TownPlan.is_town(vd) else _build_village(terrain, vd)
	node.name = key
	_built_mutex.lock()
	_built.append([key, node, float(spec[0])])
	_built_mutex.unlock()

# ————— terrain meshes —————

static func _rows(limits: Array, sym: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if sym:
		for i in range(limits.size() - 1, -1, -1):
			out.append(-float(limits[i]))
		if limits[0] > 0.0:
			out.append(0.0)
	for v in limits:
		out.append(float(v))
	return out

const NEAR_ROWS := [1.5, 3.0, 4.5, 6.0, 8.0, 10.5, 13.5, 17.0, 21.0, 26.0, 32.0, 39.0, 47.0, 56.0, 67.0,
		80.0, 95.0, 113.0, 135.0, 160.0, 190.0, 225.0, 265.0, 310.0, 360.0, 420.0, 490.0, 570.0, 650.0, 710.0]
const FAR_ROWS := [690.0, 740.0, 800.0, 865.0, 930.0, 1000.0, 1080.0, 1160.0, 1250.0, 1345.0, 1450.0, 1560.0,
		1680.0, 1810.0, 1950.0, 2100.0, 2250.0, 2420.0, 2600.0, 2800.0, 3000.0, 3220.0, 3450.0, 3700.0, 3950.0,
		4220.0, 4500.0, 4800.0]

# Heightfield over s in [s0, s0 + len], rows across at `zs`, resolution ds along. Vertices in
# chunk space (x = -(s - s0)). UV = (s, z) for the snow shader; COLOR.r = trodden dirt.
func _ground_mesh(terrain: Terrain, s0: float, len: float, ds: float, zs: PackedFloat32Array, skirt: bool, forest_mask := false) -> ArrayMesh:
	var ns := int(round(len / ds)) + 1
	var nz := zs.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	verts.resize(ns * nz)
	norms.resize(ns * nz)
	uvs.resize(ns * nz)
	cols.resize(ns * nz)
	for i in ns:
		var s := s0 + i * ds
		for j in nz:
			var z := zs[j]
			var e := clampf(absf(z) * 0.02, 0.5, 20.0)
			var h := terrain.height(s, z)
			var k := i * nz + j
			verts[k] = Vector3(-(s - s0), h, z)
			norms[k] = terrain.normal(s, z, e)
			uvs[k] = Vector2(s, z)
			var dirt := 1.0 - smoothstep(3.2, 7.0, absf(z))
			# Beyond the modelled trees the ground itself carries the forest (COLOR.g).
			var fm := terrain.forest(s, z) * smoothstep(NEAR_Z - 40.0, NEAR_Z + 60.0, absf(z)) if forest_mask else 0.0
			cols[k] = Color(dirt, fm, 0, 1)
	var idx := PackedInt32Array()
	for i in ns - 1:
		for j in nz - 1:
			var a := i * nz + j
			var b := a + 1
			var c := a + nz
			var dd := c + 1
			idx.append_array([a, b, c, b, dd, c])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, SceneryMeshes.material("ground"))
	return mesh

func _build_near(terrain: Terrain, c: int) -> Node3D:
	var s0 := c * CHUNK
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = c * 7919 + 13
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = _ground_mesh(terrain, s0, CHUNK, 4.0, _rows(NEAR_ROWS, true), false)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)
	# Track: ballast and sleepers (rails are one long static mesh on the train side).
	var b := MeshInstance3D.new()
	b.name = "Ballast"
	b.mesh = SceneryMeshes.ballast(0.0, -CHUNK, s0)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(b)
	var ns := int(CHUNK / SLEEPER_PITCH)
	var sl := _multimesh(root, "Sleepers", SceneryMeshes.get_mesh("sleeper"), ns, false)
	sl.visibility_range_end = 450.0
	var first := ceilf(s0 / SLEEPER_PITCH) * SLEEPER_PITCH
	for i in ns:
		var s := first + i * SLEEPER_PITCH
		sl.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(-(s - s0), 0.0, 0.0)))
	# Telegraph poles along the -Z side and their wires.
	var poles: Array[Transform3D] = []
	var p0 := ceilf(s0 / POLE_PITCH) * POLE_PITCH
	var ps := p0
	while ps < s0 + CHUNK:
		var pz := pole_z(ps)
		var h := terrain.height(ps, pz)
		var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.02, 0.02)) * Basis(Vector3.FORWARD, rng.randf_range(-0.015, 0.015))
		poles.append(Transform3D(tilt, Vector3(-(ps - s0), h, pz)))
		ps += POLE_PITCH
	if not poles.is_empty():
		var pm := _multimesh(root, "Poles", SceneryMeshes.get_mesh("pole"), poles.size(), true)
		pm.visibility_range_end = 1200.0
		for i in poles.size():
			pm.multimesh.set_instance_transform(i, poles[i])
		# Wires from each pole to the next (the next may be in the following chunk).
		var lines := PackedVector3Array()
		for i in poles.size():
			var a := poles[i]
			var ns2 := p0 + (i + 1) * POLE_PITCH
			var bt := Transform3D(Basis(), Vector3(-(ns2 - s0), terrain.height(ns2, pole_z(ns2)), pole_z(ns2)))
			for wp: Vector3 in SceneryMeshes.WIRE_POINTS:
				var pa := a * wp
				var pb := bt * wp
				var segs := 10
				for k in segs:
					var t0 := float(k) / segs
					var t1 := float(k + 1) / segs
					lines.append(pa.lerp(pb, t0) - Vector3(0, 0.45 * 4.0 * t0 * (1.0 - t0), 0))
					lines.append(pa.lerp(pb, t1) - Vector3(0, 0.45 * 4.0 * t1 * (1.0 - t1), 0))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = lines
		var wm := ArrayMesh.new()
		wm.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
		wm.surface_set_material(0, SceneryMeshes.material("wire"))
		var wi := MeshInstance3D.new()
		wi.name = "Wires"
		wi.mesh = wm
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wi)
	_build_lineside_fence(root, terrain, s0)
	_build_forest(root, terrain, rng, s0)
	return root

# The boundary fence along both sides of the line, FENCE_Z out, in FENCE_BAY bays: broken at the
# level crossings and the halts' buildings, and stopping at the stopping stations' yard fences
# (StationYard: their ends at x = ±FENCE_X, where this fence meets them).
const FENCE_Z := 7.0
const FENCE_BAY := 3.0

func _build_lineside_fence(root: Node3D, terrain: Terrain, s0: float) -> void:
	var mesh := SceneryMeshes.get_mesh("fence_lineside")
	if mesh == null:
		return
	var xfs: Array = []
	var f0 := ceilf(s0 / FENCE_BAY) * FENCE_BAY
	for side: float in [-1.0, 1.0]:
		var z := side * FENCE_Z
		var s := f0
		while s < s0 + CHUNK:
			if _fence_open(s - FENCE_BAY, s, side):
				s += FENCE_BAY
				continue
			var h0 := terrain.height(s, z)
			var h1 := terrain.height(s - FENCE_BAY, z)
			# A bay runs along +x (back along the route) from its post; sheared to the ground.
			var b := Basis(Vector3(1.0, (h1 - h0) / FENCE_BAY, 0.0), Vector3.UP, Vector3(0, 0, 1))
			xfs.append(Transform3D(b, Vector3(-(s - s0), h0 - 0.05, z)))
			s += FENCE_BAY
	if xfs.is_empty():
		return
	var mi := _multimesh(root, "LinesideFence", mesh, xfs.size(), false)
	mi.visibility_range_end = 320.0
	_fill(mi, xfs)

# True where no fence bay goes between route s a..b on `side`.
static func _fence_open(a: float, b: float, side: float) -> bool:
	for st: Dictionary in RouteData.STATIONS:
		var ss: float = st.s
		if st.stop:
			if b > ss - StationYard.FENCE_X and a < ss + StationYard.FENCE_X:
				return true
		elif float(st.side) == side:
			# The halt's building stands across the fence line (its x is the hash of the name, as
			# Buildings.halt() draws it).
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(st.name)
			var bx := rng.randf_range(-2.0, 2.0)
			var c := ss - bx
			if b > c - 13.0 and a < c + 13.0:
				return true
	for cr: Dictionary in RoadNetwork.crossings():
		var half := 7.0 / maxf(absf(sin(float(cr.angle))), 0.35)
		if b > float(cr.s) - half and a < float(cr.s) + half:
			return true
	return false

# Forests: jittered sampling in bands, denser and finer near the line. Trees are grouped into
# cells (TREE_CELL m along the line × a band × a side), each its own MultiMesh centred on the cell,
# so cells cull, cast shadows and switch detail on their own:
#   band 0/1 (16–130 m): HD card trees near the camera (within HD_RANGE), the low-detail model
#       beyond; band 0 casts shadows
#   band 2/3 (130–700 m): low-detail models only, no shadows, gone past far_trees_end
const TREE_CELL := 50.0
const HD_RANGE := 120.0
const SHADOW_RANGE := 125.0         # the moon's shadows reach about 120 m (Weather)
const HD_MARGIN := 12.0
const TREE_BANDS := [[16.0, 48.0, 5.5], [48.0, 130.0, 5.5], [130.0, 380.0, 9.0], [380.0, 700.0, 15.0]]
const NEAR_KINDS := ["pine_a", "pine_b", "spruce", "spruce"]
const FAR_KINDS := ["pine_a_lod", "pine_b_lod", "spruce_lod", "pine_a_lod"]
@export var far_trees_end: float = 1700.0

func _build_forest(root: Node3D, terrain: Terrain, rng: RandomNumberGenerator, s0: float) -> void:
	var cells := {}          # "band|side|cell|kind" -> Array[Transform3D]
	for bi in TREE_BANDS.size():
		var band: Array = TREE_BANDS[bi]
		var z_in: float = band[0]
		var z_out: float = band[1]
		var step: float = band[2] / sqrt(tree_density)
		var far := bi >= 2
		for zsign: float in [-1.0, 1.0]:
			var z := z_in
			while z < z_out:
				var s := s0
				while s < s0 + CHUNK:
					var ss := s + rng.randf() * step
					var zz: float = zsign * (z + rng.randf() * step)
					# Nothing grows on the roads or the fields (scripts/life/).
					var on_road := RoadNetwork.near_road(ss, zz, 3.0) or FarmLand.covers(ss, zz, 2.0)
					var f := 0.0 if on_road else terrain.forest(ss, zz)
					# Lone birches, rocks and stumps stay out of villages and station yards.
					if not on_road and f <= 0.0 and not far and terrain.in_settlement(ss, zz):
						on_road = true
					var kind := ""
					var xf: Transform3D
					if on_road:
						pass
					elif rng.randf() < f * 0.9:
						var hgt := rng.randf_range(9.0, 21.0) * (0.75 + 0.35 * f)
						if bi == 3:
							kind = "scots_lod" if rng.randf() < 0.1 else ("pine_a_lod2" if rng.randf() < 0.5 else "pine_b_lod2")
						elif far:
							kind = "scots_lod" if rng.randf() < 0.1 else FAR_KINDS[rng.randi() % 4]
						else:
							kind = "scots" if rng.randf() < 0.1 else NEAR_KINDS[rng.randi() % 4]
						if kind.begins_with("scots"):
							hgt *= 1.15
						var y := terrain.height(ss, zz) - 0.2
						var bas := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(hgt * rng.randf_range(0.85, 1.1), hgt, hgt * rng.randf_range(0.85, 1.1)))
						xf = Transform3D(bas, Vector3(-(ss - s0), y, zz))
					elif not far and f < 0.15 and rng.randf() < 0.012:
						var bh := rng.randf_range(7.0, 13.0)
						kind = "birch"
						xf = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * bh), Vector3(-(ss - s0), terrain.height(ss, zz) - 0.1, zz))
					elif bi == 0 and f > 0.05 and rng.randf() < 0.006:
						# A felled tree's stump at the forest edge.
						var ks := rng.randf_range(0.8, 1.4)
						kind = "stump"
						xf = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * ks), Vector3(-(ss - s0), terrain.height(ss, zz) - 0.05, zz))
					elif not far and rng.randf() < 0.004:
						var rs := rng.randf_range(0.6, 2.6)
						var rb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rs * rng.randf_range(0.8, 1.6), rs, rs))
						kind = "rock_a" if rng.randf() < 0.5 else "rock_b"
						xf = Transform3D(rb, Vector3(-(ss - s0), terrain.height(ss, zz) - 0.1, zz))
					if kind != "":
						var cell := int(floor((ss - s0) / TREE_CELL)) if not far else 0
						var ck := "%d|%d|%d|%s" % [bi, int(zsign), cell, kind]
						if not cells.has(ck):
							cells[ck] = []
						cells[ck].append(xf)
					s += step
				z += step
	for ck: String in cells:
		var parts := ck.split("|")
		var bi := int(parts[0])
		var kind: String = parts[3]
		var list: Array = cells[ck]
		# Centre the cell's MultiMesh on its trees (culling and visibility ranges measure from it).
		var c := Vector3.ZERO
		for t: Transform3D in list:
			c += t.origin
		c /= list.size()
		c.y = 0.0
		var local: Array = []
		for t: Transform3D in list:
			local.append(Transform3D(t.basis, t.origin - c))
		var nm := "%s_%s" % [kind.capitalize().replace(" ", ""), ck.replace("|", "_")]
		if kind.begins_with("rock") or kind == "stump":
			var rm := _multimesh(root, nm, SceneryMeshes.get_mesh(kind), local.size(), bi == 0, c)
			_fill(rm, local)
			rm.visibility_range_end = 600.0
		elif kind == "birch":
			var bm := _multimesh(root, nm, SceneryMeshes.get_mesh("birch"), local.size(), bi == 0, c)
			_fill(bm, local)
			bm.visibility_range_end = 700.0
		elif bi <= 1:
			# Near bands: HD up close, the low-detail model beyond.
			var hd := _multimesh(root, nm + "_hd", SceneryMeshes.get_mesh(kind), local.size(), false, c)
			_fill(hd, local)
			hd.visibility_range_end = HD_RANGE
			hd.visibility_range_end_margin = HD_MARGIN
			# Shadows come from the low-detail model (same silhouette, a tenth of the triangles).
			var sh := _multimesh(root, nm + "_sh", SceneryMeshes.get_mesh(kind + "_lod"), local.size(), true, c)
			_fill(sh, local)
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sh.visibility_range_end = SHADOW_RANGE
			var lo := _multimesh(root, nm + "_lo", SceneryMeshes.get_mesh(kind + "_lod"), local.size(), false, c)
			_fill(lo, local)
			lo.visibility_range_begin = HD_RANGE
			lo.visibility_range_begin_margin = HD_MARGIN
			lo.visibility_range_end = far_trees_end
		else:
			var fm := _multimesh(root, nm, SceneryMeshes.get_mesh(kind), local.size(), false, c)
			_fill(fm, local)
			fm.visibility_range_end = far_trees_end + (400.0 if bi == 3 else 0.0)

static func _fill(mi: MultiMeshInstance3D, xfs: Array) -> void:
	for i in xfs.size():
		mi.multimesh.set_instance_transform(i, xfs[i])

# The pole line keeps to the -Z side, except past stations whose platform and building are there.
# At stopping stations it swings out to z = -side * 24, clear of the yard's extra tracks and island
# platform (StationYard), easing over STATION_POLE_EASE metres before and after.
const STATION_POLE_HALF := 120.0
const STATION_POLE_EASE := 60.0
static func pole_z(s: float) -> float:
	var z := POLE_Z
	var st := RouteData.station_at(s)
	if not st.is_empty() and st.stop and st.side < 0:
		z = -POLE_Z
	for stp in RouteData.STATIONS:
		if not stp.stop:
			continue
		var ds := absf(s - float(stp.s))
		if ds < STATION_POLE_HALF + STATION_POLE_EASE:
			var k := 1.0 - smoothstep(STATION_POLE_HALF, STATION_POLE_HALF + STATION_POLE_EASE, ds)
			var away := -float(stp.side) * 24.0
			var base := -POLE_Z if float(stp.side) < 0.0 else POLE_Z
			z = lerpf(base, away, k)
	return z

func _build_far(terrain: Terrain, c: int) -> Node3D:
	var s0 := c * FAR_CHUNK
	var root := Node3D.new()
	# One strip each side of the near ground (never across it).
	var pos := _rows(FAR_ROWS, false)
	var neg := PackedFloat32Array()
	for i in range(pos.size() - 1, -1, -1):
		neg.append(-pos[i])
	for rows: PackedFloat32Array in [neg, pos]:
		var g := MeshInstance3D.new()
		g.name = "Hills"
		g.mesh = _ground_mesh(terrain, s0, FAR_CHUNK, 15.625, rows, false, true)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)
	return root

func _multimesh(parent: Node3D, mm_name: String, mesh: Mesh, count: int, shadows: bool, at := Vector3.ZERO) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.name = mm_name
	mi.multimesh = mm
	mi.position = at
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# ————— features —————

func _build_station(terrain: Terrain, st: Dictionary) -> Node3D:
	var n := Buildings.station(st)
	_yard_floor(n, RouteData.PLATFORM_LEN + 60.0)
	return n

func _build_halt(terrain: Terrain, st: Dictionary) -> Node3D:
	var n := Buildings.halt(st)
	_yard_floor(n, RouteData.HALT_PLATFORM_LEN + 30.0)
	return n


# Walkable ground around a platform (the snow there is a visual mesh only), fenced by invisible
# walls so nobody walks off into the unwalkable land beyond: side walls along the yard's far
# edges, and end walls across the line that only stand while the train is stopped (they would
# cut through it as it comes and goes; see _set_yard_ends).
func _yard_floor(n: Node3D, len: float) -> void:
	var body := StaticBody3D.new()
	body.set_meta("surface", "snow")          # footstep sounds
	body.name = "YardFloor"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(len, 1.0, Terrain.STATION_FLAT_Z * 2.0)
	cs.shape = bs
	cs.position = Vector3(0, Terrain.FORMATION_Y - 0.5, 0)
	body.add_child(cs)
	var hw := Terrain.STATION_FLAT_Z
	for zs: float in [-1.0, 1.0]:
		body.add_child(_wall(Vector3(0, Terrain.FORMATION_Y + 2.0, zs * hw), Vector3(len, 5.0, 0.5)))
	n.add_child(body)
	var ends := StaticBody3D.new()
	ends.name = "YardEnds"
	for xs: float in [-1.0, 1.0]:
		ends.add_child(_wall(Vector3(xs * len * 0.5, Terrain.FORMATION_Y + 2.0, 0), Vector3(0.5, 5.0, hw * 2.0)))
	n.add_child(ends)

static func _wall(at: Vector3, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = at
	return cs

# The yards' end walls stand only while the train is stopped (inside the yard).
func _set_yard_ends(node: Node, on: bool) -> void:
	var ends := node.get_node_or_null("YardEnds")
	if ends == null:
		return
	for c in ends.get_children():
		(c as CollisionShape3D).disabled = not on

func _on_phase(_phase: String) -> void:
	var stopped := _ts != null and str(_ts.get("phase")) == "stopped"
	for key in _live:
		_set_yard_ends(_live[key].node, stopped)

# Houses along a lane through the village centre, facing it, a church in the middle of the bigger
# ones. Placed on the (flattened) ground.
func _build_village(terrain: Terrain, v: Dictionary) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(v.seed)
	var sc: float = v.s
	var zc: float = v.z
	var count: int = v.size
	var lane_dir := Vector2.from_angle(rng.randf_range(-0.6, 0.6) + (PI * 0.5 if rng.randf() < 0.4 else 0.0))
	var lane_n := Vector2(-lane_dir.y, lane_dir.x)
	# Hooks for other streamers (roads, shops): the centre and the lane, in route space (s, z).
	root.set_meta("life_center", Vector2(sc, zc))
	root.set_meta("life_lane", lane_dir)
	var yrng := RandomNumberGenerator.new()
	yrng.seed = int(v.seed) + 7717          # yards draw from their own sequence: the layout stays as it was
	var placed: Array[Vector2] = []
	if v.church:
		var ch := Buildings.church(rng)
		var cp := Vector2(sc, zc) + lane_n * 16.0
		_place(root, ch, terrain, cp, sc, atan2(lane_dir.y, lane_dir.x))
		placed.append(cp)
	var i := 0
	var tries := 0
	while i < count and tries < count * 6:
		tries += 1
		var along := (float(i / 2) - count * 0.25) * rng.randf_range(15.0, 19.0)
		var side := 1.0 if i % 2 == 0 else -1.0
		var off := side * rng.randf_range(10.0, 14.0) + side * (float(i % 4 >= 2) * 18.0)
		var p := Vector2(sc, zc) + lane_dir * along + lane_n * off
		var ok := true
		for q in placed:
			if q.distance_to(p) < 13.0:
				ok = false
				break
		# Never on the line or the station yard.
		if absf(p.y) < 18.0:
			ok = false
		if not ok:
			i += 1
			continue
		var h := Buildings.house(rng, 0.45)
		h.set_meta("front", -side * lane_n)          # route-space direction the front door faces
		h.set_meta("route_pos", p)
		# Front (-Z local) faces the lane.
		var face := atan2(lane_dir.y, lane_dir.x) + (PI if side > 0 else 0.0) + rng.randf_range(-0.12, 0.12)
		_place(root, h, terrain, p, sc, face)
		_add_yard(h, yrng, p)
		placed.append(p)
		i += 1
	Buildings.merge_group(root)
	return root

# ————— towns —————

# Route point at `a` metres along the lane and `c` across it from the centre.
static func _tp(c0: Vector2, lane: Vector2, a: float, c: float) -> Vector2:
	return c0 + lane * a + Vector2(-lane.y, lane.x) * c

# Never on the line, in a station yard or past the town's levelled ground.
func _buildable(p: Vector2, c0: Vector2, radius: float) -> bool:
	if absf(p.y) < 20.0 or p.distance_to(c0) > radius:
		return false
	var st := RouteData.station_at(p.x)
	return st.is_empty() or absf(p.y) > Terrain.STATION_FLAT_Z + 8.0

# A terraced row: houses side by side from t0 to t1 along `u`, fronts on the line through `origin`
# (at t = 0) and facing `f` (toward the street). Alleys open now and then. Returns how many.
func _row(root: Node3D, terrain: Terrain, rng: RandomNumberGenerator, s0: float, c0: Vector2, radius: float,
		origin: Vector2, u: Vector2, f: Vector2, t0: float, t1: float, tall: float, shop: float) -> int:
	var t := t0
	var built := 0
	var since_gap := 0
	while t < t1 - 6.0:
		var w := rng.randf_range(7.0, 10.5)
		if t + w > t1:
			w = t1 - t
			if w < 6.0:
				break
		var d := rng.randf_range(9.0, 11.0)
		var p := origin + u * (t + w * 0.5) - f * (d * 0.5)
		var storeys := 3 if rng.randf() < tall else 2
		var gable := rng.randf() < 0.35
		var shop_ok := rng.randf() < shop
		if _buildable(p, c0, radius):
			var h := Buildings.townhouse(rng, w, d, storeys, gable, shop_ok)
			h.set_meta("front", f)
			h.set_meta("route_pos", p)
			_place(root, h, terrain, p, s0, atan2(f.y, f.x) - PI * 0.5)
			built += 1
		t += w
		since_gap += 1
		if since_gap >= 3 and rng.randf() < 0.35:
			t += 3.2          # an alley through to the yards behind
			since_gap = 0
	return built

## A town (the bigger station towns, town >= 2): a square (náměstí) at the centre with the church
## on one side, a Marian column, a fountain, lamps, benches and a few trees; terraced rows of
## burgher houses along the main street (along the lane), round the square and down a cross
## street; village houses with yards on the outskirts. Merged into a few meshes at the end.
## Meta for WorldLife (route space): life_center, life_lane, life_street_half (main street from
## centre to end), life_square [centre, size (along, across), angle], life_streets [[a, b, width]].
func _build_town(terrain: Terrain, v: Dictionary) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(v.seed)
	var yrng := RandomNumberGenerator.new()
	yrng.seed = int(v.seed) + 7717
	var big: bool = int(v.get("town", 2)) >= 3
	var s0: float = v.s
	var plan := TownPlan.plan(v)
	var c0: Vector2 = plan.center
	var lane: Vector2 = plan.lane
	# Same first draws as the plan (keeps the rest of this town's sequence stable).
	rng.randf()
	rng.randf()
	var lane_n := Vector2(-lane.y, lane.x)
	var radius := (40.0 + float(v.get("town", 2)) * 45.0) * 1.05
	var main_half: float = plan.rows_half
	var ends: Array = plan.ends
	var sq_a: float = plan.sq.x
	var sq_c: float = plan.sq.y
	var street: float = float(plan.street_w) * 0.5
	var cross_half: float = plan.cross
	root.set_meta("life_center", c0)
	root.set_meta("life_lane", lane)
	root.set_meta("life_plan", plan)
	# The church on the far side of the square.
	var ch := Buildings.church(rng)
	_place(root, ch, terrain, _tp(c0, lane, 0.0, sq_c + 7.5), s0, atan2(lane.y, lane.x))
	var tall := 0.55 if big else 0.3
	# Main street, both sides, out from the square (each way as far as the plan's rows reach).
	for side: float in [-1.0, 1.0]:
		var f := -side * lane_n
		var line := _tp(c0, lane, 0.0, side * street)
		_row(root, terrain, rng, s0, c0, radius, line, lane, f, sq_a + 0.5, minf(main_half, float(ends[1]) - 18.0), tall, 0.55)
		_row(root, terrain, rng, s0, c0, radius, line, -lane, f, sq_a + 0.5, minf(main_half, float(ends[0]) - 18.0), tall, 0.55)
	# Round the square: the near side (gap for the cross street), the church side's corners.
	var near := _tp(c0, lane, 0.0, -sq_c)
	_row(root, terrain, rng, s0, c0, radius, near, lane, lane_n, street, sq_a, tall + 0.2, 0.7)
	_row(root, terrain, rng, s0, c0, radius, near, -lane, lane_n, street, sq_a, tall + 0.2, 0.7)
	var far := _tp(c0, lane, 0.0, sq_c)
	_row(root, terrain, rng, s0, c0, radius, far, lane, -lane_n, 14.0, sq_a, tall, 0.5)
	_row(root, terrain, rng, s0, c0, radius, far, -lane, -lane_n, 14.0, sq_a, tall, 0.5)
	# The cross street, away from the church (if the plan has room for one).
	if cross_half > 0.0:
		for q: float in [-1.0, 1.0]:
			var line2 := _tp(c0, lane, q * street, 0.0)
			_row(root, terrain, rng, s0, c0, radius, line2, -lane_n, -q * lane, sq_c + 11.5, cross_half, tall * 0.5, 0.3)
	# Outskirts: village houses with yards along the main street beyond the rows, to its ends.
	for side: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			var a_end := float(ends[1] if e > 0.0 else ends[0])
			var a := minf(main_half, a_end - 18.0) + 6.0
			while a < a_end - 4.0:
				var p := _tp(c0, lane, e * a, side * rng.randf_range(11.0, 14.0))
				if _buildable(p, c0, radius * 1.15):
					var h := Buildings.house(rng, 0.45)
					h.set_meta("front", -side * lane_n)
					h.set_meta("route_pos", p)
					_place(root, h, terrain, p, s0, atan2(lane.y, lane.x) + (PI if side > 0 else 0.0) + rng.randf_range(-0.08, 0.08))
					_add_yard(h, yrng, p)
				a += rng.randf_range(17.0, 22.0)
	# The square: Marian column, fountain, lamps, benches, trees.
	_square_piece(root, terrain, Buildings.marian_column(rng), _tp(c0, lane, -sq_a * 0.45, -sq_c * 0.3), s0)
	_square_piece(root, terrain, Buildings.fountain(), _tp(c0, lane, sq_a * 0.5, -sq_c * 0.3), s0)
	for xa: float in [-1.0, 1.0]:
		for xc: float in [-1.0, 1.0]:
			var lp := _tp(c0, lane, xa * (sq_a - 2.5), xc * (sq_c - 2.5))
			Buildings._lamp_post(root, Vector3(-(lp.x - s0), terrain.height(lp.x, lp.y) - 0.05, lp.y), xa * xc > 0.0)
			var tp := _tp(c0, lane, xa * (sq_a - 6.0), xc * (sq_c - 4.0))
			var tree := MeshInstance3D.new()
			tree.name = "SquareTree"
			tree.mesh = SceneryMeshes.get_mesh("birch")
			tree.set_meta("keep", true)
			tree.position = Vector3(-(tp.x - s0), terrain.height(tp.x, tp.y) - 0.1, tp.y)
			tree.scale = Vector3.ONE * rng.randf_range(8.0, 10.0)
			tree.rotation.y = rng.randf() * TAU
			root.add_child(tree)
	for k in 2:
		var bp := _tp(c0, lane, sq_a * 0.5 + (k * 2.0 - 1.0) * 4.5, -sq_c * 0.3)
		Buildings._bench(root, Vector3(-(bp.x - s0), terrain.height(bp.x, bp.y) - 0.05, bp.y))
	Buildings.merge_group(root)
	return root

func _square_piece(root: Node3D, terrain: Terrain, b: Node3D, p: Vector2, s0: float) -> void:
	b.position = Vector3(-(p.x - s0), terrain.height(p.x, p.y) - 0.1, p.y)
	root.add_child(b)

# A house's yard, unless its fence would stand on a field, an orchard, a road or by the line.
func _add_yard(h: Node3D, rng: RandomNumberGenerator, p: Vector2) -> void:
	var hs: Vector3 = h.get_meta("size")
	var y := Buildings.yard(rng, hs.x, hs.z, float(h.get_meta("door_x", 0.0)))
	var ext: Array = y.get_meta("extent")
	for cx: float in [ext[0], ext[1]]:
		for cz: float in [ext[2], ext[3]]:
			var o := h.basis * Vector3(cx, 0.0, cz)
			var rp := p + Vector2(-o.x, o.z)
			if absf(rp.y) < 22.0 or FarmLand.covers(rp.x, rp.y, 1.0) or RoadNetwork.near_road(rp.x, rp.y, 1.5):
				y.free()
				return
	h.add_child(y)

# Puts a building at route point p (s, z) relative to the feature origin s0, rotated `yaw` about Y
# in route space (0 = local +X along +s), sunk so no corner floats.
func _place(root: Node3D, b: Node3D, terrain: Terrain, p: Vector2, s0: float, yaw: float) -> void:
	var size: Vector3 = b.get_meta("size", Vector3(10, 8, 8))
	var low := INF
	for cx: float in [-0.5, 0.5]:
		for cz: float in [-0.5, 0.5]:
			var o := Vector2(cx * size.x, cz * size.z).rotated(yaw)
			low = minf(low, terrain.height(p.x + o.x, p.y + o.y))
	# Route s grows toward world -X: mirror the yaw into world space.
	b.position = Vector3(-(p.x - s0), low - 0.25, p.y)
	b.rotation.y = yaw + PI
	root.add_child(b)
