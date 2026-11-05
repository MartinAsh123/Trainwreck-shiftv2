extends SceneTree
## Renders views of the valley's life (roads, crossings, towns, fields) from the journey scene.
##   godot --path . -s tools/life_shots.gd -- <out_dir> [shot ...]
## Shots: crossing, crossing_train, town, street, shop, fields, road, station, station_far, halt, halt_far, shed, shed_out, shed_far. Camera positions are in route space
## (s, y, z) and drawn at world x = distance - s.

var world: Node3D
var cam: Camera3D
var ts: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var shots: Array = args.slice(1) if args.size() > 1 else ["crossing", "town", "street", "fields", "road"]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	world = load("res://scenes/game/journey.tscn").instantiate()
	if OS.has_environment("LIFE_SYNC"):
		world.get_node("WorldLife").threaded = false
	root.add_child(world)
	var j: Node = world.get_node("Journey")
	j.set_physics_process(false)
	world.get_node("Player").set_physics_process(false)
	cam = Camera3D.new()
	cam.far = 9000
	cam.fov = 60
	world.add_child(cam)
	await _frames(20)
	ts = root.get_node("TrainState")
	world.get_node("Player/HUD").visible = false
	cam.make_current()
	for shot: String in shots:
		await _shot(shot)
		var img := root.get_texture().get_image()
		img.save_png(out.path_join("life_%s.png" % shot))
		print("shot ", shot)
	quit(0)

func _route_cam(d: float, from: Vector3, to: Vector3) -> void:
	cam.global_position = Vector3(d - from.x, from.y, from.z)
	cam.look_at(Vector3(d - to.x, to.y, to.z))

func _go(d: float) -> void:
	ts.set("distance", d)
	await _frames(500)

func _put_car(i: int, road: int, t: float, dir: float) -> void:
	var life := world.get_node("WorldLife")
	var c = life._cars[i]
	c.road = road
	c.t = t
	c.dir = dir
	c.v = 6.0
	c.parked = 0.0
	c.node.visible = true

