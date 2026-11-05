extends SceneTree
const SD := "C:/Users/marti/AppData/Local/Temp/claude/C--Users-marti-AppData-Roaming-Claude-scratch-workspaces-3e58b957-222a-49cc-a358-7d825abce1af-88de5f8e-6168-4768-8e06-65da1c67b280-scratch-2026-09-26-7f055c/f101d24e-3f93-42ca-aaee-c6355cbfddfa/scratchpad/"
var cam: Camera3D
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	world.get_node("Journey").set_physics_process(false)
	world.get_node("Player").set_physics_process(false)
	(world.get_node("Weather") as Weather).set_state("clear", true)
	cam = Camera3D.new()
	cam.far = 9000
	world.add_child(cam)
	cam.make_current()
	await process_frame
	world.get_node("Player/HUD").visible = false
	await _frames(400)
	var town: Node3D = world.get_node("Scenery").get_node("town_KRÁLOVEC")
	var ch := town.find_child("Church", true, false) as Node3D
	var h := town.find_child("House*", true, false) as Node3D
	print("town ", town.global_position, " church ", ch.global_position if ch else null, " house ", h.global_position if h else null)
	if ch:
		await _shot(ch.global_position + Vector3(30, 8, -35), ch.global_position + Vector3(0, 10, 0), 55, "v_church.png")
	if h:
		var fwd := -h.global_basis.z
		await _shot(h.global_position + fwd * 14.0 + Vector3(0, 3, 0), h.global_position + Vector3(0, 3, 0), 60, "v_house.png")
	await _shot(town.global_position + Vector3(0, 30, -120), town.global_position + Vector3(0, 0, 0), 55, "v_town.png")
	quit(0)
func _shot(p: Vector3, at: Vector3, fov: float, f: String) -> void:
	cam.global_position = p
	cam.look_at(at)
	cam.fov = fov
	await _frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SD + f)
func _frames(n: int) -> void:
	for i in n:
		await process_frame
