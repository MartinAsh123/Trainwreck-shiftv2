class_name SceneryMeshes
extends RefCounted
## Shared procedural meshes and materials for the landscape: snowy pines and spruces, bare
## birches, rocks, sleepers, ballast, rails, telegraph poles. Built once and cached (static), so the
## streaming chunks only place instances. Every mesh's vertex alpha is "snow may lie here" (see
## snow_cover.gdshader).

const SNOW_COVER := preload("res://shaders/world/snow_cover.gdshader")
const SNOW_GROUND := preload("res://shaders/world/snow_ground.gdshader")

## HD landscape models (art_source/world_hd, built in Blender from CC0 scans). Each key the
## scenery asks for maps to a model; without the model the procedural mesh below is used.
const HD_DIR := "res://assets/models/hd_world/"
const HD_TEX := "res://assets/models/hd_world/textures/"
const HD_MODELS := {
	"pine_a": "spruce_a", "pine_b": "spruce_b", "spruce": "fir_c", "scots": "scots_pine", "birch": "birch",
	"pine_a_lod": "spruce_a_lod", "pine_b_lod": "spruce_b_lod", "spruce_lod": "fir_c_lod", "scots_lod": "scots_pine_lod",
	"pine_a_lod2": "spruce_a_lod2", "pine_b_lod2": "spruce_b_lod2",
	"sleeper": "sleeper", "pole": "pole", "rock_a": "rock_a", "rock_b": "rock_b", "stump": "stump",
	"bench": "bench", "lamp_post": "lamp_post", "fence_lineside": "fence_lineside",
}
const FOLIAGE := preload("res://shaders/world/foliage.gdshader")
const BARK := preload("res://shaders/world/bark.gdshader")
const SNOW_LUMP := preload("res://shaders/world/snow_lump.gdshader")
const NEEDLES_FAR := preload("res://shaders/world/needles_far.gdshader")
const WORLD_PBR := preload("res://shaders/world/world_pbr.gdshader")
const RAIL := preload("res://shaders/world/rail.gdshader")
const BALLAST := preload("res://shaders/world/ballast.gdshader")

static var hd_enabled := true
static var _cache := {}
static var _mutex := Mutex.new()
static var _wind_mats: Array[ShaderMaterial] = []

## Loads every HD model on the calling (main) thread, so the worker threads only read the cache.
static func warm() -> void:
	for key: String in HD_MODELS:
		get_mesh(key)

static func get_mesh(key: String) -> Mesh:
	_mutex.lock()
	var m: Mesh = _cache.get(key)
	if m == null and hd_enabled and HD_MODELS.has(key):
		m = _hd_mesh(HD_MODELS[key])
	if m == null:
		match key:
			"pine_a": m = _pine(8, 11, 0.30, 0.34, 0.0)
			"pine_b": m = _pine(10, 12, 0.24, 0.30, 0.5)
			"spruce": m = _pine(12, 10, 0.19, 0.22, 1.0)
			"pine_lo", "pine_a_lod", "pine_b_lod", "spruce_lod", "scots_lod", "pine_a_lod2", "pine_b_lod2": m = _pine(5, 7, 0.28, 0.32, 0.2)
			"scots": m = _pine(8, 11, 0.30, 0.34, 0.0)
			"birch": m = _birch()
			"rock_a": m = _rock(1)
			"rock_b": m = _rock(2)
			"sleeper": m = _sleeper()
			"pole": m = _pole()
			"rail": m = _rail(800.0)
		_cache[key] = m
	_mutex.unlock()
	return m

