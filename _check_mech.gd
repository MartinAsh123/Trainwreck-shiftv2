extends SceneTree
const SD := "C:/Users/marti/AppData/Local/Temp/claude/C--Users-marti-AppData-Roaming-Claude-scratch-workspaces-3e58b957-222a-49cc-a358-7d825abce1af-88de5f8e-6168-4768-8e06-65da1c67b280-scratch-2026-09-26-7f055c/f101d24e-3f93-42ca-aaee-c6355cbfddfa/scratchpad/"
var world: Node3D
var player: CharacterBody3D
var cam: Camera3D

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	world = load("res://scenes/train/passenger_car_walk.tscn").instantiate()
	root.add_child(world)
	player = world.get_node("Player")
	await process_frame
	await process_frame
	cam = Camera3D.new()
	world.add_child(cam)
	var ts := root.get_node("TrainState")
	var car: Node3D = world.get_node("Train/PassengerCar")
	# — sliding door: open, then close onto a player standing in the doorway —
	var inner: TrainDoor = car.get_node("Generated/Anchors/Doors/InnerDoor_WC/SlidingDoor")
	print("inner prompt: ", inner.get_prompt())
	inner.interact()
	await _secs(1.2)
	print("inner open after 1.2 s: ", inner.is_open(), " t=", inner._t)
	player.global_position = Vector3(5.65, 1.42, 0.05)
	player.velocity = Vector3.ZERO
	await _secs(0.2)
	inner.interact()   # close onto the player
	await _secs(1.2)
	print("closing onto player -> reopened: ", inner.is_open(), " t=", snappedf(inner._t, 0.01), " player z ", snappedf(player.global_position.z, 0.01))
	player.global_position = Vector3(3.0, 1.42, 0.0)
	await _secs(0.2)
	inner.interact()
	await _secs(1.2)
	print("closes once clear: ", not inner.is_open(), " t=", snappedf(inner._t, 0.01))
	# — exterior door locked while moving —
	var exits: Array = world.get_node("Train").call("exterior_doors")
	print("exterior doors: ", exits.size())
	var ex: TrainDoor = exits[0]
	ts.speed = 12.0
	print("exit while moving: '", ex.interact(), "'")
	ts.speed = 0.0
	print("exit while stopped: '", ex.interact(), "' ")
	await _secs(1.4)
	print("exit open: ", ex.is_open())
	ts.departing.emit("Test")
	await _secs(1.4)
	print("exit closed after departing signal: ", not ex.is_open())
	# — toilet lock —
	var wc: TrainDoor = null
	for d in car.find_children("*", "TrainDoor", true, false):
		if d.door_name == "W.C. door":
			wc = d
	var lock: ToiletLock = wc.lock_node
	print("lock prompt: ", lock.get_prompt())
	lock.interact()
	print("W.C. door when engaged: '", wc.interact(), "' prompt: ", wc.get_prompt())
	lock.interact()
	print("W.C. door when vacant: '", wc.interact(), "'")
	await _secs(1.4)
	print("W.C. open: ", wc.is_open())
	await _shot_door(wc, "mech_wc_open.png")
	wc.interact()
	await _secs(1.4)
	# — curtains —
	var sets := car.find_children("CurtainSet", "", true, false)
	print("curtain sets in car 2: ", sets.size())
	var cs: CurtainSet = sets[3]
	var cn: Node3D = cs.get_parent()
	cam.global_transform = Transform3D(Basis.looking_at(cn.global_basis.z, Vector3.UP), cn.global_position - cn.global_basis.z * 1.25 + Vector3(0, -0.05, 0))
	cam.fov = 60
	cam.make_current()
	await _secs(0.3)
	await _save("mech_curt_0.png")
	cs.interact()
	await _secs(0.55)
	await _save("mech_curt_mid.png")
	await _secs(1.2)
	print("curtains closed: ", cs.is_closed(), " prompt: ", cs.get_prompt())
	await _save("mech_curt_1.png")
	cs.interact()
	await _secs(1.6)
	await _save("mech_curt_back.png")
	# — aiming: player looks at the curtain area —
	cam.current = false
	(player.get_node("Head/Camera") as Camera3D).make_current()
	player.global_position = cn.global_position - cn.global_basis.z * 1.1 - Vector3(0, 1.45, 0)
	player.global_position.y = 1.42
	player.look_at(player.global_position + cn.global_basis.z * Vector3(1, 0, 1), Vector3.UP)
	(player.get_node("Head") as Node3D).rotation.x = -0.05
	await _secs(0.3)
	var tgt = player._find_target()
	print("aim target: ", tgt.name if tgt else "none", " prompt: ", player._hud_prompt.text)
	await _save("mech_hud.png")
	# — crouch —
	var shape := (player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
	Input.action_press("fp_crouch")
	await _secs(0.6)
	print("crouched height ", snappedf(shape.height, 0.01), " eye ", snappedf((player.get_node("Head") as Node3D).position.y, 0.01))
	Input.action_release("fp_crouch")
	await _secs(0.6)
	print("stood height ", snappedf(shape.height, 0.01))
	# — locomotive running gear at three positions —
	var loco: Node3D = world.get_node("Train/Locomotive6")
	cam.make_current()
	cam.fov = 45
	var lx := loco.global_position.x
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0.05, -1), Vector3.UP), Vector3(lx - 16.4, 1.0, 6.6))
	for i in 3:
		ts.distance = i * 0.8
		await _secs(0.15)
		await _save("mech_loco_%d.png" % i)
	quit(0)

func _shot_door(d: TrainDoor, file: String) -> void:
	var m: Node3D = d.get_parent()
	cam.global_transform = Transform3D(Basis.looking_at(m.global_basis.z, Vector3.UP), m.global_position - m.global_basis.z * 2.0 + Vector3(0, 1.3, 0))
	cam.fov = 70
	cam.make_current()
	await _secs(0.2)
	await _save(file)

func _secs(s: float) -> void:
	var n := int(s * 60.0)
	for i in n:
		await physics_frame

func _save(file: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SD + file)
