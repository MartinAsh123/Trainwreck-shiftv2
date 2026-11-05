class_name MonsterFace
extends Node
## What an anomaly's face really is, for the second it stops pretending (AnomalyFrenzy): its own face
## gone to something dead and wet. The skin takes monster_skin.gdshader in place of its own material:
## drained, creased, veined, hollowed, and the mouth cut wider than a mouth; real eyes stare out of the
## sockets and follow what they are told to; behind the torn mouth a bowl of wet red, gums, rows of
## needle teeth and strings of spit (built here, on the head bone: the upper row fixed, the lower one
## turning with the jaw, which is the talking face's own shape keys driven well over 1). Claws on the
## hands.
##   var m := MonsterFace.attach(body, base_slug, kind)
##   m.amount = 1.0                  # 0 the passenger .. 1 the skin and the eyes
##   m.gape = 1.0                    # the mouth, 0 shut .. 1 wide open
##   m.smile = 1.0                   # the mouth pulled back, shut: too far
##   m.stare_at = camera             # what the eyes follow

const SKIN := preload("res://shaders/characters/monster_skin.gdshader")
const EYE := preload("res://shaders/characters/monster_eye.gdshader")
const FLESH := preload("res://shaders/characters/monster_maw.gdshader")
const JAW := 3.4                     # jaw_open at full (face_rig's key turns the jaw 10 degrees at 1)
const WIDE := 2.6                    # lips_wide
const JAW_STEP := 10.0               # degrees per 1 of jaw_open
const LONG_NECK := 0.2               # how far make_anomaly lifts the head of a long neck
const EYE_R := 0.0108                # deep in the socket: only the middle of it shows
const EYE_IN := 0.0185               # how far behind the lids its middle sits
const BEAT := 1.9                    # hearts per second

static var _tex_n: Texture2D         # (the same three for every anomaly, loaded the once: Warm)
static var _tex_m: Texture2D
static var _tex_f: Texture2D
static var _warm: Array[ShaderMaterial] = []   # (held so their shaders are compiled ahead of need)

var body: TalkingCharacter
var amount := 0.0:
	set(v):
		amount = v
		_apply()
var gape := 0.0:
	set(v):
		gape = v
		_apply()
var smile := 0.0:
	set(v):
		smile = v
		_apply()
var stare_at: Node3D
var pupil := 0.07                    # radians from the eye's axis

var _mats: Array[ShaderMaterial] = []
var _maw: Node3D
var _inner: Node3D                   # what is behind the lips: hidden while they are shut
var _jaw: Node3D
var _head_rest := Transform3D()
var _head := -1
var _hand_l := -1
var _hand_r := -1
var _rest_l := Transform3D()
var _rest_r := Transform3D()
var _eyes: Array[Dictionary] = []    # {node, at, mat}
var _saccade := Vector2.ZERO
var _sacc_t := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _drool: ImmediateMesh
var _drool_ends: Array = []          # [upper point, lower point (on the jaw), sag, wobble]
var _claws: Array[Node3D] = []
var _m := Vector3.ZERO
var _half := 0.03
var _drop := 0.05

## Loads what the face is made of ahead of need, so the moment it is wanted does not stall.
static func warm() -> void:
	if _tex_n == null:
		_tex_n = load("res://assets/textures/frenzy/skin_n.png")
		_tex_m = load("res://assets/textures/frenzy/skin_mask.png")
		_tex_f = load("res://assets/textures/frenzy/face_map.png")
		for s: Shader in [SKIN, EYE, FLESH]:
			var mat := ShaderMaterial.new()
			mat.shader = s
			_warm.append(mat)

static func attach(b: TalkingCharacter, base: String, kind := "") -> MonsterFace:
	var m := MonsterFace.new()
	m.name = "MonsterFace"
	m.body = b
	b.add_child(m)
	m._build(base, kind)
	return m