static func material(key: String) -> Material:
	_mutex.lock()
	var m: Material = _cache.get("mat_" + key)
	if m == null:
		var sm := ShaderMaterial.new()
		sm.shader = SNOW_COVER
		match key:
			"needles":
				sm.set_shader_parameter("base", Color(0.13, 0.2, 0.14))
				sm.set_shader_parameter("snow_amount", 0.72)
				sm.set_shader_parameter("grain", 3)
				sm.set_shader_parameter("snow_sharp", 0.22)
			"bark":
				sm.set_shader_parameter("base", Color(0.24, 0.18, 0.14))
				sm.set_shader_parameter("snow_amount", 0.3)
				sm.set_shader_parameter("grain", 2)
			"birch":
				sm.set_shader_parameter("base", Color(0.82, 0.8, 0.76))
				sm.set_shader_parameter("snow_amount", 0.35)
				sm.set_shader_parameter("grain", 2)
				sm.set_shader_parameter("grain_scale", 2.5)
			"rock":
				sm.set_shader_parameter("base", Color(0.36, 0.35, 0.34))
				sm.set_shader_parameter("snow_amount", 0.8)
			"sleeper":
				sm.set_shader_parameter("base", Color(0.2, 0.15, 0.11))
				sm.set_shader_parameter("snow_amount", 0.45)
				sm.set_shader_parameter("grain", 1)
				sm.set_shader_parameter("grain_scale", 2.0)
			"ballast":
				sm.set_shader_parameter("base", Color(0.33, 0.31, 0.29))
				sm.set_shader_parameter("snow_amount", 0.5)
				sm.set_shader_parameter("grain", 3)
				sm.set_shader_parameter("grain_scale", 3.0)
				sm.set_shader_parameter("snow_sharp", 0.35)
			"pole":
				sm.set_shader_parameter("base", Color(0.26, 0.2, 0.15))
				sm.set_shader_parameter("snow_amount", 0.5)
				sm.set_shader_parameter("grain", 2)
			"ground":
				sm.shader = SNOW_GROUND
				if hd_enabled and ResourceLoader.exists(HD_TEX + "snow_albedo.jpg"):
					sm.set_shader_parameter("use_textures", true)
					sm.set_shader_parameter("snow_albedo", _tex("snow_albedo.jpg"))
					sm.set_shader_parameter("snow_normal", _tex("snow_normal.jpg"))
					sm.set_shader_parameter("trodden_albedo", _tex("snow_trodden_albedo.jpg"))
					sm.set_shader_parameter("trodden_normal", _tex("snow_trodden_normal.jpg"))
					sm.set_shader_parameter("rock_albedo", _tex("rock_albedo.jpg"))
					sm.set_shader_parameter("rock_normal", _tex("rock_normal.jpg"))
			"rail":
				if hd_enabled and ResourceLoader.exists(HD_TEX + "rail_rust_albedo.jpg"):
					sm.shader = RAIL
					sm.set_shader_parameter("rust_albedo", _tex("rail_rust_albedo.jpg"))
					sm.set_shader_parameter("rust_normal", _tex("rail_rust_normal.jpg"))
					sm.set_shader_parameter("rust_orm", _tex("rail_rust_orm.jpg"))
				else:
					var rm := StandardMaterial3D.new()
					rm.albedo_color = Color(0.36, 0.33, 0.31)
					rm.metallic = 0.85
					rm.roughness = 0.42
					m = rm
			"ballast_hd":
				sm.shader = BALLAST
				sm.set_shader_parameter("ballast_albedo", _tex("ballast_albedo.jpg"))
				sm.set_shader_parameter("ballast_normal", _tex("ballast_normal.jpg"))
				sm.set_shader_parameter("ballast_orm", _tex("ballast_orm.jpg"))
				sm.set_shader_parameter("snow_albedo", _tex("snow_albedo.jpg"))
				sm.set_shader_parameter("snow_normal", _tex("snow_normal.jpg"))
			"wire":
				var wm := StandardMaterial3D.new()
				wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				wm.albedo_color = Color(0.05, 0.05, 0.06)
				m = wm
		if m == null:
			m = sm
		_cache["mat_" + key] = m
	_mutex.unlock()
	return m

# ————— HD models —————

# The model's mesh with the landscape shaders in place of its placeholder materials (matched by
# material name). Called with the mutex held.
static func _hd_mesh(model: String) -> Mesh:
	var path := HD_DIR + model + ".gltf"
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
	inst.free()
	if mesh == null:
		return null
	for i in mesh.get_surface_count():
		var old := mesh.surface_get_material(i)
		var nm := old.resource_name if old else ""
		var hm := _hd_material(nm)
		if hm == null and old is StandardMaterial3D:
			hm = _pbr_from(old as StandardMaterial3D)
		if hm:
			mesh.surface_set_material(i, hm)
	return mesh

static func _tex(name: String) -> Texture2D:
	var p := HD_TEX + name
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