func _shot(shot: String) -> void:
	match shot:
		"crossing", "crossing_train":
			var cr: Dictionary = RoadNetwork.crossings()[1]
			var sx: float = cr.s
			var r: Dictionary = RoadNetwork.roads()[cr.road]
			var d := sx - 160.0 if shot == "crossing_train" else sx - 900.0
			await _go(d)
			_put_car(0, cr.road, float(r.cross_t) - 70.0, 1.0)
			_put_car(1, cr.road, float(r.cross_t) - 95.0, 1.0)
			_put_car(2, cr.road, float(r.cross_t) + 60.0, -1.0)
			await _frames(240)
			_route_cam(distance(), Vector3(sx - 26.0, 4.5, -22.0), Vector3(sx + 6.0, 0.6, 4.0))
		"town":
			var p: Dictionary = _place("Dobřany")
			await _go(float(p.s) - 40.0)
			_route_cam(distance(), Vector3(p.s - 60.0, 9.0, p.z * 0.35), Vector3(p.s, 2.0, p.z))
		"street":
			var p: Dictionary = _place("Dobřany")
			await _go(float(p.s) - 40.0)
			var a: Vector2 = p.ends[0]
			var b: Vector2 = p.ends[1]
			var e := a.lerp(b, 0.2)
			var f := a.lerp(b, 0.55)
			_route_cam(distance(), Vector3(e.x, 2.2, e.y), Vector3(f.x, 2.4, f.y))
		"fields":
			var best: Dictionary = {}
			for fl: Dictionary in FarmLand.fields():
				var c: Vector2 = fl.c
				if absf(c.y) > 50.0 and absf(c.y) < 220.0 and c.x > 3000.0 and fl.stacks.size() > 0 and fl.fence != "":
					best = fl
					break
			if best.is_empty():
				best = FarmLand.fields()[5]
			var c: Vector2 = best.c
			print("field ", c, " L ", best.L, " W ", best.W, " stubble ", best.stubble)
			await _go(c.x - 30.0)
			var sg := signf(c.y)
			_route_cam(distance(), Vector3(c.x - 75.0, 14.0, c.y - sg * (float(best.W) * 0.5 + 6.0)), Vector3(c.x, 0.0, c.y))
		"shop":
			var p: Dictionary = _place("Dobřany")
			await _go(float(p.s) - 40.0)
			var fascias := world.get_node("Scenery").find_children("Fascia", "MeshInstance3D", true, false)
			if not fascias.is_empty():
				var fa: Node3D = fascias[0]
				var b := fa.global_transform.basis
				cam.global_position = fa.global_position - b.z.normalized() * 10.0 + b.x.normalized() * 3.0 - Vector3(0, 1.0, 0)
				cam.look_at(fa.global_position - Vector3(0, 0.6, 0))
		"station", "station_far":
			# Dobřany: stop, platform on the +Z side.
			var st: Dictionary = RouteData.STATIONS[2]
			await _go(float(st.s) - 29.0)
			var sd: float = st.side
			if shot == "station":
				_route_cam(distance(), Vector3(float(st.s) - 45.0, 2.3, sd * 3.5), Vector3(float(st.s) + 5.0, 3.5, sd * 13.0))
			else:
				_route_cam(distance(), Vector3(float(st.s) - 90.0, 8.0, -sd * 25.0), Vector3(float(st.s), 3.0, sd * 12.0))
		"halt", "halt_far":
			var st: Dictionary = RouteData.STATIONS[1]          # LHOTA
			await _go(float(st.s) - 29.0)
			var sd: float = st.side
			if shot == "halt":
				_route_cam(distance(), Vector3(float(st.s) - 26.0, 2.0, sd * 2.6), Vector3(float(st.s), 3.0, sd * 7.0))
			else:
				_route_cam(distance(), Vector3(float(st.s) - 40.0, 5.0, -sd * 14.0), Vector3(float(st.s), 2.0, sd * 7.0))
		"shed", "shed_out", "shed_far":
			var st: Dictionary = RouteData.STATIONS[0]          # KRÁLOVEC
			await _go(float(st.s) - 29.0)
			var sd: float = st.side
			if shot == "shed":
				_route_cam(distance(), Vector3(float(st.s) + 30.0, 2.3, sd * 4.5), Vector3(float(st.s) - 20.0, 4.5, sd * 1.0))
			elif shot == "shed_out":
				_route_cam(distance(), Vector3(float(st.s) - 110.0, 3.0, sd * 3.0), Vector3(float(st.s) - 40.0, 6.0, sd * 1.0))
			else:
				_route_cam(distance(), Vector3(float(st.s) - 120.0, 14.0, -sd * 45.0), Vector3(float(st.s), 4.0, sd * 4.0))
		"station_near":
			var st: Dictionary = RouteData.STATIONS[2]          # DOBŘANY
			await _go(float(st.s) - 29.0)
			for b: Node in world.get_node("Scenery").find_children("StationBuilding", "Node3D", true, false):
				if String(b.get_parent().name).contains("DOB"):
					var bp: Vector3 = (b as Node3D).global_position
					var sd: float = st.side
					cam.global_position = bp + Vector3(-17.0, 1.2, -sd * 9.0)
					cam.look_at(bp + Vector3(-3.0, 3.0, 0.0))
		"island", "yard_far", "yard_back":
			var st: Dictionary = RouteData.STATIONS[2]          # DOBŘANY
			await _go(float(st.s) - 29.0)
			var sd: float = st.side
			var s0: float = st.s
			if shot == "island":
				_route_cam(distance(), Vector3(s0 + 36.0, 2.3, -sd * 3.2), Vector3(s0 - 10.0, 1.6, -sd * 7.0))
			elif shot == "yard_far":
				_route_cam(distance(), Vector3(s0 + 60.0, 22.0, -sd * 60.0), Vector3(s0 - 10.0, 0.0, -sd * 5.0))
			else:
				_route_cam(distance(), Vector3(s0 - 20.0, 1.7, sd * 40.0), Vector3(s0, 1.0, sd * 12.0))
		"big_back":
			var st: Dictionary = RouteData.STATIONS[0]          # KRÁLOVEC: the building from behind
			await _go(float(st.s) - 29.0)
			var sd: float = st.side
			_route_cam(distance(), Vector3(float(st.s) + 35.0, 1.7, sd * 30.0), Vector3(float(st.s), 1.0, sd * 12.0))
		"town_entry", "square", "corner":
			var p: Dictionary = _place("Dobřany")
			await _go(float(p.s) - 40.0)
			var plan: Dictionary = p.plan
			var c: Vector2 = plan.center
			var lane: Vector2 = plan.lane
			var n := Vector2(-lane.y, lane.x)
			var e1 := float(plan.ends[1])
			var sqh: Vector2 = plan.sq
			if shot == "town_entry":
				var q := c + lane * (e1 + 8.0)
				var f := c + lane * (e1 - 30.0)
				_route_cam(distance(), Vector3(q.x, 1.7, q.y), Vector3(f.x, 2.2, f.y))
			elif shot == "square":
				var q := c + lane * (sqh.x + 12.0) + n * 2.0
				_route_cam(distance(), Vector3(q.x, 1.8, q.y), Vector3(c.x, 2.5, c.y))
			else:
				var q := c + lane * (sqh.x + 5.0) - n * 1.0
				var f := c + lane * (sqh.x + 1.0) + n * 7.0
				_route_cam(distance(), Vector3(q.x, 1.7, q.y), Vector3(f.x, 3.2, f.y))
		"benches":
			var st: Dictionary = RouteData.STATIONS[2]          # DOBŘANY: island benches from the side
			await _go(float(st.s) - 29.0)
			var sd: float = st.side
			_route_cam(distance(), Vector3(float(st.s) + 20.0, 1.9, -sd * 9.0), Vector3(float(st.s) + 15.0, 0.9, -sd * 4.4))
		"village":
			var p: Dictionary = _place("Bukovina")
			await _go(float(p.s) - 60.0)
			var a: Vector2 = p.ends[0]
			var b: Vector2 = p.ends[1]
			var e := a.lerp(b, 0.1)
			var f := a.lerp(b, 0.6)
			var gp := GroundProbe.new()
			_route_cam(distance(), Vector3(e.x, gp.height(e.x, e.y) + 1.7, e.y), Vector3(f.x, gp.height(f.x, f.y) + 1.0, f.y))
		"town_car":
			var p: Dictionary = _place("Dobřany")
			await _go(float(p.s) - 40.0)
			await _frames(120)
			var life := world.get_node("WorldLife")
			var best = null
			for c in life._street_cars:
				if c.street >= 0 and c.node.visible and (best == null or absf(c.pos.x - float(p.s)) < absf(best.pos.x - float(p.s))):
					best = c
			if best:
				var xf: Transform3D = best.node.global_transform
				cam.global_position = xf * Vector3(-3.5, 1.6, -7.0)
				cam.look_at(xf * Vector3(0, 0.8, 0))
		"town_air":
			var p: Dictionary = _place("Dobřany")
			await _go(float(p.s) - 40.0)
			var c: Vector2 = (p.plan as Dictionary).center
			_route_cam(distance(), Vector3(c.x - 70.0, 35.0, c.y - 60.0), Vector3(c.x, 0.0, c.y))
		"umbrella", "umbrella_k":
			var st: Dictionary = RouteData.STATIONS[2 if shot == "umbrella" else 0]
			await _go(float(st.s) - 29.0)
			var sd: float = st.side
			_route_cam(distance(), Vector3(float(st.s) - 9.0, 1.7, -sd * 6.0), Vector3(float(st.s) + 2.0, 2.6, -sd * 4.4))
		"person", "person_close":
			var st: Dictionary = RouteData.STATIONS[2]          # DOBŘANY platform
			await _go(float(st.s) - 29.0)
			var sd: float = st.side
			var man: Node3D = (load(OS.get_environment("PERSON") if OS.has_environment("PERSON") else "res://assets/models/people/man_winter.glb") as PackedScene).instantiate()
			world.add_child(man)
			var spot := Vector3(distance() - (float(st.s) + 12.0), 0.55, sd * 4.0)
			man.global_position = spot
			man.rotation.y = PI * 0.5 + 0.4
			_relax_arms(man)
			var fw := man.global_basis.z.normalized()
			var rt := fw.cross(Vector3.UP).normalized()
			if shot == "person":
				cam.global_position = spot + fw * 2.6 + rt * 0.6 + Vector3(0, 1.35, 0)
				cam.look_at(spot + Vector3(0, 0.92, 0))
			else:
				cam.global_position = spot + fw * 0.85 + rt * 0.2 + Vector3(0, 1.58, 0)
				cam.look_at(spot + Vector3(0, 1.5, 0))
		"folk_street", "folk_square", "folk_village":
			var p: Dictionary = _place("Bukovina" if shot == "folk_village" else "Dobřany")
			await _go(float(p.s) - 40.0)
			await _frames(200)             # let the people load and walk
			var plan: Dictionary = p.plan
			var c: Vector2 = plan.center
			var lane: Vector2 = plan.lane
			var gp := GroundProbe.new()
			var e1 := float(plan.ends[1])
			var q: Vector2
			var f: Vector2
			if shot == "folk_street":
				q = c + lane * (e1 - 10.0)
				f = c + lane * 10.0
			elif shot == "folk_square":
				var sqh: Vector2 = plan.sq
				q = c + lane * (sqh.x + 6.0) + Vector2(-lane.y, lane.x) * 3.0
				f = c - lane * 6.0
			else:
				q = c + lane * (e1 - 4.0)
				f = c
			_route_cam(distance(), Vector3(q.x, gp.height(q.x, q.y) + 1.7, q.y), Vector3(f.x, gp.height(f.x, f.y) + 1.3, f.y))
		"road":
			var r: Dictionary = RoadNetwork.roads()[2]
			var pd: Array = RoadNetwork.point_at(r, 500.0)
			var p: Vector2 = pd[0]
			await _go(p.x - 20.0)
			_put_car(3, 2, 540.0, -1.0)
			await _frames(60)
			_route_cam(distance(), Vector3(p.x - 40.0, 3.0, p.y * 0.5), Vector3(p.x + 20.0, 0.8, p.y))
	await _frames(30)

