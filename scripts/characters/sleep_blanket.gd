class_name SleepBlanket
extends MeshInstance3D
## A wool blanket over a sleeper's bed (a child of the bed's marker: x across the bed, z along it with
## the pillow at +z, y up, origin on the floor at the bed's middle). Its shape is worked out from the
## body under it - capsules round the sleeper's bones, where they really are - so it shows shoulders,
## hips and drawn-up knees, rises and falls with the breathing, and follows the legs out as the sleeper
## gets up. `fold` (0..1) throws its top part back over the hinge at the thighs, as one throws a blanket
## off; once the body has gone it settles, rumpled.

const NU := 64                       # rows along the bed
const NV := 30                       # columns across it
const U0 := -1.02                    # foot end of the cloth (past the bed's end; it hangs over)
const U1 := 0.57                     # top edge, at the sleeper's neck (the head lies on the pillow)
const V_HALF := 0.47                 # half the cloth's width (the bed is 0.80 wide)
const BED_HALF := 0.38               # where the mattress edge rounds over
const FOOT := -0.95                  # where the foot end rounds over
const MATTRESS := 0.548              # mattress top (the bed model at its game scale)
const HINGE := 0.75                  # the fold's hinge, this far below the top edge
const THICK := 0.022
## How steeply the cloth falls away from the body to the mattress (rise per run): a blanket over a
## sleeper slopes down its sides like a tent, it doesn't drop straight down beside the body.
const DRAPE := 0.85

var body: TalkingCharacter           # the sleeper (null: an empty, made bed)
var fold := 0.0
var disturbed := 0.0                 # 0 made, 1 slept in and thrown about (rumples)
var lively := false                  # rebuild every frame (while someone is getting up)
var _h := PackedFloat32Array()       # current height of each grid point (settles toward the target)
var _t := 0.0
var _acc := 0.0
var _noise := PackedFloat32Array()
var _skel: Skeleton3D

# Performance: the shape is only worked out where it can be seen (near the camera, on screen), and
# at most one blanket per frame does it; everything that never changes is computed once, shared.
const VIEW_DIST := 12.0
static var _claimed_frame := -1
static var _UV := PackedVector2Array()      # grid point -> (v, u)
static var _BASE := PackedFloat32Array()    # grid point -> bed height under it
static var _N8 := PackedInt32Array()        # 8 neighbours per point (-1 = none)
static var _N4 := PackedInt32Array()        # 4 neighbours per point (-1 = none)
static var _IDX := PackedInt32Array()
static var _UVS := PackedVector2Array()
static var _COLS := PackedColorArray()

func _init_static() -> void:
	if not _UV.is_empty():
		return
	_UV.resize(NU * NV)
	_BASE.resize(NU * NV)
	_N8.resize(NU * NV * 8)
	_N4.resize(NU * NV * 4)
	var d8: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	for iu in NU:
		for iv in NV:
			var i := iu * NV + iv
			_UV[i] = Vector2(lerpf(-V_HALF, V_HALF, float(iv) / (NV - 1)), lerpf(U0, U1, float(iu) / (NU - 1)))
			_BASE[i] = _base(_UV[i].x, _UV[i].y)
			for k in 8:
				var u: int = iu + d8[k].y
				var v: int = iv + d8[k].x
				var n := u * NV + v if (u >= 0 and u < NU and v >= 0 and v < NV) else -1
				_N8[i * 8 + k] = n
				if k < 4:
					_N4[i * 4 + k] = n
	_UVS.resize(NU * NV)
	_COLS.resize(NU * NV)
	var white := Color(0.86, 0.85, 0.81)
	var wool := Color(0.40, 0.45, 0.33)                 # (the green of the bed's own blanket)
	for iu in NU:
		for iv in NV:
			var i := iu * NV + iv
			_UVS[i] = Vector2(float(iv) / (NV - 1) * 2.0, float(iu) / (NU - 1) * 3.5)
			var u := lerpf(U0, U1, float(iu) / (NU - 1))
			_COLS[i] = white if u > U1 - 0.09 else wool          # (the sheet turned down over the top)
	for iu in NU - 1:
		for iv in NV - 1:
			var a := iu * NV + iv
			_IDX.append_array([a, a + 1, a + NV, a + 1, a + NV + 1, a + NV])

