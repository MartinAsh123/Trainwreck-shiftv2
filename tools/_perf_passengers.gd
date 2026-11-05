extends SceneTree
## What Passengers._process itself costs per frame (its own script time, measured around the call):
## the node's own processing is switched off and the tool calls _process each frame with a timer.
## Three spots of the real journey: the run-in to a stop (the next stop's people waiting on the
## platform, scrolling past), standing at the stop (boarding / alighting) and the open line after
## it (those left behind scrolling away, errands aboard).
##   godot --headless --path . --fixed-fps 30 -s tools/_perf_passengers.gd -- [frames=600]
## Prints "PAXPERF <spot> mean <us> max <us> riders <by state>".

var pax: Passengers
var _us: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 600
	var world: Node3D = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	var nav: TrainNav = null
	while nav == null or not nav.ready_:
		await process_frame
		nav = get_first_node_in_group("train_nav")
	(get_first_node_in_group("horror") as HorrorDirector).enabled = false
	var j: Node = world.get_node("Journey")
	var ts := root.get_node("TrainState")
	pax = world.get_node("Passengers")
	pax.trip_chance = 1.0                  # (errands aboard: the movers are part of the cost)
	pax.trip_check = 4.0
	pax.set_process(false)
	process_frame.connect(_tick)
	world.get_node("Player").global_position = Vector3(-31.0, 1.45, 0.6)
	# The run-in: about a kilometre before DOBŘANY, the people there come out at 700 m.
	var stop1: float = RouteData.stops()[1].s
	j.call("warp_running", stop1 - 1200.0)
	await _until(func(): return float(ts.get("to_next_stop")) < 650.0, 120.0)
	await _sample("run-in", n, ts)
	await _until(func(): return str(ts.get("phase")) == "stopped", 120.0)
	await _sample("stopped", mini(n, 300), ts)
	await _until(func(): return str(ts.get("phase")) == "running", 120.0)
	await _sample("line", n, ts)
	quit(0)

func _tick() -> void:
	var t0 := Time.get_ticks_usec()
	pax._process(get_root().get_process_delta_time())
	_us.append(Time.get_ticks_usec() - t0)

func _sample(spot: String, n: int, ts: Node) -> void:
	_us.clear()
	for i in n:
		await process_frame
	var s := 0.0
	var mx := 0
	for u: int in _us:
		s += u
		mx = maxi(mx, u)
	var by := {}
	for r in pax.riders():
		var k: String = Passengers.State.keys()[r.state]
		by[k] = int(by.get(k, 0)) + 1
	print("PAXPERF %-8s mean %6.0f us  max %6d us  frames %d  phase %s  riders %s" % [spot, s / maxf(_us.size(), 1), mx, _us.size(), ts.get("phase"), by])

func _until(cond: Callable, limit: float) -> void:
	var el := 0.0
	while not cond.call() and el < limit:
		await process_frame
		el += get_root().get_process_delta_time()
