extends SceneTree
# The whole night's pacing, fast: the real journey from the first station to the end of the line at
# `speed` times real time, with a stand-in Kevin who does the minimum (no walking, no camera work):
# he answers the wake-up calls before their stops, finds one anomaly out early on and stays near it,
# lays the first and third ghosts to rest after a while and lets the second one break something,
# which he then puts right. Prints the night's timeline (HorrorDirector.timeline: minute -> event)
# and the longest stretch with nothing in it.
#   godot --headless --path . --fixed-fps 30 -s tools/_test_pacing.gd -- [seed] [speed]
# Prints "PACING max gap <s>" and "PACING OK" when no gap is over MAX_GAP.

const MAX_GAP := 190.0                     # real seconds

var world: Node3D
var ts: Node
var hd: HorrorDirector
var h: HauntDirector
var chores: Chores
var board: TaskBoard
var ws: WakeScare
var af: AnomalyFrenzy
var pt: PassingTrain
var pax: Passengers
var player: Node3D
var _t0 := -1.0                            # director time at departure
var dread_seen: Array = []                 # minute:dread level/phase

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 11
	var speed := float(args[1]) if args.size() > 1 else 4.0
	create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
		print("PACING FAIL: watchdog (25 minutes of wall time)")
		quit(1))
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	while ws == null:
		await process_frame
		ws = get_first_node_in_group("wake_scare")
	ws.chance = 1.0                        # (the wrong sleeper is aboard tonight: before its own setup runs)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	ts = root.get_node("TrainState")
	hd = get_first_node_in_group("horror")
	h = get_first_node_in_group("haunt")
	chores = get_first_node_in_group("chores")
	board = get_first_node_in_group("task_board")
	af = get_first_node_in_group("anomaly_frenzy")
	pt = get_first_node_in_group("passing_train")
	pax = world.get_node("Passengers")
	player = world.get_node("Player")
	hd._rng.seed = seed
	hd.log_skips = true
	h._rng.seed = seed + 1
	chores._rng.seed = seed + 2
	af.violent_chance = 1.0                # (the one he finds out turns on him...)
	af.wait_for_guard = 0.0                # (...when the night lets it)
	player.global_position = Vector3(-1.0, 1.45, 0.0)
	print("sections ", pt.sections, " wake scare: ", ws.rider.body.name if ws.rider else "-", " to ", ws.rider.dest if ws.rider else "-")
	print("calls ", chores._wake.values())
	Engine.time_scale = speed
	await _night()
	Engine.time_scale = 1.0
	_report()
	quit()

func _now() -> float:
	return hd._time - _t0

