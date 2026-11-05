extends SceneTree
# A haunting from start to finish:  -- calm <coffee|newspaper|say|riddle>   |   -- break <ebrake|toilet|ac|computer>
# Timings shortened (controlled test); everything else runs as in play.
var world: Node3D
var h: HauntDirector
var pax: Passengers
var player: Node3D
func _wait(cond: Callable, cap: float, what: String) -> bool:
	var el := 0.0
	while el < cap:
		if cond.call():
			return true
		await process_frame
		el += root.get_process_delta_time()
	print("TIMEOUT waiting for ", what)
	return false

func _initialize() -> void:
	var mode: String = OS.get_cmdline_user_args()[0]
	var what: String = OS.get_cmdline_user_args()[1]
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	pax = world.get_node("Passengers")
	pax.trips_enabled = false
	h = get_first_node_in_group("haunt")
	var hd: HorrorDirector = get_first_node_in_group("horror")
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	var rec: ShiftRecord = get_first_node_in_group("shift_record")
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	world.get_node("Journey").call("warp_running", 6600.0 if what == "ebrake" else 2000.0)   # (the brake: a long stretch, so it is still at line speed when it goes)
	player = world.get_node("Player")
	h.first_start = 1.0
	h.reply_min = 2.0
	h.reply_max = 3.0
	h.deadline = 95.0 if mode == "break" else 900.0
	h.deadline_max = h.deadline
	h.moan_gap = Vector2(3, 5)
	await process_frame
	h._next_start = 1.0
	h._kinds_used = ["coffee", "newspaper", "say", "riddle"].filter(func(k): return k != what) if mode == "calm" else []
	if mode == "break":
		h._breaks_used = HauntDirector.BREAKS.filter(func(k): return k != what)
		# (No goods train: one due on the stretch ahead holds a breakdown back until it has passed.)
		get_first_node_in_group("passing_train").set("enabled", false)
	await _wait(func(): return h.stage == "signs", 20.0, "haunting")
	var g = h.ghost
	var t := PassengerTalk.of(g.body)
	var car: Node3D = h.car
	print("GHOST ", g.body.name, " '", t.full_name, "' in ", car.name, " wants ", h.kind, " ticket date ", t.ticket_date, " dest ", t.dest)
	player.global_position = Vector3(g.body.global_position.x - 1.0, 1.45, 0.0)
	var panel: Node = car.find_children("*", "StaffPanel", true, false)[0]
	var mode0: String = panel.get("mode")
	var said := {}
	var el := 0.0
	var flashes := 0
	while el < 62.0:
		await process_frame
		el += root.get_process_delta_time()
		for r in pax.riders():
			if r.car == car and r.body.is_speaking():
				said[r.body.name] = true
		if g.body.has_node("GhostFade"):
			flashes += 1
	print("SIGNS history ", h.history.map(func(x): return x[1]), " heating ", mode0, "->", panel.get("mode"), " passengers complaining ", said.size(), " flash frames ", flashes, " giggle/flicker done ", hd.history.size())
	# name
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	t.interact(player)
	await process_frame
	t._on_pick(t._keys.find("who"))
	t._end()
	print("NAMES known ", h.known_names().map(func(e): return e[0]))
	# the wrong name first
	var other = null
	for r in pax.riders():
		if r != g and r.state == Passengers.State.SEATED:
			other = r
			break
	PassengerTalk.of(other.body).known = true
	h.send_name(PassengerTalk.of(other.body).full_name)
	await _wait(func(): return TerminalData.messages.back().subject == "About %s" % PassengerTalk.of(other.body).full_name, 10.0, "wrong-name reply")
	print("WRONG NAME reply: ", str(TerminalData.messages.back().body).left(70), " told=", h.told)
	h.send_name(t.full_name)
	h.send_name(t.full_name)
	await _wait(func(): return h.told, 10.0, "Jim")
	print("VIKTOR: ", TerminalData.messages.back().body)
	if mode == "calm":
		match what:
			"coffee", "newspaper":
				t.interact(player)
				await process_frame
				print("before item options ", t._keys)
				t._end()
				h._items[what].interact(player)
				print("carrying ", Inventory.of(h).slots.map(func(it): return it.item if it else "-"))
				player.global_position = Vector3(g.body.global_position.x - 1.0, 1.45, 0.0)
				t.interact(player)
				await process_frame
				print("with item options ", t._keys)
				t._on_pick(t._keys.find("haunt_give"))
			"say":
				t.interact(player)
				await process_frame
				print("options ", t._keys)
				t._on_pick(t._keys.find("haunt_say"))
			"riddle":
				t.interact(player)
				await process_frame
				t._on_pick(t._keys.find("haunt_riddle"))
				print("riddle options ", t._keys, " q=", h._riddle.q)
				var wrong := (int(h._riddle.ok) + 1) % 3
				var left0 := h._left
				t._on_pick(t._keys.find("haunt_ans_%d" % wrong))
				print("wrong answer: time left ", left0, " -> ", h._left, " options ", t._keys)
				t._on_pick(t._keys.find("haunt_riddle"))
				t._on_pick(t._keys.find("haunt_ans_%d" % int(h._riddle.ok)))
	else:
		await _wait(func(): return h.incident != "", 60.0, "breakdown")
		print("BREAKDOWN ", h.incident, " message: ", TerminalData.messages.back().body, " rep ", rec.reputation)
		var w := func(n: String):
			for s in h._spots:
				if is_instance_valid(s) and s.name == n: return s
			return null
		match h.incident:
			"toilet":
				print("  wc blocked: errand refused=", not pax.start_errand(_seated(car), "wc"))
				var bowl = w.call("BlockedBowl")
				print("  ", bowl.get_prompt(), " / ", w.call("Puddle").get_prompt())
				print("  plunger at ", h._items["plunger"].global_position, " in ", h._items["plunger"].get_parent().name)
				h._items["plunger"].interact(player)
				for i in 3:
					print("  ", bowl.get_prompt(), " -> '", bowl.interact(player), "'")
			"ac":
				var hatch = w.call("HatchLatch")
				print("  ", hatch.get_prompt(), " heating ", panel.get("mode"))
				print("  without: '", hatch.interact(player), "' state ", h._job_state)
				h._items["screwdriver"].interact(player)
				print("  ", hatch.get_prompt())
				hatch.interact(player)
				await create_timer(1.0).timeout
				for c in ["red", "yellow", "black"]:
					var sp = w.call("Cable_" + c)
					print("  ", sp.get_prompt())
					sp.interact(player)
				print("  ", hatch.get_prompt())
				print("  -> ", hatch.interact(player), " heating ", panel.get("mode"))
			"ebrake":
				var brake = w.call("EmergencyBrake")
				var ts := root.get_node("TrainState")
				print("  speed ", snappedf(ts.speed, 0.1), " ", brake.get_prompt())
				await _wait(func(): return ts.speed < 0.05, 40.0, "train stopped")
				print("  stopped at ", snappedf(ts.distance, 1.0), " phase ", ts.phase, " ", brake.get_prompt())
				print("  -> '", brake.interact(player), "' ", brake.get_prompt())
				await _wait(func(): return h.incident == "", 8.0, "brake line")
				await create_timer(3.0).timeout
				print("  moving again: speed ", snappedf(ts.speed, 0.01), " emergency ", world.get_node("Journey").emergency)
			"computer":
				var term: ComputerTerminal = car.find_children("*", "ComputerTerminal", true, false)[0]
				print("  ", term.get_prompt(), " mode ", term.desktop.mode)
				print("  use without usb: '", term.interact(player), "'")
				h._items["usb"].interact(player)
				print("  ", term.get_prompt())
				term.interact(player)
				await create_timer(1.0).timeout
				print("  ", term.get_prompt())
				await _wait(func(): return h.incident == "", 12.0, "reinstall")
				print("  after: ", term.get_prompt(), " mode ", term.desktop.mode)
		print("FIXED incident='", h.incident, "' deadline reset ", h._left, " spots left ", h._spots.size(), " toolbar ", Inventory.of(h).slots.map(func(it): return it.item if it else "-"), " item back ", h._items.values().all(func(i): return i.visible))
		quit(0)
		return
	var seat: Dictionary = g.seat
	await _wait(func(): return not pax.riders().has(g), 10.0, "ghost gone")
	print("RESULT gone=", not pax.riders().has(g), " seat free=", not seat.taken, " heating ", panel.get("mode"), " stage ", h.stage, " rep ", rec.reputation, " horror enabled ", hd.enabled, " summary ", rec.summary().ghost_revealed.size(), "/", rec.summary().ghost_missed.size())
	quit(0)

func _seated(car: Node3D):
	for r in pax.riders():
		if r.car == car and r.state == Passengers.State.SEATED and not r.ghost:
			return r
