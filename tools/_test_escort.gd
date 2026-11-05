extends SceneTree
# Report -> Mike walks over -> escort -> cage locked -> papers checked -> (wrongful: release back to seat).
#   -- anomaly|normal [car]
var world: Node3D
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var want_anom := args.size() == 0 or args[0] == "anomaly"
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = false
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	world.get_node("Journey").call("warp_running", 2000.0)
	world.get_node("Player").global_position = Vector3(-31.0, 1.45, 0.6)   # Kevin's room, out of the way
	for i in 30: await process_frame
	var det: Detention = get_first_node_in_group("detention")
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	var cage: HoldingCage = get_first_node_in_group("holding_cage")
	det.verify_minutes = 0.6
	NpcMover.debug = true
	duty.next_patrol = 99.0
	print("cage capacity ", cage.capacity())
	var target = null
	for r in pax.riders():
		if r.state == Passengers.State.SEATED and (r.anomaly != "") == want_anom and String(r.car.name) == (args[1] if args.size() > 1 else "PassengerCar"):
			target = r
			break
	if target == null:
		for r in pax.riders():
			if r.state == Passengers.State.SEATED and (r.anomaly != "") == want_anom:
				target = r
				break
	var t := PassengerTalk.of(target.body)
	t.seen["ticket"] = true
	t.seen["who"] = true
	print("target ", target.body.name, " anomaly=", target.anomaly, " car ", target.car.name, " evidence ", t.evidence())
	print("reportable ", det.reportable().size())
	var res := det.report(target)
	print("REPORT -> ", res)
	print("DUPLICATE -> ", det.report(target))
	var space := world.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.1
	cap.height = 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	var el := 0.0
	var log_t := 0.0
	var last := {}
	var jumps := 0
	var clips := 0
	var released := false
	while el < 400.0:
		await process_frame
		var dt: float = root.get_process_delta_time()
		el += dt
		for b in [duty.mike, target.body]:
			var p: Vector3 = b.global_position
			if last.has(b) and p.distance_to(last[b]) > maxf(0.08, dt * 1.6):
				jumps += 1
				print("JUMP ", b.name, " ", last[b], " -> ", p, " job ", duty.job, "/", duty.phase)
			last[b] = p
			if b._sit < 0.05 and not b.asleep:
				q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.05, 0))
				for h in space.intersect_shape(q, 4):
					var c: Node = h.collider
					if not c.is_in_group("npc_solid") and not (c is TrainDoor) and not (c is CharacterBody3D):
						clips += 1
						if clips % 40 == 1: print("CLIP ", b.name, " ", p, " ", c.get_path())
						break
		log_t -= dt
		if log_t <= 0.0:
			log_t = 4.0
			print("t=%5.1f mike %s/%s %s | target %s %s | gate open=%s locked=%s" % [el, duty.job, duty.phase, duty.mike.global_position.snapped(Vector3.ONE*0.1),
					Passengers.State.keys()[target.state], target.body.global_position.snapped(Vector3.ONE*0.1), cage.gate.is_open(), cage.gate.always_locked])
		if det.held.has(target.pid) and det.held[target.pid].checked and want_anom and duty.job == "room":
			break
		var rec0: ShiftRecord = get_first_node_in_group("shift_record")
		if not want_anom and rec0.entries.has(target.pid) and rec0.entries[target.pid].released and duty.job == "room":
			released = true
			break
	var rec: ShiftRecord = get_first_node_in_group("shift_record")
	print("RESULT held=", det.held.keys(), " released=", released, " status=", rec.entries[target.pid].status, " rep=", rec.reputation, " secured=", cage.is_secured(), " jumps=", jumps, " clips=", clips)
	print("MIKE LOG ", duty.log_lines)
	print("LOG\n", TerminalData.log_text)
	quit(0)
