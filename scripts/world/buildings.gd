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
const BUILDING := preload("res://shaders/world/building.gdshader")
const WINDOW_LIT := preload("res://shaders/world/window_lit.gdshader")
const TEX := "res://assets/models/hd_world/textures/"
## Scanned surfaces (plaster, tiles, timber, stone) from art_source/world_hd; off = flat colours.
static var textured := true
const FONT_PATH := "res://assets/fonts/Oswald.ttf"

const WALL_COLOURS: Array[Color] = [Color(0.93, 0.9, 0.82), Color(0.91, 0.8, 0.55), Color(0.87, 0.72, 0.62),
		Color(0.8, 0.84, 0.76), Color(0.94, 0.93, 0.9), Color(0.86, 0.66, 0.45), Color(0.78, 0.8, 0.86)]
const SCHONBRUNN := Color(0.92, 0.74, 0.32)
const TRIM := Color(0.95, 0.94, 0.9)

static var _mats := {}
static var _mutex := Mutex.new()

# ————— materials —————

static func _t(name: String) -> Texture2D:
	return load(TEX + name) as Texture2D if ResourceLoader.exists(TEX + name) else null

# The textured version of a surface material (building.gdshader), or null.
static func _hd_mat(key: String) -> Material:
	if not textured or not ResourceLoader.exists(TEX + "plaster_albedo.jpg"):
		return null
	# key: [texture set, kind, metres per tile, base colour, snow amount, snow sharpness, roughness]
	var spec: Array = {
		"wall": ["plaster", 0, 3.5, Color(1, 1, 1), 0.15, 0.18, 0.95],
		"roof": ["roof_clay", 1, 2.4, Color(1, 1, 1), 0.88, 0.08, 0.85],
		"roof_dark": ["roof_slate", 1, 2.0, Color(0.85, 0.88, 0.95), 0.85, 0.08, 0.8],
		"wood": ["planks", 2, 1.6, Color(0.95, 0.85, 0.75), 0.4, 0.18, 0.85],
		"wood_green": ["planks_green", 2, 1.6, Color(0.75, 0.95, 0.8), 0.4, 0.18, 0.85],
		"stone": ["stone_wall", 3, 1.6, Color(1.5, 1.45, 1.4), 0.75, 0.18, 0.9],
		"platform": ["platform", 3, 1.3, Color(1, 1, 1), 0.65, 0.4, 0.9],
	}.get(key, [])
	if spec.is_empty():
		if key.begins_with("glass_lit"):
			var w := ShaderMaterial.new()
			w.shader = WINDOW_LIT
			if key == "glass_lit_arch":
				w.set_shader_parameter("win_size", Vector2(0.85, 1.6))
			elif key == "glass_lit_shop":
				w.set_shader_parameter("win_size", Vector2(2.4, 2.0))
				w.set_shader_parameter("room_size", Vector3(5.0, 3.4, 4.5))
				w.set_shader_parameter("curtain_k", 0.2)
			return w
		return null
	var sm := ShaderMaterial.new()
	sm.shader = BUILDING
	var tx: String = spec[0]
	sm.set_shader_parameter("kind", spec[1])
	sm.set_shader_parameter("tex_size", spec[2])
	sm.set_shader_parameter("base", spec[3])
	sm.set_shader_parameter("snow_amount", spec[4])
	sm.set_shader_parameter("snow_sharp", spec[5])
	sm.set_shader_parameter("roughness", spec[6])
	sm.set_shader_parameter("albedo_tex", _t(tx + "_albedo.jpg"))
	sm.set_shader_parameter("normal_tex", _t(tx + "_normal.jpg"))
	sm.set_shader_parameter("orm_tex", _t(tx + "_orm.jpg"))
	sm.set_shader_parameter("plinth_albedo", _t("stone_wall_albedo.jpg"))
	sm.set_shader_parameter("plinth_normal", _t("stone_wall_normal.jpg"))
	sm.set_shader_parameter("snow_albedo", _t("snow_albedo.jpg"))
	sm.set_shader_parameter("snow_normal", _t("snow_normal.jpg"))
	if key == "wall":
		sm.set_shader_parameter("normal_k", 0.45)
	return sm

static func mat(key: String) -> Material:
	_mutex.lock()
	var m: Material = _mats.get(key)
	if m == null:
		m = _hd_mat(key)
		if m != null:
			_mats[key] = m
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
			"glass_lit", "glass_lit_shop":
				var g := StandardMaterial3D.new()
				g.albedo_color = Color(0.2, 0.12, 0.05)
				g.emission_enabled = true
				g.emission = Color(1.0, 0.55, 0.2)
				g.emission_energy_multiplier = 0.55
				m = g
			"glass_clear":
				var gc := StandardMaterial3D.new()
				gc.albedo_color = Color(0.55, 0.62, 0.66, 0.18)
				gc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gc.roughness = 0.05
				gc.metallic_specular = 0.8
				m = gc
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

# Solid collision for a building or a prop: a box (StaticBody3D "Solid") in the parent's frame, so
# nobody walks into walls, sheds, fences or fountains.
static func _solid(parent: Node3D, size: Vector3, center: Vector3, basis := Basis.IDENTITY) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)
	parent.add_child(body)

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

## A wall slab 0.4 thick along X at z = c (its outside toward `out` = ±1), from a0 to a1 and `h`
## high, with openings `holes` = Vector4(x0, x1, y0, y1).
static func _holed_wall(st: SurfaceTool, along_x: bool, c: float, out: float, a0: float, a1: float, h: float,
		holes: Array, col: Color) -> void:
	var t := 0.4
	var zc := c - out * t * 0.5
	var a := a0
	var hs := holes.duplicate()
	hs.sort_custom(func(p, q): return p.x < q.x)
	for o: Vector4 in hs:
		if o.x - a > 0.01:
			_box(st, Vector3((a + o.x) * 0.5, h * 0.5, zc), Vector3(o.x - a, h, t), col)
		if o.z > 0.01:
			_box(st, Vector3((o.x + o.y) * 0.5, o.z * 0.5, zc), Vector3(o.y - o.x, o.z, t), col)
		if h - o.w > 0.01:
			_box(st, Vector3((o.x + o.y) * 0.5, (o.w + h) * 0.5, zc), Vector3(o.y - o.x, h - o.w, t), col)
		a = o.y
	if a1 - a > 0.01:
		_box(st, Vector3((a + a1) * 0.5, h * 0.5, zc), Vector3(a1 - a, h, t), col)

## Where pilasters go on a face `face_w` wide: its corners (`inset` in from the edge) and midway
## between neighbouring windows as _windows() spaces them, so a pilaster never crosses a window.
static func _pilaster_xs(face_w: float, inset: float) -> Array[float]:
	var xs: Array[float] = [-face_w * 0.5 + inset, face_w * 0.5 - inset]
	var count := int(floor((face_w - 1.2) / 2.6))
	for i in count - 1:
		var a := ((float(i) + 0.5) / count - 0.5) * (face_w - 1.4)
		var b := ((float(i) + 1.5) / count - 0.5) * (face_w - 1.4)
		xs.append((a + b) * 0.5)
	return xs

