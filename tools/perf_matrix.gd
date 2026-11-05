extends SceneTree
## Toggles one rendering feature at a time in two views and reports frame / GPU / CPU-render ms and
## draw calls, to see what each feature costs.
##   godot --path . -s tools/perf_matrix.gd -- [width] [height]

const VIEWS := [
	["saloon", Vector3(-1.5, 3.0, 0.2), Vector3(-14.0, 2.7, 0.0), false],
	["running_out", Vector3(-30.0, 4.0, -13.0), Vector3(-50.0, 2.0, 0.0), true],
]

var world: Node3D
var vp_rid: RID

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var w := int(args[0]) if args.size() > 0 else 1920
	var h := int(args[1]) if args.size() > 1 else 1080
	DisplayServer.window_set_size(Vector2i(w, h))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var j: Node = world.get_node("Journey")
	j.set_physics_process(false)
	var player: Node = world.get_node("Player")
	player.set_physics_process(false)
	var cam := Camera3D.new()
	cam.far = 9000
	world.add_child(cam)
	vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	await _frames(30)
	player.get_node("HUD").visible = false
	cam.make_current()
	await _frames(400)
	var env: Environment = (world.find_child("WorldEnvironment", true, false) as WorldEnvironment).environment
	var moon := world.find_child("Moonlight", true, false) as DirectionalLight3D
	var omnis: Array = world.find_children("*", "OmniLight3D", true, false) + world.find_children("*", "SpotLight3D", true, false)
	for v: Array in VIEWS:
		if v[3]:
			j.call("warp_running", 4100.0)
			j.set_physics_process(true)
		cam.global_position = v[1]
		cam.look_at(v[2])
		await _frames(100)
		print("== ", v[0])
		await _row("all on")
		moon.shadow_enabled = false
		await _row("no moon shadow")
		moon.shadow_enabled = true
		var sh := []
		for l in omnis:
			sh.append(l.shadow_enabled)
			l.shadow_enabled = false
		await _row("no omni shadows")
		for i in omnis.size():
			omnis[i].shadow_enabled = sh[i]
		env.ssao_enabled = false
		await _row("no SSAO")
		env.ssao_enabled = true
		var ssil: bool = env.ssil_enabled
		env.ssil_enabled = false
		await _row("no SSIL")
		env.ssil_enabled = ssil
		var glow: bool = env.glow_enabled
		env.glow_enabled = false
		await _row("no glow")
		env.glow_enabled = glow
		var vf: bool = env.volumetric_fog_enabled
		env.volumetric_fog_enabled = false
		await _row("no vol. fog (was %s)" % vf)
		env.volumetric_fog_enabled = vf
		var snow := world.find_child("Snowfall", true, false) as GPUParticles3D
		if snow:
			snow.visible = false
			await _row("no snowfall")
			snow.visible = true
		(world.get_node("Scenery") as Node3D).visible = false
		await _row("no scenery")
		(world.get_node("Scenery") as Node3D).visible = true
		var life := world.get_node_or_null("WorldLife") as Node3D
		if life:
			life.visible = false
			await _row("no world life")
			life.visible = true
		var pax := world.get_node_or_null("Passengers") as Node3D
		if pax:
			pax.visible = false
			await _row("no passengers")
			pax.visible = true
		RenderingServer.viewport_set_scaling_3d_scale(vp_rid, 0.75)
		await _row("3D scale 0.75")
		RenderingServer.viewport_set_scaling_3d_scale(vp_rid, 1.0)
	print("ssao=%s ssil=%s sdfgi=%s glow=%s volfog=%s ssr=%s msaa=%s" % [env.ssao_enabled, env.ssil_enabled, env.sdfgi_enabled,
			env.glow_enabled, env.volumetric_fog_enabled, env.ssr_enabled, root.msaa_3d])
	quit(0)

func _row(label: String) -> void:
	await _frames(25)
	var n := 120
	var t0 := Time.get_ticks_usec()
	var gpu := 0.0
	var cpu := 0.0
	var draws := 0.0
	for i in n:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	print("  %-22s frame %6.2f  gpu %6.2f  cpu_rnd %6.2f  draws %6d" % [label, float(Time.get_ticks_usec() - t0) / 1000.0 / n,
			gpu / n, cpu / n, int(draws / n)])

func _frames(n: int) -> void:
	for i in n:
		await process_frame
