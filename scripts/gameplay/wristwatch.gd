class_name Wristwatch
extends Node3D
## Kevin's digital wristwatch: T raises his left forearm in front of him (his uniform sleeve and hand)
## with the watch face turned up to him, lit faintly so it reads in the dark; it goes
## down again on T, after a few seconds, or when the clipboard comes up. It shows the train's clock,
## the colon blinking with the real seconds.

const DIGITS := preload("res://assets/fonts/DSEG7Classic-Bold.ttf")
const ARM := preload("res://assets/viewmodels/kevin_arm.glb")
const LOOK_SECONDS := 5.0
const HEAD := preload("res://assets/viewmodels/watch_head.glb")
const PRINT := preload("res://assets/fonts/Oswald.ttf")
const STRAP_X := 0.016                   # along the forearm: over the cuff, short of where it ends
const STRAP_W := 0.019                   # the bracelet's width, between the lugs
const LINK := preload("res://assets/viewmodels/watch_link.glb")
const PITCH := 0.0048                    # one link's length along the bracelet
const LUG_REACH := 0.0196                # the pins, across the wrist from the case's middle
const PIN_Y := 0.0013                    # the pins' height over the case's underside
const VIEW_LAYER := 1 << 18              # the watch's own render layer (for its lamp)
const RING_STEPS := 48

var shown := false:
	set(v):
		shown = v
		_up_t = 0.0
var _k := 0.0
var _up_t := 0.0
var _cam: Camera3D
var _player: Node
var _arm: Node3D
var _face: Label3D
var _ts: Node
var _up: Transform3D
var _down: Transform3D

func _ready() -> void:
	add_to_group("wristwatch")
	_ts = get_node_or_null("/root/TrainState")
	visible = false
	_attach.call_deferred()

static func of(n: Node) -> Wristwatch:
	return n.get_tree().get_first_node_in_group("wristwatch") as Wristwatch

func _attach() -> void:
	await get_tree().process_frame
	_player = get_tree().root.find_child("Player", true, false)
	_cam = _player.get_node_or_null("Head/Camera") as Camera3D if _player else null
	if _cam == null:
		return
	get_parent().remove_child(self)
	_cam.add_child(self)
	_build()
	# Checking the time: the forearm bent across his chest, coming in from low on the left, the hand
	# to the right and a little away, palm down; the wrist turned so the watch faces his eyes.
	var along := Vector3(0.9, 0.1, -0.42).normalized()
	var face := Vector3(-0.05, 0.8, 0.6).normalized()
	var up := (face - along * along.dot(face)).normalized()
	var b := Basis(along, up, along.cross(up))
	_up = Transform3D(b, Vector3(-0.06, -0.105, -0.3))
	_down = Transform3D(b.rotated(Vector3.RIGHT, 0.6), Vector3(-0.12, -0.42, -0.15))
	transform = _down

func _unhandled_input(e: InputEvent) -> void:
	var pressed: bool = e.is_action_pressed("fp_watch") if InputMap.has_action("fp_watch") \
			else (e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_T)
	if pressed and _cam:
		shown = not shown
		if shown:
			var c := Clipboard.of(self)
			if c:
				c.shown = false
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _cam == null:
		return
	if shown:
		_up_t += delta
		var hd := HorrorDirector.of(self)
		if _up_t > LOOK_SECONDS or (_player.has_method("is_focused") and bool(_player.call("is_focused"))) or (hd and hd.hold):
			shown = false
	_k = move_toward(_k, 1.0 if shown else 0.0, delta * 3.6)
	visible = _k > 0.0
	if not visible:
		return
	transform = _down.interpolate_with(_up, smoothstep(0.0, 1.0, _k))
	var clock := float(_ts.get("clock")) if _ts else 19.0
	var t := TaskBoard.hhmm(clock)
	if fmod(Time.get_ticks_msec() / 1000.0, 1.0) > 0.5:
		t = t.replace(":", " ")                        # (DSEG: a space is as wide as the colon)
	if _face.text != t:
		_face.text = t

# ————— the arm, along +X with the wrist at the origin; the watch on top (+Y) —————

