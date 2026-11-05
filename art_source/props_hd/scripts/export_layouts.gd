extends SceneTree
## Exports each car type's body layout (window apertures with their wall transforms, doors, body
## dimensions) to art_source/props_hd/layouts/<type>.json for the Blender body-mouldings builder.
## Run: godot --headless --path <project> --script res://art_source/... (or an absolute path).

const OUT := "A:/Trainwreck-ShiftV2/art_source/props_hd/layouts/"
const HD := preload("res://scripts/train/hd_props.gd")

func _initialize() -> void:
	call_deferred("run")

func xf_list(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]

func run() -> void:
	var index := {}
	for type in ["passenger_car", "sleeper_car", "crew_car", "mail_van"]:
		var car := (load("res://scenes/train/%s.tscn" % type) as PackedScene).instantiate()
		root.add_child(car)
		await process_frame
		var meta: Dictionary = car.get("_frame_meta")
		var wins := []
		var wsize := Vector2(car.window_width, car.window_height)
		var s: Vector2 = car.call("_frame_scale", wsize)
		var outer: Vector2 = meta.outer_size * s - Vector2(0.004, 0.004)
		var cy: float = meta.outer_center_y * s.y
		for x in car.call("_window_xs"):
			for zs in car.call("_window_sides", x):
				var t: Transform3D = car.call("_window_xform", x, car.window_sill + car.window_height * 0.5, zs)
				wins.append({"xform": xf_list(t.translated_local(Vector3(0, cy, 0))), "size": [outer.x, outer.y]})
		# Toilet window (WC side, +Z).
		var tsize: Vector2 = car.get("TOILET_WINDOW_SIZE")
		var ts: Vector2 = car.call("_frame_scale", tsize)
		var t2: Transform3D = car.call("_window_xform", car.call("_toilet_door_x"), car.get("TOILET_WINDOW_Y"), 1.0)
		var touter: Vector2 = meta.outer_size * ts - Vector2(0.004, 0.004)
		wins.append({"xform": xf_list(t2.translated_local(Vector3(0, meta.outer_center_y * ts.y, 0))), "size": [touter.x, touter.y]})
		var d := {
			"type": type, "signature": HD.body_signature(car),
			"length": car.length, "width": car.width, "wall_thickness": car.wall_thickness, "tumblehome": car.tumblehome,
			"window_sill": car.window_sill, "window_height": car.window_height, "eave_y": car.call("_eave_y"),
			"roof_rise": car.roof_rise, "floor_thickness": car.floor_thickness,
			"side_door_x": car.call("_side_door_x"), "side_door_width": car.side_door_width, "door_height": car.door_height,
			"end_door_width": car.end_door_width, "toilet_x": car.call("_toilet_door_x"),
			"windows": wins,
			"loading_door_x": car.call("_door_x") if car.has_method("_door_x") else null,
			"loading_door_width": car.get("loading_door_width"),
		}
		var f := FileAccess.open(OUT + type + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify(d, "  "))
		f.close()
		index[d.signature] = "body_mouldings_" + type
		print("LAYOUT ", type, " windows=", wins.size(), " sig=", d.signature.left(60))
		car.queue_free()
		await process_frame
	var fi := FileAccess.open("A:/Trainwreck-ShiftV2/assets/models/hd_props/body_layouts.json", FileAccess.WRITE)
	fi.store_string(JSON.stringify(index, "  "))
	fi.close()
	quit()
