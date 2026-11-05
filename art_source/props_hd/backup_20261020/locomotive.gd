@tool
class_name Locomotive
extends Node3D
## Car 6: a 1930s express Pacific (4-6-2) in the company's green, with a corridor tender, built
## procedurally (every part a stand-in to be replaced by models later).
## Local frame: x = 0 is the tender's rear body face (coupled to the mail van), the engine runs
## toward -X; y = 0 is the floor level of the cars (footplate and corridor floor); rail top is at
## y = RAIL_Y; z across the track.
## Walkable: the tender corridor (a passage through the water tank, as on the real corridor
## tenders) from the rear doorway to the cab, and the cab floor. The backhead carries the boiler
## fittings (firehole door with its glow, gauges, water glasses, regulator, injector valves,
## brake valve); the reverser, seats, shovel and fire irons stand in the cab.

@export var engine_number: String = "1930":
	set(v): engine_number = v; _queue_rebuild()
@export var engine_name: String = "CONTINENTAL":
	set(v): engine_name = v; _queue_rebuild()
@export var company_name: String = "GRAND CONTINENTAL RAILWAY":
	set(v): company_name = v; _queue_rebuild()
@export var livery: Color = Color(0.122, 0.231, 0.153):
	set(v): livery = v; _queue_rebuild()
@export var fire_lit: bool = true:
	set(v): fire_lit = v; _queue_rebuild()

const RAIL_Y := -1.25
const GAUGE_HALF := 0.7175
const BUILT := "Built"

# Tender
const T_LEN := 8.6
const T_HALF_W := 1.35
const T_TOP := 2.15
const COR_HALF := 0.45          # corridor half width
const COR_H := 2.0
# Cab
const CAB_X0 := -8.6            # rear (open to the tender)
const CAB_X1 := -11.2           # spectacle plate / backhead
const CAB_HALF_W := 1.37
const CAB_ROOF := 2.18
# Engine
const FIREBOX_X1 := -13.0
const BOILER_X1 := -19.5
const SMOKEBOX_X1 := -21.3
const BEAM_X := -21.85
const BOILER_Y := 1.1
const BOILER_R := 0.85
const PLATE_Y := -0.1           # running plate

var _queued := false
var _m := {}
# Moving parts of the running gear, filled while building (see set_travel).
var _gear := {}
var _travel := 0.0

func _ready() -> void:
	rebuild()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var ts := get_node_or_null("/root/TrainState")
	if ts:
		set_travel(float(ts.get("distance")))

# Turns the wheels and works the rods for `dist` metres travelled: every wheel rolls (angle =
# distance / radius); the right-hand cranks lead the left by a quarter turn, as on a real
# two-cylinder engine. The coupling rods ride the crankpins without turning; the crosshead slides
# on its bars so that the connecting rod keeps its length, and the piston rod follows it.
func set_travel(dist: float) -> void:
	if _gear.is_empty() or is_equal_approx(dist, _travel):
		return
	_travel = dist
	for w: Array in _gear.wheels:
		var node: Node3D = w[0]
		if is_instance_valid(node):
			node.rotation.z = dist / float(w[1]) + float(w[2])
	for side: Dictionary in _gear.sides:
		var a: float = dist / 0.95 + float(side.phase)
		var pin: Vector2 = _crank_pin(0.95).rotated(a)
		var base: Vector2 = _crank_pin(0.95)
		var cr: Node3D = side.coupling
		cr.position = side.coupling_pos + Vector3(pin.x - base.x, pin.y - base.y, 0)
		var pin_mid := Vector3(side.mid_x + pin.x, side.wheel_y + pin.y, side.cr_z)
		var dy: float = side.cyl_y - pin_mid.y
		var xh: float = pin_mid.x - sqrt(maxf(side.con_len * side.con_len - dy * dy, 0.0))
		(side.crosshead as Node3D).position.x = xh
		_place_rod(side.conrod, Vector3(xh, side.cyl_y, pin_mid.z + side.con_dz), pin_mid)
		_place_rod(side.piston, Vector3(side.piston_x0, side.cyl_y, side.cz), Vector3(xh, side.cyl_y, side.cz))

func _place_rod(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var cm := mi.mesh as CylinderMesh
	mi.position = (a + b) * 0.5
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized())) * Basis.from_scale(Vector3(1, a.distance_to(b) / cm.height, 1))

func _queue_rebuild() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	rebuild.call_deferred()

func rebuild() -> void:
	_queued = false
	_m = {}
	_gear = {"wheels": [], "sides": []}
	_travel = INF
	var old := get_node_or_null(BUILT)
	if old:
		remove_child(old)
		old.queue_free()
	var root := Node3D.new()
	root.name = BUILT
	add_child(root)
	var tender := _group(root, "Tender")
	_build_tender(tender)
	_build_tender_corridor(tender)
	var cab := _group(root, "Cab")
	_build_cab(cab)
	_build_backhead(cab)
	_build_cab_fittings(cab)
	var eng := _group(root, "Engine")
	_build_boiler(eng)
	_build_running_gear(eng)
	_build_front(eng)
	_build_collision(root)
	set_travel(0.0)

# ————— materials —————

func _mat(key: String) -> Material:
	if _m.has(key):
		return _m[key]
	var m := StandardMaterial3D.new()
	match key:
		"green":
			m.albedo_color = livery
			m.roughness = 0.32
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
			m.clearcoat_roughness = 0.12
		"black":
			m.albedo_color = Color(0.035, 0.035, 0.035)
			m.roughness = 0.45
			m.metallic = 0.3
		"smokebox":
			m.albedo_color = Color(0.05, 0.05, 0.05)
			m.roughness = 0.75
			m.metallic = 0.2
		"red":
			m.albedo_color = Color(0.55, 0.07, 0.05)
			m.roughness = 0.35
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
		"steel":
			m.albedo_color = Color(0.58, 0.59, 0.6)
			m.metallic = 0.9
			m.roughness = 0.28
		"steel_dark":
			m.albedo_color = Color(0.22, 0.22, 0.23)
			m.metallic = 0.8
			m.roughness = 0.4
		"brass":
			m.albedo_color = Color(0.79, 0.64, 0.29)
			m.metallic = 0.85
			m.roughness = 0.28
		"copper":
			m.albedo_color = Color(0.72, 0.42, 0.25)
			m.metallic = 0.85
			m.roughness = 0.3
		"gold":
			m.albedo_color = Color(0.78, 0.62, 0.27)
			m.metallic = 0.6
			m.roughness = 0.35
		"cream":
			m.albedo_color = Color(0.82, 0.78, 0.68)
			m.roughness = 0.6
		"buff":
			m.albedo_color = Color(0.7, 0.62, 0.48)
			m.roughness = 0.65
		"wood":
			m.albedo_color = Color(0.36, 0.22, 0.12)
			m.roughness = 0.55
		"floor":
			m.albedo_color = Color(0.3, 0.2, 0.12)
			m.roughness = 0.8
		"coal":
			m.albedo_color = Color(0.025, 0.025, 0.028)
			m.roughness = 0.35
			m.metallic = 0.2
		"glass":
			m.albedo_color = Color(0.75, 0.82, 0.85, 0.18)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic_specular = 0.9
		"water":
			m.albedo_color = Color(0.45, 0.6, 0.65, 0.5)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
		"fire":
			m.albedo_color = Color(1.0, 0.45, 0.1)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.42, 0.08)
			m.emission_energy_multiplier = 4.0 if fire_lit else 0.0
		"lamp_white":
			m.albedo_color = Color(1.0, 0.97, 0.85)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.94, 0.75)
			m.emission_energy_multiplier = 1.5
		"lamp_red":
			m.albedo_color = Color(0.8, 0.05, 0.03)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.08, 0.04)
			m.emission_energy_multiplier = 2.0
		"rubber":
			m.albedo_color = Color(0.06, 0.06, 0.06)
			m.roughness = 0.9
		_:
			m.albedo_color = Color(1, 0, 1)
	_m[key] = m
	return m

# ————— helpers —————