## `ground_open` (Vector2(face z sign, x) per doorway) marks a building whose ground floor one walks
## into: no window at those doorways, the ground floor's end-face windows left out (its wings stand
## there) and its other windows in clear glass.
static func _windows(parent: Node3D, rng: RandomNumberGenerator, w: float, d: float, storeys: int, storey_h: float,
		lit_chance: float, trim: Color, shutters: bool, arched := false, door_x := NAN, side_faces := true,
		ground_open: Array = []) -> void:
	var frames := _new_st()
	var lit := _new_st()
	var dark := _new_st()
	var shut := _new_st()
	var clear := _new_st()
	var counts := [0, 0, 0, 0]       # lit, dark, shutters, clear
	var faces := [[Vector3(0, 0, -1), w, d], [Vector3(0, 0, 1), w, d], [Vector3(-1, 0, 0), d, w], [Vector3(1, 0, 0), d, w]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var face_w: float = f[1]
		var depth: float = f[2]
		if not side_faces and absf(n.x) > 0.5:
			continue          # party walls of a terraced house
		var count := int(floor((face_w - 1.2) / 2.6))
		if count < 1:
			continue
		var along := Vector3.UP.cross(n)          # along the face (right-handed with UP and n)
		for s in storeys:
			for i in count:
				var u := (float(i) + 0.5) / count - 0.5
				var c := n * (depth * 0.5 + 0.01) + along * (u * (face_w - 1.4)) + Vector3(0, s * storey_h + storey_h * 0.55, 0)
				# No ground-floor window where the front door is.
				if s == 0 and n.z < -0.5 and not is_nan(door_x) and absf(c.x - door_x) < 1.1:
					continue
				var open := s == 0 and not ground_open.is_empty()
				if open:
					if absf(n.x) > 0.5:
						continue
					var skip := false
					for g: Vector2 in ground_open:
						skip = skip or (signf(n.z) == g.x and absf(c.x - g.y) < 0.6)
					if skip:
						continue
				var ww := 0.85
				var wh := 1.25 if not arched else 1.6
				var b := Basis(along, Vector3.UP, n)
				# Plaster surround, sill, then the glass (lit or dark) with glazing bars. Round a window
				# one sees through (its wall is open behind it) the surround is a frame, not a panel.
				var trim_c := Color(trim.r, trim.g, trim.b, 0.0)
				if open:
					for sd: float in [-1.0, 1.0]:
						_box(frames, c + n * 0.015 + along * sd * (ww * 0.5 + 0.05), Vector3(0.1, wh + 0.22, 0.04), trim_c, b)
						_box(frames, c + n * 0.015 + Vector3(0, sd * (wh * 0.5 + 0.055), 0), Vector3(ww + 0.2, 0.11, 0.04), trim_c, b)
				else:
					_box(frames, c + n * 0.015, Vector3(ww + 0.2, wh + 0.22, 0.04), trim_c, b)
				_box(frames, c + Vector3(0, -wh * 0.5 - 0.12, 0) + n * 0.06, Vector3(ww + 0.3, 0.07, 0.14), Color(trim.r, trim.g, trim.b, 1.0), b)
				var is_lit := rng.randf() < lit_chance
				if open:
					counts[3] += 1
					_box(clear, c + n * 0.04, Vector3(ww, wh, 0.02), Color.WHITE, b)
				elif is_lit:
					counts[0] += 1
					_pane(lit, c + n * 0.051, ww, wh, n, Color(rng.randf(), rng.randf_range(0.3, 1.0), 0.0, 0.0))
				else:
					counts[1] += 1
					_box(dark, c + n * 0.04, Vector3(ww, wh, 0.02), Color.WHITE, b)
				var bar := Color(0.92, 0.9, 0.85, 0.0)
				_box(frames, c + n * 0.055, Vector3(0.05, wh, 0.02), bar, b)
				_box(frames, c + n * 0.055 + Vector3(0, wh * 0.18, 0), Vector3(ww, 0.05, 0.02), bar, b)
				if shutters and not is_lit and not open:
					var sc := Color(0.18, 0.32, 0.22, 0.0) if rng.randf() < 0.6 else Color(0.38, 0.22, 0.14, 0.0)
					counts[2] += 1
					for side: float in [-1.0, 1.0]:
						_box(shut, c + n * 0.05 + along * side * (ww * 0.5 + 0.24), Vector3(0.42, wh, 0.04), sc, b)
	if counts[0] + counts[1] + counts[3] == 0:
		return
	if counts[3] > 0:
		_commit(parent, clear, "ClearWindows", mat("glass_clear"), false)
	_commit(parent, frames, "WindowFrames", mat("wall"), false)
	if counts[0] > 0:
		_commit(parent, lit, "LitWindows", mat("glass_lit_arch" if arched else "glass_lit"), false)
	if counts[1] > 0:
		_commit(parent, dark, "DarkWindows", mat("glass_dark"), false)
	if counts[2] > 0:
		_commit(parent, shut, "Shutters", mat("wall"), false)

# One window pane facing `n`: UV 0..1 across (along the face frame the window shader uses: x
# along n × up, y down), `col` = the window's random and lamp brightness.
static func _pane(st: SurfaceTool, c: Vector3, w: float, h: float, n: Vector3, col: Color) -> void:
	var t := n.cross(Vector3.UP).normalized()
	var a := c - t * w * 0.5 + Vector3.UP * h * 0.5
	var b := c + t * w * 0.5 + Vector3.UP * h * 0.5
	var d := c + t * w * 0.5 - Vector3.UP * h * 0.5
	var e := c - t * w * 0.5 - Vector3.UP * h * 0.5
	# Clockwise seen from outside (Godot's front face).
	for v: Array in [[a, Vector2(0, 0)], [d, Vector2(1, 1)], [b, Vector2(1, 0)], [a, Vector2(0, 0)], [e, Vector2(0, 1)], [d, Vector2(1, 1)]]:
		st.set_color(col)
		st.set_uv(v[1])
		st.add_vertex(v[0])

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
	var door_x := rng.randf_range(-w * 0.25, w * 0.25)
	_box(st, Vector3(door_x, 1.1, -d * 0.5 - 0.03), Vector3(1.1, 2.2, 0.08), Color(0.3, 0.2, 0.13, 0.0))
	_box(st, Vector3(0, 0.08, -d * 0.5 - 0.5), Vector3(1.8, 0.16, 0.9), Color(0.6, 0.58, 0.55, 1.0))
	_commit(n, st, "Walls", mat("wall"))
	_solid(n, Vector3(w + 0.1, h, d + 0.1), Vector3(0, h * 0.5, 0))
	_windows(n, rng, w, d, storeys, storey_h, lit_chance, TRIM if rng.randf() < 0.7 else col.lightened(0.25), rng.randf() < 0.6, false, door_x)
	var pitch := deg_to_rad(rng.randf_range(44.0, 52.0))
	var half_hip := 0.28 if rng.randf() < 0.55 else 0.0
	var ridge := _roof(n, w, d, h, pitch, 0.45, half_hip, col, "roof" if rng.randf() < 0.75 else "roof_dark")
	if rng.randf() < 0.85:
		var cx := rng.randf_range(-w * 0.3, w * 0.3)
		_chimney(n, Vector3(cx, ridge - 1.2, rng.randf_range(-0.6, 0.6)), 1.9)
		n.set_meta("chimney_top", Vector3(cx, ridge + 0.8, 0))
	n.set_meta("size", Vector3(w, ridge, d))
	n.set_meta("door_x", door_x)
	return n

# ————— town —————

const TOWN_COLOURS: Array[Color] = [Color(0.93, 0.88, 0.76), Color(0.9, 0.78, 0.52), Color(0.86, 0.68, 0.6),
		Color(0.78, 0.84, 0.74), Color(0.95, 0.93, 0.88), Color(0.84, 0.62, 0.42), Color(0.74, 0.78, 0.86),
		Color(0.9, 0.72, 0.7), Color(0.82, 0.8, 0.6)]

## Burgher house for a town street or square, front (-Z) to the street, built to stand wall to wall
## in a row (no windows in its side walls): 2–3 storeys over a taller ground floor, cornices between
## the floors, quoins at the corners. Either the eaves face the street (ridge along the row) or a
## baroque gable does. With shop_ok the ground floor is a shop front: wide lit display windows
## either side of a central door (WorldLife hangs the fascia and the sign).
static func townhouse(rng: RandomNumberGenerator, w: float, d: float, storeys: int, gable_front: bool, shop_ok: bool) -> Node3D:
	var n := Node3D.new()
	n.name = "Townhouse"
	var gf := 3.8
	var sh := 3.2
	var h := gf + (storeys - 1) * sh + 0.5
	var col := TOWN_COLOURS[rng.randi() % TOWN_COLOURS.size()]
	var trim := TRIM if rng.randf() < 0.75 else col.lightened(0.35)
	var tc := Color(trim.r, trim.g, trim.b, 1.0)
	var st := _new_st()
	_walls(st, w, d, h, col)
	# Cornices front and back: over the ground floor, between the floors, under the eaves.
	var ys: Array[float] = [gf - 0.1]
	for s in range(1, storeys):
		ys.append(gf + s * sh - 0.12)
	ys.append(h - 0.15)
	for y in ys:
		for zs: float in [-1.0, 1.0]:
			_box(st, Vector3(0, y, zs * (d * 0.5 + 0.07)), Vector3(w, 0.24 if y < h - 0.2 else 0.34, 0.16), tc)
	# Quoins at the corners of the front.
	for xs: float in [-1.0, 1.0]:
		_box(st, Vector3(xs * (w * 0.5 - 0.22), h * 0.5, -d * 0.5 - 0.035), Vector3(0.44, h, 0.07), Color(tc.r, tc.g, tc.b, 0.1))
	# Door: a deep portal with a stone surround and a step.
	var door_x := 0.0 if shop_ok else rng.randf_range(-w * 0.18, w * 0.18)
	# Stone surround first, the door leaf standing proud of it.
	_box(st, Vector3(door_x, 1.4, -d * 0.5 - 0.02), Vector3(1.75, 2.85, 0.05), Color(tc.r * 0.9, tc.g * 0.9, tc.b * 0.88, 0.0))
	_box(st, Vector3(door_x, 1.3, -d * 0.5 - 0.06), Vector3(1.3, 2.6, 0.05), Color(0.24, 0.15, 0.09, 0.0))
	_box(st, Vector3(door_x, 0.09, -d * 0.5 - 0.45), Vector3(2.0, 0.18, 0.8), Color(0.62, 0.6, 0.57, 1.0))
	_commit(n, st, "Walls", mat("wall"))
	_solid(n, Vector3(w, h, d + 0.2), Vector3(0, h * 0.5, 0))
	var lit_chance := 0.5
	if shop_ok:
		var lit := _new_st()
		var fr := _new_st()
		var front := Vector3(0, 0, -1)
		var sw := minf(w * 0.5 - 1.5, 2.4)
		for sx: float in [-1.0, 1.0]:
			var cx: float = sx * (0.9 + sw * 0.5 + 0.35)
			var c := Vector3(cx, 1.5, -d * 0.5)
			_pane(lit, c + front * 0.03, sw, 2.0, front, Color(rng.randf(), rng.randf_range(0.7, 1.0), 0.0, 0.0))
			# Shop-front joinery: frame, transom, stall riser under the glass.
			for fx: float in [-0.5, 0.5]:
				_box(fr, c + Vector3(fx * sw, 0.0, -0.06), Vector3(0.1, 2.2, 0.08), Color(1, 1, 1, 0.0))
			_box(fr, c + Vector3(0, 1.05, -0.06), Vector3(sw + 0.1, 0.12, 0.1), Color(1, 1, 1, 1.0))
			_box(fr, c + Vector3(0, 0.55, -0.065), Vector3(sw, 0.05, 0.03), Color(1, 1, 1, 0.0))
			_box(fr, c + Vector3(0, -1.2, -0.06), Vector3(sw + 0.1, 0.6, 0.1), Color(1, 1, 1, 1.0))
		_commit(n, lit, "ShopWindows", mat("glass_lit_shop"), false)
		_commit(n, fr, "ShopFront", mat("wood_green" if rng.randf() < 0.5 else "wood"), false)
	else:
		var g := Node3D.new()
		g.name = "GroundFloor"
		n.add_child(g)
		_windows(g, rng, w, d, 1, gf, lit_chance, trim, rng.randf() < 0.4, false, door_x, false)
	if storeys > 1:
		var up := Node3D.new()
		up.name = "Upper"
		up.position.y = gf
		n.add_child(up)
		_windows(up, rng, w, d, storeys - 1, sh, lit_chance, trim, rng.randf() < 0.3, false, NAN, false)
	var roof_mat := "roof" if rng.randf() < 0.7 else "roof_dark"
	var ridge: float
	if gable_front:
		var pitch := deg_to_rad(rng.randf_range(48.0, 56.0))
		var rn := Node3D.new()
		rn.name = "RoofAcross"
		rn.rotation.y = PI * 0.5
		n.add_child(rn)
		ridge = _roof(rn, d, w, h, pitch, 0.25, 0.0, col, roof_mat)
		_baroque_gable(n, rng, w, d, h, ridge - h, col, trim)
	else:
		ridge = _roof(n, w, d, h, deg_to_rad(rng.randf_range(38.0, 46.0)), 0.35, 0.0, col, roof_mat)
		if rng.randf() < 0.5 and w > 7.5:
			_dormer(n, Vector3(rng.randf_range(-w * 0.2, w * 0.2), h, -d * 0.25), col, roof_mat, rng)
	if rng.randf() < 0.9:
		var cx := rng.randf_range(-w * 0.3, w * 0.3)
		_chimney(n, Vector3(cx, ridge - 1.4, rng.randf_range(-0.6, 0.6)), 2.0)
		n.set_meta("chimney_top", Vector3(cx, ridge + 0.6, 0))
	n.set_meta("size", Vector3(w, ridge, d))
	n.set_meta("storeys", storeys)
	n.set_meta("shop_ok", shop_ok)
	n.set_meta("door_x", door_x)
	return n

# Baroque street gable over the front of a gable-fronted house: the roof's triangle hidden behind
# a plastered screen with curved shoulders (volutes), a small pediment on top, a cornice along the
# outline and an oval window.
static func _baroque_gable(n: Node3D, rng: RandomNumberGenerator, w: float, d: float, h: float, rise: float, col: Color, trim: Color) -> void:
	var st := _new_st()
	var tr := _new_st()
	var z := -d * 0.5 - 0.06
	var steps := 28
	var bump := rng.randf_range(0.45, 0.8)
	var top := rise + rng.randf_range(0.4, 0.8)
	var pts: Array[Vector2] = []
	for i in steps + 1:
		var t := float(i) / steps * 2.0 - 1.0
		var u := absf(t)
		# Triangle under it, two volute shoulders and a rounded crown.
		var y := rise * (1.0 - u) + bump * sin(clampf(u * 1.6 - 0.35, 0.0, 1.0) * PI) + (top - rise) * maxf(0.0, 1.0 - u * 6.0)
		pts.append(Vector2(t * w * 0.5, h + maxf(y, 0.0)))
	var wc := Color(col.r, col.g, col.b, 0.0)
	var base := Vector3(0, h, z)
	for i in steps:
		var a := Vector3(pts[i].x, pts[i].y, z)
		var b := Vector3(pts[i + 1].x, pts[i + 1].y, z)
		_tri(st, base, a, b, wc)
		# Thickness: the top edge, where snow lies.
		var a2 := a + Vector3(0, 0, 0.3)
		var b2 := b + Vector3(0, 0, 0.3)
		_quad(st, a, a2, b2, b, Color(col.r, col.g, col.b, 1.0))
		# Cornice following the outline.
		var mid := (a + b) * 0.5
		var dirv := (b - a)
		_box(tr, mid + Vector3(0, -0.05, -0.05), Vector3(dirv.length() + 0.04, 0.14, 0.12), Color(trim.r, trim.g, trim.b, 1.0),
				Basis(Vector3.BACK, atan2(dirv.y, dirv.x)))
	_commit(n, st, "Gable", mat("wall"))
	_commit(n, tr, "GableCornice", mat("wall"), false)
	# Oval window in the gable.
	var ow := _new_st()
	var oc := Vector3(0, h + rise * 0.42, z - 0.02)
	var seg := 16
	var dk := Color(0.04, 0.05, 0.06, 0.0)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		_tri(ow, oc, oc + Vector3(cos(a1) * 0.35, sin(a1) * 0.5, 0), oc + Vector3(cos(a0) * 0.35, sin(a0) * 0.5, 0), dk)
	_commit(n, ow, "GableWindow", mat("glass_dark"), false)

# A small dormer on the street slope of an eaves-front roof.
static func _dormer(n: Node3D, at: Vector3, col: Color, roof_mat: String, rng: RandomNumberGenerator) -> void:
	var dn := Node3D.new()
	dn.name = "Dormer"
	dn.position = at + Vector3(0, 0.2, 0)
	n.add_child(dn)
	var st := _new_st()
	_box(st, Vector3(0, 0.8, 0), Vector3(1.4, 1.6, 1.6), Color(col.r, col.g, col.b, 0.2))
	_commit(dn, st, "Walls", mat("wall"))
	var p := _new_st()
	_pane(p, Vector3(0, 0.85, -0.82), 0.7, 0.9, Vector3(0, 0, -1), Color(rng.randf(), rng.randf_range(0.3, 0.9), 0, 0))
	_commit(dn, p, "LitWindows", mat("glass_lit"), false)
	var rn := Node3D.new()
	rn.rotation.y = PI * 0.5
	dn.add_child(rn)
	_roof(rn, 1.8, 1.6, 1.6, deg_to_rad(42.0), 0.15, 0.0, col, roof_mat)

# ————— yards —————

## A village house's yard (child of the house, in its frame: front -Z): picket fence round the
## front garden and the back yard with a gate at the door, a timber shed with a woodpile against
## it, sometimes a well.
static func yard(rng: RandomNumberGenerator, w: float, d: float, door_x: float) -> Node3D:
	var y := Node3D.new()
	y.name = "Yard"
	var fence := _new_st()
	var x0 := -w * 0.5 - rng.randf_range(2.0, 4.0)
	var x1 := w * 0.5 + rng.randf_range(2.0, 4.0)
	var z0 := -d * 0.5 - rng.randf_range(3.0, 5.0)
	var z1 := d * 0.5 + rng.randf_range(8.0, 13.0)
	y.set_meta("extent", [x0, x1, z0, z1])
	var fc := Color(0.75, 0.68, 0.6, 1.0) if rng.randf() < 0.6 else Color(0.5, 0.62, 0.52, 1.0)
	var runs := [[Vector3(x0, 0, z0), Vector3(door_x - 0.8, 0, z0)], [Vector3(door_x + 0.8, 0, z0), Vector3(x1, 0, z0)],
			[Vector3(x0, 0, z0), Vector3(x0, 0, z1)], [Vector3(x1, 0, z0), Vector3(x1, 0, z1)], [Vector3(x0, 0, z1), Vector3(x1, 0, z1)]]
	for r: Array in runs:
		_fence_run(fence, r[0], r[1], fc)
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		if a.distance_to(b) > 0.3:
			var dvec := b - a
			_solid(y, Vector3(dvec.length(), 1.3, 0.16), (a + b) * 0.5 + Vector3(0, 0.65, 0), Basis(Vector3.UP, -atan2(dvec.z, dvec.x)))
	_commit(y, fence, "Fence", mat("wood"))
	# Shed in a back corner, woodpile along its side.
	var shed := Node3D.new()
	shed.name = "Shed"
	var sw := rng.randf_range(3.0, 4.2)
	var sd := rng.randf_range(2.4, 3.2)
	var sx := (x1 - sw * 0.5 - 0.6) if rng.randf() < 0.5 else (x0 + sw * 0.5 + 0.6)
	shed.position = Vector3(sx, 0, z1 - sd * 0.5 - 0.6)
	y.add_child(shed)
	var s2 := _new_st()
	_box(s2, Vector3(0, 1.15, 0), Vector3(sw, 2.3, sd), Color(0.62, 0.5, 0.4, 0.2))
	_box(s2, Vector3(0, 0.95, -sd * 0.5 - 0.02), Vector3(1.0, 1.9, 0.05), Color(0.35, 0.25, 0.17, 0.0))
	_commit(shed, s2, "ShedWalls", mat("wood"))
	_solid(shed, Vector3(sw, 2.3, sd), Vector3(0, 1.15, 0))
	_solid(shed, Vector3(sw, 1.0, 0.6), Vector3(0, 0.5, -sd * 0.5 - 0.35))
	_roof(shed, sw, sd, 2.3, deg_to_rad(28.0), 0.25, 0.0, Color(0.55, 0.45, 0.35), "roof_dark")
	var logs := _new_st()
	for row in 4:
		for k in 7:
			var lx := -sw * 0.5 + 0.2 + k * (sw - 0.4) / 6.0
			_box(logs, Vector3(lx, 0.14 + row * 0.24, -sd * 0.5 - 0.35), Vector3(0.22, 0.22, 0.55),
					Color(0.55 + rng.randf() * 0.15, 0.42, 0.3, 1.0 if row == 3 else 0.3), Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)))
	_commit(shed, logs, "Woodpile", mat("wood"))
	# A well with a little roof, in some yards.
	if rng.randf() < 0.3:
		var wl := _new_st()
		var wp := Vector3(rng.randf_range(x0 + 1.5, x1 - 1.5), 0, z1 - sd - 2.5)
		_lathe(wl, [Vector2(0.75, 0.0), Vector2(0.75, 0.85), Vector2(0.62, 0.9), Vector2(0.62, 0.0)], 12, Color(0.8, 0.78, 0.74, 1.0), wp)
		for xs: float in [-0.65, 0.65]:
			_box(wl, wp + Vector3(xs, 1.2, 0), Vector3(0.1, 1.5, 0.1), Color(0.5, 0.4, 0.3, 0.2))
		_box(wl, wp + Vector3(0, 1.75, 0), Vector3(1.5, 0.08, 0.08), Color(0.5, 0.4, 0.3, 1.0))
		_commit(y, wl, "Well", mat("stone"))
		_solid(y, Vector3(1.5, 0.9, 1.5), wp + Vector3(0, 0.45, 0))
		var wr := Node3D.new()
		wr.position = wp
		y.add_child(wr)
		_roof(wr, 1.7, 1.3, 1.95, deg_to_rad(35.0), 0.1, 0.0, Color(0.5, 0.4, 0.3), "roof_dark")
	return y

