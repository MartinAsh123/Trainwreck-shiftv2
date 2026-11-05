@tool
class_name MailVan
extends SleeperCar

## Mail & parcels van (car 5): the PassengerCar body (vestibule, W.C. end, gangway doors, exterior)
## with the saloon fitted out for the mail. From the boarding end:
##   - sorting office: pigeonhole frame on a sorting desk along the -Z wall, a letter table under
##     the windows, mail-bag rack and wall clock on the partition
##   - parcels bay between two pairs of sliding loading doors (one pair in each side): parcel
##     rack, mail sacks, parcels, crates, milk churns, luggage, sack truck and platform scale
##   - holding cage by the W.C. end, along the +Z wall, for passengers removed from the train:
##     steel mesh walls, locked gate, slatted bench, barred window
## Windows are on the +Z side only (the pigeonholes take the -Z wall). Reuses the sleeping car's
## furniture helpers; none of its corridor or compartments.

@export_group("Mail van")
@export var sorting_length: float = 4.0:
	set(v): sorting_length = v; _queue_rebuild()
@export var cage_length: float = 2.8:
	set(v): cage_length = v; _queue_rebuild()
@export var loading_door_width: float = 1.6:
	set(v): loading_door_width = v; _queue_rebuild()

const CAGE_Z0 := 0.5            # aisle-side face of the holding cage (the aisle runs along -Z)
const DESK_D := 0.62
const DESK_H := 0.82

# ————— layout —————

func _aisle_z() -> float:
	return 0.0

func _partition_door_z(end_sign: float) -> float:
	if end_sign == _boarding_sign():
		return 0.0
	var wall_face := _toilet_wall_z() - wall_thickness * 0.5
	return minf(0.0, wall_face - inner_door_width * 0.5 - 0.02)

func _inner_door_pocket(_end_sign: float) -> float:
	return 0.0

func _door_trim_width() -> float:
	return 0.06

func _door_head_overhang() -> float:
	return 0.04

func _bin_z() -> float:
	return -0.95

func _span() -> float:
	return _saloon_end() - _saloon_start()

# X of a point `d` metres into the saloon from its boarding-end partition.
func _along(d: float) -> float:
	var bs := _boarding_sign()
	return (_saloon_start() if bs < 0.0 else _saloon_end()) - bs * d

func _door_x() -> float:
	return _along((sorting_length + _span() - cage_length) * 0.5)

func _window_xs() -> Array[float]:
	var xs: Array[float] = [_along(1.05), _along(sorting_length - 1.05), _along(_span() - cage_length * 0.5)]
	xs.sort()
	return xs

func _window_sides(_x: float) -> Array:
	return [1.0]

# No aisle runner: bare floorboards.
func _build_decor() -> Node3D:
	var decor := Node3D.new()
	decor.name = "Decor"
	return decor

# Loading door openings through both side walls.
func _add_interior_walls(shell: CSGCombiner3D) -> void:
	var cut_depth := wall_thickness * 2.0 + tumblehome * 2.0 + 0.2
	for z_side in [-1.0, 1.0]:
		_add_box(shell, "LoadingDoorCut", Vector3(loading_door_width, door_height, cut_depth),
				Vector3(_door_x(), door_height * 0.5, z_side * (width * 0.5 - wall_thickness * 0.5)),
				trim_material, CSGShape3D.OPERATION_SUBTRACTION)

# Company name between the -X car number and the loading doors; "MAIL & PARCELS" on the other side.
func _build_lettering() -> Node3D:
	var root := super()
	var half := _half_len()
	var dw := loading_door_width * 0.5
	var xd := _door_x()
	var lo := -(half - 3.4) + 0.5
	var hi := xd - dw - 0.25
	var lo2 := xd + dw + 0.25
	var hi2 := (half - 3.4) - 0.5
	var w := width * 0.5
	for c in root.get_children():
		if c is Label3D and c.name.begins_with("CompanyName"):
			_fit_label(c, lo, hi)
	for z_side in [-1.0, 1.0]:
		var l := _add_text(root, "VanTitle", "MAIL & PARCELS", Vector3(0, 0.3, z_side * (w + 0.003)), z_side, 0.1, 700, 0.06)
		_fit_label(l, lo2, hi2)
	return root

# Centres a label between x0 and x1, shrinking it if it does not fit.
func _fit_label(l: Label3D, x0: float, x1: float) -> void:
	var wpx := l.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x if l.font else 0.0
	var w := wpx * l.pixel_size
	if w > 0.0 and w > (x1 - x0) - 0.1:
		l.pixel_size *= ((x1 - x0) - 0.1) / w
	l.position.x = (x0 + x1) * 0.5

# ————— interior —————

func _build_extra(anchors: Node3D) -> void:
	var group := _add_group(anchors, "MailVan")
	_build_sorting(group)
	_build_parcels(group)
	_build_cage(group)
	for z_side in [-1.0, 1.0]:
		_loading_door(group, z_side)
	_room_lamp(group, "Lamp_Sorting", Vector3(_along(sorting_length * 0.5), 0, 0), 4.6, 1.1, true)
	_room_lamp(group, "Lamp_Parcels", Vector3(_door_x(), 0, 0), 4.2, 1.0, true)
	_room_lamp(group, "Lamp_Cage", Vector3(_along(_span() - cage_length * 0.5), 0, (CAGE_Z0 + _inner_half_width()) * 0.5),
			3.0, 0.8, true, compartment_lamp_scene)
	# Notices on the saloon face of the boarding-end partition.
	var bs := _boarding_sign()
	var part_x: float = _partition_face(bs, -1.0) - bs * 0.004
	_add_plate(group, "SORTING OFFICE\nPOSTAL STAFF ONLY", Vector3(part_x, 1.86, (0.45 + _inner_half_width()) * 0.5 + 0.02), Vector3(-bs, 0, 0), "brass", false, 0.026)

func _van_mat(key: String) -> StandardMaterial3D:
	var k := "van_" + key
	if _svc_mats.has(k):
		return _svc_mats[k]
	var m: StandardMaterial3D
	# Structural surfaces (loading-door skins, cage frame and fittings) use the HD texture set.
	var hd_key: String = {"varnish": "wood_furniture", "steel": "iron", "crate_dark": "wood_pine_dark"}.get(key, "")
	if hd_key != "":
		m = HDProps.textured(hd_key, 1.2 if key == "varnish" else 0.6)
		if m:
			_svc_mats[k] = m
			return m
	match key:
		"canvas": m = _mat(Color(0.6, 0.55, 0.42)); m.roughness = 1.0
		"canvas2": m = _mat(Color(0.5, 0.46, 0.36)); m.roughness = 1.0
		"kraft": m = _mat(Color(0.6, 0.45, 0.27)); m.roughness = 0.9
		"kraft2": m = _mat(Color(0.52, 0.38, 0.23)); m.roughness = 0.9
		"string": m = _mat(Color(0.86, 0.8, 0.64)); m.roughness = 1.0
		"crate": m = _mat(Color(0.58, 0.43, 0.26)); m.roughness = 0.85
		"crate_dark": m = _mat(Color(0.36, 0.25, 0.14)); m.roughness = 0.9
		"steel": m = _mat(Color(0.2, 0.21, 0.2)); m.metallic = 0.7; m.roughness = 0.45
		"churn": m = _mat(Color(0.7, 0.71, 0.72)); m.metallic = 0.85; m.roughness = 0.3
		"leather": m = _mat(Color(0.32, 0.17, 0.08)); m.roughness = 0.55
		"leather2": m = _mat(Color(0.18, 0.2, 0.26)); m.roughness = 0.6
		"trunk": m = _mat(Color(0.22, 0.3, 0.2)); m.roughness = 0.6
		"letter": m = _mat(Color(0.93, 0.91, 0.84)); m.roughness = 0.9
		"letter2": m = _mat(Color(0.85, 0.8, 0.68)); m.roughness = 0.9
		"livery": m = _mat(_c_livery); m.roughness = 0.35; m.clearcoat_enabled = true; m.clearcoat = 0.5
		"varnish": m = _mat(Color(0.3, 0.17, 0.09)); m.roughness = 0.4
		"mesh":
			var sm := ShaderMaterial.new()
			sm.shader = preload("res://shaders/props/wire_mesh.gdshader")
			_svc_mats[k] = sm
			return null
		_: m = _mat(Color(1, 0, 1))
	_svc_mats[k] = m
	return m

