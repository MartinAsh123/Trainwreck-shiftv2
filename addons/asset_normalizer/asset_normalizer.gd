# asset_normalizer.gd
# Turns a raw imported model (e.g. from res://TripoModels) into a clean prefab scene:
# front faces -Z, real-world scale, pivot where the slot expects it, optional collision.
@tool
class_name AssetNormalizer
extends RefCounted

enum Forward { POS_Z, NEG_Z, POS_X, NEG_X }
enum FitAxis { WIDTH, HEIGHT, DEPTH, LONGEST }
enum Pivot { BOTTOM, TOP, CENTER }
enum Collision { NONE, BOX, CONVEX, TRIMESH }

const MODEL_EXTENSIONS: Array[String] = ["glb", "gltf", "fbx", "obj"]

# Slot presets. `slot` is the PassengerCar property the prefab plugs into.
# `max_width` / `max_depth` are soft limits checked in the report (0 = unchecked).
const PRESETS := {
	"seat_double": {
		"label": "Seat (double)", "slot": "seat_scene", "folder": "res://assets/props/seats",
		"fit_axis": FitAxis.WIDTH, "fit_size": 1.1, "pivot": Pivot.BOTTOM,
		"collision": Collision.CONVEX, "tri_budget": 14000, "max_width": 1.1, "max_depth": 0.7,
	},
	"table": {
		"label": "Bay table", "slot": "table_scene", "folder": "res://assets/props/tables",
		"fit_axis": FitAxis.HEIGHT, "fit_size": 0.68, "pivot": Pivot.BOTTOM,
		"collision": Collision.BOX, "tri_budget": 4000, "max_width": 0.75, "max_depth": 0.6,
	},
	"lamp": {
		"label": "Ceiling lamp", "slot": "lamp_scene", "folder": "res://assets/props/lamps",
		"fit_axis": FitAxis.LONGEST, "fit_size": 0.35, "pivot": Pivot.TOP,
		"collision": Collision.NONE, "tri_budget": 3000, "max_width": 0.45, "max_depth": 0.45,
	},
	"rack": {
		"label": "Luggage rack", "slot": "rack_scene", "folder": "res://assets/props/racks",
		"fit_axis": FitAxis.WIDTH, "fit_size": 1.8, "pivot": Pivot.CENTER,
		"collision": Collision.NONE, "tri_budget": 4000, "max_width": 0.0, "max_depth": 0.45,
	},
	"side_door": {
		"label": "Side door", "slot": "side_door_scene", "folder": "res://assets/props/doors",
		"fit_axis": FitAxis.HEIGHT, "fit_size": 2.0, "pivot": Pivot.BOTTOM,
		"collision": Collision.BOX, "tri_budget": 6000, "max_width": 0.85, "max_depth": 0.1,
	},
	"inner_door": {
		"label": "Saloon door", "slot": "inner_door_scene", "folder": "res://assets/props/doors",
		"fit_axis": FitAxis.HEIGHT, "fit_size": 2.0, "pivot": Pivot.BOTTOM,
		"collision": Collision.NONE, "tri_budget": 6000, "max_width": 0.75, "max_depth": 0.15,
	},
	"end_door": {
		"label": "Gangway door", "slot": "end_door_scene", "folder": "res://assets/props/doors",
		"fit_axis": FitAxis.HEIGHT, "fit_size": 2.0, "pivot": Pivot.BOTTOM,
		"collision": Collision.NONE, "tri_budget": 6000, "max_width": 0.95, "max_depth": 0.15,
	},
	"toilet_door": {
		"label": "Toilet door", "slot": "toilet_door_scene", "folder": "res://assets/props/doors",
		"fit_axis": FitAxis.HEIGHT, "fit_size": 2.0, "pivot": Pivot.BOTTOM,
		"collision": Collision.NONE, "tri_budget": 4000, "max_width": 0.75, "max_depth": 0.15,
	},
	"toilet": {
		"label": "Toilet bowl", "slot": "toilet_scene", "folder": "res://assets/props/toilet",
		"fit_axis": FitAxis.HEIGHT, "fit_size": 0.48, "pivot": Pivot.BOTTOM,
		"collision": Collision.CONVEX, "tri_budget": 6000, "max_width": 0.5, "max_depth": 0.65,
	},
	"sink": {
		"label": "Sink", "slot": "sink_scene", "folder": "res://assets/props/toilet",
		"fit_axis": FitAxis.WIDTH, "fit_size": 0.5, "pivot": Pivot.BOTTOM,
		"collision": Collision.CONVEX, "tri_budget": 5000, "max_width": 0.6, "max_depth": 0.5,
	},
	"mirror": {
		"label": "Wall mirror", "slot": "mirror_scene", "folder": "res://assets/props/toilet",
		"fit_axis": FitAxis.WIDTH, "fit_size": 0.45, "pivot": Pivot.CENTER,
		"collision": Collision.NONE, "tri_budget": 3000, "max_width": 0.6, "max_depth": 0.08,
	},
	"extinguisher": {
		"label": "Fire extinguisher", "slot": "extinguisher_scene", "folder": "res://assets/props/safety",
		"fit_axis": FitAxis.HEIGHT, "fit_size": 0.58, "pivot": Pivot.BOTTOM,
		"collision": Collision.BOX, "tri_budget": 6000, "max_width": 0.35, "max_depth": 0.25,
	},
	"air_vent": {
		"label": "Wall air vent", "slot": "vent_scene", "folder": "res://assets/props/vents",
		"fit_axis": FitAxis.WIDTH, "fit_size": 0.32, "pivot": Pivot.CENTER,
		"collision": Collision.NONE, "tri_budget": 8000, "max_width": 0.4, "max_depth": 0.1,
	},
	"bunk_bed": {
		"label": "Bunk bed (sleeper)", "slot": "", "folder": "res://assets/props/sleeper",
		"fit_axis": FitAxis.LONGEST, "fit_size": 1.95, "pivot": Pivot.BOTTOM,
		"collision": Collision.CONVEX, "tri_budget": 20000, "max_width": 0.0, "max_depth": 0.0,
	},
	"compartment_door": {
		"label": "Compartment door (sleeper)", "slot": "", "folder": "res://assets/props/sleeper",
		"fit_axis": FitAxis.HEIGHT, "fit_size": 2.0, "pivot": Pivot.BOTTOM,
		"collision": Collision.NONE, "tri_budget": 9000, "max_width": 0.0, "max_depth": 0.0,
	},
	"bogie": {
		"label": "Bogie", "slot": "bogie_scene", "folder": "res://assets/props/bogies",
		"fit_axis": FitAxis.LONGEST, "fit_size": 3.2, "pivot": Pivot.BOTTOM,
		"collision": Collision.NONE, "tri_budget": 15000, "max_width": 2.4, "max_depth": 0.0,
	},
	"prop": {
		"label": "Generic prop", "slot": "", "folder": "res://assets/props",
		"fit_axis": FitAxis.LONGEST, "fit_size": 1.0, "pivot": Pivot.BOTTOM,
		"collision": Collision.CONVEX, "tri_budget": 10000, "max_width": 0.0, "max_depth": 0.0,
	},
}

