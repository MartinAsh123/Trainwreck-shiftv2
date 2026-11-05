extends SceneTree
# A clip of the double-track event as Kevin sees it (run with --write-movie <file.avi> --fixed-fps 24):
#   standing in coach two's aisle, looking out at the second track; the goods train's lamp, the train
#   going by; the lamps die and he turns toward the aisle in the dark; the lamps stutter back.
#   -- [stretch index, default 1]
var cam: Camera3D

func _initialize() -> void:
	var idx := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 1
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var pt: PassingTrain = get_first_node_in_group("passing_train")
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = false
	get_first_node_in_group("haunt").enabled = false
	get_first_node_in_group("horror").enabled = false
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	var fr := get_first_node_in_group("anomaly_frenzy")
	if fr:
		fr.set_process(false)
	var player: Node3D = world.get_node("Player")
	player.set_physics_process(false)
	player.get_node("HUD").visible = false
	var s: float = pt.sections[idx]
	pt._next = idx
	world.get_node("Journey").call("warp_running", s - 560.0)
	pax._on_departing("")                              # (boarders left mid-aisle by the warp: seated)
	player.global_position = Vector3(-2.6, 1.45, 0.0)
	cam = Camera3D.new()
	cam.fov = 72
	world.add_child(cam)
	cam.make_current()
	var eye := Vector3(-2.6, 3.0, -0.05)
	cam.global_position = eye
	var window_dir := (Vector3(-3.9, 2.65, 2.0) - eye).normalized()
	var aisle_dir := (Vector3(3.5, 2.75, 0.0) - eye).normalized()
	cam.look_at(eye + window_dir)
	var look := window_dir
	var el := 0.0
	var turn := 0.0
	var after := -1.0
	while el < 75.0:
		await process_frame
		var dt := 1.0 / 24.0
		el += dt
		# A slow drift while waiting, to keep it alive.
		var want := window_dir
		if pt.state in ["dark", "show"]:
			turn = minf(turn + dt / 2.4, 1.0)            # turns to the aisle in the dark
		if turn > 0.0:
			want = window_dir.slerp(aisle_dir, smoothstep(0.0, 1.0, turn))
		look = look.slerp(want, 0.12)
		var sway := Vector3(0, sin(el * 0.9) * 0.004, 0)
		cam.global_position = eye + sway
		cam.look_at(eye + look + sway)
		var args := OS.get_cmdline_user_args()
		if args.size() > 2 and args[1] == "shots" and pt.state == "coming" \
				and absf(pt._head_x + 2.6) < 90.0 and int(el * 24.0) % 3 == 0:
			root.get_viewport().get_texture().get_image().save_png("%s/near_%04d.png" % [args[2], int(el * 24.0)])
		if pt.state == "show" and after < 0.0:
			after = el
			for f: Dictionary in pt._figures:
				var b: Node3D = f.body
				print("FIGURE %s seated=%s at %.2f m" % [b.name, not (f.seat as Dictionary).is_empty(),
						Vector2(eye.x - b.global_position.x, eye.z - b.global_position.z).length()])
		if after >= 0.0 and el - after > 13.5:
			break
	quit(0)
