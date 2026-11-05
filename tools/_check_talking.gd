extends SceneTree
## TalkingCharacter: lip sync up close, the LOD and what it saves (windowed: headless loses mesh data).
##   godot --path . -s tools/_check_talking.gd -- [still.png]
##   1. spawn: a model loaded, freed and loaded again (as station staff are) fits its mouth once
##   2. close-up: a passenger 0.7 m from the camera says a line; the mouth opens with the voice and
##      shuts after it, it blinks, it is posed every frame, and its analyser bus lives only while it
##      speaks; a still of the open mouth
##   3. a passenger 30 m off is posed ~LOD_HZ times a second
##   4. 23 passengers (4 near, the rest 18-60 m off): their _process with the LOD off, then on
const MODELS := ["res://assets/characters/police_officer/police_officer.glb",
		"res://assets/characters/military_officer/military_officer.glb",
		"res://assets/characters/elderly_woman/elderly_woman.glb"]
const TALKER := "res://assets/characters/elderly_woman/elderly_woman.glb"
var ok := true

func _initialize() -> void:
	var still: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.75, 0.7)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.1, 0.09)
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	stage.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	stage.add_child(cam)
	cam.make_current()
	await process_frame

	# 1. Spawn twice: the second load is a new mesh, its fit comes from the cache.
	print("| model | load | add_child (+_ready) ms | new mesh |")
	print("|---|---|---|---|")
	for path: String in MODELS:
		var mesh_id := 0
		for pass_i in 2:
			var ps := load(path) as PackedScene
			var p := TalkingCharacter.new()
			p.model = ps
			var t0 := Time.get_ticks_usec()
			stage.add_child(p)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var id := p._face.mesh.get_instance_id() if p._face else 0
			print("| %s | %s | %.1f | %s |" % [path.get_file(), "first" if pass_i == 0 else "again", ms, "" if pass_i == 0 else str(id != mesh_id)])
			mesh_id = id
			p.free()
			ps = null
			for i in 3:
				await process_frame
	print("mouth fits kept: ", TalkingCharacter._mouth_fits.size())

	# 2. Close-up.
	var talker := TalkingCharacter.new()
	talker.model = load(TALKER)
	talker.solid = false
	stage.add_child(talker)
	var head := talker.global_position + Vector3(0, talker._head_h - 0.08, 0)
	cam.global_position = head + Vector3(0.0, 0.02, 0.7)
	cam.look_at(head)
	talker.look_at_target = cam
	for i in 30:
		await process_frame
	var buses_before := _voice_buses()
	talker.say("Is this the train for Kamenny Most?", 3.0)
	var bus_during := false
	var mouth_max := 0.0
	var posed := 0
	var frames := 0
	var lids_min := 1.0
	var best_shot := 0.0
	while talker.is_speaking():
		await process_frame
		frames += 1
		bus_during = bus_during or _voice_buses() == buses_before + 1
		var open := 0.0
		for k in range(1, TalkingCharacter.VISEMES.size()):
			open = maxf(open, _shape(talker, TalkingCharacter.VISEMES[k]))
		mouth_max = maxf(mouth_max, open)
		lids_min = minf(lids_min, _shape(talker, "lids_open_L"))
		if talker._lod_t == 0.0:                         # (reset each time the face and body are posed)
			posed += 1
		if still != "" and open > best_shot + 0.05 and frames > 10:
			best_shot = open
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(still)
	for i in 40:
		await process_frame
	var shut := 0.0
	for k in range(1, TalkingCharacter.VISEMES.size()):
		shut = maxf(shut, _shape(talker, TalkingCharacter.VISEMES[k]))
	for i in 200:                                       # a few seconds more for a blink
		await process_frame
		lids_min = minf(lids_min, _shape(talker, "lids_open_L"))
	_expect(mouth_max > 0.3, "mouth opens with the voice (max viseme %.2f)" % mouth_max)
	_expect(shut < 0.02, "mouth shut after the line (%.3f)" % shut)
	_expect(lids_min < 0.5, "it blinks (lids down to %.2f)" % lids_min)
	_expect(bus_during, "an analyser bus while speaking")
	_expect(_voice_buses() == buses_before, "no bus after the line (%d)" % _voice_buses())
	_expect(posed == frames, "posed every frame up close (%d of %d)" % [posed, frames])
	talker.free()

	# 3. Far off: posed about LOD_HZ times a second.
	var far := TalkingCharacter.new()
	far.model = load(TALKER)
	far.solid = false
	stage.add_child(far)
	far.position = Vector3(0, 0, -30)
	cam.global_position = Vector3(0, 1.6, 0)
	cam.look_at(Vector3(0, 1.4, -30))
	await process_frame
	var changes := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await process_frame
		if far._lod_t == 0.0:
			changes += 1
	_expect(changes >= 10 and changes <= 22, "30 m off: posed %d times in 2 s" % changes)
	far.free()

	# 4. The cost of 23.
	var crowd: Array[TalkingCharacter] = []
	var names := ["elderly_woman", "adult_male", "boy", "elderly_man", "old_woman", "vintage_detective", "woman_in_coat"]
	for i in 23:
		var c := TalkingCharacter.new()
		c.model = load("res://assets/characters/%s/%s.glb" % [names[i % names.size()], names[i % names.size()]])
		c.solid = false
		stage.add_child(c)
		var z := -2.0 - i * 0.6 if i < 4 else -18.0 - (i - 4) * 2.2
		c.position = Vector3((i % 3 - 1) * 0.8, 0, z)
		if i % 5 == 4:
			c.sit_now()
		crowd.append(c)
	cam.global_position = Vector3(0, 1.6, 1.0)
	cam.look_at(Vector3(0, 1.4, -10))
	for i in 60:
		await process_frame
	# Their _process alone, as at 60 fps (600 steps of 1/60 s).
	var res := {false: [], true: []}
	for round_i in 3:
		for lod_on in [false, true]:
			TalkingCharacter.lod = lod_on
			var t1 := Time.get_ticks_usec()
			for step in 600:
				for c in crowd:
					c._process(1.0 / 60.0)
			res[lod_on].append((Time.get_ticks_usec() - t1) / 1000.0 / 600.0)
			await process_frame
	print("23 passengers (4 near, 19 at 18-60 m), ms per 60 fps frame, 3 rounds:")
	print("  their _process:       LOD off %s  on %s" % [_ms(res[false]), _ms(res[true])])
	print("  voice buses while silent: %d" % _voice_buses())
	TalkingCharacter.lod = true
	print("TALKING ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _ms(a: Array) -> String:
	return " ".join(a.map(func(v: float) -> String: return "%.2f" % v))

func _shape(t: TalkingCharacter, name: String) -> float:
	return t._face.get_blend_shape_value(t._shape[name]) if t._shape.has(name) else 0.0

func _voice_buses() -> int:
	var n := 0
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i).begins_with("Voice_"):
			n += 1
	return n

func _expect(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	ok = ok and cond