# ————— pub api —————

## Model files directly inside each res://TripoModels/<name>/ folder.
static func find_models(root_dir: String = "res://TripoModels") -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root_dir)
	if dir == null:
		return found
	for sub in dir.get_directories():
		var sub_path := root_dir.path_join(sub)
		for f in DirAccess.get_files_at(sub_path):
			if f.get_extension().to_lower() in MODEL_EXTENSIONS:
				found.append(sub_path.path_join(f))
	found.sort()
	return found

## Options: source (model res path), out_path, forward, fit_axis, fit_size, pivot, collision,
## optional override_material (applied to every surface),
## plus tri_budget / max_width / max_depth for the report.
## Returns { ok, out_path, size, scale, tris, warnings, error }.
static func normalize(options: Dictionary) -> Dictionary:
	var result := {"ok": false, "out_path": "", "size": Vector3.ZERO, "scale": 0.0,
			"tris": 0, "warnings": [], "error": ""}
	var source: String = options.get("source", "")
	var out_path: String = options.get("out_path", "")
	if out_path.is_empty():
		result.error = "No output path"
		return result

	var model := _instantiate_model(load(source))
	if model == null:
		result.error = "Could not load a 3D model from: " + source
		return result
	model.name = "Model"
	# Blender-exported GLBs already carry correct materials; loose-texture matching would read
	# glTF's packed metallic-roughness image as plain metallic.
	var textured := false
	if options.get("reapply_textures", true):
		textured = _reapply_tripo_textures(model, source.get_base_dir())

	var meshes := _collect_meshes(model)
	# Optional material for every surface (e.g. a shader that keys painted glass).
	var override: Material = options.get("override_material")
	if override:
		for mi in meshes:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, override)
		textured = true
	if meshes.is_empty():
		model.free()
		result.error = "No meshes found in model"
		return result

	# Bounds in the model's parent space (includes the import's own root transform).
	var base := model.transform
	var src_aabb := _bounds(meshes, model, base)

	var rot := _forward_basis(options.get("forward", Forward.POS_Z))
	var rotated := Transform3D(rot, Vector3.ZERO) * src_aabb
	var fit_dim := _axis_size(rotated.size, options.get("fit_axis", FitAxis.LONGEST))
	if fit_dim <= 0.0:
		model.free()
		result.error = "Model has zero size along the fit axis"
		return result
	var s: float = float(options.get("fit_size", 1.0)) / fit_dim
	var scaled := Transform3D(rot.scaled(Vector3.ONE * s), Vector3.ZERO) * src_aabb
	var p := _pivot_point(scaled, options.get("pivot", Pivot.BOTTOM))

	model.transform = Transform3D(rot.scaled(Vector3.ONE * s), -p) * base
	var final_aabb := AABB(scaled.position - p, scaled.size)

	var root := Node3D.new()
	root.name = out_path.get_file().get_basename().to_pascal_case()
	root.add_child(model)
	model.owner = root
	if textured:
		# Keeps the texture overrides on the model's inner nodes when packed.
		root.set_editable_instance(model, true)

	_add_collision(root, model, meshes, final_aabb, options.get("collision", Collision.NONE))
	var tris := _count_tris(meshes)

	var pack := PackedScene.new()
	var err := pack.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
		err = ResourceSaver.save(pack, out_path)
	root.free()
	if err != OK:
		result.error = "Could not save prefab (error %d)" % err
		return result

	result.ok = true
	result.out_path = out_path
	result.size = final_aabb.size
	result.scale = s
	result.tris = tris
	result.warnings = _check(options, final_aabb.size, tris)
	return result