func _brass_mat() -> StandardMaterial3D:
	var b := _mat(_c_brass)
	b.metallic = 0.85
	b.roughness = 0.3
	return b

# ————— sorting office —————

func _build_sorting(parent: Node3D) -> void:
	var g := _add_group(parent, "SortingOffice")
	var wi := _inner_half_width()
	var bs := _boarding_sign()
	var desk_len := sorting_length - 0.7
	var dx := _along(0.35 + desk_len * 0.5)
	# Sorting desk with the pigeonhole frame on it, against the -Z wall.
	var desk := _wall_frame(g, "SortingDesk", Vector3(dx, 0, -wi + 0.01), Vector3(0, 0, 1))
	_sorting_desk(desk, desk_len)
	_pigeonholes(desk, desk_len, 16, 7)
	for k in 2:
		var st := _wall_frame(g, "Stool_%d" % (k + 1), Vector3(dx + (k - 0.5) * desk_len * 0.45, 0, -wi + DESK_D + 0.32), Vector3(0, 0, 1))
		_stool(st)
	# On the desk: letter scale, date stamp and pad, string, bundles.
	var top := Node3D.new()
	top.name = "DeskTop"
	top.position = Vector3(dx, DESK_H, -wi + 0.01 + DESK_D * 0.62)
	g.add_child(top)
	_letter_scale(top, Vector3(-desk_len * 0.32, 0, 0))
	_date_stamp(top, Vector3(-desk_len * 0.12, 0, 0.05))
	_string_ball(top, Vector3(desk_len * 0.05, 0, 0.08))
	for k in 4:
		_letter_bundle(top, Vector3(desk_len * (0.18 + 0.07 * k), 0, (k % 2) * 0.06 - 0.03), k)
	# Letter table under the windows (+Z wall), with trays of letters.
	var tbl := _wall_frame(g, "LetterTable", Vector3(dx, 0, wi - 0.01), Vector3(0, 0, -1))
	_letter_table(tbl, desk_len - 0.4)
	# Mail-bag rack on the partition, +Z of the door; wall clock on the partition, -Z of the door.
	var part_x: float = _partition_face(bs, -1.0)
	var rack := _wall_frame(g, "BagRack", Vector3(part_x, 0, (0.45 + wi) * 0.5 + 0.02), Vector3(-bs, 0, 0))
	_bag_rack(rack, wi - 0.55)
	var clk := _wall_frame(g, "WallClock", Vector3(part_x, 1.92, -0.85), Vector3(-bs, 0, 0))
	_van_clock(clk)

func _sorting_desk(n: Node3D, w: float) -> void:
	# The HD model is the desk and its 16 x 7 pigeonhole frame together (3.3 m long by default).
	if HDProps.place(n, "sorting_desk", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 3.3, 1.0, 1.0))):
		n.set_meta("hd", true)
		_furniture_body(n, Vector3(w, DESK_H, DESK_D), Vector3(0, DESK_H * 0.5, -DESK_D * 0.5))
		return
	var wood := trim_material
	var dark := _svc_mat("dark")
	_add_mesh(n, "Plinth", Vector3(w - 0.04, 0.08, DESK_D - 0.06), Vector3(0, 0.04, -(DESK_D - 0.06) * 0.5 - 0.02), dark)
	_add_mesh(n, "Carcass", Vector3(w, DESK_H - 0.1, DESK_D - 0.04), Vector3(0, 0.08 + (DESK_H - 0.12) * 0.5, -(DESK_D - 0.04) * 0.5), wood)
	var top := _add_mesh(n, "Top", Vector3(w + 0.04, 0.035, DESK_D), Vector3(0, DESK_H - 0.0175, -DESK_D * 0.5), wood)
	top.rotation.x = deg_to_rad(-3.0)
	_add_mesh(n, "TopLip", Vector3(w + 0.04, 0.03, 0.02), Vector3(0, DESK_H + 0.005, -DESK_D + 0.01), wood)
	# Cupboard doors along the front.
	var doors := int(w / 0.6)
	for i in doors:
		var x := -w * 0.5 + (i + 0.5) * w / doors
		_add_mesh(n, "DeskDoor", Vector3(w / doors - 0.03, DESK_H - 0.22, 0.015), Vector3(x, 0.09 + (DESK_H - 0.22) * 0.5 + 0.02, -DESK_D + 0.035), wood)
		_add_mesh(n, "DeskDoorPanel", Vector3(w / doors - 0.12, DESK_H - 0.32, 0.006), Vector3(x, 0.09 + (DESK_H - 0.22) * 0.5 + 0.02, -DESK_D + 0.026), dark)
		_add_ball(n, "Knob", Vector3(x + w / doors * 0.35, 0.5, -DESK_D + 0.02), 0.011, _brass_mat())
	_furniture_body(n, Vector3(w, DESK_H, DESK_D), Vector3(0, DESK_H * 0.5, -DESK_D * 0.5))

