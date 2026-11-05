extends SceneTree
## Look development for the anomalies' monster face and crawl, in a dark room with the train's kind of
## light: stills only.
##   godot --path . -s tools/_look_monster.gd -- <out_dir> face|side|pose|crawl|hand [slug ...]
## With no slug, every anomaly. `pose` prints the surfaces and materials.

const ANOM := "res://assets/anomalies/"

var out := ""
var cam: Camera3D

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var what: String = a[1]
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var slugs: Array = a.slice(2)
	if slugs.is_empty():
		for d in DirAccess.get_directories_at(ANOM):
			slugs.append(d)
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.012, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.42, 0.34)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.3, 2.4, 0.9)
	lamp.light_color = Color(1.0, 0.82, 0.6)
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	w.add_child(lamp)
	cam = Camera3D.new()
	cam.fov = 75.0
	w.add_child(cam)
	cam.make_current()
	for slug: String in slugs:
		await _one(w, slug, what)
	quit(0)

func _one(w: Node3D, slug: String, what: String) -> void:
	var b := TalkingCharacter.new()
	b.model = load(ANOM + "%s/%s.glb" % [slug, slug]) as PackedScene
	w.add_child(b)
	await process_frame
	await process_frame
	var base := slug
	var kind := ""
	for k in ["long_neck", "third_eye", "black_eyes", "grey_marks", "six_fingers", "tail", "cyclops", "faceless"]:
		if slug.ends_with("_" + k):
			kind = k
			base = slug.trim_suffix("_" + k)
	print(slug, " base ", base, " kind ", kind, " face ", b._face != null)
	if what == "pose":
		var m := b._face.mesh
		for s in m.get_surface_count():
			var sm := m.surface_get_material(s)
			if sm is StandardMaterial3D:
				var st := sm as StandardMaterial3D
				print("  ", s, " ", st.resource_name, " tex ", st.albedo_texture != null, " nrm ", st.normal_enabled and st.normal_texture != null,
						" rough ", st.roughness, " rtex ", st.roughness_texture != null, " transp ", st.transparency, " cull ", st.cull_mode, " col ", st.albedo_color)
			else:
				print("  ", s, " ", sm)
		print("  meshes: ", b.find_children("*", "MeshInstance3D", true, false).size())
		b.queue_free()
		await process_frame
		return
	var mf := MonsterFace.attach(b, base, kind)
	var f: Dictionary = FaceMarks.MARKS.get(base, {})
	var e0 := MonsterFace._v(f.eyes[0])
	var e1 := MonsterFace._v(f.eyes[1])
	var c := ((e0 + e1) * 0.5).lerp(MonsterFace._v(f.mouth), 0.72)
	if kind == "long_neck":
		c.y += MonsterFace.LONG_NECK
	var at := b.global_transform * c
	mf.amount = 1.0
	mf.gape = 1.0
	mf.stare_at = cam
	match what:
		"smile":
			mf.amount = 0.55
			mf.gape = 0.0
			mf.smile = 1.0
			cam.fov = 75.0
			cam.global_position = at + Vector3(0, 0.02, 0.55)
			cam.look_at(at + Vector3(0, -0.01, 0))
		"face":
			cam.fov = 100.0
			cam.global_position = at + Vector3(0, 0.02, 0.2)
			cam.look_at(at + Vector3(0, -0.01, 0))
		"side":
			cam.fov = 60.0
			cam.global_position = at + Vector3(0.42, 0.02, 0.62)
			cam.look_at(at + Vector3(0, -0.02, 0))
		"crawl":
			b.crawl = 1.0
			b.walk_speed = 6.5
			var fill := OmniLight3D.new()
			fill.position = Vector3(1.0, 1.6, 2.2)
			fill.light_energy = 3.0
			fill.omni_range = 7.0
			w.add_child(fill)
			cam.fov = 45.0
			for v: Array in [["side", Vector3(2.4, 0.55, 0.0), Vector3(0, 0.45, -0.1)], ["front", Vector3(0.25, 0.45, 2.4), Vector3(0, 0.4, 0)], ["rear", Vector3(-0.3, 0.7, -2.4), Vector3(0, 0.4, 0)]]:
				cam.global_position = v[1]
				cam.look_at(v[2])
				for i in 7:
					await process_frame
				RenderingServer.force_draw()
				await process_frame
				root.get_texture().get_image().save_png(out.path_join("crawl_%s_%s.png" % [v[0], slug]))
			fill.queue_free()
			b.queue_free()
			await process_frame
			return
		"hand":
			b.grab = 1.0
			b.grab_l = at + Vector3(0.235, -0.15, 0.3)
			b.grab_r = at + Vector3(-0.235, -0.15, 0.3)
			cam.fov = 100.0
			cam.global_position = at + Vector3(0, 0.0, 0.5)
			cam.look_at(at)
	for i in 8:
		await process_frame
	RenderingServer.force_draw()
	await process_frame
	root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [what, slug]))
	b.queue_free()
	await process_frame
