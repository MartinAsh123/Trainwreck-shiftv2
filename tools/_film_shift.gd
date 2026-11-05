extends SceneTree
# A whole shift played by Kevin on his own, filmed in first person (Movie Maker):
#   godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie <raw.avi> -s tools/_film_shift.gd
# He walks the train with the keys (W pressed, turning toward the way ahead, doors opened as he comes
# to them) and works through the night: the heating, every ticket in both coaches, the sleeping car's
# night lights, a berth made up, a suspicious passenger reported to Mike, the wake-up calls before
# their stops, the ghost (its name, Jim on the private line, what it needs), a coffee asked for,
# and at the end of the line his bed and the pay slip. He knows more than a player would (who the
# ghost is, which one is an anomaly) - this is a demonstration, not a solver. Prints "MARK <frame>
# <clock> <what>" for the edit.

const WALK_LOOK := 0.28                    # how near a turn of the way he comes before steering for the next

var world: Node3D
var pax: Passengers
var player: CharacterBody3D
var head: Node3D
var nav: TrainNav
var ts: Node
var h: HauntDirector
var chores: Chores
var board: TaskBoard
var inv: Inventory
var rec: ShiftRecord
var hd: HorrorDirector
var af: AnomalyFrenzy
var ws: WakeScare
var train: Node3D
var rng := RandomNumberGenerator.new()
var _urgent_busy := false
var _ghost_step := 0                       # 0 not seen to, 1 name sent, 2 laid to rest (per haunting)
var _ghost_n := 0                          # the haunting that step belongs to
var _coffee_done := {}
var _scared := false
var _reported := false
var _coffee_asked := false