# Pigeonhole frame on the back of the desk: walnut grid, brass label strips, letters in some cells.
func _pigeonholes(n: Node3D, w: float, cols: int, rows: int) -> void:
	if n.has_meta("hd"):
		_add_plate(n, "UP LINE  ·  STATIONS A - H", Vector3(0, DESK_H + 0.02 + 1.06 + 0.12, -0.085 - 0.15 - 0.03), Vector3(0, 0, -1), "brass", false, 0.02)
		return
	var wood := trim_material
	var dark := _svc_mat("dark")
	var brass := _brass_mat()
	var y0 := DESK_H + 0.02
	var h := 1.06
	var d := 0.3
	var zb := -0.085                     # clear of the wall's lean above the sill
	_add_mesh(n, "PigeonBack", Vector3(w, h, 0.012), Vector3(0, y0 + h * 0.5, zb - 0.006), dark)
	var cw := w / cols
	var ch := h / rows
	for i in cols + 1:
		var x := -w * 0.5 + i * cw
		_add_mesh(n, "Upright", Vector3(0.012 if i % 4 != 0 else 0.022, h, d), Vector3(x, y0 + h * 0.5, zb - d * 0.5), wood)
	for j in rows + 1:
		var y := y0 + j * ch
		_add_mesh(n, "Shelf", Vector3(w, 0.01 if j != 0 and j != rows else 0.022, d), Vector3(0, y, zb - d * 0.5), wood)
	_add_mesh(n, "Cornice", Vector3(w + 0.04, 0.04, d + 0.03), Vector3(0, y0 + h + 0.03, zb - d * 0.5 - 0.005), wood)
	for j in rows:
		for i in cols:
			var x := -w * 0.5 + (i + 0.5) * cw
			var y := y0 + j * ch
			_add_mesh(n, "Label", Vector3(cw * 0.55, 0.014, 0.002), Vector3(x, y + 0.012, zb - d - 0.002), brass)
			var hsh := hash_f(i * 31 + j * 7, 3.7)
			if hsh > 0.45:
				var cnt := 1 + int(hsh * 4.0)
				for k in cnt:
					var lw := cw * (0.68 + 0.1 * hash_f(k, hsh))
					var lh := ch * (0.55 + 0.2 * hash_f(k + 2, hsh))
					var lp := Vector3(x, y + 0.012 + ch * 0.32, zb - 0.03 - k * 0.012)
					var tilt := deg_to_rad(-12.0 - 4.0 * k)
					if HDProps.place(n, "envelope" if (k + i) % 3 != 0 else "envelope_kraft",
							HDProps.xf(lp, Vector3(tilt, 0, (hash_f(k + 5, hsh) - 0.5) * 0.06), Vector3(lw / 0.16, lh / 0.1, 1.0)), "Letter"):
						continue
					var lm := _van_mat("letter" if (k + i) % 3 != 0 else "letter2")
					var lt := _add_mesh(n, "Letter", Vector3(lw, lh, 0.004), lp, lm)
					lt.rotation.x = tilt
	_add_plate(n, "UP LINE  ·  STATIONS A - H", Vector3(0, y0 + h + 0.1, zb - d * 0.5 - 0.022), Vector3(0, 0, -1), "brass", false, 0.02)

func _stool(n: Node3D) -> void:
	if HDProps.place(n, "sorting_stool", HDProps.xf(Vector3(0, 0, -0.2))):
		return
	var wood := trim_material
	_cyl_v(n, "Seat", 0.17, 0.17, 0.04, Vector3(0, 0.64, -0.2), wood)
	for k in 4:
		var a := k * TAU / 4.0 + PI * 0.25
		var foot := Vector3(cos(a) * 0.17, 0.0, -0.2 + sin(a) * 0.17)
		_add_rod(n, "Leg", foot, Vector3(cos(a) * 0.11, 0.62, -0.2 + sin(a) * 0.11), 0.016, wood)
	var ring := MeshInstance3D.new()
	ring.name = "Footring"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.135
	tm.outer_radius = 0.15
	ring.mesh = tm
	ring.material_override = trim_material
	ring.position = Vector3(0, 0.25, -0.2)
	n.add_child(ring)

func _letter_scale(n: Node3D, p: Vector3) -> void:
	if HDProps.place(n, "letter_scale", HDProps.xf(p), "LetterScale"):
		return
	var brass := _brass_mat()
	_add_mesh(n, "ScaleBase", Vector3(0.22, 0.03, 0.12), p + Vector3(0, 0.015, 0), trim_material)
	_add_rod(n, "ScaleColumn", p + Vector3(0.06, 0.03, 0), p + Vector3(0.06, 0.2, 0), 0.008, brass)
	_cyl_v(n, "ScalePan", 0.06, 0.05, 0.012, p + Vector3(-0.05, 0.08, 0), brass)
	_add_rod(n, "ScaleArm", p + Vector3(0.06, 0.17, 0), p + Vector3(-0.05, 0.09, 0), 0.004, brass)
	var dial := _cyl_v(n, "ScaleDial", 0.045, 0.045, 0.008, p + Vector3(0.06, 0.2, -0.008), _svc_mat("paper"))
	dial.rotation.x = PI * 0.5

func _date_stamp(n: Node3D, p: Vector3) -> void:
	if HDProps.place(n, "date_stamp", HDProps.xf(p), "DateStamp"):
		return
	_add_mesh(n, "InkPad", Vector3(0.12, 0.018, 0.08), p + Vector3(0.09, 0.009, 0), _svc_mat("tin"))
	_add_mesh(n, "InkPadInk", Vector3(0.1, 0.002, 0.06), p + Vector3(0.09, 0.019, 0), _van_mat("leather2"))
	_add_mesh(n, "StampFoot", Vector3(0.06, 0.03, 0.04), p + Vector3(0, 0.015, 0), _svc_mat("dark"))
	_cyl_v(n, "StampHandle", 0.018, 0.024, 0.09, p + Vector3(0, 0.075, 0), trim_material)
	_add_ball(n, "StampKnob", p + Vector3(0, 0.125, 0), 0.022, trim_material)

func _string_ball(n: Node3D, p: Vector3) -> void:
	if HDProps.place(n, "string_ball", HDProps.xf(p), "StringBall"):
		return
	_add_ball(n, "StringBall", p + Vector3(0, 0.045, 0), 0.045, _van_mat("string"))

func _letter_bundle(n: Node3D, p: Vector3, k: int) -> void:
	if HDProps.place(n, ["letters_a", "letters_b", "letters_c"][k % 3], HDProps.xf(p, Vector3(0, (hash_f(k, 6.1) - 0.5) * 0.3, 0)), "Bundle"):
		return
	var h := 0.03 + 0.015 * (k % 3)
	_add_mesh(n, "Bundle", Vector3(0.16, h, 0.1), p + Vector3(0, h * 0.5, 0), _van_mat("letter" if k % 2 == 0 else "letter2"))
	_add_mesh(n, "BundleString", Vector3(0.163, h + 0.003, 0.006), p + Vector3(0, h * 0.5, 0), _van_mat("string"))
	_add_mesh(n, "BundleString", Vector3(0.006, h + 0.003, 0.103), p + Vector3(0, h * 0.5, 0), _van_mat("string"))

func _letter_table(n: Node3D, w: float) -> void:
	if HDProps.place(n, "letter_table", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 2.9, 1.0, 1.0))):
		_furniture_body(n, Vector3(w, 0.74, 0.5), Vector3(0, 0.37, -0.25))
		return
	var wood := trim_material
	var h := 0.74
	var d := 0.5
	_add_mesh(n, "TableTop", Vector3(w, 0.035, d), Vector3(0, h - 0.0175, -d * 0.5), wood)
	for sx in [-1.0, 1.0]:
		for sz in [0.06, d - 0.06]:
			_add_mesh(n, "TableLeg", Vector3(0.05, h - 0.035, 0.05), Vector3(sx * (w * 0.5 - 0.06), (h - 0.035) * 0.5, -sz), wood)
	_add_mesh(n, "TableRail", Vector3(w - 0.12, 0.08, 0.02), Vector3(0, h - 0.075, -d + 0.07), wood)
	# Wooden letter trays with letters stacked on edge.
	var trays := int(w / 0.42)
	for i in trays:
		var x := -w * 0.5 + (i + 0.5) * w / trays
		var tray := Node3D.new()
		tray.name = "LetterTray"
		tray.position = Vector3(x, h, -d * 0.5)
		n.add_child(tray)
		_add_mesh(tray, "TrayBase", Vector3(0.34, 0.01, 0.26), Vector3(0, 0.005, 0), wood)
		for sx in [-1.0, 1.0]:
			_add_mesh(tray, "TraySide", Vector3(0.01, 0.07, 0.26), Vector3(sx * 0.165, 0.035, 0), wood)
		for sz in [-1.0, 1.0]:
			_add_mesh(tray, "TrayEnd", Vector3(0.34, 0.07, 0.01), Vector3(0, 0.035, sz * 0.125), wood)
		var cnt := 10 + i * 3
		for k in cnt:
			var tp := Vector3(0, 0.055, -0.11 + k * (0.22 / cnt))
			if HDProps.place(tray, "envelope" if (k + i) % 4 != 0 else "envelope_kraft",
					HDProps.xf(tp, Vector3(deg_to_rad(-8.0), 0, 0), Vector3(0.3 / 0.16, 1.0, 1.0)), "Letter"):
				continue
			var lt := _add_mesh(tray, "Letter", Vector3(0.3, 0.1, 0.004), tp,
					_van_mat("letter" if (k + i) % 4 != 0 else "letter2"))
			lt.rotation.x = deg_to_rad(-8.0)
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

