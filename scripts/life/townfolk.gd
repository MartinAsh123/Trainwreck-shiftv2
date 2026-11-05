class_name Townfolk
extends Node
## The people of the towns and villages (assets/models/people/townfolk_NN.glb, built by
## tools/blender/make_people.py): when a settlement appears, some walk up and down its pavements and
## some stand about — at the shop windows, round the square, at their gates — each figure's choice
## fixed by the settlement, so the same people are there every journey.
##   40 people in every town and village: 28 walking - along both pavements of the streets, from
##   door to door along the house fronts, round the square, round the playground and the statue
##   (TownExtras) - and 12 standing at shop windows, in groups on the square, at their gates and
##   by the playground
## Each figure has a capsule the player cannot walk through; walkers stop for the player.
## Models load on a background thread when first needed; figures farther than FAR from the camera are
## hidden and their animation stopped.

const DIR := "res://assets/models/people/"
const COUNT := 30
const FAR := 170.0
const WALK_SPEED := 1.25           # m/s; the "Walk" cycle is made for about 1.3 m/s

var probe: GroundProbe
var _loading := {}                 # index -> true while a threaded load runs
var _queue: Array = []             # [root, plan entry] waiting for their model
var _people: Array = []            # Person
var _frame := 0
const MID := 60.0                  # beyond this the animation is stepped every third frame
const SHADOW_FAR := 45.0           # beyond this a figure casts no shadow (too small to see; saves the shadow passes)

class Person:
	var node: Node3D
	var anim: AnimationPlayer
	var root: Node3D               # the settlement it belongs to
	var walking := false
	var a := Vector2.ZERO          # walk: from a to b (route space), turning at the ends
	var b := Vector2.ZERO
	var t := 0.0
	var dir := 1.0
	var speed := WALK_SPEED
	var pause := 0.0
	var turn := 0.0                # seconds left of a turn on the spot
	var body: AnimatableBody3D
	var acc := 0.0                 # animation time owed (figures far off advance every few frames)
	var casters: Array = []        # its meshes that cast a shadow when near
	var shadowed := true
	var loop: Array = []           # a closed route: walk on from corner to corner instead of back
	var seg := 0

func _init(p: GroundProbe) -> void:
	probe = p

# ————— spawning —————

