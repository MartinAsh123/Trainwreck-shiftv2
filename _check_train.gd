extends SceneTree
# Walks the whole train end to end (sleeper rear gangway door -> locomotive cab) and checks the
# sleeper's rooms and the railings on the gangways.
const Y0 := 1.4
func _initialize() -> void:
	root.size = Vector2i(640, 360)
	var world: Node3D = load("res://scenes/train/passenger_car_walk.tscn").instantiate()
	root.add_child(world)
	var sl: SleeperCar = world.get_node("Train/SleeperCar1")
	var crew: Node3D = world.get_node("Train/CrewCar4")
	var player: CharacterBody3D = world.get_node("Player")
	await process_frame
	await process_frame
	player.set_physics_process(false)
	var nd := 0
	for d in get_nodes_in_group("train_door"):
		if str(d.get("door_name")) == "W.C. door":
			continue
		d.call("set_open_immediate", true)
		nd += 1
	print("  opened %d doors" % nd)
	await physics_frame
	var o := sl.global_position.x
	var rooms := sl._rooms()
	var comp: Dictionary = rooms[2]
	var att: Dictionary = rooms[0]
	var az := sl._aisle_z()
	var cx: float = o + sl._room_door_x(comp)
	var ax: float = o + sl._room_door_x(att)
	var lo: float = world.get_node("Train/Locomotive6").global_position.x
	# Through the train along X, at each car's aisle line; z is adjusted by the steering.
	var path: Array = [Vector2(o + sl._half_len() - 0.5, 0.0), Vector2(o + sl._partition_x(1.0) + 0.5, az),
			Vector2(o + sl._partition_x(-1.0) - 0.5, az), Vector2(8.77, 0.0), Vector2(-8.77, 0.0), Vector2(-26.31, 0.0)]
	var cz: float = crew.call("_aisle_z")
	path += [Vector2(crew.global_position.x + crew.call("_partition_x", 1.0) + 0.5, cz),
			Vector2(crew.global_position.x + crew.call("_partition_x", -1.0) - 0.5, cz), Vector2(-43.85, 0.0),
			Vector2(-46.97 + 0.7, 0.06), Vector2(-46.97 - 0.7, 0.06), Vector2(-52.62 + 3.0, -0.3), Vector2(-52.62 - 5.0, 0.0), Vector2(-61.39, 0.0), Vector2(lo - 8.9, 0.0), Vector2(lo - 10.4, -0.3)]
	var routes := {
		"whole train: sleeper end -> cars 2, 3, 4, 5 -> locomotive cab": path,
		"sleeper corridor -> compartment": [Vector2(cx, az), Vector2(cx, 0.3), Vector2(cx, 0.9)],
		"sleeper corridor -> service room -> window corners": [Vector2(ax, az), Vector2(ax, 0.2),
			Vector2(o + (att.x0 + att.x1) * 0.5, 0.6), Vector2(o + att.x0 + 0.65, 0.7), Vector2(o + att.x1 - 0.65, 0.7)],
		"sleeper corridor -> toilet": [Vector2(cx, az), Vector2(o + sl._partition_x(1.0) + 0.5, az),
			Vector2(o + sl._toilet_door_x(), sl._corridor_z()), Vector2(o + sl._toilet_door_x(), sl._toilet_room_z())],
	}
	for d in get_nodes_in_group("train_door"):
		if str(d.get("door_name")) == "W.C. door" and sl.is_ancestor_of(d):
			d.call("set_open_immediate", true)
	await physics_frame
	for route_name in routes:
		print(("  OK: " if await _walk(player, routes[route_name]) else "  BLOCKED: ") + route_name)
	for gx in [8.77, -8.77, -26.31, -43.85, -61.39]:
		for zs in [-1.0, 1.0]:
			player.global_position = Vector3(gx, Y0 + 0.02, 0.0)
			player.velocity = Vector3.ZERO
			for f in 120:
				player.velocity = Vector3(0, 0.0 if player.is_on_floor() else player.velocity.y - 0.16, zs * 3.0)
				player.move_and_slide()
				await physics_frame
			var p := player.global_position
			if absf(p.z) > 0.7 or p.y < Y0 - 0.1:
				print("  FELL OFF gangway at x %.2f" % gx)
	print("  gangway railings checked")
	quit(0)

func _walk(player: CharacterBody3D, pts: Array) -> bool:
	player.global_position = Vector3(pts[0].x, Y0 + 0.02, pts[0].y)
	player.velocity = Vector3.ZERO
	for i in range(1, pts.size()):
		var target: Vector2 = pts[i]
		var reached := false
		for f in 900:
			var p := Vector2(player.global_position.x, player.global_position.z)
			if p.distance_to(target) < 0.15:
				reached = true
				break
			var d := (target - p).normalized() * 3.0
			player.velocity = Vector3(d.x, 0.0 if player.is_on_floor() else player.velocity.y - 0.16, d.y)
			player.move_and_slide()
			await physics_frame
		if not reached or player.global_position.y < Y0 - 0.2:
			print("    stuck/fell at ", player.global_position.snappedf(0.01), " heading to ", target)
			return false
	return true
