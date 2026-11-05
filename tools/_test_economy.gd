extends SceneTree
# The money and the work, in the real journey scene:  -- <out_dir | -> [parts]
# parts (comma list, default all): tasks,berth,wake,coffee,cage,scare,scare_ghost,day,nextday
# With an out_dir (run it windowed) it saves pictures of the HUD, the scare and the pay slip there.
var world: Node3D
var pax: Passengers
var player: Node3D
var eco: Economy
var board: TaskBoard
var chores: Chores
var inv: Inventory
var rec: ShiftRecord
var out := "-"
var fails := 0

func _wait(cond: Callable, cap: float, what: String) -> bool:
	var el := 0.0
	while el < cap:
		if cond.call():
			return true
		await process_frame
		el += root.get_process_delta_time()
	print("TIMEOUT waiting for ", what)
	return false

func _sleep(s: float) -> void:
	var el := 0.0
	while el < s:
		await process_frame
		el += root.get_process_delta_time()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func _shot(n: String) -> void:
	if out == "-":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(n + ".png"))

# The player standing at `at` (floor), his eye on `look`.
func _face(at: Vector3, look: Vector3) -> void:
	player.global_position = Vector3(at.x, at.y if at.y > 1.0 else 1.4, at.z)
	var eye: Vector3 = player.get_node("Head").global_position
	var d := look - eye
	player.rotation = Vector3(0, atan2(-d.x, -d.z), 0)
	player.get_node("Head").rotation.x = atan2(d.y, Vector2(d.x, d.z).length())

func _state(id: String) -> String:
	var t := board.get_task(id)
	return t.state if t else "none"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "-"
	var parts: Array = (args[1] if args.size() > 1 else "tasks,berth,wake,coffee,cage,scare,day").split(",")
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	pax = world.get_node("Passengers")
	pax.trips_enabled = false
	player = world.get_node("Player")
	eco = get_first_node_in_group("economy")
	board = get_first_node_in_group("task_board")
	chores = get_first_node_in_group("chores")
	inv = get_first_node_in_group("inventory")
	rec = get_first_node_in_group("shift_record")
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	var h: HauntDirector = get_first_node_in_group("haunt")
	if h:
		h.enabled = false
	chores.special_first = 9999.0
	chores._special_t = 9999.0
	await _sleep(1.5)
	print("TASKS ", board.tasks.map(func(t): return "%s [%s] due %s" % [t.id, t.where, TaskBoard.hhmm(t.due)]))
	await _shot("hud_start")
	if "tasks" in parts:
		await _tasks()
	if "berth" in parts:
		await _berth()
	if "coffee" in parts:
		await _coffee()
	if "cage" in parts:
		await _cage()
	if "scare" in parts:
		await _scare("anomaly")
	if "scare_ghost" in parts:
		await _scare("ghost")
	if "wake" in parts:
		await _wake()
	if "day" in parts:
		await _day()
	print("LEDGER ", eco.lines.map(func(l): return "%s %s" % [l.text, Economy.money(l.amount)]))
	print("BALANCE ", Economy.money(eco.balance()), " today ", Economy.money(eco.today()), " | fails ", fails)
	if "nextday" in parts and "day" in parts:
		var was := eco.balance()
		eco.start_next_day()
		await _sleep(3.0)
		var e2: Economy = get_first_node_in_group("economy")
		_check(e2 != null and e2 != eco and e2.day == 2 and e2.wallet == was and e2.today() == 0, "next day: day %d, wallet %s carried" % [e2.day if e2 else -1, Economy.money(e2.wallet if e2 else 0)])
		print("SAVE ", FileAccess.get_file_as_string(Economy.SAVE))
	print("FAILS ", fails)
	quit()

