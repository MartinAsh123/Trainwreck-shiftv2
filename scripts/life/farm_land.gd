class_name FarmLand
extends RefCounted
## The fields and orchards of the valley, in route space. Laid out once (deterministic) round the
## villages and along the roads, on open, fairly level land: never in the forest, on a road, in a
## village, in a station yard or on the track bed. Each field is a rectangle (centre, furrow
## direction, length, width) ploughed or in stubble under the snow, some fenced along one side,
## some with a haystack or two. Orchards are rows of pruned apple trees near the villages.
## Farmland is cleared land: the scenery grows no trees where covers() is true.

const MAX_Z := 560.0

static var _fields: Array = []      # {c, u, L, W, stubble, fence, stacks: [[Vector2, kind, yaw]], s_min, s_max}
static var _orchards: Array = []    # {c, u, L, W, trees: [[Vector2, yaw, scale]], s_min, s_max}
static var _terrain: Terrain

static func ensure() -> void:
	if _terrain != null:
		return
	_terrain = Terrain.new()
	RoadNetwork.ensure()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var places: Array = RoadNetwork.places()
	# Orchards first (they want the land right by the villages).
	for p: Dictionary in places:
		var n := 2 if p.size >= 10 else 1
		var made := 0
		for k in 10:
			if made >= n:
				break
			var ang := rng.randf() * TAU
			var c: Vector2 = Vector2(p.s, p.z) + Vector2.from_angle(ang) * float(p.r) * rng.randf_range(0.95, 1.25)
			var u: Vector2 = (p.lane as Vector2).rotated(rng.randf_range(-0.2, 0.2))
			var nx := rng.randi_range(5, 9)
			var ny := rng.randi_range(3, 6)
			var L := nx * 7.5
			var W := ny * 7.0
			if _fits(c, u, L, W, 0.6, 0.8):
				var o := {"c": c, "u": u, "L": L, "W": W, "trees": []}
				var v := Vector2(-u.y, u.x)
				for i in nx:
					for j in ny:
						if rng.randf() < 0.08:
							continue        # a gap where a tree died
						var q := c + u * ((i - (nx - 1) * 0.5) * 7.5 + rng.randf_range(-0.6, 0.6)) \
								+ v * ((j - (ny - 1) * 0.5) * 7.0 + rng.randf_range(-0.6, 0.6))
						o.trees.append([q, rng.randf() * TAU, rng.randf_range(0.8, 1.15)])
				_span(o)
				_orchards.append(o)
				made += 1
	# Fields round each settlement.
	for p: Dictionary in places:
		var want := 4 + int(p.size / 3)
		var made := 0
		for k in want * 6:
			if made >= want:
				break
			var ang := rng.randf() * TAU
			var dist: float = float(p.r) * 1.2 + rng.randf_range(25.0, 190.0)
			var c: Vector2 = Vector2(p.s, p.z) + Vector2.from_angle(ang) * dist
			var u := Vector2.from_angle(rng.randf_range(-0.35, 0.35) + (PI * 0.5 if rng.randf() < 0.3 else 0.0))
			if _try_field(rng, c, u, rng.randf_range(70.0, 170.0), rng.randf_range(40.0, 100.0)):
				made += 1
	# Strips along the roads between them.
	for r: Dictionary in RoadNetwork.roads():
		var total := RoadNetwork.length_of(r)
		var t := rng.randf_range(60.0, 160.0)
		while t < total - 60.0:
			var pd: Array = RoadNetwork.point_at(r, t)
			var pos: Vector2 = pd[0]
			var dir: Vector2 = pd[1]
			var left := Vector2(-dir.y, dir.x)
			for sg: float in [-1.0, 1.0]:
				if rng.randf() < 0.7:
					var W := rng.randf_range(40.0, 90.0)
					var c := pos + left * sg * (RoadNetwork.WIDTH * 0.5 + 5.0 + W * 0.5)
					var tilt := rng.randf_range(-0.08, 0.08)
					_try_field(rng, c, dir.rotated(tilt), rng.randf_range(80.0, 180.0), W, -left * sg)
			t += rng.randf_range(110.0, 210.0)

static func fields() -> Array:
	ensure()
	return _fields

static func orchards() -> Array:
	ensure()
	return _orchards

