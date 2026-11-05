extends SceneTree
## A sleeper in the sleeping car, asleep and then waking (frames at set times).
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	await process_frame
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	world.get_node("Journey").set_physics_process(false)
	var player := world.get_node("Player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 30:
		await process_frame
	var pax := world.get_node("Passengers") as Passengers
	var r = null
	for x in pax._riders:
		if x.state == Passengers.State.SLEEPING:
			r = x
			break
	if r == null:
		print("NO SLEEPER"); quit(1); return
	print("SLEEPER ", r.slug, " bed ", r.bed.name, " side ", r.side)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 66
	cam.make_current()
	var bx: Transform3D = r.bed.global_transform
	cam.global_position = bx * Vector3(r.side * 0.75, 1.65, -0.75)
	cam.look_at(bx * Vector3(0, 0.55, 0.25))
	for i in 40:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "_asleep.png")
	# from beside the pillow: the sleeper's head and the blanket over the shoulder
	cam.global_position = bx * Vector3(r.side * 0.75, 1.35, 0.95)
	cam.look_at(bx * Vector3(0, 0.62, 0.0))
	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "_head.png")
	cam.global_position = bx * Vector3(r.side * 0.75, 1.65, -0.75)
	cam.look_at(bx * Vector3(0, 0.55, 0.25))
	r.state = Passengers.State.WAKING
	r.t = 0.0
	var times := [0.6, 1.2, 2.0, 2.8, 3.6, 4.8]
	var el := 0.0
	var k := 0
	while k < times.size():
		await process_frame
		el += 1.0 / 30.0
		if el >= times[k]:
			root.get_viewport().get_texture().get_image().save_png(out + "_w%d.png" % k)
			k += 1
	quit()