# Close enough to the camera, and on screen, for its breathing to be seen?
func _in_view() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	var d := cam.global_position.distance_to(global_position)
	if d > VIEW_DIST:
		return false
	if d < 2.5:
		return true
	var along := global_basis.z.normalized() * 0.9
	var up := Vector3(0, MATTRESS, 0)
	return cam.is_position_in_frustum(global_position + up) or cam.is_position_in_frustum(global_position + up + along) \
			or cam.is_position_in_frustum(global_position + up - along)

func _ready() -> void:
	_init_static()
	_h.resize(NU * NV)
	_noise.resize(NU * NV)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_path())
	for i in NU * NV:
		_noise[i] = rng.randf_range(-1.0, 1.0)
	for k in 3:                                         # (a soft lumpiness, not grain)
		_noise = _blur(_noise)
	for i in NU * NV:
		_h[i] = _target_base(i)
	material_override = _material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_rebuild(1.0)

func set_body(b: TalkingCharacter) -> void:
	body = b
	_skel = null
	_samples.clear()

func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if not lively:
		if _acc < 0.1:                                  # (asleep: breathing is slow, 10 updates a second)
			return
		if not _in_view():                              # (unseen: no need to breathe)
			return
		var f := Engine.get_process_frames()
		if _claimed_frame == f:                         # (one blanket a frame; the others next frame)
			return
		_claimed_frame = f
	var dt := _acc
	_acc = 0.0
	# (while someone moves under it the cloth keeps up with the body, or a knee would come through it)
	_rebuild(clampf(dt * (18.0 if lively else 3.0), 0.0, 1.0))

# ————— the shape —————

func _uv(i: int) -> Vector2:
	return _UV[i]

# The bed under the cloth: mattress, the folded blanket at the foot, the rounded edges.
func _base(v: float, u: float) -> float:
	var y := MATTRESS
	y += 0.035 * _bump(u, -0.84, -0.47, 0.05)          # (the bed's own folded blanket)
	y += 0.11 * _bump(u, 0.60, 0.84, 0.04) * (1.0 - smoothstep(0.25, 0.36, absf(v)))   # (the pillow)
	var ev := maxf(absf(v) - BED_HALF, 0.0)
	var eu := maxf(FOOT - u, 0.0)
	return y - 0.9 * ev - 0.9 * eu

func _bump(x: float, a: float, b: float, soft: float) -> float:
	return smoothstep(a - soft, a + soft, x) * (1.0 - smoothstep(b - soft, b + soft, x))

func _target_base(i: int) -> float:
	return _BASE[i] + THICK

# The body's skin, a sample of its vertices with their bone binds, posed on the CPU (the GPU's skinning
# can't be read back): [mesh skin, skeleton, PackedVector3Array rest, PackedInt32Array binds (2 a vertex),
# PackedFloat32Array weights].
var _samples: Array = []

func _gather() -> void:
	_samples.clear()
	_skel = null
	if body == null or not is_instance_valid(body):
		return
	var sk := body.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	_skel = sk[0]
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin == null:
			continue
		var skin := mi.skin
		var bind_bone := PackedInt32Array()
		var head_bind := {}                             # (the head stays out, on the pillow)
		for k in skin.get_bind_count():
			var bn := skin.get_bind_bone(k)
			if bn < 0:
				bn = _skel.find_bone(skin.get_bind_name(k))
			bind_bone.append(bn)
			if bn >= 0 and ("Head" in _skel.get_bone_name(bn) or "Neck" in _skel.get_bone_name(bn)):
				head_bind[k] = true
		var rest := PackedVector3Array()
		var binds := PackedInt32Array()
		var wts := PackedFloat32Array()
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			if bo.is_empty():
				continue
			var per := bo.size() / v.size()
			var stride := maxi(1, v.size() / 2500)
			for i in range(0, v.size(), stride):
				# the two strongest binds
				var b0 := 0
				var b1 := 0
				var w0 := -1.0
				var w1 := -1.0
				for j in per:
					var w := we[i * per + j]
					if w > w0:
						b1 = b0; w1 = w0; b0 = bo[i * per + j]; w0 = w
					elif w > w1:
						b1 = bo[i * per + j]; w1 = w
				if head_bind.has(b0):
					continue
				var tot := maxf(w0 + maxf(w1, 0.0), 1e-6)
				rest.append(v[i])
				binds.append_array([b0, b1])
				wts.append_array([w0 / tot, maxf(w1, 0.0) / tot])
		_samples.append([skin, bind_bone, rest, binds, wts])

