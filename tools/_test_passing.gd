extends SceneTree
# The double-track event:  -- <out_dir> [view]   view: saloon (default) | window | outside
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var view: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "saloon"
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var pt: PassingTrain = get_first_node_in_group("passing_train")
	var pax: Passengers = world.get_node("Passengers")
	var h: HauntDirector = get_first_node_in_group("haunt")
	h.enabled = false
	pax.trips_enabled = false
	var hd: HorrorDirector = get_first_node_in_group("horror")
	hd.enabled = false
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	await create_timer(0.5).timeout
	print("sections ", pt.sections, " loops ", pt._loops.size(), " train length ", pt._length)
	var s: float = pt.sections[1]
	pt._next = 1
	var j: Node = world.get_node("Journey")
	j.call("warp_running", s - 700.0)
	var player: Node3D = world.get_node("Player")
	player.set_physics_process(false)
	player.get_node("HUD").visible = false
	player.global_position = Vector3(-5.0, 1.45, 0.0)
	var cam := Camera3D.new()
	cam.fov = 70
	world.add_child(cam)
	cam.make_current()
	match view:
		"saloon":
			cam.global_position = Vector3(-5.0, 3.05, 0.0)
			cam.look_at(Vector3(5.0, 2.7, 0.0))
		"window":
			cam.global_position = Vector3(-1.0, 3.0, 0.55)
			cam.look_at(Vector3(-4.0, 2.4, 8.0))
		"outside":
			cam.global_position = Vector3(-10.0, 3.6, 9.5)
			cam.look_at(Vector3(-70.0, 2.0, 3.0))
	var el := 0.0
	var next := 0.0
	var shots := 0
	var before := {}
	var train := world.get_node("Train")
	for l: Light3D in train.find_children("*", "Light3D", true, false):
		before[l] = [l.light_energy, l.visible]
	var last_state := ""
	while el < 60.0:
		await process_frame
		var dt: float = root.get_process_delta_time()
		el += dt
		if pt.state != last_state:
			last_state = pt.state
			print("%5.1f state %s head_x %.0f distance %.0f figures %d" % [el, pt.state, pt._head_x, root.get_node("TrainState").distance, pt._figures.size()])
		if pt.state == "show" and el >= next and shots < 8:
			next = el + 0.9
			root.get_texture().get_image().save_png(out + "/p_%s_%02d.png" % [view, shots])
			shots += 1
		if pt.count > 0 and pt.state == "idle" and el > 5.0:
			break
	await create_timer(1.0).timeout
	var bad := 0
	for l in before:
		if is_instance_valid(l) and (not is_equal_approx(l.light_energy, before[l][0]) or l.visible != before[l][1]): bad += 1
	var hold_after := hd.hold
	print("RESULT events ", pt.count, " history ", pt.history.map(func(x): return x[1]), " lamps changed ", bad, "/", before.size(), " hold ", hold_after, " figures left ", pt._figures.size(), " apparition nodes ", pt.get_children().filter(func(c): return c is TalkingCharacter).size())
	quit(0)
