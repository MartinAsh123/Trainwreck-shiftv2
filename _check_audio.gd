extends SceneTree
func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var j: Journey = world.get_node("Journey")
	await process_frame
	await process_frame
	await process_frame
	var a: GameAudio = world.get_node("Audio")
	var missing := []
	for k in ["rail_loop", "loco_idle", "wind_loop", "crt_hum", "loco_chuff", "loco_whistle", "brakes", "station_bell",
			"door_slide_open", "door_slide_close", "door_hinge_open", "door_hinge_close", "door_locked", "curtain",
			"lock_turn", "land", "pc_click", "pc_startup", "pc_notify"]:
		if a.s(k) == null:
			missing.append(k)
	print("missing streams: ", missing)
	print("variants: carpet ", a._variants("step_carpet").size(), " snow ", a._variants("step_snow").size(), " keys ", a._variants("pc_key").size())
	print("rails ", a._rails.size(), " idle ", a._idle != null, " wind playing ", a._wind.playing)
	# Exercise: a door, footsteps, departure (whistle, bell), running speed (chuffs).
	var played := [0]
	for p in a._pool:
		p.finished.connect(func(): played[0] += 1)
	var d = get_first_node_in_group("train_door")
	d.interact()
	a._on_step("snow", 0.7)
	a._on_step("default", 0.5)
	j._timer = 0.0
	for i in 400:
		await physics_frame
	var busy := 0
	for p in a._pool:
		if p.playing:
			busy += 1
	print("phase ", root.get_node("TrainState").phase, " speed ", snappedf(root.get_node("TrainState").speed, 0.1), " one-shot players busy ", busy, " finished ", played[0])
	print("rail volume ", snappedf(a._rails[0].volume_db, 0.1), " pitch ", snappedf(a._rails[0].pitch_scale, 0.01))
	quit(0)
