extends SceneTree
## Sets off an anomaly's frenzy in the real journey and checks how it ends.
##   godot --path . -s tools/_test_frenzy.gd -- <out_dir> exposed|arrest|hunt|abort [slug,slug...]
## With slugs: the first of them aboard, or it stops with exit code 3 (who rides differs from run to run).
## abort: armed, then taken in hand before it goes: the passenger must come back as it was.
## "+crowd" after the mode (exposed+crowd...): others of its car up and about first, to be in its way.
## PANIC_CAM=1 in the environment: from the lunge on, the film is seen from high in the car (the people about it).
## "fate" (no scene): how the one roll falls.

var world: Node3D
var out := ""
var fr: AnomalyFrenzy
var player: CharacterBody3D
var last := ""
var shots := 0
var shot_t := 0.0
var worst: Array = []
var then := 0
var closest := INF                 # nearest it came to anyone on their feet while it ran
var through := 0                   # frames it was in someone (nearer than 0.3 m)
var most_afraid := 0
var spy: Camera3D                  # PANIC_CAM

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args[0] != "-" else ""            # "-": no stills (with --write-movie)
	var mode: String = args[1]
	var crowd := mode.ends_with("+crowd")
	mode = mode.trim_suffix("+crowd")
	if mode == "fate":
		var f := AnomalyFrenzy.new()
		var n := {"": 0, "exposed": 0, "arrest": 0}
		for i in 200000:
			n[f._fate_of(i)] += 1
		print("fate of 200000: ", n)
		f.free()
		quit(0)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	world.get_node("Journey").call("warp_running", 2000.0)
	player = world.get_node("Player")
	var pax: Passengers = world.get_node("Passengers")
	pax._on_departing("")                              # (the warp skips the departure: nobody left half way in)
	pax.trips_enabled = false
	var hd: HorrorDirector = get_first_node_in_group("horror")
	hd.enabled = false                                 # (no signs of its own, and no waiting for the night's peak)
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	fr = AnomalyFrenzy.of(world)
	if fr == null:
		fr = AnomalyFrenzy.new()
		fr.name = "AnomalyFrenzy"
		world.get_node("Gameplay").add_child(fr)
	fr.violent_chance = 1.0
	fr.wait_for_guard = 0.0 if mode == "exposed" else 1.0
	await _frames(30)
	var r = null
	var rank := 999
	var liked: PackedStringArray = args[2].split(",") if args.size() > 2 else PackedStringArray()
	var film_mike := OS.has_environment("FILM_MIKE")
	var best_d := INF
	for x in pax.anomalies():
		if x.state != Passengers.State.SEATED:
			continue
		if film_mike:
			# One whose nearest way out is on the guard's side (it runs out past him, in the
			# player's view) with room in the car behind it for the player; of those, the nearest
			# the guard (the shortest walk for him, the shortest film).
			var ax: float = pax.seat_exit(x).x
			var dir := signf(ax - duty.mike.global_position.x)
			var a := INF
			var b := INF
			for d: TrainDoor in fr._exit_doors():
				var dx := (d.get_parent() as Node3D).global_position.x - ax
				if signf(dx) == -dir:
					a = minf(a, absf(dx))
				else:
					b = minf(b, absf(dx))
			var dm := absf(ax - duty.mike.global_position.x) + (0.0 if a < b and b > 2.8 else 1000.0)
			if dm < best_d:
				best_d = dm
				r = x
			continue
		var at := liked.find(x.slug)
		at = at if at >= 0 else 998
		if at <= rank:
			r = x
			rank = at
	if r == null or (not liked.is_empty() and rank == 998):
		print("NO ANOMALY SEATED")
		quit(3)
		return
	print("anomaly ", r.slug, " kind ", r.anomaly, " at ", r.body.global_position, " pid ", r.pid)
	var pid: int = r.pid
	var aisle := pax.seat_exit(r)
	var off := Vector3(-0.2, 0, 0) if mode != "hunt" else Vector3.ZERO
	player.global_position = Vector3(aisle.x, 1.42, 0.0) + off if mode != "hunt" else Vector3(-40.0, 1.42, -1.0)
	if mode == "hunt":
		player.global_position = Vector3(19.0 if aisle.x < 0 else -40.0, 1.42, -1.0)
	var to: Vector3 = r.body.global_position
	player.look_at(Vector3(to.x, player.global_position.y, to.z))
	player.get_node("Head").rotation.x = -0.3
	if film_mike:
		# On the far side of it from where the guard comes, looking up the aisle at his way in.
		var dir := signf(aisle.x - duty.mike.global_position.x)
		player.global_position = Vector3(aisle.x + dir * 1.3, 1.42, 0.0)
		player.look_at(Vector3(aisle.x - dir * 3.0, player.global_position.y, to.z * 0.45))
		player.get_node("Head").rotation.x = -0.12
	if crowd:
		var sent := 0
		for x in pax.riders():
			if x != r and x.car == r.car and x.state == Passengers.State.SEATED and not x.ghost and sent < 3:
				if pax.start_errand(x, "window"):
					sent += 1
					print("up and about: ", x.slug)
		await _frames(150)
	await _frames(20)
	if mode == "abort":
		fr.trigger(r, "exposed")
		await _frames(10)
		print("armed: ", fr.stage, " monster ", r.body.find_child("MonsterFace", false, false) != null)
		pax.take_for_escort(r)
		await _frames(10)
		var skel: Skeleton3D = r.body._skel
		print("stage '", fr.stage, "' monster ", r.body.find_child("MonsterFace", false, false) != null,
				" override ", r.body._face.get_surface_override_material(0), " maw ", skel.find_child("MonsterMaw", false, false) != null,
				" attachments ", skel.find_children("*", "BoneAttachment3D", false, false).size(), " weights ", r.body.face_weights)
		quit(0)
		return
	var t: PassengerTalk = PassengerTalk.of(r.body)
	if mode == "exposed":
		t.interact(player)
		await _frames(30)
		var menu := root.get_node("DialogueMenu") as DialogueMenu
		menu._pick(1)
	else:
		t.seen["who"] = true
		print("report: ", get_first_node_in_group("detention").report(r))
	var seen_after := false
	var mike_seen := false
	for k in 40000:
		await process_frame
		_watch()
		if not mike_seen and duty.mike.global_position.distance_to(player.global_position) < 8.0:
			mike_seen = true
			print("frame %d  mike 8 m off" % Engine.get_frames_drawn())
		seen_after = seen_after or fr.stage == "after"
		if seen_after and fr.stage == "":
			break
	await _frames(120)
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("worst frames ms: ", worst.slice(0, 8).map(func(e): return "%s %d" % [e[1], e[0]]))
	print("panic: jumps aside %d, frightened at once %d, closest to anyone standing %.2f m, frames in someone %d" % [
			fr._panic.dodges, most_afraid, closest, through])
	print("--- log")
	for l in fr.log_lines:
		print(l)
	var rec: ShiftRecord = get_first_node_in_group("shift_record")
	print("still aboard: ", pax.rider_by_pid(pid) != null)
	print("record: ", rec.entries.get(pid, {}).get("status", "?"), " | rep ", rec.reputation)
	print("player focused: ", player.is_focused(), " cam ", player.get_node("Head/Camera").transform.origin)
	print("mike: ", duty.job, " ", duty.phase, " log ", duty.log_lines.slice(-3))
	var opened := 0
	for d: Node in world.get_node("Train").find_children("*", "TrainDoor", true, false):
		if (d as TrainDoor).lock_while_moving and (d as TrainDoor).is_open():
			opened += 1
	print("exterior doors open: ", opened)
	print("det pending ", duty._det.pending_pid, " active ", duty._det.active_pid)
	var marks := fr.find_children("*", "Decal", false, false)
	print("marks on the floor: ", marks.size())
	if out != "" and marks.size() > 2:
		var d: Decal = marks[2]
		player.global_position = d.global_position + Vector3(-0.9, 0.02, 0.0)
		player.look_at(Vector3(d.global_position.x + 1.0, player.global_position.y, d.global_position.z))
		player.get_node("Head").rotation.x = -0.85
		await _frames(30)
		root.get_texture().get_image().save_png(out.path_join("marks.png"))
	quit(0)