func _build(base: String, kind: String) -> void:
	var f: Dictionary = FaceMarks.MARKS.get(base, {})
	if f.is_empty() or body._face == null or body._skel == null or not body._bones.has("Head"):
		push_warning("MonsterFace: no face marks for %s" % base)
		return
	warm()
	_rng.seed = hash(base)
	var skel := body._skel
	_head = body._bones["Head"]
	_head_rest = skel.get_bone_global_rest(_head)
	_hand_l = body._bones.get("LeftHand", -1)
	_hand_r = body._bones.get("RightHand", -1)
	if _hand_l >= 0:
		_rest_l = skel.get_bone_global_rest(_hand_l)
	if _hand_r >= 0:
		_rest_r = skel.get_bone_global_rest(_hand_r)
	var lift := Vector3(0, LONG_NECK if kind == "long_neck" else 0.0, 0)
	var m: Vector3 = _v(f.mouth) + lift
	var c0: Vector3 = _v(f.corners[0]) + lift
	var c1: Vector3 = _v(f.corners[1]) + lift
	var half := maxf(maxf(absf(c0.x), absf(c1.x)), 0.02)
	var e0: Vector3 = _v(f.eyes[0]) + lift
	var e1: Vector3 = _v(f.eyes[1]) + lift
	_m = m
	_half = half
	_drop = (e0.y - m.y) * 0.8
	# On the head bone; children are placed in the model's rest space.
	var at := BoneAttachment3D.new()
	at.name = "MonsterMaw"
	skel.add_child(at)
	at.bone_idx = _head
	_maw = Node3D.new()
	_maw.transform = _head_rest.affine_inverse()
	at.add_child(_maw)
	_maw.visible = false
	_inner = Node3D.new()
	_maw.add_child(_inner)
	var eye_spots := _skin(base, kind, e0, e1, m, half)
	_mouth(m, c0, c1, half)
	var eyed := kind != "faceless"
	if eyed:
		for e: Vector3 in ([e0, e1] if eye_spots.is_empty() or kind == "third_eye" else []):
			_eye(e + Vector3(0, 0, -EYE_IN), EYE_R, kind == "black_eyes")
		for e: Vector3 in eye_spots:
			var out_front: bool = kind in ["cyclops", "third_eye"]
			_eye(e + Vector3(0, 0, -EYE_R * 0.45 if out_front else -EYE_IN), EYE_R * (1.7 if kind == "cyclops" else 1.1), kind == "black_eyes")
	_set_all("eyes", 1.0 if eyed and kind != "cyclops" else 0.0)
	_set_all("eye_l", e0)
	_set_all("eye_r", e1)
	_set_all("mouth", m)
	_set_all("centre", Vector3(0, (m.y + e0.y) * 0.5, (e0.z + m.z) * 0.5 - 0.06))
	_set_all("half_w", half)
	_set_all("drop", _drop)
	_set_all("neck", 0.32 if kind == "long_neck" else 0.1)
	_set_all("hand_l", _rest_l.origin)
	_set_all("hand_r", _rest_r.origin)
	_set_all("skin_n", _tex_n)
	_set_all("skin_mask", _tex_m)
	_set_all("face_map", _tex_f)
	_claws_on()
	_apply()

## The passenger back as it was: it did not go through with it.
func detach() -> void:
	amount = 0.0
	gape = 0.0
	smile = 0.0
	body.face_weights = {}
	for s in body._face.mesh.get_surface_count():
		body._face.set_surface_override_material(s, null)
	if _maw:
		_maw.get_parent().queue_free()
	for at in _claws:
		at.queue_free()
	queue_free()

func _set_all(p: StringName, v: Variant) -> void:
	for mat in _mats:
		mat.set_shader_parameter(p, v)

