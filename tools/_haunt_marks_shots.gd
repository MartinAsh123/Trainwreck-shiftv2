extends SceneTree
# Stills of a ghost's marks (frost, breath) and the breakdown props (service room tools, USB stick,
# the pulled emergency brake).  -- <out_dir>
var world: Node3D
var cam: Camera3D
var out: String
var n := 0
func _shot(at: Vector3, look: Vector3, tag: String, fov := 62.0, frames := 8) -> void:
	cam.fov = fov
	cam.global_position = at
	cam.look_at(look)
	for i in frames: await process_frame
	root.get_texture().get_image().save_png(out + "/m%02d_%s.png" % [n, tag])
	n += 1

func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	world.get_node("Journey").call("warp_running", 2000.0)
	var player: Node3D = world.get_node("Player")
	player.set_physics_process(false)
	player.get_node("HUD").visible = false
	var h: HauntDirector = get_first_node_in_group("haunt")
	get_first_node_in_group("horror").enabled = false
	h.first_start = 1.0
	h._next_start = 1.0
	h.flash_gap = Vector2(999, 999)
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	duty.next_patrol = 99.0
	duty.rest_enabled = false
	cam = Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	while h.stage != "signs":
		await process_frame
	var g = h.ghost
	var b: TalkingCharacter = g.body
	h._frost_k = 0.99
	var face := h._face_of(b)
	player.global_position = Vector3(b.global_position.x, 1.45, 0.0)
	for i in 5: await process_frame
	print("FROST ", h._frost, " a=", h._frost.modulate.a if h._frost else -1.0, " at ", h._frost.global_position if h._frost else Vector3.ZERO, " ghost ", b.global_position, " face ", face, " fwd ", b.global_basis.z)
	var gp := b.global_position
	var aisle := Vector3(gp.x, 0, 0) - Vector3(gp.x, 0, gp.z)
	await _shot(gp + aisle.normalized() * 1.2 + Vector3(0.6, 2.3, 0), gp + Vector3(0, 0.5, 0), "frost_top", 70.0, 30)
	await _shot(gp + aisle.normalized() * 1.0 + Vector3(-1.4, 1.6, 0), gp + Vector3(0, 0.9, 0), "frost_side", 65.0, 10)
	h._puff_t = 0.0
	var fwd := b.global_basis.z
	await _shot(face + fwd * 0.8 + aisle.normalized() * 0.4 + Vector3(0, 0.05, 0), face + fwd * 0.2, "breath", 55.0, 30)
	h._puff_t = 99.0
	h._puff(b)
	await _shot(face + fwd * 0.8 + aisle.normalized() * 0.4 + Vector3(0, 0.05, 0), face + fwd * 0.2, "breath_b", 55.0, 45)
	h._puff(b)
	await _shot(face + fwd * 1.6 + aisle.normalized() * 1.1 + Vector3(0, 0.2, 0), face + fwd * 0.2, "breath_far", 55.0, 40)
	var pli: Node3D = h._items["plunger"]
	var pl := pli.global_position
	var svc := root.find_child("ServiceRoom", true, false) as Node3D
	var dr := svc.get_node("Drawers") as Node3D
	var plf := svc.get_node("Plunger") as Node3D
	await _shot(plf.global_transform * Vector3(0.0, 1.62, -0.6), pl + Vector3(0, 0.3, 0), "plunger", 70.0)
	var sc: Vector3 = h._items["screwdriver"].global_position
	await _shot(sc + Vector3(0.0, 0.6, 0.0) - dr.global_basis.z * 0.6, sc, "screwdriver", 60.0)
	var us: Vector3 = h._items["usb"].global_position
	var ns := root.find_child("InspectorRoom", true, false).get_node("Nightstand") as Node3D
	await _shot(ns.global_transform * Vector3(0.1, 1.05, -0.55), us, "usb", 50.0)
	# The emergency brake, pulled.
	h._can_brake()
	h.incident = "ebrake"
	h._ebrake_begin()
	await create_timer(0.5).timeout
	var bk: Node3D = h._brake
	print("BRAKE ", bk.get_path(), " model euler ", (bk.get_child(0) as Node3D).global_basis.get_euler(), " incident ", h.incident)
	var bp := bk.global_position
	var into := Vector3(-signf(bp.x - h.car.global_position.x), 0, 0)
	await _shot(bp + into * 1.1 + Vector3(0, -0.05, -0.35), bp + Vector3(0, -0.2, 0), "ebrake", 50.0)
	await create_timer(0.4).timeout
	await _shot(bp + into * 1.1 + Vector3(0, -0.05, -0.35), bp + Vector3(0, -0.2, 0), "ebrake_b", 50.0)
	await _shot(bp + into * 0.3 + Vector3(0, -0.05, -0.75), bp + into * 0.12 + Vector3(0, -0.12, 0), "ebrake_side", 50.0)
	h._throw_brake(false)
	await create_timer(0.6).timeout
	await _shot(bp + into * 0.3 + Vector3(0, -0.05, -0.75), bp + into * 0.12 + Vector3(0, -0.12, 0), "ebrake_side_reset", 50.0)
	await _shot(bp + into * 1.1 + Vector3(0, -0.05, -0.35), bp + Vector3(0, -0.2, 0), "ebrake_reset", 50.0)
	quit(0)
