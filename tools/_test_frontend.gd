extends SceneTree
## Front end: main menu -> Start shift -> Esc pauses -> settings change FOV/volume/subtitles live ->
## Esc back -> resume -> pause -> back to the main menu. Run windowed (screenshots):
##   godot_console.exe --path . -s tools/_test_frontend.gd -- <shot dir>

var _out := ""
var _fails := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	root.size = Vector2i(1920, 1080)
	_run.call_deferred()

func _run() -> void:
	var st: Node = root.get_node("Settings")
	var fov0: float = st.fov
	var vol0: float = st.master_volume
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await _frames(90)
	_check(current_scene.scene_file_path == "res://scenes/ui/main_menu.tscn", "menu is the scene")
	await _shot("fe_1_menu.png")
	current_scene.call("_open_settings")
	await _frames(20)
	await _shot("fe_2_menu_settings.png")
	current_scene.call("_close_settings")
	current_scene.call("_start", false)
	var t := 0
	while current_scene == null or current_scene.scene_file_path != "res://scenes/game/journey.tscn":
		await process_frame
		t += 1
		if t > 3000:
			_check(false, "journey loaded")
			quit(1)
			return
	await _frames(240)
	var player := current_scene.find_child("Player") as FPController
	_check(player != null, "player in journey")
	var cam := player.get_node("Head/Camera") as Camera3D
	_check(is_equal_approx(cam.fov, fov0), "camera fov follows Settings (%.0f)" % cam.fov)
	await _shot("fe_3_journey.png")
	_esc()
	await _frames(10)
	var pm := root.get_node("PauseMenu") as PauseMenu
	_check(paused and pm.is_open(), "Esc pauses")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse free while paused")
	await _shot("fe_4_pause.png")
	pm.call("_open_settings")
	await _frames(5)
	st.set_value("fov", 100.0)
	st.set_value("master_volume", 0.5)
	st.set_value("subtitle_size", 40)
	Subtitles.show_line(current_scene, "Mike", "Mind the gap, Kevin.", 30.0)
	await _frames(20)
	_check(is_equal_approx(cam.fov, 100.0), "FOV changes live while paused")
	var mi := AudioServer.get_bus_index("Master")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(mi), 0.25), "master bus at 0.5² linear")
	await _shot("fe_5_pause_settings.png")
	_esc()
	await _frames(5)
	_check(pm.is_open() and not pm.get("_settings").visible, "Esc closes settings back to the pause card")
	_esc()
	await _frames(5)
	_check(not paused and not pm.is_open(), "Esc resumes")
	player.add_trauma(0.8)
	await _frames(3)
	_check(cam.position.length() > 0.001, "trauma shakes the camera")
	await _shot("fe_6_fov100.png")
	await _frames(120)
	_check(player.get_trauma() < 0.8, "trauma decays")
	_esc()
	await _frames(5)
	pm.call("_to_menu")
	await _frames(60)
	_check(current_scene.scene_file_path == "res://scenes/ui/main_menu.tscn" and not paused, "back to the main menu, unpaused")
	await _shot("fe_7_back_menu.png")
	# Leave the player's settings as they were.
	st.set_value("fov", fov0)
	st.set_value("master_volume", vol0)
	st.set_value("subtitle_size", 24)
	print("FRONTEND ", "OK" if _fails == 0 else "FAILED %d" % _fails)
	quit(0 if _fails == 0 else 1)

func _esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1

func _shot(f: String) -> void:
	if _out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(f))

func _frames(n: int) -> void:
	for i in n:
		await process_frame