static func _hd_material(name: String) -> Material:
	var key := "hdmat_" + name
	if _cache.has(key):
		return _cache[key]
	var sm := ShaderMaterial.new()
	match name:
		"twig_fir", "twig_pine", "twig_birch":
			sm.shader = FOLIAGE
			var base: String = name.trim_prefix("twig_")
			sm.set_shader_parameter("albedo_tex", _tex(base + "_twig_albedo.png"))
			if base != "birch":
				sm.set_shader_parameter("normal_tex", _tex(base + "_twig_normal.jpg"))
			else:
				sm.set_shader_parameter("snow_amount", 0.35)
				sm.set_shader_parameter("alpha_cut", 0.35)
				sm.set_shader_parameter("normal_k", 0.0)
		"bark_fir", "bark_pine", "bark_birch":
			sm.shader = BARK
			var tex: String = {"bark_fir": "fir_bark", "bark_pine": "pine_bark", "bark_birch": "birch_bark"}[name]
			sm.set_shader_parameter("albedo_tex", _tex(tex + "_albedo.jpg"))
			sm.set_shader_parameter("normal_tex", _tex(tex + "_normal.jpg"))
			sm.set_shader_parameter("orm_tex", _tex(tex + "_orm.jpg"))
			if name == "bark_birch":
				sm.set_shader_parameter("snow_amount", 0.5)
		"snow_lump":
			sm.shader = SNOW_LUMP
			sm.set_shader_parameter("snow_albedo", _tex("snow_albedo.jpg"))
			sm.set_shader_parameter("snow_normal", _tex("snow_normal.jpg"))
			sm.set_shader_parameter("tile", 1.2)
		"needles_mass":
			sm.shader = NEEDLES_FAR
			sm.set_shader_parameter("albedo_tex", _tex("needles_mass_albedo.jpg"))
			sm.set_shader_parameter("normal_tex", _tex("needles_mass_normal.jpg"))
		"sleeper_wood", "pole_wood", "track_steel":
			sm.shader = WORLD_PBR
			var tx: String = "rail_rust" if name == "track_steel" else "wood_weathered"
			sm.set_shader_parameter("albedo_tex", _tex(tx + "_albedo.jpg"))
			sm.set_shader_parameter("normal_tex", _tex(tx + "_normal.jpg"))
			sm.set_shader_parameter("orm_tex", _tex(tx + "_orm.jpg"))
			_snow_params(sm)
			match name:
				"sleeper_wood":
					sm.set_shader_parameter("tint", Color(0.78, 0.7, 0.62))
					sm.set_shader_parameter("snow_amount", 0.5)
				"pole_wood":
					sm.set_shader_parameter("tint", Color(0.62, 0.5, 0.4))
					sm.set_shader_parameter("snow_amount", 0.55)
				"track_steel":
					sm.set_shader_parameter("tint", Color(0.7, 0.6, 0.55))
					sm.set_shader_parameter("metallic_k", 1.0)
					sm.set_shader_parameter("snow_amount", 0.35)
		"bench_wood":
			sm.shader = WORLD_PBR
			sm.set_shader_parameter("albedo_tex", _tex("planks_albedo.jpg"))
			sm.set_shader_parameter("normal_tex", _tex("planks_normal.jpg"))
			sm.set_shader_parameter("orm_tex", _tex("planks_orm.jpg"))
			sm.set_shader_parameter("tint", Color(0.85, 0.7, 0.55))
			sm.set_shader_parameter("snow_amount", 0.5)
			_snow_params(sm)
		"chainlink":
			sm.shader = preload("res://shaders/world/chainlink.gdshader")
		"galv_steel":
			sm.shader = WORLD_PBR
			_snow_params(sm)
			sm.set_shader_parameter("tint", Color(0.5, 0.52, 0.53))
			sm.set_shader_parameter("metallic_k", 1.0)
			sm.set_shader_parameter("roughness_k", 0.4)
			sm.set_shader_parameter("snow_amount", 0.4)
		"insulator", "cast_iron", "lamp_glass":
			sm.shader = WORLD_PBR
			_snow_params(sm)
			match name:
				"insulator":
					sm.set_shader_parameter("tint", Color(0.3, 0.48, 0.44))
					sm.set_shader_parameter("roughness_k", 0.1)
					sm.set_shader_parameter("snow_amount", 0.3)
				"cast_iron":
					sm.set_shader_parameter("tint", Color(0.05, 0.065, 0.06))
					sm.set_shader_parameter("roughness_k", 0.45)
					sm.set_shader_parameter("snow_amount", 0.55)
				"lamp_glass":
					sm.set_shader_parameter("tint", Color(1.0, 0.85, 0.6))
					sm.set_shader_parameter("snow_amount", 0.0)
					sm.set_shader_parameter("emission_col", Color(1.0, 0.78, 0.45))
					sm.set_shader_parameter("emission_k", 2.2)
		_:
			_cache[key] = null
			return null
	_cache[key] = sm
	_wind_mats.append(sm)
	return sm

