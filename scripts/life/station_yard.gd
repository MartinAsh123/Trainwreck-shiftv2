class_name StationYard
extends RefCounted
## The yard round every stopping station, added when the station appears (WorldLife hears Scenery
## add "st_<NAME>"), on the main thread from meshes made once in warm():
##   - an island platform across the line (benches, lamps, an umbrella canopy; under the town
##     stations' train shed instead its lanterns' light),
##   - a loop track beyond it, joined to the main line by curved connections past both platform ends,
##     and a siding off the loop with goods wagons and a goods shed, which runs on as a spur curving
##     away from the line to a buffer stop,
##   - a palisade fence along the yard's edge (where Scenery's invisible yard walls are), with gaps
##     for the tracks and a gate behind the station building,
##   - walkable ramps at both ends of both platforms, and a stone footing under station buildings
##     that stand on the platform level.
## Canonical frame: the station's own (x along the line, track at z = 0), platform side +z; stations
## with the platform on the -z side get the yard turned half round.

const HDProps := preload("res://scripts/train/hd_props.gd")
const LOOP_Z := -8.74                 # loop track (island platform edge 1.62 from each track)
const SIDING_Z := -13.5
const PLAT_W := 5.5
const PLAT_EDGE := 1.62
const PLAT_Y := 0.55
const FENCE_X := 94.0
const FENCE_Z := 69.0
const SAMPLE := 2.0
const RAIL_HALF := 0.7535

static var _meshes := {}                # "loop_rails", "loop_ballast", "siding_rails", ...
static var _sleepers := {}              # track -> Array[Transform3D]
static var _paths := {}                 # track -> PackedVector2Array (x, z)
static var _rail_mat: Material

static func warm() -> void:
	if not _paths.is_empty():
		return
	SceneryMeshes.warm()
	StationModels.warm()
	var rm := SceneryMeshes.material("rail")
	_rail_mat = rm.duplicate() if rm else null     # its own copy: the main rails' one scrolls
	_paths["loop"] = _loop_path()
	_paths["siding"] = _siding_path()
	for k: String in _paths:
		var p: PackedVector2Array = _paths[k]
		_meshes[k + "_rails"] = _rails(p)
		_meshes[k + "_ballast"] = _ballast(p, -0.012 if k == "loop" else -0.006)
		_sleepers[k] = _sleeper_xfs(p)

static func _loop_path() -> PackedVector2Array:
	var out := PackedVector2Array()
	var x := 118.0
	while x >= -118.0:
		var ax := absf(x)
		var k := 1.0 if ax <= 68.0 else 0.5 + 0.5 * cos(PI * (ax - 68.0) / 50.0)
		out.append(Vector2(x, LOOP_Z * k))
		x -= SAMPLE
	return out

static func _siding_path() -> PackedVector2Array:
	var out := PackedVector2Array()
	var x := 68.0
	while x >= -88.0:
		var z: float
		if x > 38.0:
			z = lerpf(LOOP_Z, SIDING_Z, 0.5 - 0.5 * cos(PI * (68.0 - x) / 30.0))
		elif x >= -50.0:
			z = SIDING_Z
		else:
			# The spur curving away from the line (crosses the pole line between two poles).
			z = SIDING_Z - 10.5 * pow((-50.0 - x) / 25.0, 2.0)
		out.append(Vector2(x, z))
		x -= SAMPLE
	return out

# ————— track meshes —————

const RAIL_PROF: Array[Vector2] = [Vector2(0.065, 0.0), Vector2(0.065, 0.01), Vector2(0.03, 0.022),
		Vector2(0.011, 0.034), Vector2(0.008, 0.1), Vector2(0.018, 0.108), Vector2(0.034, 0.113), Vector2(0.036, 0.142),
		Vector2(0.03, 0.149), Vector2(0.012, 0.152), Vector2(-0.012, 0.152), Vector2(-0.03, 0.149), Vector2(-0.036, 0.142),
		Vector2(-0.034, 0.113), Vector2(-0.018, 0.108), Vector2(-0.008, 0.1), Vector2(-0.011, 0.034), Vector2(-0.03, 0.022),
		Vector2(-0.065, 0.01), Vector2(-0.065, 0.0)]

