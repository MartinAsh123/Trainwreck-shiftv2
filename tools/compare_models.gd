extends SceneTree
## Before / after: renders pairs of models side by side under the same studio light.
##   godot --path . -s tools/compare_models.gd -- <out.png> <before.glb> <after.glb> [<before> <after> ...]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.33, 0.34, 0.36)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.7
	key.shadow_enabled = true
	root.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_energy = 0.8
	fill.omni_range = 30
	root.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	cam.make_current()
	var tiles: Array[Image] = []
	# Warm-up: the very first capture comes back empty.
	for k in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	for i in range(1, args.size()):
		var n: Node3D = (load(args[i]) as PackedScene).instantiate()
		root.add_child(n)
		var ab := AABB()
		var first := true
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			var b := mi.global_transform * mi.get_aabb()
			ab = b if first else ab.merge(b)
			first = false
		print(args[i], " aabb ", ab)
		var c := ab.get_center()
		var r := ab.size.length() * 0.5
		var dir := Vector3(0.7, 0.4, 1.0).normalized()
		cam.global_position = c + dir * (r / tan(deg_to_rad(cam.fov * 0.5)) * 1.0)
		cam.look_at(c)
		fill.global_position = c + Vector3(-r * 3, r * 2, r * 3)
		for k in 25:
			await process_frame
		await RenderingServer.frame_post_draw
		var full := root.get_texture().get_image()
		var side := mini(full.get_width(), full.get_height())
		var img := full.get_region(Rect2i((full.get_width() - side) / 2, (full.get_height() - side) / 2, side, side))
		img.resize(600, 600, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		tiles.append(img)
		n.queue_free()
		await process_frame
	var pairs := tiles.size() / 2
	var sheet := Image.create(1200, 600 * pairs, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 600, 600), Vector2i((i % 2) * 600, (i / 2) * 600))
	sheet.save_png(out)
	quit(0)
