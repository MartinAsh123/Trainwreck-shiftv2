extends SceneTree
## Performance baseline: four fixed spots of the real journey, then a streaming run at line speed.
##   godot --path . --resolution 1920x1080 -s tools/_perf_baseline.gd -- [out.md|-] [stream_seconds=90]
## Windowed (headless drops mesh data), vsync off, no fps cap. Each spot: 240 warm-up frames,
## then 600 measured frames. Per spot it prints avg fps, 1%-low fps (mean of the slowest 1% of
## frames), frame ms (avg / p99 / max), GPU and CPU-render ms, process and physics ms, draw calls,
## primitives, objects, lights with shadows on, static memory, video memory and orphan nodes.
## The streaming run starts on the open line and records every frame over 33 ms (hitch) with where
## the train was and how many nodes entered the tree in that frame.
## The horror director is switched off for the spots (a scare would spoil the numbers); everything
## else runs as in play.

const WARM := 240
const MEASURE := 600
const HITCH_MS := 33.3

# name, stop index (-1: running at s), s, camera, look-at, weather
const SPOTS := [
	["open_line", -1, 4100.0, Vector3(-4.0, 2.9, 0.4), Vector3(-6.0, 2.6, 6.0), ""],
	["station_stop", 1, 0.0, Vector3(-4.0, 2.9, 0.4), Vector3(-6.0, 2.6, 6.0), ""],
	["town", 5, 0.0, Vector3(-30.0, 5.0, 4.0), Vector3(-60.0, 4.0, 60.0), ""],
	["night_storm", -1, 16000.0, Vector3(-4.0, 2.9, 0.4), Vector3(-6.0, 2.6, 6.0), "blizzard"],
]

var world: Node3D
var vp_rid: RID
var _added := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "-"
	var stream_secs := float(args[1]) if args.size() > 1 else 90.0
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	node_added.connect(func(_n: Node) -> void: _added += 1)
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var j: Node = world.get_node("Journey")
	var ts: Node = root.get_node("TrainState")
	var player: Node3D = world.get_node("Player")
	var cam := Camera3D.new()
	cam.far = 9000
	cam.fov = 75
	world.add_child(cam)
	vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var hd: HorrorDirector = get_first_node_in_group("horror")
	if hd:
		hd.enabled = false
	player.global_position = Vector3(-31.0, 1.45, 0.6)   # Kevin in his room, out of everyone's way
	player.set_physics_process(false)
	var hud := player.get_node_or_null("HUD")
	if hud:
		hud.visible = false
	cam.make_current()
	var weather := world.find_child("Weather", true, false)
	await _frames(400)
	var lines: Array[String] = []
	var sz := root.get_visible_rect().size
	lines.append("## perf baseline  %s  viewport %dx%d  %s  %s" % [Time.get_datetime_string_from_system(), sz.x, sz.y,
			RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()])
	lines.append("")
	lines.append("| spot | avg fps | 1% low | frame ms | p99 ms | max ms | gpu ms | cpu rnd ms | proc ms | phys ms | draws | prims k | objects | shadowed | static MB | vram MB | orphans | nodes |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for sp: Array in SPOTS:
		if weather and sp[5] != "":
			weather.call("set_state", sp[5], true)
		if sp[1] < 0:
			j.call("warp_running", sp[2])
		else:
			j.call("warp_to_stop", sp[1])
		cam.global_position = sp[3]
		cam.look_at(sp[4])
		await _frames(WARM)
		var row := await _measure(sp[0])
		lines.append(row)
		print(row)
		if weather and sp[5] != "":
			weather.call("set_state", "light_snow", true)
	# Streaming at line speed: what the world costs while it builds itself ahead of the train.
	lines.append("")
	lines.append("### streaming at %.0f m/s for %.0f s (from s=800, saloon window view)" % [float(j.get("line_speed")), stream_secs])
	j.call("warp_to_stop", 0)
	await _frames(120)
	j.call("warp_running", 800.0)
	cam.global_position = SPOTS[0][3]
	cam.look_at(SPOTS[0][4])
	await _frames(180)                                         # (the warp itself rebuilds the world)
	var times := PackedFloat32Array()
	var hitches: Array[String] = []
	var t_start := Time.get_ticks_msec()
	var t_end := t_start + int(stream_secs * 1000.0)
	var last := Time.get_ticks_usec()
	var s0 := float(ts.get("distance"))
	var orph0 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	_added = 0
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		times.append(ms)
		if ms > HITCH_MS:
			var s := float(ts.get("distance"))
			var near: Dictionary = RouteData.station_at(s)
			hitches.append("| %.1f | %.1f | %.0f | %s | %d | %.1f | %.1f |" % [ms, float(Time.get_ticks_msec() - t_start) / 1000.0, s,
					str(near.get("name", "-")), _added, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
		_added = 0
	var st := _stats(times)
	lines.append("")
	lines.append("frames %d, ran %.0f m (s %.0f -> %.0f), avg %.2f ms (%.0f fps), 1%%-low %.0f fps, p99 %.2f ms, max %.1f ms, hitches >33 ms: %d, frames >16.7 ms: %d" % [
			times.size(), float(ts.get("distance")) - s0, s0, float(ts.get("distance")), st.avg, 1000.0 / st.avg, st.low1,
			st.p99, st.max, hitches.size(), st.over16])
	lines.append("orphan nodes %d -> %d, static memory %.0f -> %.0f MB" % [orph0,
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), mem0 / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	if not hitches.is_empty():
		lines.append("")
		lines.append("| hitch ms | t (s) | s (m) | station near | nodes added | proc ms | phys ms |")
		lines.append("|---|---|---|---|---|---|---|")
		for h in hitches.slice(0, 60):
			lines.append(h)
	var text := "\n".join(lines)
	print(text)
	if out_path != "-":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(text + "\n")
		f.close()
	quit(0)

func _measure(label: String) -> String:
	var times := PackedFloat32Array()
	var gpu := 0.0
	var cpu := 0.0
	var proc := 0.0
	var phys := 0.0
	var draws := 0.0
	var objs := 0.0
	var prims := 0.0
	var last := Time.get_ticks_usec()
	for i in MEASURE:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var st := _stats(times)
	var n := float(MEASURE)
	return "| %s | %.0f | %.0f | %.2f | %.2f | %.1f | %.2f | %.2f | %.2f | %.2f | %d | %.0f | %d | %s | %.0f | %.0f | %d | %d |" % [
			label, 1000.0 / st.avg, st.low1, st.avg, st.p99, st.max, gpu / n, cpu / n, proc / n, phys / n,
			int(draws / n), prims / n / 1000.0, int(objs / n), _shadowed(),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]

## "omni+spot / directional" lights casting shadows right now (visible ones only).
func _shadowed() -> String:
	var local := 0
	var dir := 0
	for n: Node in root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l.shadow_enabled and l.is_visible_in_tree():
			if l is DirectionalLight3D:
				dir += 1
			else:
				local += 1
	return "%d+%dd" % [local, dir]

func _stats(times: PackedFloat32Array) -> Dictionary:
	var sorted := times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	var over := 0
	for t in times:
		sum += t
		if t > 16.7:
			over += 1
	var k := maxi(n / 100, 1)
	var worst := 0.0
	for i in k:
		worst += sorted[n - 1 - i]
	return {"avg": sum / n, "p99": sorted[int(n * 0.99)], "max": sorted[n - 1], "low1": 1000.0 / (worst / k), "over16": over}

func _frames(n: int) -> void:
	for i in n:
		await process_frame
