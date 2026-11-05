class_name StaffPanel
extends Node3D
## The working insides of a car's STAFF ONLY cabinet: the glazed door swings open, and behind it
## the electrical switchboard and the heating control (HD models from art_source/props_hd/
## scripts/assets_staff.py; the positions below mirror its SB_* / TH_* constants).
##   Switchboard: six toggles - MAIN, VESTIBULE and W.C. switch the car's lamps of those names,
##   NIGHT the dim blue night lights, HEATING and FANS the services - each with its indicator
##   lamp; five gauges whose needles follow the load (volts, amps, battery, vacuum, steam heat).
##   Heating control: a setpoint knob (16-26 °C), HEAT / FAN / OFF buttons and a lit display that
##   shows the setpoint, the mode and the saloon temperature drifting toward it.
## The car builder calls build() with the cabinet frame and the door leaf's pivot.

const SB_GAUGES := [Vector3(-0.175, 0.105, 0.06), Vector3(0.0, 0.105, 0.06), Vector3(0.175, 0.105, 0.06),
		Vector3(-0.09, -0.02, 0.05), Vector3(0.09, -0.02, 0.05)]
const SB_T := 0.012
const SB_LAMP_V := -0.1
const SB_TOGGLE_V := -0.163
const SB_COLS := [-0.2, -0.12, -0.04, 0.04, 0.12, 0.2]
const SB_NAMES := ["MAIN", "VESTIBULE", "W.C.", "NIGHT", "HEATING", "FANS"]
const LAMP_COLORS := [Color(1.0, 0.92, 0.7), Color(1.0, 0.92, 0.7), Color(1.0, 0.92, 0.7), Color(0.45, 0.6, 1.0),
		Color(1.0, 0.25, 0.1), Color(0.3, 1.0, 0.35)]
## Lamp markers each lighting toggle switches (name prefixes in the car).
const LAMP_GROUPS := {"MAIN": ["Lamp_Saloon_", "Lamp_Corridor_"], "VESTIBULE": ["Lamp_Vestibule", "Lamp_Passage"],
		"W.C.": ["Lamp_Toilet"]}
# Gauges: caption, scale max, majors, minors, red band, green band.
const GAUGE_SPECS := [["VOLTS", 150.0, 6, 5, Vector2(130, 150), Vector2(100, 120)],
		["AMPS", 100.0, 5, 4, Vector2(80, 100), Vector2(-1, -1)],
		["BATTERY  V", 30.0, 6, 5, Vector2(0, 20), Vector2(23, 27)],
		["VACUUM  in.", 30.0, 6, 5, Vector2(0, 12), Vector2(19, 23)],
		["STEAM HEAT  psi", 80.0, 4, 4, Vector2(65, 80), Vector2(-1, -1)]]

const TH_D := 0.045
const TH_DISPLAY := Vector4(0.0, 0.078, 0.13, 0.062)
const TH_KNOB := Vector3(0.0, -0.025, 0.036)
const TH_BUTTONS_V := -0.105
const TH_BUTTONS_U := [-0.052, 0.0, 0.052]
const TH_MODES := ["HEAT", "FAN", "OFF"]
const FONT := preload("res://assets/fonts/Oswald.ttf")
const HDProps := preload("res://scripts/train/hd_props.gd")
const DOOR_OPEN_DEG := 105.0

var car: Node
var door_pivot: Node3D
var toggles: Array[LightSwitch] = []
var states := {"MAIN": true, "VESTIBULE": true, "W.C.": true, "NIGHT": false, "HEATING": true, "FANS": false}
var setpoint := 21
var mode := "HEAT"
var saloon_temp := 19.0
var door_open := false

var _lenses: Array[MeshInstance3D] = []
var _needles: Array[Node3D] = []
var _needle_val: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _knob: Node3D
var _buttons: Array[Node3D] = []
var _display: Label3D
var _night: Array[OmniLight3D] = []
var _lamps_found := false
var _door_angle := 0.0

## board: marker for the switchboard (its back on the cabinet's back board, -Z into the room);
## thermo: marker for the heating control; pivot: the door's hinge node (rotates about Y);
## leaf: the door's moving part (gets the pick area of size `leaf_size`, centred at `leaf_center`).
func build(car_node: Node, board: Node3D, thermo: Node3D, pivot: Node3D, leaf: Node3D, leaf_size: Vector3, leaf_center: Vector3) -> void:
	car = car_node
	door_pivot = pivot
	var door := StaffControl.new()
	door.name = "DoorPick"
	leaf.add_child(door)
	door.setup(self, "door", leaf_size, leaf_center)
	_build_board(board)
	_build_thermostat(thermo)
	_refresh()

