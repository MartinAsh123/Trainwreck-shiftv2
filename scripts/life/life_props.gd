class_name LifeProps
extends RefCounted
## Meshes, scenes and materials for the life of the valley (roads, fields, signs, cars). Loaded once
## on the main thread by warm(); the chunk builders on the worker threads only read the caches.

const DIR := "res://assets/models/life/"
const PROPS := ["haystack_cone", "haystack_loaf", "fence", "barrier_post", "barrier_arm", "cross_andrew",
		"sign_gate", "sign_train", "sign_curve", "sign_crossroads", "signpost", "village_sign", "km_stone",
		"hanging_sign", "apple_tree", "sign_round"]
const CARS := ["car_sedan", "car_small", "truck"]
const ROAD := preload("res://shaders/life/road.gdshader")
const FIELD := preload("res://shaders/life/field.gdshader")

static var _meshes := {}
static var _scenes := {}
static var _mats := {}

static func warm() -> void:
	if not _meshes.is_empty():
		return
	for p: String in PROPS:
		var path: String = DIR + p + ".glb"
		if ResourceLoader.exists(path):
			_meshes[p] = _merge(load(path) as PackedScene)
	for c: String in CARS:
		var path: String = DIR + c + ".glb"
		if ResourceLoader.exists(path):
			_scenes[c] = load(path)
	var road := ShaderMaterial.new()
	road.shader = ROAD
	_mats["road"] = road
	var street := ShaderMaterial.new()
	street.shader = ROAD
	street.set_shader_parameter("cobbles", 1.0)
	street.set_shader_parameter("half_width", 5.0)       # TownPlan: 10 m between the house fronts
	_mats["street_town"] = street
	var square := ShaderMaterial.new()
	square.shader = ROAD
	square.set_shader_parameter("cobbles", 1.0)
	square.set_shader_parameter("half_width", 1000.0)
	_mats["square"] = square
	var lane := ShaderMaterial.new()
	lane.shader = ROAD
	lane.set_shader_parameter("cobbles", 0.0)
	lane.set_shader_parameter("packed_col", Color(0.7, 0.71, 0.74))
	_mats["street_village"] = lane
	var plough := ShaderMaterial.new()
	plough.shader = FIELD
	_mats["plough"] = plough
	var stubble := ShaderMaterial.new()
	stubble.shader = FIELD
	stubble.set_shader_parameter("stubble", 1.0)
	stubble.set_shader_parameter("furrow", 0.35)
	_mats["stubble"] = stubble
	var deck := StandardMaterial3D.new()
	deck.albedo_color = Color(0.2, 0.16, 0.12)
	deck.roughness = 0.85
	_mats["deck"] = deck
	for key: String in ["fascia_green", "fascia_red", "fascia_blue", "fascia_brown"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = {"fascia_green": Color(0.05, 0.16, 0.1), "fascia_red": Color(0.25, 0.04, 0.03),
				"fascia_blue": Color(0.04, 0.07, 0.18), "fascia_brown": Color(0.16, 0.09, 0.05)}[key]
		m.roughness = 0.45
		_mats[key] = m
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.85, 0.6)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.78, 0.45)
	glow.emission_energy_multiplier = 4.0
	_mats["glow"] = glow

static func mesh(key: String) -> Mesh:
	return _meshes.get(key)

static func car(key: String) -> PackedScene:
	return _scenes.get(key)

static func material(key: String) -> Material:
	return _mats.get(key)

# One mesh (a surface per material) from every MeshInstance3D in an imported scene, in the
# scene root's space, for MultiMesh use.
static func _merge(ps: PackedScene) -> ArrayMesh:
	var root := ps.instantiate() as Node3D
	var out := ArrayMesh.new()
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		for ch in n.get_children():
			if ch is Node3D:
				stack.append([ch, xf * (ch as Node3D).transform])
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var nb := xf.basis.inverse().transposed()
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for k in v.size():
				v[k] = xf * v[k]
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for k in nn.size():
					nn[k] = (nb * nn[k]).normalized()
				arr[Mesh.ARRAY_NORMAL] = nn
			arr[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var m := mi.get_active_material(si)
			out.surface_set_material(out.get_surface_count() - 1, m)
	root.free()
	return out
