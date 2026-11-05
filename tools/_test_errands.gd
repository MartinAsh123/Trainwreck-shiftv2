extends SceneTree
# Forces errands and watches them: states, teleports (>0.1 m in a frame), standing in solid cells.
var world: Node3D
func _initialize() -> void:
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = true
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	world.get_node("Journey").call("warp_running", 2000.0)
	for i in 30: await process_frame
	var ts := root.get_node("TrainState")
	print("to_next_stop ", ts.to_next_stop, " phase ", ts.phase)
	pax.trip_chance = 0.0          # only the forced ones
	if not OS.get_cmdline_user_args().has("player_stays"):
		world.get_node("Player").global_position = Vector3(-37.0, 1.45, -1.0)
	var space := world.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.1
	cap.height = 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	var sent := []
	for r in pax.riders():
		if r.state == Passengers.State.SEATED and sent.size() < 4:
			var kind := "wc" if sent.size() % 2 == 0 else "window"
			if pax.start_errand(r, kind):
				sent.append(r)
				print("sent ", r.body.name, " ", kind, " car ", r.car.name)
	for d in world.find_child("Train").find_children("*", "TrainDoor", true, false):
		if d.kind == TrainDoor.Kind.HINGE and not d.lock_while_moving:
			var dd: TrainDoor = d
			dd.refused.connect(func(why): 
				var who := []
				for r in sent: who.append([r.body.name.substr(10, 8), r.body.global_position.snapped(Vector3.ONE*0.05)])
				print("REFUSED ", dd.get_parent().get_parent().get_parent().get_parent().name, " hinge ", dd.global_position, " ", why, " ", who))
	var last := {}
	var jumps := 0
	var clip := 0
	var t := 0.0
	var log_t := 0.0
	while t < 150.0:
		await process_frame
		var dt := 1.0 / 60.0
		t += Engine.get_main_loop().root.get_process_delta_time()
		for r in sent:
			var p: Vector3 = r.body.global_position
			var dtp: float = Engine.get_main_loop().root.get_process_delta_time()
			if last.has(r) and p.distance_to(last[r]) > maxf(0.06, 1.3 * dtp * 1.2):
				jumps += 1
				print("JUMP ", r.body.name, " ", last[r], " -> ", p, " state ", r.state, " ", r.errand_phase)
			last[r] = p
			if r.state == Passengers.State.ERRAND and r.body._sit < 0.05:
				q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.6 + 0.45, 0))
				for h in space.intersect_shape(q, 4):
					if not (h.collider as Node).is_in_group("npc_solid") and not (h.collider is TrainDoor) and not (h.collider is CharacterBody3D):
						clip += 1
						if clip % 30 == 1:
							print("CLIP ", r.body.name, " at ", p, " vs ", (h.collider as Node).get_path())
						break
		log_t -= Engine.get_main_loop().root.get_process_delta_time()
		if log_t <= 0.0:
			log_t = 5.0
			var line := "t=%5.1f " % t
			for r in sent:
				line += "| %s %s/%s %s %s " % [r.body.name.substr(10, 12), Passengers.State.keys()[r.state], r.errand_phase, r.mover.state if r.mover else "-", r.body.global_position.snapped(Vector3.ONE * 0.1)]
			print(line)
		var done := true
		for r in sent:
			if r.state != Passengers.State.SEATED: done = false
		if done and t > 5.0:
			print("ALL BACK at t=", t)
			break
	print("jumps ", jumps, " clip_frames ", clip)
	quit(0)