# Lowers the arms of an A-posed MPFB figure (for stills; the game will animate it).
func _relax_arms(man: Node3D) -> void:
	for sk: Skeleton3D in man.find_children("*", "Skeleton3D", true, false):
		for side in ["l", "r"]:
			var i := sk.find_bone("upperarm_" + side)
			var j := sk.find_bone("lowerarm_" + side)
			if i < 0 or j < 0:
				continue
			# Swing the upper arm (in skeleton space) from where it points to nearly straight down.
			var g := sk.get_bone_global_rest(i)
			var dir := (sk.get_bone_global_rest(j).origin - g.origin).normalized()
			var want := Vector3(0.18 * signf(dir.x), -1.0, 0.04).normalized()
			var q := Quaternion(dir, want)
			var local := g.basis.inverse() * Basis(q) * g.basis
			sk.set_bone_pose_rotation(i, (sk.get_bone_rest(i).basis * local).get_rotation_quaternion())

func _place(name: String) -> Dictionary:
	for p: Dictionary in RoadNetwork.places():
		if p.name == name:
			return p
	return RoadNetwork.places()[0]

func distance() -> float:
	return float(ts.get("distance"))

func _frames(n: int) -> void:
	for i in n:
		await process_frame
		if OS.has_environment("LIFE_TRACE") and Engine.get_process_frames() % 25 == 0:
			printerr("frame %d t=%d" % [Engine.get_process_frames(), Time.get_ticks_msec()])