# The skin in its new material, the decals laid over it dealt with. Returns where its own painted eyes
# were (a cyclops, a third eye, black eyes): real ones go there.
func _skin(_base: String, kind: String, e0: Vector3, e1: Vector3, _m0: Vector3, _h: float) -> Array:
	var spots: Array = []
	var gone := StandardMaterial3D.new()
	gone.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	gone.albedo_color = Color(0, 0, 0, 0)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0.008, 0.002, 0.002)
	var tongue := StandardMaterial3D.new()
	tongue.albedo_color = Color(0.14, 0.04, 0.07)
	tongue.roughness = 0.2
	tongue.metallic_specular = 0.7
	var mesh := body._face.mesh
	for s in mesh.get_surface_count():
		var sm0 := mesh.surface_get_material(s)
		var nm := sm0.resource_name if sm0 else ""
		if nm.contains("mouth_cavity"):
			body._face.set_surface_override_material(s, black)
		elif nm.contains("teeth_"):
			body._face.set_surface_override_material(s, gone)
		elif nm.contains("tongue"):
			body._face.set_surface_override_material(s, tongue)
		elif sm0 and StaticMerge._transparent(sm0):
			if nm.ends_with("_eye"):
				spots.append(_centroid(mesh, s))
				body._face.set_surface_override_material(s, gone)
			elif kind == "black_eyes":
				body._face.set_surface_override_material(s, gone)
				spots = [e0, e1]
			elif kind == "grey_marks":
				body._face.set_surface_override_material(s, gone)
			else:
				# (the skin grown over a cyclops's two eyes, and over a faceless head's)
				var d := sm0.duplicate() as StandardMaterial3D
				d.albedo_color = Color(0.3, 0.36, 0.42)    # (cold over a warm skin: grey)
				body._face.set_surface_override_material(s, d)
		elif sm0 is StandardMaterial3D:
			var st := sm0 as StandardMaterial3D
			var mat := ShaderMaterial.new()
			mat.shader = SKIN
			mat.set_shader_parameter("base_tex", st.albedo_texture)
			mat.set_shader_parameter("base_col", st.albedo_color)
			_mats.append(mat)
			body._face.set_surface_override_material(s, mat)
	if kind == "third_eye":
		_rng.randf()                       # (its two own stay, the third joins them below)
	return spots

func _centroid(mesh: Mesh, s: int) -> Vector3:
	var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
	var c := Vector3.ZERO
	for p in v:
		c += p
	return c / maxf(v.size(), 1.0)

func _eye(at: Vector3, r: float, all_black: bool) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = EYE
	mat.set_shader_parameter("black", 1.0 if all_black else 0.0)
	mat.set_shader_parameter("seed", _rng.randf_range(0.0, 40.0))
	mi.material_override = mat
	mi.scale = Vector3.ONE * r
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_maw.add_child(mi)
	_eyes.append({"node": mi, "at": at, "r": r, "mat": mat})

