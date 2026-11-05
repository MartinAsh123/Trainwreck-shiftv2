extends SceneTree
## How the frames go while one station's life (WorldLife._station_life: hall, bell, then the yard
## in its spread steps) is built, the train held still out on the line: per frame, the frame time,
## the nodes added under the station and what entered. Windowed.
##   godot --path . --resolution 1920x1080 -s tools/_perf_yard_split.gd -- [station key=st_VRCHOVINA] [repeats=3] [at_s=3850]

var _count := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var key: String = args[0] if args.size() > 0 else "st_VRCHOVINA"
	var reps := int(args[1]) if args.size() > 1 else 3
	var at_s := float(args[2]) if args.size() > 2 else 3850.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	(get_first_node_in_group("horror") as HorrorDirector).enabled = false
	for i in 200:
		await process_frame
	var j: Node = world.get_node("Journey")
	j.call("warp_running", at_s)
	j.set_physics_process(false)
	for i in 400:
		await process_frame
	var scenery: Node = world.get_node("Scenery")
	var feat: Dictionary = {}
	for f: Dictionary in scenery.get("_features"):
		if f.key == key:
			feat = f
	if feat.is_empty():
		print("no feature ", key)
		quit(1)
		return
	var wl: Node = world.get_node("WorldLife")
	# Background frame time, nothing being built.
	var base := 0.0
	var last := Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		base += (now - last) / 1000.0
		last = now
	print("background frame %.1f ms" % (base / 120.0))
	for r in reps:
		var node: Node3D = scenery.call("_build_station", Terrain.new(), feat.data)
		node.name = key             # _station_life finds its station by name
		_count = 0
		var cb := func(_n: Node) -> void: _count += 1
		node_added.connect(cb)
		await process_frame
		last = Time.get_ticks_usec()
		world.add_child(node)
		var t_add := (Time.get_ticks_usec() - last) / 1000.0
		wl.call("_station_life", node)          # what WorldLife does when Scenery adds the station (spread: far from the train)
		var line: Array = ["add_child %.0f ms" % t_add]
		for f in 8:
			await process_frame
			var now := Time.get_ticks_usec()
			line.append("f%d %.0f ms (+%d)" % [f, (now - last) / 1000.0, _count])
			_count = 0
			last = now
		node_added.disconnect(cb)
		print("run %d: %s" % [r, ", ".join(line)])
		node.queue_free()
		for i in 120:
			await process_frame
	quit(0)