static func _snow_params(sm: ShaderMaterial) -> void:
	sm.set_shader_parameter("snow_albedo", _tex("snow_albedo.jpg"))
	sm.set_shader_parameter("snow_normal", _tex("snow_normal.jpg"))

# A scanned (Poly Haven) model's own textures under the snowy world shader.
static func _pbr_from(std: StandardMaterial3D) -> ShaderMaterial:
	var key := "hdpbr_" + str(std.get_instance_id())
	if _cache.has(key):
		return _cache[key]
	var sm := ShaderMaterial.new()
	sm.shader = WORLD_PBR
	sm.set_shader_parameter("albedo_tex", std.albedo_texture)
	if std.normal_enabled:
		sm.set_shader_parameter("normal_tex", std.normal_texture)
	# glTF metallic-roughness: G roughness, B metal; occlusion in R (same ORM packing).
	if std.roughness_texture:
		sm.set_shader_parameter("orm_tex", std.roughness_texture)
	sm.set_shader_parameter("tint", Color(std.albedo_color.r, std.albedo_color.g, std.albedo_color.b))
	_snow_params(sm)
	_cache[key] = sm
	return sm

## The weather's wind for every swaying landscape material (call from the main thread).
static func set_wind(w: Vector3, strength: float) -> void:
	for sm in _wind_mats:
		sm.set_shader_parameter("wind", w)
		sm.set_shader_parameter("wind_strength", strength)

# ————— trees —————

# A snowy conifer, 1 m tall (scale per instance): a trunk and `tiers` drooping, ragged skirts of
# branches that shrink toward the top. Surface 0 = trunk (bark), surface 1 = foliage (needles).
static func _pine(tiers: int, spokes: int, base_r: float, top_r: float, narrow: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = tiers * 131 + spokes
	var mesh := ArrayMesh.new()
	# Trunk.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, Vector3.ZERO, 0.028, 0.008, 0.95, 7, Color(1, 1, 1, 0.2))
	st.generate_normals()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	# Foliage tiers: bottom tier at 18 % height; each skirt goes from its rim up to a collar on the
	# trunk; tips droop and alternate long/short.
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := 0.16
	for t in tiers:
		var k := float(t) / float(tiers)
		var y_rim := lerpf(y0, 0.9, pow(k, 0.92))
		var r := lerpf(base_r, 0.035, pow(k, lerpf(0.9, 1.25, narrow))) * (0.92 + rng.randf() * 0.16)
		var tier_h := lerpf(0.2, 0.13, k) * (1.0 + narrow * 0.15)
		var collar := Vector3(0, y_rim + tier_h, 0)
		var rot := rng.randf() * TAU
		var rim: Array[Vector3] = []
		var n := spokes * 2
		for i in n:
			var a := rot + TAU * i / n
			var tip := i % 2 == 0
			var rr := r * (1.0 if tip else 0.62) * (0.88 + rng.randf() * 0.24)
			var droop := (0.05 if tip else 0.0) * (1.0 - k * 0.5) + rng.randf() * 0.015
			rim.append(Vector3(cos(a) * rr, y_rim - droop, sin(a) * rr))
		var tint := Color(0.92 + rng.randf() * 0.16, 0.92 + rng.randf() * 0.16, 0.9 + rng.randf() * 0.12, 1.0)
		for i in n:
			var a2 := rim[i]
			var b2 := rim[(i + 1) % n]
			# Upper surface (snow may settle).
			st_tri(sf, collar, b2, a2, tint)
			# Underside: from the rim in toward the trunk a little higher; never snowy.
			var under := Vector3(0, y_rim + tier_h * 0.25, 0)
			st_tri(sf, under, a2, b2, Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 0.0))
	# Leader at the top.
	var tip_top := Vector3(0, 1.0, 0)
	var lr := 0.03
	for i in 6:
		var a3 := TAU * i / 6.0
		var b3 := TAU * (i + 1) / 6.0
		st_tri(sf, tip_top, Vector3(cos(b3) * lr, 0.9, sin(b3) * lr), Vector3(cos(a3) * lr, 0.9, sin(a3) * lr), Color(1, 1, 1, 1))
	sf.generate_normals()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sf.commit_to_arrays())
	mesh.surface_set_material(0, material("bark"))
	mesh.surface_set_material(1, material("needles"))
	return mesh

