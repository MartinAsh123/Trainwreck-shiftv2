extends SceneTree
## A/B check of a suspect from _perf_process_blame: in the same open-line spot, switches processing
## of one kind of node off and on several times in turn and reports the frame time each way, so a
## saving can be told from drift.
##   godot --path . --resolution 1920x1080 -s tools/_perf_ab.gd -- <kind[,kind...]> [rounds=4] [frames=300] [stop|run]
## kind: a script file name (shift_hud.gd) or an engine class in brackets ([CPUParticles3D]).
## "hide:<NodeName>" hides a node instead (draw cost, e.g. hide:ShiftHUD).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var wanted: PackedStringArray = args[0].split(",") if args.size() > 0 else PackedStringArray(["shift_hud.gd"])
	var rounds := int(args[1]) if args.size() > 1 else 4
	var n_frames := int(args[2]) if args.size() > 2 else 300
	var mode: String = args[3] if args.size() > 3 else "run"
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
	for kind in wanted:
		var nodes: Array = []
		var hide := kind.begins_with("hide:")
		for n: Node in root.find_children("*", "", true, false):
			if n == cam:
				continue
			if hide:
				if String(n.name) == kind.trim_prefix("hide:") and (n is CanvasItem or n is Node3D or n is CanvasLayer):
					nodes.append(n)
			elif kind.begins_with("["):
				if n.get_class() == kind.trim_prefix("[").trim_suffix("]"):
					nodes.append(n)
			elif n.get_script() != null and (n.get_script() as Script).resource_path.get_file() == kind:
				nodes.append(n)
		var on := []
		var off := []
		for r in rounds:
			on.append(await _measure(n_frames))
			_switch(nodes, false, hide)
			await _frames(20)
			off.append(await _measure(n_frames))
			_switch(nodes, true, hide)
			await _frames(20)
		var a := _mean(on)
		var b := _mean(off)
		print("AB %-22s x%-3d on %.2f ms  off %.2f ms  saves %+.2f ms  (on %s | off %s)" % [kind, nodes.size(), a, b, a - b,
				" ".join(on.map(func(x): return "%.2f" % x)), " ".join(off.map(func(x): return "%.2f" % x))])
	quit(0)

var _saved := {}

func _switch(nodes: Array, enable: bool, hide: bool) -> void:
	for n in nodes:
		if not is_instance_valid(n):
			continue
		if hide:
			n.set("visible", enable)
		elif enable:
			n.process_mode = _saved.get(n, Node.PROCESS_MODE_INHERIT)
		else:
			_saved[n] = n.process_mode
			n.process_mode = Node.PROCESS_MODE_DISABLED

func _mean(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxf(a.size(), 1)

func _measure(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / n

func _frames(n: int) -> void:
	for i in n:
		await process_frame