# ————— switchboard —————

func _p(u: float, v: float, z: float) -> Vector3:
	return Vector3(-u, v, z)

func _build_board(board: Node3D) -> void:
	HDProps.place(board, "staff_switchboard", Transform3D.IDENTITY, "Switchboard")
	var zf := -SB_T
	for i in SB_GAUGES.size():
		var g: Vector3 = SB_GAUGES[i]
		_needles.append(_gauge(board, "Gauge_%d" % i, _p(g.x, g.y, zf), g.z, GAUGE_SPECS[i]))
	var lens_mesh := SphereMesh.new()
	lens_mesh.radius = 0.0095
	lens_mesh.height = 0.012
	lens_mesh.radial_segments = 16
	lens_mesh.rings = 6
	for i in SB_COLS.size():
		var u: float = SB_COLS[i]
		var lens := MeshInstance3D.new()
		lens.name = "Lens_%d" % i
		lens.mesh = lens_mesh
		lens.position = _p(u, SB_LAMP_V, zf - 0.004)
		lens.material_override = StandardMaterial3D.new()
		board.add_child(lens)
		_lenses.append(lens)
		var t := LightSwitch.new()
		t.name = "Toggle_%s" % SB_NAMES[i]
		t.position = _p(u, SB_TOGGLE_V, zf - 0.012)
		t.throw_deg = 40.0
		t.pick_size = Vector3(0.03, 0.05, 0.04)
		t.pick_offset = Vector3(0, 0, -0.012)
		t.label = SB_NAMES[i].to_lower()
		t.on = states[SB_NAMES[i]]
		_toggle_lever(t)
		board.add_child(t)
		t.switched.connect(_on_toggle.bind(SB_NAMES[i]))
		toggles.append(t)

# Bat-handle toggle lever: pivot at the bushing, the handle pointing out of the board (-Z).
func _toggle_lever(t: Node3D) -> void:
	var lever := Node3D.new()
	lever.name = "Toggle"
	t.add_child(lever)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.78, 0.76)
	steel.metallic = 1.0
	steel.roughness = 0.22
	var rod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0022
	cm.bottom_radius = 0.0032
	cm.height = 0.026
	cm.radial_segments = 12
	rod.mesh = cm
	rod.material_override = steel
	rod.rotation.x = PI * 0.5
	rod.position = Vector3(0, 0, -0.013)
	lever.add_child(rod)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0042
	sm.height = 0.0084
	sm.radial_segments = 12
	sm.rings = 6
	tip.mesh = sm
	tip.material_override = steel
	tip.position = Vector3(0, 0, -0.027)
	lever.add_child(tip)

# Gauge: the shared HD case, a dial (gauge_dial shader) with its caption, and a needle.
func _gauge(parent: Node3D, gname: String, pos: Vector3, r: float, spec: Array) -> Node3D:
	var g := Node3D.new()
	g.name = gname
	g.position = pos
	g.rotation.y = PI                  # local +Z (the dial's face) toward the room
	parent.add_child(g)
	if not HDProps.place(g, "gauge_case", HDProps.xf(Vector3.ZERO, Vector3.ZERO, Vector3(r / 0.1, r / 0.1, 0.8)), "Case"):
		var case_mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r + 0.01
		cm.bottom_radius = r + 0.01
		cm.height = 0.045
		case_mi.mesh = cm
		case_mi.rotation.x = PI * 0.5
		case_mi.position.z = 0.0225
		g.add_child(case_mi)
	var dial := MeshInstance3D.new()
	dial.name = "Dial"
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	dial.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/props/gauge_dial.gdshader")
	var vmax: float = spec[1]
	sm.set_shader_parameter("major_count", spec[2])
	sm.set_shader_parameter("minor_per_major", spec[3])
	var red: Vector2 = spec[4]
	var green: Vector2 = spec[5]
	if red.x >= 0.0:
		sm.set_shader_parameter("red_band", red / vmax)
	if green.x >= 0.0:
		sm.set_shader_parameter("green_band", green / vmax)
	dial.material_override = sm
	dial.position = Vector3(0, 0, 0.0488)
	g.add_child(dial)
	var cap := Label3D.new()
	cap.name = "Caption"
	cap.text = String(spec[0]).replace("  ", "\n")
	cap.font = FONT
	cap.font_size = 48
	cap.pixel_size = r * 0.1 / 48.0 * 1.25
	cap.modulate = Color(0.12, 0.09, 0.06)
	cap.outline_size = 0
	cap.double_sided = false
	cap.shaded = true
	cap.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	cap.position = Vector3(0, -r * 0.45, 0.0495)
	g.add_child(cap)
	var needle := Node3D.new()
	needle.name = "Needle"
	needle.position = Vector3(0, 0, 0.052)
	needle.set_meta("vmax", vmax)
	g.add_child(needle)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.05)
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(r * 0.05, r * 0.8, 0.002)
	bar.mesh = bm
	bar.material_override = black
	bar.position = Vector3(0, r * 0.32, 0)
	needle.add_child(bar)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = r * 0.08
	hm.bottom_radius = r * 0.08
	hm.height = 0.004
	hub.mesh = hm
	hub.rotation.x = PI * 0.5
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.79, 0.64, 0.29)
	brass.metallic = 0.85
	brass.roughness = 0.3
	hub.material_override = brass
	needle.add_child(hub)
	return needle