## True when (s, z) lies in a field or orchard (with `margin` metres round it).
static func covers(s: float, z: float, margin: float = 2.0) -> bool:
	ensure()
	for list: Array in [_fields, _orchards]:
		for f: Dictionary in list:
			if s < float(f.s_min) - margin or s > float(f.s_max) + margin:
				continue
			if _inside(f, Vector2(s, z), margin):
				return true
	return false

static func _inside(f: Dictionary, p: Vector2, margin: float) -> bool:
	var u: Vector2 = f.u
	var d: Vector2 = p - (f.c as Vector2)
	return absf(d.dot(u)) <= float(f.L) * 0.5 + margin and absf(d.dot(Vector2(-u.y, u.x))) <= float(f.W) * 0.5 + margin

static func _span(f: Dictionary) -> void:
	var u: Vector2 = f.u
	var v := Vector2(-u.y, u.x)
	var ext := absf(u.x) * float(f.L) * 0.5 + absf(v.x) * float(f.W) * 0.5
	f["s_min"] = (f.c as Vector2).x - ext
	f["s_max"] = (f.c as Vector2).x + ext

static func _try_field(rng: RandomNumberGenerator, c: Vector2, u: Vector2, L: float, W: float, road_side := Vector2.ZERO) -> bool:
	if not _fits(c, u, L, W, 0.6):
		return false
	var v := Vector2(-u.y, u.x)
	var f := {"c": c, "u": u, "L": L, "W": W, "stubble": rng.randf() < 0.35, "fence": "", "stacks": []}
	# A fence along the side by the road (or a random long side), on some fields.
	if rng.randf() < 0.4:
		var side := road_side if road_side != Vector2.ZERO else v * (1.0 if rng.randf() < 0.5 else -1.0)
		f.fence = "+v" if side.dot(v) > 0.0 else "-v"
	# A haystack or two, in from the edge.
	if rng.randf() < 0.6:
		for k in (1 if rng.randf() < 0.6 else 2):
			var q := c + u * rng.randf_range(-L * 0.35, L * 0.35) + v * rng.randf_range(-W * 0.3, W * 0.3)
			f.stacks.append([q, "haystack_cone" if rng.randf() < 0.65 else "haystack_loaf", rng.randf() * TAU])
	_span(f)
	_fields.append(f)
	return true

# Open, level, clear land for a rectangle (checked on a grid of sample points).
static func _fits(c: Vector2, u: Vector2, L: float, W: float, max_forest: float, place_k := 1.05) -> bool:
	var v := Vector2(-u.y, u.x)
	var hmin := INF
	var hmax := -INF
	var corners: Array[Vector2] = []
	for i in 6:
		for j in 5:
			var p := c + u * (L * (i / 5.0 - 0.5)) + v * (W * (j / 4.0 - 0.5))
			var az := absf(p.y)
			if az < 24.0 or az > MAX_Z:
				return false
			if _terrain.forest(p.x, p.y) > max_forest:
				return false
			if RoadNetwork.near_road(p.x, p.y, 2.0):
				return false
			var st := RouteData.station_at(p.x)
			if not st.is_empty() and az < Terrain.STATION_FLAT_Z + 50.0:
				return false
			for pl: Dictionary in RoadNetwork.places():
				if p.distance_to(Vector2(pl.s, pl.z)) < float(pl.r) * place_k:
					return false
			var h := _terrain.natural(p.x, p.y)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			if (i == 0 or i == 5) and (j == 0 or j == 4):
				corners.append(p)
	if hmax - hmin > 2.0 + 0.07 * maxf(L, W):
		return false
	# No overlap with what is laid out already.
	for list: Array in [_fields, _orchards]:
		for f: Dictionary in list:
			if (f.c as Vector2).distance_to(c) > (Vector2(L, W).length() + Vector2(f.L, f.W).length()) * 0.5 + 4.0:
				continue
			if _inside(f, c, 4.0):
				return false
			for p in corners:
				if _inside(f, p, 4.0):
					return false
			var fu: Vector2 = f.u
			var fv := Vector2(-fu.y, fu.x)
			for a: float in [-0.5, 0.5]:
				for b: float in [-0.5, 0.5]:
					var q: Vector2 = (f.c as Vector2) + fu * (float(f.L) * a) + fv * (float(f.W) * b)
					if _inside({"c": c, "u": u, "L": L, "W": W}, q, 4.0):
						return false
	return true
