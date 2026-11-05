class_name Buildings
extends RefCounted
## Bohemian village and railway buildings, built procedurally:
##   house()   — plastered cottage or two-storey house: pastel walls, steep tiled roof (gabled or
##               half-hipped), snow on it, chimney, shuttered windows, some of them lit at night
##   church()  — baroque village church: nave, apse, front tower with an onion dome and lantern
##   station() — k.u.k.-style station: two-storey Schönbrunn-yellow building with white
##               pilasters and cornices, single-storey wings, platform canopy on cast-iron columns,
##               lamps, benches, station bell, clock, name boards
##   halt()    — request halt where the train does not stop: short platform, timber shelter, board
## All return a Node3D whose local -Z faces the track (+X along the line) unless noted.

const SNOW_COVER := preload("res://shaders/world/snow_cover.gdshader")
const FONT_PATH := "res://assets/fonts/Oswald.ttf"

const WALL_COLOURS: Array[Color] = [Color(0.93, 0.9, 0.82), Color(0.91, 0.8, 0.55), Color(0.87, 0.72, 0.62),
		Color(0.8, 0.84, 0.76), Color(0.94, 0.93, 0.9), Color(0.86, 0.66, 0.45), Color(0.78, 0.8, 0.86)]
const SCHONBRUNN := Color(0.92, 0.74, 0.32)
const TRIM := Color(0.95, 0.94, 0.9)

static var _mats := {}
static var _mutex := Mutex.new()

# ————— materials —————

static func mat(key: String) -> Material:
	_mutex.lock()
	var m: Material = _mats.get(key)
	if m == null:
		var sm := ShaderMaterial.new()
		sm.shader = SNOW_COVER
		match key:
			"wall":         # colour comes from the vertex colour
				sm.set_shader_parameter("snow_amount", 0.15)
				sm.set_shader_parameter("roughness", 0.95)
			"roof":
				sm.set_shader_parameter("base", Color(0.36, 0.17, 0.12))
				sm.set_shader_parameter("snow_amount", 0.88)
				sm.set_shader_parameter("snow_sharp", 0.08)
			"roof_dark":
				sm.set_shader_parameter("base", Color(0.15, 0.15, 0.17))
				sm.set_shader_parameter("snow_amount", 0.85)
				sm.set_shader_parameter("snow_sharp", 0.08)
			"wood":
				sm.set_shader_parameter("base", Color(0.32, 0.22, 0.14))
				sm.set_shader_parameter("snow_amount", 0.4)
				sm.set_shader_parameter("grain", 1)
			"wood_green":
				sm.set_shader_parameter("base", Color(0.16, 0.27, 0.19))
				sm.set_shader_parameter("snow_amount", 0.4)
				sm.set_shader_parameter("grain", 1)
			"iron":
				sm.set_shader_parameter("base", Color(0.1, 0.13, 0.11))
				sm.set_shader_parameter("snow_amount", 0.5)
				sm.set_shader_parameter("roughness", 0.6)
				sm.set_shader_parameter("metallic_v", 0.4)
			"copper":       # verdigris onion domes
				sm.set_shader_parameter("base", Color(0.3, 0.5, 0.42))
				sm.set_shader_parameter("snow_amount", 0.55)
				sm.set_shader_parameter("roughness", 0.55)
				sm.set_shader_parameter("metallic_v", 0.3)
			"stone":
				sm.set_shader_parameter("base", Color(0.55, 0.53, 0.5))
				sm.set_shader_parameter("snow_amount", 0.75)
			"platform":
				sm.set_shader_parameter("base", Color(0.42, 0.4, 0.38))
				sm.set_shader_parameter("snow_amount", 0.65)
				sm.set_shader_parameter("snow_sharp", 0.4)
		match key:
			"glass_lit":
				var g := StandardMaterial3D.new()
				g.albedo_color = Color(0.2, 0.12, 0.05)
				g.emission_enabled = true
				g.emission = Color(1.0, 0.55, 0.2)
				g.emission_energy_multiplier = 0.55
				m = g
			"glass_dark":
				var g2 := StandardMaterial3D.new()
				g2.albedo_color = Color(0.025, 0.03, 0.04)
				g2.metallic = 0.0
				g2.roughness = 0.45
				g2.metallic_specular = 0.12
				m = g2
			"lamp":
				var l := StandardMaterial3D.new()
				l.albedo_color = Color(1, 0.9, 0.7)
				l.emission_enabled = true
				l.emission = Color(1.0, 0.78, 0.45)
				l.emission_energy_multiplier = 1.6
				m = l
			"enamel":
				var e := StandardMaterial3D.new()
				e.albedo_color = Color(0.93, 0.92, 0.88)
				e.roughness = 0.25
				m = e
			"gold":
				var au := StandardMaterial3D.new()
				au.albedo_color = Color(0.8, 0.62, 0.25)
				au.metallic = 0.9
				au.roughness = 0.3
				m = au
		if m == null:
			m = sm
		elif m is BaseMaterial3D:
			(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	_mutex.unlock()
	return m

# ————— mesh helpers (SurfaceTool with vertex colour; alpha = snow allowed) —————

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	SceneryMeshes.st_tri(st, a, b, c, col)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)

