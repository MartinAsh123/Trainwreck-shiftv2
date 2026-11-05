extends SceneTree
# Mike's day, compressed: a patrol, a nap (woken by a report), station duty at a stop.
func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = false
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var j: Node = world.get_node("Journey")
	# The patrol (~2 min) needs open line ahead: since the halved timetable the first stop came
	# 20 s after s=2000 and station duty cut it short. Start just past the stop with the longest
	# run to the next one (VRCHOVINA -> SNĚŽNÁ, 5.2 km, ~2.5 min to the braking point).
	var stops := RouteData.stops()
	var gap_i := 0
	for i in stops.size() - 1:
		if float(stops[i + 1].s) - float(stops[i].s) > float(stops[gap_i + 1].s) - float(stops[gap_i].s):
			gap_i = i
	j.call("warp_running", float(stops[gap_i].s) + 300.0)
	world.get_node("Player").global_position = Vector3(-31.0, 1.45, 0.6)
	var ts := root.get_node("TrainState")
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	var det: Detention = get_first_node_in_group("detention")
	for i in 20: await process_frame
	# 1. patrol now
	duty.next_patrol = ts.clock
	var el := 0.0
	var seen := {}
	while el < 200.0:
		await process_frame
		el += root.get_process_delta_time()
		var k: String = duty.job + "/" + duty.phase
		if not seen.has(k):
			seen[k] = true
			print("%6.1f %s pos %s clock %s" % [el, k, duty.mike.global_position.snapped(Vector3.ONE * 0.1), TerminalData.clock_text()])
		if duty.log_lines.size() > 0 and duty.log_lines.back().ends_with("patrol done") and duty.job == "room" and duty.phase == "there":
			break
	print("PATROL ", "done" if duty.log_lines.any(func(l): return l.ends_with("patrol done")) else "NOT DONE", " in ", el)
	# 2. nap: allowed now, short; a report wakes him
	duty.rest_start = ts.clock - 0.01
	duty.rest_latest = ts.clock + 1.0
	duty.rest_minutes = 4.0
	duty.next_patrol = 99.0
	j.call("warp_running", 2000.0)
	el = 0.0
	seen.clear()
	var reported := false
	while el < 120.0:
		await process_frame
		el += root.get_process_delta_time()
		var k: String = duty.job + "/" + duty.phase
		if not seen.has(k):
			seen[k] = true
			print("%6.1f %s pos %s asleep %s" % [el, k, duty.mike.global_position.snapped(Vector3.ONE * 0.1), duty.mike.asleep])
		if duty.phase == "sleep" and duty._t > 3.0 and not reported:
			reported = true
			# A report while he sleeps: the dialogue only offers to wake him; a pending report also wakes him.
			var t: PassengerTalk = null
			for r in pax.riders():
				if r.state == Passengers.State.SEATED:
					t = PassengerTalk.of(r.body)
					t.seen["ticket"] = true
					print("REPORT while asleep -> ", det.report(r))
					break
		if reported and duty.job == "escort":
			print("escort started after waking, rested=", duty.rested)
			break
	# 3. station duty: brake into the next stop
	duty.job = "room"
	duty.phase = ""
	det.pending_pid = -1
	det.active_pid = -1
	j.call("warp_running", float(RouteData.stops()[1].s) - 29.0 - 600.0)
	el = 0.0
	seen.clear()
	while el < 120.0:
		await process_frame
		el += root.get_process_delta_time()
		var k: String = duty.job + "/" + duty.phase + " " + str(ts.phase)
		if not seen.has(k):
			seen[k] = true
			print("%6.1f %s pos %s" % [el, k, duty.mike.global_position.snapped(Vector3.ONE * 0.1)])
	print("MIKE LOG ", duty.log_lines)
	quit(0)