func _watch() -> void:
	most_afraid = maxi(most_afraid, fr._panic.frightened().size())
	if fr._r != null and is_instance_valid(fr._r.body) and fr.stage in ["hunt", "flee"]:
		var at: Vector3 = fr._r.body.global_position
		var people: Array = []
		for x in (world.get_node("Passengers") as Passengers).riders():
			if x != fr._r and x.body.is_visible_in_tree() and x.body._sit < 0.3:
				people.append(x.body)
		people.append((get_first_node_in_group("mike_duty") as MikeDuty).mike)
		for b: Node3D in people:
			var d := Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length()
			if absf(b.global_position.y - at.y) < 1.0:
				closest = minf(closest, d)
				if d < 0.3:
					through += 1
				if d < 0.5 and OS.has_environment("PANIC_DEBUG"):
					var f = fr._panic._people.get(b)
					var x = (world.get_node("Passengers") as Passengers).rider_of(b)
					print("CLOSE %.2f %s %s state %s ph %s t %.1f fear %.2f frozen %s mover %s jump %.2f at %s it %s way %s" % [d, fr.stage, b.name,
							x.state if x else -1, x.errand_phase if x else "", x.errand_t if x else 0.0, f.fear if f else -1.0, f.frozen if f else false,
							(f.mover != null) if f else false, f.jump_t if f else -9.0, str(b.global_position.snapped(Vector3.ONE * 0.01)),
							str(at.snapped(Vector3.ONE * 0.01)), str(fr.way_ahead(3.0))])
	if OS.has_environment("PANIC_DEBUG") and fr.stage in ["drop", "flee", "leap", "hunt"]:
		var line := "%s it %s |" % [fr.stage, str(fr._r.body.global_position.snapped(Vector3.ONE * 0.01)) if fr._r != null else "-"]
		for x in (world.get_node("Passengers") as Passengers).riders():
			if x.state == Passengers.State.ERRAND:
				var f = fr._panic._people.get(x.body)
				line += " %s %s %s ph %s t %.1f fear %.2f frozen %s mover %s|" % [x.slug.left(8), str(x.body.global_position.snapped(Vector3.ONE * 0.01)),
						x.mover.state if x.mover else "-", x.errand_phase, x.errand_t, f.fear if f else -1.0, f.frozen if f else false, f.mover != null if f else false]
		print(line)
	var now := Time.get_ticks_usec()
	if then > 0:
		worst.append([(now - then) / 1000.0, fr.stage])
	then = now
	if OS.has_environment("PANIC_CAM"):
		_spy()
	if fr.stage != last:
		print("%7.2f  frame %d  %s  body %s  player %s" % [Time.get_ticks_msec() / 1000.0, Engine.get_frames_drawn(), fr.stage,
				str(fr._r.body.global_position.snapped(Vector3.ONE * 0.01)) if fr._r != null and is_instance_valid(fr._r.body) else "-",
				str(player.global_position.snapped(Vector3.ONE * 0.01))])
		last = fr.stage
		shot_t = 0.0
		shots = 0
	shot_t -= 0.016
	if out != "" and fr.stage in ["tell", "hunt", "lunge", "hold", "drop", "flee", "leap"] and shot_t <= 0.0 and shots < 5:
		root.get_texture().get_image().save_png(out.path_join("%s_%d.png" % [fr.stage, shots]))
		shots += 1
		shot_t = 0.22