func _build() -> void:
	_arm = Node3D.new()
	add_child(_arm)
	# His forearm and hand (assets/viewmodels/kevin_arm.glb: the uniform sleeve and a gloved hand,
	# cut from the guards' model), the wrist joint at the origin, +X toward the hand, +Y the back.
	var limb := (ARM.instantiate() as Node3D)
	_arm.add_child(limb)
	var pts: Array = []
	for mi: MeshInstance3D in limb.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Close to the eye under a ceiling lamp the leather reads too pale: a shade darker here.
		var src := mi.get_active_material(0) as StandardMaterial3D
		if src:
			var m := src.duplicate() as StandardMaterial3D
			m.albedo_color = Color(0.72, 0.72, 0.72)
			m.roughness = 0.75
			mi.material_override = m
		pts.append_array(_surface_points(mi, limb))
	# Worn over the cuff, as a man in gloves does: the bracelet follows the sleeve all the way round.
	var ring := _ring_profile(pts, STRAP_X)
	var c: Vector3 = ring.center
	var radii: PackedFloat32Array = ring.radii
	# The watch itself on top (assets/viewmodels/watch_head.glb; its origin is the case's underside).
	var top: float = c.y + radii[0] + 0.0004
	_bracelet(c, radii, top + PIN_Y)
	var head := HEAD.instantiate() as Node3D
	head.position = Vector3(STRAP_X, top, c.z)
	_arm.add_child(head)
	for mi: MeshInstance3D in head.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 | VIEW_LAYER
		var sm := mi.get_active_material(0)
		if sm:
			mi.material_override = _watch_mat(sm.resource_name)
			if sm.resource_name == "glass":
				mi.visible = false                     # (a transparent dome mirrors the whole car: the window is recessed enough)
	var lcd_y := top + 0.00705
	var ghost := _digits_label(Color(0.1, 0.14, 0.12, 0.1))
	ghost.text = "88:88"
	ghost.position = Vector3(STRAP_X, lcd_y, c.z + 0.0004)
	_arm.add_child(ghost)
	_face = _digits_label(Color(0.03, 0.04, 0.035))
	_face.position = Vector3(STRAP_X, lcd_y + 0.00003, c.z + 0.0004)
	_arm.add_child(_face)
	# The small print on the black dial, above and below the window, and by the pushers.
	var dial_y := top + 0.0077
	_print("ALARM  CHRONOGRAPH", Vector3(STRAP_X, dial_y, c.z - 0.0098), 1.0)
	_print("WATER RESIST", Vector3(STRAP_X, dial_y, c.z + 0.0098), 0.85)
	_print("LIGHT", Vector3(STRAP_X - 0.0128, dial_y, c.z - 0.0085), 0.75)
	_print("MODE", Vector3(STRAP_X - 0.0128, dial_y, c.z + 0.0085), 0.75)
	_print("ALARM", Vector3(STRAP_X + 0.0128, dial_y, c.z - 0.0085), 0.75)
	_print("START", Vector3(STRAP_X + 0.0128, dial_y, c.z + 0.0085), 0.75)
	# A small lamp of its own, so the steel catches a highlight (it lights the watch and nothing else).
	var glint := OmniLight3D.new()
	glint.light_cull_mask = VIEW_LAYER
	glint.light_energy = 0.6
	glint.omni_range = 0.25
	glint.shadow_enabled = false
	glint.position = Vector3(STRAP_X - 0.06, top + 0.08, c.z - 0.05)
	_arm.add_child(glint)

# The bracelet: its link (assets/viewmodels/watch_link.glb) laid every PITCH along the sleeve's
# outline, from the lugs on one side round under the arm to the lugs on the other.
func _bracelet(c: Vector3, radii: PackedFloat32Array, pin_y: float) -> void:
	var src := (LINK.instantiate() as Node3D)
	var link_mi := src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh := link_mi.mesh.duplicate() as Mesh
	var own := link_mi.transform                       # (the glTF keeps the link's turn on its node)
	for i in mesh.get_surface_count():
		var sm := mesh.surface_get_material(i)
		mesh.surface_set_material(i, _watch_mat(sm.resource_name if sm else ""))
	src.free()
	var at := func(a: float) -> Vector3:
		var k := fposmod(a / TAU * RING_STEPS, RING_STEPS)
		var r := lerpf(radii[int(k) % RING_STEPS], radii[(int(k) + 1) % RING_STEPS], k - floorf(k))
		return c + Vector3(0, cos(a), sin(a)) * (r + 0.0003)
	# The pins between the lugs, either side of the top: the bracelet hangs from them.
	var a0 := asin(clampf(LUG_REACH / (radii[0] + 0.0003), 0.0, 0.99))
	# (each pin's height above where the sleeve is, at its own side)
	var lift0: float = maxf(pin_y - (at.call(a0) as Vector3).y - 0.0013, 0.0)
	var lift1: float = maxf(pin_y - (at.call(TAU - a0) as Vector3).y - 0.0013, 0.0)
	var xfs: Array = []
	var a := a0
	var last: Vector3 = at.call(a)
	var walked := PITCH * 0.7
	while a < TAU - a0:
		a += 0.004
		var p: Vector3 = at.call(a)
		walked += (p - c).length() * 0.004              # (by the angle: the outline is a little jagged)
		last = p
		if walked >= PITCH:
			walked -= PITCH
			var d := Vector3(0, cos(a), sin(a))
			# The links nearest the pins rise to meet them, then lie on the sleeve.
			var r0 := radii[0] + 0.0003
			var up := lift0 * clampf(1.0 - (a - a0) * r0 / PITCH / 2.5, 0.0, 1.0) 					+ lift1 * clampf(1.0 - (TAU - a0 - a) * r0 / PITCH / 2.5, 0.0, 1.0)
			xfs.append(Transform3D(Basis(Vector3.RIGHT, d, Vector3.RIGHT.cross(d)), p + d * up))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i] * own)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.layers = 1 | VIEW_LAYER
	_arm.add_child(mmi)

