extends SceneTree
## Boarding test: the player walks at an open side door of the first coach from the track side (no
## platform, up the hung step and the footboard) and from the platform side, and must end up on the
## car floor. Run: godot --headless --path . -s _check_boarding.gd

func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	world.get_node("Journey").set_physics_process(false)
	await _frames(30)
	var player := world.get_node("Player") as CharacterBody3D
	var ok := true
	for car_name in ["PassengerCar", "SleeperCar1", "PassengerCar3", "CrewCar4", "MailVan5"]:
		var car := world.get_node("Train/" + car_name) as Node3D
		ok = await _board(car, player) and ok
	print("BOARDING ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)

func _board(car: Node3D, player: CharacterBody3D) -> bool:
	var dx: float = car.call("_side_door_x")
	var floor_y := car.global_position.y
	var ok := true
	for z_side: float in [-1.0, 1.0]:
		# Open the side door on this side.
		for d: Node in car.find_children("*", "TrainDoor", true, false):
			var p := car.to_local((d as Node3D).global_position)
			if absf(p.x - dx) < 1.0 and signf(p.z) == z_side:
				d.call("set_open_immediate", true)
		var start := car.to_global(Vector3(dx, 0, z_side * 3.6))
		start.y = 1.0
		player.global_position = start
		player.velocity = Vector3.ZERO
		player.rotation = Vector3(0, 0.0 if z_side > 0.0 else PI, 0)     # face the car
		await _frames(40)                  # settle on whatever is below
		var y0 := player.global_position.y
		var under := ""
		for k in player.get_slide_collision_count():
			under += str((player.get_slide_collision(k).get_collider() as Node).name) + " "
		Input.action_press("fp_forward")
		var inside := false
		for i in 240:
			await physics_frame
			var lp := car.to_local(player.global_position)
			if absf(lp.z) < 1.2 and absf(player.global_position.y - floor_y) < 0.15:
				inside = true
				break
			if not inside and i == 239 and OS.has_environment("BOARD_DEBUG"):
				for k in player.get_slide_collision_count():
					var c := player.get_slide_collision(k)
					print("   hit ", (c.get_collider() as Node).get_path(), " n ", c.get_normal(), " at ", car.to_local(c.get_position()))
		Input.action_release("fp_forward")
		await _frames(10)
		var pz := car.to_local(player.global_position).z
		print("%s side %+d: start y %.2f on [%s] -> y %.2f (floor %.2f), car z %.2f  %s" % [car.name, int(z_side), y0, under,
				player.global_position.y, floor_y, pz, "OK" if inside else "FAIL"])
		ok = ok and inside
	return ok

func _frames(n: int) -> void:
	for i in n:
		await process_frame
