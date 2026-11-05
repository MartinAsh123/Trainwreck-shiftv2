extends SceneTree
# Stills of Kevin's clipboard (with a strange incident written in), his wristwatch, and the wall
# clocks in a saloon and a corridor, through his own eyes.  -- <out_dir>
var world: Node3D
var player: CharacterBody3D
var head: Node3D
var out: String
var n := 0

func _look(at: Vector3, look: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	var d := look - head.global_position
	player.rotation.y = atan2(-d.x, -d.z)
	head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())

func _shot(tag: String, frames := 12) -> void:
	for i in frames: await process_frame
	root.get_texture().get_image().save_png(out + "/k%02d_%s.png" % [n, tag])
	n += 1

func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	world.get_node("Journey").call("warp_running", 6600.0)
	(world.get_node("Passengers") as Passengers)._on_departing("")
	player = world.get_node("Player")
	head = player.get_node("Head")
	var h: HauntDirector = get_first_node_in_group("haunt")
	h.first_start = 0.0
	h._next_start = 0.0
	while h.stage != "signs":
		await process_frame
	h.known = true
	for i in 10: await physics_frame
	# The clipboard, in the saloon of coach two.
	_look(Vector3(-2.0, 1.45, 0.0), Vector3(3.0, 2.6, 0.0))
	Clipboard.of(world).toggle()
	await _shot("clipboard", 40)
	Clipboard.of(world).toggle()
	await _shot("away", 30)
	# The watch.
	Wristwatch.of(world).shown = true
	await _shot("watch", 40)
	# (the same eye, zoomed in on the watch)
	var w := Wristwatch.of(world)
	var eye: Camera3D = player.get_node("Head/Camera")
	var zoom := Camera3D.new()
	zoom.fov = 16
	zoom.near = 0.01
	world.add_child(zoom)
	zoom.global_transform = eye.global_transform
	zoom.look_at(w._face.global_position)
	zoom.make_current()
	await _shot("watch_zoom", 6)
	eye.make_current()
	zoom.queue_free()
	Wristwatch.of(world).shown = false
	await _shot("watch_away", 30)
	# The wall clocks: coach two's rear end, the sleeping car's corridor.
	_look(Vector3(-2.5, 1.45, 0.1), Vector3(-6.0, 3.3, -0.5))
	await _shot("clock_saloon", 20)
	_look(Vector3(-4.6, 1.45, 0.0), Vector3(-6.0, 3.42, -0.78))
	await _shot("clock_saloon_close", 20)
	_look(Vector3(16.0, 1.45, -1.0), Vector3(11.5, 3.4, -1.0))
	await _shot("clock_corridor", 20)
	_look(Vector3(-52.6, 1.45, 0.0), Vector3(-58.7, 3.3, 0.3))
	await _shot("clock_mail", 20)
	quit(0)
