extends SceneTree
## Measures the journey scene in four typical views and prints a table:
##   frame ms (wall clock), GPU ms and CPU render ms of the main viewport, process/physics ms,
##   draw calls, objects, primitives in frame, video memory.
##   godot --path . -s tools/perf_probe.gd -- [width] [height] [label] [noworld]
## Runs windowed with vsync off. Each view: 150 warm-up frames, 300 measured frames.

const VIEWS := [
	["saloon", Vector3(-1.5, 3.0, 0.2), Vector3(-14.0, 2.7, 0.0), false],
	["platform", Vector3(-55.0, 1.9, 3.6), Vector3(-25.0, 2.4, 10.0), false],
	["running_out", Vector3(-30.0, 4.0, -13.0), Vector3(-50.0, 2.0, 0.0), true],
	["cab_fwd", Vector3(-71.2, 3.3, 0.85), Vector3(-200.0, 2.4, 1.2), true],
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var w := int(args[0]) if args.size() > 0 else 1920
	var h := int(args[1]) if args.size() > 1 else 1080
	var label: String = args[2] if args.size() > 2 else "run"
	DisplayServer.window_set_size(Vector2i(w, h))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	if args.size() > 3 and args[3] == "noworld":
		world.get_node("Scenery").process_mode = Node.PROCESS_MODE_DISABLED
		(world.get_node("Scenery") as Node3D).visible = false
	var j: Node = world.get_node("Journey")
	j.set_physics_process(false)
	var player: Node = world.get_node("Player")
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.far = 9000
	cam.fov = 75
	world.add_child(cam)
	var vp_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	await _frames(30)
	player.get_node("HUD").visible = false
	cam.make_current()
	# Let the streaming world fill in.
	await _frames(400)
	print("## perf %s  %dx%d" % [label, w, h])
	print("view          frame_ms  gpu_ms  cpu_rnd  proc_ms  phys_ms  draws  objects  prims_k  vram_MB")
	for v: Array in VIEWS:
		if v[3]:
			j.call("warp_running", 4100.0)
			j.set_physics_process(true)
		else:
			j.call("warp_to_stop", 0)
			j.set_physics_process(false)
		cam.global_position = v[1]
		cam.look_at(v[2])
		await _frames(150)
		var n := 300
		var t0 := Time.get_ticks_usec()
		var gpu := 0.0
		var cpu := 0.0
		var proc := 0.0
		var phys := 0.0
		var draws := 0.0
		var objs := 0.0
		var prims := 0.0
		for i in n:
			await process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var frame := float(Time.get_ticks_usec() - t0) / 1000.0 / n
		var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		print("%-12s  %8.2f  %6.2f  %7.2f  %7.2f  %7.2f  %5d  %7d  %7.0f  %7.0f" % [v[0], frame, gpu / n, cpu / n,
				proc / n, phys / n, int(draws / n), int(objs / n), prims / n / 1000.0, vram])
	quit(0)

func _frames(n: int) -> void:
	for i in n:
		await process_frame
