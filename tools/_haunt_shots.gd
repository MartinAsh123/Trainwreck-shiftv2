extends SceneTree
# Stills of the haunting's props and jobs.  -- <out_dir>
var world: Node3D
var cam: Camera3D
var out: String
var n := 0
func _shot(at: Vector3, look: Vector3, tag: String, fov := 62.0) -> void:
	cam.fov = fov
	cam.global_position = at
	cam.look_at(look)
	for i in 8: await process_frame
	root.get_texture().get_image().save_png(out + "/s%02d_%s.png" % [n, tag])
	n += 1

func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	world.get_node("Journey").call("warp_running", 2000.0)
	var player: Node3D = world.get_node("Player")
	player.global_position = Vector3(-37.0, 1.45, -1.0)
	player.set_physics_process(false)
	player.get_node("HUD").visible = false
	var h: HauntDirector = get_first_node_in_group("haunt")
	get_first_node_in_group("horror").enabled = false
	h.enabled = false
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	cam = Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	for i in 40: await process_frame
	var c: Vector3 = h._items["coffee"].global_position
	await _shot(c + Vector3(-0.1, 0.5, -0.5), c, "coffee")
	var p: Vector3 = h._items["newspaper"].global_position
	await _shot(p + Vector3(0.1, 0.65, -0.55), p, "desk_mike")
	var dk: Vector3 = h._items["disk"].global_position
	await _shot(dk + Vector3(0.25, 0.55, -0.5), dk, "disk")
	var pl: Vector3 = h._items["plunger"].global_position
	await _shot(pl + Vector3(-0.3, 1.6, -0.75), pl + Vector3(-0.2, 0.3, 0), "crew_wc", 75.0)
	var pax: Passengers = world.get_node("Passengers")
	var g = null
	for r in pax.riders():
		if r.state == Passengers.State.SEATED and r.anomaly == "" and String(r.car.name) == "PassengerCar":
			g = r
			break
	h.car = g.car
	h.ghost = g
	pax.make_ghost(g)
	h._toilet_begin()
	var bowl: Vector3 = (h.car.find_child("ToiletBowl", true, false) as Node3D).global_position
	await _shot(Vector3(bowl.x - 0.95, 3.15, 0.62), bowl + Vector3(-0.5, 0.0, 0.0), "flood", 80.0)
	h._incident_done()
	h._ac_begin()
	for s in h._spots:
		if s.name == "HatchLatch": s.interact(player)
	await create_timer(1.2).timeout
	var ha: Vector3 = h._hatch.global_position
	await _shot(ha + Vector3(-1.5, -1.1, -0.35), ha + Vector3(0, -0.12, 0), "hatch", 70.0)
	var term: ComputerTerminal = h.car.find_children("*", "ComputerTerminal", true, false)[0]
	h._computer_begin()
	var tp := term.global_position
	await _shot(tp + (-term.global_basis.z) * 0.7 + Vector3(0, 0.1, 0), tp, "term_dead", 55.0)
	h._term.set_broken(false)
	term.fault = null
	await create_timer(4.0).timeout
	term.desktop.mode = XPDesktop.Mode.DESKTOP
	term.desktop._windows_layer.visible = true
	var pt := PassengerTalk.of(g.body)
	pt.known = true
	PassengerTalk.of(pax.riders().filter(func(r): return r != g)[1].body).known = true
	term.desktop.open_app("friend")
	await _shot(tp + (-term.global_basis.z) * 0.62, tp, "friend", 50.0)
	# the flash
	var face: Vector3 = g.body.global_position + Vector3(0, 1.15, 0)
	var at := Vector3(face.x - 1.8, 3.05, 0.0)
	GhostFade.flash(g.body)
	cam.fov = 60
	cam.global_position = at
	cam.look_at(face)
	for i in 22: await process_frame
	root.get_texture().get_image().save_png(out + "/s%02d_flash.png" % n)
	quit(0)