# Bag rack: two posts and a top rail with hooks; open canvas mail bags hang from it.
func _bag_rack(n: Node3D, w: float) -> void:
	if HDProps.place(n, "bag_rack", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 0.925, 1.0, 1.0))):
		# The bags' stencils are painted on the HD canvas itself.
		_furniture_body(n, Vector3(w, 1.6, 0.4), Vector3(0, 0.8, -0.25))
		return
	var steel := _van_mat("steel")
	var brass := _brass_mat()
	var rail_y := 1.6
	for sx in [-1.0, 1.0]:
		_add_rod(n, "Post", Vector3(sx * w * 0.5, 0, -0.28), Vector3(sx * w * 0.5, rail_y + 0.05, -0.28), 0.014, steel)
		_add_rod(n, "Stay", Vector3(sx * w * 0.5, rail_y, -0.28), Vector3(sx * w * 0.5, rail_y, -0.01), 0.01, steel)
	_add_rod(n, "Rail", Vector3(-w * 0.5, rail_y, -0.28), Vector3(w * 0.5, rail_y, -0.28), 0.012, steel)
	var bags := 3
	for i in bags:
		var x := -w * 0.5 + (i + 0.5) * w / bags
		_add_rod(n, "Hook", Vector3(x, rail_y, -0.28), Vector3(x, rail_y - 0.07, -0.3), 0.004, brass)
		_mail_bag(n, Vector3(x, rail_y - 0.07, -0.3), i, true)
	_furniture_body(n, Vector3(w, rail_y, 0.4), Vector3(0, rail_y * 0.5, -0.25))

# Canvas mail bag. Hanging = open mouth held on a hook; otherwise a closed, tied bag lying down.
func _mail_bag(n: Node3D, top: Vector3, k: int, hanging: bool) -> void:
	if not hanging and HDProps.place(n, "mail_sack", HDProps.xf(top, Vector3(0, hash_f(k, 1.3) * 0.8, 0)), "Sack"):
		return
	var canvas := _van_mat("canvas" if k % 2 == 0 else "canvas2")
	if hanging:
		var h := 0.75
		_cyl_v(n, "Bag", 0.15, 0.2, h, top + Vector3(0, -h * 0.5 - 0.02, 0), canvas)
		var bottom := _add_ball(n, "BagBottom", top + Vector3(0, -h - 0.02, 0), 0.2, canvas)
		bottom.scale = Vector3(1, 0.35, 1)
		var rim := MeshInstance3D.new()
		rim.name = "BagRim"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.135
		tm.outer_radius = 0.16
		rim.mesh = tm
		rim.material_override = _van_mat("leather")
		rim.position = top + Vector3(0, -0.02, 0)
		n.add_child(rim)
		var l := _bag_stencil(n, top + Vector3(0, -0.35, -0.195), k)
		l.rotation.y = PI
		return
	var bag := _add_ball(n, "Sack", top, 0.5, canvas)
	bag.scale = Vector3(0.6, 0.32, 0.4)
	bag.rotation.y = hash_f(k, 1.3) * 0.8
	var neck := _cyl_v(n, "SackNeck", 0.05, 0.08, 0.16, top + bag.basis.x.normalized() * 0.34, canvas)
	neck.rotation.z = -PI * 0.5
	neck.rotation.y = bag.rotation.y

func _bag_stencil(n: Node3D, p: Vector3, k: int) -> Label3D:
	var l := Label3D.new()
	l.name = "Stencil"
	l.text = "G.C.R.\nMAILS\n%d" % (k + 1)
	l.font = _sign_font()
	l.font_size = 64
	l.pixel_size = 0.03 / (64.0 * SIGN_CAP_RATIO)
	l.line_spacing = -8.0
	l.modulate = Color(0.2, 0.14, 0.08)
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.render_priority = 1
	l.position = p
	n.add_child(l)
	return l

func _van_clock(n: Node3D) -> void:
	if HDProps.place(n, "wall_clock_station"):
		_add_plate(n, "RAILWAY TIME", Vector3(0, -0.24, -0.004), Vector3(0, 0, -1), "brass", false, 0.014)
		return
	var brass := _brass_mat()
	var case := _cyl_v(n, "ClockCase", 0.17, 0.17, 0.06, Vector3(0, 0, -0.03), trim_material)
	case.rotation.x = PI * 0.5
	var bezel := _cyl_v(n, "ClockBezel", 0.15, 0.15, 0.01, Vector3(0, 0, -0.063), brass)
	bezel.rotation.x = PI * 0.5
	var face := _cyl_v(n, "ClockFace", 0.135, 0.135, 0.004, Vector3(0, 0, -0.068), _svc_mat("paper"))
	face.rotation.x = PI * 0.5
	for i in 12:
		var a := i * TAU / 12.0
		var tick := _add_mesh(n, "Tick", Vector3(0.008 if i % 3 != 0 else 0.012, 0.022, 0.002), Vector3(sin(a) * 0.115, cos(a) * 0.115, -0.071), _svc_mat("dark"))
		tick.rotation.z = -a
	var hour := _add_mesh(n, "HourHand", Vector3(0.012, 0.075, 0.002), Vector3(0, 0, -0.073), _svc_mat("dark"))
	hour.rotation.z = deg_to_rad(-75.0)
	hour.position += hour.basis.y * 0.0375
	var mins := _add_mesh(n, "MinuteHand", Vector3(0.008, 0.11, 0.002), Vector3(0, 0, -0.074), _svc_mat("dark"))
	mins.rotation.z = deg_to_rad(-220.0)
	mins.position += mins.basis.y * 0.055
	_add_plate(n, "RAILWAY TIME", Vector3(0, -0.24, -0.004), Vector3(0, 0, -1), "brass", false, 0.014)

# ————— parcels bay —————