static func _lat(p: PackedVector2Array, i: int) -> Vector2:
	var a := p[maxi(i - 1, 0)]
	var b := p[mini(i + 1, p.size() - 1)]
	var t := (b - a).normalized()
	return Vector2(-t.y, t.x)

## Sweeps `prof` (x across, y up) along the path at lateral offset `off`; UV = (metres along, v).
static func _sweep(st: SurfaceTool, p: PackedVector2Array, prof: Array, off: float, v_scale: float) -> void:
	var along := PackedFloat32Array()
	along.resize(p.size())
	for i in range(1, p.size()):
		along[i] = along[i - 1] + p[i].distance_to(p[i - 1])
	for i in p.size() - 1:
		var la := _lat(p, i)
		var lb := _lat(p, i + 1)
		for j in prof.size() - 1:
			var a: Vector2 = prof[j]
			var b: Vector2 = prof[j + 1]
			var pa0 := p[i] + la * (off + a.x)
			var pb0 := p[i] + la * (off + b.x)
			var pa1 := p[i + 1] + lb * (off + a.x)
			var pb1 := p[i + 1] + lb * (off + b.x)
			var q := [Vector3(pa0.x, a.y, pa0.y), Vector3(pb0.x, b.y, pb0.y), Vector3(pa1.x, a.y, pa1.y), Vector3(pb1.x, b.y, pb1.y)]
			var uv := [Vector2(along[i], a.y * v_scale), Vector2(along[i], b.y * v_scale), Vector2(along[i + 1], a.y * v_scale), Vector2(along[i + 1], b.y * v_scale)]
			# Winding toward the outside (up for the ballast top): front faces clockwise.
			var ids := [0, 1, 2, 1, 3, 2]
			var q0: Vector3 = q[0]
			var q1: Vector3 = q[1]
			var q2: Vector3 = q[2]
			var q3: Vector3 = q[3]
			var nrm := (q1 - q0).cross(q2 - q0)
			var mid := (q0 + q1 + q2 + q3) * 0.25
			var centre := Vector3(p[i].x, 0.07 if v_scale > 2.0 else -0.3, p[i].y) + Vector3(la.x, 0, la.y) * off
			if nrm.dot(mid - centre) > 0.0:
				ids = [0, 2, 1, 1, 2, 3]
			for id: int in ids:
				st.set_uv(uv[id])
				st.add_vertex(q[id])

static func _rails(p: PackedVector2Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: float in [-1.0, 1.0]:
		_sweep(st, p, RAIL_PROF, s * RAIL_HALF, 1.0 / 0.152)
	st.generate_normals()
	st.generate_tangents()
	var m := st.commit()
	if _rail_mat:
		m.surface_set_material(0, _rail_mat)
	return m

static func _ballast(p: PackedVector2Array, dy: float) -> ArrayMesh:
	var f := Terrain.FORMATION_Y
	var prof: Array = [Vector2(-3.1, f - 0.04), Vector2(-2.45, f + 0.12), Vector2(-1.85, -0.05), Vector2(-0.6, -0.035),
			Vector2(0.0, -0.04), Vector2(0.6, -0.035), Vector2(1.85, -0.05), Vector2(2.45, f + 0.12), Vector2(3.1, f - 0.04)]
	for i in prof.size():
		prof[i] = Vector2(prof[i].x, prof[i].y + dy)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sweep(st, p, prof, 0.0, 1.0)
	st.generate_normals()
	if SceneryMeshes.hd_enabled:
		st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, SceneryMeshes.material("ballast_hd" if SceneryMeshes.hd_enabled else "ballast"))
	return m

