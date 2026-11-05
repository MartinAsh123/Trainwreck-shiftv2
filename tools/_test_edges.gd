extends SceneTree
# Edge cases: full cage, a report cancelled in the dialogue, a stop during an escort (the suspect's
# own stop), a blocked route (escort called off, passenger back to its seat, gate locked).
var world: Node3D
func _initialize() -> void:
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var j: Node = world.get_node("Journey")
	var ts := root.get_node("TrainState")
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = false
	var det: Detention = get_first_node_in_group("detention")
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	var cage: HoldingCage = get_first_node_in_group("holding_cage")
	var hd: HorrorDirector = get_first_node_in_group("horror")
	hd.enabled = false
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	var player: Node3D = world.get_node("Player")
	j.call("warp_running", 2000.0)
	player.global_position = Vector3(-31.0, 1.45, 0.6)
	for i in 20: await process_frame
	var seated := pax.riders().filter(func(r): return r.state == Passengers.State.SEATED)
	for r in seated: PassengerTalk.of(r.body).seen["ticket"] = true
	# a) full cage
	for i in cage.capacity(): cage.take_place(i, 9000 + i)
	print("A full cage -> ", det.report(seated[0]))
	for i in cage.capacity(): cage.leave_place(9000 + i)
	# b) cancelled in the dialogue: open Mike's talk, pick 'report', then 'Never mind'
	var talk: StaffTalk = duty.mike.get_node("Talk")
	player.global_position = duty.mike.global_position + Vector3(0.0, 0.05, -0.9)
	talk.interact(player)
	await process_frame
	var ri := -1
	for i in talk._opts.size():
		if talk._opts[i][1] == "report_pick": ri = i
	talk._on_pick(ri)
	print("B report list shown: mode=", talk._mode, " entries=", talk._report_list.size())
	talk._on_pick(talk._report_list.size())        # Never mind
	print("B after 'Never mind': pending=", det.pending_pid, " mode=", talk._mode)
	talk._on_pick(ri)
	DialogueMenu.close_for(talk)                    # Esc in the middle of choosing
	for i in 5: await process_frame
	print("B after Esc: pending=", det.pending_pid, " mode=", talk._mode, " in_talk=", duty.mike.has_meta("in_talk"))
	player.global_position = Vector3(-31.0, 1.45, 0.6)
	# c) a stop during the escort - the suspect's own stop
	var nxt_i := 1
	var stops := RouteData.stops()
	var target = null
	for r in seated:
		if String(r.car.name) == "PassengerCar":
			target = r
			break
	PassengerTalk.of(target.body).dest = str(stops[nxt_i].name)
	j.call("warp_running", float(stops[nxt_i].s) - 29.0 - 2600.0)
	print("C report -> ", det.report(target).ok, " suspect dest ", stops[nxt_i].name)
	var el := 0.0
	var saw_alight := false
	var phases := {}
	while el < 300.0:
		await process_frame
		el += root.get_process_delta_time()
		if target.state == Passengers.State.ALIGHTING: saw_alight = true
		var k := "%s/%s train=%s" % [duty.job, duty.phase, ts.phase]
		if not phases.has(k):
			phases[k] = true
			print("   %5.1f %s suspect %s" % [el, k, Passengers.State.keys()[target.state]])
		if det.held.has(target.pid) and duty.job != "escort":
			break
	print("C held=", det.held.has(target.pid), " suspect ever alighting=", saw_alight, " missed=", get_first_node_in_group("shift_record").entries[target.pid].missed)
	# d) blocked route: Kevin stands in the gangway ahead of Mike during the lead
	j.call("warp_running", 2000.0)
	for i in 30: await process_frame
	var t2 = null
	for r in pax.riders():
		if r.state == Passengers.State.SEATED and String(r.car.name) == "PassengerCar3" and not det.held.has(r.pid):
			PassengerTalk.of(r.body).seen["ticket"] = true
			t2 = r
			break
	print("D report -> ", det.report(t2).ok)
	el = 0.0
	var blocked_at := -1.0
	while el < 200.0:
		await process_frame
		el += root.get_process_delta_time()
		if duty.phase == "lead" and blocked_at < 0.0:
			blocked_at = el
			player.global_position = Vector3(-26.3, 1.45, 0.0)   # in the gangway between coach 3 and the crew car
			player.set_physics_process(false)
		if blocked_at > 0.0 and duty.job != "escort":
			break
	print("D after %.1f s blocked: mike job=%s, suspect=%s, gate secured=%s" % [el - blocked_at, duty.job, Passengers.State.keys()[t2.state], cage.is_secured()])
	player.global_position = Vector3(-31.0, 1.45, 0.6)
	el = 0.0
	while el < 60.0 and t2.state != Passengers.State.SEATED:
		await process_frame
		el += root.get_process_delta_time()
	print("D suspect back in seat: ", t2.state == Passengers.State.SEATED, " at ", t2.body.global_position.snapped(Vector3.ONE*0.01), " seat ", pax.seat_xf(t2).origin.snapped(Vector3.ONE*0.01))
	print("LOG\n", TerminalData.log_text)
	quit(0)
