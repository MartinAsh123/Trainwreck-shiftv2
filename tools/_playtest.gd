extends SceneTree
# The whole journey, nothing forced: errands, Mike's day, stops (alighting at own destinations,
# boarding), the scheduled scares. Runs at `speed` x real time and logs what happens.
#   godot --path . -s tools/_playtest.gd -- [speed=4] [minutes_cap=12]
var world: Node3D
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var speed := float(args[0]) if args.size() > 0 else 4.0
	var cap_min := float(args[1]) if args.size() > 1 else 12.0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var ts := root.get_node("TrainState")
	var pax: Passengers = world.get_node("Passengers")
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	var hd: HorrorDirector = get_first_node_in_group("horror")
	var rec: ShiftRecord = get_first_node_in_group("shift_record")
	hd.seed_value = 7
	var player: Node3D = world.get_node("Player")
	player.global_position = Vector3(-31.0, 1.45, 0.6)   # Kevin in his room, out of everyone's way
	Engine.time_scale = speed
	var last_states := {}
	var counts := {"errands": 0, "errands_done": 0, "alight": 0, "board": 0, "yield": 0, "mover_failed": 0}
	var last_mike := ""
	var last_phase := ""
	var wall0 := Time.get_ticks_msec()
	var frames := 0
	var slow := 0
	var last_t := Time.get_ticks_usec()
	var ptn0 = get_first_node_in_group("passing_train")
	var pstate := [""]
	hd.event_started.connect(func(k, f): print("%s HORROR %s%s" % [TerminalData.clock_text(), k, " (forced)" if f else " (scheduled)"]))
	while Time.get_ticks_msec() - wall0 < cap_min * 60000.0 and not rec.finished:
		await process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		if now - last_t > 33333: slow += 1
		last_t = now
		if ptn0.state != pstate[0]:
			pstate[0] = ptn0.state
			print("%s PASSING %s (figures %d) player at %s" % [TerminalData.clock_text(), ptn0.state, ptn0._figures.size(), player.global_position.snapped(Vector3.ONE * 0.1)])
		if str(ts.phase) != last_phase:
			last_phase = str(ts.phase)
			print("%s TRAIN %s %s" % [TerminalData.clock_text(), last_phase, ts.station if ts.station != "" else ts.next_stop])
		var mj := duty.job
		if mj != last_mike:
			last_mike = mj
			print("%s MIKE %s" % [TerminalData.clock_text(), mj])
		for r in pax.riders():
			var st: String = Passengers.State.keys()[r.state]
			var prev: String = last_states.get(r.pid, "")
			if st != prev:
				last_states[r.pid] = st
				if st == "ERRAND": counts.errands += 1; print("%s  errand start %s (%s)" % [TerminalData.clock_text(), r.body.name, r.errand])
				if prev == "ERRAND" and st == "SEATED": counts.errands_done += 1; print("%s  errand back %s" % [TerminalData.clock_text(), r.body.name])
				if st == "ALIGHTING": counts.alight += 1
				if st == "BOARDING": counts.board += 1
				if st == "PREPARING": print("%s  preparing to leave %s for %s" % [TerminalData.clock_text(), r.body.name, pax._dest(r)])
			if r.mover and r.mover.state == "yield" and not r.has_meta("y"):
				r.set_meta("y", true); counts.yield += 1; print("%s  yield %s" % [TerminalData.clock_text(), r.body.name])
			elif r.mover and r.mover.state != "yield" and r.has_meta("y"):
				r.remove_meta("y")
	Engine.time_scale = 1.0
	var wall := (Time.get_ticks_msec() - wall0) / 1000.0
	print("END clock %s finished=%s wall %.0fs frames %d (%.0f fps at x%.0f) frames>33ms %d" % [TerminalData.clock_text(), rec.finished, wall, frames, frames / wall, speed, slow])
	print("COUNTS ", counts)
	print("MIKE ", duty.log_lines)
	print("HORROR ", hd.history)
	print("GHOST stage ", get_first_node_in_group("ghost_story").stage)
	print("HAUNT ", get_first_node_in_group("haunt").history)
	var ptn = get_first_node_in_group("passing_train")
	print("PASSING ", ptn.history, " events ", ptn.count, " sections ", ptn.sections)
	print("REP ", rec.reputation, " summary sizes ", rec.summary().resolved.size(), "/", rec.summary().unresolved.size(), "/", rec.summary().not_checked.size())
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png("C:/Users/marti/AppData/Local/Temp/claude/A--Trainwreck-ShiftV2/f101d24e-3f93-42ca-aaee-c6355cbfddfa/scratchpad/summary.png")
	quit(0)