func _initialize() -> void:
	rng.seed = 7
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	pax = world.get_node("Passengers")
	player = world.get_node("Player")
	head = player.get_node("Head")
	ts = root.get_node("TrainState")
	h = get_first_node_in_group("haunt")
	chores = get_first_node_in_group("chores")
	board = get_first_node_in_group("task_board")
	inv = get_first_node_in_group("inventory")
	rec = get_first_node_in_group("shift_record")
	hd = get_first_node_in_group("horror")
	af = get_first_node_in_group("anomaly_frenzy")
	ws = get_first_node_in_group("wake_scare")
	train = world.find_child("Train", true, false)
	chores._special_t = 1e9                       # (the requests come when the film wants them)
	pax.max_wandering = 1                         # (one out of their seat at a time: the aisle stays passable)
	# A slimmer body than a player's, so he keeps to the staff's walking grid between the seats.
	var cap := (player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
	cap.radius = 0.16
	await _sleep(2.0)
	_mark("start")
	await _shift()
	_mark("end")
	print("ORDERS ", board.tasks.map(func(t): return "%s=%s" % [t.id, t.state]))
	print("LEDGER ", Economy.of(world).lines.map(func(l): return "%s %s" % [l.text, Economy.money(l.amount)]))
	print("HAUNTS ", h.history.map(func(x): return "%s %s" % [x[0], x[1]]))
	print("REPORTED ", rec.entries.values().filter(func(e): return e.reported).map(func(e): return "%s: %s" % [e.name, e.status]))
	print("MIKE ", (get_first_node_in_group("mike_duty") as MikeDuty).log_lines)
	quit()

func _mark(what: String) -> void:
	print("MARK %d %s %s" % [Engine.get_process_frames(), TerminalData.clock_text(), what])

func _sleep(s: float) -> void:
	var el := 0.0
	while el < s:
		await physics_frame
		el += 1.0 / Engine.physics_ticks_per_second

func _run_t() -> float:
	return Engine.get_process_frames() / 30.0

# ————— the night —————

func _shift() -> void:
	# The berth that is not what it seems: the sleeper riding furthest (still asleep when he gets to it).
	var names: Array = RouteData.stops().map(func(s): return str(s.name))
	var far: Array = pax.riders().filter(func(r): return r.state == Passengers.State.SLEEPING and not r.body.has_meta("wake_call"))
	far.sort_custom(func(a, b): return names.find(a.dest) > names.find(b.dest))
	if not far.is_empty():
		if ws.rider and ws.rider != far[0]:
			ws.rider.body.remove_meta("wake_scare")
		ws.pick(far[0], "anomaly")
	await _heating("PassengerCar")
	await _tickets("PassengerCar")
	await _heating("PassengerCar3")
	await _tickets("PassengerCar3")
	await _night_lights()
	await _berth()
	while not rec.shift_over:
		await _urgent()
		if not _reported and (get_first_node_in_group("mike_duty") as MikeDuty).job == "room":
			await _report()
		if not _coffee_asked and _run_t() > 560.0:
			_coffee_asked = true
			chores._coffee_request()
			continue
		if not _scared and _run_t() > 640.0:
			await _wake_scare()
			continue
		await _stroll()
	await _urgent()
	await _turn_in()

# Whatever can't wait: a scare under way (stand and take it), a wake-up call before its stop, the
# ghost, a coffee asked for, a breakdown.
func _urgent() -> void:
	if _urgent_busy:
		return
	_urgent_busy = true
	await _hold_for_scares()
	for pid in chores._wake:
		var r = pax.rider_by_pid(pid)
		var stop: String = chores._wake[pid][1]
		if r and r.state == Passengers.State.SLEEPING and not r.body.has_meta("woken") \
				and str(ts.get("next_stop")) == stop and str(ts.get("phase")) in ["running", "braking"]:
			await _wake(r)
	if h.count != _ghost_n:
		_ghost_n = h.count
		_ghost_step = 0
	if h.stage == "signs" and h.ghost != null:
		if _ghost_step == 0 and h.known:
			await _ghost_name()
		elif _ghost_step == 1 and h.told:
			await _ghost_rest()
	if h.incident != "":
		await _fix()
	for pid in chores._coffee:
		var t := board.get_task(chores._coffee[pid])
		if t and t.state in ["open", "missed"] and not _coffee_done.has(pid):
			_coffee_done[pid] = true
			await _coffee(pax.rider_by_pid(pid))
	_urgent_busy = false

func _hold_for_scares() -> void:
	while hd.hold or not (af.stage in ["", "armed"]):
		Input.action_release("fp_forward")
		await _sleep(0.2)

# ————— walking —————

## Walks to the nearest free spot to `to` (the staff's walking grid), the doors opened on the way.
func _go(to: Vector3) -> bool:
	await _urgent()
	var c := nav.nearest_free(to, false, 1.2)
	if c.x < 0:
		_mark("no spot near %s" % str(to))
		return false
	var goal := nav.cell_pos(c)
	var path := nav.path(player.global_position, goal, false)
	if path.size() < 2:
		return player.global_position.distance_to(goal) < 0.4
	var doors := nav.doors_on(path)
	var i := 1
	var stuck := 0.0
	var last := player.global_position
	var waited := 0.0
	var best := INF
	var since_best := 0.0
	var spent := 0.0
	var length := 0.0
	for k in range(1, path.size()):
		length += path[k].distance_to(path[k - 1])
	var allowed := length / 1.2 + 15.0
	while true:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		if hd.hold or not (af.stage in ["", "armed"]):
			Input.action_release("fp_forward")
			continue
		var p := player.global_position
		# Along the way: the point a little ahead that he steers for.
		while i < path.size() - 1 and Vector2(path[i].x - p.x, path[i].z - p.z).length() < WALK_LOOK:
			i += 1
		var aim := path[i]
		var left := Vector2(goal.x - p.x, goal.z - p.z).length()
		if i >= path.size() - 1 and left < 0.22:
			break
		# No nearer for a while: close enough (furniture keeps his body off the very spot), or give up.
		spent += dt
		if left < best - 0.05:
			best = left
			since_best = 0.0
		else:
			since_best += dt
		if OS.has_environment("FILM_HUD") and fmod(spent, 2.0) < dt:
			var hud := world.find_child("ShiftHUD", true, false)
			print("  hud %s visible %s root %s focused %s hold %s pt %s frame %d" % [hud != null, hud.visible if hud else false, hud._root.visible if hud else false, player.is_focused(), hd.hold, str((get_first_node_in_group("passing_train") as PassingTrain).state) if get_first_node_in_group("passing_train") else "-", Engine.get_process_frames()])
			root.get_texture().get_image().save_png("user://hud_%d.png" % Engine.get_process_frames())
		if OS.has_environment("FILM_DEBUG") and fmod(spent, 2.0) < dt:
			print("  walk p %s aim %s left %.2f i %d/%d" % [str(p.snapped(Vector3.ONE * 0.01)), str(aim.snapped(Vector3.ONE * 0.01)), left, i, path.size()])
		if (since_best > 1.5 and left < 0.9) or spent > allowed:
			if spent > allowed:
				_mark("walk given up %.1f m short at %s" % [left, str(p.snapped(Vector3.ONE * 0.01))])
				_why(p)
			break
		# A door ahead: open it as he comes to it, and wait for it if it isn't open yet.
		var hold := false
		var flat := Vector2(aim.x - p.x, aim.z - p.z)
		_wc_t -= dt
		if _wc_t <= 0.0:
			_wc_t = 0.4
			_shut_wc_doors(p, goal)
		for e: Array in doors:
			var d: TrainDoor = e[1]
			if not is_instance_valid(d):
				continue
			var dp := (d.get_parent() as Node3D).global_position
			var to_d := Vector2(dp.x - p.x, dp.z - p.z)
			if to_d.length() > 2.4 or to_d.dot(flat) < -0.2:
				continue                             # (far, or behind him)
			if _wc_door(d) and d.global_position.distance_to(goal) > 1.6:
				continue                             # (the way only brushes the W.C.'s threshold: not going in)
			if not (d.is_open() and float(d.get("_t")) > 0.8):
				if not d.is_open():
					d.request(true)
					_opened.append(d)
				if to_d.length() < 1.1:
					hold = true
		var want := atan2(-flat.x, -flat.y)
		player.rotation.y = lerp_angle(player.rotation.y, want, clampf(dt * 7.0, 0.0, 1.0))
		head.rotation.x = lerpf(head.rotation.x, -0.06, clampf(dt * 3.0, 0.0, 1.0))
		var off := absf(angle_difference(player.rotation.y, want))
		if hold or off > 0.7:
			Input.action_release("fp_forward")
			waited += dt
			if waited > 8.0:
				_mark("door would not open")
				break
			continue
		waited = 0.0
		Input.action_press("fp_forward")
		# Caught on a corner, or someone standing in the way: a small step past (to one side for a person).
		stuck += dt
		if stuck > 0.8:
			if p.distance_to(last) < 0.08:
				var who := _in_the_way(p, flat)
				if who:
					# Somebody coming the other way in the aisle: into the gap beside it till they are by.
					Input.action_release("fp_forward")
					await _let_pass(who, Vector3(flat.x, 0, flat.y).normalized())
					path = nav.path(player.global_position, goal, false)
					doors = nav.doors_on(path)
					i = 1
					if path.size() < 2:
						break
				elif await _shut_door_ahead(p, flat, doors):
					pass                                 # (a W.C. door left standing open across the way)
				else:
					player.global_position = p + Vector3(flat.x, 0, flat.y).normalized() * 0.15
			stuck = 0.0
			last = player.global_position
		# Doors he opened, shut behind him.
		for e: Array in doors:
			var d: TrainDoor = e[1]
			if is_instance_valid(d) and d.is_open() and _opened.has(d):
				var dp := (d.get_parent() as Node3D).global_position
				var to_d := Vector2(dp.x - p.x, dp.z - p.z)
				if to_d.length() > 1.8 and to_d.dot(flat) < 0.0:
					d.request(false)
					_opened.erase(d)
	Input.action_release("fp_forward")
	return true

var _opened: Array = []
var _wc_t := 0.0

# W.C. doors left standing open across the vestibules: shut as he comes near (unless he is going in,
# or somebody is at it).
func _shut_wc_doors(p: Vector3, goal: Vector3) -> void:
	if _all_doors.is_empty():
		_all_doors = train.find_children("*", "TrainDoor", true, false)
	for d: TrainDoor in _all_doors:
		if not is_instance_valid(d) or not _wc_door(d) or not d.is_open():
			continue
		var hinge := d.global_position
		if hinge.distance_to(p) > 3.2 or hinge.distance_to(goal) < 1.6:
			continue
		var busy := false
		for r in pax.riders():
			if r.body.global_position.distance_to(hinge) < 1.3 or (r.wc_car != null and (r.wc_car as Node).is_ancestor_of(d)):
				busy = true                          # (somebody at it, or in that W.C.)
		if not busy:
			d.request(false)

func _wc_door(d: TrainDoor) -> bool:
	return String(d.get_parent().name).begins_with("ToiletDoor")

func _why(p: Vector3) -> void:
	if _all_doors.is_empty():
		_all_doors = train.find_children("*", "TrainDoor", true, false)
	for d: TrainDoor in _all_doors:
		if is_instance_valid(d) and d.global_position.distance_to(p) < 2.5:
			print("    door %s/%s open %s t %.2f lock '%s' at %s" % [d.get_parent().name, d.name, d.is_open(), float(d.get("_t")), d.lock_reason(), str(d.global_position.snapped(Vector3.ONE * 0.01))])
	for r in pax.riders():
		if r.body.global_position.distance_to(p) < 2.0:
			print("    person %s state %d at %s" % [r.body.name, r.state, str(r.body.global_position.snapped(Vector3.ONE * 0.01))])
var _all_doors: Array = []

# An open door standing across his way (a W.C. door left open): shut it. True if there was one.
func _shut_door_ahead(p: Vector3, flat: Vector2, mine: Array) -> bool:
	if _all_doors.is_empty():
		_all_doors = train.find_children("*", "TrainDoor", true, false)
	var on_way: Array = mine.map(func(e): return e[1]).filter(func(d): return is_instance_valid(d) and not _wc_door(d))
	for d: TrainDoor in _all_doors:
		if not is_instance_valid(d) or not d.is_open() or on_way.has(d):
			continue
		var dp := d.global_position
		var to_d := Vector2(dp.x - p.x, dp.z - p.z)
		if to_d.length() < 1.4 and to_d.dot(flat) > -0.3:
			Input.action_release("fp_forward")
			var away := Vector3(p.x - dp.x, 0, p.z - dp.z)
			if away.length() < 1.0:
				var c := nav.nearest_free(p + away.normalized() * 0.7, false, 0.4)
				if c.x >= 0:
					var from := player.global_position
					var to := nav.cell_pos(c)
					var el := 0.0
					while el < 0.5:
						await physics_frame
						el += 1.0 / Engine.physics_ticks_per_second
						player.global_position = from.lerp(Vector3(to.x, from.y, to.z), smoothstep(0.0, 1.0, el / 0.5))
			await _face(dp + Vector3(0, 1.0, 0), 0.35)
			d.request(false)
			await _sleep(1.2)
			return true
	return false

# A person (a passenger, or Mike) standing or walking just ahead.
func _in_the_way(p: Vector3, flat: Vector2) -> Node3D:
	var people: Array = pax.riders().map(func(r): return r.body)
	var mike := train.find_child("Mike", true, false)
	if mike:
		people.append(mike)
	for b: Node3D in people:
		if not is_instance_valid(b):
			continue
		var to_b := Vector2(b.global_position.x - p.x, b.global_position.z - p.z)
		if to_b.length() < 1.2 and to_b.dot(flat) > 0.0:
			return b
	return null

func _let_pass(who: Node3D, dir: Vector3) -> void:
	var p := player.global_position
	var side := Vector3(-dir.z, 0, dir.x)
	var spot := Vector3.INF
	for s in [0.75, -0.75, 0.6, -0.6, 1.0, -1.0]:
		var c := nav.nearest_free(p + side * s - dir * 0.3, false, 0.2)
		if c.x >= 0:
			var q := nav.cell_pos(c)
			if Vector2(q.x - p.x, q.z - p.z).length() > 0.4 and q.distance_to(who.global_position) > 0.6:
				spot = q
				break
	if spot != Vector3.INF:
		var from := p
		var el := 0.0
		while el < 0.5:
			await physics_frame
			el += 1.0 / Engine.physics_ticks_per_second
			player.global_position = from.lerp(Vector3(spot.x, from.y, spot.z), smoothstep(0.0, 1.0, el / 0.5))
	var waited := 0.0
	while waited < 3.0 and is_instance_valid(who) and Vector2(who.global_position.x - player.global_position.x, who.global_position.z - player.global_position.z).length() < 1.3:
		await _sleep(0.25)
		waited += 0.25
	# Still standing there (at the vestibule window, say): he squeezes past.
	if is_instance_valid(who) and waited >= 3.0:
		for b: Node in who.find_children("*", "PhysicsBody3D", true, false) + ([who] if who is PhysicsBody3D else []):
			player.add_collision_exception_with(b)
		var mb := train.find_child("MikeBody", true, false)
		if mb and who.name == "Mike":
			player.add_collision_exception_with(mb)
	await _sleep(0.4)

## Turns the eye to `p` over `secs`.
func _face(p: Vector3, secs := 0.45) -> void:
	var eye: Vector3 = head.global_position
	var d := p - eye
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var y0 := player.rotation.y
	var p0 := head.rotation.x
	var el := 0.0
	while el < secs:
		await physics_frame
		el += 1.0 / Engine.physics_ticks_per_second
		var k := smoothstep(0.0, 1.0, el / secs)
		player.rotation.y = lerp_angle(y0, yaw, k)
		head.rotation.x = lerpf(p0, pitch, k)

func _use(n: Node, wait := 0.8) -> void:
	var r := str(n.call("interact", player))
	if r != "":
		player.show_message(r, 2.5)
	await _sleep(wait)

func _head_of(b: TalkingCharacter) -> Vector3:
	if b._skel and b._bones.has("Head"):
		return b._skel.global_transform * b._skel.get_bone_global_pose(b._bones["Head"]).origin
	return b.global_transform * Vector3(0, b._head_h, 0)

func _car(n: String) -> Node3D:
	return train.get_node(n) as Node3D

# ————— talking —————

## A conversation with a passenger: the lines asked in turn by their keys, then goodbye.
func _talk(r, keys: Array) -> void:
	if r == null or not pax.riders().has(r):
		return
	var spot: Vector3 = pax.seat_front(r) if not r.seat.is_empty() else r.body.global_position
	await _go(spot)
	await _face(_head_of(r.body), 0.4)
	var t := PassengerTalk.of(r.body)
	if t == null:
		return
	t.interact(player)
	await _sleep(1.1)
	for k in keys:
		if not is_instance_valid(t):
			break
		var i := t._keys.find(k)
		if i < 0:
			continue
		t._on_pick(i)
		await _sleep(3.4)
		if hd.hold or not (af.stage in ["", "armed"]):
			await _hold_for_scares()             # (it turned on him: the scare has the eye now)
			return
	if not is_instance_valid(t):
		await _sleep(1.2)                       # (laid to rest: nobody left to say goodbye to)
		return
	var bye := t._keys.find("bye")
	if bye >= 0 and DialogueMenu._instance(t).is_open_for(t):
		t._on_pick(bye)
	await _sleep(1.2)

# ————— the routine —————

func _panel(car: String) -> StaffPanel:
	return _car(car).find_children("*", "StaffPanel", true, false)[0] as StaffPanel

func _at_panel(p: StaffPanel) -> void:
	await _go(p.global_position + Vector3(0, 0, 0.45))
	await _face(p.global_position + Vector3(0, -0.1, 0), 0.5)
	if not p.door_open:
		p.press("door")
		await _sleep(1.0)

func _heating(car: String) -> void:
	_mark("heating " + car)
	var p := _panel(car)
	await _at_panel(p)
	p.press("mode:HEAT")
	await _sleep(1.2)
	p.press("door")
	await _sleep(0.6)

func _night_lights() -> void:
	_mark("night lights")
	var p := _panel("SleeperCar1")
	await _at_panel(p)
	await _use(p.toggles[0], 0.9)               # MAIN off
	await _use(p.toggles[3], 1.2)               # NIGHT on
	p.press("door")
	await _sleep(0.6)

func _tickets(car: String) -> void:
	_mark("tickets " + car)
	# Round the coach, then round again for anyone who was off on an errand the first time.
	for round_n in 3:
		var list: Array = pax.riders().filter(func(r): return r.car == _car(car) and r.state == Passengers.State.SEATED and not r.ghost and not PassengerTalk.of(r.body).seen.has("ticket"))
		if list.is_empty():
			break
		var from_x := player.global_position.x
		list.sort_custom(func(a, b): return absf(a.body.global_position.x - from_x) < absf(b.body.global_position.x - from_x))
		for r in list:
			await _urgent()
			if not pax.riders().has(r) or r.state != Passengers.State.SEATED:
				continue
			await _talk(r, ["ticket", "well"] if r.anomaly != "" else ["ticket"])
		if round_n < 2:
			await _sleep(2.0)

func _berth() -> void:
	if chores.berths.is_empty():
		return
	var job: BerthJob = chores.berths[0]
	_mark("berth " + job.berth)
	var bed := job.get_parent() as Node3D
	var door := _comp_door(bed)
	await _go(Vector3(door.x, 1.4, 0.3))
	await _face(bed.global_position + Vector3(0, 0.6, 0), 0.5)
	await _sleep(0.8)
	if job.waste and job._waste_on():
		await _face(job.waste.global_position, 0.4)
		await _use(job.waste, 1.0)
	await _face(bed.global_position + Vector3(0, 0.6, 0), 0.4)
	await _use(job._spot, 1.2)                  # strip
	var room := _car("SleeperCar1").find_child("ServiceRoom", true, false) as Node3D
	var hamper := chores.find_child("HamperSpot", true, false) as Node3D
	await _go(hamper.global_position)
	await _face(hamper.global_position, 0.4)
	await _use(hamper, 0.8)
	var brush := chores.find_child("Item_brush", true, false) as Node3D
	await _go(brush.global_position)
	await _face(brush.global_position, 0.4)
	await _use(brush, 0.6)
	var linen := chores.find_child("LinenSpot", true, false) as Node3D
	await _go(linen.global_position + Vector3(0.5, 0, 0))
	await _face(linen.global_position, 0.4)
	await _use(linen, 0.8)
	await _go(Vector3(door.x, 1.4, 0.3))
	await _face(bed.global_position + Vector3(0, 0.6, 0), 0.5)
	for k in 3:
		await _use(job._spot, 1.1)              # scrub, scrub, make up
	await _sleep(0.8)
	inv.use("brush")
	# The waste down the W.C. at the end of the car.
	var bowl := _car("SleeperCar1").find_child("ToiletBowl", true, false) as Node3D
	if inv.has_item("waste") and bowl:
		await _go(bowl.global_position)
		await _face(bowl.global_position + Vector3(0, 0.4, 0), 0.5)
		for s: Node in chores.find_children("WasteSpot", "HauntSpot", true, false):
			if (s as Node3D).global_position.distance_to(bowl.global_position) < 1.0:
				await _use(s, 1.0)

func _comp_door(bed: Node3D) -> Vector3:
	var n := int(bed.get_meta("compartment", 1))
	var d := _car("SleeperCar1").find_child("Door_Compartment_%d" % n, true, false) as Node3D
	return d.global_position if d else bed.global_position

# A suspicious one (an anomaly he has spoken to) reported to Mike.
func _report() -> void:
	var det: Detention = get_first_node_in_group("detention")
	var list := det.reportable().filter(func(r): return r.anomaly != "" and not PassengerTalk.of(r.body).evidence().is_empty())
	if list.is_empty():
		_reported = true                        # (nobody to report)
		return
	_mark("report to Mike")
	var mike := train.find_child("Mike", true, false) as TalkingCharacter
	await _go(mike.global_position + Vector3(0.9, 0, 0))
	await _face(_head_of(mike), 0.5)
	var st := mike.get_node(StaffTalk.NAME) as StaffTalk
	await _use(st, 1.2)
	if not DialogueMenu._instance(st).is_open_for(st):
		await _sleep(1.5)                       # (woken from his nap first)
		await _use(st, 1.2)
	st._on_pick(1)                              # "I want to report a passenger."
	await _sleep(1.6)
	var i := st._report_list.find(list[0])
	print("  report: menu open %s, mode %s, list %d, index %d" % [DialogueMenu._instance(st).is_open_for(st), st._mode, st._report_list.size(), i])
	if i >= 0:
		st._on_pick(i)
	_reported = true
	await _sleep(3.0)
	if DialogueMenu._instance(st).is_open_for(st):
		st._end()

func _wake(r) -> void:
	_mark("wake-up call berth %s" % str(r.bed.get_meta("berth", "?")))
	await _go(Vector3(_comp_door(r.bed).x, 1.4, 0.3))
	await _face(_head_of(r.body), 0.5)
	await _use(PassengerTalk.of(r.body), 2.5)

# ————— the ghost —————

func _ghost_name() -> void:
	var g = h.ghost
	_mark("ghost: who is it")
	await _talk(g, ["ticket", "who"])
	if h.ghost != g:
		return
	var term := h.car.find_children("*", "ComputerTerminal", true, false)[0] as ComputerTerminal
	_mark("ghost: Jim")
	await _go(term.view_transform().origin)
	await _face(term.global_position, 0.5)
	term.interact(player)
	await _sleep(1.4)
	term.desktop.open_app("friend")
	await _sleep(3.0)
	h.send_name(PassengerTalk.of(g.body).full_name)
	await _sleep(2.5)
	term.release()
	await _sleep(0.8)
	_ghost_step = 1

func _ghost_rest() -> void:
	var g = h.ghost
	_mark("ghost: " + h.kind)
	match h.kind:
		"coffee", "newspaper":
			var it: HauntItem = h._items[h.kind]
			await _go(it.global_position)
			await _face(it.global_position, 0.5)
			await _use(it, 0.8)
			await _talk(g, ["haunt_give"])
		"say":
			await _talk(g, ["haunt_say"])
		"riddle":
			await _talk(g, ["haunt_riddle", "haunt_ans_%d" % int(h._riddle.ok)])
	_ghost_step = 2 if h.ghost != g else 1          # (not laid to rest yet: try again)
	await _sleep(3.0)

# A breakdown (the ghost left too long): the tool, then every step of the job where it is.
func _fix() -> void:
	_mark("fault: " + h.incident)
	var tool: String = {"toilet": "plunger", "ac": "screwdriver", "computer": "usb"}.get(h.incident, "")
	if tool != "" and not inv.has_item(tool) and h._items.has(tool):
		var it: HauntItem = h._items[tool]
		await _go(it.global_position)
		await _face(it.global_position, 0.4)
		await _use(it, 0.6)
	var tries := 0
	while h.incident != "" and tries < 30:
		tries += 1
		var target: Node = null
		if h.incident == "computer" and h._term:
			target = h._term
		else:
			for s: Node in h._spots:
				if is_instance_valid(s) and s is HauntSpot and (s as HauntSpot).prompt.is_valid() and str(s.call("get_prompt")).begins_with("E"):
					target = s
					break
		if target == null:
			await _sleep(1.0)
			continue
		var at := (target as Node3D).global_position
		await _go(Vector3(at.x, 1.4, at.z))
		await _face(at, 0.4)
		await _use(target, 1.0)
		if h.incident == "computer":
			await _sleep(9.0)

func _coffee(r) -> void:
	if r == null:
		return
	_mark("coffee")
	var it: HauntItem = h._items["coffee"]
	await _go(it.global_position)
	await _face(it.global_position, 0.5)
	await _use(it, 0.8)
	await _talk(r, ["chore_coffee"])

# ————— the rest of the night —————

func _wake_scare() -> void:
	_scared = true
	var can := pax.riders().filter(func(r): return r.state == Passengers.State.SLEEPING and not r.body.has_meta("wake_call"))
	if can.is_empty():
		return
	var r = can[0]
	if ws.rider == null or not pax.riders().has(ws.rider) or ws.rider.state != Passengers.State.SLEEPING:
		if ws.rider and pax.riders().has(ws.rider):
			ws.rider.body.remove_meta("wake_scare")
		ws.sprung = false
		ws.pick(r, "anomaly")
	r = ws.rider
	_mark("wake the wrong one")
	await _go(Vector3(_comp_door(r.bed).x, 1.4, 0.35))
	await _face(r.bed.global_transform * Vector3(0, SleepBlanket.MATTRESS + 0.15, 0.45), 0.6)
	await _sleep(0.8)
	await _use(PassengerTalk.of(r.body), 3.5)
	await _sleep(2.5)

# Down the train and back, looking in at the passengers.
func _stroll() -> void:
	var spots := [Vector3(rng.randf_range(-24.0, -12.0), 1.4, 0.0), Vector3(rng.randf_range(-6.0, 6.0), 1.4, 0.0),
			Vector3(rng.randf_range(12.0, 23.0), 1.4, -1.0)]
	var to: Vector3 = spots[rng.randi_range(0, spots.size() - 1)]
	await _go(to)
	await _face(player.global_position + Vector3(rng.randf_range(-3.0, 3.0), 0.3, rng.randf_range(-1.0, 1.0)), 0.8)
	await _sleep(rng.randf_range(2.0, 5.0))

func _turn_in() -> void:
	_mark("turn in")
	var eod: EndOfDay = world.find_child("EndOfDay", true, false)
	var bed := _car("CrewCar4").find_child("InspectorRoom", true, false).get_node("Bed") as Node3D
	await _go(bed.global_position + Vector3(-0.6, 0, 0))
	await _face(bed.global_position + Vector3(0, 0.6, 0), 0.6)
	await _sleep(1.0)
	await _use(eod._spot, 1.0)
	await _sleep(9.0)
