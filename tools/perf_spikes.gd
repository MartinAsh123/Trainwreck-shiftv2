extends SceneTree
## Frame-time distribution while the train runs (streaming, smoke, passengers…): average, 95th and
## 99th percentile and worst frame, from a seat in the saloon looking out of the window.
##   godot --path . -s tools/perf_spikes.gd -- [width] [height] [seconds]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var w := int(args[0]) if args.size() > 0 else 1920
	var h := int(args[1]) if args.size() > 1 else 1080
	var secs := float(args[2]) if args.size() > 2 else 20.0
	DisplayServer.window_set_size(Vector2i(w, h))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var j: Node = world.get_node("Journey")
	var player: Node = world.get_node("Player")
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.far = 9000
	cam.fov = 75
	world.add_child(cam)
	for i in 30:
		await process_frame
	player.get_node("HUD").visible = false
	cam.make_current()
	cam.global_position = Vector3(-4.0, 2.9, 0.4)
	cam.look_at(Vector3(-6.0, 2.6, 6.0))
	for i in 300:
		await process_frame
	j.call("warp_running", 4100.0)
	for i in 120:
		await process_frame
	var times := PackedFloat32Array()
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	for t in times:
		sum += t
	var n := sorted.size()
	var over := 0
	for t in times:
		if t > 16.7:
			over += 1
	print("running %ds: frames %d  avg %.2f ms (%.0f fps)  p95 %.2f  p99 %.2f  max %.2f  frames>16.7ms %.1f%%" % [
			int(secs), n, sum / n, 1000.0 / (sum / n), sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1], 100.0 * over / n])
	quit(0)