# High in the car, over the player's shoulder, then behind it on its way out, looking along its way.
func _spy() -> void:
	if fr.stage == "lunge" and spy == null:
		spy = Camera3D.new()
		spy.fov = 72.0
		world.add_child(spy)
		var p := player.global_position
		var side := -signf(fr._r.body.global_position.z) if absf(fr._r.body.global_position.z) > 0.1 else 1.0
		# (the way along the aisle that stays in this car: no door or wall between)
		var nav: TrainNav = get_first_node_in_group("train_nav")
		var away := 1.0
		for s: float in [1.0, -1.0]:
			var way := nav.path(Vector3(p.x, 1.4, 0.0), Vector3(p.x + s * 2.6, 1.4, 0.0), true)
			if way.size() >= 2 and nav.doors_on(way).is_empty():
				away = s
				break
		spy.global_position = Vector3(p.x + away * 2.6, 3.05, side * 0.85)
		spy.look_at(Vector3(p.x, 2.1, 0.0))
		spy.make_current()
	elif fr.stage == "flee" and spy != null and fr._exit != null and not spy.has_meta("moved"):
		spy.set_meta("moved", true)
		var m := (fr._exit.get_parent() as Node3D).global_position
		var at: Vector3 = fr._r.body.global_position
		var dir := signf(m.x - at.x)
		spy.global_position = Vector3(at.x - dir * 1.6, 3.05, -signf(m.z) * 0.85)
		spy.look_at(Vector3(lerpf(at.x, m.x, 0.55), 1.5, m.z * 0.3))
	elif fr.stage == "" and spy != null:
		spy.queue_free()
		spy = null

func _frames(n: int) -> void:
	for i in n:
		await process_frame