static func _sleeper_xfs(p: PackedVector2Array) -> Array:
	var out: Array = []
	var acc := 0.0
	for i in p.size() - 1:
		var seg := p[i].distance_to(p[i + 1])
		var t := (p[i + 1] - p[i]).normalized()
		while acc < seg:
			var q := p[i] + t * acc
			var x := Vector3(t.x, 0, t.y)
			var z := Vector3(-t.y, 0, t.x)
			out.append(Transform3D(Basis(x, Vector3.UP, z), Vector3(q.x, 0.0, q.y)))
			acc += 0.65
		acc -= seg
	return out

# ————— the yard of one station —————

# Waits a frame; false when the station has gone meanwhile (streamed out, the game quitting).
static func _next_frame(n: Node3D) -> bool:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return false
	await n.get_tree().process_frame
	return is_instance_valid(n) and n.is_inside_tree() and n.has_node("Yard")

## `car_fn(kind) -> Node3D` makes the cars parked on the forecourt (see StationForecourt).
## `spread`: built over a few frames (a station streaming in far ahead), not all in this one.
static func attach(n: Node3D, st: Dictionary, car_fn := Callable(), ground_fn := Callable(), spread := false) -> void:
	if _paths.is_empty() or n.has_node("Yard"):
		return
	var side: float = st.side
	var town: int = st.get("town", 0)
	var shed := town >= 3 and n.find_child("TrainShed", true, false) != null
	var yard := Node3D.new()
	yard.name = "Yard"
	if side < 0:
		yard.rotation.y = PI
	n.add_child(yard)
	# Tracks.
	for k: String in _paths:
		var r := MeshInstance3D.new()
		r.name = k.capitalize() + "Rails"
		r.mesh = _meshes[k + "_rails"]
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.visibility_range_end = 500.0
		yard.add_child(r)
		var b := MeshInstance3D.new()
		b.name = k.capitalize() + "Ballast"
		b.mesh = _meshes[k + "_ballast"]
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		yard.add_child(b)
		_multimesh(yard, k.capitalize() + "Sleepers", SceneryMeshes.get_mesh("sleeper"), _sleepers[k], 450.0, false)
	# Buffer stop at the end of the spur, its struts toward the dead end.
	var sp: PackedVector2Array = _paths["siding"]
	var e1 := sp[sp.size() - 1]
	var t_end := (e1 - sp[sp.size() - 2]).normalized()
	_model(yard, "buffer_stop", Transform3D(_basis_along(t_end), Vector3(e1.x, 0.0, e1.y) - Vector3(t_end.x, 0, t_end.y) * 1.2), 300.0)
	# Goods wagons on the siding, a goods shed beside it (loading side toward the track).
	for i in 3:
		var wx := 6.0 - i * 8.9
		var wagon := _model(yard, "boxcar", Transform3D(Basis.IDENTITY, Vector3(wx, 0.15, SIDING_Z)), 450.0)
		_box_body(wagon, Vector3(8.2, 3.3, 2.8), Vector3(0, 1.8, 0))
	var gs := _model(yard, "goods_shed", Transform3D(Basis(Vector3.UP, PI), Vector3(-25.0, Terrain.FORMATION_Y + 0.4, SIDING_Z - 6.3)), 500.0)
	_box_body(gs, Vector3(18.0, 6.0, 9.4), Vector3(0, 2.6, -0.6))
	if spread and not await _next_frame(n):
		return
	# Island platform between the main line and the loop.
	Buildings._platform(n, RouteData.PLATFORM_LEN, PLAT_W, PLAT_EDGE, PLAT_Y, -side)
	var iz := -(PLAT_EDGE + PLAT_W * 0.5)
	if shed:
		for i in 8:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.8, 0.55)
			l.light_energy = 2.2
			l.omni_range = 15.0
			l.distance_fade_enabled = true
			l.distance_fade_begin = 140.0
			l.distance_fade_length = 30.0
			l.position = Vector3(-60.0 + i * 16.0, Terrain.FORMATION_Y + 3.85, -4.4)
			yard.add_child(Buildings.track_lamp(l))
	else:
		for i in 5:
			var cx := -12.0 + i * 6.0
			_model(yard, "island_canopy", Transform3D(Basis.IDENTITY, Vector3(cx, PLAT_Y, iz)), 400.0)
			_box_body(yard, Vector3(0.3, 3.0, 0.3), Vector3(cx, PLAT_Y + 1.5, iz))
		for i in 5:
			var lx := lerpf(-58.0, 58.0, i / 4.0)
			if absf(lx) < 20.0:
				continue
			Buildings._lamp_post(yard, Vector3(lx, PLAT_Y, iz), i % 2 == 0)
	if spread and not await _next_frame(n):
		return
	# Benches back to back along the island, facing both tracks.
	for i in 6:
		var bx := -25.0 + i * 10.0
		for f: float in [-1.0, 1.0]:
			var before := yard.get_child_count()
			var bp := Vector3(bx, PLAT_Y, iz + f * 0.55)
			Buildings._bench(yard, bp)
			for c in range(before, yard.get_child_count()):
				var ch := yard.get_child(c) as Node3D
				if ch and ch.position.distance_to(bp) < 0.01:      # the HD bench (seat toward -Z): face the track
					ch.rotation.y = PI if f > 0.0 else 0.0
	for xs: float in [-1.0, 1.0]:
		Buildings._name_board(yard, str(st.name), Vector3(xs * (RouteData.PLATFORM_LEN * 0.5 - 4.0), PLAT_Y, iz), Buildings._font())
	# Benches at the far ends of the main platform too.
	for xs: float in [-50.0, 50.0]:
		Buildings._bench(yard, Vector3(xs, PLAT_Y, PLAT_EDGE + PLAT_W - 1.4))
	# Walkable ramps at the ends of both platforms.
	var ramps := StaticBody3D.new()
	ramps.name = "PlatformRamps"
	ramps.set_meta("surface", "snow")
	yard.add_child(ramps)
	for zc: float in [PLAT_EDGE + PLAT_W * 0.5, iz]:
		for xs: float in [-1.0, 1.0]:
			var top := Vector3(xs * RouteData.PLATFORM_LEN * 0.5, PLAT_Y, zc)
			var foot := Vector3(xs * (RouteData.PLATFORM_LEN * 0.5 + 6.0), Terrain.FORMATION_Y, zc)
			var along := (foot - top).normalized()
			var bz := Vector3(0, 0, 1)
			var by := bz.cross(along)
			if by.y < 0.0:
				by = -by
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(top.distance_to(foot), 0.1, PLAT_W)
			cs.shape = bs
			cs.transform = Transform3D(Basis(along, by, along.cross(by)), (top + foot) * 0.5 - by * 0.05)
			ramps.add_child(cs)
	# Footing under station buildings that stand at platform level.
	_footings(n)
	if spread and not await _next_frame(n):
		return
	# The town side: entrance, forecourt, approach road and gate, car park, transformer.
	var gate_x := StationForecourt.build(yard, n, st, car_fn, ground_fn)
	if is_nan(gate_x):
		gate_x = 0.0
		var bldg := n.find_child("StationBuilding", false, false) as Node3D
		if bldg:
			gate_x = bldg.position.x * (1.0 if side > 0 else -1.0)
	# The security fence round the yard (galvanised chain-link with barbed wire, its outside away
	# from the yard), with gaps for the tracks and the gate behind the building; warning plates on
	# it every few bays, facing out.
	if spread and not await _next_frame(n):
		return
	var gap := StationForecourt.GATE_GAP
	var xfs: Array = []
	_fence_run(xfs, Vector2(-FENCE_X, FENCE_Z), Vector2(gate_x - gap, FENCE_Z))
	_fence_run(xfs, Vector2(gate_x + gap, FENCE_Z), Vector2(FENCE_X, FENCE_Z))
	_fence_run(xfs, Vector2(FENCE_X, -FENCE_Z), Vector2(-FENCE_X, -FENCE_Z))
	# The ends come in to the line fence (Scenery.FENCE_Z), leaving the way open for the tracks.
	var lz := Scenery.FENCE_Z
	_fence_run(xfs, Vector2(FENCE_X, FENCE_Z), Vector2(FENCE_X, lz))
	_fence_run(xfs, Vector2(FENCE_X, -lz), Vector2(FENCE_X, -FENCE_Z))
	_fence_run(xfs, Vector2(-FENCE_X, lz), Vector2(-FENCE_X, FENCE_Z))
	_fence_run(xfs, Vector2(-FENCE_X, -FENCE_Z), Vector2(-FENCE_X, -lz))
	_platform_fence(yard, n, lz)
	var fence_mesh := HDProps.mesh("fence_chainlink")
	if fence_mesh == null:
		fence_mesh = StationModels.mesh("station_fence_detail")
	_multimesh(yard, "Fence", fence_mesh, xfs, 350.0, false)
	var signs := ["warning_sign_a", "warning_sign_b", "warning_sign_a", "warning_sign_c"]
	for i in range(3, xfs.size(), 9):
		var fx: Transform3D = xfs[i]
		var b := fx.basis.orthonormalized()
		var at := fx.origin + fx.basis.x * 0.5
		var sgn := HDProps.place(yard, signs[(i / 9) % signs.size()], Transform3D(b * Basis(Vector3.UP, PI), at), "WarningSign")
		if sgn:
			StationForecourt._vis(sgn, 120.0)
	_fence_body(yard, xfs)

