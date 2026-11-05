extends SceneTree
const SD := "C:/Users/marti/AppData/Local/Temp/claude/C--Users-marti-AppData-Roaming-Claude-scratch-workspaces-3e58b957-222a-49cc-a358-7d825abce1af-88de5f8e-6168-4768-8e06-65da1c67b280-scratch-2026-09-26-7f055c/f101d24e-3f93-42ca-aaee-c6355cbfddfa/scratchpad/"
var cam: Camera3D
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var j: Journey = world.get_node("Journey")
	j.set_physics_process(false)
	var player = world.get_node("Player")
	player.set_physics_process(false)
	cam = Camera3D.new()
	cam.far = 9000
	world.add_child(cam)
	cam.make_current()
	await process_frame
	player.get_node("HUD").visible = false
	var t0 := Time.get_ticks_msec()
	await _frames(400)
	print("live after 400 frames: ", world.get_node("Scenery")._live.size(), " pending ", world.get_node("Scenery")._pending.size(), " ms ", Time.get_ticks_msec() - t0)
	await _shot(Vector3(15, 14, 45), Vector3(-29, 2, 0), 55, "j_station_wide.png")
	await _shot(Vector3(-55, 1.9, 3.6), Vector3(-25, 2.4, 10), 65, "j_platform.png")
	await _shot(Vector3(-15, 1.9, 4.2), Vector3(-45, 2.0, 3.0), 65, "j_platform2.png")
	await _shot(Vector3(-29, 6, 70), Vector3(-29, 3, 10), 50, "j_station_front.png")
	await _shot(Vector3(-7.0, 2.95, -0.5), Vector3(-7.0, 2.6, 10), 70, "j_window.png")
	await _shot(Vector3(-130, 40, -120), Vector3(-29, 0, 0), 55, "j_aerial.png")
	j.warp_running(4100.0)
	await _frames(300)
	print("fps ", Engine.get_frames_per_second())
	await _shot(Vector3(-30, 4, -13), Vector3(-50, 2, 0), 60, "j_run_side.png")
	await _shot(Vector3(-71.2, 3.3, 0.85), Vector3(-200, 2.4, 1.2), 70, "j_cab.png")
	var w: Weather = world.get_node("Weather")
	w.set_state("blizzard", true)
	await _frames(60)
	await _shot(Vector3(-30, 4, -13), Vector3(-50, 2, 0), 60, "j_blizzard.png")
	w.set_state("clear", true)
	await _frames(60)
	await _shot(Vector3(-130, 40, -120), Vector3(-29, 0, 0), 55, "j_clear_aerial.png")
	j.warp_to_stop(2)
	await _frames(240)
	await _shot(Vector3(-55, 1.9, -3.6), Vector3(-25, 2.4, -10), 65, "j_vrchovina.png")
	quit(0)
func _shot(p: Vector3, at: Vector3, fov: float, f: String) -> void:
	cam.global_position = p
	cam.look_at(at)
	cam.fov = fov
	await _frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SD + f)
func _frames(n: int) -> void:
	for i in n:
		await process_frame
