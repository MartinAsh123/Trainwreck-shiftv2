extends SceneTree
# Mike lying down on his bunk, sleeping and getting up: frames from the foot of the bed and from the
# room side, with and without the blanket, and how high his body is above the mattress.
#   -- <out_dir> [noblanket]
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var hide_blanket := OS.get_cmdline_user_args().has("noblanket")
	DisplayServer.window_set_size(Vector2i(960, 540))
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	world.get_node("Journey").call("warp_running", 2000.0)
	var player: Node3D = world.get_node("Player")
	player.global_position = Vector3(-31.0, 1.45, 0.6)
	player.get_node("HUD").visible = false
	var hd: HorrorDirector = get_first_node_in_group("horror")
	hd.enabled = false
	var duty: MikeDuty = get_first_node_in_group("mike_duty")
	var ts := root.get_node("TrainState")
	duty.next_patrol = 99.0
	duty.rest_start = ts.clock - 0.01
	duty.rest_latest = ts.clock + 1.0
	duty.rest_minutes = 0.6
	var bed: Node3D = duty._bed
	var cam := Camera3D.new()
	cam.fov = 60
	world.add_child(cam)
	cam.make_current()
	var views := [
		[bed.global_position + Vector3(1.25, 2.0, -0.5), bed.global_position + Vector3(0, 0.6, 0.25)],     # high, from the room corner by the door
		[bed.global_position + Vector3(1.9, 1.35, 0.35), bed.global_position + Vector3(0, 0.55, 0.35)],      # from the room
	]
	var shots := 0
	var el := 0.0
	var next := 0.0
	var mattress := bed.global_position.y + SleepBlanket.MATTRESS
	var sk: Skeleton3D = duty.mike._skel
	var hips := sk.find_bone("mixamorig_Hips")
	var low := INF
	while el < 70.0 and shots < 26:
		await process_frame
		el += root.get_process_delta_time()
		if duty._blanket and hide_blanket:
			duty._blanket.visible = false
		var phases := ["sleep", "wake"] if OS.get_cmdline_user_args().has("wakeonly") else ["lie_down", "sleep", "wake"]
		var lying := duty.job == "rest" and duty.phase in phases
		if lying and duty.phase == "sleep" and shots >= 2 and phases.size() == 2:
			lying = false
		if OS.get_cmdline_user_args().has("rollonly") and not (duty.phase == "lie_down" and duty._t > 2.9 and duty._t < 5.8):
			lying = false
		if lying and el >= next:
			next = el + (0.3 if duty.phase == "wake" and duty._t < 1.6 else 0.6)
			var hy := (sk.global_transform * sk.get_bone_global_pose(hips)).origin.y - mattress
			var minb := INF
			for b in sk.get_bone_count():
				minb = minf(minb, (sk.global_transform * sk.get_bone_global_pose(b)).origin.y - mattress)
			low = minf(low, minb)
			print("%s t=%.2f hips %.3f above mattress, lowest bone %.3f" % [duty.phase, duty._t, hy, minb])
			for v in views:
				cam.global_position = v[0]
				cam.look_at(v[1])
				await process_frame
				await process_frame
				root.get_texture().get_image().save_png(out + "/bunk_%02d.png" % shots)
				shots += 1
		if duty.rested and duty.job == "room":
			break
	quit(0)