## Default output path for a model + preset: <preset folder>/<model_name>.tscn
static func default_out_path(source: String, preset_key: String) -> String:
	var folder: String = PRESETS.get(preset_key, PRESETS.prop).folder
	return folder.path_join(source.get_file().get_basename().to_snake_case() + ".tscn")

# ————— impl —————

# glb/gltf/fbx import as scenes; obj imports as a bare Mesh by default.
static func _instantiate_model(res: Resource) -> Node3D:
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		return mi
	return null

# The Tripo bridge applies loose PBR textures as surface overrides on the scene instance it
# drops in; a fresh instance from the file doesn't have them, so apply them again here.
static func _reapply_tripo_textures(model: Node, asset_dir: String) -> bool:
	var files := ImportFileUtils.list_files_recursive(ProjectSettings.globalize_path(asset_dir))
	var maps := TripoTextureApplicator.collect_texture_maps(asset_dir, files)
	var has_any := false
	for key in maps:
		if not (maps[key] as Dictionary).is_empty():
			has_any = true
	if has_any:
		TripoTextureApplicator.apply_surface_material_overrides(model, maps, {})
	return has_any

static func _collect_meshes(node: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)
	return out

# Transform from the model root's local space to `node` (the root's own transform excluded).
static func _local_to(model: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != model and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

static func _bounds(meshes: Array[MeshInstance3D], model: Node3D, base: Transform3D) -> AABB:
	var aabb := AABB()
	var first := true
	for mi in meshes:
		var box := (base * _local_to(model, mi)) * mi.mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	return aabb

# Rotation about Y that turns the source's front direction into -Z.
static func _forward_basis(forward: int) -> Basis:
	match forward:
		Forward.POS_Z: return Basis(Vector3.UP, PI)
		Forward.POS_X: return Basis(Vector3.UP, PI * 0.5)
		Forward.NEG_X: return Basis(Vector3.UP, -PI * 0.5)
	return Basis.IDENTITY

static func _axis_size(size: Vector3, axis: int) -> float:
	match axis:
		FitAxis.WIDTH: return size.x
		FitAxis.HEIGHT: return size.y
		FitAxis.DEPTH: return size.z
	return maxf(size.x, maxf(size.y, size.z))

static func _pivot_point(aabb: AABB, pivot: int) -> Vector3:
	var c := aabb.get_center()
	match pivot:
		Pivot.BOTTOM: return Vector3(c.x, aabb.position.y, c.z)
		Pivot.TOP: return Vector3(c.x, aabb.end.y, c.z)
	return c

static func _add_collision(root: Node3D, model: Node3D, meshes: Array[MeshInstance3D],
		final_aabb: AABB, mode: int) -> void:
	if mode == Collision.NONE:
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)
	body.owner = root
	if mode == Collision.BOX:
		var box := BoxShape3D.new()
		box.size = final_aabb.size
		_add_shape(body, root, box, Transform3D(Basis.IDENTITY, final_aabb.get_center()))
		return
	for mi in meshes:
		var shape: Shape3D
		if mode == Collision.CONVEX:
			shape = mi.mesh.create_convex_shape(true, true)
		else:
			shape = mi.mesh.create_trimesh_shape()
		if shape:
			_add_shape(body, root, shape, model.transform * _local_to(model, mi))

static func _add_shape(body: StaticBody3D, owner: Node, shape: Shape3D, xform: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	cs.transform = xform
	body.add_child(cs, true)
	cs.owner = owner

static func _count_tris(meshes: Array[MeshInstance3D]) -> int:
	var total := 0
	for mi in meshes:
		total += mi.mesh.get_faces().size() / 3
	return total

static func _check(options: Dictionary, size: Vector3, tris: int) -> Array[String]:
	var warnings: Array[String] = []
	var budget: int = options.get("tri_budget", 0)
	if budget > 0 and tris > budget:
		warnings.append("%d triangles is over the %d budget for this slot — decimate in Blender or rely on LODs." % [tris, budget])
	var max_w: float = options.get("max_width", 0.0)
	if max_w > 0.0 and size.x > max_w + 0.01:
		warnings.append("Width %.2f m exceeds the slot's %.2f m — it may clip into neighbours." % [size.x, max_w])
	var max_d: float = options.get("max_depth", 0.0)
	if max_d > 0.0 and size.z > max_d + 0.01:
		warnings.append("Depth %.2f m exceeds the slot's %.2f m — it may clip into neighbours." % [size.z, max_d])
	return warnings
