extends SceneTree
# Flicker (with a switch thrown mid-way), reduced flicker, giggle and scream placement, no stacking,
# and the ghost pilot's three beats with material and cleanup checks.
func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	var j: Node = world.get_node("Journey")
	j.call("warp_running", 2000.0)
	var ts := root.get_node("TrainState")
	var hd: HorrorDirector = get_first_node_in_group("horror")
	var ghost: GhostStory = get_first_node_in_group("ghost_story")
	hd.enabled = false
	ghost.intro_at = 99.0
	var player: Node3D = world.get_node("Player")
	player.global_position = Vector3(-1.0, 1.45, 0.0)
	for i in 10: await process_frame
	# --- flicker with a switch thrown mid-way
	var train := world.get_node("Train")
	var lamps := {}
	for l: Light3D in train.find_children("*", "Light3D", true, false):
		if l.global_position.distance_to(player.global_position) < 9.0 and not l is DirectionalLight3D:
			lamps[l] = [l.light_energy, l.visible]
	print("lamps near: ", lamps.size())
	var sw: LightSwitch = null
	for s in train.get_node("PassengerCar").find_children("*", "", true, false):
		if s is LightSwitch and not s.lamps.is_empty():
			sw = s
			break
	hd.trigger("flicker")
	var min_f := 1.0
	var t := 0.0
	var thrown := false
	while hd.active == "flicker" or t < 0.2:
		await process_frame
		t += root.get_process_delta_time()
		for l in lamps:
			if l.visible and lamps[l][0] > 0.0:
				min_f = minf(min_f, l.light_energy / lamps[l][0])
		if t > 0.8 and not thrown and sw:
			thrown = true
			sw.interact(null)            # the player switches the saloon lights off mid-flicker
			print("switch thrown: on=", sw.on)
		if t > 10.0: break
	var bad := 0
	for l in lamps:
		if not is_equal_approx(l.light_energy, lamps[l][0]):
			bad += 1
	print("FLICKER full: lasted %.2f s, deepest %.2f, energies restored %d/%d, switch still off: %s" % [t, min_f, lamps.size() - bad, lamps.size(), (not sw.on) if sw else "n/a"])
	if sw: sw.interact(null)
	# --- reduced
	hd.flicker_mode = HorrorDirector.FlickerMode.REDUCED
	await create_timer(3.0).timeout
	hd.trigger("flicker")
	min_f = 1.0
	t = 0.0
	while hd.active == "flicker" or t < 0.2:
		await process_frame
		t += root.get_process_delta_time()
		for l in lamps:
			if l.visible and lamps[l][0] > 0.0:
				min_f = minf(min_f, l.light_energy / lamps[l][0])
	print("FLICKER reduced: lasted %.2f s, deepest %.2f" % [t, min_f])
	hd.flicker_mode = HorrorDirector.FlickerMode.OFF
	print("FLICKER off -> trigger accepted but not started: ", hd.trigger("flicker"))
	await create_timer(0.5).timeout
	print("   active after off: '", hd.active, "'")
	hd.flicker_mode = HorrorDirector.FlickerMode.FULL
	# --- sounds and stacking
	await create_timer(1.0).timeout
	hd.trigger("giggle")
	hd.trigger("scream")
	await process_frame
	await process_frame
	var gp := hd.sound_position()
	print("GIGGLE at ", gp.snapped(Vector3.ONE*0.1), " dist ", "%.1f" % gp.distance_to(player.global_position), " active ", hd.active)
	var both := 0
	while hd.active != "":
		await process_frame
	print("after giggle, next active: ", hd.active)
	await process_frame
	await process_frame
	var sp := hd.sound_position()
	print("SCREAM at ", sp.snapped(Vector3.ONE*0.1), " dist ", "%.1f" % sp.distance_to(player.global_position), " active ", hd.active)
	var x0 := sp.x
	await create_timer(1.0).timeout
	print("scream drifted back by %.1f m in 1 s (train speed %.1f)" % [hd.sound_position().x - x0, ts.speed])
	while hd.active != "":
		await process_frame
	print("HISTORY ", hd.history)
	# --- ghost
	var some_pax: TalkingCharacter = null
	for b in world.get_node("Passengers").get_children():
		if b is TalkingCharacter: some_pax = b; break
	var before_mats := []
	for mi: MeshInstance3D in some_pax.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count(): before_mats.append(mi.get_active_material(s))
	ghost.intro_at = ts.clock
	await create_timer(1.0).timeout
	print("GHOST stage ", ghost.stage, " messages ", TerminalData.messages.size(), " last: ", TerminalData.messages.back().subject)
	while hd.active != "": await process_frame
	TerminalData.messages.back().read = true
	# Kevin in the sleeping car corridor looking toward its far end.
	player.global_position = Vector3(13.0, 1.45, -1.0)
	var cam := player.get_viewport().get_camera_3d()
	player.rotation.y = -PI * 0.5     # facing +X
	cam.rotation = Vector3.ZERO
	for i in 30: await process_frame
	print("camera forward ", (-cam.global_basis.z).snapped(Vector3.ONE*0.01), " at ", cam.global_position.snapped(Vector3.ONE*0.01))
	t = 0.0
	while ghost.stage != "shown" and t < 5.0:
		await process_frame
		t += root.get_process_delta_time()
	print("GHOST stage ", ghost.stage)
	var g := ghost.get_node_or_null("Apparition")
	if g:
		await create_timer(1.2).timeout
		var img := root.get_texture().get_image()
		img.save_png(OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://ghost.png")
		# her materials are her own; the shared ones untouched
		var shared: Node = load("res://assets/characters/vintage_woman/vintage_woman.glb").instantiate()
		var ok := true
		for mi: MeshInstance3D in shared.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as StandardMaterial3D
				if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: ok = false
		shared.free()
		print("shared materials untouched: ", ok)
		# walk toward her: she vanishes
		player.global_position = Vector3(19.5, 1.45, -1.0)
		t = 0.0
		while ghost.stage == "shown" and t < 5.0:
			await process_frame
			t += root.get_process_delta_time()
		print("GHOST after approach: stage ", ghost.stage, " apparition left: ", ghost.get_node_or_null("Apparition") != null and is_instance_valid(ghost.get_node_or_null("Apparition")))
		await process_frame
		var solids := 0
		for b in get_nodes_in_group("npc_solid"):
			if (b as Node3D).global_position.distance_to(ghost._spot()) < 0.5 and not b.get_child(0).disabled: solids += 1
		print("colliders left at her spot: ", solids)
	var after_mats := []
	for mi: MeshInstance3D in some_pax.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count(): after_mats.append(mi.get_active_material(s))
	print("ordinary passenger materials unchanged: ", before_mats == after_mats)
	print("can report to Mike: ", ghost.can_report(), " -> ", ghost.mike_answer())
	ghost.follow_up_after = 0.2
	await create_timer(6.0).timeout
	print("GHOST final stage ", ghost.stage, " last message: ", TerminalData.messages.back().subject)
	quit(0)
