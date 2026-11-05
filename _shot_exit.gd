extends SceneTree
const SD := "C:/Users/marti/AppData/Local/Temp/claude/C--Users-marti-AppData-Roaming-Claude-scratch-workspaces-3e58b957-222a-49cc-a358-7d825abce1af-88de5f8e-6168-4768-8e06-65da1c67b280-scratch-2026-09-26-7f055c/f101d24e-3f93-42ca-aaee-c6355cbfddfa/scratchpad/"
func _initialize() -> void:
	root.size = Vector2i(1100, 640)
	var world: Node3D = load("res://scenes/train/passenger_car_walk.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var player: FPController = world.get_node("Player")
	player.set_physics_process(false)
	var car: Node3D = world.get_node("Train/PassengerCar")
	var exits: Array = []
	for d in car.find_children("*", "TrainDoor", true, false):
		print(d.get_path(), " name=", d.door_name, " kind=", d.kind, " hinge=", snappedf(d.hinge_angle, 0.01), " pos=", d.global_position.snappedf(0.01))
		if d.door_name == "exit door":
			exits.append(d)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 75
	cam.make_current()
	for i in 1:
		var d: TrainDoor = exits[i]
		var m: Node3D = d.get_parent()
		var out := -m.global_basis.z
		cam.global_position = m.global_position - out * 2.3 + Vector3(0, 1.7, 0)
		cam.look_at(m.global_position + Vector3(0, 1.1, 0))
		await _f(5)
		await _save("ex_%d_closed.png" % i)
		print("door ", d.transform, " lean ", car.call("_lean_at", 2.0))
		cam.global_position = m.global_position + Vector3(0, 4.5, 0) - out * 0.3
		cam.look_at(m.global_position + Vector3(0, 0, 0) + out * 0.3, Vector3(1, 0, 0))
		await _f(5)
		await _save("ex_%d_top_closed.png" % i)
		d.set_open_immediate(true)
		await _f(8)
		await _save("ex_%d_top_open.png" % i)
		cam.global_position = m.global_position - out * 2.3 + Vector3(0, 1.7, 0)
		cam.look_at(m.global_position + Vector3(0, 1.1, 0))
		await _f(5)
		await _save("ex_%d_open.png" % i)
		cam.global_position = m.global_position - out * 1.2 + Vector3(0, 1.6, 0) + m.global_basis.x * 0.9
		cam.look_at(m.global_position + Vector3(0, 1.2, 0))
		await _f(5)
		await _save("ex_%d_jamb.png" % i)
		cam.global_position = m.global_position + out * 2.5 + Vector3(0, 1.4, 0) + m.global_basis.x * 1.5
		cam.look_at(m.global_position + Vector3(0, 1.1, 0))
		await _f(5)
		await _save("ex_%d_open_out.png" % i)
	quit(0)
func _f(n): 
	for i in n: await process_frame
func _save(f: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SD + f)
