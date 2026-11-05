class_name TownExtras
extends RefCounted
## Things that make a settlement feel lived in, put down when it appears (WorldLife), once its
## houses stand (free ground is found with physics queries against their solids):
##   - a playground on open ground near the houses: swings, slide, seesaw, roundabout, sandbox and
##     climbing frame in a town, a smaller one in a village, a picnic table and a lamp by it;
##   - a statue: the horseman on his plinth in a town's square, a saint by the lane in a village.
## Returns the paths and spots the townsfolk use there: {"paths": [[a, b], ...], "spots": [[p, face], ...]}
## (route space). HD models: art_source/props_hd/scripts/assets_station.py.

const HDProps := preload("res://scripts/train/hd_props.gd")
const VIS := 220.0

static func build(root: Node3D, plan: Dictionary, square_town: bool, probe: GroundProbe, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"paths": [], "spots": []}
	if plan.is_empty() or not root.is_inside_tree():
		return out
	var c: Vector2 = plan.center
	var lane: Vector2 = plan.lane
	# ——— statue ———
	var sq: Array = plan.get("square", [])
	if square_town and not sq.is_empty():
		var su := Vector2.from_angle(float(sq[2]))
		var sv := Vector2(-su.y, su.x)
		var h2: Vector2 = (sq[1] as Vector2) * 0.5
		var sc: Vector2 = sq[0]
		for cand: Vector2 in [sc + sv * h2.y * 0.35, sc - sv * h2.y * 0.6, sc + su * h2.x * 0.05 + sv * h2.y * 0.6]:
			if _clear(root, probe, cand, Vector3(3.2, 3.0, 3.2), 0.0):
				var face := (sc - cand).normalized() if cand.distance_to(sc) > 0.5 else -sv
				_put(root, probe, "statue_horse", cand, face, Vector3(1.6, 2.1, 1.3), Vector3(0, 1.05, 0))
				_ring(out, cand, 3.2, rng)
				out.spots.append([cand + face * 2.6, -face])
				break
	else:
		# A saint by the lane, a little off it.
		for k in 8:
			var a := rng.randf_range(-12.0, 12.0)
			var side := 1.0 if k % 2 == 0 else -1.0
			var cand := c + lane * a + Vector2(-lane.y, lane.x) * side * (float(plan.street_w) * 0.5 + 3.0)
			if absf(cand.y) > 24.0 and _clear(root, probe, cand, Vector3(2.0, 3.0, 2.0), 0.0):
				var face := -Vector2(-lane.y, lane.x) * side
				_put(root, probe, "statue_gothic", cand, face, Vector3(1.2, 1.6, 1.2), Vector3(0, 0.8, 0))
				out.spots.append([cand + face * 1.8, -face])
				break
	# ——— playground ———
	var big := square_town
	var need := Vector3(15.0, 3.0, 12.0) if big else Vector3(10.0, 3.0, 8.0)
	var best := Vector2.INF
	var best_d := INF
	for ring: float in [30.0, 42.0, 55.0, 70.0]:
		for k in 16:
			var p := c + Vector2.from_angle(TAU * k / 16.0 + ring * 0.1) * ring
			if absf(p.y) < 32.0 or RoadNetwork.near_road(p.x, p.y, need.x * 0.6 + 2.0):
				continue
			var yaw := atan2(lane.y, lane.x)
			if not _clear(root, probe, p, need, yaw):
				continue
			if p.distance_to(c) < best_d:
				best_d = p.distance_to(c)
				best = p
		if best != Vector2.INF:
			break
	if best != Vector2.INF:
		_playground(root, probe, best, lane, big, rng, out)
	return out

static func _playground(root: Node3D, probe: GroundProbe, p: Vector2, lane: Vector2, big: bool, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var u := lane
	var v := Vector2(-lane.y, lane.x)
	var items: Array
	if big:
		items = [["swing_set", -4.5, -3.0], ["slide", 4.0, -3.0], ["seesaw", -4.5, 3.0], ["roundabout", 0.5, 2.8],
				["sandbox", 5.0, 3.0], ["climbing_frame", 0.0, -3.3], ["picnic_table", -7.5, 0.0]]
	else:
		items = [["swing_set", -2.5, -1.8], ["sandbox", 2.5, 1.5], ["seesaw", -2.5, 2.2]]
	for it: Array in items:
		var q: Vector2 = p + u * float(it[1]) + v * float(it[2])
		_put(root, probe, it[0], q, v, Vector3.ZERO, Vector3.ZERO)
	# A low fence round it would hide it under the snow; a lamp at one corner instead.
	var lp: Vector2 = p + u * (7.0 if big else 4.5) + v * (5.0 if big else 3.5)
	var gp := _local(root, probe, lp)
	Buildings._lamp_post(root, gp, true)
	_ring(out, p, 7.5 if big else 5.0, rng)
	for k in (3 if big else 2):
		var a := rng.randf() * TAU
		var sp: Vector2 = p + Vector2.from_angle(a) * (8.0 if big else 6.0)
		out.spots.append([sp, (p - sp).normalized()])

# A loop of four walking legs round `p` at radius r (people strolling round the statue or the playground).
static func _ring(out: Dictionary, p: Vector2, r: float, rng: RandomNumberGenerator) -> void:
	var a0 := rng.randf() * TAU
	var pts: Array = []
	for k in 4:
		pts.append(p + Vector2.from_angle(a0 + TAU * k / 4.0) * r)
	for k in 4:
		out.paths.append([pts[k], pts[(k + 1) % 4]])

static func _local(root: Node3D, probe: GroundProbe, p: Vector2) -> Vector3:
	var c: Vector2 = root.get_meta("life_center")
	return Vector3(-(p.x - c.x), probe.height(p.x, p.y) - 0.03, p.y)

# Places model `key` at route point `p`, its front (-Z) toward `face`; an optional solid box.
static func _put(root: Node3D, probe: GroundProbe, key: String, p: Vector2, face: Vector2, size: Vector3, center: Vector3) -> Node3D:
	var pos := _local(root, probe, p)
	var dir := Vector3(-face.x, 0, face.y)                 # route (s, z) -> local (-s, z)
	var basis := Basis.looking_at(dir, Vector3.UP) if dir.length() > 0.01 else Basis.IDENTITY
	var m := HDProps.place(root, key, Transform3D(basis, pos), key.to_pascal_case())
	if m == null:
		return null
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = VIS if key != "statue_horse" else 420.0
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	if size == Vector3.ZERO:
		# Playground pieces: their mesh bounds.
		var b := HDProps.local_aabb(m)
		bs.size = b.size
		cs.position = b.get_center()
	else:
		bs.size = size
		cs.position = center
	cs.shape = bs
	body.add_child(cs)
	m.add_child(body)
	return m

# Nothing solid (houses, walls, trees with bodies) in a box `size` round route point p.
static func _clear(root: Node3D, probe: GroundProbe, p: Vector2, size: Vector3, yaw: float) -> bool:
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	q.shape = bs
	q.collide_with_areas = false
	var local := _local(root, probe, p) + Vector3(0, size.y * 0.5 + 0.3, 0)
	q.transform = root.global_transform * Transform3D(Basis(Vector3.UP, -yaw), local)
	return space.intersect_shape(q, 1).is_empty()