func _night() -> void:
	var exposed = null
	var ghost_seen := {}                   # haunting number -> director time it began
	var dread_t := 0.0
	var fixed_at := -1.0
	while true:
		await process_frame
		if _t0 < 0.0 and str(ts.get("phase")) == "running":
			_t0 = hd._time
			hd.mark("departure", "route")
		if _t0 < 0.0:
			continue
		var now := _now()
		# The dread bed (GameAudio, if it is there) once a minute.
		if now - dread_t > 60.0:
			dread_t = now
			dread_seen.append("%d:%.2f/%s" % [int(now / 60.0), GameAudio.dread_level(), hd.phase])
		# The routine orders done in good time (they are not what this is about).
		for t: TaskBoard.Task in board.open_tasks():
			if t.kind == "routine" and not t.id.begins_with("wake_") and board.time_left(t) < 30.0:
				board.complete(t.id)
		# Wake-up calls: before the stop, as the train runs in.
		for pid in chores._wake.keys():
			var r = pax.rider_by_pid(pid)
			if r and r.state == Passengers.State.SLEEPING and str(ts.get("next_stop")) == chores._wake[pid][1] \
					and float(ts.get("to_next_stop")) < 2200.0 and str(ts.get("phase")) == "running":
				player.global_position = r.body.global_position + Vector3(0, 0.3, 0.9)
				pax.wake_by_player(r)
		# One anomaly found out at 2.5 minutes: he stays by it (it goes when the night lets it).
		if exposed == null and now > 150.0:
			for r in pax.riders():
				if r.anomaly != "" and not r.ghost and r.state == Passengers.State.SEATED:
					exposed = r
					var talk := PassengerTalk.of(r.body)
					talk.seen["ticket"] = true
					talk.seen["well"] = true
					hd.mark("Kevin finds out %s" % r.body.name, "player")
					break
		if exposed != null and af.stage in ["", "armed"] and pax.riders().has(exposed) and ws._t < 0.0:
			var b: Node3D = exposed.body
			if is_instance_valid(b) and player.global_position.distance_to(b.global_position) > 3.0:
				player.global_position = b.global_position + Vector3(0.9, 0.3, 0.0)
		# The ghosts: the first and third laid to rest after a while, the second left to break something.
		if h.stage == "signs" and h.ghost != null:
			if not ghost_seen.has(h.count):
				ghost_seen[h.count] = hd._time
			var age: float = hd._time - float(ghost_seen[h.count])
			var rest_after: float = {1: 200.0, 2: 9999.0, 3: 150.0}.get(h.count, 150.0)
			if age > rest_after and h.incident == "":
				var g = h.ghost
				hd.mark("Kevin lays ghost %d to rest" % h.count, "player")
				h._end_haunting(true)
				pax.reveal_ghost(g, "calmed")
		if h.incident != "" and fixed_at < 0.0:
			fixed_at = hd._time + 70.0
		if fixed_at > 0.0 and hd._time > fixed_at:
			fixed_at = -1.0
			if h.incident != "":
				hd.mark("Kevin puts it right", "player")
				if h.incident == "ebrake":
					h._throw_brake(false)
					world.get_node("Journey").set("emergency", false)
				h._incident_done()
				if h.count == 2 and h.ghost != null:
					var g = h.ghost
					h._end_haunting(true)
					pax.reveal_ghost(g, "calmed")
		if str(ts.get("phase")) == "stopped" and str(ts.get("station")) == str(RouteData.stops().back().name):
			hd.mark("end of the line", "route")
			return
		if now > 1500.0:
			print("TIMEOUT: still running at ", TerminalData.clock_text())
			return

func _report() -> void:
	print("TIMELINE (real minutes from departure)")
	var times: Array = []
	for e: Array in hd.timeline:
		var at := float(e[0]) - _t0
		if at < -1.0:
			continue
		var kind: String = e[2]
		var tier: String = e[3]
		print("  %5.2f  %s  %-14s %s" % [at / 60.0, e[1], tier, kind])
		# What counts as something happening: a sign, a scare, the ghost, a request, a fault, a call.
		if tier.begins_with("sign") or tier.begins_with("big") or kind.begins_with("haunting") or kind.begins_with("fault") \
				or kind.begins_with("order: Coffee") or kind.begins_with("order: Something") or kind.begins_with("order: Put right") \
				or kind.contains("Wake-up") or tier == "route":
			times.append(at)
	times.sort()
	var worst := 0.0
	var worst_at := 0.0
	for i in range(1, times.size()):
		if times[i] - times[i - 1] > worst:
			worst = times[i] - times[i - 1]
			worst_at = times[i - 1]
	var bigs := hd.timeline.filter(func(e): return str(e[3]).begins_with("big"))
	print("PACING bigs %d: %s" % [bigs.size(), bigs.map(func(e): return "%.1f %s" % [(float(e[0]) - _t0) / 60.0, e[2]])])
	print("PACING signs %d, goods trains %d, hauntings %d, frenzy %s" % [hd.timeline.filter(func(e): return str(e[3]).begins_with("sign")).size(),
			pt.count, h.count, af.log_lines])
	print("PACING dread bed (minute:level/phase) ", dread_seen)
	print("PACING max gap %.0f s (after minute %.2f)" % [worst, worst_at / 60.0])
	var close := 0
	for i in range(1, bigs.size()):
		if float(bigs[i][0]) - float(bigs[i - 1][0]) < 120.0 and not str(bigs[i][3]).contains("player"):
			close += 1
	print("PACING bigs closer than 2 min (not player-set): %d" % close)
	print("PACING OK" if worst <= MAX_GAP and close == 0 else "PACING FAIL")