static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for i in 8:
		p.append(c + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	_quad(st, p[0], p[1], p[3], p[2], col)
	_quad(st, p[4], p[6], p[7], p[5], col)
	_quad(st, p[0], p[2], p[6], p[4], col)
	_quad(st, p[1], p[5], p[7], p[3], col)
	_quad(st, p[0], p[4], p[5], p[1], col)
	_quad(st, p[2], p[3], p[7], p[6], col)

static func _commit(parent: Node3D, st: SurfaceTool, mesh_name: String, material: Material, shadows := true) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = st.commit()
	mi.material_override = material
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# Lathe: revolve profile points (radius, y) about Y.
static func _lathe(st: SurfaceTool, prof: Array, segs: int, col: Color, base := Vector3.ZERO) -> void:
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for k in segs:
			var t0 := TAU * k / segs
			var t1 := TAU * (k + 1) / segs
			var a0 := base + Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var a1 := base + Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var b0 := base + Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var b1 := base + Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			_quad(st, a0, b0, b1, a1, col)

# ————— walls with windows —————

# Rectangular block of walls (no roof) w along X, d along Z, height h, base at y 0. Windows are
# laid out on every face: `rows` storeys, about one window per 2.6 m. Returns window centres
# (with their outward normals) so the caller can decorate them.
static func _walls(st: SurfaceTool, w: float, d: float, h: float, col: Color) -> void:
	_box(st, Vector3(0, h * 0.5, 0), Vector3(w, h, d), Color(col.r, col.g, col.b, 0.3))
	# Plinth: a darker band at the foot.
	var pc := Color(col.r * 0.62, col.g * 0.6, col.b * 0.58, 0.6)
	_box(st, Vector3(0, 0.3, 0), Vector3(w + 0.08, 0.6, d + 0.08), pc)

static func _windows(parent: Node3D, rng: RandomNumberGenerator, w: float, d: float, storeys: int, storey_h: float,
		lit_chance: float, trim: Color, shutters: bool, arched := false) -> void:
	var frames := _new_st()
	var lit := _new_st()
	var dark := _new_st()
	var shut := _new_st()
	var counts := [0, 0, 0]          # lit, dark, shutters
	var faces := [[Vector3(0, 0, -1), w, d], [Vector3(0, 0, 1), w, d], [Vector3(-1, 0, 0), d, w], [Vector3(1, 0, 0), d, w]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var face_w: float = f[1]
		var depth: float = f[2]
		var count := int(floor((face_w - 1.2) / 2.6))
		if count < 1:
			continue
		var along := Vector3.UP.cross(n)          # along the face (right-handed with UP and n)
		for s in storeys:
			for i in count:
				var u := (float(i) + 0.5) / count - 0.5
				var c := n * (depth * 0.5 + 0.01) + along * (u * (face_w - 1.4)) + Vector3(0, s * storey_h + storey_h * 0.55, 0)
				var ww := 0.85
				var wh := 1.25 if not arched else 1.6
				var b := Basis(along, Vector3.UP, n)
				# Plaster surround, sill, then the glass (lit or dark) with glazing bars.
				_box(frames, c + n * 0.015, Vector3(ww + 0.2, wh + 0.22, 0.04), Color(trim.r, trim.g, trim.b, 0.0), b)
				_box(frames, c + Vector3(0, -wh * 0.5 - 0.12, 0) + n * 0.06, Vector3(ww + 0.3, 0.07, 0.14), Color(trim.r, trim.g, trim.b, 1.0), b)
				var is_lit := rng.randf() < lit_chance
				var g := lit if is_lit else dark
				counts[0 if is_lit else 1] += 1
				_box(g, c + n * 0.04, Vector3(ww, wh, 0.02), Color.WHITE, b)
				var bar := Color(0.92, 0.9, 0.85, 0.0)
				_box(frames, c + n * 0.055, Vector3(0.05, wh, 0.02), bar, b)
				_box(frames, c + n * 0.055 + Vector3(0, wh * 0.18, 0), Vector3(ww, 0.05, 0.02), bar, b)
				if shutters and not is_lit:
					var sc := Color(0.18, 0.32, 0.22, 0.0) if rng.randf() < 0.6 else Color(0.38, 0.22, 0.14, 0.0)
					counts[2] += 1
					for side: float in [-1.0, 1.0]:
						_box(shut, c + n * 0.05 + along * side * (ww * 0.5 + 0.24), Vector3(0.42, wh, 0.04), sc, b)
	if counts[0] + counts[1] == 0:
		return
	_commit(parent, frames, "WindowFrames", mat("wall"), false)
	if counts[0] > 0:
		_commit(parent, lit, "LitWindows", mat("glass_lit"), false)
	if counts[1] > 0:
		_commit(parent, dark, "DarkWindows", mat("glass_dark"), false)
	if counts[2] > 0:
		_commit(parent, shut, "Shutters", mat("wall"), false)

# ————— roofs —————

# Gabled (half_hip = 0) or half-hipped roof over a w × d block whose walls end at y = h. Ridge
# along X. `pitch` in radians, `over` = eaves overhang.
static func _roof(parent: Node3D, w: float, d: float, h: float, pitch: float, over: float, half_hip: float,
		wall_col: Color, roof_mat: String) -> float:
	var st := _new_st()
	var gable := _new_st()
	var hd := d * 0.5 + over
	var hw := w * 0.5 + over * 0.6
	var rise := (d * 0.5) * tan(pitch)
	var ridge_y := h + rise
	var eave_y := h - over * tan(pitch)
	# Half-hip: the gable is cut at fraction (1 - half_hip) of its height by a small hip slope.
	var cut_y := lerpf(ridge_y, h, half_hip)
	var inset := (ridge_y - cut_y) / tan(pitch + 0.25) if half_hip > 0.0 else 0.0
	var rx := hw - inset
	var roof_c := Color(1, 1, 1, 1)
	# Main slopes (front -Z, back +Z).
	for zs: float in [-1.0, 1.0]:
		var e0 := Vector3(-hw, eave_y, zs * hd)
		var e1 := Vector3(hw, eave_y, zs * hd)
		var r0 := Vector3(-rx, ridge_y, 0)
		var r1 := Vector3(rx, ridge_y, 0)
		if half_hip > 0.0:
			# The slope reaches the full width up to cut height, then narrows to the shorter ridge.
			var t := (cut_y - eave_y) / (ridge_y - eave_y)
			var m0 := Vector3(-hw, cut_y, zs * hd * (1.0 - t))
			var m1 := Vector3(hw, cut_y, zs * hd * (1.0 - t))
			if zs < 0:
				_quad(st, e0, m0, m1, e1, roof_c)
				_quad(st, m0, r0, r1, m1, roof_c)
			else:
				_quad(st, e1, m1, m0, e0, roof_c)
				_quad(st, m1, r1, r0, m0, roof_c)
		else:
			if zs < 0:
				_quad(st, e0, r0, r1, e1, roof_c)
			else:
				_quad(st, e1, r1, r0, e0, roof_c)
		# Thickness at the eaves (dark edge under the snow).
		_box(st, Vector3(0, eave_y - 0.06, zs * hd), Vector3(hw * 2.0, 0.12, 0.12), Color(1, 1, 1, 0.0))
	# Gable ends (wall-coloured) and the small hip slopes.
	for xs: float in [-1.0, 1.0]:
		var x := xs * w * 0.5
		var t2 := (cut_y - h) / (ridge_y - h)
		var gz := (d * 0.5) * (1.0 - t2)
		var gc := Color(wall_col.r, wall_col.g, wall_col.b, 0.0)
		if xs < 0:
			_quad(gable, Vector3(x, h, d * 0.5), Vector3(x, cut_y, gz), Vector3(x, cut_y, -gz), Vector3(x, h, -d * 0.5), gc)
		else:
			_quad(gable, Vector3(x, h, -d * 0.5), Vector3(x, cut_y, -gz), Vector3(x, cut_y, gz), Vector3(x, h, d * 0.5), gc)
		if half_hip > 0.0:
			var t := (cut_y - eave_y) / (ridge_y - eave_y)
			var mz := hd * (1.0 - t)
			var hx := xs * hw
			var tip := Vector3(xs * rx, ridge_y, 0)
			if xs < 0:
				_tri(st, Vector3(hx, cut_y, mz), tip, Vector3(hx, cut_y, -mz), roof_c)
			else:
				_tri(st, Vector3(hx, cut_y, -mz), tip, Vector3(hx, cut_y, mz), roof_c)
	_commit(parent, st, "Roof", mat(roof_mat))
	_commit(parent, gable, "Gables", mat("wall"))
	return ridge_y

static func _chimney(parent: Node3D, pos: Vector3, h: float) -> void:
	var st := _new_st()
	_box(st, pos + Vector3(0, h * 0.5, 0), Vector3(0.55, h, 0.55), Color(0.85, 0.8, 0.74, 0.2))
	_box(st, pos + Vector3(0, h + 0.05, 0), Vector3(0.7, 0.1, 0.7), Color(0.6, 0.55, 0.5, 1.0))
	_commit(parent, st, "Chimney", mat("wall"))

# ————— house —————

static func house(rng: RandomNumberGenerator, lit_chance: float = 0.4) -> Node3D:
	var n := Node3D.new()
	n.name = "House"
	var storeys := 2 if rng.randf() < 0.3 else 1
	var w := rng.randf_range(8.0, 13.0)
	var d := rng.randf_range(6.0, 8.0)
	var storey_h := 3.0
	var h := storeys * storey_h + 0.4
	var col := WALL_COLOURS[rng.randi() % WALL_COLOURS.size()]
	var st := _new_st()
	_walls(st, w, d, h, col)
	# Door on the front (-Z) with a step.
	_box(st, Vector3(rng.randf_range(-w * 0.25, w * 0.25), 1.1, -d * 0.5 - 0.03), Vector3(1.1, 2.2, 0.08), Color(0.3, 0.2, 0.13, 0.0))
	_box(st, Vector3(0, 0.08, -d * 0.5 - 0.5), Vector3(1.8, 0.16, 0.9), Color(0.6, 0.58, 0.55, 1.0))
	_commit(n, st, "Walls", mat("wall"))
	_windows(n, rng, w, d, storeys, storey_h, lit_chance, TRIM if rng.randf() < 0.7 else col.lightened(0.25), rng.randf() < 0.6)
	var pitch := deg_to_rad(rng.randf_range(44.0, 52.0))
	var half_hip := 0.28 if rng.randf() < 0.55 else 0.0
	var ridge := _roof(n, w, d, h, pitch, 0.45, half_hip, col, "roof" if rng.randf() < 0.75 else "roof_dark")
	if rng.randf() < 0.85:
		var cx := rng.randf_range(-w * 0.3, w * 0.3)
		_chimney(n, Vector3(cx, ridge - 1.2, rng.randf_range(-0.6, 0.6)), 1.9)
		n.set_meta("chimney_top", Vector3(cx, ridge + 0.8, 0))
	n.set_meta("size", Vector3(w, ridge, d))
	return n

# ————— church —————

static func church(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	n.name = "Church"
	var col := WALL_COLOURS[[0, 1, 4][rng.randi() % 3]]
	var nave_w := 20.0
	var nave_d := 11.0
	var nave_h := 9.0
	# Nave (along X) with arched windows, apse at +X, tower at -X.
	var nave := Node3D.new()
	nave.name = "Nave"
	n.add_child(nave)
	var st := _new_st()
	_walls(st, nave_w, nave_d, nave_h, col)
	# Pilasters.
	for i in 6:
		var x := lerpf(-nave_w * 0.5, nave_w * 0.5, i / 5.0)
		for zs: float in [-1.0, 1.0]:
			_box(st, Vector3(x, nave_h * 0.5, zs * (nave_d * 0.5 + 0.08)), Vector3(0.6, nave_h, 0.16), Color(TRIM.r, TRIM.g, TRIM.b, 0.2))
	_box(st, Vector3(0, nave_h - 0.25, 0), Vector3(nave_w + 0.4, 0.5, nave_d + 0.4), Color(TRIM.r, TRIM.g, TRIM.b, 1.0))
	_commit(nave, st, "Walls", mat("wall"))
	_windows(nave, rng, nave_w, nave_d, 1, 7.0, 0.3, TRIM, false, true)
	_roof(nave, nave_w, nave_d, nave_h, deg_to_rad(50.0), 0.5, 0.0, col, "roof_dark")
	# Apse: half-octagon drum.
	var ap := _new_st()
	var ar := nave_d * 0.42
	for k in 4:
		var a0 := -PI * 0.5 + PI * k / 4.0
		var a1 := -PI * 0.5 + PI * (k + 1) / 4.0
		var p0 := Vector3(nave_w * 0.5 + cos(a0) * ar, 0, sin(a0) * ar)
		var p1 := Vector3(nave_w * 0.5 + cos(a1) * ar, 0, sin(a1) * ar)
		_quad(ap, p0, p0 + Vector3(0, nave_h - 1.5, 0), p1 + Vector3(0, nave_h - 1.5, 0), p1, Color(col.r, col.g, col.b, 0.2))
		_tri(ap, p0 + Vector3(0, nave_h - 1.5, 0), Vector3(nave_w * 0.5, nave_h + 2.2, 0), p1 + Vector3(0, nave_h - 1.5, 0), Color(0.3, 0.3, 0.32, 1.0))
	_commit(n, ap, "Apse", mat("wall"))
	# Tower: square shaft, belfry stage with louvred openings, clock, onion dome, lantern, cross.
	var tw := 5.6
	var th := 21.0
	var tx := -nave_w * 0.5 - tw * 0.5 + 0.5
	var t := _new_st()
	_box(t, Vector3(tx, th * 0.5, 0), Vector3(tw, th, tw), Color(col.r, col.g, col.b, 0.2))
	for y: float in [nave_h - 0.25, th - 6.0, th - 0.2]:
		_box(t, Vector3(tx, y, 0), Vector3(tw + 0.35, 0.45, tw + 0.35), Color(TRIM.r, TRIM.g, TRIM.b, 1.0))
	for k in 4:
		var dir := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5))
		var b := Basis(Vector3.UP.cross(dir), Vector3.UP, dir)
		# Belfry opening (dark) with louvres, and a round clock face below it.
		_box(t, Vector3(tx, th - 3.0, 0) + dir * (tw * 0.5 + 0.02), Vector3(1.4, 2.6, 0.06), Color(0.08, 0.07, 0.07, 0.0), b)
		for j in 5:
			_box(t, Vector3(tx, th - 4.0 + j * 0.5, 0) + dir * (tw * 0.5 + 0.05), Vector3(1.4, 0.07, 0.1), Color(0.3, 0.22, 0.15, 0.0), b)
	_commit(n, t, "Tower", mat("wall"))
	for k in 4:
		var dir2 := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5))
		var face := MeshInstance3D.new()
		face.name = "ClockFace"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.85
		cm.bottom_radius = 0.85
		cm.height = 0.06
		cm.radial_segments = 24
		face.mesh = cm
		face.material_override = mat("enamel")
		face.position = Vector3(tx, th - 8.0, 0) + dir2 * (tw * 0.5 + 0.03)
		face.basis = Basis(Quaternion(Vector3.UP, dir2))
		n.add_child(face)
		var hands := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.07, 0.65, 0.02)
		hands.mesh = hm
		hands.material_override = mat("iron")
		hands.position = face.position + dir2 * 0.05 + Vector3(0, 0.25, 0)
		hands.basis = Basis(Vector3.UP.cross(dir2), Vector3.UP, dir2)
		n.add_child(hands)
	# Onion dome: bulb, neck, lantern, small bulb, spire and a gilded cross.
	var dome := _new_st()
	var top := th + 0.2
	var hr := tw * 0.5
	var prof := [Vector2(hr + 0.1, top), Vector2(hr * 0.75, top + 0.7), Vector2(hr * 0.95, top + 1.6),
			Vector2(hr * 0.98, top + 2.4), Vector2(hr * 0.8, top + 3.3), Vector2(hr * 0.45, top + 4.1),
			Vector2(0.38, top + 4.7), Vector2(0.38, top + 5.0)]
	_lathe(dome, prof, 24, Color(1, 1, 1, 1), Vector3(tx, 0, 0))
	var lantern := [Vector2(0.55, top + 5.0), Vector2(0.55, top + 6.4), Vector2(0.75, top + 6.5)]
	_lathe(dome, lantern, 12, Color(1, 1, 1, 0.3), Vector3(tx, 0, 0))
	var bulb2 := [Vector2(0.75, top + 6.5), Vector2(0.95, top + 7.0), Vector2(0.7, top + 7.6), Vector2(0.12, top + 8.3), Vector2(0.05, top + 9.4)]
	_lathe(dome, bulb2, 16, Color(1, 1, 1, 1), Vector3(tx, 0, 0))
	_commit(n, dome, "Dome", mat("copper"))
	var cross := _new_st()
	_box(cross, Vector3(tx, top + 10.0, 0), Vector3(0.08, 1.3, 0.08), Color(1, 1, 1, 0))
	_box(cross, Vector3(tx, top + 10.25, 0), Vector3(0.08, 0.08, 0.7), Color(1, 1, 1, 0))
	_commit(n, cross, "Cross", mat("gold"))
	n.set_meta("size", Vector3(nave_w + tw, top + 10.0, nave_d))
	return n

