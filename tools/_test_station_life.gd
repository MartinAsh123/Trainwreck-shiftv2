extends SceneTree
## Every stopping station gets its booking hall (with its staff), bell and yard, both ways it can
## come in: streamed in far ahead (WorldLife._station_life spreads it over a few frames after a
## delay) and placed next to the train by a warp (all at once).
##   godot --headless --path . -s tools/_test_station_life.gd
## Prints "FAIL ..." for a station missing a piece, "RESULT ok" when all are there.

var _fails := 0

func _initialize() -> void:
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	(get_first_node_in_group("horror") as HorrorDirector).enabled = false
	var j: Node = world.get_node("Journey")
	var scenery: Node = world.get_node("Scenery")
	for i in 120:
		await process_frame
	_check(scenery, "KRÁLOVEC", "at start")
	# Streamed: roll up to where VRCHOVINA (6500) enters (feature_ahead 2600), then wait it out.
	j.call("warp_running", 3800.0)
	var t0 := Time.get_ticks_msec()
	while scenery.get_node_or_null("st_VRCHOVINA") == null and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	for i in 6:
		await create_timer(1.0).timeout
	_check(scenery, "VRCHOVINA", "streamed")
	# Warped right to a stop.
	j.call("warp_to_stop", 3)
	for i in 30:
		await process_frame
	_check(scenery, "SNĚŽNÁ", "warp_to_stop")
	print("RESULT ok" if _fails == 0 else "FAILS %d" % _fails)
	quit(0 if _fails == 0 else 1)

func _check(scenery: Node, name: String, how: String) -> void:
	var n := scenery.get_node_or_null("st_" + name)
	if n == null:
		print("FAIL %s (%s): station not streamed in" % [name, how])
		_fails += 1
		return
	var staff := n.find_children("*", "", true, false).filter(func(c): return c is TalkingCharacter).size()
	var hall := n.find_child("BookingHall", true, false) != null
	var bell := n.find_child("StationBell", true, false) != null
	var yard := n.get_node_or_null("Yard")
	var fence := yard != null and yard.find_child("Fence", true, false) != null
	var ok := staff > 0 and hall and yard != null and fence
	print("%s %s (%s): hall %s, staff %d, bell %s, yard %s, fence %s" % ["ok  " if ok else "FAIL", name, how, hall, staff,
			bell, yard != null, fence])
	if not ok:
		_fails += 1