func _build_parcels(parent: Node3D) -> void:
	var g := _add_group(parent, "ParcelsBay")
	var wi := _inner_half_width()
	var xd := _door_x()
	var dw := loading_door_width * 0.5
	var bs := _boarding_sign()
	var toward_cage := -bs                               # +X when boarding is at -X
	var sorting_side := bs
	# -Z side: parcel rack toward the sorting office, churns and crates toward the cage.
	var rack_w := 1.2
	var rx: float = xd + sorting_side * (dw + 0.15 + rack_w * 0.5)
	var rack := _wall_frame(g, "ParcelRack", Vector3(rx, 0, -wi), Vector3(0, 0, 1))
	_parcel_rack(rack, rack_w)
	var cx: float = xd + toward_cage * (dw + 0.35)
	for k in 3:
		_milk_churn(g, Vector3(cx + toward_cage * (k % 2) * 0.36, 0, -wi + 0.25 + (k / 2) * 0.36))
	_crate_stack(g, Vector3(cx + toward_cage * 0.85, 0, -wi + 0.3))
	# +Z side: platform scale by the door and mail sacks toward the sorting office; luggage toward
	# the cage and the sack truck leaning on the cage's end wall.
	var sc := _wall_frame(g, "PlatformScale", Vector3(xd + sorting_side * (dw + 0.4), 0, wi), Vector3(0, 0, -1))
	_platform_scale(sc)
	for k in 5:
		var p := Vector3(xd + sorting_side * (dw + 0.95 + (k % 3) * 0.33), 0.1 + (k / 3) * 0.16, wi - 0.3 - (k % 2) * 0.1)
		_mail_bag(g, p, k, false)
	_luggage(g, Vector3(xd + toward_cage * (dw + 0.55), 0, wi - 0.3))
	var x_cage: float = _along(_span() - cage_length)
	var tr := _wall_frame(g, "SackTruck", Vector3(x_cage - toward_cage * 0.03, 0, 1.15), Vector3(bs, 0, 0))
	_sack_truck(tr)
	# A few parcels waiting by the -Z door, ready to unload.
	_parcel(g, Vector3(xd + sorting_side * 0.45, 0, -wi + 0.35), Vector3(0.42, 0.3, 0.32), 0)
	_parcel(g, Vector3(xd + sorting_side * 0.45, 0.3, -wi + 0.36), Vector3(0.3, 0.2, 0.24), 1)
	_parcel(g, Vector3(xd + sorting_side * 0.05, 0, -wi + 0.3), Vector3(0.36, 0.18, 0.26), 2)

func _parcel_rack(n: Node3D, w: float) -> void:
	if HDProps.place(n, "parcel_rack", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 1.2, 1.0, 1.0))):
		_furniture_body(n, Vector3(w, 1.75, 0.55), Vector3(0, 0.875, -0.275))
		return
	var wood := _van_mat("crate")
	var dark := _van_mat("crate_dark")
	var d := 0.55
	var h := 1.75
	for sx in [-1.0, 1.0]:
		for sz in [0.03, d - 0.03]:
			_add_mesh(n, "RackPost", Vector3(0.05, h, 0.05), Vector3(sx * (w * 0.5 - 0.025), h * 0.5, -sz), dark)
	var shelves := [0.08, 0.62, 1.16, 1.7]
	for si in shelves.size():
		var y: float = shelves[si]
		for k in 5:
			_add_mesh(n, "Slat", Vector3(w, 0.022, d / 5.0 - 0.02), Vector3(0, y, -0.02 - (k + 0.5) * d / 5.0), wood)
		if si < shelves.size() - 1:
			var x := -w * 0.5 + 0.12
			var idx := si * 5
			while x < w * 0.5 - 0.12:
				var sz := Vector3(0.18 + 0.2 * hash_f(idx, 2.0), 0.12 + 0.24 * hash_f(idx, 5.0), 0.2 + 0.25 * hash_f(idx, 7.0))
				sz.x = minf(sz.x, w * 0.5 - 0.06 - x)
				if sz.x < 0.12:
					break
				_parcel(n, Vector3(x + sz.x * 0.5, y + 0.011, -0.05 - sz.z * 0.5), sz, idx)
				x += sz.x + 0.03
				idx += 1
	_furniture_body(n, Vector3(w, h, d), Vector3(0, h * 0.5, -d * 0.5))

# Brown-paper parcel tied with string both ways, with an address label.
func _parcel(n: Node3D, base: Vector3, size: Vector3, k: int) -> void:
	var hp := HDProps.place(n, ["parcel_a", "parcel_b", "parcel_c"][k % 3], HDProps.xf(base, Vector3(0, (hash_f(k, 9.1) - 0.5) * 0.12, 0)), "Parcel")
	if hp:
		HDProps.fit(hp, size)
		return
	var m := _van_mat("kraft" if k % 3 != 1 else "kraft2")
	var c := base + Vector3(0, size.y * 0.5, 0)
	var box := _add_mesh(n, "Parcel", size, c, m)
	box.rotation.y = (hash_f(k, 9.1) - 0.5) * 0.12
	var s := _van_mat("string")
	var a := _add_mesh(n, "ParcelString", Vector3(size.x + 0.004, size.y + 0.004, 0.006), c, s)
	a.rotation.y = box.rotation.y
	var b := _add_mesh(n, "ParcelString", Vector3(0.006, size.y + 0.004, size.z + 0.004), c, s)
	b.rotation.y = box.rotation.y
	var lab := _add_mesh(n, "ParcelLabel", Vector3(size.x * 0.4, 0.002, size.z * 0.35), c + Vector3(size.x * 0.18, size.y * 0.5 + 0.001, -size.z * 0.15), _van_mat("letter"))
	lab.rotation.y = box.rotation.y

func _milk_churn(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "milk_churn", HDProps.xf(base, Vector3(0, hash_f(int(base.x * 100.0), 2.2) * TAU, 0)), "MilkChurn"):
		var cb := StaticBody3D.new()
		cb.name = "ChurnCollision"
		n.add_child(cb)
		var ccs := CollisionShape3D.new()
		var ccyl := CylinderShape3D.new()
		ccyl.radius = 0.18
		ccyl.height = 0.85
		ccs.shape = ccyl
		ccs.position = base + Vector3(0, 0.425, 0)
		cb.add_child(ccs)
		return
	var steel := _van_mat("churn")
	_cyl_v(n, "ChurnFoot", 0.17, 0.18, 0.04, base + Vector3(0, 0.02, 0), steel)
	_cyl_v(n, "ChurnBody", 0.165, 0.165, 0.5, base + Vector3(0, 0.29, 0), steel)
	_cyl_v(n, "ChurnShoulder", 0.09, 0.165, 0.14, base + Vector3(0, 0.61, 0), steel)
	_cyl_v(n, "ChurnNeck", 0.09, 0.09, 0.12, base + Vector3(0, 0.74, 0), steel)
	_cyl_v(n, "ChurnLid", 0.1, 0.1, 0.03, base + Vector3(0, 0.815, 0), steel)
	_add_ball(n, "ChurnKnob", base + Vector3(0, 0.84, 0), 0.025, steel)
	for sx in [-1.0, 1.0]:
		_add_rod(n, "ChurnHandle", base + Vector3(sx * 0.12, 0.62, 0), base + Vector3(sx * 0.16, 0.72, 0), 0.01, steel)
	for y in [0.1, 0.5]:
		_cyl_v(n, "ChurnBand", 0.172, 0.172, 0.03, base + Vector3(0, y, 0), steel)
	var body := StaticBody3D.new()
	body.name = "ChurnCollision"
	n.add_child(body)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.18
	cyl.height = 0.85
	cs.shape = cyl
	cs.position = base + Vector3(0, 0.425, 0)
	body.add_child(cs)