# ————— station —————

## Station building + platform + canopy + lamps for `st` (RouteData entry). Local frame: X along
## the train (world X), the track at z = 0, the platform on the station's side (st.side). The node
## is placed at the station's route position.
static func station(st: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(st.name)
	var n := Node3D.new()
	n.name = "Station_" + str(st.name)
	var side: float = st.side
	var plat_len: float = RouteData.PLATFORM_LEN
	var plat_w := 5.5
	var edge := 1.62
	var plat_y := 0.55
	_platform(n, plat_len, plat_w, edge, plat_y, side)
	# Building: centre block 2 storeys, wings 1 storey, facing the track.
	var bz := side * (edge + plat_w + 5.0)
	var bldg := Node3D.new()
	bldg.name = "StationBuilding"
	bldg.position = Vector3(rng.randf_range(-12.0, 12.0), plat_y - 0.05, bz)
	# Face the track: local -Z toward the platform.
	if side < 0:
		bldg.rotation.y = PI
	n.add_child(bldg)
	var cw := 16.0
	var cd := 10.0
	var storey := 3.6
	var stb := _new_st()
	_walls(stb, cw, cd, storey * 2.0 + 0.6, SCHONBRUNN)
	# White pilasters at the corners and between the bays, cornice between the floors and under
	# the roof, rusticated ground-floor band.
	for i in 5:
		var x := lerpf(-cw * 0.5 + 0.3, cw * 0.5 - 0.3, i / 4.0)
		for zs: float in [-1.0, 1.0]:
			_box(stb, Vector3(x, storey + 0.3, zs * (cd * 0.5 + 0.06)), Vector3(0.55, storey * 2.0, 0.12), Color(TRIM.r, TRIM.g, TRIM.b, 0.1))
	for y: float in [storey + 0.1, storey * 2.0 + 0.45]:
		_box(stb, Vector3(0, y, 0), Vector3(cw + 0.4, 0.32, cd + 0.4), Color(TRIM.r, TRIM.g, TRIM.b, 1.0))
	_commit(bldg, stb, "Walls", mat("wall"))
	_windows(bldg, rng, cw, cd, 2, storey, 0.75, TRIM, false, true)
	var ridge := _roof(bldg, cw, cd, storey * 2.0 + 0.6, deg_to_rad(38.0), 0.6, 0.45, SCHONBRUNN, "roof")
	_chimney(bldg, Vector3(-cw * 0.25, ridge - 1.6, 1.2), 2.2)
	_chimney(bldg, Vector3(cw * 0.25, ridge - 1.6, -1.2), 2.2)
	for xs: float in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "Wing"
		wing.position = Vector3(xs * (cw * 0.5 + 5.0), 0, 0.5)
		bldg.add_child(wing)
		var wst := _new_st()
		_walls(wst, 10.0, 8.0, storey + 0.4, SCHONBRUNN)
		_box(wst, Vector3(0, storey + 0.15, 0), Vector3(10.4, 0.28, 8.4), Color(TRIM.r, TRIM.g, TRIM.b, 1.0))
		_commit(wing, wst, "Walls", mat("wall"))
		_windows(wing, rng, 10.0, 8.0, 1, storey, 0.55, TRIM, false, true)
		_roof(wing, 10.0, 8.0, storey + 0.4, deg_to_rad(32.0), 0.5, 0.0, SCHONBRUNN, "roof")
	# Name on the facade (platform side) and a clock above the door.
	var font := _font()
	var nm := Label3D.new()
	nm.name = "FacadeName"
	nm.text = st.name
	nm.font = font
	nm.font_size = 160
	nm.pixel_size = 0.0045
	nm.modulate = Color(0.12, 0.1, 0.08)
	nm.outline_size = 0
	nm.shaded = true
	nm.double_sided = false
	nm.position = Vector3(0, storey * 2.0 + 0.05, -cd * 0.5 - 0.09)
	nm.rotation.y = PI
	bldg.add_child(nm)
	var clock := MeshInstance3D.new()
	clock.name = "Clock"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.45
	cm.height = 0.08
	clock.mesh = cm
	clock.material_override = mat("enamel")
	clock.rotation.x = PI * 0.5
	clock.position = Vector3(0, storey * 1.5 + 0.35, -cd * 0.5 - 0.12)
	bldg.add_child(clock)
	_canopy(bldg, cw + 20.0, -cd * 0.5, storey + 0.2)
	# Station bell (the k.u.k. "Läutewerk") on its post by the door.
	_bell(bldg, Vector3(cw * 0.5 + 1.4, 0, -cd * 0.5 - 2.6))
	# Benches under the canopy, lamps along the platform, boards at both ends.
	for i in 4:
		_bench(bldg, Vector3(-12.0 + i * 8.0, 0, -cd * 0.5 - 1.2))
	var lamp_count := int(plat_len / 18.0)
	for i in lamp_count:
		var x := lerpf(-plat_len * 0.5 + 8.0, plat_len * 0.5 - 8.0, float(i) / float(lamp_count - 1))
		var light := absf(x) > 22.0 and i % 2 == 0      # real light on every other lamp beyond the canopy
		_lamp_post(n, Vector3(x, plat_y, side * (edge + plat_w - 0.6)), light)
	for xs: float in [-1.0, 1.0]:
		_name_board(n, st.name, Vector3(xs * (plat_len * 0.5 - 4.0), plat_y, side * (edge + plat_w * 0.5)), font)
	n.set_meta("platform_side", side)
	return n

static func _platform(n: Node3D, len: float, w: float, edge: float, y: float, side: float) -> void:
	var st := _new_st()
	var zc := side * (edge + w * 0.5)
	# Body, coping stones along the edge, ramps at both ends.
	_box(st, Vector3(0, (y + Terrain.FORMATION_Y) * 0.5, zc), Vector3(len, y - Terrain.FORMATION_Y, w), Color(1, 1, 1, 1))
	_box(st, Vector3(0, y + 0.02, side * (edge + 0.3)), Vector3(len, 0.06, 0.6), Color(1.25, 1.22, 1.15, 1.0))
	for xs: float in [-1.0, 1.0]:
		var x0 := xs * len * 0.5
		var x1 := xs * (len * 0.5 + 6.0)
		var zi := side * edge
		var zo := side * (edge + w)
		var top0 := Vector3(x0, y, zi)
		var top1 := Vector3(x0, y, zo)
		var f := Terrain.FORMATION_Y
		if xs * side > 0:
			_quad(st, top0, Vector3(x1, f, zi), Vector3(x1, f, zo), top1, Color(1, 1, 1, 1))
		else:
			_quad(st, top0, top1, Vector3(x1, f, zo), Vector3(x1, f, zi), Color(1, 1, 1, 1))
	_commit(n, st, "Platform", mat("platform"))
	# Yellow-white edge line.
	var line := _new_st()
	_box(line, Vector3(0, y + 0.055, side * (edge + 0.75)), Vector3(len, 0.01, 0.08), Color(0.9, 0.85, 0.5, 0.0))
	_commit(n, line, "EdgeLine", mat("wall"), false)
	var body := StaticBody3D.new()
	body.set_meta("surface", "snow")          # footstep sounds
	body.name = "PlatformBody"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(len, y - Terrain.FORMATION_Y, w)
	cs.shape = bs
	cs.position = Vector3(0, (y + Terrain.FORMATION_Y) * 0.5, zc)
	body.add_child(cs)
	n.add_child(body)

# Canopy along the front (-Z face at z = face_z) of the building: a shallow roof on cast-iron
# columns with scrolled brackets and a fretted timber valance.
static func _canopy(parent: Node3D, len: float, face_z: float, h: float) -> void:
	var depth := 4.2
	var st := _new_st()
	var iron := _new_st()
	var z0 := face_z
	var z1 := face_z - depth
	var y0 := h + 0.5
	var y1 := h
	_quad(st, Vector3(-len * 0.5, y0, z0), Vector3(len * 0.5, y0, z0), Vector3(len * 0.5, y1, z1), Vector3(-len * 0.5, y1, z1), Color(1, 1, 1, 1))
	_quad(st, Vector3(-len * 0.5, y0 - 0.12, z0), Vector3(-len * 0.5, y1 - 0.12, z1), Vector3(len * 0.5, y1 - 0.12, z1), Vector3(len * 0.5, y0 - 0.12, z0), Color(0.75, 0.72, 0.66, 0.0))
	# Valance: saw-tooth boards along the front edge.
	var teeth := int(len / 0.22)
	for i in teeth:
		var x := -len * 0.5 + (i + 0.5) * (len / teeth)
		_tri(st, Vector3(x - 0.1, y1 - 0.05, z1 - 0.02), Vector3(x + 0.1, y1 - 0.05, z1 - 0.02), Vector3(x, y1 - 0.42, z1 - 0.02), Color(0.92, 0.9, 0.84, 0.0))
		_tri(st, Vector3(x + 0.1, y1 - 0.05, z1 - 0.02), Vector3(x - 0.1, y1 - 0.05, z1 - 0.02), Vector3(x, y1 - 0.42, z1 - 0.02), Color(0.92, 0.9, 0.84, 0.0))
	_box(st, Vector3(0, y1 - 0.1, z1), Vector3(len, 0.18, 0.06), Color(0.92, 0.9, 0.84, 0.0))
	var cols := int(len / 4.5)
	for i in cols + 1:
		var x := lerpf(-len * 0.5 + 0.6, len * 0.5 - 0.6, float(i) / cols)
		var cz := z1 + 0.35
		_lathe(iron, [Vector2(0.14, 0.0), Vector2(0.1, 0.35), Vector2(0.065, 0.5), Vector2(0.06, h - 0.45), Vector2(0.1, h - 0.3), Vector2(0.16, h - 0.12)], 10, Color(1, 1, 1, 0.0), Vector3(x, 0, cz))
		# Bracket: diagonal strut to the building and a scroll (ring) in the corner.
		var a := Vector3(x, h - 1.2, cz)
		var b := Vector3(x, h - 0.15, cz + 1.6)
		_box(iron, (a + b) * 0.5, Vector3(0.05, 0.08, a.distance_to(b)), Color(1, 1, 1, 0.0), Basis(Vector3.RIGHT, -atan2(b.y - a.y, b.z - a.z)))
		_box(iron, Vector3(x, h - 0.15, (z0 + z1) * 0.5), Vector3(0.06, 0.12, depth), Color(1, 1, 1, 0.0))
	_commit(parent, st, "Canopy", mat("wood_green"))
	_commit(parent, iron, "CanopyIron", mat("iron"))
	# Pendant lamps under the canopy.
	for i in 4:
		var x := lerpf(-len * 0.35, len * 0.35, i / 3.0)
		var bulb := MeshInstance3D.new()
		bulb.name = "CanopyLamp"
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		bulb.mesh = sm
		bulb.material_override = mat("lamp")
		bulb.position = Vector3(x, h - 0.55, (z0 + z1) * 0.5)
		parent.add_child(bulb)
		if i == 1 or i == 2:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.75, 0.45)
			l.light_energy = 1.6
			l.omni_range = 11.0
			l.omni_attenuation = 1.4
			l.position = bulb.position + Vector3(0, -0.2, 0)
			parent.add_child(l)

