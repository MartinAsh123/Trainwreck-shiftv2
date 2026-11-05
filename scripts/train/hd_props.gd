extends RefCounted
## The HD prop models made in Blender (art_source/props_hd/, CC0 textures from ambientCG and
## Poly Haven) and exported to assets/models/hd_props/<name>.gltf. The car builders call place()
## first and fall back to their procedural stand-ins when a model is missing or `enabled` is off.

const DIR := "res://assets/models/hd_props/"

## Turn the models off to compare with (or fall back to) the procedural stand-ins.
static var enabled := true
static var _cache := {}

static func scene(model: String) -> PackedScene:
	if not enabled:
		return null
	if _cache.has(model):
		return _cache[model]
	var path := DIR + model + ".gltf"
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	_cache[model] = ps
	return ps

## Instances `model` under `parent` at `xform` (in the parent's space). Returns null if unavailable.
static func place(parent: Node, model: String, xform := Transform3D.IDENTITY, node_name := "") -> Node3D:
	var ps := scene(model)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.name = node_name if node_name != "" else model.to_pascal_case()
	n.transform = xform
	_shader_mats(n)
	parent.add_child(n)
	return n

static var _meshes := {}

## The model's (single, joined) mesh, for MultiMeshes - fences and other long runs of one part.
static func mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var ps := scene(model)
	var m: Mesh = null
	if ps:
		var n := ps.instantiate() as Node3D
		var found := n.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			m = (found[0] as MeshInstance3D).mesh
			for si in m.get_surface_count():
				var sm := _shader_mat(m.surface_get_material(si))
				if sm:
					m.surface_set_material(si, sm)
		n.free()
	_meshes[model] = m
	return m

static var _chainlink: ShaderMaterial

# Placeholder materials that the game draws with its own shader (matched by name).
static func _shader_mat(m: Material) -> Material:
	if m == null or m.resource_name != "chainlink":
		return null
	if _chainlink == null:
		_chainlink = ShaderMaterial.new()
		_chainlink.shader = preload("res://shaders/world/chainlink.gdshader")
	return _chainlink

static func _shader_mats(n: Node) -> void:
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var sm := _shader_mat(mi.mesh.surface_get_material(si))
			if sm:
				mi.set_surface_override_material(si, sm)

## Transform helper: position, Euler rotation (Godot order) and scale.
static func xf(pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos)

## Scales a placed model (origin at its bottom centre) so its mesh bounds become `size`.
static func fit(node: Node3D, size: Vector3) -> void:
	var b := local_aabb(node)
	if b.size.x <= 0.0 or b.size.y <= 0.0 or b.size.z <= 0.0:
		return
	node.scale = Vector3(size.x / b.size.x, size.y / b.size.y, size.z / b.size.z)

## Bounds of every mesh under `node`, in `node`'s own (unscaled) space.
static func local_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != node:
			t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var b := t * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

static var _tex_mats := {}

## A PBR material from the shared HD texture set (<key>_albedo / _normal / _orm in the models'
## textures folder), projected triplanar so procedural boxes need no UVs. `tile` = metres per tile.
static func textured(key: String, tile := 1.0, tint := Color.WHITE) -> StandardMaterial3D:
	var id := "%s|%s|%s" % [key, tile, tint]
	if _tex_mats.has(id):
		return _tex_mats[id]
	var base := DIR + "textures/" + key
	if not enabled or not ResourceLoader.exists(base + "_albedo.jpg"):
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "_albedo.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "_normal.jpg")
	m.roughness_texture = load(base + "_orm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.metallic = 1.0
	m.metallic_texture = m.roughness_texture
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.ao_enabled = true
	m.ao_texture = m.roughness_texture
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE / tile
	_tex_mats[id] = m
	return m

## Layout signature of a car body (length, width, windows, boarding door) - the HD body mouldings
## are exported per signature (body_layouts.json) and only used on a car whose layout matches.
static func body_signature(car: Node) -> String:
	var parts: PackedStringArray = []
	parts.append("%.2f/%.2f/%.2f/%.2f" % [car.get("length"), car.get("width"), car.get("window_width"), car.get("window_height")])
	parts.append("d%.2f" % car.call("_side_door_x"))
	for x in car.call("_window_xs"):
		var sides: Array = car.call("_window_sides", x)
		parts.append("%.2f:%s" % [x, ",".join(sides.map(func(s): return "%d" % int(s)))])
	return ";".join(parts)

static var _layouts := {}

## Model name of the HD body mouldings for this car, or "" when none matches its layout.
static func body_model(car: Node) -> String:
	if not enabled:
		return ""
	if _layouts.is_empty():
		var f := FileAccess.open(DIR + "body_layouts.json", FileAccess.READ)
		if f == null:
			return ""
		_layouts = JSON.parse_string(f.get_as_text())
	return _layouts.get(body_signature(car), "")