# The fence along the back of the main platform (on its top, down the ramps, then on the ground out
# to the yard's end fences, where the line fence goes on), broken only where the station building
# stands: from the platform one goes into town through the booking hall. Where the building's
# front stands back from the fence line (the town station's wings) a short run closes the gap.
static func _platform_fence(yard: Node3D, n: Node3D, z: float) -> void:
	var mesh := SceneryMeshes.get_mesh("fence_lineside")
	if mesh == null:
		return
	var inv := yard.transform.affine_inverse()
	var boxes: Array = []                     # AABBs of the building's solids, in the yard frame
	var bldg := n.find_child("StationBuilding", false, false) as Node3D
	if bldg:
		for cs: CollisionShape3D in bldg.find_children("*", "CollisionShape3D", true, false):
			var bs := cs.shape as BoxShape3D
			if bs == null or cs.get_parent().name == "HallBody":
				continue
			boxes.append(inv * _rel(n, cs) * AABB(-bs.size * 0.5, bs.size))
	var x0 := INF
	var x1 := -INF
	for b: AABB in boxes:
		if b.end.z > z - 0.5 and b.position.z < z + 30.0:
			x0 = minf(x0, b.position.x)
			x1 = maxf(x1, b.end.x)
	var runs: Array = []                      # [a, b] along the platform's back
	if x0 < x1:
		runs = [[Vector2(-FENCE_X, z), Vector2(x0, z)], [Vector2(x1, z), Vector2(FENCE_X, z)]]
		for e: Array in [[x0, 1.0], [x1, -1.0]]:
			var xe: float = e[0]
			var zmin := INF
			for b: AABB in boxes:
				var xi: float = xe + float(e[1]) * 0.3
				if xi > b.position.x and xi < b.end.x:
					zmin = minf(zmin, b.position.z)
			if zmin > z + 0.3 and zmin < z + 30.0:
				runs.append([Vector2(xe, z), Vector2(xe, zmin)])
	else:
		runs = [[Vector2(-FENCE_X, z), Vector2(FENCE_X, z)]]
	var xfs: Array = []
	for r: Array in runs:
		var a: Vector2 = r[0]
		var b2: Vector2 = r[1]
		var len := a.distance_to(b2)
		if len < 0.5:
			continue
		var cnt := maxi(1, int(ceil(len / 3.0)))
		var d := (b2 - a) / cnt
		for i in cnt:
			var p := a + d * i
			var q := p + d
			var y0 := _plat_ground(p.x)
			var y1 := _plat_ground(q.x)
			var x := Vector3(d.x, y1 - y0, d.y) / 3.0
			xfs.append(Transform3D(Basis(x, Vector3.UP, Vector3(d.x, 0, d.y).normalized().cross(Vector3.UP)), Vector3(p.x, y0, p.y)))
	_multimesh(yard, "PlatformFence", mesh, xfs, 320.0, false)
	var body := StaticBody3D.new()
	body.name = "PlatformFenceBody"
	yard.add_child(body)
	for fx: Transform3D in xfs:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var flat := Vector3(fx.basis.x.x, 0, fx.basis.x.z) * 3.0
		bs.size = Vector3(flat.length(), 2.2, 0.1)
		cs.shape = bs
		cs.transform = Transform3D(Basis(flat.normalized(), Vector3.UP, flat.normalized().cross(Vector3.UP)),
				fx.origin + fx.basis.x * 1.5 + Vector3(0, 1.1, 0))
		body.add_child(cs)