static func st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)

static func _cylinder(st: SurfaceTool, base: Vector3, r0: float, r1: float, h: float, segs: int, col: Color) -> void:
	for i in segs:
		var a := TAU * i / segs
		var b := TAU * (i + 1) / segs
		var p0 := base + Vector3(cos(a) * r0, 0, sin(a) * r0)
		var p1 := base + Vector3(cos(b) * r0, 0, sin(b) * r0)
		var q0 := base + Vector3(cos(a) * r1, h, sin(a) * r1)
		var q1 := base + Vector3(cos(b) * r1, h, sin(b) * r1)
		st_tri(st, p0, q0, p1, col)
		st_tri(st, p1, q0, q1, col)

# Bare birch, 1 m tall: white trunk forking into a few thin branches.
static func _birch() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, Vector3.ZERO, 0.02, 0.012, 0.55, 7, Color(1, 1, 1, 0.3))
	for i in 9:
		var a := rng.randf() * TAU
		var y := 0.35 + rng.randf() * 0.25
		var len := 0.25 + rng.randf() * 0.25
		var dir := Vector3(cos(a) * 0.55, 0.85, sin(a) * 0.55).normalized()
		_branch(st, Vector3(0, y, 0), dir, len, 0.008, 6)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material("birch"))
	return mesh

static func _branch(st: SurfaceTool, from: Vector3, dir: Vector3, len: float, r: float, segs: int) -> void:
	var to := from + dir * len
	var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	for i in segs:
		var a := TAU * i / segs
		var b := TAU * (i + 1) / segs
		var oa := (side * cos(a) + up * sin(a))
		var ob := (side * cos(b) + up * sin(b))
		st_tri(st, from + oa * r, to + oa * r * 0.3, from + ob * r, Color(1, 1, 1, 0.3))
		st_tri(st, from + ob * r, to + oa * r * 0.3, to + ob * r * 0.3, Color(1, 1, 1, 0.3))

# ————— rocks —————

static func _rock(variant: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 400 + variant
	noise.frequency = 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sm := SphereMesh.new()
	sm.radial_segments = 14
	sm.rings = 8
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + noise.get_noise_3dv(v) * 0.45
		var p := v * d * Vector3(1.0, 0.62 if variant == 1 else 0.85, 0.9)
		# Flat underside sunk into the ground.
		p.y = maxf(p.y, -0.15)
		out[i] = p
	for i in range(0, idx.size(), 3):
		for j in 3:
			st.set_color(Color(1, 1, 1, 1))
			st.add_vertex(out[idx[i + j]])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material("rock"))
	return mesh

# ————— track —————

# One sleeper (timber), across the track (Z), top at y = 0.
static func _sleeper() -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.15, 2.6)
	var st := SurfaceTool.new()
	st.create_from(bm, 0)
	var arr := st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y -= 0.075
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, material("sleeper"))
	return mesh

