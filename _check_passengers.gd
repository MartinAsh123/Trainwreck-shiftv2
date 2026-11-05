extends SceneTree
## Passengers test: seated at the start; at each of three stops the doors on the platform side (and
## only those) open, some get off and walk away, the waiting ones board and sit; after departure
## nobody is half-way. Run: godot --headless --fixed-fps 30 --path . -s _check_passengers.gd

var world: Node3D
var pax: Passengers
var ts: Node
var ok := true

func _initialize() -> void:
	await process_frame
	world = load("res://scenes/game/journey.tscn").instantiate()
	root.add_child(world)
	pax = world.get_node("Passengers") as Passengers
	ts = root.get_node_or_null("TrainState")
	if ts == null:
		print("FAIL no TrainState"); quit(1); return
	ts.connect("arrived", func(s): print("EVENT arrived ", s, " side ", _side(s)))
	ts.connect("departing", func(s): print("EVENT departing ", s); _report("at departure"))
	await _secs(3.0)
	_report("start")
	if pax.anomalies().is_empty():
		print("FAIL no anomaly aboard at the start")
		ok = false
	_doors("start", 1)
	await _secs(22.0)
	_report("first stop, before departure")
	var journey := world.get_node("Journey")
	var stops := RouteData.stops()
	for i in [1, 2]:
		await _until(func(): return str(ts.get("phase")) == "running", 60.0)
		journey.call("warp_running", float(stops[i].s) - 29.0 - 650.0)
		await _until(func(): return str(ts.get("phase")) == "stopped", 120.0)
		await _secs(3.0)
		_doors(stops[i].name, int(stops[i].side))
		await _secs(14.0)
		_report("%s mid-stop" % stops[i].name)
		await _until(func(): return str(ts.get("phase")) == "running", 60.0)
		await _secs(1.0)
		_report("%s after departure" % stops[i].name)
		for r in pax._riders:
			if r.state in [Passengers.State.BOARDING, Passengers.State.ALIGHTING]:
				print("FAIL someone still on the way after departure: ", r.slug)
				ok = false
	print("PASSENGERS ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)

func _side(name: String) -> int:
	for st in RouteData.stops():
		if st.name == name:
			return st.side
	return 0

func _report(tag: String) -> void:
	var c := {}
	for r in pax._riders:
		var k: String = Passengers.State.keys()[r.state]
		c[k] = c.get(k, 0) + 1
	var bases := {}
	for r in pax._riders:
		if bases.has(r.base):
			print("FAIL ", r.base, " aboard twice (", r.slug, ")")
			ok = false
		bases[r.base] = true
	print("STATE ", tag, ": ", c, " total ", pax._riders.size(), " anomalies ", pax.anomalies().map(func(r): return r.slug))
	for r in pax._riders:
		if r.state == Passengers.State.SEATED and r.body.get("_sit") < 0.9:
			print("FAIL seated but not sitting: ", r.slug)
			ok = false

func _doors(tag: String, side: int) -> void:
	var good := 0
	for cn in Passengers.DOOR_CARS:
		var car := world.get_node("Train/" + cn) as Node3D
		for d in car.find_children("*", "TrainDoor", true, false):
			if not d.get("lock_while_moving"):
				continue
			var zs := signf(car.to_local(d.global_position).z)
			var open: bool = d.call("is_open")
			if open != (zs == side):
				print("FAIL door ", cn, " z ", zs, " open ", open, " at ", tag)
				ok = false
			elif open:
				good += 1
	print("DOORS ", tag, ": ", good, " open on side ", side)

func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await process_frame
		t += 1.0 / 30.0

func _until(f: Callable, limit: float) -> void:
	var t := 0.0
	while not f.call() and t < limit:
		await process_frame
		t += 1.0 / 30.0