static func _lamp_post(parent: Node3D, base: Vector3, light: bool) -> void:
	var st := _new_st()
	_lathe(st, [Vector2(0.16, 0.0), Vector2(0.12, 0.3), Vector2(0.06, 0.45), Vector2(0.045, 3.4), Vector2(0.08, 3.5)], 8, Color(1, 1, 1, 0.0), base)
	# Lantern: four-sided glazed box with a cap.
	_box(st, base + Vector3(0, 3.62, 0), Vector3(0.36, 0.06, 0.36), Color(1, 1, 1, 0.0))
	_lathe(st, [Vector2(0.3, 4.12), Vector2(0.05, 4.4), Vector2(0.0, 4.45)], 4, Color(1, 1, 1, 1.0), base)
	_commit(parent, st, "LampPost", mat("iron"))
	var glass := MeshInstance3D.new()
	glass.name = "Lantern"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.45, 0.3)
	glass.mesh = bm
	glass.material_override = mat("lamp")
	glass.position = base + Vector3(0, 3.88, 0)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(glass)
	if light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 2.0
		l.omni_range = 14.0
		l.omni_attenuation = 1.3
		l.position = base + Vector3(0, 3.7, 0)
		parent.add_child(l)

static func _bench(parent: Node3D, p: Vector3) -> void:
	var st := _new_st()
	for i in 3:
		_box(st, p + Vector3(0, 0.45, -0.18 + i * 0.13), Vector3(1.8, 0.04, 0.1), Color(1, 1, 1, 1))
	for i in 3:
		_box(st, p + Vector3(0, 0.62 + i * 0.13, 0.15), Vector3(1.8, 0.1, 0.03), Color(1, 1, 1, 0.0))
	_commit(parent, st, "Bench", mat("wood"))
	var iron := _new_st()
	for xs: float in [-0.75, 0.75]:
		_box(iron, p + Vector3(xs, 0.22, 0), Vector3(0.05, 0.44, 0.45), Color(1, 1, 1, 0))
		_box(iron, p + Vector3(xs, 0.7, 0.16), Vector3(0.05, 0.55, 0.05), Color(1, 1, 1, 0))
	_commit(parent, iron, "BenchIron", mat("iron"))

