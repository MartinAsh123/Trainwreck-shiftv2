extends SceneTree
## Finds which part of the journey scene costs the frame time: measures a view, then disables the
## processing of each top-level node (and, separately, hides it) and measures again.
##   godot --path . -s tools/perf_blame.gd -- [width] [height]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var w := int(args[0]) if args.size() > 0 else 1920
	var h := int(args[1]) if args.size() > 1 else 1080
	DisplayServer.window_set_size(Vector2i(w, h))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	world.get_node("Journey").set_physics_process(false)
	var player: Node = world.get_node("Player")
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.far = 9000
	world.add_child(cam)
	await _frames(30)
	player.get_node("HUD").visible = false
	cam.make_current()
	cam.global_position = Vector3(-1.5, 3.0, 0.2)
	cam.look_at(Vector3(-14.0, 2.7, 0.0))
	await _frames(400)
	var base := await _measure()
	print("baseline  frame %.2f ms" % base)
	for n: Node in world.get_children():
		if n == cam:
			continue
		var pm := n.process_mode
		n.process_mode = Node.PROCESS_MODE_DISABLED
		await _frames(30)
		var t := await _measure()
		n.process_mode = pm
		var vis_t := -1.0
		if n is Node3D:
			(n as Node3D).visible = false
			await _frames(30)
			vis_t = await _measure()
			(n as Node3D).visible = true
		await _frames(30)
		print("%-14s no-process %7.2f ms (saves %6.2f)   hidden %7.2f ms (saves %6.2f)" % [n.name, t, base - t, vis_t, base - vis_t if vis_t > 0 else 0.0])
	# Inside the train: disable processing per script type.
	var train := world.get_node("Train")
	var by_script := {}
	for n: Node in train.find_children("*", "", true, false):
		if n.get_script() != null:
			var k: String = (n.get_script() as Script).resource_path.get_file()
			if not by_script.has(k):
				by_script[k] = []
			by_script[k].append(n)
	base = await _measure()
	print("train baseline %.2f ms" % base)
	for k: String in by_script:
		var nodes: Array = by_script[k]
		var saved := []
		for n: Node in nodes:
			saved.append(n.process_mode)
			n.process_mode = Node.PROCESS_MODE_DISABLED
		await _frames(20)
		var t := await _measure()
		for i in nodes.size():
			(nodes[i] as Node).process_mode = saved[i]
		await _frames(20)
		print("  %-24s x%-3d disabled -> %7.2f ms (saves %6.2f)" % [k, nodes.size(), t, base - t])
	# Per-script _process cost inside the heaviest subtrees: count processing nodes by script.
	var counts := {}
	for n: Node in world.find_children("*", "", true, false):
		if n.get_script() != null and (n.is_processing() or n.is_physics_processing()):
			var k: String = (n.get_script() as Script).resource_path.get_file()
			counts[k] = counts.get(k, 0) + 1
	print("processing nodes by script: ", counts)
	quit(0)

func _measure() -> float:
	var t0 := Time.get_ticks_usec()
	for i in 120:
		await process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / 120.0

func _frames(n: int) -> void:
	for i in n:
		await process_frame