## Plans the people of settlement `root` (a Scenery feature with life meta) and places them as their
## models arrive.
func populate(root: Node3D, plan: Dictionary, town: bool, square_town: bool, houses: Array, extras: Dictionary = {}) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(root.name)) + 101
	var big := town or square_town
	var n_walk := 28
	var n_stand := 12
	var picks: Array = range(COUNT)
	for i in range(picks.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = picks[i]
		picks[i] = picks[j]
		picks[j] = tmp
	var k := 0
	# Walking routes: both pavements of every street (towns) or the lane's edges (villages) - these
	# twice over, they carry most people - house front to house front, round the square, and the
	# loops round the playground and the statue. A route is a line walked to and fro or a loop.
	var routes: Array = []
	for s: Array in plan.streets:
		var sa: Vector2 = s[0]
		var sb: Vector2 = s[1]
		var u := (sb - sa).normalized()
		var off := (float(s[2]) * 0.5 - 1.25) if big else (float(s[2]) * 0.5 + 0.25)
		for side: float in [-1.0, 1.0]:
			var nrm := Vector2(-u.y, u.x) * side * off
			for w in 2:
				routes.append([sa + u * 6.0 + nrm, sb - u * 6.0 + nrm])
	var fronts: Array = []
	for h: Array in houses:
		var hn: Node3D = h[1]
		var f: Vector2 = hn.get_meta("front")
		var size: Vector3 = hn.get_meta("size")
		fronts.append((hn.get_meta("route_pos") as Vector2) + f * (size.z * 0.5 + 1.6))
	for i in fronts.size():
		var best := -1
		var best_d := 30.0
		for j in fronts.size():
			var d: float = (fronts[i] as Vector2).distance_to(fronts[j])
			if j != i and d > 6.0 and d < best_d:
				best_d = d
				best = j
		if best > i:
			routes.append([fronts[i], fronts[best]])
	var sq: Array = plan.get("square", [])
	if not sq.is_empty():
		var su := Vector2.from_angle(float(sq[2]))
		var sv := Vector2(-su.y, su.x)
		var h2: Vector2 = (sq[1] as Vector2) * 0.5 - Vector2(3.0, 3.0)
		var c0: Vector2 = sq[0]
		var loop := [c0 + su * h2.x + sv * h2.y, c0 - su * h2.x + sv * h2.y, c0 - su * h2.x - sv * h2.y, c0 + su * h2.x - sv * h2.y]
		routes.append(loop + ["loop"])
		routes.append(loop + ["loop"])
	# A few stroll round the playground and the statue; everyone else is out in the streets.
	var extra: Array = extras.get("paths", [])
	var n_extra := mini(extra.size(), 6 if big else 4)
	for i in n_walk:
		var r: Array = []
		if i < n_extra:
			r = extra[(i * 5) % extra.size()]
		elif not routes.is_empty():
			r = routes[(i * 7) % routes.size()]
		if r.is_empty():
			break
		var e := {"walk": true, "t": rng.randf(), "dir": 1.0 if rng.randf() < 0.5 else -1.0,
				"speed": rng.randf_range(1.0, 1.4), "model": picks[k % COUNT]}
		if r.back() is String:
			var pts := r.slice(0, r.size() - 1)
			var seg := rng.randi() % pts.size()
			e["loop"] = pts
			e["seg"] = seg
			e["a"] = pts[seg]
			e["b"] = pts[(seg + 1) % pts.size()]
			e["dir"] = 1.0
		else:
			var jitter := Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
			e["a"] = (r[0] as Vector2) + jitter
			e["b"] = (r[1] as Vector2) + jitter
		k += 1
		_request(root, e)
	# Standers: at the shop windows, in twos and threes round the square, at house doors.
	var spots: Array = []
	var doors: Array = []
	for h: Array in houses:
		var hn: Node3D = h[1]
		var p: Vector2 = hn.get_meta("route_pos")
		var f: Vector2 = hn.get_meta("front")
		var size: Vector3 = hn.get_meta("size")
		var at := p + f * (size.z * 0.5 + 1.1) + Vector2(-f.y, f.x) * rng.randf_range(-2.0, 2.0)
		if hn.find_child("Fascia", false, false):
			spots.append([at, -f])
		else:
			doors.append([at, -f if rng.randf() < 0.5 else f])
	if not sq.is_empty():
		var su := Vector2.from_angle(float(sq[2]))
		var sv := Vector2(-su.y, su.x)
		var h2: Vector2 = (sq[1] as Vector2) * 0.5
		for g in 3:
			var pc: Vector2 = (sq[0] as Vector2) + su * rng.randf_range(-h2.x + 4.0, h2.x - 4.0) + sv * rng.randf_range(-h2.y + 3.0, h2.y - 3.0)
			var n := 2 + int(rng.randf() < 0.4)
			var a0 := rng.randf() * TAU
			for m in n:
				var d := Vector2.from_angle(a0 + TAU * m / n)
				spots.append([pc + d * 0.6, -d])          # facing the group's middle
	for sp: Array in extras.get("spots", []):
		spots.append(sp)
	# Shops, the square, the playground and the statue first, then doors in turn.
	var order: Array = []
	for i in spots.size():
		order.append(spots[i])
	for i in range(doors.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = doors[i]
		doors[i] = doors[j]
		doors[j] = tmp
	order.append_array(doors)
	# Not enough of those (a small village): the rest stop for a word along the pavements.
	var streets: Array = plan.streets
	while order.size() < n_stand and not streets.is_empty():
		var s: Array = streets[rng.randi() % streets.size()]
		var u := ((s[1] as Vector2) - (s[0] as Vector2)).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var off := (float(s[2]) * 0.5 - 1.25) if big else (float(s[2]) * 0.5 + 0.25)
		var at: Vector2 = (s[0] as Vector2).lerp(s[1], rng.randf_range(0.15, 0.85)) + Vector2(-u.y, u.x) * side * off
		order.append([at, u if rng.randf() < 0.5 else -u])
	for i in mini(n_stand, order.size()):
		var sp: Array = order[i]
		_request(root, {"walk": false, "p": sp[0], "face": sp[1], "model": picks[k % COUNT]})
		k += 1

func _path(i: int) -> String:
	return DIR + "townfolk_%02d.glb" % i

func _request(root: Node3D, e: Dictionary) -> void:
	var path := _path(int(e.model))
	if not ResourceLoader.exists(path):
		return
	if not ResourceLoader.has_cached(path) and not _loading.has(e.model):
		ResourceLoader.load_threaded_request(path, "PackedScene")
		_loading[e.model] = true
	_queue.append([root, e])

func _try_spawn() -> void:
	var still: Array = []
	for q: Array in _queue:
		if not is_instance_valid(q[0]):
			continue          # the settlement went out of range before its people arrived
		var root: Node3D = q[0]
		var e: Dictionary = q[1]
		var path := _path(int(e.model))
		var ps: PackedScene = null
		if ResourceLoader.has_cached(path):
			ps = load(path)
		else:
			var st := ResourceLoader.load_threaded_get_status(path)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				ps = ResourceLoader.load_threaded_get(path)
				_loading.erase(e.model)
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_loading.erase(e.model)
				continue
		if ps == null:
			still.append(q)
			continue
		_spawn(root, e, ps)
	_queue = still

func _spawn(root: Node3D, e: Dictionary, ps: PackedScene) -> void:
	var n: Node3D = ps.instantiate()
	n.name = "Townfolk"
	n.set_meta("townfolk", true)
	root.add_child(n)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = FAR
		# Small parts never need shadows; the figure's own shadow comes from the body and clothes.
		if mi.name.contains("eye") or mi.name.contains("brow") or mi.name.contains("lash"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var p := Person.new()
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			p.casters.append(mi)
	p.node = n
	for ap: AnimationPlayer in n.find_children("*", "AnimationPlayer", true, false):
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	p.root = root
	# A capsule the player bumps into (moved with the figure; never pushes anything itself).
	var body := AnimatableBody3D.new()
	body.name = "Body"
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	body.add_child(cs)
	n.add_child(body)
	p.body = body
	var players := n.find_children("*", "AnimationPlayer", true, false)
	p.anim = players[0] if not players.is_empty() else null
	for an in ["Idle", "Walk"]:
		if p.anim and p.anim.has_animation(an):
			p.anim.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	if e.walk:
		p.walking = true
		p.a = e.a
		p.b = e.b
		p.t = float(e.t)
		p.dir = float(e.dir)
		p.speed = float(e.speed)
		p.loop = e.get("loop", [])
		p.seg = int(e.get("seg", 0))
		_play(p, "Walk", p.speed / 1.3)
		_place_walker(p)
	else:
		var pos: Vector2 = _clear_spot(root, e.p)
		n.position = _local(root, pos)
		n.basis = LifeBuilder.facing(e.face)
		_play(p, "Idle", randf_range(0.85, 1.1))
		if p.anim:
			p.anim.seek(randf() * 4.0, true)
	_people.append(p)

## A spot near `p` (route space) where a standing figure overlaps nothing solid (fountain, column,
## bench, wall): `p` itself when clear, else the nearest free point on rings round it.
func _clear_spot(root: Node3D, p: Vector2) -> Vector2:
	var space := root.get_world_3d().direct_space_state if root.is_inside_tree() else null
	if space == null:
		return p
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collide_with_areas = false
	for ring in 5:
		var n := 1 if ring == 0 else 8
		for k in n:
			var c := p + Vector2.from_angle(TAU * k / n + ring) * (ring * 0.9)
			var local := _local(root, c) + Vector3(0, 0.95, 0)
			q.transform = Transform3D(Basis.IDENTITY, root.global_transform * local)
			if space.intersect_shape(q, 1).is_empty():
				return c
	return p

func _play(p: Person, an: String, speed: float) -> void:
	if p.anim and p.anim.has_animation(an):
		p.anim.play(an, 0.25, speed)

func _local(root: Node3D, p: Vector2) -> Vector3:
	var c: Vector2 = root.get_meta("life_center")
	return Vector3(-(p.x - c.x), probe.height(p.x, p.y) + 0.02, p.y)

func _place_walker(p: Person) -> void:
	var pos := p.a.lerp(p.b, p.t)
	p.node.position = _local(p.root, pos)
	var d := (p.b - p.a).normalized() * p.dir
	p.node.basis = LifeBuilder.facing(d)

# ————— every frame —————

func update(cam: Vector3, delta: float, player: Vector3 = Vector3(INF, INF, INF)) -> void:
	_try_spawn()
	_frame += 1
	var keep: Array = []
	for p: Person in _people:
		if not is_instance_valid(p.node):
			continue
		keep.append(p)
		var dist := p.node.global_position.distance_to(cam)
		var near := dist < FAR
		p.node.visible = near
		if not near:
			continue
		var sh := dist < SHADOW_FAR
		if sh != p.shadowed:
			p.shadowed = sh
			for mi: MeshInstance3D in p.casters:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if p.anim:
			p.acc += delta
			if dist < MID or (_frame + p.node.get_instance_id()) % 3 == 0:
				p.anim.advance(p.acc)
				p.acc = 0.0
		if not p.walking:
			continue
		# Someone (the player) in the way: stand and wait.
		var fwd := p.node.global_basis.z
		var to_pl := player - p.node.global_position
		to_pl.y = 0.0
		if to_pl.length() < 1.6 and to_pl.normalized().dot(fwd) > 0.3:
			if p.pause <= 0.0:
				_play(p, "Idle", 1.0)
			p.pause = maxf(p.pause, 0.6)
		if p.pause > 0.0:
			p.pause -= delta
			if p.pause <= 0.0:
				_play(p, "Walk", p.speed / 1.3)
			continue
		var len := maxf(p.a.distance_to(p.b), 1.0)
		p.t += p.dir * p.speed * delta / len
		if p.t > 1.0 and p.loop.size() > 1:
			# Round a loop: on to the next corner, now and then a pause to look about.
			p.seg = (p.seg + 1) % p.loop.size()
			p.a = p.loop[p.seg]
			p.b = p.loop[(p.seg + 1) % p.loop.size()]
			p.t = 0.0
			if randf() < 0.15:
				p.pause = randf_range(1.0, 3.0)
				_play(p, "Idle", 1.0)
		elif p.t > 1.0 or p.t < 0.0:
			# At the end of the street: stop a moment, turn round, walk back.
			p.t = clampf(p.t, 0.0, 1.0)
			p.dir = -p.dir
			p.pause = randf_range(1.5, 4.0)
			_play(p, "Idle", 1.0)
		_place_walker(p)
	_people = keep