# Picket fence from a to b on the ground (y = 0): posts every ~2.4 m, two rails, pickets.
static func _fence_run(st: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	var dvec := b - a
	var len := dvec.length()
	if len < 0.3:
		return
	var dir := dvec / len
	var bas := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	var posts := int(ceil(len / 2.4))
	for k in posts + 1:
		_box(st, a + dir * (len * k / posts) + Vector3(0, 0.62, 0), Vector3(0.11, 1.24, 0.11), Color(col.r * 0.85, col.g * 0.85, col.b * 0.85, 1.0), bas)
	for ry: float in [0.3, 0.85]:
		_box(st, a + dvec * 0.5 + Vector3(0, ry, 0) + dir.cross(Vector3.UP) * 0.04, Vector3(len, 0.07, 0.04), Color(col.r, col.g, col.b, 0.3), bas)
	var pickets := int(len / 0.19)
	for k in pickets:
		var p := a + dir * ((k + 0.5) * len / pickets) + dir.cross(Vector3.UP) * 0.075
		_box(st, p + Vector3(0, 0.55, 0), Vector3(0.075, 1.02, 0.018), col, bas)

# ————— square —————

## Marian (plague) column for a town square: stepped base, pedestal with corner saints' plinths,
## a tall column, gilded figure and halo.
static func marian_column(rng: RandomNumberGenerator) -> Node3D:
	var n := Node3D.new()
	n.name = "MarianColumn"
	var st := _new_st()
	var sc := Color(0.82, 0.8, 0.76, 1.0)
	for i in 3:
		var s := 6.0 - i * 1.3
		_box(st, Vector3(0, 0.2 + i * 0.4, 0), Vector3(s, 0.4, s), sc)
	_box(st, Vector3(0, 2.2, 0), Vector3(2.2, 1.8, 2.2), Color(sc.r, sc.g, sc.b, 0.2))
	_box(st, Vector3(0, 3.2, 0), Vector3(2.6, 0.25, 2.6), sc)
	for xs: float in [-1.0, 1.0]:
		for zs: float in [-1.0, 1.0]:
			_box(st, Vector3(xs * 2.2, 1.6, zs * 2.2), Vector3(0.7, 0.8, 0.7), sc)
			_lathe(st, [Vector2(0.25, 2.0), Vector2(0.3, 2.4), Vector2(0.2, 2.9), Vector2(0.12, 3.2), Vector2(0.0, 3.3)], 8, sc, Vector3(xs * 2.2, 0, zs * 2.2))
	_lathe(st, [Vector2(0.55, 3.3), Vector2(0.45, 3.6), Vector2(0.4, 9.5), Vector2(0.6, 10.0), Vector2(0.65, 10.3)], 16, sc)
	_commit(n, st, "Stone", mat("stone"))
	_solid(n, Vector3(6.0, 1.2, 6.0), Vector3(0, 0.6, 0))
	_solid(n, Vector3(2.4, 2.4, 2.4), Vector3(0, 2.4, 0))
	_solid(n, Vector3(0.9, 9.0, 0.9), Vector3(0, 6.8, 0))
	var g := _new_st()
	_lathe(g, [Vector2(0.0, 10.3), Vector2(0.35, 10.4), Vector2(0.25, 11.2), Vector2(0.18, 11.9), Vector2(0.14, 12.2), Vector2(0.0, 12.3)], 10, Color(1, 1, 1, 0.3))
	for k in 12:
		var a := TAU * k / 12.0
		_box(g, Vector3(cos(a) * 0.32, 12.3 + sin(a) * 0.32, 0), Vector3(0.06, 0.06, 0.05), Color(1, 1, 1, 0.0))
	_commit(n, g, "Gilt", mat("gold"))
	n.set_meta("size", Vector3(6.0, 12.5, 6.0))
	return n

## Town fountain: octagonal stone basin (frozen over), a pillar with a small bowl.
static func fountain() -> Node3D:
	var n := Node3D.new()
	n.name = "Fountain"
	var st := _new_st()
	var sc := Color(0.78, 0.76, 0.72, 1.0)
	_lathe(st, [Vector2(3.0, 0.0), Vector2(3.0, 0.7), Vector2(3.2, 0.8), Vector2(2.8, 0.85), Vector2(2.8, 0.5)], 8, sc)
	_lathe(st, [Vector2(0.4, 0.4), Vector2(0.3, 1.8), Vector2(0.9, 2.1), Vector2(0.95, 2.3), Vector2(0.2, 2.3), Vector2(0.15, 2.9), Vector2(0.0, 3.0)], 12, sc)
	_commit(n, st, "Stone", mat("stone"))
	_solid(n, Vector3(6.2, 0.85, 6.2), Vector3(0, 0.42, 0))
	var ice := _new_st()
	_lathe(ice, [Vector2(0.0, 0.5), Vector2(2.8, 0.5)], 8, Color(0.9, 0.93, 1.0, 1.0))
	_commit(n, ice, "Ice", mat("stone"))
	n.set_meta("size", Vector3(6.4, 3.0, 6.4))
	return n

# ————— merging —————

## Merges every MeshInstance3D under `root` (except those with meta "keep") into one mesh per
## material and shadow setting, in root's space, so a whole village is a handful of draws. The
## building nodes stay (empty, with their meta) for others to attach to. Wall surfaces get each
## vertex's height above its own building in UV.y (the building shader's plinth band).
static func merge_group(root: Node3D) -> void:
	var groups := {}          # key -> {mat, shadow, v, n, c, uv}
	var found: Array = []
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.has_meta("keep") or _kept(mi, root):
			continue
		found.append(mi)
	for mi: MeshInstance3D in found:
		# xf: mesh -> root space; bxf: mesh -> its building (the ancestor right under root).
		var building: Node = mi
		var xf := Transform3D.IDENTITY
		var q: Node = mi
		while q != null and q != root:
			xf = (q as Node3D).transform * xf
			building = q
			q = q.get_parent()
		var bxf := Transform3D.IDENTITY if building == mi else (building as Node3D).transform.affine_inverse() * xf
		var shadow := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in mi.mesh.get_surface_count():
			var material: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
			if material == null:
				continue
			var key := "%d_%s" % [material.get_instance_id(), shadow]
			if not groups.has(key):
				groups[key] = {"mat": material, "shadow": shadow, "v": PackedVector3Array(), "n": PackedVector3Array(),
						"c": PackedColorArray(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
			var g: Dictionary = groups[key]
			var arr := mi.mesh.surface_get_arrays(si)
			# Without a real renderer (--headless) the dummy rendering server, filled from several
			# threads at once, now and then hands back a surface with no vertices (and keeps doing
			# so): that piece is left out rather than stopping the whole merge. Never seen windowed.
			if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
				push_warning("Buildings.merge_group: no vertices for %s (surface %d), left out" % [mi.name, si])
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			# Packed arrays are values: take them out of the group (so appending does not copy), put back.
			var gv: PackedVector3Array = g.v
			var gn: PackedVector3Array = g.n
			var gc: PackedColorArray = g.c
			var guv: PackedVector2Array = g.uv
			var gi: PackedInt32Array = g.i
			g.erase("v")
			g.erase("n")
			g.erase("c")
			g.erase("uv")
			g.erase("i")
			var base := gv.size()
			var nb := xf.basis.inverse().transposed()
			for k in verts.size():
				var v := verts[k]
				gv.append(xf * v)
				gn.append((nb * (norms[k] if k < norms.size() else Vector3.UP)).normalized())
				gc.append(cols[k] if k < cols.size() else Color.WHITE)
				guv.append(uvs[k] if k < uvs.size() else Vector2(0.0, (bxf * v).y))
			if idx.is_empty():
				for k in verts.size():
					gi.append(base + k)
			else:
				for k in idx:
					gi.append(base + k)
			g.v = gv
			g.n = gn
			g.c = gc
			g.uv = guv
			g.i = gi
	for key: String in groups:
		var g: Dictionary = groups[key]
		if (g.v as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g.v
		arr[Mesh.ARRAY_NORMAL] = g.n
		arr[Mesh.ARRAY_COLOR] = g.c
		arr[Mesh.ARRAY_TEX_UV] = g.uv
		arr[Mesh.ARRAY_INDEX] = g.i
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "Merged"
		mi.mesh = am
		mi.material_override = _merged_mat(g.mat)
		if not g.shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	for mi: MeshInstance3D in found:
		mi.get_parent().remove_child(mi)
		mi.free()

static func _kept(mi: Node, root: Node) -> bool:
	var p := mi.get_parent()
	while p != null and p != root:
		if p.has_meta("keep"):
			return true
		p = p.get_parent()
	return false

# The building shader's plinth needs the height above each house: merged walls read it from UV.y.
static func _merged_mat(m: Material) -> Material:
	if m is ShaderMaterial and (m as ShaderMaterial).shader == BUILDING and int((m as ShaderMaterial).get_shader_parameter("kind")) == 0:
		_mutex.lock()
		var key := "merged_%d" % m.get_instance_id()
		var mm: Material = _mats.get(key)
		if mm == null:
			mm = m.duplicate()
			(mm as ShaderMaterial).set_shader_parameter("merged", true)
			_mats[key] = mm
		_mutex.unlock()
		return mm
	return m

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
	# Pilasters (at the corners and between the windows, never across one).
	for x: float in _pilaster_xs(nave_w, 0.0):
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
	_solid(n, Vector3(nave_w, nave_h, nave_d), Vector3(0, nave_h * 0.5, 0))
	_solid(n, Vector3(tw, th, tw), Vector3(tx, th * 0.5, 0))
	_solid(n, Vector3(nave_d * 0.45, nave_h - 1.5, nave_d * 0.84), Vector3(nave_w * 0.5 + nave_d * 0.2, (nave_h - 1.5) * 0.5, 0))
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
	var town: int = st.get("town", 0)
	# Country stations: the stone station of the reference photo (StationModels).
	if StationModels.ready() and town < 3:
		_stone_station(n, st, rng, side, plat_y, edge, plat_w, plat_len, false)
		n.set_meta("platform_side", side)
		return n
	# Big towns: this building, with an iron-and-glass train shed over track and platform.
	var shed := StationModels.ready()
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
	# The ground floor is the booking hall one walks into (StationHall "town"): walls 0.4 thick
	# with the doors (two to the platform, one to the town) and the windows open, under the solid
	# upper storey; the hall's fittings are put in by WorldLife at the HallSpot marker.
	var top := storey * 2.0 + 0.6
	var gh := storey - 0.06                     # up to the first-floor cornice
	var hall_c: Dictionary = StationHall.CONFIGS["town"]
	var win_xs: Array = []
	var nwin := int(floor((cw - 1.2) / 2.6))
	for i in nwin:
		win_xs.append(((float(i) + 0.5) / nwin - 0.5) * (cw - 1.4))
	var front_holes: Array = []
	var back_holes: Array = []
	for x: float in win_xs:
		var is_door := false
		for dx: float in hall_c.front_doors:
			is_door = is_door or absf(x - dx) < 0.3
		front_holes.append(Vector4(x - 0.65, x + 0.65, 0.0, 2.35) if is_door else Vector4(x - 0.43, x + 0.43, 1.18, 2.78))
		if absf(x - float(hall_c.back_door)) < 0.3:
			back_holes.append(Vector4(x - 0.75, x + 0.75, 0.0, 2.3))
		else:
			back_holes.append(Vector4(x - 0.43, x + 0.43, 1.18, 2.78))
	var wc := Color(SCHONBRUNN.r, SCHONBRUNN.g, SCHONBRUNN.b, 0.0)
	_holed_wall(stb, true, -cd * 0.5, -1.0, -cw * 0.5, cw * 0.5, gh, front_holes, wc)
	_holed_wall(stb, true, cd * 0.5, 1.0, -cw * 0.5, cw * 0.5, gh, back_holes, wc)
	for sx: float in [-1.0, 1.0]:
		_box(stb, Vector3(sx * (cw * 0.5 - 0.2), gh * 0.5, 0), Vector3(0.4, gh, cd - 0.8), wc)
	_box(stb, Vector3(0, (gh + top) * 0.5, 0), Vector3(cw, top - gh, cd), Color(SCHONBRUNN.r, SCHONBRUNN.g, SCHONBRUNN.b, 0.3))
	# Plinth: a darker band at the foot, broken at the doors.
	var pc := Color(SCHONBRUNN.r * 0.62, SCHONBRUNN.g * 0.6, SCHONBRUNN.b * 0.58, 0.6)
	for zs: float in [-1.0, 1.0]:
		var a := -cw * 0.5 - 0.04
		for h: Vector4 in (front_holes if zs < 0.0 else back_holes) + [Vector4(cw * 0.5 + 0.04, cw * 0.5 + 0.04, 1, 1)]:
			if h.z > 0.5:
				continue
			if h.x - a > 0.01:
				_box(stb, Vector3((a + h.x) * 0.5, 0.3, zs * (cd * 0.5 + 0.02)), Vector3(h.x - a, 0.6, 0.04), pc)
			a = h.y
		if cw * 0.5 + 0.04 - a > 0.01:
			_box(stb, Vector3((a + cw * 0.5 + 0.04) * 0.5, 0.3, zs * (cd * 0.5 + 0.02)), Vector3(cw * 0.5 + 0.04 - a, 0.6, 0.04), pc)
	for sx: float in [-1.0, 1.0]:
		_box(stb, Vector3(sx * (cw * 0.5 + 0.02), 0.3, 0), Vector3(0.04, 0.6, cd + 0.08), pc)
	# White pilasters at the corners and between the bays, cornice between the floors and under
	# the roof, rusticated ground-floor band.
	for x: float in _pilaster_xs(cw, 0.3):
		for zs: float in [-1.0, 1.0]:
			_box(stb, Vector3(x, storey + 0.3, zs * (cd * 0.5 + 0.06)), Vector3(0.55, storey * 2.0, 0.12), Color(TRIM.r, TRIM.g, TRIM.b, 0.1))
	for y: float in [storey + 0.1, storey * 2.0 + 0.45]:
		_box(stb, Vector3(0, y, 0), Vector3(cw + 0.4, 0.32, cd + 0.4), Color(TRIM.r, TRIM.g, TRIM.b, 1.0))
	_commit(bldg, stb, "Walls", mat("wall"))
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.set_meta("surface", "stone")
	bldg.add_child(body)
	for b: Array in StationHall.wall_boxes("town", gh) + [[Vector3(cw, top - gh, cd), Vector3(0, (gh + top) * 0.5, 0)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[0]
		cs.shape = bs
		cs.position = b[1]
		body.add_child(cs)
	var hall := Marker3D.new()
	hall.name = "HallSpot"
	hall.set_meta("kind", "town")
	bldg.add_child(hall)
	var skips: Array = []
	for dx: float in hall_c.front_doors:
		skips.append(Vector2(-1, dx))
	skips.append(Vector2(1, hall_c.back_door))
	_windows(bldg, rng, cw, cd, 2, storey, 0.75, TRIM, false, true, NAN, true, skips)
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
		_solid(wing, Vector3(10.0, storey + 0.4, 8.0), Vector3(0, (storey + 0.4) * 0.5, 0))
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
	if shed:
		_train_shed(n, side, plat_len)
	else:
		_canopy(bldg, cw + 20.0, -cd * 0.5, storey + 0.2)
	# Station bell (the k.u.k. "Läutewerk") on its post by the door.
	_bell(bldg, Vector3(cw * 0.5 + 1.4, 0, -cd * 0.5 - 2.6))
	# Benches under the canopy (clear of the hall's doors), lamps along the platform, boards at both ends.
	for bx: float in [-12.0, -6.5, 4.5, 12.0]:
		_bench(bldg, Vector3(bx, 0, -cd * 0.5 - 1.2))
	var lamp_count := int(plat_len / 18.0)
	for i in lamp_count:
		if shed:
			break          # the shed's own lanterns light the platform
		var x := lerpf(-plat_len * 0.5 + 8.0, plat_len * 0.5 - 8.0, float(i) / float(lamp_count - 1))
		var light := absf(x) > 22.0 and i % 2 == 0      # real light on every other lamp beyond the canopy
		_lamp_post(n, Vector3(x, plat_y, side * (edge + plat_w - 0.6)), light)
	for xs: float in [-1.0, 1.0]:
		_name_board(n, st.name, Vector3(xs * (plat_len * 0.5 - 4.0), plat_y, side * (edge + plat_w * 0.5)), font)
	n.set_meta("platform_side", side)
	return n

# The stone country station (reference: Ellicott's Mills): the building stands at the back of the
# platform and its roof runs out over the platform as a canopy on timber posts, on into an open
# shelter at one end. `halt` = the small version beside a halt's narrow platform.
const STONE_STATION := {"L": 16.0, "D": 9.0, "H": 4.6, "canopy": 4.2, "shelter": 12.0, "annex": 4.0}
const STONE_HALT := {"L": 7.5, "D": 5.2, "H": 3.3, "canopy": 3.0, "shelter": 5.0, "annex": 0.0}

static func _stone_station(n: Node3D, st: Dictionary, rng: RandomNumberGenerator, side: float, plat_y: float,
		edge: float, plat_w: float, plat_len: float, halt: bool) -> void:
	var k: Dictionary = STONE_HALT if halt else STONE_STATION
	var L: float = k.L
	var D: float = k.D
	var H: float = k.H
	var canopy: float = k.canopy
	var shelter: float = k.shelter
	var hx := L * 0.5
	var hz := D * 0.5
	# The front wall at the back of the platform (a halt's stands a metre further back, on a paved
	# apron, so the canopy posts still come down on the platform).
	var front := edge + plat_w + (1.0 if halt else 0.0)
	var bx := rng.randf_range(-2.0, 2.0) if halt else rng.randf_range(-6.0, 10.0)
	var bldg := Node3D.new()
	bldg.name = "StationBuilding"
	bldg.position = Vector3(bx, plat_y - 0.05, side * (front + hz))
	if side < 0:
		bldg.rotation.y = PI          # local -Z toward the track
	n.add_child(bldg)
	StationModels.place(bldg, "halt_house" if halt else "station_house", Transform3D.IDENTITY, 300.0)
	# Footing down to the ground under the building, annexe and shelter, and (halt) the apron.
	var x0 := -hx - shelter
	var x1 := hx + float(k.annex)
	var foot_z0 := -hz - (1.0 if halt else 0.0)
	var foot := MeshInstance3D.new()
	foot.name = "Footing"
	var fm := BoxMesh.new()
	var fh := plat_y - 0.05 - Terrain.FORMATION_Y + 0.25
	fm.size = Vector3(x1 - x0, fh, hz - foot_z0)
	foot.mesh = fm
	foot.material_override = mat("stone")
	foot.position = Vector3((x0 + x1) * 0.5, -fh * 0.5 + 0.0, (foot_z0 + hz) * 0.5)
	foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bldg.add_child(foot)
	var body := StaticBody3D.new()
	body.name = "StationBody"
	body.set_meta("surface", "snow")
	bldg.add_child(body)
	if halt:
		var walls := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(L, H, D)
		walls.shape = wb
		walls.position = Vector3(0, H * 0.5, 0)
		body.add_child(walls)
	else:
		# The station one walks into: its walls with the doorways open, and a marker where the
		# booking hall's fittings go (StationHall, put in on the main thread by WorldLife).
		for b: Array in StationHall.wall_boxes("stone", H):
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = b[0]
			cs.shape = bs
			cs.position = b[1]
			body.add_child(cs)
		var hall := Marker3D.new()
		hall.name = "HallSpot"
		hall.set_meta("kind", "stone")
		bldg.add_child(hall)
	var apron := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(x1 - x0, fh, hz - foot_z0)
	apron.shape = ab
	apron.position = foot.position
	body.add_child(apron)
	if float(k.annex) > 0.0:
		var an := CollisionShape3D.new()
		var anb := BoxShape3D.new()
		anb.size = Vector3(float(k.annex), H * 0.72, D * 0.7)
		an.shape = anb
		an.position = Vector3(hx + float(k.annex) * 0.5, H * 0.36, hz - D * 0.35)
		body.add_child(an)
	# Canopy posts (same spacing as the model): solid to walk into.
	var z_out := -hz - canopy
	var zp := z_out + 0.45
	var n_posts := maxi(2, int((hx + 0.6 - x0) / 3.4))
	for i in n_posts + 1:
		var px := x0 + 0.3 + i * (hx + 0.6 - x0 - 0.6) / n_posts
		var pc := CollisionShape3D.new()
		var pb := BoxShape3D.new()
		pb.size = Vector3(0.25, 3.0, 0.25)
		pc.shape = pb
		pc.position = Vector3(px, 1.5, zp)
		body.add_child(pc)
	# Station name: on the boards under both gables and along the canopy fascia over the platform.
	var font := _font()
	var px_size := (0.0034 if str(st.name).length() < 11 else 0.0026) * (0.75 if halt else 1.0)
	for sx: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.name = "GableName"
		l.text = st.name
		l.font = font
		l.font_size = 96
		l.pixel_size = px_size
		l.modulate = Color(0.06, 0.06, 0.07)
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(sx * (hx + 0.16), H - 0.55, 0)
		l.rotation.y = sx * PI * 0.5
		l.visibility_range_end = 120.0
		bldg.add_child(l)
	var y_out := H - 0.05 - canopy * tan(deg_to_rad(14.0))
	var fl := Label3D.new()
	fl.name = "FasciaName"
	fl.text = st.name
	fl.font = font
	fl.font_size = 96
	fl.pixel_size = px_size * 0.6
	fl.modulate = Color(0.93, 0.9, 0.82)
	fl.shaded = true
	fl.double_sided = false
	fl.position = Vector3((x0 + hx + 0.6) * 0.5, y_out - 0.16, z_out - 0.04)
	fl.rotation.y = PI
	fl.visibility_range_end = 90.0
	bldg.add_child(fl)
	# Lamps under the canopy (a glowing globe each, real light on some).
	var nl := 2 if halt else 4
	for i in nl:
		var lx := lerpf(x0 + 2.0, hx - 1.0, (i + 0.5) / nl)
		var g := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		g.mesh = sm
		g.material_override = mat("lamp")
		g.position = Vector3(lx, y_out - 0.05 + (H - y_out) * 0.5 - 0.55, -hz - canopy * 0.5)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = 400.0
		bldg.add_child(g)
		if i % 2 == 0 or halt:
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.78, 0.5)
			ol.light_energy = 1.8
			ol.omni_range = 11.0
			ol.omni_attenuation = 1.2
			ol.distance_fade_enabled = true
			ol.distance_fade_begin = 120.0
			ol.distance_fade_length = 30.0
			ol.position = g.position - Vector3(0, 0.2, 0)
			bldg.add_child(track_lamp(ol))
	# Benches along the wall clear of the doorways (StationHall's front_doors, -3.2 and 0) and of the
	# platform guard's place, the bell by the door; lamp posts along the open platform beyond.
	for bx_b: float in ([-6.0, 2.6] if halt else [-16.0, -10.0, -6.2, 3.4]):
		_bench(bldg, Vector3(bx_b, 0, -hz - 0.9))
	if not halt:
		_bell(bldg, Vector3(hx + 1.6, 0, -hz - 2.4))
	var lo := bx + (x0 if side > 0 else -x1) - 2.0
	var hi := bx + (x1 if side > 0 else -x0) + 2.0
	var lamp_count := int(plat_len / 18.0)
	for i in (0 if halt else lamp_count):
		var x := lerpf(-plat_len * 0.5 + 6.0, plat_len * 0.5 - 6.0, float(i) / float(maxi(lamp_count - 1, 1)))
		if x > lo and x < hi:
			continue
		_lamp_post(n, Vector3(x, plat_y, side * (edge + plat_w - 0.6)), i % 2 == 0)
	if not halt:
		for xs: float in [-1.0, 1.0]:
			_name_board(n, st.name, Vector3(xs * (plat_len * 0.5 - 4.0), plat_y, side * (edge + plat_w * 0.5)), font)

# The big towns' train shed (reference 1): arched iron trusses on cast-iron columns every 8 m over
# the track and the platform, slate-and-glass roof, an iron arcade along both sides, lanterns hung
# over the platform, fan-glazed screens at both ends. Model frame: track at z = 0, platform +z.
static func _train_shed(n: Node3D, side: float, plat_len: float) -> void:
	var shed := Node3D.new()
	shed.name = "TrainShed"
	shed.position = Vector3(0, Terrain.FORMATION_Y, 0)
	if side < 0:
		shed.rotation.y = PI
	n.add_child(shed)
	var bays := int(plat_len / 8.0)
	var body := StaticBody3D.new()
	body.name = "ShedColumns"
	shed.add_child(body)
	for i in bays:
		var x := (i - (bays - 1) * 0.5) * 8.0
		StationModels.place(shed, "shed_bay", Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), 420.0)
		for z: float in [-10.4, 6.75]:         # the shed now spans the island platform and the loop too
			var cs := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = 0.28
			cy.height = 6.0
			cs.shape = cy
			cs.position = Vector3(x, 3.0, z)
			body.add_child(cs)
		if i % 2 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.8, 0.55)
			l.light_energy = 2.2
			l.omni_range = 15.0
			l.omni_attenuation = 1.1
			l.distance_fade_enabled = true
			l.distance_fade_begin = 140.0
			l.distance_fade_length = 30.0
			l.position = Vector3(x, 3.85, 4.4)
			shed.add_child(track_lamp(l))
	for e: float in [-1.0, 1.0]:
		StationModels.place(shed, "shed_end", Transform3D(Basis.IDENTITY, Vector3(e * bays * 4.0, 0, 0)), 1500.0)

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
			parent.add_child(track_lamp(l))

## Lamps by the track (platform lamps, canopy and shed lights) cast shadows near the camera: the
## train's roof and walls then keep their light out of the cars (without, it shines through the
## roof and lights the compartments as if they had no ceiling). Cheap dual-paraboloid maps, and
## only for the lamps close by.
static func track_lamp(l: OmniLight3D) -> OmniLight3D:
	l.shadow_enabled = true
	l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	l.shadow_bias = 0.08
	l.shadow_normal_bias = 1.5
	l.distance_fade_enabled = true
	if l.distance_fade_begin < 1.0 or l.distance_fade_begin > 140.0:
		l.distance_fade_begin = 140.0
		l.distance_fade_length = 30.0
	l.distance_fade_shadow = 45.0
	return l

static func _lamp_post(parent: Node3D, base: Vector3, light: bool) -> void:
	var hd := SceneryMeshes.get_mesh("lamp_post") if textured else null
	if hd:
		var mi := MeshInstance3D.new()
		mi.name = "LampPost"
		mi.mesh = hd
		mi.position = base
		mi.visibility_range_end = 260.0
		parent.add_child(mi)
		if light:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.78, 0.5)
			l.light_energy = 2.0
			l.omni_range = 14.0
			l.omni_attenuation = 1.3
			l.position = base + Vector3(0, 3.7, 0)
			parent.add_child(track_lamp(l))
		return
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
		parent.add_child(track_lamp(l))

static func _bench(parent: Node3D, p: Vector3) -> void:
	var hd := SceneryMeshes.get_mesh("bench") if textured else null
	if hd:
		var mi := MeshInstance3D.new()
		mi.name = "Bench"
		mi.mesh = hd
		mi.position = p
		mi.visibility_range_end = 150.0
		parent.add_child(mi)
		return
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
	# The HD bell (props_hd station_bell) is put in on the main thread (WorldLife) at this marker.
	if textured and ResourceLoader.exists("res://assets/models/hd_props/station_bell.gltf"):
		var m := Marker3D.new()
		m.name = "BellSpot"
		m.position = p
		parent.add_child(m)
		return
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
	if StationModels.ready():
		_stone_station(n, st, rng, side, y, edge, w, len, true)
		_lamp_post(n, Vector3(-len * 0.42, y, side * (edge + w - 0.4)), true)
		_name_board(n, st.name, Vector3(len * 0.2, y, side * (edge + w * 0.5)), _font())
		n.set_meta("platform_side", side)
		return n
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