# The inside of it. The bowl behind everything, the gums, the teeth in them, the strings of spit.
func _mouth(m: Vector3, c0: Vector3, c1: Vector3, half: float) -> void:
	var cz := minf(c0.z, c1.z)
	var hinge := Vector3(0, m.y + 0.03, m.z - 0.085)
	var arch := func(t: float, wide: float) -> Vector3:
		return Vector3(t * half * wide, 0.0, m.z + (cz - m.z) * t * t * 1.5 - 0.017)
	# The bowl: a deep socket of wet flesh, black down the throat.
	var bowl := MeshInstance3D.new()
	bowl.mesh = _bowl(Vector3(half * 1.8, _drop * 0.62, 0.07))
	bowl.position = Vector3(0, m.y - _drop * 0.34, m.z - 0.03)
	bowl.material_override = _flesh(Color(0.3, 0.025, 0.04), 1.0)
	bowl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inner.add_child(bowl)
	var gum_mat := _flesh(Color(0.42, 0.05, 0.07), 0.0)
	var bone := StandardMaterial3D.new()
	bone.vertex_color_use_as_albedo = true
	bone.roughness = 0.24
	bone.metallic_specular = 0.75
	var up := _st()
	var lo := _st()
	var gu := _st()
	var gl := _st()
	# Upper arch: on the skull, up behind the lip.
	var up_pts: Array = []
	var lo_pts: Array = []
	var n := 15
	for i in n:
		var t := (float(i) / float(n - 1)) * 2.0 - 1.0
		var ua: Vector3 = arch.call(t, 1.7) + Vector3(0, m.y + 0.012, 0)
		var la: Vector3 = arch.call(t, 1.5) + Vector3(0, m.y - 0.01, 0.001) - hinge
		up_pts.append(ua)
		lo_pts.append(la)
		if _rng.randf() > 0.08:            # (one or two gone from the row)
			var fang := 1.0 + 1.25 * exp(-pow((absf(t) - 0.5) / 0.14, 2.0))
			var l := _rng.randf_range(0.015, 0.024) * fang
			_fang(up, ua + Vector3(_rng.randf_range(-0.001, 0.001), 0.002, _rng.randf_range(-0.0016, 0.0016)),
					Vector3(-t * 0.16 + _rng.randf_range(-0.14, 0.14), -1.0, 0.13), l, 0.003 + 0.0009 * fang, Vector3(0, 0, -0.007))
		if _rng.randf() > 0.1:
			var l2 := _rng.randf_range(0.013, 0.02) * (1.0 + 0.8 * exp(-pow((absf(t) - 0.4) / 0.14, 2.0)))
			_fang(lo, la + Vector3(0, -0.002, 0), Vector3(-t * 0.12 + _rng.randf_range(-0.14, 0.14), 1.0, 0.14), l2, 0.0029, Vector3(0, 0, -0.006))
		# A second row behind, smaller, set anyhow: it goes on down the throat.
		if i % 2 == 1:
			_fang(up, ua + Vector3(0, 0.003, -0.012), Vector3(_rng.randf_range(-0.25, 0.25), -1.0, -0.05), _rng.randf_range(0.009, 0.014), 0.0024, Vector3(0, 0, -0.004))
			_fang(lo, la + Vector3(0, -0.003, -0.012), Vector3(_rng.randf_range(-0.25, 0.25), 1.0, -0.05), _rng.randf_range(0.008, 0.012), 0.0022, Vector3(0, 0, -0.004))
	_tube(gu, up_pts, 0.0072)
	_tube(gl, lo_pts, 0.0064)
	var upper := MeshInstance3D.new()
	upper.mesh = _finish(up)
	upper.material_override = bone
	upper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inner.add_child(upper)
	var gum_u := MeshInstance3D.new()
	gum_u.mesh = _finish(gu)
	gum_u.material_override = gum_mat
	gum_u.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inner.add_child(gum_u)
	_jaw = Node3D.new()
	_jaw.position = hinge
	_inner.add_child(_jaw)
	var lower := MeshInstance3D.new()
	lower.mesh = _finish(lo)
	lower.material_override = bone
	lower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jaw.add_child(lower)
	var gum_l := MeshInstance3D.new()
	gum_l.mesh = _finish(gl)
	gum_l.material_override = gum_mat
	gum_l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jaw.add_child(gum_l)
	# Strings of spit across the mouth.
	_drool = ImmediateMesh.new()
	var dm := MeshInstance3D.new()
	dm.mesh = _drool
	var wet := StandardMaterial3D.new()
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.albedo_color = Color(0.78, 0.72, 0.62, 0.6)
	wet.roughness = 0.05
	wet.metallic_specular = 1.0
	wet.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.material_override = wet
	dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dm.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	_inner.add_child(dm)
	for t: float in [-0.72, -0.36, 0.1, 0.42, 0.78]:
		_drool_ends.append([up_pts[int((t + 1.0) * 0.5 * (n - 1))] + Vector3(0, -0.001, 0.002),
				lo_pts[int((t + 1.0) * 0.5 * (n - 1))] + Vector3(0, 0.001, 0.002), _rng.randf_range(0.006, 0.016), _rng.randf_range(0.0, TAU)])

func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	return st

