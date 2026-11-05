extends SceneTree
func _initialize() -> void:
	var ts := root.get_node("TrainState")
	var j := Journey.new()
	j.dwell = 10.0
	j.first_dwell = 5.0
	root.add_child(j)
	await process_frame
	j.set_physics_process(false)
	var log := []
	ts.connect("arrived", func(s): log.append("ARRIVED %s at d=%.2f t" % [s, ts.distance]))
	ts.connect("departing", func(s): log.append("DEPART %s" % s))
	var t := 0.0
	var vmax := 0.0
	var dt := 1.0 / 30.0
	while t < 20000.0 and not (ts.phase == "stopped" and ts.station == "KAMENNÝ MOST"):
		j._physics_process(dt)
		t += dt
		vmax = maxf(vmax, ts.speed)
	for l in log:
		print(l)
	print("sim time %.0f s  vmax %.1f  clock %.2f" % [t, vmax, ts.clock])
	for st in RouteData.stops():
		print("  %s stop mark %.2f" % [st.name, st.s - 29.0])
	quit(0)
