extends SceneTree
# A clip of the four breakdowns a ghost causes, as Kevin does them (run with --write-movie <file.avi>
# --fixed-fps 24): the emergency brake, the heating hatch (screwdriver), the W.C. (plunger) and the
# terminal (USB stick). The real player is driven: his prompts, toolbar and messages are the game's.
#   -- ebrake   only the emergency brake, watching the lever as it is pulled
var world: Node3D
var player: CharacterBody3D
var head: Node3D
var h: HauntDirector
var ts: Node
var cap: Label
var want_pos := Vector3.INF
var aim := Vector3.INF
var walk := 1.3

func _initialize() -> void:
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	ts = root.get_node("TrainState")
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = false
	get_first_node_in_group("horror").enabled = false
	var pt := get_first_node_in_group("passing_train")
	if pt:
		pt.enabled = false
	var fr := get_first_node_in_group("anomaly_frenzy")
	if fr:
		fr.set_process(false)
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	duty.next_patrol = 999.0
	duty.rest_enabled = false
	h = get_first_node_in_group("haunt")
	h.deadline = 9999.0
	h.deadline_max = 9999.0
	h.flash_gap = Vector2(999, 999)
	world.get_node("Journey").call("warp_running", 6600.0)
	pax._on_departing("")
	player = world.get_node("Player")
	head = player.get_node("Head")
	_caption_layer()
	# A ghost aboard (its car is where things go wrong).
	h.first_start = 0.0
	h._next_start = 0.0
	while h.stage != "signs":
		await process_frame
	var car: Node3D = h.car
	var floor_y := 1.45

	# ——— 1. the emergency brake ———
	var brake: Node3D = null
	for n: Node3D in car.find_children("EmergencyBrake_*", "", true, false):
		if brake == null or n.global_position.distance_to(h.ghost.body.global_position) < brake.global_position.distance_to(h.ghost.body.global_position):
			brake = n
	var bp := brake.global_position
	var into := signf(car.global_position.x - bp.x)
	var only := OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "ebrake"
	if only:
		# Looking down the car towards the partition, the brake in view, the line running past.
		_put(Vector3(bp.x + into * 2.6, floor_y, -0.35), bp + Vector3(0, -0.3, -0.2))
		_caption("The emergency brake")
		await _hold(3.0)
	else:
		_put(Vector3(bp.x + into * 3.2, floor_y, -0.25), Vector3(bp.x + into * 3.2, 2.9, 3.0))
		_caption("1 / 4   The emergency brake")
		await _hold(2.5)
	h._breaks_used = ["ac", "toilet", "computer"]
	h._start_incident()
	print("INCIDENT ", h.incident, " spots ", h._spots.map(func(s): return s.name), " phase ", ts.phase, " speed ", ts.speed)
	await _hold(0.6)
	aim = bp + Vector3(0, -0.25, 0)
	await _hold(2.5)
	aim = Vector3(bp.x + into * 3.0, 2.8, 3.0)                  # (out of the window: the line slowing)
	await _hold(3.0)
	want_pos = Vector3(bp.x + into * 0.6, floor_y, 0.5)
	aim = bp + Vector3(0, -0.2, 0)
	while float(ts.speed) > 0.05:
		await _hold(0.1)
	await _hold(1.0)
	_press()
	await _hold(1.5)
	if only:
		aim = bp + Vector3(0, -0.2, 0)
		await _hold(1.5)
	aim = Vector3(bp.x + into * 2.0, 2.8, 3.0)
	await _hold(4.5 if not only else 6.0)
	if only:
		quit(0)
		return

	# ——— 2. the heating unit ———
	h._breaks_used = ["ebrake", "toilet", "computer"]
	h._start_incident()
	print("INCIDENT ", h.incident, " spots ", h._spots.map(func(s): return s.name), " phase ", ts.phase, " speed ", ts.speed)
	var svc := root.find_child("ServiceRoom", true, false) as Node3D
	var dr := svc.get_node("Drawers") as Node3D
	var sc: Node3D = h._items["screwdriver"]
	_put(dr.global_transform * Vector3(0.1, 0, -1.05), sc.global_position)
	_put_y(floor_y)
	_caption("2 / 4   The heating unit")
	await _hold(2.0)
	_press()
	await _hold(1.5)
	var hatch: Node3D = _spot("HatchLatch")
	var hp := hatch.global_position
	_put(Vector3(hp.x + signf(car.global_position.x - hp.x) * 0.4, floor_y, -0.15), hp)
	_put_y(floor_y)
	await _hold(1.6)
	_press()
	await _hold(1.6)
	for c in ["red", "yellow", "black"]:
		aim = _spot("Cable_" + c).global_position + Vector3(0, -0.05, 0)
		await _hold(1.1)
		_press()
		await _hold(0.5)
	aim = hp + Vector3(0, 0, -0.26)                             # (the hatch's edge, clear of the cables)
	await _hold(1.0)
	_press()
	await _hold(2.5)

	# ——— 3. the W.C. ———
	h._breaks_used = ["ebrake", "ac", "computer"]
	h._start_incident()
	print("INCIDENT ", h.incident, " spots ", h._spots.map(func(s): return s.name), " phase ", ts.phase, " speed ", ts.speed)
	var plf := svc.get_node("Plunger") as Node3D
	var pl: Node3D = h._items["plunger"]
	_put(plf.global_transform * Vector3(0.1, 0, -1.0), pl.global_position + Vector3(0, 0.45, 0))
	_put_y(floor_y)
	_caption("3 / 4   The W.C.")
	await _hold(2.0)
	_press()
	await _hold(1.4)
	var bowl: Node3D = _spot("BlockedBowl")
	var bw := bowl.global_position
	_put(Vector3(bw.x - 0.95, floor_y, bw.z - 0.05), Vector3(bw.x - 0.5, 1.45, bw.z - 0.1))
	_put_y(floor_y)
	await _hold(1.8)
	aim = bw
	await _hold(0.8)
	for i in 3:
		_press()
		await _hold(0.9)
	aim = Vector3(bw.x - 0.5, 1.45, bw.z - 0.1)
	await _hold(2.0)

	# ——— 4. the terminal ———
	h._breaks_used = ["ebrake", "ac", "toilet"]
	h._start_incident()
	print("INCIDENT ", h.incident, " spots ", h._spots.map(func(s): return s.name), " phase ", ts.phase, " speed ", ts.speed)
	var ns := root.find_child("InspectorRoom", true, false).get_node("Nightstand") as Node3D
	var us: Node3D = h._items["usb"]
	_put(ns.global_transform * Vector3(0.12, 0, -0.85), us.global_position)
	_put_y(floor_y)
	_caption("4 / 4   The terminal")
	await _hold(2.0)
	_press()
	await _hold(1.4)
	var term: ComputerTerminal = car.find_children("*", "ComputerTerminal", true, false)[0]
	var tp := term.global_position
	var tf := -term.global_basis.z
	_put(Vector3(tp.x, floor_y, tp.z) + Vector3(tf.x, 0, tf.z).normalized() * 0.75, tp)
	_put_y(floor_y)
	await _hold(2.0)
	_press()
	while h.incident != "":
		await _hold(0.1)
	await _hold(3.0)
	quit(0)

