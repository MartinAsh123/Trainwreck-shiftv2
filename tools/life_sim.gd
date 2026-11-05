extends SceneTree
## Runs the journey through a level crossing (godot --path . -s tools/life_sim.gd): measures WorldLife's per-frame cost and logs the
## barrier and the cars on that road (one line per second).
func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var life: Node = world.get_node("WorldLife")
	life.process_mode = Node.PROCESS_MODE_DISABLED
	var j: Node = world.get_node("Journey")
	await process_frame
	var ts: Node = root.get_node("TrainState")
	var cr: Dictionary = RoadNetwork.crossings()[1]
	j.call("warp_running", float(cr.s) - 900.0)
	# Cars on the crossing road, both directions, approaching.
	var r: Dictionary = RoadNetwork.roads()[cr.road]
	var cars: Array = life._cars
	for k in 3:
		var c = cars[k]
		c.road = cr.road
		c.t = float(r.cross_t) + (-120.0 - k * 25.0 if k < 2 else 140.0)
		c.dir = 1.0 if k < 2 else -1.0
		c.v = 8.0
		c.parked = 0.0
		c.node.visible = true
	var total := 0
	var n := 0
	var worst := 0
	for f in 2400:
		await process_frame
		var t0 := Time.get_ticks_usec()
		life._process(get_root().get_process_delta_time() if false else 1.0 / 60.0)
		var dt := Time.get_ticks_usec() - t0
		if f > 300:
			total += dt
			n += 1
			worst = maxi(worst, dt)
		if f % 60 == 0:
			var d: float = ts.get("distance")
			var s := "t=%2ds train_front-crossing=%6.0f arm=%.2f" % [f / 60, d + 84.0 - float(cr.s), life._arm_angle.get(1, 1.45)]
			for k in 3:
				var c = cars[k]
				s += " | car%d t-cross=%6.1f v=%4.1f" % [k, (c.t - float(r.cross_t)) * c.dir, c.v]
			print(s)
	print("WorldLife _process: avg %.3f ms, worst %.3f ms" % [total / 1000.0 / n, worst / 1000.0])
	quit()
