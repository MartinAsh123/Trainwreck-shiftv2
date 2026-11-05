extends SceneTree
const SD := "C:/Users/marti/AppData/Local/Temp/claude/C--Users-marti-AppData-Roaming-Claude-scratch-workspaces-3e58b957-222a-49cc-a358-7d825abce1af-88de5f8e-6168-4768-8e06-65da1c67b280-scratch-2026-09-26-7f055c/f101d24e-3f93-42ca-aaee-c6355cbfddfa/scratchpad/"
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	world.get_node("Journey").set_physics_process(false)
	await _frames(30)
	var player: FPController = world.get_node("Player")
	var term: ComputerTerminal = get_first_node_in_group("terminal")
	print("terminals: ", get_nodes_in_group("terminal").size(), " at ", term.global_position)
	# Stand in front of it and look at it.
	var front := -term.global_basis.z
	player.global_position = term.global_position + front * 0.75 - Vector3(0, 1.45, 0)
	player.global_position.y = 1.42
	await _frames(10)
	player.look_at(Vector3(term.global_position.x, player.global_position.y, term.global_position.z), Vector3.UP)
	(player.get_node("Head") as Node3D).rotation.x = -0.25
	await _frames(20)
	print("aim: ", player._find_target(), " prompt: ", player._hud_prompt.text)
	await _save("t_approach.png")
	term.interact(player)
	await _frames(60)
	print("uv at centre: ", term._screen_uv(Vector2(640, 360)), " corner: ", term._screen_uv(Vector2(0, 0)))
	await _save("t_welcome.png")
	term.desktop._click(term.desktop._user_tile_rect().get_center())
	term.desktop.open_app("manifest")
	await _frames(30)
	await _save("t_manifest.png")
	term.desktop.open_app("status")
	term.desktop.open_app("timetable")
	await _frames(40)
	await _save("t_apps.png")
	term.desktop._start_open = true
	await _frames(10)
	await _save("t_start.png")
	# Real mouse events through the screen: click the Start button via the 3D mapping.
	term.desktop._start_open = false
	var cam := root.get_camera_3d()
	var sp := cam.unproject_position(term.to_global(Vector3(0.435 * 0.5 - 0.435 * 52.0 / 1024.0, -0.326 * 0.5 + 0.326 * 16.0 / 768.0, 0)))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = sp
	ev.global_position = sp
	root.push_input(ev)
	await _frames(5)
	print("start menu opened by mapped click: ", term.desktop._start_open, " cursor ", term.desktop.cursor)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await _frames(5)
	print("after esc: user ", term._user, " focus ", player._focus)
	await _frames(60)
	print("released: ", not player.is_focused())
	quit(0)
func _save(f: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SD + f)
func _frames(n: int) -> void:
	for i in n:
		await process_frame