func _crate_stack(n: Node3D, base: Vector3) -> void:
	_crate(n, base, Vector3(0.55, 0.42, 0.45), 0)
	_crate(n, base + Vector3(0.02, 0.42, 0), Vector3(0.45, 0.32, 0.4), 1)

# Slatted wooden crate with corner battens and a stencil.
func _crate(n: Node3D, base: Vector3, size: Vector3, k: int) -> void:
	var hc := HDProps.place(n, "crate_a" if k % 2 == 0 else "crate_b", HDProps.xf(base, Vector3(0, (hash_f(k, 4.4) - 0.5) * 0.2, 0)), "Crate")
	if hc:
		HDProps.fit(hc, size)
		_furniture_body(n, size, base + Vector3(0, size.y * 0.5, 0))
		return
	var g := Node3D.new()
	g.name = "Crate"
	g.position = base
	g.rotation.y = (hash_f(k, 4.4) - 0.5) * 0.2
	n.add_child(g)
	var wood := _van_mat("crate")
	var dark := _van_mat("crate_dark")
	_add_mesh(g, "CrateCore", size - Vector3(0.03, 0.03, 0.03), Vector3(0, size.y * 0.5, 0), dark)
	var slats := 4
	for i in slats:
		var y := (i + 0.5) * size.y / slats
		for sz in [-1.0, 1.0]:
			_add_mesh(g, "Slat", Vector3(size.x, size.y / slats - 0.02, 0.015), Vector3(0, y, sz * (size.z * 0.5 - 0.0075)), wood)
		for sx in [-1.0, 1.0]:
			_add_mesh(g, "Slat", Vector3(0.015, size.y / slats - 0.02, size.z), Vector3(sx * (size.x * 0.5 - 0.0075), y, 0), wood)
	for i in 3:
		_add_mesh(g, "Lid", Vector3(size.x, 0.015, size.z / 3.0 - 0.015), Vector3(0, size.y - 0.0075, (i - 1) * size.z / 3.0), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_mesh(g, "Batten", Vector3(0.035, size.y, 0.035), Vector3(sx * (size.x * 0.5 - 0.01), size.y * 0.5, sz * (size.z * 0.5 - 0.01)), wood)
	var l := Label3D.new()
	l.name = "Stencil"
	l.text = "FRAGILE\nWITH CARE" if k == 0 else "G.C.R."
	l.font = _sign_font()
	l.font_size = 64
	l.pixel_size = 0.035 / (64.0 * SIGN_CAP_RATIO)
	l.line_spacing = -8.0
	l.modulate = Color(0.15, 0.1, 0.05, 0.85)
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.render_priority = 1
	l.position = Vector3(0, size.y * 0.5, size.z * 0.5 + 0.002)
	g.add_child(l)
	_furniture_body(g, size, Vector3(0, size.y * 0.5, 0))

# Steamer trunk with two suitcases on top.
func _luggage(n: Node3D, base: Vector3) -> void:
	if HDProps.place(n, "luggage", HDProps.xf(base), "Luggage"):
		_furniture_body(n, Vector3(0.9, 0.8, 0.5), base + Vector3(0, 0.4, 0))
		return
	var g := Node3D.new()
	g.name = "Luggage"
	g.position = base
	n.add_child(g)
	var brass := _brass_mat()
	var leather := _van_mat("leather")
	_add_mesh(g, "Trunk", Vector3(0.9, 0.5, 0.5), Vector3(0, 0.25, 0), _van_mat("trunk"))
	for x in [-0.3, 0.0, 0.3]:
		_add_mesh(g, "TrunkSlat", Vector3(0.05, 0.505, 0.505), Vector3(x, 0.25, 0), trim_material)
	_add_mesh(g, "TrunkLidEdge", Vector3(0.905, 0.03, 0.505), Vector3(0, 0.38, 0), leather)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_mesh(g, "TrunkCorner", Vector3(0.05, 0.05, 0.05), Vector3(sx * 0.43, 0.48, sz * 0.23), brass)
			_add_mesh(g, "TrunkCorner", Vector3(0.05, 0.05, 0.05), Vector3(sx * 0.43, 0.02, sz * 0.23), brass)
	_add_mesh(g, "TrunkLock", Vector3(0.06, 0.07, 0.01), Vector3(0, 0.38, -0.255), brass)
	var s1 := _add_mesh(g, "Suitcase", Vector3(0.62, 0.17, 0.4), Vector3(0.05, 0.585, 0.0), leather)
	s1.rotation.y = 0.12
	_add_rod(g, "SuitcaseHandle", Vector3(-0.0, 0.67, -0.04), Vector3(0.1, 0.67, -0.03), 0.01, _van_mat("leather2"))
	var s2 := _add_mesh(g, "Suitcase", Vector3(0.48, 0.14, 0.32), Vector3(-0.05, 0.74, 0.02), _van_mat("leather2"))
	s2.rotation.y = -0.2
	for sx in [-1.0, 1.0]:
		var strap := _add_mesh(g, "Strap", Vector3(0.025, 0.175, 0.405), Vector3(0.05 + sx * 0.18, 0.585, 0), _van_mat("crate_dark"))
		strap.rotation.y = 0.12
	_furniture_body(g, Vector3(0.9, 0.8, 0.5), Vector3(0, 0.4, 0))

# Two-wheeled sack truck leaning on the wall.
func _sack_truck(n: Node3D) -> void:
	if HDProps.place(n, "sack_truck"):
		return
	var steel := _van_mat("steel")
	var g := Node3D.new()
	g.name = "Truck"
	g.position = Vector3(0, 0, -0.22)
	g.rotation.x = deg_to_rad(-14.0)
	n.add_child(g)
	for sx in [-1.0, 1.0]:
		_add_rod(g, "Rail", Vector3(sx * 0.2, 0.12, 0), Vector3(sx * 0.17, 1.25, 0), 0.016, trim_material)
		var wheel := _cyl_v(g, "Wheel", 0.12, 0.12, 0.05, Vector3(sx * 0.27, 0.12, 0.05), _svc_mat("dark"))
		wheel.rotation.z = PI * 0.5
	for y in [0.4, 0.75, 1.05]:
		_add_rod(g, "Rung", Vector3(-0.19, y, 0), Vector3(0.19, y, 0), 0.009, steel)
	_add_mesh(g, "Toe", Vector3(0.42, 0.012, 0.2), Vector3(0, 0.04, -0.09), steel)
	_add_rod(g, "Axle", Vector3(-0.27, 0.12, 0.05), Vector3(0.27, 0.12, 0.05), 0.012, steel)
	for sx in [-1.0, 1.0]:
		_add_rod(g, "Grip", Vector3(sx * 0.17, 1.25, 0), Vector3(sx * 0.2, 1.33, 0.06), 0.017, _svc_mat("dark"))

# Platform weighing scale: cast-iron platform, column, beam with poise and weights.
func _platform_scale(n: Node3D) -> void:
	if HDProps.place(n, "platform_scale"):
		var sg := Node3D.new()
		sg.name = "Scale"
		sg.position = Vector3(0, 0, -0.35)
		n.add_child(sg)
		_add_plate(sg, "AVERY", Vector3(0, 0.75, 0.25 - 0.048), Vector3(0, 0, -1), "brass", false, 0.012)
		_furniture_body(sg, Vector3(0.6, 1.1, 0.6), Vector3(0, 0.55, 0.05))
		return
	var steel := _van_mat("steel")
	var brass := _brass_mat()
	var g := Node3D.new()
	g.name = "Scale"
	g.position = Vector3(0, 0, -0.35)
	n.add_child(g)
	_add_mesh(g, "Platform", Vector3(0.6, 0.12, 0.5), Vector3(0, 0.06, 0), steel)
	_add_mesh(g, "PlatformTop", Vector3(0.56, 0.01, 0.46), Vector3(0, 0.125, 0), _van_mat("crate_dark"))
	_add_mesh(g, "Column", Vector3(0.08, 0.95, 0.08), Vector3(0, 0.6, 0.29), steel)
	_add_mesh(g, "Beam", Vector3(0.5, 0.03, 0.03), Vector3(0, 1.05, 0.25), brass)
	_add_mesh(g, "Poise", Vector3(0.05, 0.06, 0.05), Vector3(0.08, 1.05, 0.25), steel)
	_add_rod(g, "Hanger", Vector3(-0.24, 1.05, 0.25), Vector3(-0.24, 0.92, 0.25), 0.004, brass)
	for k in 3:
		_cyl_v(g, "Weight", 0.035 - k * 0.006, 0.035 - k * 0.006, 0.02, Vector3(-0.24, 0.9 - k * 0.02, 0.25), brass)
	_add_plate(g, "AVERY", Vector3(0, 0.75, 0.25 - 0.045), Vector3(0, 0, -1), "brass", false, 0.012)
	_furniture_body(g, Vector3(0.6, 1.1, 0.6), Vector3(0, 0.55, 0.05))

# ————— holding cage —————

func _build_cage(parent: Node3D) -> void:
	var g := _add_group(parent, "HoldingCage")
	var wi := _inner_half_width()
	var bs := _boarding_sign()
	var d0 := _span() - cage_length
	var x_open: float = _along(d0)                     # the cage's end wall facing the parcels bay
	var x_end: float = _along(_span())
	var xa := minf(x_open, x_end)
	var xb := maxf(x_open, x_end)
	var steel := _van_mat("steel")
	var mesh_mat: Material = _svc_mats.get("van_mesh") if _svc_mats.has("van_mesh") else null
	if mesh_mat == null:
		_van_mat("mesh")
		mesh_mat = _svc_mats["van_mesh"]
	var h := 2.0
	var z0 := CAGE_Z0
	var gate_w := 0.8
	var gx: float = (xa + xb) * 0.5
	# Aisle-side wall (along X, at z0) with the gate in the middle; end wall (along Z, at x_open).
	var posts: Array[float] = [xa + 0.03, gx - gate_w * 0.5 - 0.03, gx + gate_w * 0.5 + 0.03, xb - 0.03]
	for px in posts:
		_add_mesh(g, "Post", Vector3(0.05, h, 0.05), Vector3(px, h * 0.5, z0), steel)
	_add_mesh(g, "TopRail", Vector3(xb - xa, 0.05, 0.05), Vector3(gx, h, z0), steel)
	_add_mesh(g, "BottomRail", Vector3(xb - xa, 0.05, 0.05), Vector3(gx, 0.08, z0), steel)
	_mesh_panel(g, "Mesh_A", Vector3((xa + gx - gate_w * 0.5) * 0.5, h * 0.5, z0), Vector2((gx - gate_w * 0.5) - xa - 0.06, h - 0.1), 0.0, mesh_mat)
	_mesh_panel(g, "Mesh_B", Vector3((gx + gate_w * 0.5 + xb) * 0.5, h * 0.5, z0), Vector2(xb - (gx + gate_w * 0.5) - 0.06, h - 0.1), 0.0, mesh_mat)
	# End wall across the car.
	var zl := wi - z0
	for pz in [z0, wi - 0.03]:
		_add_mesh(g, "Post", Vector3(0.05, h, 0.05), Vector3(x_open, h * 0.5, pz), steel)
	_add_mesh(g, "TopRail", Vector3(0.05, 0.05, zl), Vector3(x_open, h, (z0 + wi) * 0.5), steel)
	_add_mesh(g, "BottomRail", Vector3(0.05, 0.05, zl), Vector3(x_open, 0.08, (z0 + wi) * 0.5), steel)
	_mesh_panel(g, "Mesh_End", Vector3(x_open, h * 0.5, (z0 + wi) * 0.5), Vector2(zl - 0.06, h - 0.1), PI * 0.5, mesh_mat)
	# Gate (closed): frame, mesh, hinges, hasp and padlock.
	var gate := Node3D.new()
	gate.name = "Gate"
	gate.position = Vector3(gx, 0, z0)
	g.add_child(gate)
	for sx in [-1.0, 1.0]:
		_add_mesh(gate, "GateStile", Vector3(0.04, h - 0.12, 0.04), Vector3(sx * (gate_w * 0.5 - 0.02), h * 0.5, 0), steel)
		_add_mesh(gate, "Hinge", Vector3(0.06, 0.05, 0.05), Vector3(-gate_w * 0.5 - 0.02, 0.35 + (sx + 1.0) * 0.6, 0), steel)
	for y in [0.1, h * 0.5, h - 0.08]:
		_add_mesh(gate, "GateRail", Vector3(gate_w, 0.04, 0.04), Vector3(0, y, 0), steel)
	_mesh_panel(gate, "GateMesh", Vector3(0, h * 0.5, 0), Vector2(gate_w - 0.06, h - 0.16), 0.0, mesh_mat)
	var brass := _brass_mat()
	# Hasp and staple with the padlock through them (HD model), or the simple stand-in.
	var hd_lock := HDProps.place(gate, "cage_padlock", HDProps.xf(Vector3(gate_w * 0.5 + 0.005, 1.03, 0.0)), "Padlock")
	_add_mesh(gate, "Hasp", Vector3(0.1, 0.03, 0.015), Vector3(gate_w * 0.5, 1.05, -0.03), steel)
	_add_mesh(gate, "PadlockBody", Vector3(0.05, 0.06, 0.025), Vector3(gate_w * 0.5 + 0.03, 0.99, -0.045), brass)
	var shackle := MeshInstance3D.new()
	shackle.name = "PadlockShackle"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.012
	tm.outer_radius = 0.018
	shackle.mesh = tm
	shackle.material_override = steel
	shackle.rotation.x = PI * 0.5
	shackle.position = Vector3(gate_w * 0.5 + 0.03, 1.03, -0.045)
	gate.add_child(shackle)
	if hd_lock:
		for nm in ["Hasp", "PadlockBody", "PadlockShackle"]:
			var old := gate.get_node_or_null(nm)
			if old:
				old.free()
	_add_plate(g, "HOLDING CAGE\nDETAINED PASSENGERS", Vector3(gx, 2.13, z0 - 0.03), Vector3(0, 0, -1), "red", false, 0.022)
	# Slatted bench along the outer wall, a bucket in the corner.
	var bench := _wall_frame(g, "Bench", Vector3(gx, 0, wi), Vector3(0, 0, -1))
	_cage_bench(bench, cage_length - 0.6)
	var bk := _wall_frame(g, "Bucket", Vector3(x_end + bs * 0.25, 0, wi - 0.25), Vector3(0, 0, -1))
	if not HDProps.place(bk, "pail"):
		_cyl_v(bk, "Pail", 0.13, 0.11, 0.26, Vector3(0, 0.13, 0), _svc_mat("tin"))
	# Bars over the window.
	var wx := _along(_span() - cage_length * 0.5)
	var xf := _window_xform(wx, window_sill + window_height * 0.5, 1.0)
	var bars := Node3D.new()
	bars.name = "WindowBars"
	bars.transform = xf
	g.add_child(bars)
	var bz := -wall_thickness * 0.5 - 0.05
	var n_bars := 7
	for i in n_bars:
		var x := -window_width * 0.5 + (i + 0.5) * window_width / n_bars
		_add_rod(bars, "Bar", Vector3(x, -window_height * 0.5 - 0.04, bz), Vector3(x, window_height * 0.5 + 0.04, bz), 0.011, steel)
	for y in [-window_height * 0.5 - 0.04, 0.0, window_height * 0.5 + 0.04]:
		_add_mesh(bars, "BarRail", Vector3(window_width + 0.1, 0.03, 0.012), Vector3(0, y, bz), steel)
	# Collision: the mesh walls (gate included, it is locked) up to the ceiling.
	var body := StaticBody3D.new()
	body.name = "CageCollision"
	g.add_child(body)
	for sh in [[Vector3(xb - xa, 2.3, 0.06), Vector3(gx, 1.15, z0)], [Vector3(0.06, 2.3, zl), Vector3(x_open, 1.15, (z0 + wi) * 0.5)]]:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = sh[0]
		cs.shape = bx
		cs.position = sh[1]
		body.add_child(cs)

func _mesh_panel(parent: Node3D, pname: String, pos: Vector3, size: Vector2, rot_y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = pname
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := (mat as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("size", size)
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)

func _cage_bench(n: Node3D, w: float) -> void:
	if HDProps.place(n, "cage_bench", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(w / 2.2, 1.0, 1.0))):
		_furniture_body(n, Vector3(w, 0.45, 0.4), Vector3(0, 0.225, -0.2))
		return
	var steel := _van_mat("steel")
	var wood := trim_material
	var h := 0.45
	for k in 4:
		_add_mesh(n, "BenchSlat", Vector3(w, 0.025, 0.08), Vector3(0, h, -0.05 - k * 0.095), wood)
	for k in 2:
		_add_mesh(n, "BackSlat", Vector3(w, 0.08, 0.025), Vector3(0, 0.62 + k * 0.14, -0.02), wood)
	for sx in [-1.0, 1.0]:
		_add_mesh(n, "Bracket", Vector3(0.03, h, 0.03), Vector3(sx * (w * 0.5 - 0.1), h * 0.5, -0.35), steel)
		_add_rod(n, "Stay", Vector3(sx * (w * 0.5 - 0.1), h - 0.02, -0.38), Vector3(sx * (w * 0.5 - 0.1), 0.15, -0.01), 0.01, steel)
	_furniture_body(n, Vector3(w, h, 0.4), Vector3(0, h * 0.5, -0.2))

# ————— loading doors —————

# Pair of sliding loading doors on the outside of the body, closed, following the wall's lean:
# boarded leaves in the livery with a top runner, bottom guide, grab handles and a lock bar.
# Inside, the opening shows a varnished inner skin.
func _loading_door(parent: Node3D, z_side: float) -> void:
	var t := wall_thickness
	var m := _add_marker(parent, "LoadingDoor_%s" % ("L" if z_side < 0.0 else "R"),
			Vector3(_door_x(), 0, z_side * (width * 0.5 - t * 0.5)))
	m.rotation.y = 0.0 if z_side < 0.0 else PI      # marker -Z out of the car, +Z into it
	var n := Node3D.new()
	n.name = "Leaves"
	m.add_child(n)
	var livery := _van_mat("livery")
	var dark := _svc_mat("dark")
	var steel := _van_mat("steel")
	var brass := _brass_mat()
	var w := loading_door_width
	var lw := w * 0.5 + 0.03
	var y0 := -0.17
	var y1 := door_height + 0.03
	var zc := -t * 0.5 - 0.022
	for sx in [-1.0, 1.0]:
		var cx: float = sx * (w * 0.25 + 0.015)
		_add_mesh(n, "Leaf", Vector3(lw, y1 - y0, 0.035), Vector3(cx, (y0 + y1) * 0.5, zc), livery)
		var boards := 6
		for k in boards - 1:
			var gx := cx - lw * 0.5 + (k + 1) * lw / boards
			_add_mesh(n, "BoardJoint", Vector3(0.006, y1 - y0 - 0.16, 0.002), Vector3(gx, (y0 + y1) * 0.5, zc - 0.0185), dark)
		for y in [y0 + 0.08, (y0 + y1) * 0.5, y1 - 0.08]:
			_add_mesh(n, "LeafRail", Vector3(lw - 0.02, 0.09, 0.012), Vector3(cx, y, zc - 0.022), livery)
		var brace := _add_mesh(n, "Brace", Vector3(0.07, (y1 - y0) * 0.5, 0.012), Vector3(cx, (y0 + y1) * 0.5 - (y1 - y0) * 0.25, zc - 0.022), livery)
		brace.rotation.z = sx * 0.55
		_add_rod(n, "GrabHandle", Vector3(sx * 0.07, 0.75, zc - 0.05), Vector3(sx * 0.07, 1.3, zc - 0.05), 0.012, brass)
		for y in [0.75, 1.3]:
			_add_rod(n, "HandleStay", Vector3(sx * 0.07, y, zc - 0.018), Vector3(sx * 0.07, y, zc - 0.05), 0.008, brass)
		_add_mesh(n, "Roller", Vector3(0.08, 0.06, 0.04), Vector3(cx - sx * lw * 0.3, y1 + 0.02, zc - 0.01), steel)
		# Inner skin, seen from inside the van.
		_add_mesh(n, "InnerSkin", Vector3(lw - 0.02, y1 - y0 - 0.2, 0.01), Vector3(cx, (0.0 + door_height) * 0.5, t * 0.5 - 0.008), _van_mat("varnish"))
	_add_mesh(n, "TopRunner", Vector3(w * 2.0 + 0.2, 0.05, 0.05), Vector3(0, y1 + 0.06, zc - 0.005), steel)
	_add_mesh(n, "BottomGuide", Vector3(w * 2.0 + 0.2, 0.04, 0.04), Vector3(0, y0 - 0.02, zc + 0.005), steel)
	_add_mesh(n, "LockBar", Vector3(0.36, 0.035, 0.02), Vector3(0, 1.0, zc - 0.03), steel)
	_add_mesh(n, "LockStaple", Vector3(0.04, 0.06, 0.03), Vector3(0.05, 1.0, zc - 0.035), brass)
	_lean_with_wall(n)
	# The leaves are locked shut: block the opening cut through the shell's collision.
	_furniture_body(m, Vector3(w + 0.12, door_height + 0.1, t + 0.14), Vector3(0, door_height * 0.5, 0))
