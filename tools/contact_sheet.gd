extends SceneTree
## Renders every prop (prefab scenes and glTF models under the given folders) on a neutral studio
## background and composes labelled contact sheets, for reviewing materials and textures.
##   godot --path . -s tools/contact_sheet.gd -- <out_dir> <folder> [<folder> ...]

var CELL := 320
const COLS := 6

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	if OS.has_environment("SHEET_CELL"):
		CELL = int(OS.get_environment("SHEET_CELL"))
	var files: Array[String] = []
	for i in range(1, args.size()):
		_collect(args[i], files)
	files.sort()
	root.size = Vector2i(CELL, CELL)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.37, 0.39)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.6)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.6
	root.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 35
	root.add_child(cam)
	cam.make_current()
	var shots: Array = []
	# Warm-up: the very first capture comes back empty.
	for k in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	for f in files:
		var res = load(f)
		if not (res is PackedScene):
			continue
		var n: Node = (res as PackedScene).instantiate()
		if not (n is Node3D):
			n.free()
			continue
		root.add_child(n)
		var ab := _aabb(n as Node3D)
		if ab.size.length() < 0.001:
			n.queue_free()
			continue
		var c := ab.get_center()
		var r := ab.size.length() * 0.5
		var dir := Vector3(0.75, 0.45, -1.0).normalized()      # props face -Z
		cam.global_position = c + dir * (r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05)
		cam.look_at(c)
		cam.near = maxf(0.005, r * 0.02)
		for k in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var full := root.get_texture().get_image()
		var side := mini(full.get_width(), full.get_height())
		var img := full.get_region(Rect2i((full.get_width() - side) / 2, (full.get_height() - side) / 2, side, side))
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		shots.append([f.get_file().get_basename() + "  %.2fm" % ab.size[ab.size.max_axis_index()], img])
		n.queue_free()
		await process_frame
	# Compose sheets.
	var per := COLS * 4
	var sheet_i := 0
	for start in range(0, shots.size(), per):
		var count := mini(per, shots.size() - start)
		var rows := int(ceil(float(count) / COLS))
		var sheet := Image.create(COLS * CELL, rows * (CELL + 22), false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.1, 0.1, 0.1))
		for i in count:
			var s: Array = shots[start + i]
			var img: Image = s[1]
			img.convert(Image.FORMAT_RGB8)
			var x := (i % COLS) * CELL
			var y := (i / COLS) * (CELL + 22)
			sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(x, y + 22))
		sheet.save_png(out_dir.path_join("sheet_%d.png" % sheet_i))
		var names := PackedStringArray()
		for i in count:
			names.append("%d: %s" % [i, shots[start + i][0]])
		var fa := FileAccess.open(out_dir.path_join("sheet_%d.txt" % sheet_i), FileAccess.WRITE)
		fa.store_string("\n".join(names))
		sheet_i += 1
	print("rendered ", shots.size(), " props into ", sheet_i, " sheets")
	quit(0)

func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tscn") or f.ends_with(".gltf") or f.ends_with(".glb"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)

func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