func _flesh(tint: Color, ridges: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FLESH
	mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("ridges", ridges)
	return mat

# An ellipsoid's back half, opening toward +Z: red at the rim, black at the bottom.
func _bowl(radii: Vector3) -> ArrayMesh:
	const RINGS := 12
	const SIDES := 28
	var st := _st()
	for i in RINGS:
		for k in SIDES:
			for e: Array in [[i, k], [i + 1, k], [i + 1, k + 1], [i, k], [i + 1, k + 1], [i, k + 1]]:
				var r: float = float(e[0]) / RINGS
				var a: float = TAU * float(e[1]) / SIDES
				var th: float = r * PI * 0.5
				st.set_color(Color(smoothstep(0.15, 0.8, r), 0, 0))
				st.add_vertex(Vector3(cos(a) * cos(th) * radii.x, sin(a) * cos(th) * radii.y, -sin(th) * radii.z))
	return _finish(st)

# A soft tube along `pts`, lumpy: gum. COLOR.r is a little way down the throat.
func _tube(st: SurfaceTool, pts: Array, r: float) -> void:
	const SIDES := 10
	var dense: Array = []
	for i in pts.size() - 1:
		for s in 4:
			dense.append((pts[i] as Vector3).lerp(pts[i + 1], s / 4.0))
	dense.append(pts[-1])
	var rings: Array = []
	for i in dense.size():
		var fwd: Vector3 = (dense[mini(i + 1, dense.size() - 1)] - dense[maxi(i - 1, 0)]).normalized()
		var u := fwd.cross(Vector3.UP).normalized()
		var v := u.cross(fwd).normalized()
		var bump := 1.0 + 0.2 * sin(float(i) * 1.7) * sin(float(i) * 0.43)
		var ring: Array = []
		for k in SIDES:
			var a := TAU * k / SIDES
			ring.append(dense[i] + (u * cos(a) * 1.2 + v * sin(a)) * r * bump)
		rings.append(ring)
	for i in rings.size() - 1:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			for e: Array in [[i, k], [i + 1, k], [i + 1, k2], [i, k], [i + 1, k2], [i, k2]]:
				st.set_color(Color(0.18, 0, 0))
				st.add_vertex(rings[e[0]][e[1]])

func _claws_on() -> void:
	var skel := body._skel
	var bone := StandardMaterial3D.new()
	bone.vertex_color_use_as_albedo = true
	bone.roughness = 0.3
	bone.metallic_specular = 0.6
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		if not (n.contains("Hand") and n.ends_with("4")):
			continue
		var p := skel.get_bone_parent(i)
		if p < 0:
			continue
		var tip := skel.get_bone_global_rest(i).origin
		var from := skel.get_bone_global_rest(p).origin
		var st := _st()
		var d := (tip - from).normalized()
		var r := minf(from.distance_to(tip) * 0.42, 0.0052)
		_fang(st, tip - d * 0.012, d, 0.034 if n.contains("Thumb") else 0.046, r, Vector3(0, -0.012, 0.004), true)
		var at := BoneAttachment3D.new()
		skel.add_child(at)
		at.bone_idx = p
		var mi := MeshInstance3D.new()
		mi.mesh = _finish(st)
		mi.material_override = bone
		mi.transform = skel.get_bone_global_rest(p).affine_inverse()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		at.add_child(mi)
		at.visible = false
		_claws.append(at)

static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()

# A curved cone from `root`, `len` long along `dir`, bending toward `bend` at the tip: yellowed and dark
# at the root, bone-white at the point (a claw is the other way about: black at the point).
func _fang(st: SurfaceTool, root: Vector3, dir: Vector3, len: float, r: float, bend: Vector3, claw := false) -> void:
	const RINGS := 7
	const SIDES := 8
	var d := dir.normalized()
	var u := d.cross(Vector3.BACK).normalized()
	if u.length() < 0.5:
		u = d.cross(Vector3.RIGHT).normalized()
	var v := d.cross(u).normalized()
	var pts: Array = []
	var cols: Array = []
	var stain := _rng.randf_range(0.0, 0.5)
	for i in RINGS + 1:
		var t := float(i) / RINGS
		var c := root + d * len * t + bend * t * t
		var rad := r * pow(1.0 - t, 0.75) + 0.00012
		var ring: Array = []
		for k in SIDES:
			var a := TAU * k / SIDES
			ring.append(c + (u * cos(a) * 1.15 + v * sin(a)) * rad)
		pts.append(ring)
		if claw:
			cols.append(Color(0.42, 0.34, 0.26).lerp(Color(0.05, 0.035, 0.03), smoothstep(0.1, 0.85, t)))
		else:
			var tooth := Color(0.93, 0.87, 0.7).lerp(Color(0.74, 0.63, 0.41), stain)
			cols.append(Color(0.2, 0.06, 0.05).lerp(tooth, smoothstep(0.0, 0.42, t)))
	for i in RINGS:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			for e: Array in [[i, k], [i + 1, k], [i + 1, k2], [i, k], [i + 1, k2], [i, k2]]:
				st.set_color(cols[e[0]])
				st.add_vertex(pts[e[0]][e[1]])

func _apply() -> void:
	if body == null or _mats.is_empty():
		return
	var a := clampf(amount, 0.0, 1.0)
	var g := clampf(gape, 0.0, 1.0)
	var s := clampf(smile, 0.0, 1.0)
	var w := g * JAW
	if a > 0.0 or g > 0.0 or s > 0.0:
		body.face_weights = {"jaw_open": w, "lips_wide": maxf(g * WIDE, s * 1.9), "angry": a * 1.3 * (1.0 - s * 0.7),
				"smile": s * 1.5, "surprised": g * 0.7}
	else:
		body.face_weights = {}
	_set_all("amount", a)
	_set_all("grin", g)
	_maw.visible = a > 0.01 or g > 0.01
	_inner.visible = g > 0.02
	_jaw.rotation.x = deg_to_rad(JAW_STEP) * w
	for at in _claws:
		at.visible = a > 0.5

func _process(delta: float) -> void:
	if _mats.is_empty() or body._skel == null or (amount <= 0.0 and gape <= 0.0):
		return
	_time += delta
	var skel := body._skel
	var xf := skel.global_transform
	var head_now := xf * skel.get_bone_global_pose(_head)
	# (rest -> world for the head, and both ways for the hands)
	var to_world := head_now * _head_rest.affine_inverse()
	_set_all("head_inv", to_world.affine_inverse())
	_set_all("head_now", to_world)
	if _hand_l >= 0 and _hand_r >= 0:
		_set_all("hand_l_inv", _rest_l * (xf * skel.get_bone_global_pose(_hand_l)).affine_inverse())
		_set_all("hand_r_inv", _rest_r * (xf * skel.get_bone_global_pose(_hand_r)).affine_inverse())
	var ph := fposmod(_time * BEAT, 1.0)
	_set_all("beat", maxf(exp(-ph * 9.0), 0.7 * exp(-absf(ph - 0.22) * 14.0)))
	_stare(delta, to_world)
	_spit()

# The eyes on what they are told to look at, in the darting way of something very awake.
func _stare(delta: float, to_world: Transform3D) -> void:
	if _eyes.is_empty():
		return
	_sacc_t -= delta
	if _sacc_t <= 0.0:
		_sacc_t = _rng.randf_range(0.09, 0.6)
		_saccade = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * 0.06
	var a := clampf(amount, 0.0, 1.0)
	var inv := to_world.affine_inverse()
	for e: Dictionary in _eyes:
		var mi: MeshInstance3D = e.node
		mi.position = (e.at as Vector3) + Vector3(0, 0, -0.011 * (1.0 - a))     # (they come up as the lids go back)
		var look := Vector3.BACK
		if stare_at and is_instance_valid(stare_at):
			look = (inv * stare_at.global_position - mi.position).normalized()
		look = (look + Vector3(_saccade.x, _saccade.y, 0)).normalized()
		look = Vector3.BACK.slerp(look, 0.6 / maxf(Vector3.BACK.angle_to(look), 0.6))          # (no further round than an eye goes)
		mi.basis = Basis.looking_at(look, Vector3.UP, true).scaled(Vector3.ONE * float(e.r))
		(e.mat as ShaderMaterial).set_shader_parameter("pupil", pupil)

func _spit() -> void:
	_drool.clear_surfaces()
	if gape < 0.25:
		return
	const STEPS := 8
	var jaw := _jaw.transform
	_drool.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: Array in _drool_ends:
		var a: Vector3 = s[0]
		var b: Vector3 = jaw * (s[1] as Vector3)
		var sway := sin(_time * 3.1 + float(s[3])) * 0.0016
		var last_l := Vector3.ZERO
		var last_r := Vector3.ZERO
		for i in STEPS + 1:
			var t := float(i) / STEPS
			var p := a.lerp(b, t) + Vector3(sway * sin(t * PI), -float(s[2]) * 4.0 * t * (1.0 - t), 0.002)
			var w := 0.00028 + 0.0011 * pow(absf(t * 2.0 - 1.0), 2.4)
			var l := p + Vector3(-w, 0, 0)
			var r := p + Vector3(w, 0, 0)
			if i > 0:
				for v: Vector3 in [last_l, last_r, r, last_l, r, l]:
					_drool.surface_add_vertex(v)
			last_l = l
			last_r = r
	_drool.surface_end()
