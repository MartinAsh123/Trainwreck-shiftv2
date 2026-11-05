extends SceneTree
# A picture of the HUD in the middle of a haunting (run windowed):  -- <out.png>
# The train under way, two things in the toolbar, a haunting under way in coach two and Kevin in it,
# so the ghost's timer shows.

func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var pax: Passengers = world.get_node("Passengers")
	pax.trips_enabled = false
	world.get_node("Journey").call("warp_running", 1200.0)
	pax._on_departing("")
	var h: HauntDirector = get_first_node_in_group("haunt")
	h.first_start = 0.5
	h._next_start = 0.5
	var player: Node3D = world.get_node("Player")
	while h.stage != "signs":
		await process_frame
	var g: Node3D = h.ghost.body
	player.global_position = Vector3(g.global_position.x + 2.2, 1.4, 0.0)
	player.rotation.y = PI * 0.5
	var inv: Inventory = get_first_node_in_group("inventory")
	for id in ["coffee", "usb"]:
		if h._items.has(id):
			inv.take(h._items[id])
	var el := 0.0
	while el < 4.0:
		await process_frame
		el += root.get_process_delta_time()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("SAVED ", out, " ghost timer ", h.ghost_timer())
	quit()