static func _bell(parent: Node3D, p: Vector3) -> void:
	var st := _new_st()
	_lathe(st, [Vector2(0.09, 0.0), Vector2(0.07, 2.2)], 8, Color(1, 1, 1, 0), p)
	_box(st, p + Vector3(0, 2.3, 0), Vector3(0.5, 0.5, 0.35), Color(1, 1, 1, 0.3))
	_lathe(st, [Vector2(0.3, 2.55), Vector2(0.22, 2.7), Vector2(0.12, 2.95), Vector2(0.0, 3.0)], 12, Color(1, 1, 1, 1), p)
	_commit(parent, st, "StationBell", mat("wood_green"))
	var bell := _new_st()
	_lathe(bell, [Vector2(0.26, 2.42), Vector2(0.2, 2.5), Vector2(0.14, 2.62), Vector2(0.0, 2.66)], 14, Color(1, 1, 1, 0), p + Vector3(0, 0, -0.25))
	_commit(parent, bell, "Bell", mat("gold"))

static func _name_board(parent: Node3D, text: String, p: Vector3, font: Font) -> void:
	var st := _new_st()
	for xs: float in [-1.2, 1.2]:
		_box(st, p + Vector3(xs, 1.3, 0), Vector3(0.08, 2.6, 0.08), Color(1, 1, 1, 0.0))
	_box(st, p + Vector3(0, 2.55, 0), Vector3(2.9, 0.62, 0.06), Color(1, 1, 1, 1.0))
	_commit(parent, st, "BoardFrame", mat("iron"))
	var face := MeshInstance3D.new()
	face.name = "BoardFace"
	var bm := BoxMesh.new()
	bm.size = Vector3(2.75, 0.5, 0.075)
	face.mesh = bm
	face.material_override = mat("enamel")
	face.position = p + Vector3(0, 2.55, 0)
	parent.add_child(face)
	for zs: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.name = "BoardText"
		l.text = text
		l.font = font
		l.font_size = 96
		l.pixel_size = 0.0034 if text.length() < 11 else 0.0026
		l.modulate = Color(0.06, 0.06, 0.07)
		l.shaded = true
		l.double_sided = false
		l.position = p + Vector3(0, 2.55, zs * 0.04)
		l.rotation.y = 0.0 if zs > 0 else PI
		parent.add_child(l)

