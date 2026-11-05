extends SceneTree
## Hitch hunter: runs the train at line speed over a stretch of the line and, for every frame over
## the threshold, prints where the train was and what entered the tree in that frame (counted by the
## first two levels under the journey scene, e.g. "Scenery/st_3"), plus resources that finished
## loading. Saloon window view, horror off.
## Each hitch is split into the time before drawing (scripts, add_child, _ready, physics) and the
## drawing itself (render thread work, pipeline/shader compiles), and the classes and scripts of a
## big subtree that came in are listed.
##   godot --path . --resolution 1920x1080 -s tools/_perf_hitch.gd -- <from_s> <to_s> [threshold_ms=60]

var _added := {}
var _world: Node3D
var _roots := {}                   # key -> first node added under it this frame
var _pre_us := 0
var _post_us := 0
var _prev_post_us := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var from_s := float(args[0]) if args.size() > 0 else 3500.0
	var to_s := float(args[1]) if args.size() > 1 else 4300.0
	var thr := float(args[2]) if args.size() > 2 else 60.0
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(_world)
	var j: Node = _world.get_node("Journey")
	var ts: Node = root.get_node("TrainState")
	var player: Node3D = _world.get_node("Player")
	var cam := Camera3D.new()
	cam.far = 9000
	cam.fov = 75
	_world.add_child(cam)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	(get_first_node_in_group("horror") as HorrorDirector).enabled = false
	player.global_position = Vector3(-31.0, 1.45, 0.6)
	cam.make_current()
	cam.global_position = Vector3(-4.0, 2.9, 0.4)
	cam.look_at(Vector3(-6.0, 2.6, 6.0))
	for i in 300:
		await process_frame
	j.call("warp_running", from_s)
	for i in 240:
		await process_frame
	node_added.connect(_on_added)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void:
		_prev_post_us = _post_us
		_post_us = Time.get_ticks_usec())
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	print("## hitches over %.0f ms, s %.0f -> %.0f" % [thr, from_s, to_s])
	var last := Time.get_ticks_usec()
	var frames := 0
	var worst := 0.0
	_added.clear()
	while float(ts.get("distance")) < to_s and frames < 60 * 600:
		await process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		worst = maxf(worst, ms)
		if ms > thr:
			var keys := _added.keys()
			keys.sort_custom(func(a, b) -> bool: return _added[a] > _added[b])
			var parts: Array = []
			for k in keys.slice(0, 6):
				parts.append("%s x%d" % [k, _added[k]])
			print("HITCH %.0f ms at s=%.0f (%s, phase %s): %s" % [ms, float(ts.get("distance")),
					str(RouteData.station_at(float(ts.get("distance"))).get("name", "open line")), str(ts.get("phase")),
					", ".join(parts) if not parts.is_empty() else "nothing added"])
			print("      before draw %.0f ms, draw %.0f ms (cpu render %.1f, gpu %.1f)" % [(_pre_us - _prev_post_us) / 1000.0,
					(_post_us - _pre_us) / 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(vp),
					RenderingServer.viewport_get_measured_render_time_gpu(vp)])
			for k in keys.slice(0, 2):
				if int(_added[k]) > 100 and is_instance_valid(_roots.get(k)):
					_describe(_roots[k])
		_added.clear()
		_roots.clear()
		if str(ts.get("phase")) == "stopped":
			j.call("warp_running", float(ts.get("distance")) + 40.0)     # (keep rolling through stops)
	print("frames %d  worst %.0f ms" % [frames, worst])
	quit(0)

func _on_added(n: Node) -> void:
	var p := str(_world.get_path_to(n)) if _world.is_ancestor_of(n) else "(outside) " + n.get_class()
	var bits := p.split("/")
	var key := "/".join(bits.slice(0, mini(2, bits.size())))
	if key.begins_with("@"):
		key = n.get_class()
	_added[key] = int(_added.get(key, 0)) + 1
	if not _roots.has(key):
		_roots[key] = n

func _describe(n: Node) -> void:
	var classes := {}
	var scripts := {}
	for c: Node in [n] + n.find_children("*", "", true, false):
		classes[c.get_class()] = int(classes.get(c.get_class(), 0)) + 1
		if c.get_script() != null:
			var f := (c.get_script() as Script).resource_path.get_file()
			scripts[f] = int(scripts.get(f, 0)) + 1
	print("      %s classes %s" % [n.name, classes])
	print("      scripts %s" % [scripts])
