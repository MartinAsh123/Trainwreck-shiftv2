extends SceneTree
# Short demonstration clips (run with --write-movie <dir>/frame.png --fixed-fps 24):
#   -- errand | escort | ghost | mike_rest
# Controlled set-ups (forced), filmed with a camera that follows the action.
var world: Node3D
var cam: Camera3D
func _initialize() -> void:
	var clip: String = OS.get_cmdline_user_args()[0]
	DisplayServer.window_set_size(Vector2i(960, 540))
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var j: Node = world.get_node("Journey")
	j.call("warp_running", 2000.0)
	var player: Node3D = world.get_node("Player")
	player.set_physics_process(false)
	player.get_node("HUD").visible = false
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = false
	var hd: HorrorDirector = get_first_node_in_group("horror")
	hd.enabled = false
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	duty.next_patrol = 99.0
	duty.rest_enabled = clip == "mike_rest"
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 4000
	world.add_child(cam)
	cam.make_current()
	for i in 40: await process_frame
	match clip:
		"errand": await _errand(pax, player)
		"escort": await _escort(pax, player, duty)
		"ghost": await _ghost(player)
		"mike_rest": await _rest(duty, player)
	quit(0)

func _follow(target: Node3D, offset: Vector3, look_up := 1.3, smooth := 3.0, delta := 1.0 / 24.0) -> void:
	var want: Vector3 = target.global_position + offset
	cam.global_position = cam.global_position.lerp(want, clampf(delta * smooth, 0.0, 1.0))
	cam.look_at(target.global_position + Vector3(0, look_up, 0))

func _errand(pax: Passengers, player: Node3D) -> void:
	player.global_position = Vector3(-37.0, 1.45, -1.0)
	var r = null
	for x in pax.riders():
		if x.state == Passengers.State.SEATED and String(x.car.name) == "PassengerCar" and x.body.global_position.x > 0.0:
			r = x
			break
	pax.start_errand(r, "wc")
	cam.global_position = Vector3(r.body.global_position.x - 3.2, 3.05, -0.05)
	cam.fov = 70
	cam.look_at(r.body.global_position + Vector3(0, 1.1, 0))
	var t := 0.0
	while t < 50.0 and not (r.state == Passengers.State.ERRAND and r.errand_phase == "there" and r.errand_t > 4.0):
		await process_frame
		t += 1.0 / 24.0
		var want: Vector3 = (r.body.global_position + Vector3(0, 1.1, 0) - cam.global_position).normalized()
		cam.look_at(cam.global_position + (-cam.global_basis.z).lerp(want, 0.12))

func _escort(pax: Passengers, player: Node3D, duty: MikeDuty) -> void:
	player.global_position = Vector3(-31.0, 1.45, 0.6)
	var det: Detention = get_first_node_in_group("detention")
	var r = null
	for x in pax.riders():
		if x.state == Passengers.State.SEATED and String(x.car.name) == "PassengerCar3" and x.body.global_position.x < -18.0:
			r = x
			break
	PassengerTalk.of(r.body).seen["ticket"] = true
	det.report(r)
	cam.global_position = duty.mike.global_position + Vector3(2.0, 2.2, -0.3)
	cam.fov = 70
	var t := 0.0
	while t < 200.0:
		await process_frame
		t += 1.0 / 24.0
		var ahead := duty.mover.heading if duty.mover and duty.mover.heading != Vector3.ZERO else Vector3(1, 0, 0)
		var mid: Vector3 = duty.mike.global_position
		var want := Vector3.ZERO
		if duty.phase in ["lead"]:
			# high behind the passenger: Mike leading, the passenger a step behind him
			mid = (duty.mike.global_position + r.body.global_position) * 0.5
			want = r.body.global_position - ahead * 1.5 + Vector3(0, 1.75, 0)
		elif duty.phase in ["arrest"]:
			mid = (duty.mike.global_position + r.body.global_position) * 0.5
			want = duty.mike.global_position - ahead * 1.2 + Vector3(0, 1.75, 0)
		elif duty.phase in ["open", "enter", "close"]:
			mid = cage_mid()
			want = duty.mike.global_position + Vector3(1.0, 1.75, -0.6)
		else:
			want = duty.mike.global_position - ahead * 1.6 + Vector3(0, 1.75, 0)
		# Inside the car: never through the roof, the walls or out over a gangway's side.
		want.y = minf(want.y, 1.4 + 1.85)
		var nav: TrainNav = get_first_node_in_group("train_nav")
		var c := nav.nearest_free(Vector3(want.x, 1.4, want.z), false, 0.6)
		if c.x >= 0:
			var fp := nav.cell_pos(c)
			want.x = fp.x
			want.z = fp.z
		cam.global_position = cam.global_position.lerp(want, 0.05)
		var dir := (mid + Vector3(0, 1.0, 0) - cam.global_position).normalized()
		cam.look_at(cam.global_position + (-cam.global_basis.z).lerp(dir, 0.15))
		if det.held.has(r.pid) and duty.job == "room":
			for i in 48: await process_frame
			break

func cage_mid() -> Vector3:
	var cage: HoldingCage = get_first_node_in_group("holding_cage")
	return cage.gate_middle() + Vector3(0, -0.6, 0.4)

func _ghost(player: Node3D) -> void:
	var ghost: GhostStory = get_first_node_in_group("ghost_story")
	ghost.intro_at = 0.0
	for i in 30: await process_frame
	TerminalData.messages[ghost._msg_index].read = true
	player.global_position = Vector3(12.4, 1.45, -1.0)
	player.rotation.y = -PI * 0.5
	var pcam := player.get_viewport().get_camera_3d()
	cam.global_position = Vector3(12.4, 2.95, -1.0)
	cam.rotation = Vector3(0, -PI * 0.5, 0)
	var t := 0.0
	while t < 14.0:
		await process_frame
		t += 1.0 / 24.0
		# Kevin walks slowly down the corridor toward her.
		if t > 2.0 and ghost.stage in ["shown", "waiting"]:
			player.global_position.x += 0.9 / 24.0
			cam.global_position.x = player.global_position.x
		if ghost.stage == "waiting":
			# (the story checks the player's own camera: keep it in step)
			pcam.global_transform = cam.global_transform

func _rest(duty: MikeDuty, player: Node3D) -> void:
	player.global_position = Vector3(-31.0, 1.45, 0.6)
	var ts := root.get_node("TrainState")
	duty.rest_start = ts.clock - 0.01
	duty.rest_latest = ts.clock + 1.0
	duty.rest_minutes = 1.0
	cam.global_position = duty._bed.global_position + Vector3(1.25, 2.0, -0.5)
	cam.fov = 70
	var bed: Node3D = duty._bed
	var t := 0.0
	while t < 60.0:
		await process_frame
		t += 1.0 / 24.0
		var focus := duty.mike.global_position + Vector3(0, 1.0, 0)
		if duty.job == "rest" and duty.phase in ["lie_down", "sleep", "wake"]:
			focus = bed.global_position + Vector3(0, 0.75, 0)
		cam.look_at(cam.global_position + (-cam.global_basis.z).lerp((focus - cam.global_position).normalized(), 0.15))
		if duty.rested and duty.job == "room" and t > 6.0:
			for i in 36: await process_frame
			break