# Height of the ground along the platform's back: its top, down the ramps, then the yard floor.
static func _plat_ground(x: float) -> float:
	var half := RouteData.PLATFORM_LEN * 0.5
	var t := clampf((absf(x) - half) / 6.0, 0.0, 1.0)
	return lerpf(PLAT_Y, Terrain.FORMATION_Y, t)

# One thin solid along each fence bay, so nobody walks through the mesh.
static func _fence_body(yard: Node3D, xfs: Array) -> void:
	var body := StaticBody3D.new()
	body.name = "FenceBody"
	yard.add_child(body)
	for fx: Transform3D in xfs:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var len := fx.basis.x.length() * 2.5
		bs.size = Vector3(len, 2.4, 0.12)
		cs.shape = bs
		cs.transform = Transform3D(fx.basis.orthonormalized(), fx.origin + fx.basis.x * 1.25 + Vector3(0, 1.2, 0))
		body.add_child(cs)

static func _basis_along(t: Vector2) -> Basis:
	var x := Vector3(t.x, 0, t.y).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))

static func _model(parent: Node3D, key: String, xf: Transform3D, vis: float) -> Node3D:
	if StationModels.mesh(key) == null:
		var empty := Node3D.new()
		empty.transform = xf
		parent.add_child(empty)
		return empty
	return StationModels.place(parent, key, xf, vis)