# Height of the body's top over each grid point (0 where there is none).
func _body_field() -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(NU * NV)
	if body == null or not is_instance_valid(body):
		return f
	if _samples.is_empty():
		_gather()
	if _skel == null:
		return f
	var to_me := global_transform.affine_inverse() * _skel.global_transform
	for smp in _samples:
		var skin: Skin = smp[0]
		var bind_bone: PackedInt32Array = smp[1]
		var rest: PackedVector3Array = smp[2]
		var binds: PackedInt32Array = smp[3]
		var wts: PackedFloat32Array = smp[4]
		var mats: Array[Transform3D] = []
		for k in skin.get_bind_count():
			var bn := bind_bone[k]
			mats.append(to_me * (_skel.get_bone_global_pose(bn) if bn >= 0 else Transform3D.IDENTITY) * skin.get_bind_pose(k))
		for i in rest.size():
			var p: Vector3 = mats[binds[2 * i]] * rest[i] * wts[2 * i] + mats[binds[2 * i + 1]] * rest[i] * wts[2 * i + 1]
			if absf(p.x) > BED_HALF + 0.01 or p.z < FOOT or p.z > U1 or p.y > MATTRESS + 0.45:   # (sat up: not under it)
				continue
			var iu := int(round((p.z - U0) / (U1 - U0) * (NU - 1)))
			var iv := int(round((p.x + V_HALF) / (2.0 * V_HALF) * (NV - 1)))
			var k2 := iu * NV + iv
			if p.y > f[k2]:
				f[k2] = p.y
	# (a sample, not every vertex: close the gaps between the samples)
	var g := f.duplicate()
	for i in NU * NV:
		var m := f[i]
		for k in 8:
			var n := _N8[i * 8 + k]
			if n >= 0:
				m = maxf(m, f[n] - 0.01)
		g[i] = m
	# breathing: the chest (the part of the body nearest the pillow) rises and falls a little
	var br := 0.012 * sin(_t * 1.25)
	for i in NU * NV:
		if g[i] > 0.0:
			g[i] += br * smoothstep(-0.3, 0.2, _UV[i].y)
	return g

func _dilate(a: PackedFloat32Array) -> PackedFloat32Array:
	var o := a.duplicate()
	for i in NU * NV:
		var m := a[i]
		for k in 4:
			var n := _N4[i * 4 + k]
			if n >= 0:
				m = maxf(m, a[n])
		o[i] = m
	return o

# Every point at least as high as the body's top nearby less DRAPE times the distance to it (two
# chamfer passes over the grid: a cone round each high point, all merged).
func _drape(a: PackedFloat32Array) -> PackedFloat32Array:
	var o := a.duplicate()
	var sv := DRAPE * 2.0 * V_HALF / (NV - 1)
	var su := DRAPE * (U1 - U0) / (NU - 1)
	var sd := sqrt(sv * sv + su * su)
	for iu in NU:
		for iv in NV:
			var i := iu * NV + iv
			var m := o[i]
			if iv > 0:
				m = maxf(m, o[i - 1] - sv)
			if iu > 0:
				m = maxf(m, o[i - NV] - su)
				if iv > 0:
					m = maxf(m, o[i - NV - 1] - sd)
				if iv < NV - 1:
					m = maxf(m, o[i - NV + 1] - sd)
			o[i] = m
	for iu in range(NU - 1, -1, -1):
		for iv in range(NV - 1, -1, -1):
			var i := iu * NV + iv
			var m := o[i]
			if iv < NV - 1:
				m = maxf(m, o[i + 1] - sv)
			if iu < NU - 1:
				m = maxf(m, o[i + NV] - su)
				if iv < NV - 1:
					m = maxf(m, o[i + NV + 1] - sd)
				if iv > 0:
					m = maxf(m, o[i + NV - 1] - sd)
			o[i] = m
	return o

func _blur(a: PackedFloat32Array) -> PackedFloat32Array:
	var o := a.duplicate()
	for i in NU * NV:
		var s := a[i]
		var c := 1
		for k in 4:
			var n := _N4[i * 4 + k]
			if n >= 0:
				s += a[n]
				c += 1
		o[i] = s / c
	return o