func _watch_mat(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match kind:
		"steel_polished":
			m.albedo_color = Color(0.8, 0.8, 0.82)
			m.metallic = 1.0
			m.roughness = 0.14
		"case_brushed":
			m.albedo_color = Color(0.72, 0.72, 0.74)
			m.metallic = 1.0
			m.roughness = 0.32
		"dial_black":
			m.albedo_color = Color(0.01, 0.01, 0.012)
			m.roughness = 0.7                          # (matte paint: it must read black under a lamp)
			m.metallic_specular = 0.2
		"lcd":
			return _lcd_mat()
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.85, 0.92, 1.0, 0.04)
			m.roughness = 0.06
			m.metallic_specular = 0.12
		_:
			m.albedo_color = Color(0.7, 0.7, 0.72)
			m.metallic = 1.0
			m.roughness = 0.3
	return m

# Points over the mesh's surface (its vertices and the middles of its triangles) in the limb's space.
func _surface_points(mi: MeshInstance3D, limb: Node3D) -> Array:
	var xf := limb.global_transform.affine_inverse() * mi.global_transform
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out: Array = []
	for v in vs:
		out.append(xf * v)
	for i in range(0, idx.size(), 3):
		out.append(xf * ((vs[idx[i]] + vs[idx[i + 1]] + vs[idx[i + 2]]) / 3.0))
	return out

# The sleeve's outline round its axis at `x`: a centre, and a radius for each of RING_STEPS angles
# (angle 0 = straight up, +Y), each the furthest the surface reaches there, smoothed, plus clearance.
func _ring_profile(pts: Array, x: float) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := -lo
	var slice: Array = []
	for p: Vector3 in pts:
		if absf(p.x - x) < STRAP_W * 0.6:
			slice.append(p)
			lo = lo.min(Vector2(p.y, p.z))
			hi = hi.max(Vector2(p.y, p.z))
	var mid := (lo + hi) * 0.5
	var r := PackedFloat32Array()
	r.resize(RING_STEPS)
	r.fill(0.0)
	for p: Vector3 in slice:
		var d := Vector2(p.y - mid.x, p.z - mid.y)
		var a := fposmod(atan2(d.y, d.x), TAU)
		var k := int(round(a / TAU * RING_STEPS)) % RING_STEPS
		r[k] = maxf(r[k], d.length())
	# Bins nothing fell in take their neighbours'; then a gentle smoothing (a strap does not dent).
	for pass_i in 3:
		for k in RING_STEPS:
			if r[k] <= 0.0:
				r[k] = maxf(r[(k + 1) % RING_STEPS], r[(k - 1 + RING_STEPS) % RING_STEPS])
	var sm := PackedFloat32Array()
	sm.resize(RING_STEPS)
	for k in RING_STEPS:
		var m := 0.0
		for j in range(-2, 3):
			m = maxf(m, r[(k + j + RING_STEPS) % RING_STEPS])
		sm[k] = m + 0.0012
	return {"center": Vector3(x, mid.x, mid.y), "radii": sm}

func _print(text: String, at: Vector3, scale := 1.0) -> void:
	var l := Label3D.new()
	l.font = PRINT
	l.text = text
	l.font_size = 24
	l.pixel_size = 0.000042 * scale
	l.modulate = Color(0.82, 0.82, 0.8)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	l.position = at
	_arm.add_child(l)

func _digits_label(col: Color) -> Label3D:
	var l := Label3D.new()
	l.font = DIGITS
	l.font_size = 48
	l.pixel_size = 0.000162
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	# Lying on the face, reading along the forearm toward the hand, its top away from him.
	l.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	l.position = Vector3(0, 0.0352, 0)
	return l

func _lcd_mat() -> StandardMaterial3D:
	var m := _mat(Color(0.56, 0.63, 0.56), 0.4)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.62, 0.55)
	m.emission_energy_multiplier = 0.35
	return m

func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