# ————— halt —————

static func halt(st: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(st.name)
	var n := Node3D.new()
	n.name = "Halt_" + str(st.name)
	var side: float = st.side
	var len: float = RouteData.HALT_PLATFORM_LEN
	var edge := 1.62
	var w := 3.0
	var y := 0.45
	_platform(n, len, w, edge, y, side)
	# Timber shelter, open to the track.
	var sh := Node3D.new()
	sh.name = "Shelter"
	sh.position = Vector3(rng.randf_range(-8.0, 8.0), y, side * (edge + w - 0.9))
	if side < 0:
		sh.rotation.y = PI
	n.add_child(sh)
	var s2 := _new_st()
	var sw := 4.0
	var sd := 1.6
	var shh := 2.4
	_box(s2, Vector3(0, shh * 0.5, sd * 0.5), Vector3(sw, shh, 0.08), Color(1, 1, 1, 0.0))
	for xs: float in [-1.0, 1.0]:
		_box(s2, Vector3(xs * sw * 0.5, shh * 0.5, 0), Vector3(0.08, shh, sd), Color(1, 1, 1, 0.0))
	_box(s2, Vector3(0, 0.45, sd * 0.25), Vector3(sw - 0.3, 0.05, 0.4), Color(1, 1, 1, 1.0))
	_commit(sh, s2, "Walls", mat("wood"))
	_roof(sh, sw, sd, shh, deg_to_rad(30.0), 0.35, 0.0, Color(0.32, 0.22, 0.14), "roof_dark")
	_lamp_post(n, Vector3(-len * 0.25, y, side * (edge + w - 0.4)), true)
	_name_board(n, st.name, Vector3(len * 0.2, y, side * (edge + w * 0.5)), _font())
	n.set_meta("platform_side", side)
	return n

static var _font_cache: Font = null

static func _font() -> Font:
	_mutex.lock()
	if _font_cache == null:
		if ResourceLoader.exists(FONT_PATH):
			var base := load(FONT_PATH) as FontFile
			var fv := FontVariation.new()
			fv.base_font = base
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
			fv.spacing_glyph = 3
			_font_cache = fv
		else:
			_font_cache = ThemeDB.fallback_font
	_mutex.unlock()
	return _font_cache
