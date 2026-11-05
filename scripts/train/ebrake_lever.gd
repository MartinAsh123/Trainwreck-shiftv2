class_name EBrakeLever
extends Node3D
## The emergency brake on a saloon partition: a box with a red lever on a pin (the model is split
## into "Box" and "Handle", the handle pivoted on its pin). Having a script also keeps it out of
## StaticMerge, so the lever can move.

const THROW := 1.0                     # radians the pulled lever swings out from the wall

var pulled := false

## Throws the lever out (pulled) or back down against the box.
func throw(on: bool) -> void:
	pulled = on
	var lever := find_child("Handle", true, false) as Node3D
	if lever == null:
		return
	var tw := create_tween()
	tw.tween_property(lever, "rotation:z", THROW if on else 0.0, 0.12 if on else 0.35)