static func _box_body(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = at
	body.add_child(cs)
	parent.add_child(body)

static func _multimesh(parent: Node3D, nm: String, mesh: Mesh, xfs: Array, vis: float, shadows: bool) -> void:
	if mesh == null or xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.visibility_range_end = vis
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Fence bays from a to b (2.5 m each, stretched to fit), on the yard floor.
static func _fence_run(xfs: Array, a: Vector2, b: Vector2) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var n := maxi(1, int(ceil(len / 2.5)))
	var d := (b - a) / n
	var x := Vector3(d.x, 0, d.y) / 2.5
	var z := x.normalized().cross(Vector3.UP)
	for i in n:
		var p := a + d * i
		xfs.append(Transform3D(Basis(x, Vector3.UP, z), Vector3(p.x, Terrain.FORMATION_Y, p.y)))

## Stone footing from the ground up to the floor of station buildings raised to platform level.
static func _footings(n: Node3D) -> void:
	for b: Node in n.find_children("StationBuilding", "Node3D", false, false):
		var bldg := b as Node3D
		if bldg.find_child("Footing", false, false) or bldg.position.y < 0.05:
			continue
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in bldg.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var a := (bldg.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb() \
					if mi.is_inside_tree() else (_rel(bldg, mi) * mi.mesh.get_aabb())
			if a.position.y > 0.6:
				continue          # only what stands on the ground: walls, wings
			box = a if first else box.merge(a)
			first = false
		if first:
			continue
		var h := bldg.position.y - Terrain.FORMATION_Y + 0.2
		var foot := MeshInstance3D.new()
		foot.name = "Footing"
		var bm := BoxMesh.new()
		bm.size = Vector3(box.size.x - 0.6, h, box.size.z - 0.6)
		foot.mesh = bm
		foot.material_override = Buildings.mat("stone")
		foot.position = Vector3(box.get_center().x, -h * 0.5 + 0.02, box.get_center().z)
		foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bldg.add_child(foot)

static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != root:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
