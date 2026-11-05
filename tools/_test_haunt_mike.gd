extends SceneTree
# A ghost reported to Mike: he walks over, his hand goes through it, it stays; the report closes.
func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = false
	var h: HauntDirector = get_first_node_in_group("haunt")
	h.first_start = 1.0
	h.deadline = 900.0
	h._next_start = 1.0
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	var det: Detention = get_first_node_in_group("detention")
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	world.get_node("Journey").call("warp_running", 2000.0)
	world.get_node("Player").global_position = Vector3(-31.0, 1.45, 0.6)
	while h.stage != "signs":
		await process_frame
	var g = h.ghost
	PassengerTalk.of(g.body).seen["ticket"] = true
	print("report -> ", det.report(g))
	var el := 0.0
	var seen_ghost := false
	while el < 120.0:
		await process_frame
		el += root.get_process_delta_time()
		if duty.phase == "ghost": seen_ghost = true
		if seen_ghost and duty.job == "room":
			break
	print("RESULT mike reached it=", seen_ghost, " ghost still here=", pax.riders().has(g), " state=", Passengers.State.keys()[g.state], " active=", det.active_pid, " held=", det.held.size(), " stage=", h.stage, " t=%.1f" % el)
	print("MIKE ", duty.log_lines)
	quit(0)
