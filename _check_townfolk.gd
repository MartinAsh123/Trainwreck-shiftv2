extends SceneTree
## Townsfolk test: at every village and town along the line, how many people are there once it is
## loaded; then the player walks at a standing figure and must be stopped by it.
## Run: godot --path . -s _check_townfolk.gd   (windowed: the models load as in the game)

func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	world.get_node("Journey").set_physics_process(false)
	await _frames(20)
	var ts := root.get_node("TrainState")
	var scenery := world.get_node("Scenery")
	var ok := true
	var stand: Node3D = null
	for pl: Dictionary in ([] if OS.has_environment("COLLISION_ONLY") else RoadNetwork.places()):
		ts.set("distance", float(pl.s) - 40.0)
		var found := 0
		var want := 38
		for wait in 40:                      # up to ~20 s: big towns build and load a while
			await _frames(30)
			found = 0
			for f: Node in scenery.get_children():
				if f.has_meta("life_center") and (f.get_meta("life_center") as Vector2).distance_to(Vector2(pl.s, pl.z)) < 1.0:
					for ch: Node in f.get_children():
						if ch.has_meta("townfolk"):
							found += 1
			if found >= want:
				break
		var good := found >= want
		ok = ok and good
		var folk = world.get_node("WorldLife")._folk
		print("%-16s %-7s people %2d  %s   (queue %d, live %d)" % [pl.name, "town" if pl.town else "village", found, "OK" if good else "FEW",
				folk._queue.size(), folk._people.size()])
	# Collision: the player walks straight at a standing figure and must stop short of it.
	var folk = world.get_node("WorldLife")._folk
	# Go to Dobřany and take one of its people onto the platform (the only walkable ground).
	var st: Dictionary = RouteData.STATIONS[2]
	ts.set("distance", float(st.s) - 29.0)
	await _frames(400)
	var target: Node3D = null
	for p in folk._people:
		if not p.walking and is_instance_valid(p.node):
			target = p.node
			break
	var player := world.get_node("Player") as CharacterBody3D
	if target:
		target.global_position = Vector3(-15.0, 0.55, float(st.side) * 4.4)
		target.global_basis = Basis(Vector3.UP, PI * 0.5)
		await _frames(5)
		var fwd := target.global_basis.z.normalized()
		player.global_position = target.global_position + fwd * 3.0 + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.look_at(Vector3(target.global_position.x, player.global_position.y, target.global_position.z))
		player.rotation.x = 0
		player.rotation.z = 0
		await _frames(30)
		Input.action_press("fp_forward")
		for i in 180:
			await physics_frame
		Input.action_release("fp_forward")
		var d := Vector2(player.global_position.x - target.global_position.x, player.global_position.z - target.global_position.z).length()
		var blocked := d > 0.4
		print("player stopped %.2f m from the figure: %s" % [d, "OK" if blocked else "WALKED THROUGH"])
		ok = ok and blocked
	print("TOWNFOLK ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)

func _frames(n: int) -> void:
	for i in n:
		await process_frame