func _group(parent: Node, gname: String) -> Node3D:
	var n := Node3D.new()
	n.name = gname
	parent.add_child(n)
	return n

func _box(p: Node, bname: String, size: Vector3, pos: Vector3, mat: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = bname
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(mat)
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi, true)
	return mi

# Cylinder along `axis` (UP, RIGHT or BACK).
func _cyl(p: Node, cname: String, r_top: float, r_bot: float, h: float, pos: Vector3, mat: String,
		axis := Vector3.UP, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = cname
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(mat)
	mi.position = pos
	if axis != Vector3.UP:
		mi.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	p.add_child(mi, true)
	return mi

func _rod(p: Node, rname: String, a: Vector3, b: Vector3, r: float, mat: String) -> MeshInstance3D:
	var mi := _cyl(p, rname, r, r, a.distance_to(b), (a + b) * 0.5, mat, Vector3.UP, 10)
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return mi

func _ball(p: Node, bname: String, pos: Vector3, r: float, mat: String, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = bname
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = _mat(mat)
	mi.position = pos
	mi.scale = sc
	p.add_child(mi, true)
	return mi

func _torus(p: Node, tname: String, r_in: float, r_out: float, pos: Vector3, mat: String, axis := Vector3.UP) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = tname
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	tm.rings = 32
	tm.ring_segments = 10
	mi.mesh = tm
	mi.material_override = _mat(mat)
	mi.position = pos
	if axis != Vector3.UP:
		mi.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	p.add_child(mi, true)
	return mi

var _font_cache := {}
func _font(path: String, weight: int) -> Font:
	var key := "%s_%d" % [path, weight]
	if _font_cache.has(key):
		return _font_cache[key]
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var base := load(path) as FontFile
	base.multichannel_signed_distance_field = true
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_font_cache[key] = fv
	return fv

# Text facing `normal` (an axis vector), cap height in metres.
func _text(p: Node, tname: String, text: String, pos: Vector3, normal: Vector3, cap: float, color: Color,
		serif := false, outline := Color(0, 0, 0, 0)) -> Label3D:
	var l := Label3D.new()
	l.name = tname
	l.text = text
	l.font = _font("res://assets/fonts/PlayfairDisplay.ttf", 700) if serif else _font("res://assets/fonts/Oswald.ttf", 600)
	l.font_size = 128
	l.pixel_size = cap / (128.0 * (0.708 if serif else 0.81))
	l.modulate = color
	if outline.a > 0.0:
		l.outline_size = 10
		l.outline_modulate = outline
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.render_priority = 1
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.position = pos
	l.rotation.y = atan2(normal.x, normal.z)
	p.add_child(l, true)
	return l

# Brass plate with raised letters (name and number plates).
func _brass_plate(p: Node, pname: String, text: String, pos: Vector3, normal: Vector3, size: Vector2, cap: float,
		ground := "red") -> void:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	n.rotation.y = atan2(normal.x, normal.z)
	p.add_child(n)
	_box(n, "PlateRim", Vector3(size.x, size.y, 0.012), Vector3(0, 0, 0.006), "brass")
	_box(n, "PlateGround", Vector3(size.x - 0.03, size.y - 0.03, 0.004), Vector3(0, 0, 0.013), ground)
	_text(n, "PlateText", text, Vector3(0, 0, 0.017), Vector3(0, 0, 1), cap, Color(0.95, 0.8, 0.42), false)

# A spoked wheel pair on an axle at x; wheels in the z = ±GAUGE_HALF planes.
func _wheelset(p: Node, wname: String, x: float, r: float, spokes: int, mat: String, crank := false) -> void:
	var yc := RAIL_Y + r
	_rod(p, wname + "_Axle", Vector3(x, yc, -GAUGE_HALF), Vector3(x, yc, GAUGE_HALF), 0.07, "steel_dark")
	for zs in [-1.0, 1.0]:
		var z: float = zs * GAUGE_HALF
		var w := Node3D.new()
		w.name = "%s_%s" % [wname, "L" if zs < 0.0 else "R"]
		w.position = Vector3(x, yc, z)
		p.add_child(w)
		_gear.wheels.append([w, r, 0.0 if zs < 0.0 else PI * 0.5])
		_torus(w, "Tyre", r * 0.83, r, Vector3.ZERO, "steel_dark", Vector3.BACK)
		_torus(w, "Rim", r * 0.78, r * 0.86, Vector3.ZERO, mat, Vector3.BACK)
		_cyl(w, "Hub", r * 0.17, r * 0.17, 0.16, Vector3.ZERO, mat, Vector3.BACK, 16)
		_cyl(w, "HubCap", r * 0.09, r * 0.09, 0.2, Vector3.ZERO, "steel", Vector3.BACK, 12)
		for i in spokes:
			var a := i * TAU / spokes
			var len := r * 0.66
			var s := _box(w, "Spoke", Vector3(r * 0.07, len, 0.05), Vector3(0, 0, 0), mat)
			s.rotation.z = a
			s.position = Vector3(-sin(a), cos(a), 0) * (r * 0.17 + len * 0.5)
		if crank:
			# Balance weight between the spokes opposite the crank, and the crankpin outside.
			var bw := _box(w, "BalanceWeight", Vector3(r * 0.5, r * 0.22, 0.06), Vector3(0, 0, 0), mat)
			bw.rotation.z = deg_to_rad(40.0)
			bw.position = Vector3(-0.42, 0.36, 0) * r
			var pin := _crank_pin(r)
			_cyl(w, "CrankBoss", 0.08, 0.08, 0.1, Vector3(pin.x, pin.y, zs * 0.06), mat, Vector3.BACK, 16)
			_cyl(w, "CrankPin", 0.045, 0.045, 0.26, Vector3(pin.x, pin.y, zs * 0.14), "steel", Vector3.BACK, 12)

# Crankpin offset from the wheel centre (all drivers in phase on one side).
func _crank_pin(_r: float) -> Vector2:
	return Vector2(0.26, -0.2)

# ————— tender —————

func _build_tender(g: Node3D) -> void:
	var hw := T_HALF_W
	var xc := -T_LEN * 0.5
	var side_w := hw - COR_HALF
	# Tank body in three blocks around the corridor (the rear and front faces form the end plates,
	# open at the corridor doorways) and the top plate over the corridor.
	for zs in [-1.0, 1.0]:
		_box(g, "TankSide", Vector3(T_LEN, T_TOP + 0.25, side_w), Vector3(xc, (T_TOP - 0.25) * 0.5, zs * (COR_HALF + side_w * 0.5)), "green")
	_box(g, "TankTop", Vector3(T_LEN, T_TOP - COR_H, COR_HALF * 2.0), Vector3(xc, (T_TOP + COR_H) * 0.5, 0), "green")
	_box(g, "TankFloor", Vector3(T_LEN, 0.25, COR_HALF * 2.0), Vector3(xc, -0.125, 0), "black")
	# Lining: black band with gold lines framing each tank side panel.
	for zs in [-1.0, 1.0]:
		var z: float = zs * (hw + 0.003)
		for y in [0.05, T_TOP - 0.15]:
			_box(g, "LiningBlack", Vector3(T_LEN - 0.3, 0.05, 0.004), Vector3(xc, y, z), "black")
			_box(g, "LiningGold", Vector3(T_LEN - 0.36, 0.012, 0.006), Vector3(xc, y + (0.04 if y < 1.0 else -0.04), z), "gold")
		for x in [-0.15, -T_LEN + 0.15]:
			_box(g, "LiningBlack", Vector3(0.05, T_TOP - 0.2, 0.004), Vector3(x, T_TOP * 0.5 - 0.05, z), "black")
			_box(g, "LiningGold", Vector3(0.012, T_TOP - 0.28, 0.006), Vector3(x + (-0.04 if x > -1.0 else 0.04), T_TOP * 0.5 - 0.05, z), "gold")
		_text(g, "TenderLettering", company_name, Vector3(xc, 1.05, z + 0.003 * zs), Vector3(0, 0, zs), 0.16,
				Color(0.85, 0.68, 0.32), true, Color(0.08, 0.06, 0.03, 0.9))
	# Coal space on the front of the tank: flared sides, front plate and a heap of coal.
	var cx0 := -T_LEN + 0.15
	var cx1 := -T_LEN + 3.4
	for zs in [-1.0, 1.0]:
		var fl := _box(g, "CoalRail", Vector3(cx1 - cx0, 0.42, 0.04), Vector3((cx0 + cx1) * 0.5, T_TOP + 0.2, zs * (hw - 0.03)), "green")
		fl.rotation.x = zs * -0.25
	_box(g, "CoalPlate", Vector3(0.04, 0.42, hw * 2.0), Vector3(cx1, T_TOP + 0.2, 0), "green")
	for i in 22:
		var hx := lerpf(cx0 + 0.3, cx1 - 0.25, fposmod(sin(i * 12.9898) * 43758.5453, 1.0))
		var hz := lerpf(-hw + 0.3, hw - 0.3, fposmod(sin(i * 78.233) * 43758.5453, 1.0))
		var hy := T_TOP + 0.08 + 0.18 * (1.0 - absf(hz) / hw)
		_ball(g, "Coal", Vector3(hx, hy, hz), 0.22 + 0.1 * fposmod(i * 0.37, 1.0), "coal", Vector3(1.0, 0.45, 0.85))
	# Water filler, tank vents, rear ladder, lamps.
	_cyl(g, "WaterFiller", 0.28, 0.28, 0.12, Vector3(-1.3, T_TOP + 0.06, 0), "green")
	_cyl(g, "WaterFillerLid", 0.3, 0.3, 0.03, Vector3(-1.3, T_TOP + 0.135, 0), "black")
	_rod(g, "LidHandle", Vector3(-1.45, T_TOP + 0.16, 0), Vector3(-1.15, T_TOP + 0.16, 0), 0.015, "steel")
	for zs in [-1.0, 1.0]:
		_cyl(g, "TankVent", 0.05, 0.05, 0.25, Vector3(-3.0, T_TOP + 0.12, zs * 0.9), "black")
		_ball(g, "TankVentCap", Vector3(-3.0, T_TOP + 0.26, zs * 0.9), 0.07, "black")
	for i in 8:
		_rod(g, "LadderRung", Vector3(0.05, 0.1 + i * 0.25, 0.62), Vector3(0.05, 0.1 + i * 0.25, 1.02), 0.012, "steel")
	for zz in [0.62, 1.02]:
		_rod(g, "LadderRail", Vector3(0.04, 0.0, zz), Vector3(0.04, T_TOP, zz), 0.016, "black")
	_tail_lamp(g, Vector3(0.08, T_TOP - 0.25, -0.95))
	_box(g, "LampIron", Vector3(0.06, 0.12, 0.03), Vector3(0.04, T_TOP - 0.42, 0.95), "black")
	# Rear doorway frame and a notice.
	for zs in [-1.0, 1.0]:
		_box(g, "DoorJamb", Vector3(0.05, COR_H, 0.06), Vector3(0.025, COR_H * 0.5, zs * (COR_HALF + 0.03)), "black")
	_box(g, "DoorHead", Vector3(0.05, 0.06, COR_HALF * 2.0 + 0.12), Vector3(0.025, COR_H + 0.03, 0), "black")
	_brass_plate(g, "CrewOnly", "ENGINE CREW ONLY", Vector3(0.006, COR_H + 0.12, -0.0), Vector3(1, 0, 0), Vector2(0.62, 0.11), 0.045)
	# Underframe: solebars, buffer beam, buffers, axleboxes and springs, wheels, brake gear.
	for zs in [-1.0, 1.0]:
		_box(g, "Solebar", Vector3(T_LEN - 0.2, 0.32, 0.1), Vector3(xc, -0.42, zs * 1.2), "black")
	_box(g, "RearBeam", Vector3(0.14, 0.45, hw * 2.0), Vector3(-0.07, -0.42, 0), "red")
	_buffers(g, 0.0, 1.0)
	_box(g, "CouplingHook", Vector3(0.3, 0.1, 0.09), Vector3(0.13, -0.46, 0), "steel_dark")
	_rod(g, "VacuumPipe", Vector3(0.0, -0.6, 0.35), Vector3(0.3, -0.85, 0.42), 0.035, "rubber")
	for ax in [-1.4, -4.3, -7.2]:
		_wheelset(g, "TenderWheels", ax, 0.6, 10, "green")
		for zs in [-1.0, 1.0]:
			_box(g, "Axlebox", Vector3(0.32, 0.36, 0.18), Vector3(ax, RAIL_Y + 0.6, zs * 1.2), "black")
			for k in 6:
				_box(g, "SpringLeaf", Vector3(1.0 - k * 0.12, 0.022, 0.12), Vector3(ax, RAIL_Y + 0.83 + k * 0.024, zs * 1.2), "steel_dark")
			_box(g, "BrakeShoe", Vector3(0.1, 0.32, 0.08), Vector3(ax + 0.64, RAIL_Y + 0.6, zs * GAUGE_HALF), "black")
	# Front of the tender (facing the cab): coal hole, tool cupboards, handbrake, water valves.
	var fx := -T_LEN - 0.003
	_box(g, "CoalHole", Vector3(0.02, 0.5, 0.55), Vector3(fx, 0.95, 0.85), "coal")
	_box(g, "ShovellingPlate", Vector3(0.35, 0.03, 0.6), Vector3(fx - 0.17, 0.7, 0.85), "steel")
	for zz in [-1.05, -0.65]:
		_box(g, "ToolCupboard", Vector3(0.02, 0.6, 0.36), Vector3(fx, 1.45, zz), "green")
		_ball(g, "CupboardKnob", Vector3(fx - 0.02, 1.45, zz + 0.12), 0.02, "brass")
	_rod(g, "HandbrakeColumn", Vector3(fx - 0.12, 0.0, -0.95), Vector3(fx - 0.12, 1.0, -0.95), 0.03, "black")
	_torus(g, "HandbrakeWheel", 0.13, 0.16, Vector3(fx - 0.12, 1.02, -0.95), "black")
	for zz in [-0.75, 0.7]:
		_rod(g, "WaterValveSpindle", Vector3(fx, 0.45, zz), Vector3(fx - 0.12, 0.45, zz), 0.015, "steel")
		_torus(g, "WaterValveWheel", 0.05, 0.065, Vector3(fx - 0.12, 0.45, zz), "red", Vector3.RIGHT)
	for zs in [-1.0, 1.0]:
		_rod(g, "Handrail", Vector3(fx - 0.04, 0.1, zs * (hw - 0.04)), Vector3(fx - 0.04, 1.9, zs * (hw - 0.04)), 0.016, "brass")

func _tail_lamp(g: Node, p: Vector3) -> void:
	_box(g, "TailLampBody", Vector3(0.16, 0.22, 0.18), p, "red")
	_cyl(g, "TailLampLens", 0.06, 0.06, 0.03, p + Vector3(0.09, 0, 0), "lamp_red", Vector3.RIGHT)
	_rod(g, "TailLampHandle", p + Vector3(0, 0.11, -0.05), p + Vector3(0, 0.16, 0.05), 0.008, "black")
	var l := OmniLight3D.new()
	l.name = "TailLight"
	l.position = p + Vector3(0.2, 0, 0)
	l.light_color = Color(1.0, 0.1, 0.05)
	l.light_energy = 0.6
	l.omni_range = 1.5
	g.add_child(l)

func _buffers(g: Node, x: float, dir: float) -> void:
	for zs in [-1.0, 1.0]:
		var z: float = zs * 0.875
		_cyl(g, "BufferStock", 0.085, 0.085, 0.32, Vector3(x + dir * 0.16, -0.34, z), "black", Vector3.RIGHT)
		_cyl(g, "BufferHead", 0.19, 0.19, 0.05, Vector3(x + dir * 0.345, -0.34, z), "steel", Vector3.RIGHT)

# The passage through the tank: cream steel walls with a varnished dado and handrail, a planked
# floor, two lamps; an open door into the cab at the front.
func _build_tender_corridor(g: Node3D) -> void:
	var xc := -T_LEN * 0.5
	for zs in [-1.0, 1.0]:
		var z: float = zs * (COR_HALF - 0.005)
		_box(g, "CorridorWall", Vector3(T_LEN, COR_H, 0.01), Vector3(xc, COR_H * 0.5, z), "cream")
		_box(g, "CorridorDado", Vector3(T_LEN, 0.9, 0.012), Vector3(xc, 0.45, z - zs * 0.004), "wood")
		_box(g, "DadoRail", Vector3(T_LEN, 0.04, 0.03), Vector3(xc, 0.91, z - zs * 0.012), "wood")
		var rivets := int(T_LEN / 0.25)
		for i in rivets:
			_ball(g, "Rivet", Vector3(-0.12 - i * 0.25, 1.55, z - zs * 0.004), 0.008, "cream")
	_box(g, "CorridorCeiling", Vector3(T_LEN, 0.01, COR_HALF * 2.0), Vector3(xc, COR_H - 0.005, 0), "cream")
	_box(g, "CorridorFloor", Vector3(T_LEN, 0.01, COR_HALF * 2.0 - 0.02), Vector3(xc, 0.005, 0), "floor")
	for i in 9:
		_box(g, "FloorJoint", Vector3(0.006, 0.003, COR_HALF * 2.0 - 0.02), Vector3(-0.5 - i * 0.95, 0.011, 0), "black")
	_rod(g, "CorridorHandrail", Vector3(-0.3, 1.0, COR_HALF - 0.05), Vector3(-T_LEN + 0.3, 1.0, COR_HALF - 0.05), 0.014, "brass")
	for x in [-2.2, -6.4]:
		_cyl(g, "CorridorLampBase", 0.07, 0.07, 0.03, Vector3(x, COR_H - 0.025, 0), "brass")
		_ball(g, "CorridorLampGlobe", Vector3(x, COR_H - 0.08, 0), 0.06, "lamp_white")
		var l := OmniLight3D.new()
		l.name = "CorridorLight"
		l.position = Vector3(x, COR_H - 0.2, 0)
		l.light_color = Color(1.0, 0.92, 0.75)
		l.light_energy = 0.7
		l.omni_range = 3.0
		g.add_child(l)
	_text(g, "CorridorSign", "CAB  ·  MIND THE FALL PLATE", Vector3(-T_LEN + 0.6, COR_H - 0.12, -COR_HALF + 0.012), Vector3(0, 0, 1), 0.035, Color(0.15, 0.1, 0.05))

# ————— cab —————

func _build_cab(g: Node3D) -> void:
	var x0 := CAB_X0
	var x1 := CAB_X1
	var xc := (x0 + x1) * 0.5
	var ln := x0 - x1
	_box(g, "Footplate", Vector3(ln, 0.08, CAB_HALF_W * 2.0), Vector3(xc, -0.04, 0), "floor")
	for i in 7:
		_box(g, "FloorBoardJoint", Vector3(ln, 0.003, 0.006), Vector3(xc, 0.002, -CAB_HALF_W + (i + 1) * CAB_HALF_W * 2.0 / 8.0), "black")
	_box(g, "FallPlate", Vector3(0.5, 0.012, COR_HALF * 2.0 + 0.2), Vector3(x0 + 0.1, 0.006, 0), "steel")
	# Sides: full height at the front with a window, a high panel over the rear opening.
	var w0 := -9.75
	var wa := -9.85
	var wb := -10.85
	for zs in [-1.0, 1.0]:
		var z: float = zs * CAB_HALF_W
		_box(g, "SideLower", Vector3(w0 - x1, 1.25, 0.04), Vector3((w0 + x1) * 0.5, 0.625, z), "green")
		_box(g, "SideUpper", Vector3(x0 - x1, CAB_ROOF - 1.95, 0.04), Vector3(xc, (CAB_ROOF + 1.95) * 0.5, z), "green")
		_box(g, "SidePostRear", Vector3(w0 - wa if wa < w0 else 0.1, 0.7, 0.04), Vector3((w0 + wa) * 0.5, 1.6, z), "green")
		_box(g, "SidePostFront", Vector3(wb - x1, 0.7, 0.04), Vector3((wb + x1) * 0.5, 1.6, z), "green")
		_box(g, "SideRearUpper", Vector3(x0 - w0, CAB_ROOF - 1.55, 0.04), Vector3((x0 + w0) * 0.5, (CAB_ROOF + 1.55) * 0.5, z), "green")
		_box(g, "SideLining", Vector3(x0 - x1, CAB_ROOF, 0.01), Vector3(xc, CAB_ROOF * 0.5, z - zs * 0.025), "buff")
		_box(g, "WindowGlass", Vector3(wa - wb, 0.7, 0.008), Vector3((wa + wb) * 0.5, 1.6, z), "glass")
		for x in [wa, wb]:
			_box(g, "WindowFrame", Vector3(0.03, 0.72, 0.05), Vector3(x, 1.6, z), "wood")
		for y in [1.25, 1.95]:
			_box(g, "WindowFrame", Vector3(wa - wb + 0.03, 0.03, 0.05), Vector3((wa + wb) * 0.5, y, z), "wood")
		# Rear opening: half door (closed), handrail, steps and the cab-side number plate.
		var door := _box(g, "CabHalfDoor", Vector3(x0 - w0 - 0.05, 0.95, 0.035), Vector3((x0 + w0) * 0.5, 0.5, z), "green")
		door.name = "CabHalfDoor"
		_rod(g, "DoorHinge", Vector3(w0 - 0.02, 0.1, z), Vector3(w0 - 0.02, 0.9, z), 0.015, "black")
		_rod(g, "CabHandrail", Vector3(x0 + 0.02, 0.0, z + zs * 0.05), Vector3(x0 + 0.02, 1.6, z + zs * 0.05), 0.016, "brass")
		_rod(g, "CabHandrailFront", Vector3(w0 + 0.02, 0.0, z + zs * 0.05), Vector3(w0 + 0.02, 1.5, z + zs * 0.05), 0.016, "brass")
		for k in 2:
			_box(g, "Step", Vector3(0.45, 0.03, 0.22), Vector3((x0 + w0) * 0.5, -0.45 - k * 0.4, z + zs * 0.08), "steel_dark")
		_box(g, "StepHanger", Vector3(0.04, 0.8, 0.04), Vector3((x0 + w0) * 0.5 - 0.2, -0.5, z + zs * 0.1), "black")
		_brass_plate(g, "NumberPlate", engine_number, Vector3(xc - 0.35, 0.75, z + zs * 0.022), Vector3(0, 0, zs), Vector2(0.5, 0.22), 0.11)
	# Roof: an arched sheet in segments, with a sliding ventilator, overhanging the sides.
	var segs := 9
	var rw := CAB_HALF_W + 0.06
	var rise := 0.28
	for i in segs:
		var za := -rw + i * rw * 2.0 / segs
		var zb := -rw + (i + 1) * rw * 2.0 / segs
		var ya := CAB_ROOF + rise * (1.0 - pow(za / rw, 2.0))
		var yb := CAB_ROOF + rise * (1.0 - pow(zb / rw, 2.0))
		var seg := _box(g, "RoofSheet", Vector3(x0 - x1 + 0.3, 0.035, Vector2(za, ya).distance_to(Vector2(zb, yb)) + 0.01),
				Vector3(xc, (ya + yb) * 0.5, (za + zb) * 0.5), "black")
		seg.rotation.x = -atan2(yb - ya, zb - za)
		var inner := _box(g, "RoofLining", Vector3(x0 - x1, 0.01, Vector2(za, ya).distance_to(Vector2(zb, yb)) + 0.01),
				Vector3(xc, (ya + yb) * 0.5 - 0.025, (za + zb) * 0.5), "buff")
		inner.rotation.x = seg.rotation.x
	_box(g, "RoofVent", Vector3(0.7, 0.06, 0.5), Vector3(xc, CAB_ROOF + rise + 0.03, 0), "black")
	# Spectacle plate (front) with two round windows above the firebox shoulders.
	var front := CSGCombiner3D.new()
	front.name = "SpectaclePlate"
	g.add_child(front)
	# Plate outline follows the roof's arch so no gap is left under it.
	var outline := PackedVector2Array([Vector2(-CAB_HALF_W, 0.0), Vector2(CAB_HALF_W, 0.0)])
	var n_arc := 16
	for i in n_arc + 1:
		var zz := CAB_HALF_W - i * CAB_HALF_W * 2.0 / n_arc
		outline.append(Vector2(zz, CAB_ROOF + rise * (1.0 - pow(zz / rw, 2.0)) - 0.01))
	var plate := CSGPolygon3D.new()
	plate.polygon = outline
	plate.depth = 0.04
	plate.rotation.y = PI * 0.5            # extrudes along -X from its origin
	plate.position = Vector3(x1, 0, 0)
	plate.material = _mat("green")
	front.add_child(plate)
	for zs in [-1.0, 1.0]:
		var hole := CSGCylinder3D.new()
		hole.radius = 0.17
		hole.height = 0.2
		hole.sides = 24
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		hole.position = Vector3(x1 - 0.02, 1.72, zs * 1.12)
		hole.rotation.z = PI * 0.5
		front.add_child(hole)
		_cyl(g, "SpectacleGlass", 0.17, 0.17, 0.008, Vector3(x1 - 0.02, 1.72, zs * 1.12), "glass", Vector3.RIGHT)
		_torus(g, "SpectacleRim", 0.165, 0.205, Vector3(x1 + 0.005, 1.72, zs * 1.12), "brass", Vector3.RIGHT)
	_box(g, "FrontLining", Vector3(0.01, CAB_ROOF, CAB_HALF_W * 2.0 - 0.06), Vector3(x1 + 0.006, CAB_ROOF * 0.5, 0), "buff")
	# Cab lamp.
	_cyl(g, "CabLampBase", 0.06, 0.06, 0.03, Vector3(xc + 0.3, CAB_ROOF + 0.22, 0.5), "brass")
	_ball(g, "CabLampGlobe", Vector3(xc + 0.3, CAB_ROOF + 0.16, 0.5), 0.055, "lamp_white")
	var l := OmniLight3D.new()
	l.name = "CabLight"
	l.position = Vector3(xc + 0.3, CAB_ROOF, 0.4)
	l.light_color = Color(1.0, 0.9, 0.7)
	l.light_energy = 0.8
	l.omni_range = 3.5
	l.shadow_enabled = true
	g.add_child(l)

# The firebox back inside the cab with its fittings (local face at BH_X, facing +X).
const BH_X := -11.03

func _build_backhead(g: Node3D) -> void:
	var bh := _group(g, "Backhead")
	var w := 0.95
	_box(bh, "BackheadLower", Vector3(0.16, 1.05, w * 2.0), Vector3(CAB_X1 + 0.09, 0.525, 0), "black")
	_cyl(bh, "BackheadTop", w, w, 0.16, Vector3(CAB_X1 + 0.09, 1.05, 0), "black", Vector3.RIGHT, 40)
	# Lagging clamp bands and a polished edge ring.
	_torus(bh, "BackheadRing", w - 0.02, w + 0.01, Vector3(BH_X, 1.05, 0), "steel", Vector3.RIGHT)
	# Firehole door with its glow.
	var fy := 0.62
	_box(bh, "FireholeFrame", Vector3(0.04, 0.42, 0.56), Vector3(BH_X + 0.02, fy, 0), "steel_dark")
	for zs in [-1.0, 1.0]:
		_box(bh, "FireholeLeaf", Vector3(0.03, 0.34, 0.235), Vector3(BH_X + 0.045, fy, zs * 0.12), "black")
		_rod(bh, "FireholeHandle", Vector3(BH_X + 0.07, fy + 0.05, zs * 0.2), Vector3(BH_X + 0.07, fy - 0.05, zs * 0.2), 0.012, "steel")
	_box(bh, "FireGlowGap", Vector3(0.01, 0.3, 0.012), Vector3(BH_X + 0.062, fy, 0), "fire")
	_box(bh, "FireGlowSill", Vector3(0.01, 0.02, 0.44), Vector3(BH_X + 0.045, fy - 0.19, 0), "fire")
	_box(bh, "DeflectorPlate", Vector3(0.12, 0.02, 0.5), Vector3(BH_X + 0.08, fy + 0.22, 0), "steel")
	if fire_lit:
		var fl := OmniLight3D.new()
		fl.name = "FireGlow"
		fl.position = Vector3(BH_X + 0.35, fy - 0.05, 0)
		fl.light_color = Color(1.0, 0.45, 0.15)
		fl.light_energy = 1.2
		fl.omni_range = 2.6
		bh.add_child(fl)
	# Gauges: boiler pressure (big, centre), steam chest and vacuum brake.
	_gauge(bh, "BoilerPressure", Vector3(BH_X, 1.66, 0.22), 0.13, 0.0, 300.0, 6, 5, 220.0, Vector2(250.0, 300.0), Vector2(200.0, 230.0), "BOILER  lb/in²")
	_gauge(bh, "SteamChest", Vector3(BH_X, 1.66, 0.55), 0.085, 0.0, 300.0, 6, 5, 180.0, Vector2(-1, -1), Vector2(-1, -1), "STEAM CHEST")
	_gauge(bh, "VacuumBrake", Vector3(BH_X, 1.66, -0.25), 0.12, 0.0, 30.0, 6, 5, 21.0, Vector2(0.0, 12.0), Vector2(19.0, 23.0), "VACUUM  in.")
	# Water gauge glasses, either side of the firehole, in protector frames.
	for zs in [-1.0, 1.0]:
		var z: float = zs * 0.62
		_box(bh, "GlassTopCock", Vector3(0.06, 0.08, 0.07), Vector3(BH_X + 0.04, 1.4, z), "brass")
		_box(bh, "GlassBottomCock", Vector3(0.06, 0.08, 0.07), Vector3(BH_X + 0.04, 0.93, z), "brass")
		_cyl(bh, "GaugeGlass", 0.016, 0.016, 0.39, Vector3(BH_X + 0.05, 1.165, z), "glass")
		_cyl(bh, "WaterLevel", 0.013, 0.013, 0.24, Vector3(BH_X + 0.05, 1.09, z), "water")
		for k in [-1.0, 1.0]:
			_rod(bh, "GlassGuard", Vector3(BH_X + 0.075, 0.97, z + k * 0.028), Vector3(BH_X + 0.075, 1.36, z + k * 0.028), 0.005, "brass")
		_rod(bh, "DrainCockHandle", Vector3(BH_X + 0.07, 0.89, z), Vector3(BH_X + 0.12, 0.84, z + zs * 0.06), 0.008, "brass")
	# Regulator: boss and long handle across the top of the backhead (driver's side, -Z).
	_cyl(bh, "RegulatorBoss", 0.06, 0.06, 0.08, Vector3(BH_X + 0.04, 1.42, -0.05), "steel", Vector3.RIGHT)
	_rod(bh, "RegulatorHandle", Vector3(BH_X + 0.08, 1.42, -0.05), Vector3(BH_X + 0.12, 1.3, -0.52), 0.016, "steel")
	_ball(bh, "RegulatorGrip", Vector3(BH_X + 0.12, 1.3, -0.53), 0.025, "wood", Vector3(1, 1, 1.6))
	# Steam manifold across the top with valve wheels (injectors, blower, ejector, whistle).
	_cyl(bh, "Manifold", 0.05, 0.05, 1.0, Vector3(BH_X + 0.06, 1.92, 0), "brass", Vector3.BACK, 16)
	for i in 5:
		var z := -0.4 + i * 0.2
		_rod(bh, "ValveSpindle", Vector3(BH_X + 0.06, 1.92, z), Vector3(BH_X + 0.17, 1.86, z), 0.01, "steel")
		_torus(bh, "ValveWheel", 0.035, 0.05, Vector3(BH_X + 0.17, 1.86, z), "red" if i % 2 == 0 else "black", Vector3.RIGHT)
	_rod(bh, "WhistleCord", Vector3(BH_X + 0.1, 2.0, 0.2), Vector3(BH_X + 0.2, 1.3, 0.25), 0.004, "black")
	_ball(bh, "WhistleHandle", Vector3(BH_X + 0.2, 1.28, 0.25), 0.02, "wood")
	# Copper steam pipes down the sides of the backhead.
	for zs in [-1.0, 1.0]:
		_rod(bh, "SteamPipe", Vector3(BH_X + 0.05, 1.92, zs * 0.5), Vector3(BH_X + 0.05, 1.5, zs * 0.85), 0.02, "copper")
		_rod(bh, "SteamPipe", Vector3(BH_X + 0.05, 1.5, zs * 0.85), Vector3(BH_X + 0.05, 0.2, zs * 0.88), 0.02, "copper")
	# Driver's brake valve on the -Z side.
	_box(bh, "BrakeValveBody", Vector3(0.14, 0.18, 0.14), Vector3(BH_X + 0.08, 1.15, -0.85), "brass")
	_rod(bh, "BrakeValveHandle", Vector3(BH_X + 0.13, 1.25, -0.85), Vector3(BH_X + 0.3, 1.3, -0.75), 0.012, "steel")
	_ball(bh, "BrakeValveGrip", Vector3(BH_X + 0.3, 1.3, -0.75), 0.022, "black")
	_text(bh, "BrakePlate", "BRAKE", Vector3(BH_X + 0.155, 1.15, -0.85), Vector3(1, 0, 0), 0.022, Color(0.15, 0.1, 0.04))

# Boiler-fitting gauge: brass bezel, dial (gauge_dial shader), needle and a caption under it.
func _gauge(p: Node, gname: String, pos: Vector3, r: float, vmin: float, vmax: float, majors: int, minors: int,
		value: float, red: Vector2, green: Vector2, caption: String) -> void:
	var g := Node3D.new()
	g.name = gname
	g.position = pos
	g.rotation.y = PI * 0.5            # local +Z faces +X (into the cab)
	p.add_child(g)
	_cyl(g, "Case", r + 0.012, r + 0.012, 0.06, Vector3(0, 0, 0.03), "black", Vector3.BACK, 32)
	_torus(g, "Bezel", r - 0.004, r + 0.016, Vector3(0, 0, 0.06), "brass", Vector3.BACK)
	var dial := MeshInstance3D.new()
	dial.name = "Dial"
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	dial.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/props/gauge_dial.gdshader")
	sm.set_shader_parameter("major_count", majors)
	sm.set_shader_parameter("minor_per_major", minors)
	if red.x >= 0.0:
		sm.set_shader_parameter("red_band", Vector2((red.x - vmin) / (vmax - vmin), (red.y - vmin) / (vmax - vmin)))
	if green.x >= 0.0:
		sm.set_shader_parameter("green_band", Vector2((green.x - vmin) / (vmax - vmin), (green.y - vmin) / (vmax - vmin)))
	dial.material_override = sm
	dial.position = Vector3(0, 0, 0.061)
	g.add_child(dial)
	var a := deg_to_rad(-135.0 + 270.0 * (value - vmin) / (vmax - vmin))
	var needle := _box(g, "Needle", Vector3(r * 0.05, r * 0.8, 0.003), Vector3(0, 0, 0.066), "black")
	needle.rotation.z = -a
	needle.position = Vector3(sin(a), cos(a), 0) * r * 0.32 + Vector3(0, 0, 0.066)
	_cyl(g, "NeedleHub", r * 0.07, r * 0.07, 0.008, Vector3(0, 0, 0.068), "brass", Vector3.BACK, 12)
	_cyl(g, "Glass", r, r, 0.004, Vector3(0, 0, 0.075), "glass", Vector3.BACK, 32)
	_text(g, "Caption", caption, Vector3(0, -r - 0.03, 0.04), Vector3(0, 0, 1), r * 0.16, Color(0.85, 0.75, 0.5))

func _build_cab_fittings(g: Node3D) -> void:
	# Screw reverser on the driver's side (-Z) with its cut-off scale.
	var rx := -10.55
	var rz := -1.05
	_box(g, "ReverserPedestal", Vector3(0.14, 0.95, 0.14), Vector3(rx, 0.475, rz), "black")
	_box(g, "ReverserScale", Vector3(0.02, 0.32, 0.1), Vector3(rx + 0.08, 0.75, rz), "brass")
	for k in 7:
		_box(g, "ScaleTick", Vector3(0.004, 0.003, 0.05), Vector3(rx + 0.091, 0.62 + k * 0.045, rz), "black")
	_text(g, "ReverserLabel", "FORE\nMID\nBACK", Vector3(rx + 0.092, 0.75, rz + 0.07), Vector3(1, 0, 0), 0.016, Color(0.12, 0.08, 0.03))
	_rod(g, "ReverserSpindle", Vector3(rx, 0.98, rz), Vector3(rx + 0.25, 0.98, rz), 0.02, "steel")
	_torus(g, "ReverserWheel", 0.15, 0.18, Vector3(rx + 0.25, 0.98, rz), "steel", Vector3.RIGHT)
	_rod(g, "ReverserHandle", Vector3(rx + 0.27, 1.12, rz + 0.06), Vector3(rx + 0.36, 1.12, rz + 0.06), 0.015, "wood")
	# Tip-up seats on both sides with padded cushions.
	for zs in [-1.0, 1.0]:
		var sz: float = zs * (CAB_HALF_W - 0.2)
		_box(g, "SeatBracket", Vector3(0.04, 0.25, 0.3), Vector3(-9.95, 0.82, zs * (CAB_HALF_W - 0.17)), "black")
		_box(g, "Seat", Vector3(0.36, 0.05, 0.32), Vector3(-9.95, 0.95, sz), "wood")
		_box(g, "SeatPad", Vector3(0.32, 0.04, 0.28), Vector3(-9.95, 0.995, sz), "rubber")
	# Shovel against the tender front, fire irons on their rack, coal on the footplate, oil can.
	_box(g, "ShovelBlade", Vector3(0.03, 0.32, 0.26), Vector3(-8.75, 0.25, 0.42), "steel_dark", Vector3(0, 0, 0.18))
	_rod(g, "ShovelShaft", Vector3(-8.76, 0.42, 0.42), Vector3(-8.68, 1.05, 0.42), 0.018, "wood")
	_rod(g, "ShovelGrip", Vector3(-8.68, 1.05, 0.36), Vector3(-8.68, 1.05, 0.48), 0.016, "wood")
	for k in 3:
		var y := 1.75 + k * 0.08
		_rod(g, "FireIron", Vector3(-8.66, y, -0.6), Vector3(-8.66, y, 1.2), 0.012, "steel_dark")
		_rod(g, "FireIronHook", Vector3(-8.66, y, 1.2), Vector3(-8.66, y - 0.12, 1.22), 0.012, "steel_dark")
	for i in 9:
		var cx := -8.85 - fposmod(i * 0.61, 1.0) * 0.5
		var cz := 0.55 + fposmod(i * 0.37, 1.0) * 0.6
		_ball(g, "FloorCoal", Vector3(cx, 0.03, cz), 0.07, "coal", Vector3(1.0, 0.6, 0.8))
	_cyl(g, "OilCan", 0.06, 0.07, 0.14, Vector3(-10.9, 0.07, 1.05), "steel")
	_rod(g, "OilCanSpout", Vector3(-10.9, 0.13, 1.05), Vector3(-10.78, 0.32, 1.05), 0.008, "steel")
	_rod(g, "OilCanHandle", Vector3(-10.95, 0.1, 1.05), Vector3(-10.98, 0.2, 1.05), 0.01, "steel")
	# Sanding lever on the driver's side wall.
	_rod(g, "SandingLever", Vector3(-10.2, 0.6, -CAB_HALF_W + 0.04), Vector3(-10.1, 1.25, -CAB_HALF_W + 0.1), 0.014, "steel")
	_ball(g, "SandingGrip", Vector3(-10.1, 1.25, -CAB_HALF_W + 0.1), 0.022, "black")

# ————— boiler and engine —————

func _build_boiler(g: Node3D) -> void:
	# Belpaire firebox with rounded shoulders, safety valves and whistle on top.
	var fx := (CAB_X1 + FIREBOX_X1) * 0.5
	var fl := CAB_X1 - FIREBOX_X1
	_box(g, "Firebox", Vector3(fl, 1.62, 1.6), Vector3(fx, 1.06, 0), "green")
	_box(g, "FireboxTop", Vector3(fl, 0.2, 1.44), Vector3(fx, 1.97, 0), "green")
	for zs in [-1.0, 1.0]:
		_cyl(g, "FireboxShoulder", 0.2, 0.2, fl, Vector3(fx, 1.86, zs * 0.72), "green", Vector3.RIGHT, 20)
	_box(g, "FireboxFoot", Vector3(fl + 0.02, 0.3, 1.64), Vector3(fx, 0.16, 0), "black")
	for zs in [-1.0, 1.0]:
		_cyl(g, "SafetyValve", 0.07, 0.07, 0.22, Vector3(fx - 0.25, 2.18, zs * 0.12), "brass")
		_ball(g, "SafetyValveCap", Vector3(fx - 0.25, 2.3, zs * 0.12), 0.07, "brass", Vector3(1, 0.5, 1))
	_cyl(g, "SafetyValveBase", 0.2, 0.25, 0.08, Vector3(fx - 0.25, 2.07, 0), "brass")
	_cyl(g, "Whistle", 0.05, 0.05, 0.28, Vector3(CAB_X1 - 0.25, 2.22, -0.3), "brass")
	_ball(g, "WhistleBell", Vector3(CAB_X1 - 0.25, 2.38, -0.3), 0.06, "brass", Vector3(1, 1.6, 1))
	# Barrel with lining bands, dome, handrails.
	var bx := (FIREBOX_X1 + BOILER_X1) * 0.5
	var bl := FIREBOX_X1 - BOILER_X1
	_cyl(g, "Barrel", BOILER_R, BOILER_R, bl, Vector3(bx, BOILER_Y, 0), "green", Vector3.RIGHT, 48)
	for x in [FIREBOX_X1 - 0.03, -15.2, -17.4, BOILER_X1 + 0.03]:
		_cyl(g, "BoilerBand", BOILER_R + 0.008, BOILER_R + 0.008, 0.06, Vector3(x, BOILER_Y, 0), "black", Vector3.RIGHT, 48)
		for k in [-1.0, 1.0]:
			_cyl(g, "BandLine", BOILER_R + 0.009, BOILER_R + 0.009, 0.01, Vector3(x + k * 0.04, BOILER_Y, 0), "gold", Vector3.RIGHT, 48)
	_cyl(g, "Dome", 0.32, 0.36, 0.3, Vector3(-16.2, BOILER_Y + BOILER_R + 0.08, 0), "green")
	_ball(g, "DomeTop", Vector3(-16.2, BOILER_Y + BOILER_R + 0.23, 0), 0.32, "green", Vector3(1, 0.45, 1))
	for zs in [-1.0, 1.0]:
		var z: float = zs * (BOILER_R + 0.09)
		_rod(g, "BoilerHandrail", Vector3(FIREBOX_X1 - 0.2, 1.35, z), Vector3(BOILER_X1 - 1.4, 1.35, z), 0.014, "steel")
		var x := FIREBOX_X1 - 0.3
		while x > BOILER_X1 - 1.4:
			_rod(g, "HandrailKnob", Vector3(x, 1.35, z), Vector3(x, 1.35, z - zs * 0.1), 0.01, "steel")
			x -= 1.2
		_rod(g, "Washout", Vector3(FIREBOX_X1 + 0.3, 1.4, zs * 0.8), Vector3(FIREBOX_X1 + 0.3, 1.4, zs * 0.85), 0.04, "brass")
	# Smokebox, saddle, door, chimney, front lamp.
	var sx := (BOILER_X1 + SMOKEBOX_X1) * 0.5
	var sl := BOILER_X1 - SMOKEBOX_X1
	_cyl(g, "Smokebox", BOILER_R + 0.05, BOILER_R + 0.05, sl, Vector3(sx, BOILER_Y, 0), "smokebox", Vector3.RIGHT, 48)
	_box(g, "Saddle", Vector3(sl, 0.75, 1.2), Vector3(sx, 0.05, 0), "smokebox")
	var dxp := SMOKEBOX_X1 - 0.03
	_cyl(g, "SmokeboxDoor", 0.78, 0.8, 0.07, Vector3(dxp, BOILER_Y, 0), "smokebox", Vector3.RIGHT, 48)
	_torus(g, "DoorRing", 0.76, 0.84, Vector3(SMOKEBOX_X1 + 0.005, BOILER_Y, 0), "steel_dark", Vector3.RIGHT)
	_cyl(g, "DartBoss", 0.07, 0.07, 0.08, Vector3(dxp - 0.06, BOILER_Y, 0), "steel", Vector3.RIGHT)
	_rod(g, "DartHandle", Vector3(dxp - 0.1, BOILER_Y + 0.12, 0), Vector3(dxp - 0.1, BOILER_Y - 0.12, 0), 0.014, "steel")
	_rod(g, "DartHandle", Vector3(dxp - 0.1, BOILER_Y, -0.12), Vector3(dxp - 0.1, BOILER_Y, 0.12), 0.014, "steel")
	for y in [BOILER_Y + 0.42, BOILER_Y - 0.42]:
		_box(g, "HingeStrap", Vector3(0.02, 0.06, 0.7), Vector3(dxp - 0.04, y, 0.3), "steel_dark")
	_brass_plate(g, "SmokeboxNumber", engine_number, Vector3(dxp - 0.045, BOILER_Y + 0.62, 0), Vector3(-1, 0, 0), Vector2(0.44, 0.14), 0.08, "black")
	_cyl(g, "Chimney", 0.22, 0.25, 0.42, Vector3(-20.5, BOILER_Y + BOILER_R + 0.22, 0), "smokebox")
	_cyl(g, "ChimneyLip", 0.27, 0.25, 0.06, Vector3(-20.5, BOILER_Y + BOILER_R + 0.46, 0), "smokebox")
	_lamp(g, Vector3(SMOKEBOX_X1 - 0.08, BOILER_Y + BOILER_R + 0.05, 0))

func _lamp(g: Node, p: Vector3) -> void:
	_box(g, "LampBody", Vector3(0.18, 0.22, 0.18), p, "black")
	_cyl(g, "LampLens", 0.065, 0.065, 0.03, p + Vector3(-0.1, 0, 0), "lamp_white", Vector3.RIGHT)
	_rod(g, "LampHandle", p + Vector3(0, 0.11, -0.05), p + Vector3(0, 0.16, 0.05), 0.008, "black")

func _build_running_gear(g: Node3D) -> void:
	# Running plate and its valance, continuous splashers over the drivers with the nameplate.
	var px0 := CAB_X1
	var px1 := BEAM_X
	var pl := px0 - px1
	_box(g, "RunningPlate", Vector3(pl, 0.04, T_HALF_W * 2.0), Vector3((px0 + px1) * 0.5, PLATE_Y - 0.02, 0), "black")
	for zs in [-1.0, 1.0]:
		var z: float = zs * T_HALF_W
		_box(g, "Valance", Vector3(pl, 0.13, 0.03), Vector3((px0 + px1) * 0.5, PLATE_Y - 0.085, z), "green")
		_box(g, "ValanceLine", Vector3(pl - 0.1, 0.012, 0.005), Vector3((px0 + px1) * 0.5, PLATE_Y - 0.085, z + zs * 0.016), "gold")
		_box(g, "Splasher", Vector3(5.9, 0.72, 0.22), Vector3(-15.95, PLATE_Y + 0.36, zs * 0.74), "green")
		_box(g, "SplasherBeading", Vector3(5.92, 0.025, 0.24), Vector3(-15.95, PLATE_Y + 0.73, zs * 0.74), "brass")
		_brass_plate(g, "Nameplate", engine_name, Vector3(-16.05, PLATE_Y + 0.4, zs * 0.852), Vector3(0, 0, zs), Vector2(1.5, 0.2), 0.11)
	# Frames.
	for zs in [-1.0, 1.0]:
		_box(g, "Frame", Vector3(CAB_X0 - BEAM_X - 0.2, 0.75, 0.04), Vector3((CAB_X0 + BEAM_X) * 0.5, -0.55, zs * 0.6), "black")
	# Wheels: leading bogie, three coupled drivers, trailing truck.
	var drivers: Array[float] = [-14.05, -16.05, -18.05]
	for x in drivers:
		_wheelset(g, "Driver", x, 0.95, 18, "green", true)
	for x in [-19.95, -21.0]:
		_wheelset(g, "BogieWheel", x, 0.45, 10, "green")
	_box(g, "BogieFrame", Vector3(1.6, 0.18, 1.0), Vector3(-20.47, -0.75, 0), "black")
	_wheelset(g, "TrailingWheel", -12.15, 0.55, 12, "green")
	for zs in [-1.0, 1.0]:
		_box(g, "TrailingAxlebox", Vector3(0.3, 0.3, 0.16), Vector3(-12.15, RAIL_Y + 0.55, zs * 1.05), "black")
	# Coupling rods, outside cylinders, slide bars, crossheads and connecting rods.
	for zs in [-1.0, 1.0]:
		var zr: float = zs * 0.89
		var pin := _crank_pin(0.95)
		var yc := RAIL_Y + 0.95 + pin.y
		var crod := _box(g, "CouplingRod", Vector3(drivers[0] - drivers[2] + 0.25, 0.1, 0.045), Vector3((drivers[0] + drivers[2]) * 0.5 + pin.x, yc, zr), "steel")
		# Crank bosses for the rod ends, carried with it.
		for x in drivers:
			_cyl(crod, "RodBoss", 0.07, 0.07, 0.06, Vector3(x - (drivers[0] + drivers[2]) * 0.5, 0, 0), "steel", Vector3.BACK, 14)
		var cyl_x := -20.35
		var cyl_y := -0.45
		var cz: float = zs * 1.12
		_cyl(g, "Cylinder", 0.33, 0.33, 0.95, Vector3(cyl_x, cyl_y, cz), "green", Vector3.RIGHT, 28)
		for k in [-1.0, 1.0]:
			_cyl(g, "CylinderCover", 0.3, 0.3, 0.04, Vector3(cyl_x + k * 0.49, cyl_y, cz), "steel", Vector3.RIGHT, 28)
		_box(g, "ValveChest", Vector3(0.95, 0.3, 0.32), Vector3(cyl_x, cyl_y + 0.38, cz), "green")
		for k in [-1.0, 1.0]:
			_box(g, "SlideBar", Vector3(1.3, 0.04, 0.06), Vector3(-19.2, cyl_y + k * 0.08, cz - zs * 0.02), "steel")
		var xh := -18.95
		var xhead := _box(g, "Crosshead", Vector3(0.22, 0.14, 0.1), Vector3(xh, cyl_y, cz - zs * 0.02), "steel")
		var pin_mid := Vector3(drivers[1] + pin.x, yc, zs * 0.99)
		var con := _rod(g, "ConnectingRod", Vector3(xh, cyl_y, zs * 1.04), pin_mid, 0.045, "steel")
		var pst := _rod(g, "PistonRod", Vector3(cyl_x + 0.48, cyl_y, cz), Vector3(xh, cyl_y, cz), 0.025, "steel")
		_gear.sides.append({
			"phase": 0.0 if zs < 0.0 else PI * 0.5,
			"coupling": crod, "coupling_pos": crod.position,
			"mid_x": drivers[1], "wheel_y": RAIL_Y + 0.95, "cr_z": zs * 0.99, "con_dz": zs * 0.05,
			"cyl_y": cyl_y, "cz": cz, "piston_x0": cyl_x + 0.48,
			"con_len": Vector2(xh, cyl_y).distance_to(Vector2(pin_mid.x, pin_mid.y)),
			"crosshead": xhead, "conrod": con, "piston": pst})
		_rod(g, "Drawbar", Vector3(CAB_X0 + 0.1, -0.55, 0), Vector3(CAB_X0 - 0.4, -0.55, 0), 0.04, "steel_dark")
		# Sandboxes and brake hangers by the drivers.
		for x in drivers:
			_box(g, "BrakeShoe", Vector3(0.1, 0.4, 0.08), Vector3(x + 0.98, RAIL_Y + 0.95, zs * GAUGE_HALF), "black")
		_rod(g, "SandPipe", Vector3(drivers[0] - 0.7, PLATE_Y - 0.1, zs * 0.75), Vector3(drivers[0] - 0.9, RAIL_Y + 0.05, zs * GAUGE_HALF), 0.02, "black")

func _build_front(g: Node3D) -> void:
	_box(g, "BufferBeam", Vector3(0.15, 0.45, T_HALF_W * 2.0), Vector3(BEAM_X + 0.075, -0.34, 0), "red")
	_buffers(g, BEAM_X, -1.0)
	_box(g, "FrontCoupling", Vector3(0.3, 0.1, 0.09), Vector3(BEAM_X - 0.13, -0.46, 0), "steel_dark")
	_rod(g, "FrontVacuumPipe", Vector3(BEAM_X, -0.6, -0.35), Vector3(BEAM_X - 0.25, -0.9, -0.42), 0.035, "rubber")
	for zs in [-1.0, 1.0]:
		_lamp(g, Vector3(BEAM_X - 0.02, 0.0, zs * 0.75))
		_box(g, "FrontStep", Vector3(0.25, 0.03, 0.2), Vector3(BEAM_X + 0.3, -0.75, zs * 1.15), "steel_dark")
	_text(g, "BeamNumber", engine_number, Vector3(BEAM_X - 0.003, -0.34, 0), Vector3(-1, 0, 0), 0.12, Color(0.9, 0.75, 0.4))

# ————— collision (cab and corridor are walkable; the rest just stops you at its surface) —————

func _build_collision(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)
	var xc := -T_LEN * 0.5
	# Corridor floor and walls; tank sides behind them.
	_shape(body, Vector3(T_LEN + 0.1, 0.1, COR_HALF * 2.0 + 0.1), Vector3(xc, -0.05, 0))
	for zs in [-1.0, 1.0]:
		_shape(body, Vector3(T_LEN, COR_H + 0.3, 0.06), Vector3(xc, COR_H * 0.5, zs * (COR_HALF + 0.02)))
		# Tender end plates either side of the doorways.
		_shape(body, Vector3(0.06, 2.3, T_HALF_W - COR_HALF), Vector3(0.03, 1.15, zs * (COR_HALF + T_HALF_W) * 0.5))
		_shape(body, Vector3(0.06, 2.3, T_HALF_W - COR_HALF), Vector3(-T_LEN - 0.03, 1.15, zs * (COR_HALF + T_HALF_W) * 0.5))
	# Cab floor, sides (full height: the half doors and rails keep you on the footplate), front.
	var cxc := (CAB_X0 + CAB_X1) * 0.5
	_shape(body, Vector3(CAB_X0 - CAB_X1 + 0.1, 0.1, CAB_HALF_W * 2.0), Vector3(cxc, -0.05, 0))
	for zs in [-1.0, 1.0]:
		_shape(body, Vector3(CAB_X0 - CAB_X1, 2.3, 0.06), Vector3(cxc, 1.15, zs * (CAB_HALF_W + 0.01)))
	_shape(body, Vector3(0.2, 2.3, CAB_HALF_W * 2.0), Vector3(CAB_X1 + 0.12, 1.15, 0))
	_shape(body, Vector3(0.2, 1.4, 0.2), Vector3(-10.55, 0.7, -1.05))     # reverser

func _shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)
