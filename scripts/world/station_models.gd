class_name StationModels
extends RefCounted
## The station models from tools/blender/make_stations.py (after the user's reference photos): the
## stone country station and halt (Ellicott's Mills type) and the iron-and-glass train shed of the
## big towns. warm() loads them on the main thread and merges each into meshes whose materials are
## Buildings.mat() keys (matched by material name), so roofs carry the same snow as every other
## building; Buildings.station()/halt() on the worker threads only read the cache.
## Each model gives two meshes: "<name>" (body: walls, roofs; casts shadows) and "<name>_detail"
## (timber, iron and glass work; no shadows).

const DIR := "res://assets/models/stations/"
const MODELS := ["station_house", "halt_house", "shed_bay", "shed_end", "island_canopy", "goods_shed", "boxcar",
		"buffer_stop", "station_fence"]
const BODY_PARTS := ["Body", "Roof"]          # object names that cast shadows
const MAT_KEY := {"brick": "roof"}            # model material -> Buildings.mat key

static var _meshes := {}

static func warm() -> void:
	if not _meshes.is_empty():
		return
	for m: String in MODELS:
		var path: String = DIR + m + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		var body := ArrayMesh.new()
		var detail := ArrayMesh.new()
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			var target := body if String(mi.name) in BODY_PARTS else detail
			var xf := _xform_to(inst, mi)
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				for k in v.size():
					v[k] = xf * v[k]
				arr[Mesh.ARRAY_VERTEX] = v
				var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var nb := xf.basis.inverse().transposed()
				for k in nn.size():
					nn[k] = (nb * nn[k]).normalized()
				arr[Mesh.ARRAY_NORMAL] = nn
				arr[Mesh.ARRAY_TANGENT] = null
				target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				var src := mi.get_active_material(si)
				var key: String = src.resource_name if src else "wall"
				var mat: Material
				if m == "shed_end" and key == "glass_lit":
					mat = _shed_glass()
				elif key == "brick" and m in ["boxcar", "buffer_stop"]:
					mat = _wagon_red()
				elif key == "iron":
					mat = _iron()           # columns, trusses, brackets: no snow on thin vertical iron (read as birch bark)
				elif key == "glass_lit":
					mat = _lit_glass()      # Buildings' window_lit shader needs per-pane UVs these panes lack
				elif key == "glass_clear":
					mat = _clear_glass()    # the walk-in station: see into the lit booking hall
				else:
					mat = Buildings.mat(MAT_KEY.get(key, key))
				target.surface_set_material(target.get_surface_count() - 1, mat)
		inst.free()
		_meshes[m] = body
		_meshes[m + "_detail"] = detail

# Goods wagons and buffer-stop beams: oxide-red paint, weathered, a dusting of snow from the shader-less
# material is not needed (the wagon roof is a separate "roof_dark" surface).
static var _red: StandardMaterial3D

static func _wagon_red() -> Material:
	if _red == null:
		_red = StandardMaterial3D.new()
		_red.albedo_color = Color(0.3, 0.1, 0.07)
		_red.roughness = 0.8
		_red.cull_mode = BaseMaterial3D.CULL_DISABLED      # like Buildings.mat(): the model's faces aren't all wound alike
	return _red

# Painted cast and wrought iron (dark green-black), no snow shader.
static var _iron_mat: StandardMaterial3D

static func _iron() -> Material:
	if _iron_mat == null:
		_iron_mat = StandardMaterial3D.new()
		_iron_mat.albedo_color = Color(0.035, 0.045, 0.04)
		_iron_mat.roughness = 0.5
		_iron_mat.metallic = 0.3
		_iron_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _iron_mat

# Lit windows of the station buildings: warm lamplight behind old glass.
static var _lit: StandardMaterial3D

static func _lit_glass() -> Material:
	if _lit == null:
		_lit = StandardMaterial3D.new()
		_lit.albedo_color = Color(0.2, 0.12, 0.05)
		_lit.roughness = 0.2
		_lit.emission_enabled = true
		_lit.emission = Color(1.0, 0.58, 0.24)
		_lit.emission_energy_multiplier = 0.6
		_lit.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _lit

# Clear window glass of the station one can walk into.
static var _clear: StandardMaterial3D

static func _clear_glass() -> Material:
	if _clear == null:
		_clear = StandardMaterial3D.new()
		_clear.albedo_color = Color(0.55, 0.62, 0.66, 0.18)
		_clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_clear.roughness = 0.05
		_clear.metallic_specular = 0.8
		_clear.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _clear

# The shed's end lunettes: old, slightly grimy glass with the hall's lamplight behind it.
static func _shed_glass() -> Material:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.06, 0.055, 0.05)
	g.roughness = 0.25
	g.emission_enabled = true
	g.emission = Color(1.0, 0.72, 0.42)
	g.emission_energy_multiplier = 0.06
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	return g

static func _xform_to(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != root:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

static func ready() -> bool:
	return not _meshes.is_empty()

static func mesh(key: String) -> Mesh:
	return _meshes.get(key)

## A MeshInstance pair (body with shadows, details without) for model `key` under `parent`.
static func place(parent: Node3D, key: String, xf: Transform3D, vis_detail := 260.0) -> Node3D:
	var n := Node3D.new()
	n.name = key.to_pascal_case()
	n.transform = xf
	parent.add_child(n)
	var b := MeshInstance3D.new()
	b.name = "Body"
	b.mesh = mesh(key)
	n.add_child(b)
	var d := MeshInstance3D.new()
	d.name = "Detail"
	d.mesh = mesh(key + "_detail")
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.visibility_range_end = vis_detail
	n.add_child(d)
	return n
