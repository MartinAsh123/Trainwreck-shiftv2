extends SceneTree
const HDProps := preload("res://scripts/train/hd_props.gd")
## What adding one streamed station costs on the main thread: builds the station's node the way
## Scenery does (off the tree), then times add_child with parts of it taken out first, so the
## freeze when a station comes into range can be split up. Windowed.
## The train is first moved to `at_s` and held there, so the station before has streamed out and
## its models are no longer cached (as in a real run).
##   godot --path . --resolution 1920x1080 -s tools/_perf_station_add.gd -- [station key=st_VRCHOVINA] [repeats=2] [at_s=3850]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var key: String = args[0] if args.size() > 0 else "st_VRCHOVINA"
	var reps := int(args[1]) if args.size() > 1 else 2
	var at_s := float(args[2]) if args.size() > 2 else 3850.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
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
	# What WorldLife._on_feature does on the main thread when the station enters Scenery, piece by piece.
	var wl: Node = world.get_node("WorldLife")
	var stn: Dictionary = {}
	for st: Dictionary in RouteData.STATIONS:
		if "st_" + str(st.name) == key:
			stn = st
	for r in reps:
		var node: Node3D = scenery.call("_build_station", Terrain.new(), feat.data)
		node.name = "probe2_" + key
		world.add_child(node)
		var t0 := Time.get_ticks_usec()
		for hs: Node in node.find_children("HallSpot", "Marker3D", true, false):
			StationHall.build(hs as Node3D)
		var t1 := Time.get_ticks_usec()
		for spot: Node in node.find_children("BellSpot", "Marker3D", true, false):
			HDProps.place(spot, "station_bell", Transform3D.IDENTITY, "StationBell")
		var t2 := Time.get_ticks_usec()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(stn.name)) + 5
		var probe = wl.get("_probe")
		StationYard.attach(node, stn, func(kind: String) -> Node3D: return wl.call("_car_node", kind, rng, false),
				func(s: float, z: float) -> float: return probe.height(s, z))
		var t3 := Time.get_ticks_usec()
		await process_frame
		var t4 := Time.get_ticks_usec()
		print("on_feature split (%s): StationHall.build %.0f ms, bell %.0f ms, StationYard.attach %.0f ms, next frame %.0f ms, nodes %d" % [
				"fresh" if r == 0 else "again", (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0,
				node.find_children("*", "", true, false).size()])
		node.queue_free()
		for i in 90:
			await process_frame
	print("| variant | nodes | build ms (Scenery does this on a worker) | add_child ms | next frame ms |")
	print("|---|---|---|---|---|")
	for variant in ["all", "no TalkingCharacter", "no collision", "no lights/probes", "no Label3D"]:
		for r in reps:
			var b0 := Time.get_ticks_usec()
			var node: Node3D = scenery.call("_build_station", Terrain.new(), feat.data)
			var build_ms := (Time.get_ticks_usec() - b0) / 1000.0
			node.name = "probe_" + key
			_strip(node, variant)
			var t0 := Time.get_ticks_usec()
			world.add_child(node)
			var t1 := Time.get_ticks_usec()
			await process_frame
			var t2 := Time.get_ticks_usec()
			print("| %s | %d | %.0f | %.0f | %.0f |" % [variant, node.find_children("*", "", true, false).size(), build_ms,
					(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
			node.queue_free()
			for i in 90:
				await process_frame
	quit(0)

func _strip(node: Node, variant: String) -> void:
	var gone: Array = []
	for c: Node in node.find_children("*", "", true, false):
		match variant:
			"no TalkingCharacter":
				if c is TalkingCharacter:
					gone.append(c)
			"no collision":
				if c is CollisionObject3D:
					gone.append(c)
			"no lights/probes":
				if c is Light3D or c is ReflectionProbe:
					gone.append(c)
			"no Label3D":
				if c is Label3D:
					gone.append(c)
	for c: Node in gone:
		if is_instance_valid(c) and c.get_parent():
			c.get_parent().remove_child(c)
			c.free()