# Both rails of the line, `length` metres along X centred on the origin: flat-bottom rail
# profile (foot, web, rounded head), heads 1.435 m apart, rail top at y = 0.15. UV.x = metres along,
# UV.y = height up the profile (0 foot .. 1 head top), for rail.gdshader. Flat normals per face.
static func _rail(length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 0.7175 + 0.036
	var prof: Array[Vector2] = [Vector2(-0.065, 0.0), Vector2(0.065, 0.0), Vector2(0.065, 0.01), Vector2(0.03, 0.022),
			Vector2(0.011, 0.034), Vector2(0.008, 0.1), Vector2(0.018, 0.108), Vector2(0.034, 0.113), Vector2(0.036, 0.142),
			Vector2(0.03, 0.149), Vector2(0.012, 0.152), Vector2(-0.012, 0.152), Vector2(-0.03, 0.149), Vector2(-0.036, 0.142),
			Vector2(-0.034, 0.113), Vector2(-0.018, 0.108), Vector2(-0.008, 0.1), Vector2(-0.011, 0.034), Vector2(-0.03, 0.022),
			Vector2(-0.065, 0.01)]
	var x0 := -length * 0.5
	var x1 := length * 0.5
	for zs: float in [-1.0, 1.0]:
		var zc: float = zs * half
		for i in prof.size():
			if i == 0:
				continue          # the underside of the foot is never seen
			var a := prof[i]
			var b := prof[(i + 1) % prof.size()]
			var e := b - a
			var n := Vector3(0, -e.x, e.y).normalized()       # outward (the profile runs anticlockwise in z/y)
			var pa0 := Vector3(x0, a.y, zc + a.x)
			var pb0 := Vector3(x0, b.y, zc + b.x)
			var pa1 := Vector3(x1, a.y, zc + a.x)
			var pb1 := Vector3(x1, b.y, zc + b.x)
			var va := a.y / 0.152
			var vb := b.y / 0.152
			for q: Array in [[pa0, x0, va], [pb0, x0, vb], [pa1, x1, va], [pb0, x0, vb], [pb1, x1, vb], [pa1, x1, va]]:
				st.set_normal(n)
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material("rail"))
	return mesh

## Ballast bed from x0 to x1 (local X), under the sleepers: crib level with the sleeper tops,
## shoulders sloping down to the formation. UV = route metres (s = s0 - x, z) for ballast.gdshader.
static func ballast(x0: float, x1: float, s0: float = 0.0) -> ArrayMesh:
	var f := Terrain.FORMATION_Y
	var prof: Array[Vector2] = [Vector2(-3.1, f - 0.04), Vector2(-2.45, f + 0.12), Vector2(-1.85, -0.05), Vector2(-1.45, -0.03),
			Vector2(-0.6, -0.035), Vector2(0.0, -0.04), Vector2(0.6, -0.035), Vector2(1.45, -0.03), Vector2(1.85, -0.05),
			Vector2(2.45, f + 0.12), Vector2(3.1, f - 0.04)]
	var hd := hd_enabled and ResourceLoader.exists(HD_TEX + "ballast_albedo.jpg")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := int(ceil(absf(x1 - x0) / 10.0))
	for k in steps:
		var xa := lerpf(x0, x1, float(k) / steps)
		var xb := lerpf(x0, x1, float(k + 1) / steps)
		for i in prof.size() - 1:
			var a := prof[i]
			var b := prof[i + 1]
			var quad := [Vector3(xa, a.y, a.x), Vector3(xa, b.y, b.x), Vector3(xb, a.y, a.x),
					Vector3(xb, a.y, a.x), Vector3(xa, b.y, b.x), Vector3(xb, b.y, b.x)]
			for v: Vector3 in quad:
				st.set_uv(Vector2(s0 - v.x, v.z))
				st.set_color(Color.WHITE)
				st.add_vertex(v)
	st.generate_normals()
	if hd:
		st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material("ballast_hd" if hd else "ballast"))
	return mesh

# ————— telegraph pole —————

const POLE_H := 7.2
## Insulator positions (local) where the wires are tied.
const WIRE_POINTS: Array[Vector3] = [Vector3(0.11, 6.95, -0.62), Vector3(0.11, 6.95, -0.22), Vector3(0.11, 6.95, 0.22),
		Vector3(0.11, 6.95, 0.62), Vector3(0.11, 6.35, -0.45), Vector3(0.11, 6.35, 0.45)]

static func _pole() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, Vector3(0, -0.3, 0), 0.12, 0.09, POLE_H + 0.3, 8, Color(1, 1, 1, 0.6))
	# Two crossarms (along Z, across the line) with insulators.
	for arm in [[6.85, 0.75], [6.25, 0.55]]:
		var ay: float = arm[0]
		var aw: float = arm[1]
		_box(st, Vector3(0, ay, 0), Vector3(0.09, 0.09, aw * 2.0), Color(1, 1, 1, 1))
	var ins := Color(0.85, 0.85, 0.8, 0.0)
	for p: Vector3 in WIRE_POINTS:
		_cylinder(st, p - Vector3(0, 0.12, 0), 0.025, 0.02, 0.12, 6, ins)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, material("pole"))
	return mesh

static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(c + Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]
	for f: Array in faces:
		st_tri(st, corners[f[0]], corners[f[1]], corners[f[2]], col)
		st_tri(st, corners[f[0]], corners[f[2]], corners[f[3]], col)
