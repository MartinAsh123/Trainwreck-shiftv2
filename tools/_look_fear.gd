extends SceneTree
## Look development for a frightened passenger (TalkingCharacter.fear, FrenzyPanic), in a dark room
## with the train's kind of light: stills only, the thing it shrinks from low on the floor ahead.
##   godot --path . -s tools/_look_fear.gd -- <out_dir> stand|seat [slug ...]

const DIR := "res://assets/characters/"

var out := ""
var cam: Camera3D

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var what: String = a[1]
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var slugs: Array = a.slice(2)
	if slugs.is_empty():
		slugs = ["man_in_coat", "elderly_woman_2", "boy"]
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.045, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.52, 0.44)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.6, 2.6, 1.6)
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 2.2
	lamp.omni_range = 8.0
	w.add_child(lamp)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor.mesh = pm
	w.add_child(floor)
	cam = Camera3D.new()
	cam.fov = 40.0
	w.add_child(cam)
	cam.make_current()
	for slug: String in slugs:
		await _one(w, slug, what)
	quit(0)

func _one(w: Node3D, slug: String, what: String) -> void:
	var b := TalkingCharacter.new()
	b.model = load(DIR + "%s/%s.glb" % [slug, slug]) as PackedScene
	b.solid = false
	b.look_range = 0.0
	w.add_child(b)
	if what == "seat":
		b.sit_now()
	await process_frame
	var thing := Vector3(0.5, 0.45, 1.6)          # (where a crawling one's head would be)
	for k: Array in [["calm", 0.0], ["afraid", 1.0]]:
		b.fear = k[1]
		b.fear_at = thing
		if k[1] > 0.0:
			b.set_expression("surprised", 1.0)
		for v: Array in [["front", Vector3(0.9, 1.25, 3.2)], ["side", Vector3(3.2, 1.2, 0.4)]]:
			cam.global_position = v[1]
			cam.look_at(Vector3(0, 0.95 if what == "stand" else 0.75, 0))
			for i in 30:
				await process_frame
			RenderingServer.force_draw()
			await process_frame
			root.get_texture().get_image().save_png(out.path_join("%s_%s_%s_%s.png" % [what, slug, k[0], v[0]]))
	b.queue_free()
	await process_frame
