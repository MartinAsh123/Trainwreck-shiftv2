@tool
class_name ToiletLock
extends Node3D
## Lavatory door lock: a brass thumb-turn on the inside face and a VACANT / ENGAGED indicator on
## the outside face, both driven by `locked`. Sits where the door model's painted indicator is;
## local origin = indicator centre on the door's mid-plane, -Z = outside (corridor), +Z = inside.
## Call toggle() from gameplay to lock / unlock.

signal lock_changed(locked: bool)

@export var locked: bool = false:
	set(v):
		locked = v
		_apply()
		lock_changed.emit(locked)
## Door faces at the indicator (local Z of the outside and inside surfaces).
@export var outside_z: float = -0.056:
	set(v): outside_z = v; _rebuild()
@export var inside_z: float = 0.058:
	set(v): inside_z = v; _rebuild()

const VACANT_COLOR := Color(0.1, 0.48, 0.2)
const ENGAGED_COLOR := Color(0.72, 0.08, 0.06)
const FONT_PATH := "res://assets/fonts/Oswald.ttf"

var _face_mat: StandardMaterial3D
var _label: Label3D
var _turn: Node3D

func _ready() -> void:
	_rebuild()

func toggle() -> void:
	locked = not locked

func get_prompt() -> String:
	return "E — Unlock" if locked else "E — Lock"

func interact(_by: Node = null) -> String:
	toggle()
	return ""

func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("_lock_part"):
			c.free()
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.79, 0.64, 0.29)
	brass.metallic = 0.85
	brass.roughness = 0.28

	# Outside: brass bezel with a domed glass window over the coloured indicator plate.
	var out := _part("Indicator", Vector3(0, 0, outside_z))
	_disc(out, "Bezel", 0.031, 0.004, -0.002, brass)
	_disc(out, "BezelLip", 0.0255, 0.0015, -0.0045, brass)
	_face_mat = StandardMaterial3D.new()
	_face_mat.roughness = 0.35
	_face_mat.emission_enabled = true
	_face_mat.emission_energy_multiplier = 0.25
	_disc(out, "Window", 0.0215, 0.001, -0.0055, _face_mat)
	_label = Label3D.new()
	_label.name = "Word"
	_label.font = _font()
	_label.font_size = 64
	_label.pixel_size = 0.006 / (64.0 * 0.81)
	_label.modulate = Color(0.97, 0.94, 0.85)
	_label.double_sided = false
	_label.shaded = true
	_label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	_label.render_priority = 1
	_label.position = Vector3(0, 0, -0.0062)
	_label.rotation.y = PI          # face the corridor (-Z)
	out.add_child(_label)
	for sx in [-1.0, 1.0]:
		_disc(out, "Screw", 0.0022, 0.0012, -0.0046, brass).position.x = sx * 0.0282

	# Inside: round brass rose with a turn piece (vertical = open, horizontal = locked).
	var inn := _part("ThumbTurn", Vector3(0, 0, inside_z))
	_disc(inn, "Rose", 0.031, 0.004, 0.002, brass)
	_disc(inn, "RoseStep", 0.019, 0.002, 0.005, brass)
	_turn = Node3D.new()
	_turn.name = "Turn"
	_turn.position = Vector3(0, 0, 0.006)
	inn.add_child(_turn)
	_disc(_turn, "Neck", 0.008, 0.004, 0.002, brass)
	var grip := MeshInstance3D.new()
	grip.name = "Grip"
	var cm := CapsuleMesh.new()
	cm.radius = 0.0065
	cm.height = 0.04
	cm.radial_segments = 20
	cm.rings = 6
	grip.mesh = cm
	grip.material_override = brass
	grip.scale = Vector3(0.75, 1.0, 1.15)
	grip.position = Vector3(0, 0, 0.0105)
	_turn.add_child(grip)
	# Small occupancy window above the rose, seen from inside too.
	var inner_dot := StandardMaterial3D.new()
	inner_dot.roughness = 0.4
	_disc(inn, "StateDot", 0.004, 0.001, 0.0045, inner_dot).position.y = 0.038
	_disc(inn, "StateDotRim", 0.0055, 0.0008, 0.004, brass).position.y = 0.038
	# What the player aims at to turn it (inside only: from the corridor the door is in the way).
	var area := Area3D.new()
	area.name = "TurnArea"
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = false
	inn.add_child(area)
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.055
	cs.shape = sph
	cs.position = Vector3(0, 0, 0.03)
	area.add_child(cs)
	_apply()

func _apply() -> void:
	if _face_mat == null:
		return
	var c := ENGAGED_COLOR if locked else VACANT_COLOR
	_face_mat.albedo_color = c
	_face_mat.emission = c
	_label.text = "ENGAGED" if locked else "VACANT"
	var turn_to := PI * 0.5 if locked else 0.0
	if Engine.is_editor_hint() or not _turn.is_inside_tree():
		_turn.rotation.z = turn_to
	else:
		_turn.create_tween().tween_property(_turn, "rotation:z", turn_to, 0.25).set_trans(Tween.TRANS_SINE)
	var dot := get_node_or_null("ThumbTurn/StateDot") as MeshInstance3D
	if dot:
		(dot.material_override as StandardMaterial3D).albedo_color = c

func _part(part_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = part_name
	n.position = pos
	n.set_meta("_lock_part", true)
	add_child(n)
	return n

# Disc facing along Z (thickness `h`), centred at local z = `z`.
func _disc(parent: Node3D, disc_name: String, r: float, h: float, z: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = disc_name
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 32
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.rotation.x = PI * 0.5
	mi.position = Vector3(0, 0, z)
	parent.add_child(mi)
	return mi

func _font() -> Font:
	if not ResourceLoader.exists(FONT_PATH):
		return ThemeDB.fallback_font
	var base := load(FONT_PATH) as FontFile
	base.multichannel_signed_distance_field = true
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	fv.spacing_glyph = 2
	return fv