func _rebuild(rate: float) -> void:
	# The cloth lies on the bed and over the body, stiff enough to bridge the hollows between limbs.
	var bf := _body_field()
	var ex := PackedFloat32Array()
	ex.resize(NU * NV)
	for i in NU * NV:
		ex[i] = maxf(bf[i] + 0.028 - _BASE[i], 0.0)
	# (cloth: it can't follow into narrow gaps or hug the body's sides - it bridges them and falls
	# away to the mattress on a slope, then rounds off)
	var cl := _drape(_dilate(ex))
	var sm := _blur(_blur(cl))
	var ex1 := _blur(ex)
	for i in NU * NV:
		var b := _BASE[i]
		var tgt := b + THICK + maxf(sm[i], ex1[i]) + disturbed * 0.018 * _noise[i]
		# the top edge drapes down round the neck onto the sheet, not cut off at shoulder height
		tgt = lerpf(tgt, b + THICK + 0.04, 0.55 * smoothstep(U1 - 0.10, U1, _UV[i].y))
		_h[i] = lerpf(_h[i], tgt, rate)
	_build_mesh()

# ————— the mesh —————

func _point(i: int) -> Vector3:
	var p := _uv(i)
	var x := p.x
	var z := p.y
	var y := _h[i]
	# the overhang hangs down (sides and foot), close to the bed
	var sv := clampf((absf(x) - BED_HALF) / (V_HALF - BED_HALF), 0.0, 1.0)
	var droop := 0.17 * pow(sv, 1.3)
	if sv > 0.0:
		x = signf(x) * (BED_HALF + 0.045 * sin(sv * PI * 0.5))
		y -= droop
	var su := clampf((FOOT - z) / (FOOT - U0), 0.0, 1.0)
	if su > 0.0:
		z = FOOT - 0.045 * sin(su * PI * 0.5)
		y -= 0.17 * pow(su, 1.3)
	# thrown back: a rolling fold - the crease starts at the top edge and runs down to the hinge;
	# what has gone over it lies doubled back on the rest, with a round crease between
	var hu := U1 - HINGE
	if fold > 0.0 and p.y > hu:
		var fl := lerpf(U1, hu, smoothstep(0.0, 1.0, fold))    # where the crease is now
		var d := p.y - fl
		if d > 0.0:
			var r := 0.035                                    # the crease's radius
			var under := _h[_row_at(fl, i % NV)]
			if d < PI * r:
				var a := d / r
				z = fl + r * sin(a)
				y = under + r * (1.0 - cos(a))
			else:
				z = fl - (d - PI * r)
				y = maxf(_h[_row_at(z, i % NV)], under) + 2.0 * r
			y -= droop                                    # (its sides hang over the bed's edge too)
			y = maxf(y, _base(x, z) + THICK)
	return Vector3(x, y, z)

func _row_at(u: float, iv: int) -> int:
	var iu := clampi(int(round((u - U0) / (U1 - U0) * (NU - 1))), 0, NU - 1)
	return iu * NV + iv

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	verts.resize(NU * NV)
	for i in NU * NV:
		verts[i] = _point(i)
	var normals := PackedVector3Array()
	normals.resize(NU * NV)
	for iu in NU:
		for iv in NV:
			var i := iu * NV + iv
			var ea := verts[mini(iu + 1, NU - 1) * NV + iv] - verts[maxi(iu - 1, 0) * NV + iv]
			var eb := verts[iu * NV + mini(iv + 1, NV - 1)] - verts[iu * NV + maxi(iv - 1, 0)]
			normals[i] = ea.cross(eb).normalized()
	var uvs := _UVS
	var cols := _COLS
	var idx := _IDX
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := mesh as ArrayMesh
	if m == null:
		m = ArrayMesh.new()
		mesh = m
	m.clear_surfaces()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

static var _mat: StandardMaterial3D

func _material() -> StandardMaterial3D:
	if _mat:
		return _mat
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.95
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.09
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	tex.color_ramp = Gradient.new()
	tex.color_ramp.set_color(0, Color(0.82, 0.82, 0.82))
	tex.color_ramp.set_color(1, Color(1, 1, 1))
	_mat.albedo_texture = tex
	_mat.uv1_scale = Vector3(4, 4, 1)
	return _mat
