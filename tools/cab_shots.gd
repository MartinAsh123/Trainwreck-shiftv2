extends SceneTree
## Renders views inside the locomotive cab (positions in the Locomotive's local space).
##   godot --path . -s tools/cab_shots.gd -- <out_dir> [view ...]
## Views: backhead, gauges_side, gauges_close, cab_wide, cab_rear, driver.

const VIEWS := {
	"backhead": [Vector3(-9.15, 1.55, 0.0), Vector3(-10.6, 1.35, 0.0)],
	"gauges_side": [Vector3(-10.05, 1.75, -0.95), Vector3(-10.6, 1.66, 0.05)],
	"gauges_close": [Vector3(-9.95, 1.7, 0.0), Vector3(-10.6, 1.64, 0.0)],
	"cab_wide": [Vector3(-8.85, 1.55, 0.95), Vector3(-11.0, 1.2, -0.7)],
	"cab_rear": [Vector3(-10.2, 1.55, 0.2), Vector3(-8.5, 1.0, -0.3)],
	"driver": [Vector3(-9.75, 1.5, -0.95), Vector3(-10.75, 1.3, -0.4)],
	"fireman": [Vector3(-9.6, 1.5, 0.95), Vector3(-11.0, 1.1, 0.9)],
	"tender_front": [Vector3(-10.2, 1.6, 0.1), Vector3(-8.6, 0.8, 0.2)],
	"coal_hole": [Vector3(-9.4, 1.4, 0.6), Vector3(-8.6, 0.9, 0.85)],
	"pail": [Vector3(-9.5, 1.3, -0.5), Vector3(-8.75, 0.3, -0.95)],
	"seat_driver": [Vector3(-9.0, 1.5, -0.3), Vector3(-10.0, 0.8, -1.15)],
	"firehole": [Vector3(-9.85, 1.35, 0.15), Vector3(-10.7, 0.55, 0.0)],
	"firehole_in": [Vector3(-10.25, 0.95, 0.05), Vector3(-11.0, 0.42, 0.0)],
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var views: Array = args.slice(1) if args.size() > 1 else VIEWS.keys()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	world.get_node("Journey").set_physics_process(false)
	world.get_node("Player").set_physics_process(false)
	var cam := Camera3D.new()
	cam.fov = 70
	cam.near = 0.02
	world.add_child(cam)
	await _frames(60)
	world.get_node("Player/HUD").visible = false
	cam.make_current()
	var loco := world.get_node("Train/Locomotive6") as Node3D
	for v: String in views:
		var spec: Array = VIEWS[v]
		cam.global_position = loco.to_global(spec[0])
		cam.look_at(loco.to_global(spec[1]))
		await _frames(30)
		root.get_texture().get_image().save_png(out.path_join("cab_%s.png" % v))
		print("view ", v)
	quit(0)

func _frames(n: int) -> void:
	for i in n:
		await process_frame