func _tasks() -> void:
	var train := world.find_child("Train", true, false)
	for cn in ["PassengerCar", "PassengerCar3"]:
		for p: Node in train.get_node(cn).find_children("*", "StaffPanel", true, false):
			p.call("press", "mode:HEAT")
	for p: Node in train.get_node("SleeperCar1").find_children("*", "StaffPanel", true, false):
		p.call("_on_toggle", false, "MAIN")
		p.call("_on_toggle", true, "NIGHT")
	await _sleep(0.6)
	_check(_state("heating") == "done", "heating on: paid")
	_check(_state("night") == "done", "night lights: paid")
	# Tickets: the train leaves the first station, then every ticket in coach two is asked for.
	world.get_node("Journey").call("warp_running", 300.0)
	pax._on_departing("")
	chores._on_departing("")
	await _sleep(0.4)
	var t := board.get_task("tickets_PassengerCar")
	_check(t != null, "ticket order for coach two")
	if t:
		for r in pax.riders():
			if r.car and String(r.car.name) == "PassengerCar":
				PassengerTalk.of(r.body).seen["ticket"] = true
		await _sleep(0.6)
		_check(t.state == "done", "coach two tickets: paid")

func _berth() -> void:
	var job: BerthJob = chores.berths[0]
	print("BERTH ", job.berth, " prompt: ", job._prompt())
	_face(job.global_position + Vector3(0, 0, -1.25), job.global_position + Vector3(0, 0.55, 0))
	await _sleep(0.3)
	await _shot("berth_dirty")
	_check(inv.take(job.waste) == "", "waste picked up")
	print("  after waste: ", job._prompt())
	job._use()
	_check(job.stripped and inv.has_item("dirty_linen"), "stripped, the bundle in hand")
	await _shot("berth_bare")
	print("  after strip: ", job._prompt())
	var brush: HauntItem = chores.find_child("Item_brush", true, false)
	_check(brush != null and inv.take(brush) == "", "brush taken")
	job._use()
	job._use()
	print("  after scrub: ", job._prompt())
	chores._take_linen()
	_check(inv.has_item("linen"), "clean linen taken")
	print("  toolbar: ", inv.slots.map(func(it): return it.item if it else "-"))
	await _shot("hud_toolbar")
	job._use()
	_check(job.made and not inv.has_item("linen"), "berth made")
	await _sleep(0.5)
	_check(_state("berth_" + job.berth) == "done", "berth order paid")
	await _shot("berth_made")
	inv.consume("waste")
	inv.consume("dirty_linen")
	inv.use("brush")
	_check(inv.count() == 0, "toolbar empty again")

func _coffee() -> void:
	chores._coffee_request()
	var id := ""
	for k in chores._coffee:
		id = chores._coffee[k]
	var r = pax.rider_by_pid(int(id.trim_prefix("coffee_")))
	_check(r != null and board.get_task(id) != null, "coffee asked for")
	var cup: HauntItem = world.find_child("Item_coffee", true, false)
	if cup == null:
		print("  (no coffee cup in the scene)")
		return
	inv.take(cup)
	var t := PassengerTalk.of(r.body)
	print("  options: ", chores.talk_options(t))
	print("  answer: ", chores.talk_pick(t, "chore_coffee"))
	await _sleep(0.4)
	_check(_state(id) == "done" and not inv.has_item("coffee"), "coffee brought: paid, the cup back on the desk")

func _cage() -> void:
	var cage: HoldingCage = get_first_node_in_group("holding_cage")
	var det: Detention = get_first_node_in_group("detention")
	var cand := pax.anomalies().filter(func(r): return r.state == Passengers.State.SEATED)
	if cand.is_empty():
		print("  (no anomaly seated)")
		return
	var r = cand[0]
	pax.take_for_escort(r)
	pax.free_seat_of(r)
	pax.set_detained(r)
	cage.take_place(0, r.pid)
	r.body.global_transform = cage.place_xf(0)
	r.body.sit_now()
	det.held[r.pid] = {"place": 0, "verify_at": 99.0, "checked": false}
	rec.entry_for(r).held = true
	var key: HauntItem = cage.find_child("Item_key", true, false)
	_check(key != null, "the cage key lies on the safe")
	inv.take(key)
	cage._key_use()
	_check(cage.kevin_opened and not cage.is_secured(), "Kevin unlocked the cage")
	player.global_position = cage.gate_middle() + Vector3(-12.0, -0.6, 0)
	await _wait(func(): return not det.held.has(r.pid), cage.escape_after + 3.0, "the escape")
	var e: Dictionary = rec.entries[r.pid]
	var alias := rec.entries.values().filter(func(x): return x.alias_of == r.pid)
	_check(e.escaped and not pax.riders().has(r) and alias.size() == 1, "escaped, riding on as %s" % (alias[0].slug if alias else "?"))
	player.global_position = cage.gate_middle() + Vector3(1.0, -0.6, -0.6)
	cage._key_use()
	await _wait(cage.is_secured, 6.0, "the cage locked")
	_check(cage.is_secured(), "locked again")
	inv.use("key")

