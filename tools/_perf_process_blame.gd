extends SceneTree
## Which nodes cost the CPU "process" time: in the open-line spot of _perf_baseline (running at line
## speed, saloon window view), it switches off processing for one kind of node at a time (by script,
## or by engine class for script-less nodes that process internally: animation players, 3D audio...)
## and reports how much TIME_PROCESS / TIME_PHYSICS_PROCESS and the frame drop. Measurement only:
## the game may misbehave while a kind is off; each kind is switched back before the next.
##   godot --path . --resolution 1920x1080 -s tools/_perf_process_blame.gd -- [stop|run] [frames=150]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "run"
	var n_frames := int(args[1]) if args.size() > 1 else 150
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var j: Node = world.get_node("Journey")
	var player: Node3D = world.get_node("Player")
	var cam := Camera3D.new()
	cam.far = 9000
	cam.fov = 75
	world.add_child(cam)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	(get_first_node_in_group("horror") as HorrorDirector).enabled = false
	player.global_position = Vector3(-31.0, 1.45, 0.6)
	player.set_physics_process(false)
	cam.make_current()
	cam.global_position = Vector3(-4.0, 2.9, 0.4)
	cam.look_at(Vector3(-6.0, 2.6, 6.0))
	await _frames(400)
	if mode == "run":
		j.call("warp_running", 4100.0)
	else:
		j.call("warp_to_stop", 1)
	await _frames(240)
	# Kinds of processing nodes.
	var kinds := {}
	for n: Node in root.find_children("*", "", true, false):
		if n == cam:
			continue
		var k := ""
		if n.get_script() != null and (n.is_processing() or n.is_physics_processing()):
			k = (n.get_script() as Script).resource_path.get_file()
			if k == "":
				k = "(built-in script on %s)" % n.get_class()
		elif n.is_processing_internal() or n.is_physics_processing_internal():
			k = "[" + n.get_class() + "]"
		if k == "":
			continue
		if not kinds.has(k):
			kinds[k] = []
		kinds[k].append(n)
	var base := await _measure(n_frames)
	print("## process blame (%s)  frame %.2f ms  process %.2f ms  physics %.2f ms" % [mode, base.frame, base.proc, base.phys])
	print("| kind | nodes | frame ms | saves frame | saves process | saves physics |")
	print("|---|---|---|---|---|---|")
	var rows: Array = []
	for k: String in kinds:
		var nodes: Array = kinds[k]
		var saved := []
		for n: Node in nodes:
			saved.append(n.process_mode)
			n.process_mode = Node.PROCESS_MODE_DISABLED
		await _frames(20)
		var m := await _measure(n_frames)
		for i in nodes.size():
			if is_instance_valid(nodes[i]):
				(nodes[i] as Node).process_mode = saved[i]
		await _frames(20)
		rows.append([k, nodes.size(), m.frame, base.frame - m.frame, base.proc - m.proc, base.phys - m.phys])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[4] > b[4])
	for r: Array in rows:
		print("| %s | %d | %.2f | %+.2f | %+.2f | %+.2f |" % r)
	var again := await _measure(n_frames)
	print("re-measured baseline: frame %.2f ms  process %.2f ms" % [again.frame, again.proc])
	quit(0)

func _measure(n: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var phys := 0.0
	for i in n:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return {"frame": float(Time.get_ticks_usec() - t0) / 1000.0 / n, "proc": proc / n, "phys": phys / n}

func _frames(n: int) -> void:
	for i in n:
		await process_frame