# ————— heating control —————

func _build_thermostat(thermo: Node3D) -> void:
	HDProps.place(thermo, "staff_thermostat", Transform3D.IDENTITY, "HeatingControl")
	var zf := -TH_D
	# Display: amber figures behind the dark glass.
	_display = Label3D.new()
	_display.name = "Display"
	_display.font = FONT
	_display.font_size = 64
	_display.pixel_size = 0.00034
	_display.line_spacing = -6.0
	_display.modulate = Color(1.0, 0.62, 0.2)
	_display.outline_size = 0
	_display.double_sided = false
	_display.shaded = false
	_display.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	_display.rotation.y = PI
	_display.position = _p(TH_DISPLAY.x, TH_DISPLAY.y, zf - 0.0025)
	thermo.add_child(_display)
	# Knob: a ribbed black bakelite skirt with a white pointer line.
	_knob = StaffControl.new()
	_knob.name = "Knob"
	_knob.position = _p(TH_KNOB.x, TH_KNOB.y, zf - 0.002)
	thermo.add_child(_knob)
	(_knob as StaffControl).setup(self, "knob", Vector3(0.08, 0.08, 0.04), Vector3(0, 0, -0.012))
	var bake := StandardMaterial3D.new()
	bake.albedo_color = Color(0.06, 0.05, 0.045)
	bake.roughness = 0.25
	bake.clearcoat_enabled = true
	bake.clearcoat = 0.6
	var knob := MeshInstance3D.new()
	var km := CylinderMesh.new()
	km.top_radius = TH_KNOB.z * 0.82
	km.bottom_radius = TH_KNOB.z
	km.height = 0.02
	km.radial_segments = 24
	knob.mesh = km
	knob.material_override = bake
	knob.rotation.x = PI * 0.5
	knob.position.z = -0.01
	_knob.add_child(knob)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.93, 0.86)
	var ptr := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.003, TH_KNOB.z * 0.7, 0.001)
	ptr.mesh = pm
	ptr.material_override = white
	ptr.position = Vector3(0, TH_KNOB.z * 0.45, -0.0205)
	_knob.add_child(ptr)
	# Push buttons with a lamp in each (the chosen mode's is lit).
	for i in TH_MODES.size():
		var b := StaffControl.new()
		b.name = "Button_" + TH_MODES[i]
		b.position = _p(TH_BUTTONS_U[i], TH_BUTTONS_V, zf)
		thermo.add_child(b)
		b.setup(self, "mode:" + TH_MODES[i], Vector3(0.032, 0.032, 0.03), Vector3(0, 0, -0.008))
		var cap := MeshInstance3D.new()
		cap.name = "Cap"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.026, 0.026, 0.01)
		cap.mesh = bm
		cap.material_override = StandardMaterial3D.new()
		b.add_child(cap)
		_buttons.append(b)

# ————— behaviour —————

func prompt_for(id: String) -> String:
	if id == "door":
		return "E — Close cabinet" if door_open else "E — Open cabinet"
	if id == "knob":
		return "E — Turn up the heating (set %d °C)" % setpoint
	if id.begins_with("mode:"):
		return "E — Heating: %s" % id.substr(5)
	return ""

func press(id: String) -> String:
	if id == "door":
		door_open = not door_open
		set_process(true)
	elif id == "knob":
		setpoint = 16 if setpoint >= 26 else setpoint + 1
	elif id.begins_with("mode:"):
		mode = id.substr(5)
	_refresh()
	return ""

func _on_toggle(on: bool, which: String) -> void:
	states[which] = on
	_refresh()

func _ready() -> void:
	set_process(true)
	# The car's lamps are built after the cabinet; take them over once everything is in place.
	await get_tree().process_frame
	await get_tree().process_frame
	_find_lamps()