func _scare(kind: String) -> void:
	var ws: WakeScare = get_first_node_in_group("wake_scare")
	var can := pax.riders().filter(func(r): return r.state == Passengers.State.SLEEPING and not r.body.has_meta("wake_call"))
	if can.is_empty():
		print("  (no sleeper for the scare)")
		return
	var r = can[0]
	if ws.rider and ws.rider != r:
		ws.rider.body.remove_meta("wake_scare")
	ws.sprung = false
	ws.pick(r, kind)
	# Standing in the compartment, looking down at the berth.
	var door := pax._compartment_door(r)
	var at: Vector3 = (door as Node3D).global_position if door else r.bed.global_position
	var pillow: Vector3 = r.bed.global_transform * Vector3(0, SleepBlanket.MATTRESS + 0.15, 0.45)
	_face(Vector3(at.x, 1.4, at.z + 0.75), pillow)
	await _sleep(1.5)
	await _shot("scare_before")
	print("SPRING %s frame %d" % [kind, Engine.get_process_frames()])
	pax.wake_by_player(r)
	var shots := 0
	var el := 0.0
	while el < 2.4:
		await process_frame
		el += root.get_process_delta_time()
		if el > ws.calm + ws.rise * 0.8 + shots * 0.12 and shots < 4:
			await _shot("scare_%d" % shots)
			shots += 1
	_check(not pax.riders().has(r), "the thing in the berth is gone (%s)" % kind)
	await _sleep(1.5)

func _wake() -> void:
	var names: Array = RouteData.stops().map(func(s): return str(s.name))
	var calls: Array = pax.riders().filter(func(r): return r.body.has_meta("wake_call"))
	calls.sort_custom(func(a, b): return names.find(a.dest) < names.find(b.dest))
	if calls.size() < 2:
		print("  (only %d wake-up calls)" % calls.size())
		return
	var j := world.get_node("Journey")
	var off := float(j.get("stop_offset"))
	# The first: woken on the way in to its stop.
	var a = calls[0]
	var sa: Dictionary = RouteData.stops()[names.find(a.dest)]
	j.call("warp_running", float(sa.s) + off - 700.0)
	pax._on_departing("")
	await process_frame
	pax.wake_by_player(a)
	_check(a.state == Passengers.State.WAKING and a.body.has_meta("hold_wake"), "woken before %s, sitting up to wait" % a.dest)
	await _sleep(0.5)
	_check(_state("wake_%d" % a.pid) == "done", "wake-up call made: paid")
	await _wait(func(): return a.state == Passengers.State.ALIGHTING or not pax.riders().has(a), 90.0, "off at the stop")
	_check(a.state == Passengers.State.ALIGHTING or not pax.riders().has(a), "it got off at its stop")
	# The second: never woken.
	var b = calls[1]
	var sb: Dictionary = RouteData.stops()[names.find(b.dest)]
	var was: String = b.dest
	j.call("warp_running", float(sb.s) + off - 500.0)
	pax._on_departing("")
	await _wait(func(): return str(root.get_node("TrainState").get("station")) == was, 90.0, "arriving at " + was)
	await _sleep(0.6)
	_check(_state("wake_%d" % b.pid) == "missed" and b.state == Passengers.State.SLEEPING and b.dest != was, "no wake-up call: slept through %s, missed" % was)

func _day() -> void:
	var j := world.get_node("Journey")
	j.call("warp_to_stop", RouteData.stops().size() - 1)
	await _sleep(0.5)
	_check(rec.shift_over, "end of the line: shift over")
	var eod: EndOfDay = world.find_child("EndOfDay", true, false)
	print("  bed prompt: ", eod._prompt())
	eod.turn_in()
	await _wait(func(): return eod.find_child("ShiftSummary", true, false) != null, 5.0, "the summary")
	_check(eco.closed and eco.booked("wage"), "day closed, base pay in")
	await _sleep(0.3)
	await _shot("pay_slip")
