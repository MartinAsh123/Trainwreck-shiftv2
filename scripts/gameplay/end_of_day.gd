class_name EndOfDay
extends Node
## Kevin's bed in his own room (crew car, InspectorRoom) ends the day. Until the train stands at the
## end of the line it is only a bed; after that, E turns in: the screen goes dark, whatever work is
## still open is called off (missed ones were charged already), the record counts what is left
## (ShiftRecord.finish), the base pay goes in, and the summary (ShiftSummary) offers sleep - the next
## day, the wallet carried over (Economy).

@export var fade := 1.2                    # seconds to black, and back

var _spot: HauntSpot
var _black: ColorRect
var _busy := false

func _ready() -> void:
	_setup.call_deferred()

func _setup() -> void:
	await get_tree().process_frame
	var train := get_tree().root.find_child("Train", true, false) as Node3D
	var room := train.find_child("InspectorRoom", true, false) as Node3D if train else null
	var bed := room.get_node_or_null("Bed") as Node3D if room else null
	if bed == null:
		push_warning("EndOfDay: no bed in Kevin's room")
		return
	_spot = HauntSpot.make("TurnIn", Vector3(0.9, 0.7, 2.0), _prompt, _use)
	bed.add_child(_spot)
	_spot.position = Vector3(0, 0.6, 0)
	var layer := CanvasLayer.new()
	layer.layer = 19
	add_child(layer)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_black)

func _over() -> bool:
	var rec := ShiftRecord.of(self)
	return rec != null and rec.shift_over

func _prompt() -> String:
	if _busy:
		return ""
	return "E — Turn in (end the day)" if _over() else "Your bed - not before the end of the line"

func _use() -> String:
	if _busy or not _over():
		return ""
	turn_in()
	return ""

## The day is over (also for tests).
func turn_in() -> void:
	_busy = true
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 1.0, fade)
	await tw.finished
	var board := TaskBoard.of(self)
	if board:
		board.close_all()
	var rec := ShiftRecord.of(self)
	var s: Dictionary = rec.finish() if rec else {}
	var eco := Economy.of(self)
	if eco:
		eco.close_day()
	var ui := ShiftSummary.new()
	ui.name = "ShiftSummary"
	add_child(ui)
	ui.show_summary(s, eco)
	ui.sleep.connect(func() -> void:
		ui.queue_free()
		if eco:
			eco.start_next_day())