func _find_lamps() -> void:
	if _lamps_found or car == null:
		return
	_lamps_found = true
	var all := car.find_children("Lamp_*", "Node3D", true, false)
	for i in SB_NAMES.size():
		var key: String = SB_NAMES[i]
		if not LAMP_GROUPS.has(key):
			continue
		for n: Node in all:
			for prefix: String in LAMP_GROUPS[key]:
				if not (String(n.name).begins_with(prefix) and n.find_child("Light", false, false) is Light3D):
					continue
				n.set_meta("dynamic", true)
				toggles[i].lamps.append(n as Node3D)
				if key == "MAIN":
					var nl := OmniLight3D.new()
					nl.name = "NightLight"
					nl.position.y = -0.25
					nl.light_color = Color(0.5, 0.6, 1.0)
					nl.light_energy = 0.22
					nl.omni_range = 3.2
					nl.shadow_enabled = false
					nl.visible = states["NIGHT"]
					# Not under the lamp marker: the MAIN switch would hide it with the lamp.
					(n.get_parent() as Node3D).add_child(nl)
					nl.global_transform = (n as Node3D).global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0))
					_night.append(nl)
				break
	for t in toggles:
		t.on = t.on                    # re-apply now that it has its lamps
	_refresh()

func _refresh() -> void:
	for i in SB_NAMES.size():
		var lit: bool = states[SB_NAMES[i]]
		if i < _lenses.size():
			var m := _lenses[i].material_override as StandardMaterial3D
			var c: Color = LAMP_COLORS[i]
			m.albedo_color = c * (0.9 if lit else 0.25)
			m.roughness = 0.15
			m.emission_enabled = lit
			m.emission = c
			m.emission_energy_multiplier = 2.2
	for nl in _night:
		nl.visible = states["NIGHT"]
	if _knob:
		_knob.rotation.z = deg_to_rad(-135.0 + 27.0 * (setpoint - 16))
	for i in _buttons.size():
		var b := _buttons[i]
		var active: bool = TH_MODES[i] == mode
		var cap := b.get_node("Cap") as MeshInstance3D
		cap.position.z = -0.003 if active else -0.006
		var m := cap.material_override as StandardMaterial3D
		m.albedo_color = Color(0.92, 0.9, 0.84)
		m.roughness = 0.3
		m.emission_enabled = active
		m.emission = Color(1.0, 0.7, 0.3) if i == 0 else (Color(0.5, 0.9, 1.0) if i == 1 else Color(1, 1, 1))
		m.emission_energy_multiplier = 0.6
	_update_display()

func _heating_on() -> bool:
	return states["HEATING"] and mode == "HEAT"

func _update_display() -> void:
	if _display == null:
		return
	if not states["HEATING"] and mode == "HEAT":
		_display.text = "SET %d°\nNO SUPPLY" % setpoint
	else:
		_display.text = "SET %d°  %s\nSALOON %.1f°" % [setpoint, mode, saloon_temp]

func _process(delta: float) -> void:
	# Door swing.
	var target := DOOR_OPEN_DEG if door_open else 0.0
	_door_angle = move_toward(_door_angle, target, delta * 240.0)
	if door_pivot:
		door_pivot.rotation.y = deg_to_rad(_door_angle)
	# Saloon temperature drifts toward the setpoint while heating, toward 12 ° otherwise.
	var goal := float(setpoint) if _heating_on() else 12.0
	var old := snappedf(saloon_temp, 0.1)
	saloon_temp = move_toward(saloon_temp, goal, delta * (0.08 if _heating_on() else 0.03))
	if snappedf(saloon_temp, 0.1) != old:
		_update_display()
	# Needles: the load on the supply.
	var lights := int(states["MAIN"]) * 2 + int(states["VESTIBULE"]) + int(states["W.C."]) + int(states["NIGHT"])
	var amps := 6.0 + lights * 7.0 + (28.0 if _heating_on() else 0.0) + (9.0 if states["FANS"] or mode == "FAN" else 0.0)
	var goals := [110.0 - amps * 0.06, amps, 24.6, 21.0, 45.0 if _heating_on() else 3.0]
	for i in _needles.size():
		_needle_val[i] = lerpf(_needle_val[i], goals[i], clampf(delta * 1.5, 0.0, 1.0))
		var vmax: float = _needles[i].get_meta("vmax")
		var a := deg_to_rad(-135.0 + 270.0 * clampf(_needle_val[i] / vmax, 0.0, 1.0))
		_needles[i].rotation.z = -a