# ————— driving Kevin —————

func _spot(n: String) -> Node3D:
	for s in h._spots:
		if is_instance_valid(s) and s.name == n:
			return s
	return null

# Cut to standing at `pos`, looking at `look`.
func _put(pos: Vector3, look: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	want_pos = pos
	aim = look
	_face(1.0)

func _put_y(y: float) -> void:
	player.global_position.y = y
	want_pos.y = y

func _face(k: float) -> void:
	var eye := head.global_position
	var d := aim - eye
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	player.rotation.y = lerp_angle(player.rotation.y, yaw, k)
	head.rotation.x = lerpf(head.rotation.x, pitch, k)

func _hold(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await process_frame
		var dt := root.get_process_delta_time()
		t += dt
		if want_pos != Vector3.INF:
			var p := player.global_position
			var to := Vector3(want_pos.x, p.y, want_pos.z)
			player.global_position = p.move_toward(to, walk * dt)
		if aim != Vector3.INF:
			_face(0.12)

func _press() -> void:
	var t = player.get("_target")
	print("PRESS target ", t.name if t else "none", " eye ", head.global_position, " aim ", aim, " cam fwd ", -player.get("_cam").global_basis.z)
	player.call("_interact")

func _caption_layer() -> void:
	var c := CanvasLayer.new()
	c.layer = 50
	world.add_child(c)
	cap = Label.new()
	cap.set_anchors_preset(Control.PRESET_CENTER_TOP)
	cap.position = Vector2(-300, 70)
	cap.size = Vector2(600, 40)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 30)
	cap.add_theme_color_override("font_outline_color", Color.BLACK)
	cap.add_theme_constant_override("outline_size", 8)
	c.add_child(cap)

func _caption(text: String) -> void:
	cap.text = text
	cap.modulate.a = 1.0
	var tw := cap.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(cap, "modulate:a", 0.0, 0.6)
