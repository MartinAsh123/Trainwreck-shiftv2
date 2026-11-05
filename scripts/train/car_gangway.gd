@tool
class_name CarGangway
extends Node3D
## Open gangway between two coupled cars: two hinged chequer-plate fall plates (one from each
## car, overlapping in the middle), steel toe boards, and a waist-high railing on each side made
## of telescopic tubes running from posts bolted to each car end (so the cars can move apart a
## little on curves). Collision keeps you on the plates.
## Origin = middle of the gap between the two car bodies, at car floor level; X runs along the train.

## Distance between the two car end walls (buffer face to buffer face of PassengerCar = 0.74 m).
@export var gap_length: float = 0.74:
	set(v): gap_length = v; _rebuild()
## Width of the walkway (a little wider than the gangway doors).
@export var walk_width: float = 1.12:
	set(v): walk_width = v; _rebuild()
## Top rail height above the floor (waist height).
@export var rail_height: float = 1.0:
	set(v): rail_height = v; _rebuild()

const PLATE_SHADER := preload("res://shaders/train/chequer_plate.gdshader")

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	var old := get_node_or_null("Built")
	if old:
		old.free()
	var root := Node3D.new()
	root.name = "Built"
	add_child(root)

	var half := gap_length * 0.5
	var hw := walk_width * 0.5
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.12, 0.12, 0.11)
	iron.metallic = 0.45
	iron.roughness = 0.55
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.79, 0.64, 0.29)
	brass.metallic = 0.85
	brass.roughness = 0.3

	# Fall plates: hinged at each car's end, the -X plate lies under the +X plate's free end.
	var overlap := 0.05
	for s in [-1.0, 1.0]:
		var pl := half + overlap
		var top_y := 0.004 if s < 0.0 else 0.009
		var plate_mat := ShaderMaterial.new()
		plate_mat.shader = PLATE_SHADER
		plate_mat.set_shader_parameter("half_size", Vector2(pl * 0.5, hw))
		var p := _box(root, "FallPlate", Vector3(pl, 0.01, walk_width), Vector3(s * (half - pl * 0.5), top_y - 0.005, 0), plate_mat)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Hinge knuckles along the car end.
		for kz in [-0.38, 0.0, 0.38]:
			var k := _cyl(root, "Hinge", 0.011, 0.13, Vector3(s * (half - 0.02), top_y - 0.008, kz), iron)
			k.rotation.x = PI * 0.5
		# Lifting slots near the upper plate's free end.
		if s > 0.0:
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.03, 0.03, 0.03)
			for lz in [-0.3, 0.3]:
				_box(root, "LiftSlot", Vector3(0.025, 0.002, 0.1), Vector3(-overlap + 0.045, top_y + 0.0005, lz), dark)
	# Bevelled lip on the upper plate's free end, so feet don't catch on it.
	var lip := _box(root, "PlateLip", Vector3(0.02, 0.005, walk_width), Vector3(-overlap - 0.01, 0.0065, 0), iron)
	lip.rotation.z = 0.25

	# Toe boards (telescopic: the +X board slides outside the -X one) and railings, both sides.
	for zs in [-1.0, 1.0]:
		var z_in: float = zs * (hw + 0.006)
		var z_out: float = zs * (hw + 0.016)
		_box(root, "ToeBoard", Vector3(half + 0.1, 0.12, 0.006), Vector3(-half + (half + 0.1) * 0.5, 0.06, z_in), iron)
		_box(root, "ToeBoard", Vector3(half + 0.1, 0.12, 0.006), Vector3(half - (half + 0.1) * 0.5, 0.06, z_out), iron)
		var rz: float = zs * (hw + 0.04)
		for s in [-1.0, 1.0]:
			var px: float = s * (half - 0.035)
			# Post with a base flange and a brass ball finial.
			_rod(root, "RailPost", Vector3(px, 0.0, rz), Vector3(px, rail_height, rz), 0.017, iron)
			_box(root, "PostFlange", Vector3(0.07, 0.008, 0.07), Vector3(px, 0.004, rz), iron)
			_ball(root, "PostCap", Vector3(px, rail_height + 0.02, rz), 0.024, brass)
			# Two brackets bolting the post to the car end wall.
			for by in [0.3, rail_height - 0.1]:
				_rod(root, "WallBracket", Vector3(px, by, rz), Vector3(s * half, by, rz), 0.009, iron)
				_box(root, "WallPlate", Vector3(0.008, 0.07, 0.05), Vector3(s * (half - 0.004), by, rz), iron)
		# Telescopic rails: thin tubes from the -X posts slide into sleeves from the +X posts.
		for ry: float in [rail_height, rail_height * 0.55]:
			var top := ry == rail_height
			var tube_m: Material = brass if top else iron
			var r_in := 0.015 if top else 0.011
			var r_out := 0.021 if top else 0.016
			_rod(root, "RailTube", Vector3(-half + 0.035, ry, rz), Vector3(0.12, ry, rz), r_in, tube_m)
			_rod(root, "RailSleeve", Vector3(half - 0.035, ry, rz), Vector3(-0.01, ry, rz), r_out, tube_m)
			var collar := _cyl(root, "SleeveCollar", r_out + 0.005, 0.022, Vector3(-0.01, ry, rz), iron if top else brass)
			collar.rotation.z = PI * 0.5
			for s in [-1.0, 1.0]:
				_ball(root, "RailJoint", Vector3(s * (half - 0.035), ry, rz), r_out + 0.004, iron)

	# Collision: the walkway and a tall invisible barrier along each railing.
	var body := StaticBody3D.new()
	body.set_meta("surface", "metal")          # footstep sounds
	body.name = "Collision"
	root.add_child(body)
	_shape(body, Vector3(gap_length + 0.1, 0.05, walk_width + 0.08), Vector3(0, 0.009 - 0.025, 0))
	for zs in [-1.0, 1.0]:
		_shape(body, Vector3(gap_length, 1.6, 0.06), Vector3(0, 0.8, zs * (hw + 0.05)))

func _shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)

func _box(parent: Node3D, n: String, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi, true)
	return mi

# Cylinder along Y (rotate to lay it down).
func _cyl(parent: Node3D, n: String, r: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi, true)
	return mi

func _rod(parent: Node3D, n: String, a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := _cyl(parent, n, r, a.distance_to(b), (a + b) * 0.5, m)
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return mi

func _ball(parent: Node3D, n: String, pos: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi, true)
	return mi
